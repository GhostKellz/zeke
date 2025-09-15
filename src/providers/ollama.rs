use async_trait::async_trait;
use reqwest::Client;
use serde_json::json;
use std::env;
use tracing::{debug, error};

use crate::error::{ZekeError, ZekeResult};
use super::{ProviderClient, ChatRequest, ChatResponse, Provider, Usage};

pub struct OllamaClient {
    client: Client,
    base_url: String,
}

impl OllamaClient {
    pub fn new() -> ZekeResult<Self> {
        let base_url = env::var("OLLAMA_URL")
            .unwrap_or_else(|_| "http://localhost:11434".to_string());

        Ok(Self {
            client: Client::new(),
            base_url,
        })
    }

    pub fn with_base_url(base_url: String) -> Self {
        Self {
            client: Client::new(),
            base_url,
        }
    }
}

#[async_trait]
impl ProviderClient for OllamaClient {
    async fn chat_completion(&self, request: &ChatRequest) -> ZekeResult<ChatResponse> {
        let url = format!("{}/api/chat", self.base_url);

        let payload = json!({
            "model": request.model.as_deref().unwrap_or(self.get_default_model()),
            "messages": request.messages,
            "stream": false,
            "options": {
                "temperature": request.temperature.unwrap_or(0.7),
                "num_predict": request.max_tokens.unwrap_or(2048),
            }
        });

        debug!("Sending request to Ollama: {}", url);

        let response = self.client
            .post(&url)
            .header("Content-Type", "application/json")
            .json(&payload)
            .send()
            .await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            error!("Ollama API error: {}", error_text);
            return Err(ZekeError::provider(format!("Ollama API error: {}", error_text)));
        }

        let response_json: serde_json::Value = response.json().await?;

        let content = response_json["message"]["content"]
            .as_str()
            .unwrap_or("")
            .to_string();

        let model = response_json["model"]
            .as_str()
            .unwrap_or(self.get_default_model())
            .to_string();

        // Ollama doesn't provide detailed usage stats like OpenAI
        let usage = None;

        Ok(ChatResponse {
            content,
            model,
            provider: Provider::Ollama,
            usage,
        })
    }

    async fn health_check(&self) -> ZekeResult<bool> {
        let url = format!("{}/api/tags", self.base_url);

        match self.client.get(&url).send().await {
            Ok(response) => Ok(response.status().is_success()),
            Err(_) => Ok(false),
        }
    }

    fn get_provider(&self) -> Provider {
        Provider::Ollama
    }

    fn get_default_model(&self) -> &str {
        "llama3.2"
    }
}