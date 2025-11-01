const std = @import("std");
const zeke = @import("zeke");
const ollama = zeke.providers.ollama;
const routing_db = zeke.db;
const mcp = zeke.mcp;
const config = zeke.config;

pub const Status = enum { ok, warning, err };

pub const DoctorResult = struct {
    system: []const u8,
    status: Status,
    message: []const u8,
    details: ?[]const u8 = null,
};

pub const DoctorOptions = struct {
    check_ollama: bool = true,
    check_omen: bool = true,
    check_mcp: bool = true,
    check_db: bool = true,
    check_providers: bool = true,
    verbose: bool = false,
};

pub const Doctor = struct {
    allocator: std.mem.Allocator,
    results: std.ArrayList(DoctorResult),

    pub fn init(allocator: std.mem.Allocator) Doctor {
        return .{
            .allocator = allocator,
            .results = std.ArrayList(DoctorResult).empty,
        };
    }

    pub fn deinit(self: *Doctor) void {
        for (self.results.items) |result| {
            self.allocator.free(result.system);
            self.allocator.free(result.message);
            if (result.details) |details| {
                self.allocator.free(details);
            }
        }
        self.results.deinit(self.allocator);
    }

    fn addResult(self: *Doctor, system: []const u8, status: Status, message: []const u8, details: ?[]const u8) !void {
        try self.results.append(self.allocator, .{
            .system = try self.allocator.dupe(u8, system),
            .status = status,
            .message = try self.allocator.dupe(u8, message),
            .details = if (details) |d| try self.allocator.dupe(u8, d) else null,
        });
    }

    pub fn runChecks(self: *Doctor, options: DoctorOptions) !void {
        std.debug.print("\n🩺 Zeke Health Check\n", .{});
        std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

        // Check database
        if (options.check_db) {
            try self.checkDatabase(options.verbose);
        }

        // Check Ollama
        if (options.check_ollama) {
            try self.checkOllama(options.verbose);
        }

        // Check OMEN
        if (options.check_omen) {
            try self.checkOmen(options.verbose);
        }

        // Check MCP (Glyph)
        if (options.check_mcp) {
            try self.checkMcp(options.verbose);
        }

        // Check other providers
        if (options.check_providers) {
            try self.checkProviders(options.verbose);
        }

        // Print summary
        try self.printSummary();
    }

    fn checkDatabase(self: *Doctor, verbose: bool) !void {
        std.debug.print("📊 Checking zqlite database...\n", .{});

        const db_path = getDbPath(self.allocator) catch |e| {
            try self.addResult("Database", .err, "Failed to determine database path", null);
            std.debug.print("  ❌ Database path error: {}\n\n", .{e});
            return;
        };
        defer self.allocator.free(db_path);

        // Try to open/create database
        var db = routing_db.RoutingDB.init(self.allocator, db_path) catch |e| {
            const msg = try std.fmt.allocPrint(self.allocator, "Failed to open database: {}", .{e});
            defer self.allocator.free(msg);
            try self.addResult("Database", .err, msg, null);
            std.debug.print("  ❌ {s}\n\n", .{msg});
            return;
        };
        defer db.deinit();

        try self.addResult("Database", .ok, "Database initialized successfully", db_path);
        std.debug.print("  ✅ Database: {s}\n", .{db_path});

        // Count routing decisions
        const stats = routing_db.getRecentStats(&db, self.allocator, null, 1000) catch |e| {
            std.debug.print("  ⚠️  Could not read stats: {}\n", .{e});
            return;
        };
        defer self.allocator.free(stats);

        if (verbose or stats.len > 0) {
            std.debug.print("  📈 Routing decisions: {d} recorded\n", .{stats.len});
        }

        std.debug.print("\n", .{});
    }

    fn checkOllama(self: *Doctor, verbose: bool) !void {
        std.debug.print("🦙 Checking Ollama...\n", .{});

        const ollama_host = std.posix.getenv("OLLAMA_HOST") orelse "http://localhost:11434";

        var provider = ollama.OllamaProvider.init(self.allocator, ollama_host, 5000) catch |e| {
            const msg = try std.fmt.allocPrint(self.allocator, "Failed to initialize Ollama client: {}", .{e});
            defer self.allocator.free(msg);
            try self.addResult("Ollama", .err, msg, null);
            std.debug.print("  ❌ {s}\n\n", .{msg});
            return;
        };
        defer provider.deinit();

        // Health check
        const is_healthy = provider.health() catch false;
        if (!is_healthy) {
            const msg = try std.fmt.allocPrint(self.allocator, "Ollama is not responding at {s}", .{ollama_host});
            defer self.allocator.free(msg);
            try self.addResult("Ollama", .err, msg, null);
            std.debug.print("  ❌ {s}\n", .{msg});
            std.debug.print("  💡 Make sure Ollama is running: docker start ollama\n\n", .{});
            return;
        }

        std.debug.print("  ✅ Ollama is healthy at {s}\n", .{ollama_host});

        // List models
        const models_response = provider.listModels() catch |e| {
            const msg = try std.fmt.allocPrint(self.allocator, "Failed to list models: {}", .{e});
            defer self.allocator.free(msg);
            try self.addResult("Ollama Models", .warning, msg, null);
            std.debug.print("  ⚠️  {s}\n\n", .{msg});
            return;
        };

        const details = try std.fmt.allocPrint(
            self.allocator,
            "{d} models available",
            .{models_response.models.len},
        );
        try self.addResult("Ollama", .ok, "Ollama is healthy", details);

        std.debug.print("  📦 Models available: {d}\n", .{models_response.models.len});

        if (verbose or models_response.models.len > 0) {
            for (models_response.models) |model| {
                std.debug.print("     • {s} ({s}, {s})\n", .{
                    model.name,
                    model.details.parameter_size,
                    model.details.quantization_level,
                });
            }
        }

        // Test a quick generation
        std.debug.print("  🧪 Testing generation...\n", .{});

        if (models_response.models.len > 0) {
            const test_model = models_response.models[0].name;
            const start_time = std.time.milliTimestamp();

            const gen_result = provider.generate(.{
                .model = test_model,
                .prompt = "Reply with just 'OK'",
                .stream = false,
            }) catch |e| {
                std.debug.print("  ⚠️  Generation test failed: {}\n", .{e});
                std.debug.print("\n", .{});
                return;
            };

            const end_time = std.time.milliTimestamp();
            const latency = end_time - start_time;

            std.debug.print("  ⚡ Latency: {d}ms (model: {s})\n", .{ latency, test_model });
            std.debug.print("  💬 Response: {s}\n", .{gen_result.response[0..@min(50, gen_result.response.len)]});
        }

        std.debug.print("\n", .{});
    }

    fn checkOmen(self: *Doctor, verbose: bool) !void {
        _ = verbose;
        std.debug.print("🔮 Checking OMEN...\n", .{});

        const omen_base = std.posix.getenv("OMEN_BASE") orelse "http://localhost:8080/v1";

        // Try to ping OMEN health endpoint
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const health_url = try std.fmt.allocPrint(self.allocator, "{s}/../health", .{omen_base});
        defer self.allocator.free(health_url);

        const result = client.fetch(.{
            .location = .{ .url = health_url },
            .method = .GET,
        }) catch {
            const msg = try std.fmt.allocPrint(self.allocator, "OMEN not reachable at {s}", .{omen_base});
            defer self.allocator.free(msg);
            try self.addResult("OMEN", .warning, msg, null);
            std.debug.print("  ⚠️  {s}\n", .{msg});
            std.debug.print("  💡 OMEN is optional. Zeke will use direct providers.\n\n", .{});
            return;
        };

        if (result.status == .ok) {
            try self.addResult("OMEN", .ok, "OMEN is healthy", omen_base);
            std.debug.print("  ✅ OMEN is healthy at {s}\n", .{omen_base});
        } else {
            std.debug.print("  ⚠️  OMEN returned status: {}\n", .{result.status});
        }

        std.debug.print("\n", .{});
    }

    fn checkMcp(self: *Doctor, verbose: bool) !void {
        _ = verbose;
        std.debug.print("📋 Checking MCP (Glyph)...\n", .{});

        // Try to load config
        const home = std.posix.getenv("HOME") orelse {
            try self.addResult("MCP", .err, "HOME environment variable not set", null);
            std.debug.print("  ❌ Cannot find config: HOME not set\n\n", .{});
            return;
        };

        const config_path = try std.fmt.allocPrint(self.allocator, "{s}/.config/zeke/config.json", .{home});
        defer self.allocator.free(config_path);

        // Load config file
        var cfg = config.Config.loadFromFile(self.allocator, config_path) catch {
            try self.addResult("MCP", .warning, "Config file not found or invalid", config_path);
            std.debug.print("  ⚠️  Config not found: {s}\n", .{config_path});
            std.debug.print("  💡 MCP is optional. Copy config.example.json to set up Glyph integration.\n\n", .{});
            return;
        };
        defer cfg.deinit();

        // Check if Glyph service is configured
        if (cfg.services.glyph == null) {
            try self.addResult("MCP", .warning, "Glyph service not configured", null);
            std.debug.print("  ⚠️  Glyph service not configured in {s}\n", .{config_path});
            std.debug.print("  💡 Add 'services.glyph' section to config.json\n\n", .{});
            return;
        }

        const glyph_config = cfg.services.glyph.?;
        if (!glyph_config.enabled) {
            try self.addResult("MCP", .warning, "Glyph service disabled", null);
            std.debug.print("  ⚠️  Glyph service is disabled\n\n", .{});
            return;
        }

        // Try to initialize MCP client
        var mcp_client = mcp.McpClient.initFromConfig(self.allocator, glyph_config) catch |e| {
            const msg = try std.fmt.allocPrint(self.allocator, "Failed to initialize MCP client: {}", .{e});
            defer self.allocator.free(msg);
            try self.addResult("MCP", .err, msg, null);
            std.debug.print("  ❌ {s}\n\n", .{msg});
            return;
        };
        defer mcp_client.deinit();

        std.debug.print("  ✅ MCP client initialized\n", .{});

        // Try a simple ping/tool call
        std.debug.print("  🧪 Testing MCP connection...\n", .{});

        var params = std.json.ObjectMap.init(self.allocator);
        defer params.deinit();

        params.put("name", .{ .string = "ping" }) catch {};
        params.put("arguments", .{ .object = std.json.ObjectMap.init(self.allocator) }) catch {};

        const start_time = std.time.milliTimestamp();
        const result = mcp_client.callTool("ping", .{ .object = params }) catch |e| {
            const msg = try std.fmt.allocPrint(self.allocator, "MCP tool call failed: {}", .{e});
            defer self.allocator.free(msg);
            try self.addResult("MCP", .warning, msg, null);
            std.debug.print("  ⚠️  {s}\n", .{msg});
            std.debug.print("  💡 Make sure Glyph is running or configured correctly\n\n", .{});
            return;
        };
        defer result.deinit();

        const end_time = std.time.milliTimestamp();
        const latency = end_time - start_time;

        if (result.is_error) {
            try self.addResult("MCP", .warning, "MCP tool returned error", result.content);
            std.debug.print("  ⚠️  MCP tool returned error: {s}\n\n", .{result.content});
        } else {
            try self.addResult("MCP", .ok, "MCP is healthy", null);
            std.debug.print("  ✅ MCP connection successful\n", .{});
            std.debug.print("  ⚡ Latency: {d}ms\n\n", .{latency});
        }
    }

    fn checkProviders(self: *Doctor, verbose: bool) !void {
        std.debug.print("🔑 Checking provider credentials...\n", .{});

        // Import AuthManager for OAuth checks
        const AuthManager = @import("../auth/manager.zig").AuthManager;
        var auth = AuthManager.init(self.allocator);
        defer auth.deinit();

        // Check OpenAI
        if (std.posix.getenv("OPENAI_API_KEY")) |key| {
            const masked = try maskApiKey(self.allocator, key);
            defer self.allocator.free(masked);
            try self.addResult("OpenAI", .ok, "API key configured", masked);
            std.debug.print("  ✅ OpenAI: {s}\n", .{masked});
        } else {
            try self.addResult("OpenAI", .warning, "API key not set", null);
            std.debug.print("  ⚠️  OpenAI: Not configured\n", .{});
            if (verbose) {
                std.debug.print("     Set OPENAI_API_KEY environment variable\n", .{});
            }
        }

        // Check Anthropic/Claude (API key + OAuth)
        const anthropic_env_key = std.posix.getenv("ANTHROPIC_API_KEY");
        const anthropic_oauth = try auth.keyring.get("zeke", "anthropic");
        defer if (anthropic_oauth) |token| self.allocator.free(token);

        if (anthropic_env_key != null or anthropic_oauth != null) {
            if (anthropic_oauth != null) {
                const masked = try maskApiKey(self.allocator, anthropic_oauth.?);
                defer self.allocator.free(masked);
                try self.addResult("Anthropic", .ok, "OAuth token configured", masked);
                std.debug.print("  ✅ Anthropic (OAuth): {s}\n", .{masked});
            } else if (anthropic_env_key) |key| {
                const masked = try maskApiKey(self.allocator, key);
                defer self.allocator.free(masked);
                try self.addResult("Anthropic", .ok, "API key configured", masked);
                std.debug.print("  ✅ Anthropic (API Key): {s}\n", .{masked});
            }
        } else {
            try self.addResult("Anthropic", .warning, "Not configured", null);
            std.debug.print("  ⚠️  Anthropic: Not configured\n", .{});
            if (verbose) {
                std.debug.print("     Option 1: zeke auth claude (OAuth)\n", .{});
                std.debug.print("     Option 2: Set ANTHROPIC_API_KEY\n", .{});
            }
        }

        // Check GitHub Copilot (OAuth only)
        const github_oauth = try auth.keyring.get("zeke", "github");
        defer if (github_oauth) |token| self.allocator.free(token);

        if (github_oauth) |token| {
            const masked = try maskApiKey(self.allocator, token);
            defer self.allocator.free(masked);
            try self.addResult("GitHub Copilot", .ok, "OAuth token configured", masked);
            std.debug.print("  ✅ GitHub Copilot (OAuth): {s}\n", .{masked});
        } else {
            try self.addResult("GitHub Copilot", .warning, "Not configured", null);
            std.debug.print("  ⚠️  GitHub Copilot: Not configured\n", .{});
            if (verbose) {
                std.debug.print("     Setup: zeke auth copilot\n", .{});
            }
        }

        // Check Azure
        if (std.posix.getenv("AZURE_OPENAI_API_KEY")) |key| {
            const masked = try maskApiKey(self.allocator, key);
            defer self.allocator.free(masked);
            try self.addResult("Azure OpenAI", .ok, "API key configured", masked);
            std.debug.print("  ✅ Azure OpenAI: {s}\n", .{masked});
        } else {
            std.debug.print("  ℹ️  Azure OpenAI: Not configured (optional)\n", .{});
        }

        std.debug.print("\n", .{});
    }

    fn printSummary(self: *Doctor) !void {
        var ok_count: usize = 0;
        var warning_count: usize = 0;
        var error_count: usize = 0;

        for (self.results.items) |result| {
            switch (result.status) {
                .ok => ok_count += 1,
                .warning => warning_count += 1,
                .err => error_count += 1,
            }
        }

        std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
        std.debug.print("📋 Summary\n\n", .{});
        std.debug.print("  ✅ OK:       {d}\n", .{ok_count});
        std.debug.print("  ⚠️  Warning:  {d}\n", .{warning_count});
        std.debug.print("  ❌ Error:    {d}\n", .{error_count});
        std.debug.print("\n", .{});

        if (error_count == 0 and warning_count == 0) {
            std.debug.print("🎉 All systems operational!\n\n", .{});
        } else if (error_count == 0) {
            std.debug.print("✨ Core systems working. Some optional features not configured.\n\n", .{});
        } else {
            std.debug.print("⚠️  Some critical systems have errors. Please check above.\n\n", .{});
        }
    }
};

