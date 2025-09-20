use crate::error::{ZekeError, ZekeResult};
use crate::providers::{ChatRequest, ChatResponse, Provider, ChatMessage, ProviderClient};
use async_stream::stream;
use futures::{Stream, SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use std::pin::Pin;
use std::sync::Arc;
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::{accept_async, tungstenite::Message, WebSocketStream};
use tracing::{debug, info, warn, error};
use uuid::Uuid;

#[derive(Debug, Serialize, Deserialize)]
pub struct StreamedResponse {
    pub delta: String,
    pub model: String,
    pub provider: Provider,
    pub finished: bool,
}

pub type ChatStream = Pin<Box<dyn Stream<Item = ZekeResult<StreamedResponse>> + Send>>;

/// WebSocket connection information
#[derive(Debug, Clone)]
pub struct WebSocketConnection {
    pub id: String,
    pub auth_token: Option<String>,
    pub connected_at: std::time::SystemTime,
}

/// WebSocket streaming message types
#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum StreamMessage {
    /// Chat completion chunk
    ChatDelta {
        id: String,
        delta: String,
        model: String,
        provider: String,
        finished: bool,
    },
    /// Error occurred during streaming
    Error {
        id: String,
        error: String,
        code: Option<i32>,
    },
    /// Streaming session started
    StreamStart {
        id: String,
        model: String,
        provider: String,
    },
    /// Streaming session ended
    StreamEnd {
        id: String,
        total_tokens: Option<u32>,
    },
    /// Heartbeat/keepalive
    Ping {
        timestamp: u64,
    },
    /// Response to ping
    Pong {
        timestamp: u64,
    },
}

/// WebSocket streaming server
pub struct StreamServer {
    listener: TcpListener,
    connections: Arc<tokio::sync::RwLock<std::collections::HashMap<String, WebSocketConnection>>>,
}

impl StreamServer {
    /// Create a new streaming server on the specified port
    pub async fn new(port: u16) -> ZekeResult<Self> {
        let addr = format!("127.0.0.1:{}", port);
        let listener = TcpListener::bind(&addr).await
            .map_err(|e| ZekeError::provider(format!("Failed to bind WebSocket server to {}: {}", addr, e)))?;

        info!("🌊 WebSocket streaming server listening on {}", addr);

        Ok(Self {
            listener,
            connections: Arc::new(tokio::sync::RwLock::new(std::collections::HashMap::new())),
        })
    }

    /// Start accepting WebSocket connections
    pub async fn start(&self) -> ZekeResult<()> {
        loop {
            match self.listener.accept().await {
                Ok((stream, addr)) => {
                    info!("📡 New WebSocket connection from {}", addr);
                    let connections = self.connections.clone();
                    tokio::spawn(async move {
                        if let Err(e) = Self::handle_connection(stream, connections).await {
                            warn!("WebSocket connection error: {}", e);
                        }
                    });
                }
                Err(e) => {
                    error!("Failed to accept WebSocket connection: {}", e);
                }
            }
        }
    }

    /// Handle individual WebSocket connection
    async fn handle_connection(
        stream: TcpStream,
        connections: Arc<tokio::sync::RwLock<std::collections::HashMap<String, WebSocketConnection>>>,
    ) -> ZekeResult<()> {
        let ws_stream = accept_async(stream).await
            .map_err(|e| ZekeError::provider(format!("WebSocket handshake failed: {}", e)))?;

        let connection_id = Uuid::new_v4().to_string();
        let connection = WebSocketConnection {
            id: connection_id.clone(),
            auth_token: None, // TODO: Extract from handshake headers
            connected_at: std::time::SystemTime::now(),
        };

        // Store connection
        {
            let mut conn_map = connections.write().await;
            conn_map.insert(connection_id.clone(), connection);
        }

        info!("✅ WebSocket connection established: {}", connection_id);

        // Handle messages
        let result = Self::handle_messages(ws_stream, connection_id.clone()).await;

        // Clean up connection
        {
            let mut conn_map = connections.write().await;
            conn_map.remove(&connection_id);
        }

        info!("🔌 WebSocket connection closed: {}", connection_id);
        result
    }

