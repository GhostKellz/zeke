const std = @import("std");
const flash = @import("flash");
const zeke = @import("zeke");
const formatting = @import("formatting.zig");
const file_ops = @import("file_ops.zig");
const cli_streaming = @import("cli_streaming.zig");

// Simple command structure for ZEKE AI
const ZekeCommand = struct {
    command: ?[]const u8 = null,
    message: ?[]const u8 = null,
    question: ?[]const u8 = null,
    code: ?[]const u8 = null,
    description: ?[]const u8 = null,
    error_description: ?[]const u8 = null,
    file: ?[]const u8 = null,
    analysis_type: ?[]const u8 = null,
    model_name: ?[]const u8 = null,
    provider: ?[]const u8 = null,
    token: ?[]const u8 = null,
    language: ?[]const u8 = null,
    output: ?[]const u8 = null,
    stream: bool = false,
    list: bool = false,
    tui: bool = false,
    verbose: bool = false,
    help: bool = false,
};


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Initialize ZEKE instance
    var zeke_instance = zeke.Zeke.init(allocator) catch |err| {
        std.log.err("Failed to initialize ZEKE: {}", .{err});
        return;
    };
    defer zeke_instance.deinit();

    try zeke.bufferedPrint();

    // Parse and handle commands
    if (args.len < 2) {
        try printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "chat")) {
        if (args.len > 2) {
            try handleChat(&zeke_instance, allocator, args[2]);
        } else {
            std.debug.print("Usage: zeke chat \"your message\"\n", .{});
        }
    } else if (std.mem.eql(u8, command, "ask")) {
        if (args.len > 2) {
            try handleAsk(&zeke_instance, allocator, args[2]);
        } else {
            std.debug.print("Usage: zeke ask \"your question\"\n", .{});
        }
    } else if (std.mem.eql(u8, command, "explain")) {
        if (args.len > 2) {
            try handleExplain(&zeke_instance, allocator, args[2], if (args.len > 3) args[3] else null);
        } else {
            std.debug.print("Usage: zeke explain \"code\" [language]\n", .{});
        }
    } else if (std.mem.eql(u8, command, "generate")) {
        if (args.len > 2) {
            try handleGenerate(&zeke_instance, allocator, args[2], if (args.len > 3) args[3] else null);
        } else {
            std.debug.print("Usage: zeke generate \"description\" [language]\n", .{});
        }
    } else if (std.mem.eql(u8, command, "debug")) {
        if (args.len > 2) {
            try handleDebug(&zeke_instance, allocator, args[2]);
        } else {
            std.debug.print("Usage: zeke debug \"error description\"\n", .{});
        }
    } else if (std.mem.eql(u8, command, "analyze")) {
        if (args.len > 3) {
            try handleAnalyze(&zeke_instance, allocator, args[2], args[3]);
        } else {
            std.debug.print("Usage: zeke analyze <file> <type>\n", .{});
            std.debug.print("Types: performance, security, style, quality, architecture\n", .{});
        }
    } else if (std.mem.eql(u8, command, "model")) {
        if (args.len > 2) {
            if (std.mem.eql(u8, args[2], "list")) {
                try handleModelList();
            } else {
                try handleModelSet(&zeke_instance, args[2]);
            }
        } else {
            try handleModelShow(&zeke_instance);
        }
    } else if (std.mem.eql(u8, command, "auth")) {
        if (args.len > 3) {
            try handleAuth(&zeke_instance, args[2], args[3]);
        } else if (args.len > 2) {
            if (std.mem.eql(u8, args[2], "list")) {
                try handleAuthList();
            } else if (std.mem.eql(u8, args[2], "google")) {
                try handleOAuthFlow(&zeke_instance, .google);
            } else if (std.mem.eql(u8, args[2], "github")) {
                try handleOAuthFlow(&zeke_instance, .github);
            } else if (std.mem.eql(u8, args[2], "test")) {
                if (args.len > 3) {
                    try handleAuthTest(&zeke_instance, args[3]);
                } else {
                    std.debug.print("Usage: zeke auth test <provider>\n", .{});
                }
            } else {
                std.debug.print("Usage: zeke auth <provider> <token> | zeke auth list | zeke auth google | zeke auth github\n", .{});
            }
        } else {
            std.debug.print("Usage: zeke auth <provider> <token> | zeke auth list | zeke auth google | zeke auth github\n", .{});
        }
    } else if (std.mem.eql(u8, command, "provider")) {
        if (args.len > 2) {
            if (std.mem.eql(u8, args[2], "switch") and args.len > 3) {
                try handleProviderSwitch(&zeke_instance, args[3]);
            } else if (std.mem.eql(u8, args[2], "status")) {
                try handleProviderStatus(&zeke_instance);
            } else if (std.mem.eql(u8, args[2], "list")) {
                try handleProviderList();
            } else {
                std.debug.print("Usage: zeke provider switch <name> | zeke provider status | zeke provider list\n", .{});
            }
        } else {
            try handleProviderStatus(&zeke_instance);
        }
    } else if (std.mem.eql(u8, command, "stream")) {
        if (args.len > 2) {
            try handleStreamChat(&zeke_instance, allocator, args[2]);
        } else {
            std.debug.print("Usage: zeke stream \"your message\"\n", .{});
        }
    } else if (std.mem.eql(u8, command, "realtime")) {
        if (args.len > 2 and std.mem.eql(u8, args[2], "enable")) {
            try handleRealTimeEnable(&zeke_instance);
        } else {
            std.debug.print("Usage: zeke realtime enable\n", .{});
        }
    } else if (std.mem.eql(u8, command, "smart")) {
        if (args.len > 3) {
            if (std.mem.eql(u8, args[2], "analyze")) {
                try handleSmartAnalyze(&zeke_instance, allocator, args[3], if (args.len > 4) args[4] else "quality");
            } else if (std.mem.eql(u8, args[2], "explain")) {
                try handleSmartExplain(&zeke_instance, allocator, args[3], if (args.len > 4) args[4] else null);
            } else {
                std.debug.print("Usage: zeke smart analyze <file> [type] | zeke smart explain <code> [language]\n", .{});
            }
        } else {
            std.debug.print("Usage: zeke smart analyze <file> [type] | zeke smart explain <code> [language]\n", .{});
        }
    } else if (std.mem.eql(u8, command, "tui")) {
        std.debug.print("🚧 TUI mode temporarily disabled while fixing dependencies\n", .{});
        std.debug.print("💡 Use the command-line interface for now!\n", .{});
    } else if (std.mem.eql(u8, command, "nvim")) {
        if (args.len > 2) {
            try handleNvimCommand(&zeke_instance, allocator, args[2..]);
        } else {
            std.debug.print("Usage: zeke nvim <subcommand>\n", .{});
            std.debug.print("Subcommands: --rpc, chat, edit, explain, create, analyze\n", .{});
        }
    } else if (std.mem.eql(u8, command, "file")) {
        if (args.len > 2) {
            try handleFileCommand(&zeke_instance, allocator, args[2..]);
        } else {
            std.debug.print("Usage: zeke file <subcommand>\n", .{});
            std.debug.print("Subcommands: read, write, edit, generate\n", .{});
        }
    } else if (std.mem.eql(u8, command, "stream")) {
        if (args.len > 2) {
            try handleStreamingCommand(&zeke_instance, allocator, args[2..]);
        } else {
            std.debug.print("Usage: zeke stream <subcommand>\n", .{});
            std.debug.print("Subcommands: chat, demo\n", .{});
        }
    } else {
        try printUsage();
    }
}

