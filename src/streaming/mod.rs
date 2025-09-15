use crate::error::ZekeResult;
use crate::providers::{ChatRequest, ChatResponse, Provider, ChatMessage};
use async_stream::stream;
use futures::Stream;
use serde::{Deserialize, Serialize};
use std::pin::Pin;

#[derive(Debug, Serialize, Deserialize)]
pub struct StreamedResponse {
    pub delta: String,
    pub model: String,
    pub provider: Provider,
    pub finished: bool,
}

pub type ChatStream = Pin<Box<dyn Stream<Item = ZekeResult<StreamedResponse>> + Send>>;

pub struct StreamManager;

impl StreamManager {
    pub fn new() -> Self {
        Self
    }

    pub async fn create_chat_stream(
        &self,
        request: &ChatRequest,
        provider: Provider,
    ) -> ZekeResult<ChatStream> {
        let request_clone = request.clone();
        let provider_clone = provider;

        // Get the full response first to avoid lifetime issues
        let full_response = self.get_full_response(&request_clone, provider_clone).await?;

        let stream = stream! {
            // Simulate streaming by chunking the response
            let words: Vec<&str> = full_response.content.split_whitespace().collect();
            let chunk_size = 3; // Stream 3 words at a time

            for chunk in words.chunks(chunk_size) {
                let delta = chunk.join(" ");
                if !delta.is_empty() {
                    yield Ok(StreamedResponse {
                        delta: delta + " ",
                        model: full_response.model.clone(),
                        provider: full_response.provider,
                        finished: false,
                    });
                    // Small delay to simulate real streaming
                    tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
                }
            }

            // Send final chunk to indicate completion
            yield Ok(StreamedResponse {
                delta: "".to_string(),
                model: full_response.model.clone(),
                provider: full_response.provider,
                finished: true,
            });
        };

        Ok(Box::pin(stream))
    }

    // Helper method to get full response for simulation
    // In a real implementation, providers would have native streaming support
    async fn get_full_response(&self, request: &ChatRequest, provider: Provider) -> ZekeResult<ChatResponse> {
        // Simulate a response based on the provider
        let content = match provider {
            Provider::OpenAI => "This is a simulated OpenAI streaming response with multiple words to demonstrate the streaming capability.",
            Provider::Claude => "This is a simulated Claude streaming response showcasing the real-time text generation feature.",
            Provider::GhostLLM => "This is a simulated GhostLLM streaming response demonstrating high-performance GPU inference capabilities.",
            Provider::Ollama => "This is a simulated Ollama streaming response from your local model running on this machine.",
            Provider::Copilot => "This is a simulated GitHub Copilot streaming response for code completion and assistance.",
            Provider::DeepSeek => "This is a simulated DeepSeek streaming response demonstrating advanced reasoning and code generation capabilities.",
        };

        Ok(ChatResponse {
            content: content.to_string(),
            model: request.model.clone().unwrap_or_else(|| "simulated-model".to_string()),
            provider,
            usage: None,
        })
    }

    pub async fn start_stream(&self, _provider: &str) -> ZekeResult<()> {
        Ok(())
    }
}