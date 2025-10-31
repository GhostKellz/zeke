// LSP Protocol Types
// Based on Language Server Protocol Specification 3.17

const std = @import("std");

/// LSP Position (line, character)
pub const Position = struct {
    line: u32,
    character: u32,
};

/// LSP Range (start, end)
pub const Range = struct {
    start: Position,
    end: Position,
};

/// LSP Location (uri, range)
pub const Location = struct {
    uri: []const u8,
    range: Range,
};

/// Diagnostic severity levels
pub const DiagnosticSeverity = enum(u8) {
    @"error" = 1,
    warning = 2,
    information = 3,
    hint = 4,
};

/// LSP Diagnostic
pub const Diagnostic = struct {
    range: Range,
    severity: ?DiagnosticSeverity,
    code: ?[]const u8,
    source: ?[]const u8,
    message: []const u8,
    relatedInformation: ?[]const u8,

    pub fn deinit(self: *Diagnostic, allocator: std.mem.Allocator) void {
        if (self.code) |code| allocator.free(code);
        if (self.source) |source| allocator.free(source);
        allocator.free(self.message);
        if (self.relatedInformation) |info| allocator.free(info);
    }
};

/// Completion item kind
pub const CompletionItemKind = enum(u8) {
    text = 1,
    method = 2,
    function = 3,
    constructor = 4,
    field = 5,
    variable = 6,
    class = 7,
    interface = 8,
    module = 9,
    property = 10,
    unit = 11,
    value = 12,
    enum_type = 13,
    keyword = 14,
    snippet = 15,
    color = 16,
    file = 17,
    reference = 18,
    folder = 19,
    enum_member = 20,
    constant = 21,
    struct_type = 22,
    event = 23,
    operator = 24,
    type_parameter = 25,
};

/// Completion item
pub const CompletionItem = struct {
    label: []const u8,
    kind: ?CompletionItemKind,
    detail: ?[]const u8,
    documentation: ?[]const u8,
    insertText: ?[]const u8,

    pub fn deinit(self: *CompletionItem, allocator: std.mem.Allocator) void {
        allocator.free(self.label);
        if (self.detail) |detail| allocator.free(detail);
        if (self.documentation) |doc| allocator.free(doc);
        if (self.insertText) |text| allocator.free(text);
    }
};

/// Hover response
pub const Hover = struct {
    contents: []const u8,
    range: ?Range,

    pub fn deinit(self: *Hover, allocator: std.mem.Allocator) void {
        allocator.free(self.contents);
    }
};

/// Symbol kind
pub const SymbolKind = enum(u8) {
    file = 1,
    module = 2,
    namespace = 3,
    package = 4,
    class = 5,
    method = 6,
    property = 7,
    field = 8,
    constructor = 9,
    enum_type = 10,
    interface = 11,
    function = 12,
    variable = 13,
    constant = 14,
    string = 15,
    number = 16,
    boolean = 17,
    array = 18,
    object = 19,
    key = 20,
    null = 21,
    enum_member = 22,
    struct_type = 23,
    event = 24,
    operator = 25,
    type_parameter = 26,
};

/// Document symbol
pub const DocumentSymbol = struct {
    name: []const u8,
    kind: SymbolKind,
    range: Range,
    selectionRange: Range,
    detail: ?[]const u8,
    children: ?[]DocumentSymbol,

    pub fn deinit(self: *DocumentSymbol, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.detail) |detail| allocator.free(detail);
        if (self.children) |children| {
            for (children) |*child| {
                child.deinit(allocator);
            }
            allocator.free(children);
        }
    }
};

/// Text document identifier
pub const TextDocumentIdentifier = struct {
    uri: []const u8,
};

/// Text document position params
pub const TextDocumentPositionParams = struct {
    textDocument: TextDocumentIdentifier,
    position: Position,
};

/// LSP Server capabilities
pub const ServerCapabilities = struct {
    textDocumentSync: ?u8,
    completionProvider: bool,
    hoverProvider: bool,
    definitionProvider: bool,
    referencesProvider: bool,
    documentSymbolProvider: bool,
    workspaceSymbolProvider: bool,
    diagnosticProvider: bool,
};

/// LSP Initialize result
pub const InitializeResult = struct {
    capabilities: ServerCapabilities,
    serverInfo: ?struct {
        name: []const u8,
        version: ?[]const u8,
    },
};

/// LSP Server configuration
pub const ServerConfig = struct {
    name: []const u8, // e.g., "zls", "rust-analyzer"
    command: []const u8, // e.g., "zls", "rust-analyzer"
    args: []const []const u8,
    filetypes: []const []const u8, // e.g., [".zig"]
    rootPatterns: []const []const u8, // e.g., ["build.zig"]
};

/// Get default LSP server configs
pub fn getDefaultServers(allocator: std.mem.Allocator) ![]ServerConfig {
    var servers = std.ArrayList(ServerConfig).empty;

    // Zig Language Server
    try servers.append(allocator, .{
        .name = try allocator.dupe(u8, "zls"),
        .command = try allocator.dupe(u8, "zls"),
        .args = &[_][]const u8{},
        .filetypes = &[_][]const u8{".zig"},
        .rootPatterns = &[_][]const u8{"build.zig"},
    });

    // Rust Analyzer
    try servers.append(allocator, .{
        .name = try allocator.dupe(u8, "rust-analyzer"),
        .command = try allocator.dupe(u8, "rust-analyzer"),
        .args = &[_][]const u8{},
        .filetypes = &[_][]const u8{".rs"},
        .rootPatterns = &[_][]const u8{"Cargo.toml"},
    });

    // TypeScript Language Server
    try servers.append(allocator, .{
        .name = try allocator.dupe(u8, "typescript-language-server"),
        .command = try allocator.dupe(u8, "typescript-language-server"),
        .args = &[_][]const u8{"--stdio"},
        .filetypes = &[_][]const u8{ ".ts", ".tsx", ".js", ".jsx" },
        .rootPatterns = &[_][]const u8{ "package.json", "tsconfig.json" },
    });

    // Python Language Server (Pyright)
    try servers.append(allocator, .{
        .name = try allocator.dupe(u8, "pyright"),
        .command = try allocator.dupe(u8, "pyright-langserver"),
        .args = &[_][]const u8{"--stdio"},
        .filetypes = &[_][]const u8{".py"},
        .rootPatterns = &[_][]const u8{ "pyproject.toml", "setup.py", "requirements.txt" },
    });

    // Go Language Server (gopls)
    try servers.append(allocator, .{
        .name = try allocator.dupe(u8, "gopls"),
        .command = try allocator.dupe(u8, "gopls"),
        .args = &[_][]const u8{},
        .filetypes = &[_][]const u8{".go"},
        .rootPatterns = &[_][]const u8{ "go.mod", "go.sum" },
    });

    // C/C++ Language Server (clangd)
    try servers.append(allocator, .{
        .name = try allocator.dupe(u8, "clangd"),
        .command = try allocator.dupe(u8, "clangd"),
        .args = &[_][]const u8{},
        .filetypes = &[_][]const u8{ ".c", ".cpp", ".h", ".hpp" },
        .rootPatterns = &[_][]const u8{ "compile_commands.json", ".clangd" },
    });

    return servers.toOwnedSlice(allocator);
}
