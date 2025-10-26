const std = @import("std");
const zeke = @import("zeke");

pub fn run(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    if (args.len == 0) {
        try printUsage();
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "dump")) {
        const format = if (args.len > 1) args[1] else "toml";
        try dumpConfig(allocator, format);
    } else if (std.mem.eql(u8, subcommand, "show")) {
        try showConfig(allocator);
    } else if (std.mem.eql(u8, subcommand, "path")) {
        try showConfigPath(allocator);
    } else {
        try printUsage();
    }
}

fn printUsage() !void {
    std.debug.print(
        \\Usage: zeke config <subcommand>
        \\
        \\Subcommands:
        \\  dump [format]  - Dump configuration (formats: json, toml, pretty)
        \\  show           - Show current configuration in human-readable format
        \\  path           - Show configuration file path
        \\
        \\Examples:
        \\  zeke config dump json       # Dump as JSON (for nvim integration)
        \\  zeke config dump toml       # Dump as TOML
        \\  zeke config show            # Pretty-print configuration
        \\  zeke config path            # Show config file location
        \\
    , .{});
}

fn dumpConfig(allocator: std.mem.Allocator, format: []const u8) !void {
    // Load configuration
    var config = try zeke.config.loadConfig(allocator);
    defer config.deinit();

    if (std.mem.eql(u8, format, "json") or std.mem.eql(u8, format, "--json")) {
        dumpAsJson(allocator, &config);
    } else if (std.mem.eql(u8, format, "toml")) {
        dumpAsToml(allocator, &config);
    } else if (std.mem.eql(u8, format, "pretty")) {
        try showConfig(allocator);
    } else {
        std.debug.print("Unknown format: {s}\n", .{format});
        std.debug.print("Supported formats: json, toml, pretty\n", .{});
    }
}

fn dumpAsJson(_: std.mem.Allocator, config: *const zeke.config.Config) void {
    // Build JSON object manually for clean output
    std.debug.print("{{\n", .{});

    // Default provider and model
    std.debug.print("  \"default\": {{\n", .{});
    std.debug.print("    \"provider\": \"{s}\",\n", .{config.providers.default_provider});
    std.debug.print("    \"model\": \"{s}\"\n", .{config.default_model});
    std.debug.print("  }},\n", .{});

    // Providers configuration
    std.debug.print("  \"providers\": {{\n", .{});

    // OpenAI
    std.debug.print("    \"openai\": {{\n", .{});
    std.debug.print("      \"enabled\": true,\n", .{});
    std.debug.print("      \"endpoint\": \"{s}\",\n", .{config.endpoints.openai});
    std.debug.print("      \"model\": \"gpt-4-turbo\"\n", .{});
    std.debug.print("    }},\n", .{});

    // Claude
    std.debug.print("    \"claude\": {{\n", .{});
    std.debug.print("      \"enabled\": true,\n", .{});
    std.debug.print("      \"endpoint\": \"{s}\",\n", .{config.endpoints.claude});
    std.debug.print("      \"model\": \"claude-3-5-sonnet-20241022\"\n", .{});
    std.debug.print("    }},\n", .{});

    // xAI
    std.debug.print("    \"xai\": {{\n", .{});
    std.debug.print("      \"enabled\": true,\n", .{});
    std.debug.print("      \"endpoint\": \"{s}\",\n", .{config.endpoints.xai});
    std.debug.print("      \"model\": \"grok-beta\"\n", .{});
    std.debug.print("    }},\n", .{});

    // Google
    std.debug.print("    \"google\": {{\n", .{});
    std.debug.print("      \"enabled\": true,\n", .{});
    std.debug.print("      \"endpoint\": \"{s}\",\n", .{config.endpoints.google});
    std.debug.print("      \"model\": \"gemini-pro\"\n", .{});
    std.debug.print("    }},\n", .{});

    // Azure
    std.debug.print("    \"azure\": {{\n", .{});
    std.debug.print("      \"enabled\": true,\n", .{});
    std.debug.print("      \"endpoint\": \"{s}\",\n", .{config.endpoints.azure});
    std.debug.print("      \"model\": \"gpt-4\"\n", .{});
    std.debug.print("    }},\n", .{});

    // Ollama
    std.debug.print("    \"ollama\": {{\n", .{});
    std.debug.print("      \"enabled\": true,\n", .{});
    std.debug.print("      \"endpoint\": \"{s}\",\n", .{config.endpoints.ollama});
    std.debug.print("      \"model\": \"qwen2.5-coder:7b\"\n", .{});
    std.debug.print("    }},\n", .{});

    // GitHub Copilot
    std.debug.print("    \"copilot\": {{\n", .{});
    std.debug.print("      \"enabled\": true,\n", .{});
    std.debug.print("      \"model\": \"gpt-4\"\n", .{});
    std.debug.print("    }}\n", .{});
    std.debug.print("  }},\n", .{});

    // Features
    std.debug.print("  \"features\": {{\n", .{});
    std.debug.print("    \"streaming\": {},\n", .{config.streaming.enabled});
    std.debug.print("    \"file_operations\": true,\n", .{});
    std.debug.print("    \"realtime\": {}\n", .{config.realtime.enabled});
    std.debug.print("  }},\n", .{});

    // Model aliases
    std.debug.print("  \"model_aliases\": {{\n", .{});
    std.debug.print("    \"fast\": \"{s}\",\n", .{config.model_aliases.fast});
    std.debug.print("    \"smart\": \"{s}\",\n", .{config.model_aliases.smart});
    std.debug.print("    \"balanced\": \"{s}\",\n", .{config.model_aliases.balanced});
    std.debug.print("    \"local\": \"{s}\"\n", .{config.model_aliases.local});
    std.debug.print("  }},\n", .{});

    // Nvim-specific settings
    std.debug.print("  \"nvim\": {{\n", .{});
    std.debug.print("    \"enabled\": true,\n", .{});
    std.debug.print("    \"auto_complete\": true,\n", .{});
    std.debug.print("    \"inline_suggestions\": true,\n", .{});
    std.debug.print("    \"provider_fallback\": [\"copilot\", \"ollama\", \"google\", \"claude\", \"openai\", \"xai\"]\n", .{});
    std.debug.print("  }}\n", .{});

    std.debug.print("}}\n", .{});
}

