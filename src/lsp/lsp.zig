// LSP Module - Main entry point for LSP functionality

const std = @import("std");

pub const types = @import("types.zig");
pub const jsonrpc = @import("jsonrpc.zig");
pub const client = @import("client.zig");

pub const LspClient = client.LspClient;
pub const ServerConfig = types.ServerConfig;
pub const Diagnostic = types.Diagnostic;
pub const DiagnosticSeverity = types.DiagnosticSeverity;
pub const Hover = types.Hover;
pub const Position = types.Position;
pub const Range = types.Range;
pub const Location = types.Location;

/// LSP Manager - Manages multiple LSP servers
pub const LspManager = struct {
    allocator: std.mem.Allocator,
    clients: std.StringHashMap(*LspClient),
    server_configs: []ServerConfig,
    diagnostic_aggregator: ?*@import("diagnostics.zig").DiagnosticAggregator,

    pub fn init(allocator: std.mem.Allocator) !LspManager {
        const configs = try types.getDefaultServers(allocator);

        return LspManager{
            .allocator = allocator,
            .clients = std.StringHashMap(*LspClient).init(allocator),
            .server_configs = configs,
            .diagnostic_aggregator = null,
        };
    }

    /// Enable diagnostic aggregation (optional feature)
    pub fn enableDiagnostics(self: *LspManager) !void {
        if (self.diagnostic_aggregator != null) return;

        const diag_mod = @import("diagnostics.zig");
        const aggregator = try self.allocator.create(diag_mod.DiagnosticAggregator);
        aggregator.* = diag_mod.DiagnosticAggregator.init(self.allocator);
        self.diagnostic_aggregator = aggregator;
    }

    pub fn deinit(self: *LspManager) void {
        var iter = self.clients.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.clients.deinit();

        for (self.server_configs) |*config| {
            self.allocator.free(config.name);
            self.allocator.free(config.command);
            // filetypes and rootPatterns are static const slices, don't free them
        }
        self.allocator.free(self.server_configs);

        if (self.diagnostic_aggregator) |aggregator| {
            aggregator.deinit();
            self.allocator.destroy(aggregator);
        }
    }

    /// Get or create LSP client for a file
    pub fn getClientForFile(self: *LspManager, file_path: []const u8, root_path: []const u8) !?*LspClient {
        const ext = std.fs.path.extension(file_path);

        // Find matching server config
        var matching_config: ?ServerConfig = null;
        for (self.server_configs) |config| {
            for (config.filetypes) |filetype| {
                if (std.mem.eql(u8, ext, filetype)) {
                    matching_config = config;
                    break;
                }
            }
            if (matching_config != null) break;
        }

        if (matching_config == null) {
            std.debug.print("No LSP server found for file type: {s}\n", .{ext});
            return null;
        }

        const config = matching_config.?;

        // Check if client already exists
        if (self.clients.get(config.name)) |existing| {
            return existing;
        }

        // Create new client
        std.debug.print("Creating LSP client for {s}\n", .{config.name});

        const new_client = try self.allocator.create(LspClient);
        new_client.* = try LspClient.init(self.allocator, config, root_path);

        try new_client.start();
        _ = try new_client.initialize();

        try self.clients.put(config.name, new_client);

        return new_client;
    }

    /// Get diagnostics for a file
    pub fn getDiagnosticsForFile(self: *LspManager, file_path: []const u8, root_path: []const u8) ![]Diagnostic {
        const lsp_client = try self.getClientForFile(file_path, root_path) orelse return &[_]Diagnostic{};

        const file_uri = try std.fmt.allocPrint(self.allocator, "file://{s}", .{file_path});
        defer self.allocator.free(file_uri);

        return try lsp_client.getDiagnostics(file_uri);
    }

    /// Get hover information for a position in a file
    pub fn getHoverForPosition(
        self: *LspManager,
        file_path: []const u8,
        root_path: []const u8,
        line: u32,
        character: u32,
    ) !?Hover {
        const lsp_client = try self.getClientForFile(file_path, root_path) orelse return null;

        const file_uri = try std.fmt.allocPrint(self.allocator, "file://{s}", .{file_path});
        defer self.allocator.free(file_uri);

        return try lsp_client.getHover(file_uri, line, character);
    }

    /// Get definition for a position in a file
    pub fn getDefinitionForPosition(
        self: *LspManager,
        file_path: []const u8,
        root_path: []const u8,
        line: u32,
        character: u32,
    ) !?[]types.Location {
        const lsp_client = try self.getClientForFile(file_path, root_path) orelse return null;

        const file_uri = try std.fmt.allocPrint(self.allocator, "file://{s}", .{file_path});
        defer self.allocator.free(file_uri);

        return try lsp_client.getDefinition(file_uri, line, character);
    }

    /// Find references for a position in a file
    pub fn getReferencesForPosition(
        self: *LspManager,
        file_path: []const u8,
        root_path: []const u8,
        line: u32,
        character: u32,
        include_declaration: bool,
    ) !?[]types.Location {
        const lsp_client = try self.getClientForFile(file_path, root_path) orelse return null;

        const file_uri = try std.fmt.allocPrint(self.allocator, "file://{s}", .{file_path});
        defer self.allocator.free(file_uri);

        return try lsp_client.findReferences(file_uri, line, character, include_declaration);
    }

    /// Shutdown all LSP servers
    pub fn shutdownAll(self: *LspManager) !void {
        var iter = self.clients.iterator();
        while (iter.next()) |entry| {
            std.debug.print("Shutting down LSP client: {s}\n", .{entry.key_ptr.*});
            try entry.value_ptr.*.shutdown();
        }
    }
};

/// Check if LSP server is available for a file type
pub fn isServerAvailable(allocator: std.mem.Allocator, file_extension: []const u8) !bool {
    const configs = try types.getDefaultServers(allocator);
    defer {
        for (configs) |*config| {
            allocator.free(config.name);
            allocator.free(config.command);
        }
        allocator.free(configs);
    }

    for (configs) |config| {
        for (config.filetypes) |filetype| {
            if (std.mem.eql(u8, file_extension, filetype)) {
                // Check if command exists
                const result = std.process.Child.run(.{
                    .allocator = allocator,
                    .argv = &[_][]const u8{ "which", config.command },
                }) catch return false;

                defer {
                    allocator.free(result.stdout);
                    allocator.free(result.stderr);
                }

                return result.term.Exited == 0;
            }
        }
    }

    return false;
}

/// Get available LSP servers
pub fn getAvailableServers(allocator: std.mem.Allocator) ![]const []const u8 {
    var available = std.ArrayList([]const u8).empty;
    defer available.deinit(allocator);

    const configs = try types.getDefaultServers(allocator);
    defer {
        for (configs) |*config| {
            allocator.free(config.name);
            allocator.free(config.command);
        }
        allocator.free(configs);
    }

    for (configs) |config| {
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "which", config.command },
        }) catch continue;

        defer {
            allocator.free(result.stdout);
            allocator.free(result.stderr);
        }

        if (result.term.Exited == 0) {
            try available.append(allocator, try allocator.dupe(u8, config.name));
        }
    }

    return available.toOwnedSlice(allocator);
}

// Tests
test "LSP manager initialization" {
    const allocator = std.testing.allocator;

    var manager = try LspManager.init(allocator);
    defer manager.deinit();

    try std.testing.expect(manager.server_configs.len > 0);
}

test "check server availability" {
    const allocator = std.testing.allocator;

    // Test with a common file extension
    const available = try isServerAvailable(allocator, ".zig");
    _ = available; // May or may not be available depending on system
}
