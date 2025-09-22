//! AI provider definitions and utilities

use serde::{Deserialize, Serialize};
use std::fmt;
use zeke_sys::ZekeProvider;

/// AI providers supported by Zeke
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Provider {
    /// GitHub Copilot
    Copilot,
    /// Anthropic Claude
    Claude,
    /// OpenAI GPT models
    OpenAI,
    /// Local Ollama instance
    Ollama,
    /// GhostLLM GPU-accelerated inference
    GhostLLM,
}

impl Provider {
    /// Get all available providers
    pub fn all() -> Vec<Provider> {
        vec![
            Provider::Copilot,
            Provider::Claude,
            Provider::OpenAI,
            Provider::Ollama,
            Provider::GhostLLM,
        ]
    }

    /// Get the default base URL for this provider
    pub fn default_base_url(&self) -> &'static str {
        match self {
            Provider::Copilot => "https://api.githubcopilot.com",
            Provider::Claude => "https://api.anthropic.com/v1",
            Provider::OpenAI => "https://api.openai.com/v1",
            Provider::Ollama => "http://localhost:11434",
            Provider::GhostLLM => "http://localhost:8080",
        }
    }

    /// Get default models for this provider
    pub fn default_models(&self) -> Vec<&'static str> {
        match self {
            Provider::Copilot => vec!["copilot-codex"],
            Provider::Claude => vec![
                "claude-3-5-sonnet-20241022",
                "claude-3-opus-20240229",
                "claude-3-sonnet-20240229",
                "claude-3-haiku-20240307",
            ],
            Provider::OpenAI => vec![
                "gpt-4o",
                "gpt-4",
                "gpt-4-turbo",
                "gpt-3.5-turbo",
            ],
            Provider::Ollama => vec![
                "llama2",
                "llama3",
                "codellama",
                "mistral",
                "mixtral",
            ],
            Provider::GhostLLM => vec![
                "ghostllm-7b",
                "ghostllm-13b",
                "ghostllm-30b",
                "llama2-7b",
                "llama2-13b",
            ],
        }
    }

    /// Get the default model for this provider
    pub fn default_model(&self) -> &'static str {
        match self {
            Provider::Copilot => "copilot-codex",
            Provider::Claude => "claude-3-5-sonnet-20241022",
            Provider::OpenAI => "gpt-4o",
            Provider::Ollama => "llama3",
            Provider::GhostLLM => "ghostllm-7b",
        }
    }

    /// Check if this provider supports streaming
    pub fn supports_streaming(&self) -> bool {
        match self {
            Provider::Copilot => false, // GitHub Copilot doesn't support streaming
            Provider::Claude => true,
            Provider::OpenAI => true,
            Provider::Ollama => true,
            Provider::GhostLLM => true,
        }
    }

    /// Check if this provider supports GPU acceleration
    pub fn supports_gpu(&self) -> bool {
        match self {
            Provider::GhostLLM => true,
            Provider::Ollama => true, // Ollama can use GPU if available
            _ => false,
        }
    }

    /// Check if this provider is hosted locally
    pub fn is_local(&self) -> bool {
        matches!(self, Provider::Ollama | Provider::GhostLLM)
    }

    /// Check if this provider requires an API key
    pub fn requires_api_key(&self) -> bool {
        match self {
            Provider::Ollama => false, // Local, no API key needed
            Provider::GhostLLM => false, // Can run without API key locally
            _ => true,
        }
    }

    /// Get authentication method for this provider
    pub fn auth_method(&self) -> AuthMethod {
        match self {
            Provider::Copilot => AuthMethod::OAuth,
            Provider::Claude => AuthMethod::ApiKey,
            Provider::OpenAI => AuthMethod::ApiKey,
            Provider::Ollama => AuthMethod::None,
            Provider::GhostLLM => AuthMethod::Optional,
        }
    }

    /// Get the provider's official name
    pub fn display_name(&self) -> &'static str {
        match self {
            Provider::Copilot => "GitHub Copilot",
            Provider::Claude => "Anthropic Claude",
            Provider::OpenAI => "OpenAI",
            Provider::Ollama => "Ollama",
            Provider::GhostLLM => "GhostLLM",
        }
    }

    /// Get the provider's short identifier
    pub fn identifier(&self) -> &'static str {
        match self {
            Provider::Copilot => "copilot",
            Provider::Claude => "claude",
            Provider::OpenAI => "openai",
            Provider::Ollama => "ollama",
            Provider::GhostLLM => "ghostllm",
        }
    }

    /// Parse provider from string identifier
    pub fn from_str(s: &str) -> Option<Provider> {
        match s.to_lowercase().as_str() {
            "copilot" | "github-copilot" => Some(Provider::Copilot),
            "claude" | "anthropic" => Some(Provider::Claude),
            "openai" | "gpt" => Some(Provider::OpenAI),
            "ollama" => Some(Provider::Ollama),
            "ghostllm" | "ghost-llm" | "ghost" => Some(Provider::GhostLLM),
            _ => None,
        }
    }

    /// Get typical rate limits for this provider (requests per minute)
    pub fn rate_limit(&self) -> Option<u32> {
        match self {
            Provider::Copilot => Some(60),    // GitHub API limits
            Provider::Claude => Some(50),     // Anthropic rate limits
            Provider::OpenAI => Some(60),     // OpenAI rate limits (varies by tier)
            Provider::Ollama => None,         // Local, no limits
            Provider::GhostLLM => None,       // Local, no limits
        }
    }

    /// Convert to FFI provider enum
    pub(crate) fn to_ffi(&self) -> ZekeProvider {
        match self {
            Provider::Copilot => ZekeProvider::ZEKE_PROVIDER_COPILOT,
            Provider::Claude => ZekeProvider::ZEKE_PROVIDER_CLAUDE,
            Provider::OpenAI => ZekeProvider::ZEKE_PROVIDER_OPENAI,
            Provider::Ollama => ZekeProvider::ZEKE_PROVIDER_OLLAMA,
            Provider::GhostLLM => ZekeProvider::ZEKE_PROVIDER_GHOSTLLM,
        }
    }

    /// Convert from FFI provider enum
    pub(crate) fn from_ffi(provider: ZekeProvider) -> Option<Provider> {
        match provider {
            ZekeProvider::ZEKE_PROVIDER_COPILOT => Some(Provider::Copilot),
            ZekeProvider::ZEKE_PROVIDER_CLAUDE => Some(Provider::Claude),
            ZekeProvider::ZEKE_PROVIDER_OPENAI => Some(Provider::OpenAI),
            ZekeProvider::ZEKE_PROVIDER_OLLAMA => Some(Provider::Ollama),
            ZekeProvider::ZEKE_PROVIDER_GHOSTLLM => Some(Provider::GhostLLM),
        }
    }
}

