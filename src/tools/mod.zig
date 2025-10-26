//! Tools Module - Smart Operations
//!
//! High-level tools that leverage the GhostKellz ecosystem
//! Comprehensive tooling inspired by Gemini CLI and Claude Code

pub const smart_git = @import("smart_git.zig");
pub const smart_edit = @import("smart_edit.zig");
pub const editor = @import("editor.zig");
pub const codegen = @import("codegen.zig");
pub const registry = @import("registry.zig");
pub const web = @import("web.zig");

// Re-export main types
pub const SmartGit = smart_git.SmartGit;
pub const SmartEdit = smart_edit.SmartEdit;
pub const FileEditor = editor.FileEditor;
pub const Checkpointer = editor.Checkpointer;
pub const CodeGenerator = codegen.CodeGenerator;
pub const ToolRegistry = registry.ToolRegistry;
pub const Tool = registry.Tool;
pub const WebTools = web.WebTools;

test {
    @import("std").testing.refAllDecls(@This());
}
