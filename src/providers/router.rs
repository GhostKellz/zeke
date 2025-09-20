use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{debug, info, warn};

use crate::config::ZekeConfig;
use crate::error::{ZekeError, ZekeResult};
use crate::providers::{
    ChatRequest, ChatResponse, ProviderClient, Provider, ProviderManager
};

/// Provider connection mode - determines how Zeke connects to AI providers
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ProviderMode {
    /// Connect directly to individual providers (Claude API, OpenAI API, etc.)
    Direct,
    /// Connect via GhostLLM proxy (unified routing with consent system)
    GhostLLM,
    /// Automatic mode - prefer GhostLLM if available, fallback to direct
    Auto,
}

impl Default for ProviderMode {
    fn default() -> Self {
        ProviderMode::Auto
    }
}

impl std::str::FromStr for ProviderMode {
    type Err = ZekeError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "direct" => Ok(ProviderMode::Direct),
            "ghostllm" => Ok(ProviderMode::GhostLLM),
            "auto" => Ok(ProviderMode::Auto),
            _ => Err(ZekeError::invalid_input(format!("Unknown provider mode: {}", s))),
        }
    }
}

/// Enhanced configuration for provider routing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderRouterConfig {
    /// Primary connection mode
    pub mode: ProviderMode,
    /// GhostLLM configuration
    pub ghostllm: GhostLLMRouterConfig,
    /// Direct provider preferences
    pub direct: DirectProviderConfig,
    /// Consent and security settings
    pub security: SecurityConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GhostLLMRouterConfig {
    /// GhostLLM base URL
    pub base_url: String,
    /// Enable intelligent routing
    pub enable_routing: bool,
    /// Enable GhostWarden consent system
    pub enable_consent: bool,
    /// Session persistence across model swaps
    pub session_persistence: bool,
    /// Cost tracking and optimization
    pub cost_tracking: bool,
    /// Timeout for GhostLLM connection check
    pub health_check_timeout_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DirectProviderConfig {
    /// Preferred provider for direct connections
    pub preferred_provider: Option<Provider>,
    /// Fallback order when direct connections fail
    pub fallback_order: Vec<Provider>,
    /// Enable local model preference (Ollama)
    pub prefer_local: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityConfig {
    /// Auto-approve file read operations
    pub auto_approve_read: bool,
    /// Auto-approve file write operations
    pub auto_approve_write: bool,
    /// Require multi-factor authentication
    pub require_mfa: bool,
    /// Project scope for permissions
    pub project_scope: Option<String>,
}

impl Default for ProviderRouterConfig {
    fn default() -> Self {
        Self {
            mode: ProviderMode::Auto,
            ghostllm: GhostLLMRouterConfig {
                base_url: "http://localhost:8080/v1".to_string(),
                enable_routing: true,
                enable_consent: true,
                session_persistence: true,
                cost_tracking: true,
                health_check_timeout_ms: 5000,
            },
            direct: DirectProviderConfig {
                preferred_provider: None,
                fallback_order: vec![Provider::Claude, Provider::OpenAI, Provider::Ollama],
                prefer_local: true,
            },
            security: SecurityConfig {
                auto_approve_read: true,
                auto_approve_write: false,
                require_mfa: false,
                project_scope: Some("repo:current".to_string()),
            },
        }
    }
}

/// Provider router that abstracts between direct and GhostLLM connections
pub struct ProviderRouter {
    config: ProviderRouterConfig,
    provider_manager: Arc<ProviderManager>,
    ghostllm_client: Option<Arc<dyn ProviderClient>>,
    active_mode: ProviderMode,
}

impl ProviderRouter {
    /// Create a new provider router with configuration
    pub async fn new(config: ProviderRouterConfig) -> ZekeResult<Self> {
        let provider_manager = Arc::new(ProviderManager::new());

        // Initialize providers based on mode
        let mut router = Self {
            config: config.clone(),
            provider_manager,
            ghostllm_client: None,
            active_mode: ProviderMode::Direct, // Will be updated by detect_mode
        };

        router.initialize().await?;
        Ok(router)
    }

    /// Create router from Zeke configuration
    pub async fn from_zeke_config(zeke_config: &ZekeConfig) -> ZekeResult<Self> {
        let router_config = Self::extract_router_config(zeke_config);
        Self::new(router_config).await
    }

    /// Initialize the router and detect the best mode
    async fn initialize(&mut self) -> ZekeResult<()> {
        info!("🔄 Initializing provider router (mode: {:?})", self.config.mode);

        // Detect and set active mode
        self.active_mode = self.detect_active_mode().await;
        info!("✅ Active provider mode: {:?}", self.active_mode);

        match self.active_mode {
            ProviderMode::GhostLLM => {
                self.initialize_ghostllm_mode().await?;
            }
            ProviderMode::Direct => {
                self.initialize_direct_mode().await?;
            }
            ProviderMode::Auto => {
                // This shouldn't happen after detect_active_mode
                return Err(ZekeError::provider("Auto mode not resolved"));
            }
        }

        Ok(())
    }

    /// Detect which mode to use based on availability
    async fn detect_active_mode(&self) -> ProviderMode {
        match self.config.mode {
            ProviderMode::Direct => ProviderMode::Direct,
            ProviderMode::GhostLLM => ProviderMode::GhostLLM,
            ProviderMode::Auto => {
                // Try GhostLLM first, fallback to direct
                if self.check_ghostllm_availability().await {
                    ProviderMode::GhostLLM
                } else {
                    ProviderMode::Direct
                }
            }
        }
    }

    /// Check if GhostLLM is available
    async fn check_ghostllm_availability(&self) -> bool {
        debug!("🔍 Checking GhostLLM availability at {}", self.config.ghostllm.base_url);

        // Try to create a GhostLLM client and test connectivity
        match crate::providers::ghostllm::GhostLLMClient::with_config(
            &self.config.ghostllm.base_url
        ) {
            Ok(client) => {
                match tokio::time::timeout(
                    std::time::Duration::from_millis(self.config.ghostllm.health_check_timeout_ms),
                    client.health_check()
                ).await {
                    Ok(Ok(true)) => {
                        debug!("✅ GhostLLM is available");
                        true
                    }
                    Ok(Ok(false)) => {
                        debug!("❌ GhostLLM health check failed");
                        false
                    }
                    Ok(Err(e)) => {
                        debug!("❌ GhostLLM error: {}", e);
                        false
                    }
                    Err(_) => {
                        debug!("⏰ GhostLLM health check timeout");
                        false
                    }
                }
            }
            Err(e) => {
                debug!("❌ Failed to create GhostLLM client: {}", e);
                false
            }
        }
    }

    /// Initialize GhostLLM mode
    async fn initialize_ghostllm_mode(&mut self) -> ZekeResult<()> {
        info!("🚀 Initializing GhostLLM mode");

        let client = crate::providers::ghostllm::GhostLLMClient::with_config(
            &self.config.ghostllm.base_url
        )?;

        let client_arc = Arc::new(client);
        self.provider_manager.register_provider(client_arc.clone()).await?;
        self.ghostllm_client = Some(client_arc);

        info!("✅ GhostLLM mode initialized");
        Ok(())
    }

    /// Initialize direct mode with fallback providers
    async fn initialize_direct_mode(&mut self) -> ZekeResult<()> {
        info!("🚀 Initializing direct provider mode");

        // Initialize all available direct providers
        if let Err(e) = self.provider_manager.initialize_default_providers().await {
            warn!("⚠️  Some providers failed to initialize: {}", e);
        }

        // Check if we have at least one working provider
        let providers = self.provider_manager.list_providers().await;
        if providers.is_empty() {
            return Err(ZekeError::provider("No direct providers available"));
        }

        info!("✅ Direct mode initialized with {} providers", providers.len());
        Ok(())
    }

    /// Extract router configuration from Zeke config
    fn extract_router_config(zeke_config: &ZekeConfig) -> ProviderRouterConfig {
        let mut config = ProviderRouterConfig::default();

        // Set GhostLLM URL from config
        if let Some(ghostllm_config) = &zeke_config.auth.ghostllm_config {
            config.ghostllm.base_url = format!("{}/v1", ghostllm_config.url.trim_end_matches("/v1"));
        }

        // Determine mode based on default provider
        if let Some(default_provider) = &zeke_config.default_provider {
            config.mode = if default_provider == "ghostllm" {
                ProviderMode::GhostLLM
            } else {
                ProviderMode::Direct
            };
        }

        config
    }

    /// Get the current active mode
    pub fn get_active_mode(&self) -> ProviderMode {
        self.active_mode.clone()
    }

    /// Get the router configuration
    pub fn get_config(&self) -> &ProviderRouterConfig {
        &self.config
    }

    /// Force switch to a specific mode (if possible)
    pub async fn switch_mode(&mut self, mode: ProviderMode) -> ZekeResult<()> {
        info!("🔄 Switching provider mode to: {:?}", mode);

        match mode {
            ProviderMode::Auto => {
                return Err(ZekeError::invalid_input("Cannot switch to Auto mode explicitly"));
            }
            ProviderMode::GhostLLM => {
                if !self.check_ghostllm_availability().await {
                    return Err(ZekeError::provider("GhostLLM not available"));
                }
                self.initialize_ghostllm_mode().await?;
            }
            ProviderMode::Direct => {
                self.initialize_direct_mode().await?;
            }
        }

        self.active_mode = mode;
        info!("✅ Switched to mode: {:?}", self.active_mode);
        Ok(())
    }

    /// Route a chat completion request through the active mode
    pub async fn chat_completion(&self, request: &ChatRequest) -> ZekeResult<ChatResponse> {
        match self.active_mode {
            ProviderMode::GhostLLM => {
                if let Some(client) = &self.ghostllm_client {
                    client.chat_completion(request).await
                } else {
                    Err(ZekeError::provider("GhostLLM client not initialized"))
                }
            }
            ProviderMode::Direct => {
                self.provider_manager.chat_completion(request).await
            }
            ProviderMode::Auto => {
                // This shouldn't happen
                Err(ZekeError::provider("Auto mode not resolved"))
            }
        }
    }

    /// Get available providers based on current mode
    pub async fn list_available_providers(&self) -> Vec<Provider> {
        match self.active_mode {
            ProviderMode::GhostLLM => {
                // GhostLLM acts as a unified provider
                vec![Provider::GhostLLM]
            }
            ProviderMode::Direct => {
                self.provider_manager.list_providers().await
            }
            ProviderMode::Auto => {
                // This shouldn't happen
                vec![]
            }
        }
    }

    /// Get provider status information
    pub async fn get_provider_status(&self) -> ZekeResult<Vec<(Provider, bool)>> {
        match self.active_mode {
            ProviderMode::GhostLLM => {
                let is_healthy = if let Some(client) = &self.ghostllm_client {
                    client.health_check().await.unwrap_or(false)
                } else {
                    false
                };
                Ok(vec![(Provider::GhostLLM, is_healthy)])
            }
            ProviderMode::Direct => {
                let health_status = self.provider_manager.get_provider_status().await;
                Ok(health_status.into_iter().map(|(p, h)| (p, h.is_healthy)).collect())
            }
            ProviderMode::Auto => {
                Ok(vec![])
            }
        }
    }
}

/// Trait for components that need provider routing capability
#[async_trait]
pub trait ProviderRouterAware {
    async fn set_provider_router(&mut self, router: Arc<ProviderRouter>) -> ZekeResult<()>;
    fn get_provider_router(&self) -> Option<Arc<ProviderRouter>>;
}