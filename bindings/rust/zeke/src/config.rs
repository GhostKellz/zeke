//! Configuration management for Zeke

use crate::{Error, Provider, Result};
use secrecy::{ExposeSecret, Secret};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;
use url::Url;

/// Main configuration for Zeke instances
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// AI provider to use
    pub provider: Provider,
    
    /// Base URL for API requests
    pub base_url: Option<String>,
    
    /// API key for authentication (stored securely)
    #[serde(skip)]
    pub api_key: Option<Secret<String>>,
    
    /// Model name to use
    pub model: String,
    
    /// Temperature for text generation (0.0 to 1.0)
    pub temperature: f32,
    
    /// Maximum tokens to generate
    pub max_tokens: u32,
    
    /// Enable streaming responses
    pub streaming: bool,
    
    /// Enable GPU acceleration (where supported)
    pub enable_gpu: bool,
    
    /// Enable automatic failover to backup providers
    pub enable_fallback: bool,
    
    /// Request timeout in milliseconds
    pub timeout_ms: u32,
    
    /// Provider-specific settings
    pub provider_settings: HashMap<String, serde_json::Value>,
}

impl Default for Config {
    fn default() -> Self {
        Config {
            provider: Provider::OpenAI,
            base_url: None,
            api_key: None,
            model: "gpt-4o".to_string(),
            temperature: 0.7,
            max_tokens: 2048,
            streaming: false,
            enable_gpu: false,
            enable_fallback: true,
            timeout_ms: 30000,
            provider_settings: HashMap::new(),
        }
    }
}

impl Config {
    /// Create a new configuration with default values
    pub fn new() -> Self {
        Self::default()
    }

    /// Create a configuration builder
    pub fn builder() -> ConfigBuilder {
        ConfigBuilder::new()
    }

    /// Load configuration from a TOML file
    pub fn from_file<P: AsRef<Path>>(path: P) -> Result<Self> {
        let content = std::fs::read_to_string(path)
            .map_err(|e| Error::ConfigError {
                message: format!("Failed to read config file: {}", e),
            })?;
        
        let mut config: Config = toml::from_str(&content)
            .map_err(|e| Error::ConfigError {
                message: format!("Failed to parse TOML config: {}", e),
            })?;
        
        // Try to load API key from environment if not set
        if config.api_key.is_none() {
            if let Some(key) = Self::get_api_key_from_env(config.provider) {
                config.api_key = Some(Secret::new(key));
            }
        }
        
        Ok(config)
    }

    /// Save configuration to a TOML file (API key is excluded)
    pub fn to_file<P: AsRef<Path>>(&self, path: P) -> Result<()> {
        let content = toml::to_string_pretty(self)
            .map_err(|e| Error::ConfigError {
                message: format!("Failed to serialize config: {}", e),
            })?;
        
        std::fs::write(path, content)
            .map_err(|e| Error::ConfigError {
                message: format!("Failed to write config file: {}", e),
            })?;
        
        Ok(())
    }

    /// Get the effective base URL (provider default or configured)
    pub fn effective_base_url(&self) -> String {
        self.base_url
            .as_ref()
            .unwrap_or(&self.provider.default_base_url().to_string())
            .clone()
    }

    /// Validate the configuration
    pub fn validate(&self) -> Result<()> {
        // Validate base URL
        if let Some(ref url) = self.base_url {
            Url::parse(url).map_err(|e| Error::ConfigError {
                message: format!("Invalid base URL: {}", e),
            })?;
        }

        // Validate temperature
        if !(0.0..=2.0).contains(&self.temperature) {
            return Err(Error::ConfigError {
                message: "Temperature must be between 0.0 and 2.0".to_string(),
            });
        }

        // Validate max tokens
        if self.max_tokens == 0 || self.max_tokens > 100_000 {
            return Err(Error::ConfigError {
                message: "Max tokens must be between 1 and 100,000".to_string(),
            });
        }

        // Validate timeout
        if self.timeout_ms < 1000 || self.timeout_ms > 300_000 {
            return Err(Error::ConfigError {
                message: "Timeout must be between 1 and 300 seconds".to_string(),
            });
        }

        // Check if API key is required but missing
        if self.provider.requires_api_key() && self.api_key.is_none() {
            return Err(Error::ConfigError {
                message: format!(
                    "API key is required for provider {}",
                    self.provider.display_name()
                ),
            });
        }

        // Validate model for provider
        let valid_models = self.provider.default_models();
        if !valid_models.is_empty() && !valid_models.contains(&self.model.as_str()) {
            tracing::warn!(
                "Model '{}' may not be valid for provider {}. Valid models: {:?}",
                self.model,
                self.provider.display_name(),
                valid_models
            );
        }

        Ok(())
    }

