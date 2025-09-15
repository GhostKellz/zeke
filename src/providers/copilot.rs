// GitHub Copilot provider implementation - placeholder
use async_trait::async_trait;
use crate::error::ZekeResult;
use super::{ProviderClient, ChatRequest, ChatResponse, Provider};

pub struct CopilotClient;

impl CopilotClient {
    pub fn new() -> ZekeResult<Self> {
        Ok(Self)
    }
}

#[async_trait]
impl ProviderClient for CopilotClient {
    async fn chat_completion(&self, _request: &ChatRequest) -> ZekeResult<ChatResponse> {
        todo!("Implement Copilot chat completion")
    }

    async fn health_check(&self) -> ZekeResult<bool> {
        Ok(false)
    }

    fn get_provider(&self) -> Provider {
        Provider::Copilot
    }

    fn get_default_model(&self) -> &str {
        "copilot-codex"
    }
}