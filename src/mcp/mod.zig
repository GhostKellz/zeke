/// Model Context Protocol (MCP) Client
///
/// Provides communication with MCP servers like Glyph for file operations
/// and other tools via JSON-RPC over stdio or WebSocket.

pub const client = @import("client.zig");
pub const McpClient = client.McpClient;
pub const checkHealth = client.checkHealth;
