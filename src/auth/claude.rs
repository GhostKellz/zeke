use async_trait::async_trait;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::time::Duration;
use tracing::{debug, info, error};

use crate::error::{ZekeError, ZekeResult};
use super::{AuthProvider, AuthToken, DeviceCodeResponse};

#[derive(Debug, Clone)]
pub struct ClaudeAuthProvider {
    client: Client,
    client_id: String,
}

#[derive(Debug, Deserialize)]
struct GoogleDeviceCodeResponse {
    device_code: String,
    user_code: String,
    verification_url: String,
    verification_url_complete: Option<String>,
    expires_in: u64,
    interval: u64,
}

#[derive(Debug, Deserialize)]
struct GoogleTokenResponse {
    access_token: String,
    token_type: String,
    expires_in: Option<u64>,
    refresh_token: Option<String>,
    scope: Option<String>,
}

#[derive(Debug, Deserialize)]
struct GoogleTokenError {
    error: String,
    error_description: Option<String>,
}

#[derive(Debug, Deserialize)]
struct ClaudeSessionResponse {
    session_token: String,
    expires_at: Option<String>,
    user_id: String,
    organization_id: Option<String>,
}

impl ClaudeAuthProvider {
    pub fn new() -> Self {
        // Using Google OAuth2 client ID for Claude.ai access
        let client_id = "your-google-oauth-client-id".to_string(); // This would be configured

        Self {
            client: Client::builder()
                .timeout(Duration::from_secs(30))
                .user_agent("Zeke/0.3.0")
                .build()
                .unwrap_or_else(|_| Client::new()),
            client_id,
        }
    }

    pub fn with_client_id(client_id: String) -> Self {
        Self {
            client: Client::builder()
                .timeout(Duration::from_secs(30))
                .user_agent("Zeke/0.3.0")
                .build()
                .unwrap_or_else(|_| Client::new()),
            client_id,
        }
    }

    async fn request_google_device_code(&self) -> ZekeResult<GoogleDeviceCodeResponse> {
        let url = "https://oauth2.googleapis.com/device/code";

        let params = json!({
            "client_id": self.client_id,
            "scope": "openid email profile"
        });

        debug!("Requesting Google device code");

        let response = self.client
            .post(url)
            .header("Content-Type", "application/x-www-form-urlencoded")
            .form(&[
                ("client_id", self.client_id.as_str()),
                ("scope", "openid email profile"),
            ])
            .send()
            .await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            return Err(ZekeError::auth(format!("Google device code request failed: {}", error_text)));
        }

        let device_response: GoogleDeviceCodeResponse = response.json().await?;
        Ok(device_response)
    }

    async fn poll_google_token(&self, device_code: &str) -> ZekeResult<Option<GoogleTokenResponse>> {
        let url = "https://oauth2.googleapis.com/token";

        let response = self.client
            .post(url)
            .header("Content-Type", "application/x-www-form-urlencoded")
            .form(&[
                ("client_id", self.client_id.as_str()),
                ("device_code", device_code),
                ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
            ])
            .send()
            .await?;

        let response_text = response.text().await?;

        // Try to parse as error first
        if let Ok(error_response) = serde_json::from_str::<GoogleTokenError>(&response_text) {
            match error_response.error.as_str() {
                "authorization_pending" => {
                    debug!("Google authorization still pending");
                    return Ok(None);
                }
                "slow_down" => {
                    debug!("Google rate limit hit, slowing down");
                    return Ok(None);
                }
                "expired_token" => {
                    return Err(ZekeError::auth("Google device code expired. Please restart the authentication process."));
                }
                "access_denied" => {
                    return Err(ZekeError::auth("User denied the Google authorization request."));
                }
                _ => {
                    return Err(ZekeError::auth(format!("Google OAuth error: {}", error_response.error)));
                }
            }
        }

        // Try to parse as successful token response
        match serde_json::from_str::<GoogleTokenResponse>(&response_text) {
            Ok(token_response) => Ok(Some(token_response)),
            Err(e) => {
                error!("Failed to parse Google token response: {}", e);
                error!("Response body: {}", response_text);
                Err(ZekeError::auth("Failed to parse Google token response"))
            }
        }
    }

    async fn exchange_google_token_for_claude_session(&self, google_token: &str) -> ZekeResult<ClaudeSessionResponse> {
        // This is a simplified implementation. In reality, you'd need to:
        // 1. Use the Google token to authenticate with Claude.ai
        // 2. Get a Claude session token
        // 3. Handle the specific Claude.ai authentication flow

        let url = "https://claude.ai/api/auth/google";

        let response = self.client
            .post(url)
            .header("Authorization", format!("Bearer {}", google_token))
            .header("Content-Type", "application/json")
            .json(&json!({}))
            .send()
            .await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            return Err(ZekeError::auth(format!("Claude session exchange failed: {}", error_text)));
        }

        let claude_session: ClaudeSessionResponse = response.json().await?;
        Ok(claude_session)
    }
}

