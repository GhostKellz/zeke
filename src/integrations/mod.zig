//! Integration Module - GhostKellz Ecosystem
//!
//! This module provides integrations with the GhostKellz ecosystem:
//! - Zap: AI-powered Git operations
//! - Grove: AST-based code intelligence
//! - Ghostlang: Plugin runtime (future)
//! - Rune: MCP protocol support (future)

pub const zap = @import("zap.zig");
pub const grove = @import("grove.zig");

// Re-export main types for convenience
pub const ZapGit = zap.ZapGit;
pub const GroveAST = grove.GroveAST;

test {
    @import("std").testing.refAllDecls(@This());
}
