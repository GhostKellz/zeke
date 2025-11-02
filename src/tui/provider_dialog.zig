const std = @import("std");
const api = @import("../api/client.zig");

/// Provider information for display
pub const ProviderInfo = struct {
    name: []const u8,
    display_name: []const u8,
    is_authenticated: bool,
    is_available: bool,
    models: []const []const u8,

    pub fn deinit(self: *ProviderInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.display_name);
        for (self.models) |model| {
            allocator.free(model);
        }
        allocator.free(self.models);
    }
};

/// Provider selection dialog
pub const ProviderDialog = struct {
    allocator: std.mem.Allocator,
    providers: std.array_list.AlignedManaged(ProviderInfo, null),
    selected_index: usize,

    pub fn init(allocator: std.mem.Allocator) ProviderDialog {
        return ProviderDialog{
            .allocator = allocator,
            .providers = std.array_list.AlignedManaged(ProviderInfo, null).init(allocator),
            .selected_index = 0,
        };
    }

    pub fn deinit(self: *ProviderDialog) void {
        for (self.providers.items) |*prov| {
            prov.deinit(self.allocator);
        }
        self.providers.deinit();
    }

    /// Add a provider to the dialog
    pub fn addProvider(
        self: *ProviderDialog,
        name: []const u8,
        display_name: []const u8,
        is_authenticated: bool,
        is_available: bool,
        models: []const []const u8,
    ) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        const owned_display = try self.allocator.dupe(u8, display_name);

        var owned_models = try self.allocator.alloc([]const u8, models.len);
        for (models, 0..) |model, i| {
            owned_models[i] = try self.allocator.dupe(u8, model);
        }

        const info = ProviderInfo{
            .name = owned_name,
            .display_name = owned_display,
            .is_authenticated = is_authenticated,
            .is_available = is_available,
            .models = owned_models,
        };

        try self.providers.append(info);
    }

    /// Move selection up
    pub fn selectPrevious(self: *ProviderDialog) void {
        if (self.selected_index > 0) {
            self.selected_index -= 1;
        }
    }

    /// Move selection down
    pub fn selectNext(self: *ProviderDialog) void {
        if (self.selected_index < self.providers.items.len - 1) {
            self.selected_index += 1;
        }
    }

    /// Get the currently selected provider
    pub fn getSelected(self: *const ProviderDialog) ?*const ProviderInfo {
        if (self.providers.items.len == 0) return null;
        return &self.providers.items[self.selected_index];
    }

    /// Render the provider dialog to a buffer
    pub fn render(self: *const ProviderDialog, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.array_list.AlignedManaged(u8, null).init(allocator);
        defer buf.deinit();

        try buf.appendSlice("╭─ Select Provider ────────────────────────────╮\n");
        try buf.appendSlice("│ Use ↑/↓ to navigate, Enter to select        │\n");
        try buf.appendSlice("├──────────────────────────────────────────────┤\n");

        for (self.providers.items, 0..) |prov, i| {
            const is_selected = (i == self.selected_index);
            const marker = if (is_selected) "▶" else " ";

            // Status indicators
            const auth_indicator = if (prov.is_authenticated) "✓" else "✗";
            const avail_indicator = if (prov.is_available) "●" else "○";

            const line = try std.fmt.allocPrint(
                allocator,
                "│ {s} {s} {s} {s:<20} [{s}]  │\n",
                .{ marker, auth_indicator, avail_indicator, prov.display_name, prov.name },
            );
            defer allocator.free(line);
            try buf.appendSlice(line);
        }

        try buf.appendSlice("├──────────────────────────────────────────────┤\n");
        try buf.appendSlice("│ ✓ = Authenticated   ● = Available           │\n");
        try buf.appendSlice("╰──────────────────────────────────────────────╯\n");

        return try buf.toOwnedSlice();
    }

    /// Write the dialog directly to stdout
    pub fn write(self: *const ProviderDialog, stdout: std.posix.fd_t) !void {
        const rendered = try self.render(self.allocator);
        defer self.allocator.free(rendered);
        _ = try std.posix.write(stdout, rendered);
    }
};