fn getDbPath(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    return try std.fmt.allocPrint(allocator, "{s}/.local/share/zeke/routing.db", .{home});
}

fn maskApiKey(allocator: std.mem.Allocator, key: []const u8) ![]const u8 {
    if (key.len <= 8) {
        return try allocator.dupe(u8, "***");
    }
    const prefix = key[0..4];
    const suffix = key[key.len - 4 ..];
    return try std.fmt.allocPrint(allocator, "{s}...{s}", .{ prefix, suffix });
}

/// Run doctor command
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var options = DoctorOptions{};

    // Parse arguments
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            options.verbose = true;
        } else if (std.mem.eql(u8, arg, "--ollama")) {
            options.check_ollama = true;
            options.check_omen = false;
            options.check_mcp = false;
            options.check_db = false;
            options.check_providers = false;
        } else if (std.mem.eql(u8, arg, "--omen")) {
            options.check_ollama = false;
            options.check_omen = true;
            options.check_mcp = false;
            options.check_db = false;
            options.check_providers = false;
        } else if (std.mem.eql(u8, arg, "--mcp") or std.mem.eql(u8, arg, "--glyph")) {
            options.check_ollama = false;
            options.check_omen = false;
            options.check_mcp = true;
            options.check_db = false;
            options.check_providers = false;
        } else if (std.mem.eql(u8, arg, "--db")) {
            options.check_ollama = false;
            options.check_omen = false;
            options.check_mcp = false;
            options.check_db = true;
            options.check_providers = false;
        }
    }

    var doctor = Doctor.init(allocator);
    defer doctor.deinit();

    try doctor.runChecks(options);
}
