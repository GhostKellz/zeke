use async_trait::async_trait;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::time::Duration;
use tracing::{debug, info, error};

use crate::error::{ZekeError, ZekeResult};
use super::{AuthProvider, AuthToken, DeviceCodeResponse};

#[derive(Debug, Clone)]
pub struct GitHubAuthProvider {
    client: Client,
    client_id: String,
    client_secret: Option<String>,
}

#[derive(Debug, Deserialize)]
struct GitHubDeviceCodeResponse {
    device_code: String,
    user_code: String,
    verification_uri: String,
    verification_uri_complete: Option<String>,
    expires_in: u64,
    interval: u64,
}

#[derive(Debug, Deserialize)]
struct GitHubTokenResponse {
    access_token: String,
    token_type: String,
    scope: String,
    #[serde(default)]
    expires_in: Option<u64>,
    #[serde(default)]
    refresh_token: Option<String>,
}

#[derive(Debug, Deserialize)]
struct GitHubTokenError {
    error: String,
    error_description: Option<String>,
}

impl GitHubAuthProvider {
    pub fn new() -> Self {
        // GitHub Copilot uses a specific client ID for device flow
        let client_id = "Iv1.b507a08c87ecfe98".to_string(); // Official GitHub CLI client ID

        Self {
            client: Client::builder()
                .timeout(Duration::from_secs(30))
                .user_agent("Zeke/0.3.0")
                .build()
                .unwrap_or_else(|_| Client::new()),
            client_id,
            client_secret: None,
        }
    }

    pub fn with_client_credentials(client_id: String, client_secret: Option<String>) -> Self {
        Self {
            client: Client::builder()
                .timeout(Duration::from_secs(30))
                .user_agent("Zeke/0.3.0")
                .build()
                .unwrap_or_else(|_| Client::new()),
            client_id,
            client_secret,
        }
    }

    async fn request_device_code(&self) -> ZekeResult<GitHubDeviceCodeResponse> {
        let url = "https://github.com/login/device/code";

        let params = json!({
            "client_id": self.client_id,
            "scope": "read:user copilot"
        });

        debug!("Requesting device code from GitHub");

        let response = self.client
            .post(url)
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .json(&params)
            .send()
            .await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            return Err(ZekeError::auth(format!("GitHub device code request failed: {}", error_text)));
        }

        let device_response: GitHubDeviceCodeResponse = response.json().await?;
        Ok(device_response)
    }

    async fn poll_token(&self, device_code: &str) -> ZekeResult<Option<GitHubTokenResponse>> {
        let url = "https://github.com/login/oauth/access_token";

        let params = json!({
            "client_id": self.client_id,
            "device_code": device_code,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        });

        let response = self.client
            .post(url)
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .json(&params)
            .send()
            .await?;

        let response_text = response.text().await?;

        // Try to parse as error first
        if let Ok(error_response) = serde_json::from_str::<GitHubTokenError>(&response_text) {
            match error_response.error.as_str() {
                "authorization_pending" => {
                    debug!("Authorization still pending");
                    return Ok(None);
                }
                "slow_down" => {
                    debug!("Rate limit hit, slowing down");
                    return Ok(None);
                }
                "expired_token" => {
                    return Err(ZekeError::auth("Device code expired. Please restart the authentication process."));
                }
                "access_denied" => {
                    return Err(ZekeError::auth("User denied the authorization request."));
                }
                _ => {
                    return Err(ZekeError::auth(format!("GitHub OAuth error: {}", error_response.error)));
                }
            }
        }

        // Try to parse as successful token response
        match serde_json::from_str::<GitHubTokenResponse>(&response_text) {
            Ok(token_response) => Ok(Some(token_response)),
            Err(e) => {
                error!("Failed to parse GitHub token response: {}", e);
                error!("Response body: {}", response_text);
                Err(ZekeError::auth("Failed to parse GitHub token response"))
            }
        }
    }
}

#[async_trait]
impl AuthProvider for GitHubAuthProvider {
    fn provider_name(&self) -> &str {
        "GitHub"
    }

    async fn start_device_flow(&self) -> ZekeResult<DeviceCodeResponse> {
        let github_response = self.request_device_code().await?;

        info!("GitHub device flow started");
        info!("Go to: {}", github_response.verification_uri);
        info!("Enter code: {}", github_response.user_code);

        if let Some(complete_uri) = &github_response.verification_uri_complete {
            info!("Or visit: {}", complete_uri);
        }

        Ok(DeviceCodeResponse {
            device_code: github_response.device_code,
            user_code: github_response.user_code,
            verification_uri: github_response.verification_uri,
            verification_uri_complete: github_response.verification_uri_complete,
            expires_in: github_response.expires_in,
            interval: github_response.interval,
        })
    }

    async fn poll_for_token(&self, device_code: &str) -> ZekeResult<Option<AuthToken>> {
        match self.poll_token(device_code).await? {
            Some(github_token) => {
                let mut auth_token = AuthToken::new(
                    github_token.access_token,
                    github_token.token_type,
                )
                .with_scope(github_token.scope);

                if let Some(expires_in) = github_token.expires_in {
                    auth_token = auth_token.with_expiry(expires_in);
                }

                if let Some(refresh_token) = github_token.refresh_token {
                    auth_token = auth_token.with_refresh_token(refresh_token);
                }

                Ok(Some(auth_token))
            }
            None => Ok(None),
        }
    }

    async fn refresh_token(&self, refresh_token: &str) -> ZekeResult<AuthToken> {
        if self.client_secret.is_none() {
            return Err(ZekeError::auth("Client secret required for token refresh"));
        }

        let url = "https://github.com/login/oauth/access_token";

        let params = json!({
            "client_id": self.client_id,
            "client_secret": self.client_secret.as_ref().unwrap(),
            "refresh_token": refresh_token,
            "grant_type": "refresh_token"
        });

        let response = self.client
            .post(url)
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .json(&params)
            .send()
            .await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            return Err(ZekeError::auth(format!("GitHub token refresh failed: {}", error_text)));
        }

        let github_token: GitHubTokenResponse = response.json().await?;

        let mut auth_token = AuthToken::new(
            github_token.access_token,
            github_token.token_type,
        )
        .with_scope(github_token.scope);

        if let Some(expires_in) = github_token.expires_in {
            auth_token = auth_token.with_expiry(expires_in);
        }

        if let Some(new_refresh_token) = github_token.refresh_token {
            auth_token = auth_token.with_refresh_token(new_refresh_token);
        }

        Ok(auth_token)
    }
}