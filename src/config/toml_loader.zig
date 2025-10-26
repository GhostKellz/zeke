const std = @import("std");
const zontom = @import("zontom");
const config_mod = @import("mod.zig");

/// Load Zeke configuration from TOML file using zontom
pub fn loadFromToml(allocator: std.mem.Allocator, file_path: []const u8) !config_mod.Config {
    // Read the TOML file
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const contents = try allocator.alloc(u8, file_size);
    defer allocator.free(contents);

    _ = try file.readAll(contents);

    // Parse TOML
    var table = try zontom.parse(allocator, contents);
    defer table.deinit();

    // Create config with defaults
    var cfg = config_mod.Config.init(allocator);

    // Parse [default] section
    if (table.get("default")) |default_val| {
        if (default_val == .table) {
            const default_section = default_val.table;
            if (default_section.get("provider")) |prov_val| {
                if (prov_val == .string) {
                    cfg.providers.default_provider = try allocator.dupe(u8, prov_val.string);
                }
            }
            if (default_section.get("model")) |model_val| {
                if (model_val == .string) {
                    cfg.default_model = try allocator.dupe(u8, model_val.string);
                }
            }
        }
    }

    // TODO: Parse provider sections with proper type checking
    // For now, add default models
    try cfg.addDefaultModels();

    return cfg;
}

test "load config from TOML" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[default]
        \\provider = "ollama"
        \\model = "qwen2.5-coder:7b"
        \\
        \\[providers.ollama]
        \\enabled = true
        \\model = "qwen2.5-coder:7b"
        \\host = "http://localhost:11434"
        \\
        \\[providers.openai]
        \\enabled = true
        \\model = "gpt-4-turbo"
        \\temperature = 0.7
        \\max_tokens = 4096
    ;

    // Write test file
    const test_file = "test_config.toml";
    {
        const file = try std.fs.cwd().createFile(test_file, .{});
        defer file.close();
        try file.writeAll(toml_content);
    }
    defer std.fs.cwd().deleteFile(test_file) catch {};

    // Load config
    var cfg = try loadFromToml(allocator, test_file);
    defer cfg.deinit();

    // Verify defaults
    try std.testing.expectEqualStrings("ollama", cfg.providers.default_provider);
    try std.testing.expectEqualStrings("qwen2.5-coder:7b", cfg.default_model);

    // Verify models were loaded
    try std.testing.expect(cfg.models.items.len >= 2);
}