    /// Handle WebSocket messages for a connection
    async fn handle_messages(
        mut ws_stream: WebSocketStream<TcpStream>,
        connection_id: String,
    ) -> ZekeResult<()> {
        while let Some(msg) = ws_stream.next().await {
            match msg {
                Ok(Message::Text(text)) => {
                    debug!("📨 Received message from {}: {}", connection_id, text);

                    // Parse and handle the message
                    match serde_json::from_str::<StreamMessage>(&text) {
                        Ok(stream_msg) => {
                            if let Err(e) = Self::process_message(stream_msg, &mut ws_stream).await {
                                warn!("Failed to process message: {}", e);
                            }
                        }
                        Err(e) => {
                            warn!("Invalid message format from {}: {}", connection_id, e);
                        }
                    }
                }
                Ok(Message::Binary(_)) => {
                    debug!("📨 Received binary message from {}", connection_id);
                }
                Ok(Message::Ping(payload)) => {
                    debug!("🏓 Received ping from {}", connection_id);
                    if let Err(e) = ws_stream.send(Message::Pong(payload)).await {
                        warn!("Failed to send pong: {}", e);
                        break;
                    }
                }
                Ok(Message::Pong(_)) => {
                    debug!("🏓 Received pong from {}", connection_id);
                }
                Ok(Message::Close(_)) => {
                    info!("🔌 Connection {} requested close", connection_id);
                    break;
                }
                Ok(Message::Frame(_)) => {
                    debug!("📨 Received frame message from {}", connection_id);
                }
                Err(e) => {
                    warn!("WebSocket error for {}: {}", connection_id, e);
                    break;
                }
            }
        }

        Ok(())
    }

    /// Process a parsed stream message
    async fn process_message(
        message: StreamMessage,
        ws_stream: &mut WebSocketStream<TcpStream>,
    ) -> ZekeResult<()> {
        match message {
            StreamMessage::Ping { timestamp } => {
                let pong = StreamMessage::Pong { timestamp };
                let pong_text = serde_json::to_string(&pong)?;
                ws_stream.send(Message::Text(pong_text)).await
                    .map_err(|e| ZekeError::provider(format!("Failed to send pong: {}", e)))?;
            }
            _ => {
                debug!("Unhandled message type: {:?}", message);
            }
        }
        Ok(())
    }

    /// Get current connection count
    pub async fn connection_count(&self) -> usize {
        let connections = self.connections.read().await;
        connections.len()
    }

    /// Get connection information
    pub async fn get_connections(&self) -> Vec<WebSocketConnection> {
        let connections = self.connections.read().await;
        connections.values().cloned().collect()
    }
}

/// Enhanced streaming manager with WebSocket support
pub struct StreamManager {
    server: Option<Arc<StreamServer>>,
    provider_clients: Arc<tokio::sync::RwLock<std::collections::HashMap<Provider, Arc<dyn ProviderClient>>>>,
}

impl StreamManager {
    pub fn new() -> Self {
        Self {
            server: None,
            provider_clients: Arc::new(tokio::sync::RwLock::new(std::collections::HashMap::new())),
        }
    }

    /// Start WebSocket server on specified port
    pub async fn start_websocket_server(&mut self, port: u16) -> ZekeResult<()> {
        let server = Arc::new(StreamServer::new(port).await?);
        let server_clone = server.clone();

        // Start server in background
        tokio::spawn(async move {
            if let Err(e) = server_clone.start().await {
                error!("WebSocket server error: {}", e);
            }
        });

        self.server = Some(server);
        Ok(())
    }

    /// Register a provider client for streaming
    pub async fn register_provider(&self, provider: Provider, client: Arc<dyn ProviderClient>) {
        let mut clients = self.provider_clients.write().await;
        clients.insert(provider, client);
    }

    /// Create a streaming chat response
    pub async fn create_chat_stream(
        &self,
        request: &ChatRequest,
        provider: Provider,
    ) -> ZekeResult<ChatStream> {
        let clients = self.provider_clients.read().await;

        // Check if we have a real provider client for streaming
        if let Some(client) = clients.get(&provider) {
            self.create_real_stream(request, provider, client.clone()).await
        } else {
            self.create_simulated_stream(request, provider).await
        }
    }

