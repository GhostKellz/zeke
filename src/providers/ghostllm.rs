use async_trait::async_trait;
use reqwest::Client;
use serde_json::json;
use std::env;
use tracing::{debug, error};

use crate::error::{ZekeError, ZekeResult};
use super::{ProviderClient, ChatRequest, ChatResponse, Provider, Usage};

pub struct GhostLLMClient {
    client: Client,
    base_url: String,
    api_key: Option<String>,
}

impl GhostLLMClient {
    pub fn new() -> ZekeResult<Self> {
        let base_url = env::var("GHOSTLLM_URL")
            .unwrap_or_else(|_| "http://localhost:8080".to_string());

        let api_key = env::var("GHOSTLLM_API_KEY").ok();

        Ok(Self {
            client: Client::new(),
            base_url,
            api_key,
        })
    }

    pub fn with_config(base_url: String, api_key: Option<String>) -> Self {
        Self {
            client: Client::new(),
            base_url,
            api_key,
        }
    }
}

#[async_trait]
impl ProviderClient for GhostLLMClient {
    async fn chat_completion(&self, request: &ChatRequest) -> ZekeResult<ChatResponse> {
        let url = format!("{}/v1/chat/completions", self.base_url);

        let mut headers = reqwest::header::HeaderMap::new();
        headers.insert(
            reqwest::header::CONTENT_TYPE,
            "application/json".parse().unwrap(),
        );

        if let Some(api_key) = &self.api_key {
            headers.insert(
                reqwest::header::AUTHORIZATION,
                format!("Bearer {}", api_key).parse().unwrap(),
            );
        }

        let payload = json!({
            "model": request.model.as_deref().unwrap_or(self.get_default_model()),
            "messages": request.messages,
            "temperature": request.temperature.unwrap_or(0.7),
            "max_tokens": request.max_tokens.unwrap_or(2048),
            "stream": request.stream.unwrap_or(false),
        });

        debug!("Sending request to GhostLLM: {}", url);

        let response = self.client
            .post(&url)
            .headers(headers)
            .json(&payload)
            .send()
            .await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            error!("GhostLLM API error: {}", error_text);
            return Err(ZekeError::provider(format!("GhostLLM API error: {}", error_text)));
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
            provider: Provider::GhostLLM,
            usage,
        })
    }

    async fn health_check(&self) -> ZekeResult<bool> {
        let url = format!("{}/health", self.base_url);

        match self.client.get(&url).send().await {
            Ok(response) => Ok(response.status().is_success()),
            Err(_) => Ok(false),
        }
    }

    fn get_provider(&self) -> Provider {
        Provider::GhostLLM
    }

    fn get_default_model(&self) -> &str {
        "ghostllm-default"
    }
}