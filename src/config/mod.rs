// Configuration management with multiple auth methods
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use crate::error::ZekeResult;

#[derive(Debug, Serialize, Deserialize)]
pub struct ZekeConfig {
    pub default_provider: Option<String>,
    pub providers: HashMap<String, ProviderConfig>,
    pub auth: AuthConfig,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ProviderConfig {
    pub enabled: bool,
    pub api_key: Option<String>,
    pub base_url: Option<String>,
    pub model: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AuthConfig {
    pub google_oauth: Option<GoogleOAuthConfig>,
    pub github_token: Option<String>,
    pub openai_api_key: Option<String>,
    pub claude_api_key: Option<String>,
    pub gemini_api_key: Option<String>,
    pub ghostllm_config: Option<GhostLLMConfig>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct GoogleOAuthConfig {
    pub client_id: String,
    pub client_secret: String,
    pub refresh_token: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct GhostLLMConfig {
    pub url: String,
    pub api_key: Option<String>,
}

pub struct ConfigManager;

impl ConfigManager {
    pub fn new() -> Self {
        Self
    }

    pub async fn load_config(&self) -> ZekeResult<ZekeConfig> {
        // TODO: Load from config file
        Ok(ZekeConfig {
            default_provider: Some("ghostllm".to_string()),
            providers: HashMap::new(),
            auth: AuthConfig {
                google_oauth: None,
                github_token: std::env::var("GITHUB_TOKEN").ok(),
                openai_api_key: std::env::var("OPENAI_API_KEY").ok(),
                claude_api_key: std::env::var("CLAUDE_API_KEY").ok(),
                gemini_api_key: std::env::var("GEMINI_API_KEY").ok(),
                ghostllm_config: Some(GhostLLMConfig {
                    url: std::env::var("GHOSTLLM_URL").unwrap_or_else(|_| "http://localhost:8080".to_string()),
                    api_key: std::env::var("GHOSTLLM_API_KEY").ok(),
                }),
            },
        })
    }

    pub async fn save_config(&self, _config: &ZekeConfig) -> ZekeResult<()> {
        // TODO: Save to config file
        Ok(())
    }
}