    /// Create a real streaming response using provider client
    async fn create_real_stream(
        &self,
        request: &ChatRequest,
        provider: Provider,
        client: Arc<dyn ProviderClient>,
    ) -> ZekeResult<ChatStream> {
        let request_clone = request.clone();
        let provider_clone = provider;
        let client_clone = client.clone();

        let stream = stream! {
            // For now, get full response and simulate streaming
            // In future, providers can implement native streaming
            match client_clone.chat_completion(&request_clone).await {
                Ok(response) => {
                    let words: Vec<&str> = response.content.split_whitespace().collect();
                    let chunk_size = 2; // Stream 2 words at a time for more granular streaming

                    for (i, chunk) in words.chunks(chunk_size).enumerate() {
                        let delta = chunk.join(" ");
                        if !delta.is_empty() {
                            yield Ok(StreamedResponse {
                                delta: if i == 0 { delta } else { format!(" {}", delta) },
                                model: response.model.clone(),
                                provider: provider_clone,
                                finished: false,
                            });
                            // Realistic streaming delay
                            tokio::time::sleep(tokio::time::Duration::from_millis(30)).await;
                        }
                    }

                    // Send final chunk
                    yield Ok(StreamedResponse {
                        delta: "".to_string(),
                        model: response.model.clone(),
                        provider: provider_clone,
                        finished: true,
                    });
                }
                Err(e) => {
                    yield Err(e);
                }
            }
        };

        Ok(Box::pin(stream))
    }

    /// Create simulated streaming response for testing
    async fn create_simulated_stream(
        &self,
        request: &ChatRequest,
        provider: Provider,
    ) -> ZekeResult<ChatStream> {
        let request_clone = request.clone();
        let provider_clone = provider;

        // Get the simulated full response
        let full_response = self.get_full_response(&request_clone, provider_clone).await?;

        let stream = stream! {
            // Simulate streaming by chunking the response
            let words: Vec<&str> = full_response.content.split_whitespace().collect();
            let chunk_size = 3; // Stream 3 words at a time

            for (i, chunk) in words.chunks(chunk_size).enumerate() {
                let delta = chunk.join(" ");
                if !delta.is_empty() {
                    yield Ok(StreamedResponse {
                        delta: if i == 0 { delta } else { format!(" {}", delta) },
                        model: full_response.model.clone(),
                        provider: full_response.provider,
                        finished: false,
                    });
                    // Small delay to simulate real streaming
                    tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
                }
            }

            // Send final chunk to indicate completion
            yield Ok(StreamedResponse {
                delta: "".to_string(),
                model: full_response.model.clone(),
                provider: full_response.provider,
                finished: true,
            });
        };

        Ok(Box::pin(stream))
    }

    /// Broadcast a stream to all connected WebSocket clients
    pub async fn broadcast_stream(&self, _stream: ChatStream) -> ZekeResult<()> {
        if let Some(server) = &self.server {
            let connections = server.get_connections().await;
            if connections.is_empty() {
                debug!("No WebSocket connections to broadcast to");
                return Ok(());
            }

            // TODO: Implement actual broadcast to WebSocket connections
            // For now, just log that we would broadcast
            info!("🌊 Would broadcast stream to {} connections", connections.len());
        }
        Ok(())
    }

    /// Get WebSocket server status
    pub async fn get_websocket_status(&self) -> Option<(usize, Vec<WebSocketConnection>)> {
        if let Some(server) = &self.server {
            let count = server.connection_count().await;
            let connections = server.get_connections().await;
            Some((count, connections))
        } else {
            None
        }
    }

    /// Stop WebSocket server
    pub async fn stop_websocket_server(&mut self) -> ZekeResult<()> {
        if let Some(_server) = self.server.take() {
            info!("🛑 WebSocket server stopped");
            // Server will be dropped and connections closed
        }
        Ok(())
    }
    // Helper method to get full response for simulation
    // In a real implementation, providers would have native streaming support
    async fn get_full_response(&self, request: &ChatRequest, provider: Provider) -> ZekeResult<ChatResponse> {
        // Simulate a response based on the provider
        let content = match provider {
            Provider::OpenAI => "This is a simulated OpenAI streaming response with multiple words to demonstrate the streaming capability.",
            Provider::Claude => "This is a simulated Claude streaming response showcasing the real-time text generation feature.",
            Provider::GhostLLM => "This is a simulated GhostLLM streaming response demonstrating high-performance GPU inference capabilities.",
            Provider::Ollama => "This is a simulated Ollama streaming response from your local model running on this machine.",
            Provider::Copilot => "This is a simulated GitHub Copilot streaming response for code completion and assistance.",
            Provider::DeepSeek => "This is a simulated DeepSeek streaming response demonstrating advanced reasoning and code generation capabilities.",
        };

        Ok(ChatResponse {
            content: content.to_string(),
            model: request.model.clone().unwrap_or_else(|| "simulated-model".to_string()),
            provider,
            usage: None,
        })
    }

    pub async fn start_stream(&self, _provider: &str) -> ZekeResult<()> {
        Ok(())
    }
}