fn dumpAsToml(allocator: std.mem.Allocator, config: *const zeke.config.Config) void {
    _ = allocator;

    std.debug.print("[default]\n", .{});
    std.debug.print("provider = \"{s}\"\n", .{config.providers.default_provider});
    std.debug.print("model = \"{s}\"\n\n", .{config.default_model});

    std.debug.print("[providers]\n", .{});
    std.debug.print("default_provider = \"{s}\"\n", .{config.providers.default_provider});
    std.debug.print("fallback_enabled = {}\n", .{config.providers.fallback_enabled});
    std.debug.print("auto_switch_on_failure = {}\n\n", .{config.providers.auto_switch_on_failure});

    std.debug.print("[providers.openai]\n", .{});
    std.debug.print("enabled = true\n", .{});
    std.debug.print("model = \"gpt-4-turbo\"\n\n", .{});

    std.debug.print("[providers.claude]\n", .{});
    std.debug.print("enabled = true\n", .{});
    std.debug.print("model = \"claude-3-5-sonnet-20241022\"\n\n", .{});

    std.debug.print("[providers.ollama]\n", .{});
    std.debug.print("enabled = true\n", .{});
    std.debug.print("model = \"qwen2.5-coder:7b\"\n", .{});
    std.debug.print("host = \"{s}\"\n\n", .{config.endpoints.ollama});

    std.debug.print("[features]\n", .{});
    std.debug.print("streaming = {}\n", .{config.streaming.enabled});
    std.debug.print("file_operations = true\n\n", .{});

    std.debug.print("[model_aliases]\n", .{});
    std.debug.print("fast = \"{s}\"\n", .{config.model_aliases.fast});
    std.debug.print("smart = \"{s}\"\n", .{config.model_aliases.smart});
    std.debug.print("local = \"{s}\"\n\n", .{config.model_aliases.local});

    std.debug.print("[nvim]\n", .{});
    std.debug.print("enabled = true\n", .{});
    std.debug.print("auto_complete = true\n", .{});
    std.debug.print("inline_suggestions = true\n", .{});
    std.debug.print("provider_fallback = [\"copilot\", \"ollama\", \"google\", \"claude\", \"openai\", \"xai\"]\n", .{});
}

fn showConfig(allocator: std.mem.Allocator) !void {
    var config = try zeke.config.loadConfig(allocator);
    defer config.deinit();

    std.debug.print("\n📋 Zeke Configuration\n", .{});
    std.debug.print("================================================================\n\n", .{});

    std.debug.print("Default Provider: {s}\n", .{config.providers.default_provider});
    std.debug.print("Default Model:    {s}\n\n", .{config.default_model});

    std.debug.print("Model Aliases:\n", .{});
    std.debug.print("  fast:     {s}\n", .{config.model_aliases.fast});
    std.debug.print("  smart:    {s}\n", .{config.model_aliases.smart});
    std.debug.print("  balanced: {s}\n", .{config.model_aliases.balanced});
    std.debug.print("  local:    {s}\n\n", .{config.model_aliases.local});

    std.debug.print("Features:\n", .{});
    std.debug.print("  Streaming:        {}\n", .{config.streaming.enabled});
    std.debug.print("  File Operations:  true\n", .{});
    std.debug.print("  Real-time:        {}\n\n", .{config.realtime.enabled});

    std.debug.print("Provider Endpoints:\n", .{});
    std.debug.print("  OpenAI:  {s}\n", .{config.endpoints.openai});
    std.debug.print("  Claude:  {s}\n", .{config.endpoints.claude});
    std.debug.print("  xAI:     {s}\n", .{config.endpoints.xai});
    std.debug.print("  Google:  {s}\n", .{config.endpoints.google});
    std.debug.print("  Ollama:  {s}\n", .{config.endpoints.ollama});
    std.debug.print("\n", .{});
}

fn showConfigPath(allocator: std.mem.Allocator) !void {
    const home = std.posix.getenv("HOME") orelse {
        std.debug.print("Error: HOME environment variable not set\n", .{});
        return;
    };

    const config_path = try std.fmt.allocPrint(
        allocator,
        "{s}/.config/zeke/zeke.toml",
        .{home}
    );
    defer allocator.free(config_path);

    std.debug.print("{s}\n", .{config_path});
}
