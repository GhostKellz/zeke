const std = @import("std");
const flash = @import("flash");
const zeke = @import("zeke");

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
        } else if (args.len > 2 and std.mem.eql(u8, args[2], "list")) {
            try handleAuthList();
        } else {
            std.debug.print("Usage: zeke auth <provider> <token> | zeke auth list\n", .{});
        }
    } else if (std.mem.eql(u8, command, "tui")) {
        std.debug.print("🚧 TUI mode temporarily disabled while fixing dependencies\n", .{});
        std.debug.print("💡 Use the command-line interface for now!\n", .{});
    } else {
        try printUsage();
    }
}

fn handleChat(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, message: []const u8) !void {
    const response = zeke_instance.chat(message) catch |err| {
        std.log.err("Chat failed: {}", .{err});
        return;
    };
    defer allocator.free(response);
    
    std.debug.print("🤖 ZEKE: {s}\n", .{response});
}

fn handleAsk(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, question: []const u8) !void {
    const response = zeke_instance.chat(question) catch |err| {
        std.log.err("Ask failed: {}", .{err});
        return;
    };
    defer allocator.free(response);
    
    std.debug.print("🤖 ZEKE: {s}\n", .{response});
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

fn handleTui(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator) !void {
    const tui = @import("tui/mod.zig");
    var tui_app = tui.TuiApp.init(allocator, zeke_instance) catch |err| {
        std.log.err("Failed to initialize TUI: {}", .{err});
        return;
    };
    defer tui_app.deinit();
    
    tui_app.run() catch |err| {
        std.log.err("TUI error: {}", .{err});
        return;
    };
}

fn printUsage() !void {
    std.debug.print("⚡ ZEKE - The Zig-Native AI Dev Companion\n", .{});
    std.debug.print("🚀 GhostLLM Integration Ready!\n", .{});
    std.debug.print("\nUsage:\n", .{});
    std.debug.print("  zeke chat \"your message\"              - Chat with AI\n", .{});
    std.debug.print("  zeke ask \"your question\"             - Ask AI a question\n", .{});
    std.debug.print("  zeke explain \"code\" [language]       - Get code explanation\n", .{});
    std.debug.print("  zeke generate \"description\" [lang]   - Generate code/content\n", .{});
    std.debug.print("  zeke debug \"error description\"       - Get debugging help\n", .{});
    std.debug.print("  zeke analyze <file> <type>            - Analyze code file\n", .{});
    std.debug.print("  zeke model [name | list]              - Switch/view models\n", .{});
    std.debug.print("  zeke auth <provider> <token>          - Authenticate\n", .{});
    std.debug.print("  zeke auth list                        - List providers\n", .{});
    std.debug.print("  zeke tui                              - Launch TUI interface\n", .{});
    std.debug.print("\n🔗 Providers: github, openai, claude, ghostllm, ollama\n", .{});
    std.debug.print("🔍 Analysis types: performance, security, style, quality, architecture\n", .{});
    std.debug.print("\n💡 GhostLLM Features:\n", .{});
    std.debug.print("  • GPU-accelerated AI inference\n", .{});
    std.debug.print("  • Sub-100ms response times\n", .{});
    std.debug.print("  • Advanced code analysis\n", .{});
    std.debug.print("  • Real-time suggestions\n", .{});
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
