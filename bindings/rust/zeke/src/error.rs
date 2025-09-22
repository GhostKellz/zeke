//! Error types and handling for Zeke operations

use std::ffi::NulError;
use thiserror::Error;
use zeke_sys::ZekeErrorCode;

/// Result type used throughout the Zeke crate
pub type Result<T> = std::result::Result<T, Error>;

/// Errors that can occur when using Zeke
#[derive(Error, Debug)]
pub enum Error {
    /// Failed to initialize Zeke instance
    #[error("Failed to initialize Zeke: {message}")]
    InitializationFailed {
        /// Additional error details
        message: String,
    },

    /// Authentication failed for the specified provider
    #[error("Authentication failed for provider {provider}: {message}")]
    AuthenticationFailed {
        /// The provider that failed authentication
        provider: String,
        /// Additional error details
        message: String,
    },

    /// Failed to load configuration
    #[error("Configuration error: {message}")]
    ConfigError {
        /// Configuration error details
        message: String,
    },

    /// Network-related error occurred
    #[error("Network error: {message}")]
    NetworkError {
        /// Network error details
        message: String,
    },

    /// Invalid model specified
    #[error("Invalid model '{model}' for provider {provider}")]
    InvalidModel {
        /// The invalid model name
        model: String,
        /// The provider that rejected the model
        provider: String,
    },

    /// Token exchange failed during OAuth
    #[error("Token exchange failed: {message}")]
    TokenExchangeFailed {
        /// Token exchange error details
        message: String,
    },

    /// Unexpected response from AI provider
    #[error("Unexpected response from {provider}: {message}")]
    UnexpectedResponse {
        /// The provider that sent the unexpected response
        provider: String,
        /// Response error details
        message: String,
    },

    /// Memory allocation error
    #[error("Memory allocation failed: {message}")]
    MemoryError {
        /// Memory error details
        message: String,
    },

    /// Invalid parameter provided to function
    #[error("Invalid parameter: {parameter} - {message}")]
    InvalidParameter {
        /// The invalid parameter name
        parameter: String,
        /// Parameter error details
        message: String,
    },

    /// Provider is currently unavailable
    #[error("Provider {provider} is unavailable: {message}")]
    ProviderUnavailable {
        /// The unavailable provider
        provider: String,
        /// Unavailability reason
        message: String,
    },

    /// Streaming operation failed
    #[error("Streaming failed: {message}")]
    StreamingFailed {
        /// Streaming error details
        message: String,
    },