/// Model selection dialog for a specific provider
pub const ModelDialog = struct {
    allocator: std.mem.Allocator,
    provider_name: []const u8,
    models: []const []const u8,
    selected_index: usize,

    pub fn init(allocator: std.mem.Allocator, provider_name: []const u8, models: []const []const u8) !ModelDialog {
        return ModelDialog{
            .allocator = allocator,
            .provider_name = try allocator.dupe(u8, provider_name),
            .models = models, // Borrowed, not owned
            .selected_index = 0,
        };
    }

    pub fn deinit(self: *ModelDialog) void {
        self.allocator.free(self.provider_name);
    }

    pub fn selectPrevious(self: *ModelDialog) void {
        if (self.selected_index > 0) {
            self.selected_index -= 1;
        }
    }

    pub fn selectNext(self: *ModelDialog) void {
        if (self.selected_index < self.models.len - 1) {
            self.selected_index += 1;
        }
    }

    pub fn getSelected(self: *const ModelDialog) ?[]const u8 {
        if (self.models.len == 0) return null;
        return self.models[self.selected_index];
    }

    pub fn render(self: *const ModelDialog, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.array_list.AlignedManaged(u8, null).init(allocator);
        defer buf.deinit();

        const header = try std.fmt.allocPrint(
            allocator,
            "╭─ Select Model for {s} ─────────────────╮\n",
            .{self.provider_name},
        );
        defer allocator.free(header);
        try buf.appendSlice(header);

        try buf.appendSlice("│ Use ↑/↓ to navigate, Enter to select   │\n");
        try buf.appendSlice("├─────────────────────────────────────────┤\n");

        for (self.models, 0..) |model, i| {
            const is_selected = (i == self.selected_index);
            const marker = if (is_selected) "▶" else " ";

            const line = try std.fmt.allocPrint(
                allocator,
                "│ {s} {s:<35} │\n",
                .{ marker, model },
            );
            defer allocator.free(line);
            try buf.appendSlice(line);
        }

        try buf.appendSlice("╰─────────────────────────────────────────╯\n");

        return try buf.toOwnedSlice();
    }

    pub fn write(self: *const ModelDialog, stdout: std.posix.fd_t) !void {
        const rendered = try self.render(self.allocator);
        defer self.allocator.free(rendered);
        _ = try std.posix.write(stdout, rendered);
    }
};

// Tests
test "provider dialog basic" {
    const allocator = std.testing.allocator;

    var dialog = ProviderDialog.init(allocator);
    defer dialog.deinit();

    const models = [_][]const u8{ "model1", "model2" };
    try dialog.addProvider("ollama", "Ollama", true, true, &models);
    try dialog.addProvider("claude", "Claude", false, true, &models);

    try std.testing.expectEqual(@as(usize, 2), dialog.providers.items.len);
    try std.testing.expectEqual(@as(usize, 0), dialog.selected_index);

    dialog.selectNext();
    try std.testing.expectEqual(@as(usize, 1), dialog.selected_index);

    dialog.selectPrevious();
    try std.testing.expectEqual(@as(usize, 0), dialog.selected_index);
}

test "model dialog basic" {
    const allocator = std.testing.allocator;

    const models = [_][]const u8{ "gpt-4", "gpt-3.5-turbo" };
    var dialog = try ModelDialog.init(allocator, "OpenAI", &models);
    defer dialog.deinit();

    try std.testing.expectEqual(@as(usize, 0), dialog.selected_index);
    try std.testing.expectEqualStrings("gpt-4", dialog.getSelected().?);

    dialog.selectNext();
    try std.testing.expectEqualStrings("gpt-3.5-turbo", dialog.getSelected().?);
}
