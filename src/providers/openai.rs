use async_trait::async_trait;
use reqwest::Client;
use serde_json::json;
use std::env;
use tracing::{debug, error};

use crate::error::{ZekeError, ZekeResult};
use super::{ProviderClient, ChatRequest, ChatResponse, Provider, Usage};

pub struct OpenAIClient {
    client: Client,
    api_key: String,
    base_url: String,
}

impl OpenAIClient {
    pub fn new() -> ZekeResult<Self> {
        let api_key = env::var("OPENAI_API_KEY")
            .map_err(|_| ZekeError::provider("OPENAI_API_KEY environment variable not set"))?;

        Ok(Self {
            client: Client::new(),
            api_key,
            base_url: "https://api.openai.com".to_string(),
        })
    }

    pub fn with_api_key(api_key: String) -> Self {
        Self {
            client: Client::new(),
            api_key,
            base_url: "https://api.openai.com".to_string(),
        }
    }
}

#[async_trait]
impl ProviderClient for OpenAIClient {
    async fn chat_completion(&self, request: &ChatRequest) -> ZekeResult<ChatResponse> {
        let url = format!("{}/v1/chat/completions", self.base_url);

        let payload = json!({
            "model": request.model.as_deref().unwrap_or(self.get_default_model()),
            "messages": request.messages,
            "temperature": request.temperature.unwrap_or(0.7),
            "max_tokens": request.max_tokens.unwrap_or(2048),
            "stream": request.stream.unwrap_or(false),
        });

        debug!("Sending request to OpenAI: {}", url);

        let response = self.client
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("Content-Type", "application/json")
            .json(&payload)
            .send()
            .await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            error!("OpenAI API error: {}", error_text);
            return Err(ZekeError::provider(format!("OpenAI API error: {}", error_text)));
        }

        let response_json: serde_json::Value = response.json().await?;

        let content = response_json["choices"][0]["message"]["content"]
            .as_str()
            .unwrap_or("")
            .to_string();

        let model = response_json["model"]
            .as_str()
            .unwrap_or(self.get_default_model())
            .to_string();

        let usage = if let Some(usage_data) = response_json.get("usage") {
            Some(Usage {
                prompt_tokens: usage_data["prompt_tokens"].as_u64().unwrap_or(0) as u32,
                completion_tokens: usage_data["completion_tokens"].as_u64().unwrap_or(0) as u32,
                total_tokens: usage_data["total_tokens"].as_u64().unwrap_or(0) as u32,
            })
        } else {
            None
        };

        Ok(ChatResponse {
            content,
            model,
            provider: Provider::OpenAI,
            usage,
        })
    }

    async fn health_check(&self) -> ZekeResult<bool> {
        let url = format!("{}/v1/models", self.base_url);

        match self.client
            .get(&url)
            .header("Authorization", format!("Bearer {}", self.api_key))
            .send()
            .await
        {
            Ok(response) => Ok(response.status().is_success()),
            Err(_) => Ok(false),
        }
    }

    fn get_provider(&self) -> Provider {
        Provider::OpenAI
    }

    fn get_default_model(&self) -> &str {
        "gpt-4o"
    }
}