fn handleStreamingCommand(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: zeke stream <subcommand>\n", .{});
        return;
    }
    
    const subcommand = args[0];
    
    if (std.mem.eql(u8, subcommand, "chat")) {
        if (args.len > 1) {
            try cli_streaming.handleStreamingChat(zeke_instance, allocator, args[1]);
        } else {
            std.debug.print("Usage: zeke stream chat <message>\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "demo")) {
        // Demo streaming with a sample response
        const sample_response = "This is a demonstration of Zeke's streaming capabilities. " ++
            "The text appears character by character to simulate real-time AI response generation. " ++
            "This creates a more interactive and engaging user experience!";
        
        try cli_streaming.simulateStreamingResponse(allocator, sample_response);
    } else {
        std.debug.print("Unknown streaming subcommand: {s}\n", .{subcommand});
        std.debug.print("Available: chat, demo\n", .{});
    }
}

fn handleFileCommand(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: zeke file <subcommand>\n", .{});
        return;
    }
    
    const subcommand = args[0];
    
    if (std.mem.eql(u8, subcommand, "read")) {
        if (args.len > 1) {
            try file_ops.handleFileRead(allocator, args[1]);
        } else {
            std.debug.print("Usage: zeke file read <file_path>\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "write")) {
        if (args.len > 2) {
            try file_ops.handleFileWrite(allocator, args[1], args[2]);
        } else {
            std.debug.print("Usage: zeke file write <file_path> <content>\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "edit")) {
        if (args.len > 2) {
            try file_ops.handleFileEdit(zeke_instance, allocator, args[1], args[2]);
        } else {
            std.debug.print("Usage: zeke file edit <file_path> <instruction>\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "generate")) {
        if (args.len > 2) {
            try file_ops.handleFileGenerate(zeke_instance, allocator, args[1], args[2]);
        } else {
            std.debug.print("Usage: zeke file generate <file_path> <description>\n", .{});
        }
    } else {
        std.debug.print("Unknown file subcommand: {s}\n", .{subcommand});
        std.debug.print("Available: read, write, edit, generate\n", .{});
    }
}

fn handleChat(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, message: []const u8) !void {
    var formatter = formatting.Formatter.init(allocator, .plain);
    
    const response = zeke_instance.chat(message) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Chat failed: {}", .{err});
        
        const formatted_error = if (error_msg.len > 0) 
            try formatter.formatError(error_msg) 
        else 
            try formatter.formatError("Unknown error occurred");
        
        defer allocator.free(formatted_error);
        defer allocator.free(error_msg);
        
        std.debug.print("{s}", .{formatted_error});
        return;
    };
    defer allocator.free(response);
    
    const formatted_response = try formatter.formatResponse(response);
    defer allocator.free(formatted_response);
    
    std.debug.print("{s}", .{formatted_response});
}

fn handleAsk(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, question: []const u8) !void {
    var formatter = formatting.Formatter.init(allocator, .plain);
    
    const response = zeke_instance.chat(question) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Ask failed: {}", .{err});
        
        const formatted_error = if (error_msg.len > 0) 
            try formatter.formatError(error_msg) 
        else 
            try formatter.formatError("Unknown error occurred");
        
        defer allocator.free(formatted_error);
        defer allocator.free(error_msg);
        
        std.debug.print("{s}", .{formatted_error});
        return;
    };
    defer allocator.free(response);
    
    const formatted_response = try formatter.formatResponse(response);
    defer allocator.free(formatted_response);
    
    std.debug.print("{s}", .{formatted_response});
}

fn handleExplain(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, code: []const u8, language: ?[]const u8) !void {
    const context = zeke.api.CodeContext{
        .file_path = null,
        .language = language,
        .cursor_position = null,
        .surrounding_code = null,
    };
    
    var response = zeke_instance.explainCode(code, context) catch |err| {
        std.log.err("Explain failed: {}", .{err});
        return;
    };
    defer response.deinit(allocator);
    
    std.debug.print("📖 Explanation: {s}\n", .{response.explanation});
}

fn handleGenerate(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, description: []const u8, language: ?[]const u8) !void {
    const prompt = try std.fmt.allocPrint(allocator, "Generate {s}: {s}", .{language orelse "code", description});
    defer allocator.free(prompt);
    
    const response = zeke_instance.chat(prompt) catch |err| {
        std.log.err("Generate failed: {}", .{err});
        return;
    };
    defer allocator.free(response);
    
    std.debug.print("✨ Generated:\n{s}\n", .{response});
}

fn handleDebug(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, error_description: []const u8) !void {
    const prompt = try std.fmt.allocPrint(allocator, "Help debug this issue: {s}", .{error_description});
    defer allocator.free(prompt);
    
    const response = zeke_instance.chat(prompt) catch |err| {
        std.log.err("Debug failed: {}", .{err});
        return;
    };
    defer allocator.free(response);
    
    std.debug.print("🔧 Debug Help:\n{s}\n", .{response});
}

fn handleAnalyze(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, file_path: []const u8, analysis_type_str: []const u8) !void {
    const file_contents = std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024) catch |err| {
        std.log.err("Failed to read file {s}: {}", .{file_path, err});
        return;
    };
    defer allocator.free(file_contents);
    
    const analysis_type = if (std.mem.eql(u8, analysis_type_str, "performance"))
        zeke.api.AnalysisType.performance
    else if (std.mem.eql(u8, analysis_type_str, "security"))
        zeke.api.AnalysisType.security
    else if (std.mem.eql(u8, analysis_type_str, "style"))
        zeke.api.AnalysisType.style
    else if (std.mem.eql(u8, analysis_type_str, "architecture"))
        zeke.api.AnalysisType.architecture
    else
        zeke.api.AnalysisType.quality;
    
    const project_context = zeke.api.ProjectContext{
        .project_path = std.fs.cwd().realpathAlloc(allocator, ".") catch null,
        .git_info = null,
        .dependencies = null,
        .framework = null,
    };
    
    var response = zeke_instance.analyzeCode(file_contents, analysis_type, project_context) catch |err| {
        std.log.err("Analysis failed: {}", .{err});
        return;
    };
    defer response.deinit(allocator);
    
    std.debug.print("🔍 Analysis Result:\n{s}\n", .{response.analysis});
    if (response.suggestions.len > 0) {
        std.debug.print("\n💡 Suggestions:\n", .{});
        for (response.suggestions) |suggestion| {
            std.debug.print("  • {s}\n", .{suggestion});
        }
    }
}

fn handleModelSet(zeke_instance: *zeke.Zeke, model_name: []const u8) !void {
    zeke_instance.setModel(model_name) catch |err| {
        std.log.err("Failed to set model: {}", .{err});
        return;
    };
    std.debug.print("✅ Switched to model: {s}\n", .{model_name});
}

fn handleModelList() !void {
    std.debug.print("📋 Available models:\n", .{});
    std.debug.print("  • gpt-4 (OpenAI)\n", .{});
    std.debug.print("  • gpt-3.5-turbo (OpenAI)\n", .{});
    std.debug.print("  • claude-3-5-sonnet-20241022 (Claude)\n", .{});
    std.debug.print("  • copilot-codex (GitHub Copilot)\n", .{});
    std.debug.print("  • ghostllm-model (GhostLLM)\n", .{});
}

fn handleModelShow(zeke_instance: *zeke.Zeke) !void {
    std.debug.print("🔧 Current model: {s}\n", .{zeke_instance.current_model});
}

fn handleAuth(zeke_instance: *zeke.Zeke, provider: []const u8, token: []const u8) !void {
    if (std.mem.eql(u8, provider, "github")) {
        zeke_instance.authenticateGitHub(token) catch |err| {
            std.log.err("GitHub authentication failed: {}", .{err});
            return;
        };
        std.debug.print("✅ GitHub authentication successful\n", .{});
    } else if (std.mem.eql(u8, provider, "openai")) {
        zeke_instance.setOpenAIKey(token) catch |err| {
            std.log.err("OpenAI authentication failed: {}", .{err});
            return;
        };
        std.debug.print("✅ OpenAI authentication successful\n", .{});
    } else if (std.mem.eql(u8, provider, "ghostllm")) {
        try zeke_instance.api_client.setAuth(token);
        std.debug.print("✅ GhostLLM authentication successful\n", .{});
    } else {
        std.debug.print("🚧 Provider {s} authentication not yet implemented\n", .{provider});
    }
}

fn handleAuthList() !void {
    std.debug.print("🔑 Supported providers:\n", .{});
    std.debug.print("  • github - GitHub Copilot\n", .{});
    std.debug.print("  • openai - OpenAI GPT models\n", .{});
    std.debug.print("  • claude - Anthropic Claude\n", .{});
    std.debug.print("  • ghostllm - GhostLLM GPU proxy\n", .{});
    std.debug.print("  • ollama - Local Ollama instance\n", .{});
}

fn handleOAuthFlow(zeke_instance: *zeke.Zeke, provider: zeke.auth.AuthProvider) !void {
    switch (provider) {
        .google => {
            const auth_url = zeke_instance.auth_manager.startGoogleOAuth() catch |err| {
                std.log.err("Failed to start Google OAuth: {}", .{err});
                std.debug.print("❌ Google OAuth not configured. Please set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET\n", .{});
                return;
            };
            defer zeke_instance.allocator.free(auth_url);
            
            std.debug.print("🔐 Google OAuth Flow\n", .{});
            std.debug.print("1. Open this URL in your browser:\n{s}\n", .{auth_url});
            std.debug.print("2. Complete authorization and copy the code parameter from the callback URL\n", .{});
            std.debug.print("3. Run: zeke auth google <code>\n", .{});
        },
        .github => {
            const auth_url = zeke_instance.auth_manager.startGitHubOAuth() catch |err| {
                std.log.err("Failed to start GitHub OAuth: {}", .{err});
                std.debug.print("❌ GitHub OAuth not configured. Please set GITHUB_CLIENT_ID and GITHUB_CLIENT_SECRET\n", .{});
                return;
            };
            defer zeke_instance.allocator.free(auth_url);
            
            std.debug.print("🔐 GitHub OAuth Flow\n", .{});
            std.debug.print("1. Open this URL in your browser:\n{s}\n", .{auth_url});
            std.debug.print("2. Complete authorization and copy the code parameter from the callback URL\n", .{});
            std.debug.print("3. Run: zeke auth github <code>\n", .{});
        },
        else => {
            std.debug.print("❌ OAuth not supported for this provider\n", .{});
        },
    }
}

fn handleAuthTest(zeke_instance: *zeke.Zeke, provider_str: []const u8) !void {
    const provider = if (std.mem.eql(u8, provider_str, "github"))
        zeke.auth.AuthProvider.github
    else if (std.mem.eql(u8, provider_str, "openai"))
        zeke.auth.AuthProvider.openai
    else if (std.mem.eql(u8, provider_str, "google"))
        zeke.auth.AuthProvider.google
    else if (std.mem.eql(u8, provider_str, "local"))
        zeke.auth.AuthProvider.local
    else {
        std.debug.print("❌ Unknown provider: {s}\n", .{provider_str});
        return;
    };
    
    const is_authenticated = zeke_instance.auth_manager.isAuthenticated(provider) catch false;
    
    if (is_authenticated) {
        std.debug.print("✅ Authentication test passed for {s}\n", .{provider_str});
    } else {
        std.debug.print("❌ Authentication test failed for {s}\n", .{provider_str});
        std.debug.print("💡 Run: zeke auth {s} <token> to authenticate\n", .{provider_str});
    }
}

fn handleProviderSwitch(zeke_instance: *zeke.Zeke, provider_str: []const u8) !void {
    const provider = if (std.mem.eql(u8, provider_str, "openai"))
        zeke.api.ApiProvider.openai
    else if (std.mem.eql(u8, provider_str, "claude"))
        zeke.api.ApiProvider.claude
    else if (std.mem.eql(u8, provider_str, "copilot"))
        zeke.api.ApiProvider.copilot
    else if (std.mem.eql(u8, provider_str, "ghostllm"))
        zeke.api.ApiProvider.ghostllm
    else if (std.mem.eql(u8, provider_str, "ollama"))
        zeke.api.ApiProvider.ollama
    else {
        std.debug.print("❌ Unknown provider: {s}\n", .{provider_str});
        std.debug.print("Available providers: openai, claude, copilot, ghostllm, ollama\n", .{});
        return;
    };
    
    zeke_instance.switchToProvider(provider) catch |err| {
        std.log.err("Failed to switch provider: {}", .{err});
        std.debug.print("❌ Failed to switch to provider: {s}\n", .{provider_str});
        return;
    };
    
    std.debug.print("✅ Switched to provider: {s}\n", .{provider_str});
}

fn handleProviderStatus(zeke_instance: *zeke.Zeke) !void {
    std.debug.print("🚀 Provider Status:\n", .{});
    std.debug.print("Current: {s}\n", .{@tagName(zeke_instance.current_provider)});
    std.debug.print("Model: {s}\n\n", .{zeke_instance.current_model});
    
    const status_list = zeke_instance.getProviderStatus() catch |err| {
        std.log.err("Failed to get provider status: {}", .{err});
        return;
    };
    defer zeke_instance.allocator.free(status_list);
    
    for (status_list) |status| {
        const health_icon = if (status.is_healthy) "✅" else "❌";
        const response_time = if (status.response_time_ms > 0) status.response_time_ms else 0;
        const error_rate = @as(u32, @intFromFloat(status.error_rate * 100));
        
        std.debug.print("{s} {s}: {d}ms, {d}% errors\n", .{
            health_icon, @tagName(status.provider), response_time, error_rate
        });
    }
}

fn handleProviderList() !void {
    std.debug.print("📋 Available providers:\n", .{});
    std.debug.print("  • openai - OpenAI GPT models\n", .{});
    std.debug.print("  • claude - Anthropic Claude models\n", .{});
    std.debug.print("  • copilot - GitHub Copilot\n", .{});
    std.debug.print("  • ghostllm - GhostLLM GPU proxy (recommended)\n", .{});
    std.debug.print("  • ollama - Local Ollama instance\n", .{});
}

fn handleStreamChat(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, message: []const u8) !void {
    _ = allocator;
    
    std.debug.print("🌊 Streaming response from {s}:\n", .{@tagName(zeke_instance.current_provider)});
    
    const StreamHandler = struct {
        fn callback(chunk: zeke.streaming.StreamChunk) void {
            if (chunk.content.len > 0) {
                std.debug.print("{s}", .{chunk.content});
            }
            if (chunk.is_final) {
                std.debug.print("\n\n✅ Stream complete!\n", .{});
            }
        }
    };
    
    zeke_instance.streamChat(message, StreamHandler.callback) catch |err| {
        std.log.err("Streaming failed: {}", .{err});
        std.debug.print("❌ Streaming failed, falling back to regular chat...\n", .{});
        
        // Fallback to regular chat
        const response = zeke_instance.chatWithFallback(message) catch |fallback_err| {
            std.log.err("Fallback chat failed: {}", .{fallback_err});
            std.debug.print("❌ All providers failed\n", .{});
            return;
        };
        defer zeke_instance.allocator.free(response);
        
        std.debug.print("🤖 ZEKE: {s}\n", .{response});
    };
}

fn handleRealTimeEnable(zeke_instance: *zeke.Zeke) !void {
    zeke_instance.enableRealTimeFeatures() catch |err| {
        std.log.err("Failed to enable real-time features: {}", .{err});
        std.debug.print("❌ Failed to enable real-time features\n", .{});
        return;
    };
    
    std.debug.print("✅ Real-time features enabled\n", .{});
    std.debug.print("🚀 Features available:\n", .{});
    std.debug.print("  • Real-time code analysis\n", .{});
    std.debug.print("  • Streaming responses\n", .{});
    std.debug.print("  • Live typing assistance\n", .{});
}

fn handleSmartAnalyze(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, file_path: []const u8, analysis_type_str: []const u8) !void {
    const file_contents = std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024) catch |err| {
        std.log.err("Failed to read file {s}: {}", .{file_path, err});
        return;
    };
    defer allocator.free(file_contents);
    
    const analysis_type = if (std.mem.eql(u8, analysis_type_str, "performance"))
        zeke.api.AnalysisType.performance
    else if (std.mem.eql(u8, analysis_type_str, "security"))
        zeke.api.AnalysisType.security
    else if (std.mem.eql(u8, analysis_type_str, "style"))
        zeke.api.AnalysisType.style
    else if (std.mem.eql(u8, analysis_type_str, "architecture"))
        zeke.api.AnalysisType.architecture
    else
        zeke.api.AnalysisType.quality;
    
    const project_context = zeke.api.ProjectContext{
        .project_path = std.fs.cwd().realpathAlloc(allocator, ".") catch null,
        .git_info = null,
        .dependencies = null,
        .framework = null,
    };
    
    std.debug.print("🧠 Smart Analysis with best provider...\n", .{});
    
    var response = zeke_instance.analyzeCodeWithBestProvider(file_contents, analysis_type, project_context) catch |err| {
        std.log.err("Smart analysis failed: {}", .{err});
        return;
    };
    defer response.deinit(allocator);
    
    std.debug.print("🔍 Analysis Result:\n{s}\n", .{response.analysis});
    if (response.suggestions.len > 0) {
        std.debug.print("\n💡 Suggestions:\n", .{});
        for (response.suggestions) |suggestion| {
            std.debug.print("  • {s}\n", .{suggestion});
        }
    }
    std.debug.print("\n📊 Confidence: {d:.1}%\n", .{response.confidence * 100});
}

fn handleSmartExplain(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, code: []const u8, language: ?[]const u8) !void {
    const context = zeke.api.CodeContext{
        .file_path = null,
        .language = language,
        .cursor_position = null,
        .surrounding_code = null,
    };
    
    std.debug.print("🧠 Smart Explanation with best provider...\n", .{});
    
    var response = zeke_instance.explainCodeWithBestProvider(code, context) catch |err| {
        std.log.err("Smart explanation failed: {}", .{err});
        return;
    };
    defer response.deinit(allocator);
    
    std.debug.print("📖 Explanation:\n{s}\n", .{response.explanation});
    
    if (response.examples.len > 0) {
        std.debug.print("\n💡 Examples:\n", .{});
        for (response.examples) |example| {
            std.debug.print("  {s}\n", .{example});
        }
    }
    
    if (response.related_concepts.len > 0) {
        std.debug.print("\n🔗 Related Concepts:\n", .{});
        for (response.related_concepts) |concept| {
            std.debug.print("  • {s}\n", .{concept});
        }
    }
}

fn handleTui(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator) !void {
    var tui_app = zeke.tui.TuiApp.init(allocator, zeke_instance) catch |err| {
        std.log.err("Failed to initialize TUI: {}", .{err});
        return;
    };
    defer tui_app.deinit();
    
    tui_app.run() catch |err| {
        std.log.err("TUI error: {}", .{err});
        return;
    };
}

fn handleNvimCommand(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: zeke nvim <subcommand>\n", .{});
        return;
    }
    
    const subcommand = args[0];
    
    if (std.mem.eql(u8, subcommand, "--rpc")) {
        // RPC server temporarily disabled - use CLI commands instead
        std.debug.print("RPC server temporarily disabled. Use CLI commands instead:\n", .{});
        std.debug.print("  zeke nvim chat \"message\"\n", .{});
        std.debug.print("  zeke nvim edit \"code\" \"instruction\"\n", .{});
        std.debug.print("  zeke nvim explain \"code\"\n", .{});
        std.debug.print("  zeke nvim create \"description\"\n", .{});
        std.debug.print("  zeke nvim analyze \"code\" \"type\"\n", .{});
    } else if (std.mem.eql(u8, subcommand, "chat")) {
        if (args.len > 1) {
            try handleNvimChat(zeke_instance, allocator, args[1]);
        } else {
            std.debug.print("Usage: zeke nvim chat <message>\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "edit")) {
        if (args.len > 2) {
            try handleNvimEdit(zeke_instance, allocator, args[1], args[2]);
        } else {
            std.debug.print("Usage: zeke nvim edit <code> <instruction>\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "explain")) {
        if (args.len > 1) {
            try handleNvimExplain(zeke_instance, allocator, args[1]);
        } else {
            std.debug.print("Usage: zeke nvim explain <code>\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "create")) {
        if (args.len > 1) {
            try handleNvimCreate(zeke_instance, allocator, args[1]);
        } else {
            std.debug.print("Usage: zeke nvim create <description>\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "analyze")) {
        if (args.len > 2) {
            try handleNvimAnalyze(zeke_instance, allocator, args[1], args[2]);
        } else {
            std.debug.print("Usage: zeke nvim analyze <code> <type>\n", .{});
        }
    } else {
        std.debug.print("Unknown nvim subcommand: {s}\n", .{subcommand});
        std.debug.print("Available: --rpc, chat, edit, explain, create, analyze\n", .{});
    }
}

fn handleRPCServer(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator) !void {
    std.debug.print("🚀 Starting ZEKE MessagePack-RPC server...\n", .{});
    
    var rpc_server = try zeke.rpc.MsgPackRPC.init(allocator, zeke_instance);
    defer rpc_server.deinit();
    
    // Set up signal handling for graceful shutdown
    const SignalHandler = struct {
        server: *zeke.rpc.MsgPackRPC,
        
        fn handle(self: @This()) void {
            std.debug.print("\n🛑 Received shutdown signal, stopping RPC server...\n", .{});
            self.server.stop();
        }
    };
    
    const signal_handler = SignalHandler{ .server = &rpc_server };
    _ = signal_handler; // TODO: Set up actual signal handling
    
    // Start the RPC server
    try rpc_server.start();
    
    std.debug.print("✅ RPC server stopped\n", .{});
}

fn handleNvimChat(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, message: []const u8) !void {
    const response = zeke_instance.chat(message) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Chat failed: {}", .{err});
        defer allocator.free(error_msg);
        
        const json_response = try std.fmt.allocPrint(allocator, 
            "{{\"success\": false, \"error\": \"{s}\", \"content\": null}}", 
            .{error_msg}
        );
        defer allocator.free(json_response);
        
        std.debug.print("{s}\n", .{json_response});
        return;
    };
    defer allocator.free(response);
    
    const json_response = try std.fmt.allocPrint(allocator, 
        "{{\"success\": true, \"error\": null, \"content\": \"{s}\"}}", 
        .{response}
    );
    defer allocator.free(json_response);
    
    std.debug.print("{s}\n", .{json_response});
}

fn handleNvimEdit(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, code: []const u8, instruction: []const u8) !void {
    const edit_prompt = try std.fmt.allocPrint(allocator, 
        "Edit this code according to the instruction.\n\nInstruction: {s}\n\nCode:\n{s}", 
        .{ instruction, code });
    defer allocator.free(edit_prompt);
    
    const response = zeke_instance.chat(edit_prompt) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Edit failed: {}", .{err});
        defer allocator.free(error_msg);
        
        const json_response = try std.fmt.allocPrint(allocator, 
            "{{\"success\": false, \"error\": \"{s}\", \"content\": null}}", 
            .{error_msg}
        );
        defer allocator.free(json_response);
        
        std.debug.print("{s}\n", .{json_response});
        return;
    };
    defer allocator.free(response);
    
    const json_response = try std.fmt.allocPrint(allocator, 
        "{{\"success\": true, \"error\": null, \"content\": \"{s}\"}}", 
        .{response}
    );
    defer allocator.free(json_response);
    
    std.debug.print("{s}\n", .{json_response});
}

fn handleNvimExplain(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, code: []const u8) !void {
    const context = zeke.api.CodeContext{
        .file_path = null,
        .language = null,
        .cursor_position = null,
        .surrounding_code = null,
    };
    
    var explanation = zeke_instance.explainCode(code, context) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Explain failed: {}", .{err});
        defer allocator.free(error_msg);
        
        const json_response = try std.fmt.allocPrint(allocator, 
            "{{\"success\": false, \"error\": \"{s}\", \"content\": null}}", 
            .{error_msg}
        );
        defer allocator.free(json_response);
        
        std.debug.print("{s}\n", .{json_response});
        return;
    };
    defer explanation.deinit(allocator);
    
    const json_response = try std.fmt.allocPrint(allocator, 
        "{{\"success\": true, \"error\": null, \"content\": \"{s}\"}}", 
        .{explanation.explanation}
    );
    defer allocator.free(json_response);
    
    std.debug.print("{s}\n", .{json_response});
}

fn handleNvimCreate(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, description: []const u8) !void {
    const create_prompt = try std.fmt.allocPrint(allocator, 
        "Create a file with the following description: {s}", 
        .{description});
    defer allocator.free(create_prompt);
    
    const response = zeke_instance.chat(create_prompt) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Create failed: {}", .{err});
        defer allocator.free(error_msg);
        
        const json_response = try std.fmt.allocPrint(allocator, 
            "{{\"success\": false, \"error\": \"{s}\", \"content\": null}}", 
            .{error_msg}
        );
        defer allocator.free(json_response);
        
        std.debug.print("{s}\n", .{json_response});
        return;
    };
    defer allocator.free(response);
    
    const json_response = try std.fmt.allocPrint(allocator, 
        "{{\"success\": true, \"error\": null, \"content\": \"{s}\"}}", 
        .{response}
    );
    defer allocator.free(json_response);
    
    std.debug.print("{s}\n", .{json_response});
}

fn handleNvimAnalyze(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, code: []const u8, analysis_type_str: []const u8) !void {
    const analysis_type = if (std.mem.eql(u8, analysis_type_str, "performance"))
        zeke.api.AnalysisType.performance
    else if (std.mem.eql(u8, analysis_type_str, "security"))
        zeke.api.AnalysisType.security
    else if (std.mem.eql(u8, analysis_type_str, "style"))
        zeke.api.AnalysisType.style
    else if (std.mem.eql(u8, analysis_type_str, "architecture"))
        zeke.api.AnalysisType.architecture
    else
        zeke.api.AnalysisType.quality;
    
    const project_context = zeke.api.ProjectContext{
        .project_path = std.fs.cwd().realpathAlloc(allocator, ".") catch null,
        .git_info = null,
        .dependencies = null,
        .framework = null,
    };
    
    var analysis = zeke_instance.analyzeCode(code, analysis_type, project_context) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Analysis failed: {}", .{err});
        defer allocator.free(error_msg);
        
        const json_response = try std.fmt.allocPrint(allocator, 
            "{{\"success\": false, \"error\": \"{s}\", \"content\": null}}", 
            .{error_msg}
        );
        defer allocator.free(json_response);
        
        std.debug.print("{s}\n", .{json_response});
        return;
    };
    defer analysis.deinit(allocator);
    
    const json_response = try std.fmt.allocPrint(allocator, 
        "{{\"success\": true, \"error\": null, \"content\": \"{s}\"}}", 
        .{analysis.analysis}
    );
    defer allocator.free(json_response);
    
    std.debug.print("{s}\n", .{json_response});
}

fn printUsage() !void {
    std.debug.print("⚡ ZEKE v0.2.0 - The Zig-Native AI Dev Companion\n", .{});
    std.debug.print("🚀 Multi-Provider AI with Smart Routing & Real-Time Features\n", .{});
    std.debug.print("\n📋 Basic Commands:\n", .{});
    std.debug.print("  zeke chat \"your message\"              - Chat with AI\n", .{});
    std.debug.print("  zeke ask \"your question\"             - Ask AI a question\n", .{});
    std.debug.print("  zeke explain \"code\" [language]       - Get code explanation\n", .{});
    std.debug.print("  zeke generate \"description\" [lang]   - Generate code/content\n", .{});
    std.debug.print("  zeke debug \"error description\"       - Get debugging help\n", .{});
    std.debug.print("  zeke analyze <file> <type>            - Analyze code file\n", .{});
    std.debug.print("\n🔐 Authentication:\n", .{});
    std.debug.print("  zeke auth <provider> <token>          - Authenticate with API key\n", .{});
    std.debug.print("  zeke auth google                      - Start Google OAuth flow\n", .{});
    std.debug.print("  zeke auth github                      - Start GitHub OAuth flow\n", .{});
    std.debug.print("  zeke auth test <provider>             - Test authentication\n", .{});
    std.debug.print("  zeke auth list                        - List auth providers\n", .{});
    std.debug.print("\n🔄 Provider Management:\n", .{});
    std.debug.print("  zeke provider switch <name>           - Switch to provider\n", .{});
    std.debug.print("  zeke provider status                  - Show provider health\n", .{});
    std.debug.print("  zeke provider list                    - List all providers\n", .{});
    std.debug.print("\n🌊 Streaming & Real-Time:\n", .{});
    std.debug.print("  zeke stream chat \"message\"           - Stream AI response in real-time\n", .{});
    std.debug.print("  zeke stream demo                      - Demo streaming capabilities\n", .{});
    std.debug.print("  zeke realtime enable                  - Enable real-time features\n", .{});
    std.debug.print("\n🧠 Smart Features:\n", .{});
    std.debug.print("  zeke smart analyze <file> [type]      - Smart code analysis\n", .{});
    std.debug.print("  zeke smart explain \"code\" [lang]     - Smart code explanation\n", .{});
    std.debug.print("\n📁 File Operations:\n", .{});
    std.debug.print("  zeke file read <file_path>            - Read and display file\n", .{});
    std.debug.print("  zeke file write <file_path> <content> - Write content to file\n", .{});
    std.debug.print("  zeke file edit <file_path> <instruction> - Edit file with AI\n", .{});
    std.debug.print("  zeke file generate <file_path> <description> - Generate file with AI\n", .{});
    std.debug.print("\n🔌 Neovim Integration:\n", .{});
    std.debug.print("  zeke nvim --rpc                       - Start MessagePack-RPC server\n", .{});
    std.debug.print("  zeke nvim chat \"message\"              - Chat with context\n", .{});
    std.debug.print("  zeke nvim edit \"code\" \"instruction\"  - Edit code inline\n", .{});
    std.debug.print("  zeke nvim explain \"code\"              - Explain code\n", .{});
    std.debug.print("  zeke nvim create \"description\"        - Create file\n", .{});
    std.debug.print("  zeke nvim analyze \"code\" <type>       - Analyze code\n", .{});
    std.debug.print("\n⚙️ Configuration:\n", .{});
    std.debug.print("  zeke model [name | list]              - Switch/view models\n", .{});
    std.debug.print("  zeke tui                              - Launch TUI interface\n", .{});
    std.debug.print("\n🚀 Providers: ghostllm (GPU), claude, openai, copilot, ollama\n", .{});
    std.debug.print("🔍 Analysis: performance, security, style, quality, architecture\n", .{});
    std.debug.print("\n✨ v0.2.0 Features:\n", .{});
    std.debug.print("  • Multi-provider authentication with OAuth\n", .{});
    std.debug.print("  • Smart provider routing with fallbacks\n", .{});
    std.debug.print("  • Real-time streaming responses\n", .{});
    std.debug.print("  • GPU-accelerated GhostLLM integration\n", .{});
    std.debug.print("  • Enhanced error handling & health monitoring\n", .{});
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
