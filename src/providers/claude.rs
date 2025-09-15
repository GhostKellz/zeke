use async_trait::async_trait;
use reqwest::Client;
use serde_json::json;
use std::env;
use tracing::{debug, error};

use crate::error::{ZekeError, ZekeResult};
use super::{ProviderClient, ChatRequest, ChatResponse, Provider, Usage, ChatMessage};

pub struct ClaudeClient {
    client: Client,
    api_key: String,
    base_url: String,
}

impl ClaudeClient {
    pub fn new() -> ZekeResult<Self> {
        let api_key = env::var("CLAUDE_API_KEY")
            .or_else(|_| env::var("ANTHROPIC_API_KEY"))
            .map_err(|_| ZekeError::provider("CLAUDE_API_KEY or ANTHROPIC_API_KEY environment variable not set"))?;

        Ok(Self {
            client: Client::new(),
            api_key,
            base_url: "https://api.anthropic.com".to_string(),
        })
    }

    pub fn with_api_key(api_key: String) -> Self {
        Self {
            client: Client::new(),
            api_key,
            base_url: "https://api.anthropic.com".to_string(),
        }
    }

    // Convert OpenAI-style messages to Claude format
    fn convert_messages(&self, messages: &[ChatMessage]) -> (String, Vec<serde_json::Value>) {
        let mut system_prompt = String::new();
        let mut claude_messages = Vec::new();

        for message in messages {
            match message.role.as_str() {
                "system" => {
                    if !system_prompt.is_empty() {
                        system_prompt.push('\n');
                    }
                    system_prompt.push_str(&message.content);
                }
                "user" | "assistant" => {
                    claude_messages.push(json!({
                        "role": message.role,
                        "content": message.content
                    }));
                }
                _ => {
                    // Convert other roles to user
                    claude_messages.push(json!({
                        "role": "user",
                        "content": message.content
                    }));
                }
            }
        }

        (system_prompt, claude_messages)
    }
}

#[async_trait]
impl ProviderClient for ClaudeClient {
    async fn chat_completion(&self, request: &ChatRequest) -> ZekeResult<ChatResponse> {
        let url = format!("{}/v1/messages", self.base_url);

        let (system_prompt, messages) = self.convert_messages(&request.messages);

        let mut payload = json!({
            "model": request.model.as_deref().unwrap_or(self.get_default_model()),
            "messages": messages,
            "max_tokens": request.max_tokens.unwrap_or(2048),
            "temperature": request.temperature.unwrap_or(0.7),
        });

        if !system_prompt.is_empty() {
            payload["system"] = json!(system_prompt);
        }

        debug!("Sending request to Claude: {}", url);

        let response = self.client
            .post(&url)
            .header("x-api-key", &self.api_key)
            .header("Content-Type", "application/json")
            .header("anthropic-version", "2023-06-01")
            .json(&payload)
            .send()
            .await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            error!("Claude API error: {}", error_text);
            return Err(ZekeError::provider(format!("Claude API error: {}", error_text)));
        }

        let response_json: serde_json::Value = response.json().await?;

        let content = response_json["content"][0]["text"]
            .as_str()
            .unwrap_or("")
            .to_string();

        let model = response_json["model"]
            .as_str()
            .unwrap_or(self.get_default_model())
            .to_string();

        let usage = if let Some(usage_data) = response_json.get("usage") {
            Some(Usage {
                prompt_tokens: usage_data["input_tokens"].as_u64().unwrap_or(0) as u32,
                completion_tokens: usage_data["output_tokens"].as_u64().unwrap_or(0) as u32,
                total_tokens: (usage_data["input_tokens"].as_u64().unwrap_or(0) +
                              usage_data["output_tokens"].as_u64().unwrap_or(0)) as u32,
            })
        } else {
            None
        };

        Ok(ChatResponse {
            content,
            model,
            provider: Provider::Claude,
            usage,
        })
    }

    async fn health_check(&self) -> ZekeResult<bool> {
        // Claude doesn't have a simple health endpoint, so we'll make a minimal request
        let url = format!("{}/v1/messages", self.base_url);

        let payload = json!({
            "model": self.get_default_model(),
            "messages": [{"role": "user", "content": "ping"}],
            "max_tokens": 1
        });

        match self.client
            .post(&url)
            .header("x-api-key", &self.api_key)
            .header("Content-Type", "application/json")
            .header("anthropic-version", "2023-06-01")
            .json(&payload)
            .send()
            .await
        {
            Ok(response) => Ok(response.status().is_success() || response.status().as_u16() == 400),
            Err(_) => Ok(false),
        }
    }

    fn get_provider(&self) -> Provider {
        Provider::Claude
    }

    fn get_default_model(&self) -> &str {
        "claude-3-5-sonnet-20241022"
    }
}