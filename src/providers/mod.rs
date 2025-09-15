use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tracing::{debug, warn};

use crate::error::{ZekeError, ZekeResult};

// Helper types for library integration
#[derive(Debug, Clone)]
pub struct ApiResponse {
    pub content: String,
    pub provider: String,
    pub model: String,
    pub usage: Option<ApiUsage>,
}

#[derive(Debug, Clone)]
pub struct ApiUsage {
    pub total_tokens: u32,
    pub prompt_tokens: u32,
    pub completion_tokens: u32,
}

#[derive(Debug, Clone)]
pub struct ApiProviderInfo {
    pub name: String,
    pub status: String,
    pub models: Vec<String>,
}

pub mod openai;
pub mod claude;
pub mod copilot;
pub mod ghostllm;
pub mod ollama;
pub mod deepseek;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Provider {
    OpenAI,
    Claude,
    Copilot,
    GhostLLM,
    Ollama,
    DeepSeek,
}

impl std::fmt::Display for Provider {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Provider::OpenAI => write!(f, "openai"),
            Provider::Claude => write!(f, "claude"),
            Provider::Copilot => write!(f, "copilot"),
            Provider::GhostLLM => write!(f, "ghostllm"),
            Provider::Ollama => write!(f, "ollama"),
            Provider::DeepSeek => write!(f, "deepseek"),
        }
    }
}

impl std::str::FromStr for Provider {
    type Err = ZekeError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "openai" => Ok(Provider::OpenAI),
            "claude" => Ok(Provider::Claude),
            "copilot" => Ok(Provider::Copilot),
            "ghostllm" => Ok(Provider::GhostLLM),
            "ollama" => Ok(Provider::Ollama),
            "deepseek" => Ok(Provider::DeepSeek),
            _ => Err(ZekeError::invalid_input(format!("Unknown provider: {}", s))),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Capability {
    ChatCompletion,
    CodeCompletion,
    CodeAnalysis,
    CodeExplanation,
    CodeRefactoring,
    TestGeneration,
    ProjectContext,
    CommitGeneration,
    SecurityScanning,
    Streaming,
}

#[derive(Debug, Clone)]
pub struct ProviderConfig {
    pub provider: Provider,
    pub priority: u8,
    pub capabilities: Vec<Capability>,
    pub max_requests_per_minute: u32,
    pub timeout: Duration,
    pub fallback_providers: Vec<Provider>,
}

impl ProviderConfig {
    pub fn has_capability(&self, capability: &Capability) -> bool {
        self.capabilities.contains(capability)
    }
}

#[derive(Debug, Clone)]
pub struct ProviderHealth {
    pub provider: Provider,
    pub is_healthy: bool,
    pub last_check: Instant,
    pub response_time: Duration,
    pub error_rate: f32,
}

impl ProviderHealth {
    pub fn new(provider: Provider) -> Self {
        Self {
            provider,
            is_healthy: true,
            last_check: Instant::now(),
            response_time: Duration::from_millis(0),
            error_rate: 0.0,
        }
    }

