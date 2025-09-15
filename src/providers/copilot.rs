use async_trait::async_trait;
use reqwest::Client;
use serde_json::json;
use std::time::Duration;
use tokio::sync::RwLock;
use tracing::{debug, error, warn, info};

use crate::auth::{AuthToken, AuthProvider};
use crate::auth::github::GitHubAuthProvider;
use crate::error::{ZekeError, ZekeResult};
use super::{ProviderClient, ChatRequest, ChatResponse, Provider, Usage};

pub struct CopilotClient {
    client: Client,
    auth_provider: GitHubAuthProvider,
    auth_token: RwLock<Option<AuthToken>>,
}

impl CopilotClient {
    pub fn new() -> ZekeResult<Self> {
        Ok(Self {
            client: Client::builder()
                .timeout(Duration::from_secs(30))
                .user_agent("Zeke/0.3.0")
                .build()
                .unwrap_or_else(|_| Client::new()),
            auth_provider: GitHubAuthProvider::new(),
            auth_token: RwLock::new(None),
        })
    }

    pub async fn authenticate(&self) -> ZekeResult<()> {
        info!("Starting GitHub authentication for Copilot access...");

        let device_flow = self.auth_provider.start_device_flow().await?;

        println!("\n🔐 GitHub Authentication Required");
        println!("   Please visit: {}", device_flow.verification_uri);
        println!("   Enter code: {}", device_flow.user_code);

        if let Some(complete_uri) = &device_flow.verification_uri_complete {
            println!("   Or click: {}", complete_uri);
        }

        println!("\n   Waiting for authorization...");

        let poll_interval = Duration::from_secs(device_flow.interval);
        let max_attempts = (device_flow.expires_in / device_flow.interval) as usize;

        for attempt in 0..max_attempts {
            tokio::time::sleep(poll_interval).await;

            match self.auth_provider.poll_for_token(&device_flow.device_code).await? {
                Some(token) => {
                    println!("✅ Authentication successful!");

                    let mut auth_token = self.auth_token.write().await;
                    *auth_token = Some(token);

                    return Ok(());
                }
                None => {
                    if attempt % 5 == 0 && attempt > 0 {
                        println!("   Still waiting... ({}/{})", attempt + 1, max_attempts);
                    }
                    continue;
                }
            }
        }

        Err(ZekeError::auth("Authentication timeout. Please try again."))
    }

    async fn get_valid_token(&self) -> ZekeResult<String> {
        let token_guard = self.auth_token.read().await;

        match token_guard.as_ref() {
            Some(token) => {
                if token.is_expired() {
                    drop(token_guard);
                    return Err(ZekeError::auth("Token expired. Please re-authenticate."));
                }

                if token.needs_refresh() {
                    if let Some(refresh_token) = token.refresh_token.clone() {
                        drop(token_guard);

                        // Try to refresh the token
                        match self.auth_provider.refresh_token(&refresh_token).await {
                            Ok(new_token) => {
                                let mut token_guard = self.auth_token.write().await;
                                let access_token = new_token.access_token.clone();
                                *token_guard = Some(new_token);
                                return Ok(access_token);
                            }
                            Err(e) => {
                                warn!("Token refresh failed: {}", e);
                                return Err(ZekeError::auth("Token refresh failed. Please re-authenticate."));
                            }
                        }
                    }
                }

                Ok(token.access_token.clone())
            }
            None => Err(ZekeError::auth("Not authenticated. Please call authenticate() first.")),
        }
    }

    async fn make_copilot_request(&self, request: &ChatRequest) -> ZekeResult<ChatResponse> {
        let token = self.get_valid_token().await?;
        let url = "https://api.githubcopilot.com/chat/completions";

        // Convert messages to Copilot format
        let messages: Vec<serde_json::Value> = request.messages
            .iter()
            .map(|msg| json!({
                "role": msg.role,
                "content": msg.content
            }))
            .collect();

        let payload = json!({
            "model": request.model.as_deref().unwrap_or(self.get_default_model()),
            "messages": messages,
            "temperature": request.temperature.unwrap_or(0.7),
            "max_tokens": request.max_tokens.unwrap_or(2048),
            "stream": request.stream.unwrap_or(false),
        });

        debug!("Sending request to GitHub Copilot: {}", url);

        let response = self.client
            .post(url)
            .header("Authorization", format!("Bearer {}", token))
            .header("Content-Type", "application/json")
            .header("Editor-Version", "vscode/1.85.0")
            .header("Editor-Plugin-Version", "copilot-chat/0.10.0")
            .json(&payload)
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());

            if status.as_u16() == 401 {
                return Err(ZekeError::auth("Copilot access denied. Please check your subscription and re-authenticate."));
            }

            error!("GitHub Copilot API error ({}): {}", status, error_text);
            return Err(ZekeError::provider(format!("GitHub Copilot API error: {}", error_text)));
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
            provider: Provider::Copilot,
            usage,
        })
    }
}

#[async_trait]
impl ProviderClient for CopilotClient {
    async fn chat_completion(&self, request: &ChatRequest) -> ZekeResult<ChatResponse> {
        // Check if we're authenticated
        {
            let token_guard = self.auth_token.read().await;
            if token_guard.is_none() {
                drop(token_guard);
                return Err(ZekeError::auth("GitHub Copilot not authenticated. Please authenticate first."));
            }
        }

        self.make_copilot_request(request).await
    }

    async fn health_check(&self) -> ZekeResult<bool> {
        // Check if we have a valid token
        match self.get_valid_token().await {
            Ok(token) => {
                // Try a simple request to verify the token works
                let url = "https://api.github.com/user";

                match self.client
                    .get(url)
                    .header("Authorization", format!("Bearer {}", token))
                    .header("User-Agent", "Zeke/0.3.0")
                    .send()
                    .await
                {
                    Ok(response) => Ok(response.status().is_success()),
                    Err(_) => Ok(false),
                }
            }
            Err(_) => Ok(false),
        }
    }

    fn get_provider(&self) -> Provider {
        Provider::Copilot
    }

    fn get_default_model(&self) -> &str {
        "gpt-4"
    }
}