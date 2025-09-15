use async_trait::async_trait;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;
use tracing::{debug, info, error, warn};

use crate::error::{ZekeError, ZekeResult};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpServer {
    pub name: String,
    pub url: String,
    pub description: Option<String>,
    pub capabilities: Vec<String>,
    pub auth_token: Option<String>,
    pub timeout: Duration,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpTool {
    pub name: String,
    pub description: String,
    pub parameters: Value,
    pub server_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpResource {
    pub name: String,
    pub description: String,
    pub uri: String,
    pub mime_type: Option<String>,
    pub server_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpRequest {
    pub jsonrpc: String,
    pub id: String,
    pub method: String,
    pub params: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpResponse {
    pub jsonrpc: String,
    pub id: String,
    pub result: Option<Value>,
    pub error: Option<McpError>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpError {
    pub code: i32,
    pub message: String,
    pub data: Option<Value>,
}

#[async_trait]
pub trait McpServerConnection: Send + Sync {
    async fn connect(&self) -> ZekeResult<()>;
    async fn disconnect(&self) -> ZekeResult<()>;
    async fn send_request(&self, request: McpRequest) -> ZekeResult<McpResponse>;
    async fn list_tools(&self) -> ZekeResult<Vec<McpTool>>;
    async fn list_resources(&self) -> ZekeResult<Vec<McpResource>>;
    async fn call_tool(&self, tool_name: &str, arguments: Value) -> ZekeResult<Value>;
    async fn read_resource(&self, uri: &str) -> ZekeResult<Value>;
    fn get_server_info(&self) -> &McpServer;
}

pub struct HttpMcpConnection {
    server: McpServer,
    client: Client,
    connected: RwLock<bool>,
}

impl HttpMcpConnection {
    pub fn new(server: McpServer) -> Self {
        let client = Client::builder()
            .timeout(server.timeout)
            .build()
            .unwrap_or_else(|_| Client::new());

        Self {
            server,
            client,
            connected: RwLock::new(false),
        }
    }

    async fn make_request(&self, method: &str, params: Option<Value>) -> ZekeResult<McpResponse> {
        let request_id = uuid::Uuid::new_v4().to_string();
        let request = McpRequest {
            jsonrpc: "2.0".to_string(),
            id: request_id.clone(),
            method: method.to_string(),
            params,
        };

        debug!("Sending MCP request to {}: {}", self.server.name, method);

        let mut http_request = self.client
            .post(&self.server.url)
            .header("Content-Type", "application/json")
            .json(&request);

        if let Some(auth_token) = &self.server.auth_token {
            http_request = http_request.header("Authorization", format!("Bearer {}", auth_token));
        }

        let response = http_request
            .send()
            .await
            .map_err(|e| ZekeError::provider(format!("MCP request failed: {}", e)))?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            return Err(ZekeError::provider(format!("MCP server error: {}", error_text)));
        }

        let mcp_response: McpResponse = response
            .json()
            .await
            .map_err(|e| ZekeError::provider(format!("Failed to parse MCP response: {}", e)))?;

        if let Some(error) = &mcp_response.error {
            return Err(ZekeError::provider(format!("MCP error {}: {}", error.code, error.message)));
        }

        Ok(mcp_response)
    }
}

#[async_trait]
impl McpServerConnection for HttpMcpConnection {
    async fn connect(&self) -> ZekeResult<()> {
        // Send initialize request
        let params = json!({
            "protocolVersion": "2024-11-05",
            "capabilities": {
                "tools": {},
                "resources": {}
            },
            "clientInfo": {
                "name": "Zeke",
                "version": "0.3.0"
            }
        });

        let response = self.make_request("initialize", Some(params)).await?;

        if response.result.is_some() {
            let mut connected = self.connected.write().await;
            *connected = true;
            info!("Connected to MCP server: {}", self.server.name);
        }

        // Send initialized notification
        let _ = self.make_request("initialized", None).await;

        Ok(())
    }

    async fn disconnect(&self) -> ZekeResult<()> {
        let mut connected = self.connected.write().await;
        *connected = false;
        info!("Disconnected from MCP server: {}", self.server.name);
        Ok(())
    }

    async fn send_request(&self, request: McpRequest) -> ZekeResult<McpResponse> {
        self.make_request(&request.method, request.params).await
    }

    async fn list_tools(&self) -> ZekeResult<Vec<McpTool>> {
        let response = self.make_request("tools/list", None).await?;

        if let Some(result) = response.result {
            if let Some(tools_array) = result.get("tools").and_then(|t| t.as_array()) {
                let mut tools = Vec::new();

                for tool_value in tools_array {
                    if let Ok(tool_data) = serde_json::from_value::<Value>(tool_value.clone()) {
                        let tool = McpTool {
                            name: tool_data.get("name")
                                .and_then(|n| n.as_str())
                                .unwrap_or("unknown")
                                .to_string(),
                            description: tool_data.get("description")
                                .and_then(|d| d.as_str())
                                .unwrap_or("")
                                .to_string(),
                            parameters: tool_data.get("inputSchema")
                                .cloned()
                                .unwrap_or(json!({})),
                            server_name: self.server.name.clone(),
                        };
                        tools.push(tool);
                    }
                }

                return Ok(tools);
            }
        }

        Ok(Vec::new())
    }

    async fn list_resources(&self) -> ZekeResult<Vec<McpResource>> {
        let response = self.make_request("resources/list", None).await?;

        if let Some(result) = response.result {
            if let Some(resources_array) = result.get("resources").and_then(|r| r.as_array()) {
                let mut resources = Vec::new();

                for resource_value in resources_array {
                    if let Ok(resource_data) = serde_json::from_value::<Value>(resource_value.clone()) {
                        let resource = McpResource {
                            name: resource_data.get("name")
                                .and_then(|n| n.as_str())
                                .unwrap_or("unknown")
                                .to_string(),
                            description: resource_data.get("description")
                                .and_then(|d| d.as_str())
                                .unwrap_or("")
                                .to_string(),
                            uri: resource_data.get("uri")
                                .and_then(|u| u.as_str())
                                .unwrap_or("")
                                .to_string(),
                            mime_type: resource_data.get("mimeType")
                                .and_then(|m| m.as_str())
                                .map(|s| s.to_string()),
                            server_name: self.server.name.clone(),
                        };
                        resources.push(resource);
                    }
                }

                return Ok(resources);
            }
        }

        Ok(Vec::new())
    }

    async fn call_tool(&self, tool_name: &str, arguments: Value) -> ZekeResult<Value> {
        let params = json!({
            "name": tool_name,
            "arguments": arguments
        });

        let response = self.make_request("tools/call", Some(params)).await?;

        response.result
            .ok_or_else(|| ZekeError::provider("Tool call returned no result".to_string()))
    }

    async fn read_resource(&self, uri: &str) -> ZekeResult<Value> {
        let params = json!({
            "uri": uri
        });

        let response = self.make_request("resources/read", Some(params)).await?;

        response.result
            .ok_or_else(|| ZekeError::provider("Resource read returned no result".to_string()))
    }

    fn get_server_info(&self) -> &McpServer {
        &self.server
    }
}

pub struct McpManager {
    servers: RwLock<HashMap<String, Arc<dyn McpServerConnection>>>,
    available_tools: RwLock<HashMap<String, McpTool>>,
    available_resources: RwLock<HashMap<String, McpResource>>,
}

impl McpManager {
    pub fn new() -> Self {
        Self {
            servers: RwLock::new(HashMap::new()),
            available_tools: RwLock::new(HashMap::new()),
            available_resources: RwLock::new(HashMap::new()),
        }
    }

    pub async fn add_server(&self, server: McpServer) -> ZekeResult<()> {
        let connection = Arc::new(HttpMcpConnection::new(server.clone()));

        // Try to connect
        connection.connect().await?;

        // Load tools and resources
        let tools = connection.list_tools().await?;
        let resources = connection.list_resources().await?;

        // Store connection and its capabilities
        {
            let mut servers = self.servers.write().await;
            servers.insert(server.name.clone(), connection);
        }

        {
            let mut available_tools = self.available_tools.write().await;
            for tool in tools {
                let tool_key = format!("{}::{}", tool.server_name, tool.name);
                available_tools.insert(tool_key, tool);
            }
        }

        {
            let mut available_resources = self.available_resources.write().await;
            for resource in resources {
                let resource_key = format!("{}::{}", resource.server_name, resource.name);
                available_resources.insert(resource_key, resource);
            }
        }

        let tools_count = self.available_tools.read().await.len();
        let resources_count = self.available_resources.read().await.len();
        info!("Added MCP server: {} with {} tools and {} resources",
              server.name, tools_count, resources_count);

        Ok(())
    }

    pub async fn remove_server(&self, server_name: &str) -> ZekeResult<()> {
        {
            let mut servers = self.servers.write().await;
            if let Some(connection) = servers.remove(server_name) {
                let _ = connection.disconnect().await;
            }
        }

        // Remove tools and resources from this server
        {
            let mut available_tools = self.available_tools.write().await;
            available_tools.retain(|key, _| !key.starts_with(&format!("{}::", server_name)));
        }

        {
            let mut available_resources = self.available_resources.write().await;
            available_resources.retain(|key, _| !key.starts_with(&format!("{}::", server_name)));
        }

        info!("Removed MCP server: {}", server_name);
        Ok(())
    }

    pub async fn call_tool(&self, server_name: &str, tool_name: &str, arguments: Value) -> ZekeResult<Value> {
        let servers = self.servers.read().await;

        let connection = servers.get(server_name)
            .ok_or_else(|| ZekeError::invalid_input(format!("MCP server '{}' not found", server_name)))?;

        connection.call_tool(tool_name, arguments).await
    }

    pub async fn read_resource(&self, server_name: &str, uri: &str) -> ZekeResult<Value> {
        let servers = self.servers.read().await;

        let connection = servers.get(server_name)
            .ok_or_else(|| ZekeError::invalid_input(format!("MCP server '{}' not found", server_name)))?;

        connection.read_resource(uri).await
    }

    pub async fn list_available_tools(&self) -> Vec<McpTool> {
        let tools = self.available_tools.read().await;
        tools.values().cloned().collect()
    }

    pub async fn list_available_resources(&self) -> Vec<McpResource> {
        let resources = self.available_resources.read().await;
        resources.values().cloned().collect()
    }

    pub async fn get_server_status(&self) -> Vec<(String, bool)> {
        let servers = self.servers.read().await;
        let mut status = Vec::new();

        for (name, connection) in servers.iter() {
            // Simple connectivity check - in reality you'd want more sophisticated health checks
            let is_connected = true; // Placeholder
            status.push((name.clone(), is_connected));
        }

        status
    }

    pub async fn create_default_servers() -> Vec<McpServer> {
        vec![
            McpServer {
                name: "filesystem".to_string(),
                url: "http://localhost:8080/mcp".to_string(),
                description: Some("Local filesystem access via MCP".to_string()),
                capabilities: vec!["files".to_string(), "directories".to_string()],
                auth_token: None,
                timeout: Duration::from_secs(10),
            },
            McpServer {
                name: "google-drive".to_string(),
                url: "http://localhost:8081/mcp".to_string(),
                description: Some("Google Drive integration via MCP".to_string()),
                capabilities: vec!["documents".to_string(), "spreadsheets".to_string()],
                auth_token: None,
                timeout: Duration::from_secs(15),
            },
            McpServer {
                name: "slack".to_string(),
                url: "http://localhost:8082/mcp".to_string(),
                description: Some("Slack workspace integration via MCP".to_string()),
                capabilities: vec!["messages".to_string(), "channels".to_string()],
                auth_token: None,
                timeout: Duration::from_secs(10),
            },
        ]
    }
}

impl Default for McpManager {
    fn default() -> Self {
        Self::new()
    }
}