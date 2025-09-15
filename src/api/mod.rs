use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::{Json, Sse},
    routing::{get, post},
    Router,
};
use axum::response::sse::{Event, KeepAlive};
use futures::StreamExt;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::convert::Infallible;
use tokio::net::TcpListener;
use tower_http::cors::CorsLayer;
use tracing::{info, error};
use uuid;

use crate::error::ZekeResult;
use crate::providers::{ChatMessage, ChatRequest, ProviderManager};
// HTTP API server for external integrations (like Neovim plugins)
use crate::streaming::{StreamManager, StreamedResponse};

type AppState = (Arc<ProviderManager>, Arc<StreamManager>);

// RPC support removed - external clients should use HTTP API

#[derive(Debug, Serialize, Deserialize)]
pub struct ApiResponse<T> {
    pub success: bool,
    pub data: Option<T>,
    pub error: Option<String>,
}

impl<T> ApiResponse<T> {
    pub fn success(data: T) -> Self {
        Self {
            success: true,
            data: Some(data),
            error: None,
        }
    }

    pub fn error(error: String) -> Self {
        Self {
            success: false,
            data: None,
            error: Some(error),
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ChatApiRequest {
    pub message: String,
    pub context: Option<Vec<ChatMessage>>,
    pub model: Option<String>,
    pub temperature: Option<f32>,
    pub max_tokens: Option<u32>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ChatApiResponse {
    pub content: String,
    pub model: String,
    pub provider: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ExplainRequest {
    pub code: String,
    pub language: Option<String>,
    pub context: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ExplainResponse {
    pub explanation: String,
    pub suggestions: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EditRequest {
    pub code: String,
    pub instruction: String,
    pub language: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EditResponse {
    pub edited_code: String,
    pub changes: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct HealthQuery {
    pub detailed: Option<bool>,
}

#[derive(Debug, Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub version: String,
    pub providers: Option<Vec<ProviderStatus>>,
}

#[derive(Debug, Serialize)]
pub struct ProviderStatus {
    pub name: String,
    pub healthy: bool,
    pub response_time_ms: u64,
    pub error_rate: f32,
}

// Claude API compatible structures
#[derive(Debug, Serialize, Deserialize)]
pub struct ClaudeMessage {
    pub role: String,
    pub content: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ClaudeApiRequest {
    pub model: String,
    pub messages: Vec<ClaudeMessage>,
    pub max_tokens: Option<u32>,
    pub temperature: Option<f32>,
    pub stream: Option<bool>,
    pub system: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ClaudeApiResponse {
    pub id: String,
    pub content: Vec<ClaudeContentBlock>,
    pub model: String,
    pub role: String,
    pub stop_reason: String,
    pub usage: ClaudeUsage,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ClaudeContentBlock {
    pub r#type: String,
    pub text: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ClaudeUsage {
    pub input_tokens: u32,
    pub output_tokens: u32,
}

pub struct ApiServer {
    provider_manager: Arc<ProviderManager>,
    stream_manager: Arc<StreamManager>,
}

impl ApiServer {
    pub fn new(provider_manager: Arc<ProviderManager>) -> Self {
        Self {
            provider_manager,
            stream_manager: Arc::new(StreamManager::new()),
        }
    }

    pub async fn start(&self, host: &str, port: u16) -> ZekeResult<()> {
        let app = self.create_router();
        let addr = format!("{}:{}", host, port);

        info!("🚀 Starting Zeke API server on {}", addr);

        let listener = TcpListener::bind(&addr).await?;
        axum::serve(listener, app).await?;

        Ok(())
    }

    fn create_router(&self) -> Router {
        Router::new()
            // Health endpoint
            .route("/health", get(health_handler))

            // Claude API compatible endpoints
            .route("/v1/messages", post(claude_messages_handler))
            .route("/v1/messages/stream", post(claude_messages_stream_handler))

            // Chat endpoints (Claude Code compatible)
            .route("/api/v1/chat", post(chat_handler))
            .route("/api/v1/chat/stream", post(chat_stream_handler))

            // Code operations
            .route("/api/v1/code/explain", post(explain_handler))
            .route("/api/v1/code/edit", post(edit_handler))
            .route("/api/v1/code/generate", post(generate_handler))
            .route("/api/v1/code/analyze", post(analyze_handler))

            // Provider management
            .route("/api/v1/providers", get(list_providers_handler))
            .route("/api/v1/providers/switch", post(switch_provider_handler))

            // Add CORS for browser access
            .layer(CorsLayer::permissive())
            .with_state((Arc::clone(&self.provider_manager), Arc::clone(&self.stream_manager)))
    }
}

// Handler implementations
async fn health_handler(
    Query(params): Query<HealthQuery>,
    State((provider_manager, _stream_manager)): State<AppState>,
) -> Result<Json<ApiResponse<HealthResponse>>, StatusCode> {
    let mut response = HealthResponse {
        status: "healthy".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        providers: None,
    };

    if params.detailed.unwrap_or(false) {
        let provider_statuses = provider_manager.get_provider_status().await;
        response.providers = Some(
            provider_statuses
                .into_iter()
                .map(|(provider, health)| ProviderStatus {
                    name: provider.to_string(),
                    healthy: health.is_healthy,
                    response_time_ms: health.response_time.as_millis() as u64,
                    error_rate: health.error_rate,
                })
                .collect(),
        );
    }

    Ok(Json(ApiResponse::success(response)))
}

async fn chat_handler(
    State((provider_manager, _stream_manager)): State<AppState>,
    Json(request): Json<ChatApiRequest>,
) -> Result<Json<ApiResponse<ChatApiResponse>>, StatusCode> {
    let mut messages = request.context.unwrap_or_default();
    messages.push(ChatMessage {
        role: "user".to_string(),
        content: request.message,
    });

    let chat_request = ChatRequest {
        messages,
        model: request.model,
        temperature: request.temperature,
        max_tokens: request.max_tokens,
        stream: Some(false),
    };

    match provider_manager.chat_completion(&chat_request).await {
        Ok(response) => {
            let api_response = ChatApiResponse {
                content: response.content,
                model: response.model,
                provider: response.provider.to_string(),
            };
            Ok(Json(ApiResponse::success(api_response)))
        }
        Err(e) => {
            error!("Chat completion failed: {}", e);
            Ok(Json(ApiResponse::error(e.to_string())))
        }
    }
}

async fn chat_stream_handler(
    State((provider_manager, stream_manager)): State<AppState>,
    Json(request): Json<ChatApiRequest>,
) -> Result<Sse<impl futures::Stream<Item = Result<Event, Infallible>>>, StatusCode> {
    let mut messages = request.context.unwrap_or_default();
    messages.push(ChatMessage {
        role: "user".to_string(),
        content: request.message,
    });

    let chat_request = ChatRequest {
        messages,
        model: request.model,
        temperature: request.temperature,
        max_tokens: request.max_tokens,
        stream: Some(true),
    };

    // Get the best provider for streaming
    let provider = match provider_manager.select_best_provider(&crate::providers::Capability::Streaming).await {
        Ok(p) => p,
        Err(e) => {
            error!("Failed to select provider for streaming: {}", e);
            return Err(StatusCode::INTERNAL_SERVER_ERROR);
        }
    };

    // Create the stream
    let stream = match stream_manager.create_chat_stream(&chat_request, provider).await {
        Ok(s) => s,
        Err(e) => {
            error!("Failed to create chat stream: {}", e);
            return Err(StatusCode::INTERNAL_SERVER_ERROR);
        }
    };

    // Convert to SSE events
    let event_stream = stream.map(|result| {
        match result {
            Ok(streamed_response) => {
                let data = serde_json::to_string(&streamed_response).unwrap_or_default();
                Ok(Event::default().data(data))
            },
            Err(e) => {
                let error_data = format!("{{\"error\": \"{}\"}}", e);
                Ok(Event::default().data(error_data))
            }
        }
    });

    Ok(Sse::new(event_stream).keep_alive(KeepAlive::default()))
}

async fn explain_handler(
    State((provider_manager, _stream_manager)): State<AppState>,
    Json(request): Json<ExplainRequest>,
) -> Result<Json<ApiResponse<ExplainResponse>>, StatusCode> {
    let prompt = format!(
        "Please explain the following {} code:\n\n```{}\n{}\n```\n\nProvide a clear explanation and any suggestions for improvement.",
        request.language.as_deref().unwrap_or(""),
        request.language.as_deref().unwrap_or(""),
        request.code
    );

    let messages = vec![ChatMessage {
        role: "user".to_string(),
        content: prompt,
    }];

    let chat_request = ChatRequest {
        messages,
        model: None,
        temperature: Some(0.3),
        max_tokens: Some(1024),
        stream: Some(false),
    };

    match provider_manager.chat_completion(&chat_request).await {
        Ok(response) => {
            let explain_response = ExplainResponse {
                explanation: response.content,
                suggestions: vec![], // TODO: Parse suggestions from response
            };
            Ok(Json(ApiResponse::success(explain_response)))
        }
        Err(e) => {
            error!("Code explanation failed: {}", e);
            Ok(Json(ApiResponse::error(e.to_string())))
        }
    }
}

async fn edit_handler(
    State((provider_manager, _stream_manager)): State<AppState>,
    Json(request): Json<EditRequest>,
) -> Result<Json<ApiResponse<EditResponse>>, StatusCode> {
    let prompt = format!(
        "Please edit the following {} code according to the instruction:\n\nInstruction: {}\n\nCode:\n```{}\n{}\n```\n\nPlease provide only the edited code.",
        request.language.as_deref().unwrap_or(""),
        request.instruction,
        request.language.as_deref().unwrap_or(""),
        request.code
    );

    let messages = vec![ChatMessage {
        role: "user".to_string(),
        content: prompt,
    }];

    let chat_request = ChatRequest {
        messages,
        model: None,
        temperature: Some(0.2),
        max_tokens: Some(2048),
        stream: Some(false),
    };

    match provider_manager.chat_completion(&chat_request).await {
        Ok(response) => {
            let edit_response = EditResponse {
                edited_code: response.content,
                changes: vec![], // TODO: Calculate diff
            };
            Ok(Json(ApiResponse::success(edit_response)))
        }
        Err(e) => {
            error!("Code editing failed: {}", e);
            Ok(Json(ApiResponse::error(e.to_string())))
        }
    }
}

async fn generate_handler(
    State((_provider_manager, _stream_manager)): State<AppState>,
    Json(_request): Json<serde_json::Value>,
) -> Result<Json<ApiResponse<String>>, StatusCode> {
    // TODO: Implement code generation
    Ok(Json(ApiResponse::error("Code generation not yet implemented".to_string())))
}

async fn analyze_handler(
    State((_provider_manager, _stream_manager)): State<AppState>,
    Json(_request): Json<serde_json::Value>,
) -> Result<Json<ApiResponse<String>>, StatusCode> {
    // TODO: Implement code analysis
    Ok(Json(ApiResponse::error("Code analysis not yet implemented".to_string())))
}

async fn list_providers_handler(
    State((provider_manager, _stream_manager)): State<AppState>,
) -> Result<Json<ApiResponse<Vec<String>>>, StatusCode> {
    let providers = provider_manager.list_providers().await;
    let provider_names: Vec<String> = providers.into_iter().map(|p| p.to_string()).collect();
    Ok(Json(ApiResponse::success(provider_names)))
}

// Claude API compatible handler
async fn claude_messages_handler(
    State((provider_manager, _stream_manager)): State<AppState>,
    Json(request): Json<ClaudeApiRequest>,
) -> Result<Json<ClaudeApiResponse>, StatusCode> {
    // Convert Claude API request to internal format
    let messages: Vec<ChatMessage> = request.messages.into_iter().map(|msg| ChatMessage {
        role: msg.role,
        content: msg.content,
    }).collect();

    let chat_request = ChatRequest {
        messages,
        model: Some(request.model.clone()),
        temperature: request.temperature,
        max_tokens: request.max_tokens,
        stream: Some(false),
    };

    match provider_manager.chat_completion(&chat_request).await {
        Ok(response) => {
            // Convert internal response to Claude API format
            let claude_response = ClaudeApiResponse {
                id: format!("msg_{}", uuid::Uuid::new_v4()),
                content: vec![ClaudeContentBlock {
                    r#type: "text".to_string(),
                    text: response.content,
                }],
                model: response.model,
                role: "assistant".to_string(),
                stop_reason: "end_turn".to_string(),
                usage: ClaudeUsage {
                    input_tokens: response.usage.as_ref().map(|u| u.prompt_tokens).unwrap_or(0),
                    output_tokens: response.usage.as_ref().map(|u| u.completion_tokens).unwrap_or(0),
                },
            };
            Ok(Json(claude_response))
        }
        Err(e) => {
            error!("Claude messages API error: {}", e);
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

async fn claude_messages_stream_handler(
    State((provider_manager, stream_manager)): State<AppState>,
    Json(request): Json<ClaudeApiRequest>,
) -> Result<Sse<impl futures::Stream<Item = Result<Event, Infallible>>>, StatusCode> {
    // Convert Claude API request to internal format
    let messages: Vec<ChatMessage> = request.messages.into_iter().map(|msg| ChatMessage {
        role: msg.role,
        content: msg.content,
    }).collect();

    let chat_request = ChatRequest {
        messages,
        model: Some(request.model.clone()),
        temperature: request.temperature,
        max_tokens: request.max_tokens,
        stream: Some(true),
    };

    // Get the best provider for streaming
    let provider = match provider_manager.select_best_provider(&crate::providers::Capability::Streaming).await {
        Ok(p) => p,
        Err(e) => {
            error!("Failed to select provider for streaming: {}", e);
            return Err(StatusCode::INTERNAL_SERVER_ERROR);
        }
    };

    // Create the stream
    let stream = match stream_manager.create_chat_stream(&chat_request, provider).await {
        Ok(s) => s,
        Err(e) => {
            error!("Failed to create chat stream: {}", e);
            return Err(StatusCode::INTERNAL_SERVER_ERROR);
        }
    };

    // Convert to Claude API streaming format (SSE events)
    let event_stream = stream.map(|result| {
        match result {
            Ok(streamed_response) => {
                // Format as Claude API streaming event
                let event_data = if streamed_response.finished {
                    serde_json::json!({
                        "type": "message_stop"
                    })
                } else {
                    serde_json::json!({
                        "type": "content_block_delta",
                        "delta": {
                            "type": "text_delta",
                            "text": streamed_response.delta
                        }
                    })
                };
                let data = serde_json::to_string(&event_data).unwrap_or_default();
                Ok(Event::default().data(data))
            },
            Err(e) => {
                let error_data = serde_json::json!({
                    "type": "error",
                    "error": {
                        "type": "api_error",
                        "message": e.to_string()
                    }
                });
                let data = serde_json::to_string(&error_data).unwrap_or_default();
                Ok(Event::default().data(data))
            }
        }
    });

    Ok(Sse::new(event_stream).keep_alive(KeepAlive::default()))
}

async fn switch_provider_handler(
    State((provider_manager, _stream_manager)): State<AppState>,
    Json(request): Json<HashMap<String, String>>,
) -> Result<Json<ApiResponse<String>>, StatusCode> {
    if let Some(provider_name) = request.get("provider") {
        match provider_name.parse() {
            Ok(provider) => {
                provider_manager.set_current_provider(provider).await;
                Ok(Json(ApiResponse::success(format!("Switched to provider: {}", provider_name))))
            }
            Err(e) => Ok(Json(ApiResponse::error(e.to_string()))),
        }
    } else {
        Ok(Json(ApiResponse::error("Missing 'provider' field".to_string())))
    }
}

/// Start the HTTP API server for external integrations
pub async fn start_api_server(host: &str, port: u16) -> ZekeResult<()> {
    info!("🚀 Starting Zeke API server on {}:{}", host, port);

    // Initialize provider manager
    let provider_manager = Arc::new(ProviderManager::new());

    // Initialize available providers
    if let Err(e) = provider_manager.initialize_default_providers().await {
        error!("Warning: Failed to initialize some providers: {}", e);
        // Continue anyway - some providers might work
    }

    // Start HTTP API server
    let api_server = ApiServer::new(provider_manager);
    api_server.start(host, port).await
}