    /// Set API key securely
    pub fn set_api_key<S: Into<String>>(&mut self, key: S) {
        self.api_key = Some(Secret::new(key.into()));
    }

    /// Get API key (use carefully)
    pub fn api_key(&self) -> Option<&str> {
        self.api_key.as_ref().map(|k| k.expose_secret())
    }

    /// Try to get API key from environment variables
    fn get_api_key_from_env(provider: Provider) -> Option<String> {
        let env_vars = match provider {
            Provider::OpenAI => vec!["OPENAI_API_KEY", "OPENAI_KEY"],
            Provider::Claude => vec!["ANTHROPIC_API_KEY", "CLAUDE_API_KEY"],
            Provider::Copilot => vec!["GITHUB_TOKEN", "COPILOT_TOKEN"],
            Provider::GhostLLM => vec!["GHOSTLLM_API_KEY", "GHOST_API_KEY"],
            Provider::Ollama => vec![], // No API key needed
        };

        for var in env_vars {
            if let Ok(key) = std::env::var(var) {
                if !key.is_empty() {
                    return Some(key);
                }
            }
        }

        None
    }

    /// Get provider-specific setting
    pub fn get_provider_setting<T>(&self, key: &str) -> Option<T>
    where
        T: for<'de> Deserialize<'de>,
    {
        let provider_key = format!("{}.{}", self.provider.identifier(), key);
        self.provider_settings
            .get(&provider_key)
            .and_then(|v| serde_json::from_value(v.clone()).ok())
    }

    /// Set provider-specific setting
    pub fn set_provider_setting<T>(&mut self, key: &str, value: T) -> Result<()>
    where
        T: Serialize,
    {
        let provider_key = format!("{}.{}", self.provider.identifier(), key);
        let json_value = serde_json::to_value(value)?;
        self.provider_settings.insert(provider_key, json_value);
        Ok(())
    }

    /// Create a copy with different provider
    pub fn with_provider(&self, provider: Provider) -> Self {
        let mut config = self.clone();
        config.provider = provider;
        
        // Update model to provider default if current model is not supported
        let valid_models = provider.default_models();
        if !valid_models.contains(&config.model.as_str()) {
            config.model = provider.default_model().to_string();
        }
        
        // Clear API key if switching to provider that doesn't need one
        if !provider.requires_api_key() {
            config.api_key = None;
        }
        
        config
    }
}

/// Builder for creating Zeke configurations
#[derive(Debug)]
pub struct ConfigBuilder {
    config: Config,
}

impl ConfigBuilder {
    /// Create a new config builder
    pub fn new() -> Self {
        Self {
            config: Config::default(),
        }
    }

    /// Set the AI provider
    pub fn provider(mut self, provider: Provider) -> Self {
        self.config.provider = provider;
        // Auto-set default model for provider
        self.config.model = provider.default_model().to_string();
        self
    }

    /// Set the base URL
    pub fn base_url<S: Into<String>>(mut self, url: S) -> Self {
        self.config.base_url = Some(url.into());
        self
    }

    /// Set the API key
    pub fn api_key<S: Into<String>>(mut self, key: S) -> Self {
        self.config.api_key = Some(Secret::new(key.into()));
        self
    }

    /// Set the model name
    pub fn model<S: Into<String>>(mut self, model: S) -> Self {
        self.config.model = model.into();
        self
    }

    /// Set the temperature
    pub fn temperature(mut self, temperature: f32) -> Self {
        self.config.temperature = temperature;
        self
    }

    /// Set the maximum tokens
    pub fn max_tokens(mut self, max_tokens: u32) -> Self {
        self.config.max_tokens = max_tokens;
        self
    }