impl fmt::Display for Provider {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.display_name())
    }
}

impl From<Provider> for String {
    fn from(provider: Provider) -> String {
        provider.identifier().to_string()
    }
}

/// Authentication methods supported by providers
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthMethod {
    /// No authentication required
    None,
    /// API key authentication
    ApiKey,
    /// OAuth 2.0 authentication
    OAuth,
    /// Authentication is optional
    Optional,
}

impl fmt::Display for AuthMethod {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AuthMethod::None => write!(f, "None"),
            AuthMethod::ApiKey => write!(f, "API Key"),
            AuthMethod::OAuth => write!(f, "OAuth 2.0"),
            AuthMethod::Optional => write!(f, "Optional"),
        }
    }
}

/// Provider capabilities and metadata
#[derive(Debug, Clone)]
pub struct ProviderInfo {
    /// The provider
    pub provider: Provider,
    /// Display name
    pub name: String,
    /// Default base URL
    pub base_url: String,
    /// Available models
    pub models: Vec<String>,
    /// Default model
    pub default_model: String,
    /// Supports streaming
    pub supports_streaming: bool,
    /// Supports GPU acceleration
    pub supports_gpu: bool,
    /// Is hosted locally
    pub is_local: bool,
    /// Requires API key
    pub requires_api_key: bool,
    /// Authentication method
    pub auth_method: AuthMethod,
    /// Rate limit (requests per minute)
    pub rate_limit: Option<u32>,
}

