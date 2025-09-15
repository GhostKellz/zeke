use thiserror::Error;

pub type ZekeResult<T> = Result<T, ZekeError>;

#[derive(Error, Debug)]
pub enum ZekeError {
    #[error("Provider error: {0}")]
    Provider(String),

    #[error("Authentication error: {0}")]
    Auth(String),

    #[error("Configuration error: {0}")]
    Config(String),

    #[error("Network error: {0}")]
    Network(#[from] reqwest::Error),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("JSON serialization error: {0}")]
    Json(#[from] serde_json::Error),

    #[cfg(feature = "git")]
    #[error("Git error: {0}")]
    Git(#[from] git2::Error),

    #[error("MessagePack error: {0}")]
    MessagePack(#[from] rmp_serde::encode::Error),

    #[error("MessagePack decode error: {0}")]
    MessagePackDecode(#[from] rmp_serde::decode::Error),

    #[error("MessagePack value decode error: {0}")]
    MessagePackValueDecode(#[from] rmpv::decode::Error),

    #[error("MessagePack value encode error: {0}")]
    MessagePackValueEncode(#[from] rmpv::encode::Error),

    #[error("Invalid input: {0}")]
    InvalidInput(String),

    #[error("Command failed: {0}")]
    CommandFailed(String),
}

impl ZekeError {
    pub fn provider<T: Into<String>>(msg: T) -> Self {
        ZekeError::Provider(msg.into())
    }

    pub fn auth<T: Into<String>>(msg: T) -> Self {
        ZekeError::Auth(msg.into())
    }

    pub fn config<T: Into<String>>(msg: T) -> Self {
        ZekeError::Config(msg.into())
    }

    pub fn invalid_input<T: Into<String>>(msg: T) -> Self {
        ZekeError::InvalidInput(msg.into())
    }

    pub fn command_failed<T: Into<String>>(msg: T) -> Self {
        ZekeError::CommandFailed(msg.into())
    }

    pub fn io<T: Into<String>>(msg: T) -> Self {
        ZekeError::Io(std::io::Error::new(std::io::ErrorKind::Other, msg.into()))
    }
}