    /// Enable or disable streaming
    pub fn streaming(mut self, streaming: bool) -> Self {
        self.config.streaming = streaming;
        self
    }

    /// Enable or disable GPU acceleration
    pub fn gpu(mut self, enable_gpu: bool) -> Self {
        self.config.enable_gpu = enable_gpu;
        self
    }

    /// Enable or disable fallback providers
    pub fn fallback(mut self, enable_fallback: bool) -> Self {
        self.config.enable_fallback = enable_fallback;
        self
    }

    /// Set request timeout in milliseconds
    pub fn timeout_ms(mut self, timeout_ms: u32) -> Self {
        self.config.timeout_ms = timeout_ms;
        self
    }

    /// Set request timeout in seconds
    pub fn timeout_secs(mut self, timeout_secs: u32) -> Self {
        self.config.timeout_ms = timeout_secs * 1000;
        self
    }

    /// Add a provider-specific setting
    pub fn provider_setting<T>(mut self, key: &str, value: T) -> Result<Self>
    where
        T: Serialize,
    {
        self.config.set_provider_setting(key, value)?;
        Ok(self)
    }

    /// Load API key from environment variable
    pub fn api_key_from_env(mut self) -> Self {
        if let Some(key) = Config::get_api_key_from_env(self.config.provider) {
            self.config.api_key = Some(Secret::new(key));
        }
        self
    }

    /// Build the configuration
    pub fn build(self) -> Result<Config> {
        // Try to get API key from environment if not set
        let mut config = self.config;
        if config.api_key.is_none() {
            if let Some(key) = Config::get_api_key_from_env(config.provider) {
                config.api_key = Some(Secret::new(key));
            }
        }

        // Validate the configuration
        config.validate()?;
        
        Ok(config)
    }
}

impl Default for ConfigBuilder {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = Config::default();
        assert_eq!(config.provider, Provider::OpenAI);
        assert_eq!(config.model, "gpt-4o");
        assert_eq!(config.temperature, 0.7);
        assert!(config.enable_fallback);
    }

    #[test]
    fn test_config_builder() {
        let config = Config::builder()
            .provider(Provider::Claude)
            .temperature(0.5)
            .max_tokens(1000)
            .build()
            .unwrap();

        assert_eq!(config.provider, Provider::Claude);
        assert_eq!(config.temperature, 0.5);
        assert_eq!(config.max_tokens, 1000);
        assert_eq!(config.model, "claude-3-5-sonnet-20241022");
    }

    #[test]
    fn test_config_validation() {
        let mut config = Config::default();
        
        // Valid config should pass
        assert!(config.validate().is_ok());
        
        // Invalid temperature should fail
        config.temperature = 3.0;
        assert!(config.validate().is_err());
        
        // Invalid max tokens should fail
        config.temperature = 0.7;
        config.max_tokens = 0;
        assert!(config.validate().is_err());
    }

    #[test]
    fn test_effective_base_url() {
        let mut config = Config::default();
        config.provider = Provider::OpenAI;
        
        // Should use provider default when not set
        assert_eq!(config.effective_base_url(), "https://api.openai.com/v1");
        
        // Should use configured URL when set
        config.base_url = Some("https://custom.api.com".to_string());
        assert_eq!(config.effective_base_url(), "https://custom.api.com");
    }

    #[test]
    fn test_provider_settings() {
        let mut config = Config::default();
        config.provider = Provider::OpenAI;
        
        // Set a provider setting
        config.set_provider_setting("custom_param", "value").unwrap();
        
        // Get the setting back
        let value: Option<String> = config.get_provider_setting("custom_param");
        assert_eq!(value, Some("value".to_string()));
    }

    #[test]
    fn test_with_provider() {
        let config = Config::builder()
            .provider(Provider::OpenAI)
            .model("gpt-4")
            .build()
            .unwrap();
        
        let claude_config = config.with_provider(Provider::Claude);
        assert_eq!(claude_config.provider, Provider::Claude);
        // Model should change to Claude's default
        assert_eq!(claude_config.model, "claude-3-5-sonnet-20241022");
    }
}