#[async_trait]
impl AuthProvider for ClaudeAuthProvider {
    fn provider_name(&self) -> &str {
        "Claude (Google Sign-in)"
    }

    async fn start_device_flow(&self) -> ZekeResult<DeviceCodeResponse> {
        let google_response = self.request_google_device_code().await?;

        info!("Claude Google sign-in flow started");
        info!("Go to: {}", google_response.verification_url);
        info!("Enter code: {}", google_response.user_code);

        if let Some(complete_url) = &google_response.verification_url_complete {
            info!("Or visit: {}", complete_url);
        }

        Ok(DeviceCodeResponse {
            device_code: google_response.device_code,
            user_code: google_response.user_code,
            verification_uri: google_response.verification_url,
            verification_uri_complete: google_response.verification_url_complete,
            expires_in: google_response.expires_in,
            interval: google_response.interval,
        })
    }

    async fn poll_for_token(&self, device_code: &str) -> ZekeResult<Option<AuthToken>> {
        match self.poll_google_token(device_code).await? {
            Some(google_token) => {
                info!("Google authentication successful, exchanging for Claude session...");

                // Exchange Google token for Claude session
                let claude_session = self.exchange_google_token_for_claude_session(&google_token.access_token).await?;

                let mut auth_token = AuthToken::new(
                    claude_session.session_token,
                    "Bearer".to_string(),
                );

                if let Some(expires_in) = google_token.expires_in {
                    auth_token = auth_token.with_expiry(expires_in);
                }

                if let Some(refresh_token) = google_token.refresh_token {
                    auth_token = auth_token.with_refresh_token(refresh_token);
                }

                if let Some(scope) = google_token.scope {
                    auth_token = auth_token.with_scope(scope);
                }

                info!("Claude session established successfully");
                Ok(Some(auth_token))
            }
            None => Ok(None),
        }
    }

    async fn refresh_token(&self, refresh_token: &str) -> ZekeResult<AuthToken> {
        let url = "https://oauth2.googleapis.com/token";

        let response = self.client
            .post(url)
            .header("Content-Type", "application/x-www-form-urlencoded")
            .form(&[
                ("client_id", self.client_id.as_str()),
                ("refresh_token", refresh_token),
                ("grant_type", "refresh_token"),
            ])
            .send()
            .await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            return Err(ZekeError::auth(format!("Google token refresh failed: {}", error_text)));
        }

        let google_token: GoogleTokenResponse = response.json().await?;

        // Exchange refreshed Google token for new Claude session
        let claude_session = self.exchange_google_token_for_claude_session(&google_token.access_token).await?;

        let mut auth_token = AuthToken::new(
            claude_session.session_token,
            "Bearer".to_string(),
        );

        if let Some(expires_in) = google_token.expires_in {
            auth_token = auth_token.with_expiry(expires_in);
        }

        if let Some(new_refresh_token) = google_token.refresh_token {
            auth_token = auth_token.with_refresh_token(new_refresh_token);
        }

        Ok(auth_token)
    }
}