    pub fn is_stale(&self) -> bool {
        self.last_check.elapsed() > Duration::from_secs(300) // 5 minutes
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub role: String,
    pub content: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatRequest {
    pub messages: Vec<ChatMessage>,
    pub model: Option<String>,
    pub temperature: Option<f32>,
    pub max_tokens: Option<u32>,
    pub stream: Option<bool>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ChatResponse {
    pub content: String,
    pub model: String,
    pub provider: Provider,
    pub usage: Option<Usage>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Usage {
    pub prompt_tokens: u32,
    pub completion_tokens: u32,
    pub total_tokens: u32,
}

#[async_trait]
pub trait ProviderClient: Send + Sync {
    async fn chat_completion(&self, request: &ChatRequest) -> ZekeResult<ChatResponse>;
    async fn health_check(&self) -> ZekeResult<bool>;
    fn get_provider(&self) -> Provider;
    fn get_default_model(&self) -> &str;
}

pub struct ProviderManager {
    providers: RwLock<HashMap<Provider, Arc<dyn ProviderClient>>>,
    configs: HashMap<Provider, ProviderConfig>,
    health: RwLock<HashMap<Provider, ProviderHealth>>,
    current_provider: RwLock<Provider>,
}

impl ProviderManager {
    pub fn new() -> Self {
        let configs = Self::create_default_configs();

        Self {
            providers: RwLock::new(HashMap::new()),
            configs,
            health: RwLock::new(HashMap::new()),
            current_provider: RwLock::new(Provider::GhostLLM), // Default to GhostLLM
        }
    }

    pub async fn initialize_default_providers(&self) -> ZekeResult<()> {
        // Try to initialize GhostLLM (highest priority)
        if let Ok(client) = ghostllm::GhostLLMClient::new() {
            self.register_provider(Arc::new(client)).await?;
        }

        // Try to initialize OpenAI
        if let Ok(client) = openai::OpenAIClient::new() {
            self.register_provider(Arc::new(client)).await?;
        }

        // Try to initialize Claude
        if let Ok(client) = claude::ClaudeClient::new() {
            self.register_provider(Arc::new(client)).await?;
        }

        // Try to initialize Ollama
        if let Ok(client) = ollama::OllamaClient::new() {
            self.register_provider(Arc::new(client)).await?;
        }

        // Try to initialize DeepSeek
        if let Ok(client) = deepseek::DeepSeekClient::new() {
            self.register_provider(Arc::new(client)).await?;
        }

        // GitHub Copilot would require more complex OAuth setup, skip for now

        Ok(())
    }

    fn create_default_configs() -> HashMap<Provider, ProviderConfig> {
        let mut configs = HashMap::new();

        // OpenAI configuration
        configs.insert(Provider::OpenAI, ProviderConfig {
            provider: Provider::OpenAI,
            priority: 8,
            capabilities: vec![
                Capability::ChatCompletion,
                Capability::CodeCompletion,
                Capability::CodeExplanation,
                Capability::Streaming,
            ],
            max_requests_per_minute: 60,
            timeout: Duration::from_secs(30),
            fallback_providers: vec![Provider::Claude, Provider::Ollama],
        });

        // Claude configuration
        configs.insert(Provider::Claude, ProviderConfig {
            provider: Provider::Claude,
            priority: 9,
            capabilities: vec![
                Capability::ChatCompletion,
                Capability::CodeCompletion,
                Capability::CodeAnalysis,
                Capability::CodeExplanation,
                Capability::Streaming,
            ],
            max_requests_per_minute: 50,
            timeout: Duration::from_secs(45),
            fallback_providers: vec![Provider::OpenAI, Provider::Ollama],
        });

        // GitHub Copilot configuration
        configs.insert(Provider::Copilot, ProviderConfig {
            provider: Provider::Copilot,
            priority: 7,
            capabilities: vec![
                Capability::CodeCompletion,
                Capability::CodeExplanation,
            ],
            max_requests_per_minute: 100,
            timeout: Duration::from_secs(15),
            fallback_providers: vec![Provider::OpenAI, Provider::Claude],
        });

        // GhostLLM configuration (highest priority)
        configs.insert(Provider::GhostLLM, ProviderConfig {
            provider: Provider::GhostLLM,
            priority: 10,
            capabilities: vec![
                Capability::ChatCompletion,
                Capability::CodeCompletion,
                Capability::CodeAnalysis,
                Capability::CodeExplanation,
                Capability::CodeRefactoring,
                Capability::TestGeneration,
                Capability::ProjectContext,
                Capability::CommitGeneration,
                Capability::SecurityScanning,
                Capability::Streaming,
            ],
            max_requests_per_minute: 200,
            timeout: Duration::from_secs(5), // Fast GPU responses
            fallback_providers: vec![Provider::Claude, Provider::OpenAI],
        });

        // Ollama configuration (local fallback)
        configs.insert(Provider::Ollama, ProviderConfig {
            provider: Provider::Ollama,
            priority: 5,
            capabilities: vec![
                Capability::ChatCompletion,
                Capability::CodeCompletion,
                Capability::CodeExplanation,
            ],
            max_requests_per_minute: 1000, // Local, no real limit
            timeout: Duration::from_secs(60), // Local inference can be slow
            fallback_providers: vec![],
        });

        // DeepSeek configuration
        configs.insert(Provider::DeepSeek, ProviderConfig {
            provider: Provider::DeepSeek,
            priority: 6,
            capabilities: vec![
                Capability::ChatCompletion,
                Capability::CodeCompletion,
                Capability::CodeExplanation,
                Capability::CodeRefactoring,
                Capability::TestGeneration,
            ],
            max_requests_per_minute: 60,
            timeout: Duration::from_secs(30),
            fallback_providers: vec![Provider::OpenAI, Provider::Claude],
        });

        configs
    }

    pub async fn register_provider(&self, client: Arc<dyn ProviderClient>) -> ZekeResult<()> {
        let provider = client.get_provider();
        debug!("Registering provider: {}", provider);

        let mut providers = self.providers.write().await;
        providers.insert(provider, client);

        let mut health = self.health.write().await;
        health.insert(provider, ProviderHealth::new(provider));

        Ok(())
    }

    pub async fn select_best_provider(&self, capability: &Capability) -> ZekeResult<Provider> {
        let health = self.health.read().await;
        let mut best_provider: Option<Provider> = None;
        let mut best_score: f32 = 0.0;

        for (provider, config) in &self.configs {
            // Check if provider has the required capability
            if !config.has_capability(capability) {
                continue;
            }

            // Calculate provider score
            let mut score = config.priority as f32;

            // Factor in health status
            if let Some(provider_health) = health.get(provider) {
                if !provider_health.is_healthy {
                    score *= 0.1; // Heavily penalize unhealthy providers
                }

                // Factor in response time (lower is better)
                if !provider_health.response_time.is_zero() {
                    let response_factor = 1000.0 / provider_health.response_time.as_millis() as f32;
                    score *= response_factor;
                }

                // Factor in error rate (lower is better)
                score *= 1.0 - provider_health.error_rate;
            }

            if score > best_score {
                best_score = score;
                best_provider = Some(*provider);
            }
        }

        best_provider.ok_or_else(|| ZekeError::provider("No suitable provider found"))
    }

    pub async fn select_providers_with_fallback(&self, capability: &Capability) -> ZekeResult<Vec<Provider>> {
        let mut providers = Vec::new();

        // Get the best provider
        if let Ok(primary) = self.select_best_provider(capability).await {
            providers.push(primary);

            // Add fallback providers
            if let Some(config) = self.configs.get(&primary) {
                for fallback in &config.fallback_providers {
                    // Only add fallback if it has the required capability
                    if let Some(fallback_config) = self.configs.get(fallback) {
                        if fallback_config.has_capability(capability) {
                            providers.push(*fallback);
                        }
                    }
                }
            }
        }

        if providers.is_empty() {
            return Err(ZekeError::provider("No providers available for capability"));
        }

        Ok(providers)
    }

    pub async fn chat_completion(&self, request: &ChatRequest) -> ZekeResult<ChatResponse> {
        let providers = self.select_providers_with_fallback(&Capability::ChatCompletion).await?;

        for provider in providers {
            if let Some(client) = self.get_provider_client_ref(provider).await {
                let start_time = std::time::Instant::now();

                match client.chat_completion(request).await {
                    Ok(response) => {
                        let duration = start_time.elapsed();
                        self.update_health(provider, true, duration).await;
                        return Ok(response);
                    }
                    Err(e) => {
                        let duration = start_time.elapsed();
                        self.update_health(provider, false, duration).await;
                        warn!("Provider {} failed: {}", provider, e);
                        continue;
                    }
                }
            }
        }

        Err(ZekeError::provider("All providers failed"))
    }

    async fn get_provider_client(&self, provider: Provider) -> ZekeResult<bool> {
        let providers = self.providers.read().await;
        Ok(providers.contains_key(&provider))
        // Note: This is a simplified version for compilation - trait object lifetime issues need proper handling
    }

    async fn get_provider_client_ref(&self, provider: Provider) -> Option<Arc<dyn ProviderClient>> {
        let providers = self.providers.read().await;
        providers.get(&provider).cloned()
    }

    async fn update_health(&self, provider: Provider, is_healthy: bool, response_time: Duration) {
        let mut health = self.health.write().await;

        if let Some(provider_health) = health.get_mut(&provider) {
            provider_health.is_healthy = is_healthy;
            provider_health.last_check = Instant::now();
            provider_health.response_time = response_time;

            // Update error rate with exponential moving average
            let error_value = if is_healthy { 0.0 } else { 1.0 };
            provider_health.error_rate = provider_health.error_rate * 0.9 + error_value * 0.1;
        }
    }

    pub async fn get_current_provider(&self) -> Provider {
        *self.current_provider.read().await
    }

    pub async fn set_current_provider(&self, provider: Provider) {
        let mut current = self.current_provider.write().await;
        *current = provider;
    }

    pub async fn list_providers(&self) -> Vec<Provider> {
        self.configs.keys().copied().collect()
    }

    pub async fn get_provider_status(&self) -> Vec<(Provider, ProviderHealth)> {
        let health = self.health.read().await;
        health.iter().map(|(p, h)| (*p, h.clone())).collect()
    }

    /// Simple ask method for direct provider interaction
    pub async fn ask(&self, provider: &str, question: &str, model: Option<&str>) -> ZekeResult<ApiResponse> {
        let provider_enum: Provider = provider.parse()?;

        let request = ChatRequest {
            messages: vec![ChatMessage {
                role: "user".to_string(),
                content: question.to_string(),
            }],
            model: model.map(|s| s.to_string()),
            temperature: Some(0.7),
            max_tokens: Some(2000),
            stream: Some(false),
        };

        let response = if let Some(client) = self.get_provider_client_ref(provider_enum).await {
            client.chat_completion(&request).await?
        } else {
            return Err(ZekeError::provider(format!("Provider '{}' not available", provider)));
        };

        Ok(ApiResponse {
            content: response.content,
            provider: response.provider.to_string(),
            model: response.model,
            usage: response.usage.map(|u| ApiUsage {
                total_tokens: u.total_tokens,
                prompt_tokens: u.prompt_tokens,
                completion_tokens: u.completion_tokens,
            }),
        })
    }

    /// List provider information for external use
    pub async fn list_provider_info(&self) -> ZekeResult<Vec<ApiProviderInfo>> {
        let providers = self.providers.read().await;
        let health = self.health.read().await;

        let mut provider_infos = Vec::new();

        for (provider, _client) in providers.iter() {
            let status = if let Some(provider_health) = health.get(provider) {
                if provider_health.is_healthy {
                    "healthy".to_string()
                } else {
                    "unhealthy".to_string()
                }
            } else {
                "unknown".to_string()
            };

            provider_infos.push(ApiProviderInfo {
                name: provider.to_string(),
                status,
                models: vec![], // TODO: Implement model listing per provider
            });
        }

        Ok(provider_infos)
    }
}