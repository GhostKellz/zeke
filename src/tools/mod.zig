//! Tools Module - Smart Operations
//!
//! High-level tools that leverage the GhostKellz ecosystem

pub const smart_git = @import("smart_git.zig");
pub const smart_edit = @import("smart_edit.zig");

// Re-export main types
pub const SmartGit = smart_git.SmartGit;
pub const SmartEdit = smart_edit.SmartEdit;

test {
    @import("std").testing.refAllDecls(@This());
}