    /// String conversion error (contains null bytes)
    #[error("String conversion error: {0}")]
    StringConversion(#[from] NulError),

    /// UTF-8 conversion error
    #[error("UTF-8 conversion error: {0}")]
    Utf8Error(#[from] std::str::Utf8Error),

    /// JSON serialization/deserialization error
    #[error("JSON error: {0}")]
    JsonError(#[from] serde_json::Error),

    /// I/O error
    #[error("I/O error: {0}")]
    IoError(#[from] std::io::Error),

    /// URL parsing error
    #[error("URL parsing error: {0}")]
    UrlError(#[from] url::ParseError),

    /// Generic error with custom message
    #[error("{message}")]
    Custom {
        /// Custom error message
        message: String,
    },
}

impl Error {
    /// Create a new custom error
    pub fn custom<S: Into<String>>(message: S) -> Self {
        Self::Custom {
            message: message.into(),
        }
    }

    /// Create an initialization error
    pub fn initialization<S: Into<String>>(message: S) -> Self {
        Self::InitializationFailed {
            message: message.into(),
        }
    }

    /// Create an authentication error
    pub fn authentication<S: Into<String>>(provider: S, message: S) -> Self {
        Self::AuthenticationFailed {
            provider: provider.into(),
            message: message.into(),
        }
    }

    /// Create a network error
    pub fn network<S: Into<String>>(message: S) -> Self {
        Self::NetworkError {
            message: message.into(),
        }
    }

    /// Create an invalid model error
    pub fn invalid_model<S: Into<String>>(model: S, provider: S) -> Self {
        Self::InvalidModel {
            model: model.into(),
            provider: provider.into(),
        }
    }

    /// Create a provider unavailable error
    pub fn provider_unavailable<S: Into<String>>(provider: S, message: S) -> Self {
        Self::ProviderUnavailable {
            provider: provider.into(),
            message: message.into(),
        }
    }

    /// Create a streaming error
    pub fn streaming<S: Into<String>>(message: S) -> Self {
        Self::StreamingFailed {
            message: message.into(),
        }
    }

    /// Check if this error is retryable
    pub fn is_retryable(&self) -> bool {
        matches!(
            self,
            Error::NetworkError { .. }
                | Error::ProviderUnavailable { .. }
                | Error::UnexpectedResponse { .. }
        )
    }

    /// Check if this error is related to authentication
    pub fn is_auth_error(&self) -> bool {
        matches!(
            self,
            Error::AuthenticationFailed { .. } | Error::TokenExchangeFailed { .. }
        )
    }

    /// Get the error category for metrics/logging
    pub fn category(&self) -> &'static str {
        match self {
            Error::InitializationFailed { .. } => "initialization",
            Error::AuthenticationFailed { .. } | Error::TokenExchangeFailed { .. } => {
                "authentication"
            }
            Error::ConfigError { .. } => "configuration",
            Error::NetworkError { .. } => "network",
            Error::InvalidModel { .. } => "model",
            Error::UnexpectedResponse { .. } => "response",
            Error::MemoryError { .. } => "memory",
            Error::InvalidParameter { .. } => "parameter",
            Error::ProviderUnavailable { .. } => "provider",
            Error::StreamingFailed { .. } => "streaming",
            Error::StringConversion(_) | Error::Utf8Error(_) => "encoding",
            Error::JsonError(_) => "serialization",
            Error::IoError(_) => "io",
            Error::UrlError(_) => "url",
            Error::Custom { .. } => "custom",
        }
    }
}

impl From<ZekeErrorCode> for Error {
    fn from(code: ZekeErrorCode) -> Self {
        match code {
            ZekeErrorCode::ZEKE_SUCCESS => {
                // This shouldn't happen, but handle gracefully
                Error::custom("Unexpected success code in error context")
            }
            ZekeErrorCode::ZEKE_INITIALIZATION_FAILED => {
                Error::initialization("Zeke initialization failed")
            }
            ZekeErrorCode::ZEKE_AUTHENTICATION_FAILED => {
                Error::authentication("unknown", "Authentication failed")
            }
            ZekeErrorCode::ZEKE_CONFIG_LOAD_FAILED => {
                Error::ConfigError {
                    message: "Failed to load configuration".to_string(),
                }
            }
            ZekeErrorCode::ZEKE_NETWORK_ERROR => Error::network("Network operation failed"),
            ZekeErrorCode::ZEKE_INVALID_MODEL => {
                Error::invalid_model("unknown", "unknown")
            }
            ZekeErrorCode::ZEKE_TOKEN_EXCHANGE_FAILED => Error::TokenExchangeFailed {
                message: "OAuth token exchange failed".to_string(),
            },
            ZekeErrorCode::ZEKE_UNEXPECTED_RESPONSE => Error::UnexpectedResponse {
                provider: "unknown".to_string(),
                message: "Received unexpected response".to_string(),
            },
            ZekeErrorCode::ZEKE_MEMORY_ERROR => Error::MemoryError {
                message: "Memory allocation failed".to_string(),
            },
            ZekeErrorCode::ZEKE_INVALID_PARAMETER => Error::InvalidParameter {
                parameter: "unknown".to_string(),
                message: "Invalid parameter provided".to_string(),
            },
            ZekeErrorCode::ZEKE_PROVIDER_UNAVAILABLE => Error::provider_unavailable(
                "unknown",
                "Provider is currently unavailable",
            ),
            ZekeErrorCode::ZEKE_STREAMING_FAILED => {
                Error::streaming("Streaming operation failed")
            }
        }
    }
}

/// Convert a Zeke error code with context into a Result
pub fn check_result(code: ZekeErrorCode) -> Result<()> {
    if code == ZekeErrorCode::ZEKE_SUCCESS {
        Ok(())
    } else {
        Err(Error::from(code))
    }
}

/// Enhanced error checking with last error message
pub fn check_result_with_context(code: ZekeErrorCode) -> Result<()> {
    if code == ZekeErrorCode::ZEKE_SUCCESS {
        Ok(())
    } else {
        let base_error = Error::from(code);
        
        // Try to get additional context from Zeke
        let context = unsafe {
            zeke_sys::get_last_error().unwrap_or_else(|| "No additional context available".to_string())
        };
        
        // Enhance the error with context
        let enhanced_error = match base_error {
            Error::AuthenticationFailed { provider, .. } => {
                Error::authentication(provider, context)
            }
            Error::NetworkError { .. } => Error::network(context),
            Error::InitializationFailed { .. } => Error::initialization(context),
            Error::StreamingFailed { .. } => Error::streaming(context),
            Error::ProviderUnavailable { provider, .. } => {
                Error::provider_unavailable(provider, context)
            }
            _ => Error::custom(context),
        };
        
        Err(enhanced_error)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_creation() {
        let err = Error::custom("test error");
        assert_eq!(err.to_string(), "test error");
    }

    #[test]
    fn test_error_categories() {
        assert_eq!(Error::network("test").category(), "network");
        assert_eq!(Error::initialization("test").category(), "initialization");
        assert_eq!(Error::authentication("test", "test").category(), "authentication");
    }

    #[test]
    fn test_retryable_errors() {
        assert!(Error::network("test").is_retryable());
        assert!(!Error::initialization("test").is_retryable());
        assert!(Error::provider_unavailable("test", "test").is_retryable());
    }

    #[test]
    fn test_auth_errors() {
        assert!(Error::authentication("test", "test").is_auth_error());
        assert!(!Error::network("test").is_auth_error());
    }

    #[test]
    fn test_error_code_conversion() {
        let err = Error::from(ZekeErrorCode::ZEKE_NETWORK_ERROR);
        assert!(matches!(err, Error::NetworkError { .. }));
    }
}