impl From<Provider> for ProviderInfo {
    fn from(provider: Provider) -> Self {
        ProviderInfo {
            name: provider.display_name().to_string(),
            base_url: provider.default_base_url().to_string(),
            models: provider.default_models().into_iter().map(String::from).collect(),
            default_model: provider.default_model().to_string(),
            supports_streaming: provider.supports_streaming(),
            supports_gpu: provider.supports_gpu(),
            is_local: provider.is_local(),
            requires_api_key: provider.requires_api_key(),
            auth_method: provider.auth_method(),
            rate_limit: provider.rate_limit(),
            provider,
        }
    }
}

/// Provider status information
#[derive(Debug, Clone)]
pub struct ProviderStatus {
    /// The provider
    pub provider: Provider,
    /// Whether the provider is healthy
    pub is_healthy: bool,
    /// Average response time in milliseconds
    pub response_time_ms: u32,
    /// Error rate as a percentage (0.0 to 1.0)
    pub error_rate: f32,
    /// Requests per minute
    pub requests_per_minute: u32,
    /// Last health check timestamp
    pub last_check: std::time::SystemTime,
}

impl ProviderStatus {
    /// Check if the provider is performing well
    pub fn is_performing_well(&self) -> bool {
        self.is_healthy 
            && self.response_time_ms < 5000 // Less than 5 seconds
            && self.error_rate < 0.05       // Less than 5% error rate
    }

    /// Get a health score from 0.0 to 1.0
    pub fn health_score(&self) -> f32 {
        if !self.is_healthy {
            return 0.0;
        }

        // Score based on response time and error rate
        let response_score = if self.response_time_ms < 1000 {
            1.0
        } else if self.response_time_ms < 3000 {
            0.8
        } else if self.response_time_ms < 10000 {
            0.5
        } else {
            0.2
        };

        let error_score = 1.0 - self.error_rate.min(1.0);

        (response_score + error_score) / 2.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_provider_properties() {
        assert_eq!(Provider::OpenAI.default_model(), "gpt-4o");
        assert!(Provider::Claude.supports_streaming());
        assert!(Provider::GhostLLM.supports_gpu());
        assert!(Provider::Ollama.is_local());
        assert!(!Provider::Ollama.requires_api_key());
    }

    #[test]
    fn test_provider_from_string() {
        assert_eq!(Provider::from_str("openai"), Some(Provider::OpenAI));
        assert_eq!(Provider::from_str("claude"), Some(Provider::Claude));
        assert_eq!(Provider::from_str("ghostllm"), Some(Provider::GhostLLM));
        assert_eq!(Provider::from_str("invalid"), None);
    }

    #[test]
    fn test_provider_display() {
        assert_eq!(Provider::OpenAI.to_string(), "OpenAI");
        assert_eq!(Provider::Claude.identifier(), "claude");
    }

    #[test]
    fn test_provider_info() {
        let info = ProviderInfo::from(Provider::OpenAI);
        assert_eq!(info.provider, Provider::OpenAI);
        assert_eq!(info.name, "OpenAI");
        assert!(info.models.contains(&"gpt-4o".to_string()));
    }

    #[test]
    fn test_ffi_conversion() {
        let provider = Provider::OpenAI;
        let ffi = provider.to_ffi();
        assert_eq!(Provider::from_ffi(ffi), Some(provider));
    }

    #[test]
    fn test_provider_status_health_score() {
        let status = ProviderStatus {
            provider: Provider::OpenAI,
            is_healthy: true,
            response_time_ms: 500,
            error_rate: 0.01,
            requests_per_minute: 30,
            last_check: std::time::SystemTime::now(),
        };
        
        assert!(status.is_performing_well());
        assert!(status.health_score() > 0.8);
    }
}