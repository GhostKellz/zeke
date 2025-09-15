use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};
use crate::error::{ZekeError, ZekeResult};

pub mod github;
pub mod claude;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthToken {
    pub access_token: String,
    pub token_type: String,
    pub expires_at: Option<u64>,
    pub refresh_token: Option<String>,
    pub scope: Option<String>,
}

impl AuthToken {
    pub fn new(access_token: String, token_type: String) -> Self {
        Self {
            access_token,
            token_type,
            expires_at: None,
            refresh_token: None,
            scope: None,
        }
    }

    pub fn with_expiry(mut self, expires_in: u64) -> Self {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        self.expires_at = Some(now + expires_in);
        self
    }

    pub fn with_refresh_token(mut self, refresh_token: String) -> Self {
        self.refresh_token = Some(refresh_token);
        self
    }

    pub fn with_scope(mut self, scope: String) -> Self {
        self.scope = Some(scope);
        self
    }

    pub fn is_expired(&self) -> bool {
        if let Some(expires_at) = self.expires_at {
            let now = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs();
            now >= expires_at
        } else {
            false
        }
    }

    pub fn needs_refresh(&self) -> bool {
        if let Some(expires_at) = self.expires_at {
            let now = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs();
            // Refresh if expiring within 5 minutes
            (expires_at - now) < 300
        } else {
            false
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceCodeResponse {
    pub device_code: String,
    pub user_code: String,
    pub verification_uri: String,
    pub verification_uri_complete: Option<String>,
    pub expires_in: u64,
    pub interval: u64,
}

#[async_trait]
pub trait AuthProvider: Send + Sync {
    fn provider_name(&self) -> &str;
    async fn start_device_flow(&self) -> ZekeResult<DeviceCodeResponse>;
    async fn poll_for_token(&self, device_code: &str) -> ZekeResult<Option<AuthToken>>;
    async fn refresh_token(&self, refresh_token: &str) -> ZekeResult<AuthToken>;
}