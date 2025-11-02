const std = @import("std");
const flash = @import("flash");
const zsync = @import("zsync");
const zeke = @import("zeke");
const formatting = @import("formatting.zig");
const file_ops = @import("file_ops.zig");
const cli_streaming = @import("cli_streaming.zig");
const agent = @import("agent/mod.zig");
const tools = @import("tools/mod.zig");
const git_ops = zeke.git;
const search = zeke.search;
const ui = zeke.ui;

// Version will be set by build system
const VERSION = "0.3.2";
const build_ops = zeke.build;

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
    // Enhanced zsync v0.5.4 runtime with hybrid execution model
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Check if this is an auth command - skip zsync for simple auth operations
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const is_auth_command = args.len >= 2 and std.mem.eql(u8, args[1], "auth");

    if (is_auth_command) {
        // Auth commands don't need zsync runtime - run directly
        try zekeMain(allocator);
        return;
    }

    // Use zsync v0.5.4 hybrid execution for optimal performance
    const cpu_count = std.Thread.getCpuCount() catch 4;
    const available_memory = cpu_count * 64 * 1024 * 1024; // Estimate

    // Choose optimal execution model based on system capabilities
    const execution_model: zsync.ExecutionModel = if (cpu_count >= 8 and available_memory > 512 * 1024 * 1024)
        .thread_pool // Use thread pool for high-performance systems
    else if (cpu_count >= 4)
        .green_threads // Use green threads for medium systems
    else
        .blocking; // Fallback to blocking for low-resource systems

    const config = zsync.Config{
        .execution_model = execution_model,
    };

    const runtime = try zsync.Runtime.init(allocator, config);
    defer runtime.deinit();

    runtime.setGlobal();

    try zekeMain(allocator);
}

fn zekeMain(allocator: std.mem.Allocator) !void {
    // Initialize Tokyo Night theme
    ui.initTheme(allocator);

    // Get command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Initialize ZEKE instance with zsync support
    // For now, pass null to avoid type mismatch until zsync types are fixed
    var zeke_instance = zeke.Zeke.initWithIO(allocator, null) catch |err| {
        std.log.err("Failed to initialize ZEKE: {}", .{err});
        return;
    };
    defer zeke_instance.deinit();

    try zeke.bufferedPrint();

    // Parse and handle commands
    if (args.len < 2) {
        const help = @import("cli/help.zig");
        try help.showHelp(allocator);
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "chat")) {
        if (args.len > 2) {
            // Check for flags
            var message_idx: usize = 2;
            var stream_mode = false;
            var json_mode = false;

            // Parse flags
            for (args[2..], 0..) |arg, i| {
                if (std.mem.eql(u8, arg, "--stream")) {
                    stream_mode = true;
                    message_idx = 2 + i + 1;
                } else if (std.mem.eql(u8, arg, "--json")) {
                    json_mode = true;
                    message_idx = 2 + i + 1;
                } else {
                    // Found the message
                    break;
                }
            }

            if (message_idx >= args.len) {
                std.debug.print("Usage: zeke chat [--stream] [--json] \"your message\"\n", .{});
                return;
            }

            const message = args[message_idx];

            if (stream_mode and json_mode) {
                try cli_streaming.handleStreamingChatJson(&zeke_instance, allocator, message);
            } else if (stream_mode) {
                try cli_streaming.handleStreamingChat(&zeke_instance, allocator, message);
            } else {
                try handleChat(&zeke_instance, allocator, message);
            }
        } else {
            std.debug.print("Usage: zeke chat [--stream] [--json] \"your message\"\n", .{});
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
        const auth_cli = @import("cli/auth.zig");
        try auth_cli.run(allocator, if (args.len > 2) args[2..] else &[_][:0]u8{});
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
    } else if (std.mem.eql(u8, command, "watch")) {
        try zeke.watch.runWatchMode(allocator, if (args.len > 2) args[2..] else &[_][:0]u8{});
    } else if (std.mem.eql(u8, command, "doctor")) {
        const doctor = @import("cli/doctor.zig");
        try doctor.run(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "completion")) {
        const completions = @import("cli/completions.zig");
        if (args.len > 2) {
            if (completions.Shell.fromString(args[2])) |shell| {
                try completions.generateCompletions(allocator, shell);
            } else {
                std.debug.print("Unknown shell: {s}\n", .{args[2]});
                std.debug.print("Supported: bash, zsh, fish\n", .{});
            }
        } else {
            std.debug.print("Usage: zeke completion <shell>\n", .{});
            std.debug.print("Shells: bash, zsh, fish\n", .{});
        }
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        const help = @import("cli/help.zig");
        if (args.len > 2) {
            try help.showCommandHelp(allocator, args[2]);
        } else {
            try help.showHelp(allocator);
        }
    } else if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "-v")) {
        std.debug.print("ZEKE v{s}\n", .{VERSION});
    } else if (std.mem.eql(u8, command, "usage")) {
        try handleUsageCommand(&zeke_instance, allocator, if (args.len > 2) args[2..] else &[_][:0]u8{});
    } else if (std.mem.eql(u8, command, "glyph")) {
        const glyph = @import("cli/glyph.zig");
        try glyph.run(allocator, if (args.len > 2) args[2..] else &[_][:0]u8{});
    } else if (std.mem.eql(u8, command, "serve")) {
        const serve = @import("cli/serve.zig");
        try serve.run(allocator, if (args.len > 2) args[2..] else &[_][:0]u8{});
    } else if (std.mem.eql(u8, command, "edit")) {
        const edit = @import("cli/edit.zig");
        try edit.run(allocator, if (args.len > 2) args[2..] else &[_][:0]u8{});
    } else if (std.mem.eql(u8, command, "refactor")) {
        const refactor = @import("cli/refactor.zig");
        try refactor.run(allocator, if (args.len > 2) args[2..] else &[_][:0]u8{});
    } else if (std.mem.eql(u8, command, "analyze")) {
        const analyze = @import("cli/analyze.zig");
        try analyze.run(allocator, if (args.len > 2) args[2..] else &[_][:0]u8{});
    } else if (std.mem.eql(u8, command, "generate")) {
        const generate = @import("cli/generate.zig");
        try generate.run(allocator, if (args.len > 2) args[2..] else &[_][:0]u8{});
    } else if (std.mem.eql(u8, command, "index")) {
        const index_cli = @import("cli/index.zig");
        try index_cli.run(allocator, if (args.len > 2) args[2..] else &[_][:0]u8{});
    } else if (std.mem.eql(u8, command, "lsp")) {
        const lsp_cli = @import("cli/lsp.zig");
        try lsp_cli.run(allocator, if (args.len > 2) args[2..] else &[_][:0]u8{});
    } else if (std.mem.eql(u8, command, "daemon")) {
        const daemon_cli = @import("cli/daemon.zig");
        try daemon_cli.run(allocator, if (args.len > 2) args[2..] else &[_][:0]u8{});
    } else if (std.mem.eql(u8, command, "tui")) {
        try handleTui(&zeke_instance, allocator);
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
    } else if (std.mem.eql(u8, command, "agent")) {
        if (args.len > 2) {
            try handleAgentCommand(&zeke_instance, allocator, args[2..]);
        } else {
            std.debug.print("Usage: zeke agent <subcommand>\n", .{});
            std.debug.print("Subcommands: blockchain, smartcontract, network, security\n", .{});
        }
    } else if (std.mem.eql(u8, command, "git")) {
        if (args.len > 2) {
            try handleGitCommand(allocator, args[2..]);
        } else {
            std.debug.print("Usage: zeke git <subcommand>\n", .{});
            std.debug.print("Subcommands: status, diff, add, commit, branch, pr\n", .{});
        }
    } else if (std.mem.eql(u8, command, "search")) {
        if (args.len > 2) {
            try handleSearchCommand(allocator, args[2..]);
        } else {
            std.debug.print("Usage: zeke search <subcommand>\n", .{});
            std.debug.print("Subcommands: files, content, grep\n", .{});
        }
    } else if (std.mem.eql(u8, command, "config")) {
        const config_cli = @import("cli/config.zig");
        try config_cli.run(allocator, if (args.len > 2) args[2..] else &[_][:0]u8{});
    } else if (std.mem.eql(u8, command, "build")) {
        if (args.len > 2) {
            try handleBuildCommand(allocator, args[2..]);
        } else {
            std.debug.print("Usage: zeke build <subcommand>\n", .{});
            std.debug.print("Subcommands: run, test, clean, detect\n", .{});
        }
    } else if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "-v")) {
        std.debug.print("ZEKE v{s}\n", .{VERSION});
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        try printUsage();
    } else {
        try printUsage();
    }
}

fn handleAgentCommand(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    _ = zeke_instance;

    if (args.len == 0) {
        std.debug.print("Usage: zeke agent <agent_type> <command> [args...]\n", .{});
        std.debug.print("Agent Types: blockchain, smartcontract, network, security\n", .{});
        return;
    }

    const agent_type_str = args[0];

    // Initialize agent manager
    var agent_manager = agent.AgentManager.init(allocator);
    defer agent_manager.deinit();

    if (std.mem.eql(u8, agent_type_str, "blockchain")) {
        var blockchain_agent = agent.blockchain.BlockchainAgent.init(allocator, "http://localhost:8545", 1337);
        try agent_manager.registerAgent(&blockchain_agent.agent);

        if (args.len > 1) {
            const command = args[1];
            const command_args = if (args.len > 2) args[2..] else &[_][:0]u8{};

            const result = try agent_manager.executeCommand(.blockchain, command, command_args);
            if (result.success) {
                std.debug.print("✅ {s}\n", .{result.message});
            } else {
                std.debug.print("❌ {s}\n", .{result.message});
            }
        } else {
            std.debug.print("Available blockchain commands: status, balance, block, gas, health, monitor\n", .{});
        }
    } else if (std.mem.eql(u8, agent_type_str, "smartcontract")) {
        var rpc_client = agent.blockchain.RpcClient.init(allocator, "http://localhost:8545");
        var smartcontract_agent = agent.smartcontract.SmartContractAgent.init(allocator, &rpc_client);
        try agent_manager.registerAgent(&smartcontract_agent.agent);

        if (args.len > 1) {
            const command = args[1];
            const command_args = if (args.len > 2) args[2..] else &[_][:0]u8{};

            const result = try agent_manager.executeCommand(.smartcontract, command, command_args);
            if (result.success) {
                std.debug.print("✅ {s}\n", .{result.message});
            } else {
                std.debug.print("❌ {s}\n", .{result.message});
            }
        } else {
            std.debug.print("Available smartcontract commands: deploy, call, send, audit, estimate, events, code\n", .{});
        }
    } else if (std.mem.eql(u8, agent_type_str, "network")) {
        var network_agent = agent.network.NetworkAgent.init(allocator);
        try agent_manager.registerAgent(&network_agent.agent);

        if (args.len > 1) {
            const command = args[1];
            const command_args = if (args.len > 2) args[2..] else &[_][:0]u8{};

            const result = try agent_manager.executeCommand(.network, command, command_args);
            if (result.success) {
                std.debug.print("✅ {s}\n", .{result.message});
            } else {
                std.debug.print("❌ {s}\n", .{result.message});
            }
        } else {
            std.debug.print("Available blockchain commands: status, balance, block, gas, health, monitor\n", .{});
        }
    } else if (std.mem.eql(u8, agent_type_str, "smartcontract")) {
        var rpc_client = agent.blockchain.RpcClient.init(allocator, "http://localhost:8545");
        var smartcontract_agent = agent.smartcontract.SmartContractAgent.init(allocator, &rpc_client);
        try agent_manager.registerAgent(&smartcontract_agent.agent);

        if (args.len > 1) {
            const command = args[1];
            const command_args = if (args.len > 2) args[2..] else &[_][:0]u8{};

            const result = try agent_manager.executeCommand(.smartcontract, command, command_args);
            if (result.success) {
                std.debug.print("✅ {s}\n", .{result.message});
            } else {
                std.debug.print("❌ {s}\n", .{result.message});
            }
        } else {
            std.debug.print("Available smartcontract commands: deploy, call, send, audit, estimate, events, code\n", .{});
        }
    } else if (std.mem.eql(u8, agent_type_str, "network")) {
        var network_agent = agent.network.NetworkAgent.init(allocator);
        try agent_manager.registerAgent(&network_agent.agent);

        if (args.len > 1) {
            const command = args[1];
            const command_args = if (args.len > 2) args[2..] else &[_][:0]u8{};

            const result = try agent_manager.executeCommand(.network, command, command_args);
            if (result.success) {
                std.debug.print("✅ {s}\n", .{result.message});
            } else {
                std.debug.print("❌ {s}\n", .{result.message});
            }
        } else {
            std.debug.print("Available network commands: scan, ping, ports, monitor, trace\n", .{});
        }
    } else if (std.mem.eql(u8, agent_type_str, "security")) {
        var security_agent = agent.security.SecurityAgent.init(allocator);
        try agent_manager.registerAgent(&security_agent.agent);

        if (args.len > 1) {
            const command = args[1];
            const command_args = if (args.len > 2) args[2..] else &[_][:0]u8{};

            const result = try agent_manager.executeCommand(.security, command, command_args);
            if (result.success) {
                std.debug.print("✅ {s}\n", .{result.message});
            } else {
                std.debug.print("❌ {s}\n", .{result.message});
            }
        } else {
            std.debug.print("Available security commands: scan, monitor, harden, audit, firewall, encrypt\n", .{});
        }
    } else if (std.mem.eql(u8, agent_type_str, "list")) {
        std.debug.print("🤖 Available Agent Types:\n", .{});
        std.debug.print("  • blockchain - Blockchain network operations\n", .{});
        std.debug.print("  • smartcontract - Smart contract interactions\n", .{});
        std.debug.print("  • network - Network monitoring and scanning\n", .{});
        std.debug.print("  • security - Security analysis and hardening\n", .{});
    } else {
        std.debug.print("Unknown agent type: {s}\n", .{agent_type_str});
        std.debug.print("Available types: blockchain, smartcontract, network, security\n", .{});
        std.debug.print("Use 'zeke agent list' to see all available agents\n", .{});
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

    const response = zeke_instance.chatWithUsage(message) catch |err| {
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
    defer allocator.free(response.content);
    defer allocator.free(response.model);

    const formatted_response = try formatter.formatResponse(response.content);
    defer allocator.free(formatted_response);

    std.debug.print("{s}", .{formatted_response});

    // Display token usage if available
    if (response.usage) |usage| {
        zeke_instance.token_tracker.printCompact(zeke_instance.current_provider, usage);
    }
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
    const prompt = try std.fmt.allocPrint(allocator, "Generate {s}: {s}", .{ language orelse "code", description });
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
    const file_contents = std.fs.cwd().readFileAlloc(file_path, allocator, @as(std.Io.Limit, @enumFromInt(1024 * 1024))) catch |err| {
        std.log.err("Failed to read file {s}: {}", .{ file_path, err });
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
    } else {
        std.debug.print("🚧 Provider {s} authentication not yet implemented\n", .{provider});
    }
}

fn handleAuthList() !void {
    std.debug.print("🔑 Supported providers:\n", .{});
    std.debug.print("  • github - GitHub Copilot\n", .{});
    std.debug.print("  • openai - OpenAI GPT models\n", .{});
    std.debug.print("  • claude - Anthropic Claude\n", .{});
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
    else if (std.mem.eql(u8, provider_str, "xai"))
        zeke.api.ApiProvider.xai
    else if (std.mem.eql(u8, provider_str, "azure"))
        zeke.api.ApiProvider.azure
    else if (std.mem.eql(u8, provider_str, "ollama"))
        zeke.api.ApiProvider.ollama
    else if (std.mem.eql(u8, provider_str, "github") or std.mem.eql(u8, provider_str, "copilot") or std.mem.eql(u8, provider_str, "github_copilot"))
        zeke.api.ApiProvider.github_copilot
    else {
        std.debug.print("❌ Unknown provider: {s}\n", .{provider_str});
        std.debug.print("Available providers: openai, claude, xai, azure, ollama, github_copilot\n", .{});
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

        std.debug.print("{s} {s}: {d}ms, {d}% errors\n", .{ health_icon, @tagName(status.provider), response_time, error_rate });
    }
}

fn handleProviderList() !void {
    std.debug.print("📋 Available providers:\n", .{});
    std.debug.print("  • openai - OpenAI GPT models\n", .{});
    std.debug.print("  • claude - Anthropic Claude models (OAuth)\n", .{});
    std.debug.print("  • github_copilot - GitHub Copilot Pro (OAuth) - 19+ models\n", .{});
    std.debug.print("  • xai - xAI Grok models\n", .{});
    std.debug.print("  • google - Google Gemini models\n", .{});
    std.debug.print("  • azure - Azure OpenAI\n", .{});
    std.debug.print("  • ollama - Local Ollama instance\n", .{});
}

/// Check if a flag exists in args
fn hasFlag(args: []const [:0]u8, flag: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, flag)) return true;
    }
    return false;
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
    const file_contents = std.fs.cwd().readFileAlloc(file_path, allocator, @as(std.Io.Limit, @enumFromInt(1024 * 1024))) catch |err| {
        std.log.err("Failed to read file {s}: {}", .{ file_path, err });
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
    const WelcomeScreen = @import("tui/welcome_screen.zig").WelcomeScreen;
    const input = @import("tui/input.zig");
    const commands = @import("tui/commands.zig");
    const Session = @import("tui/session.zig").Session;
    const ThinkingIndicator = @import("tui/thinking.zig").ThinkingIndicator;
    const status_bar = @import("tui/status_bar.zig");

    // Get username from environment
    const username = std.posix.getenv("USER") orelse "User";

    // Get current directory
    var cwd_buf: [1024]u8 = undefined;
    const cwd = try std.fs.cwd().realpath(".", &cwd_buf);

    // Get current model and provider
    const model_display = zeke_instance.config.default_model;
    const provider_display = zeke_instance.config.providers.default_provider;

    // Create session
    var session = try Session.init(allocator, provider_display, model_display);
    defer session.deinit();

    // Create welcome screen
    var screen = try WelcomeScreen.init(
        allocator,
        username,
        model_display,
        cwd,
    );
    defer screen.deinit();

    // Initialize terminal in raw mode
    var term_state = try input.TerminalState.init();
    defer term_state.deinit();

    const stdout = std.posix.STDOUT_FILENO;
    const stdin = std.posix.STDIN_FILENO;

    // Set up full-screen TUI layout
    const layout_mod = @import("tui/layout.zig");
    const dims = try layout_mod.Dimensions.get();
    const layout = layout_mod.Layout.init(dims);

    // Clear screen and hide cursor
    try layout_mod.Layout.clearScreen(stdout);
    try layout_mod.Layout.hideCursor(stdout);

    // Render welcome screen in upper portion
    {
        try screen.build();
        var stdout_buf: [8192]u8 = undefined;
        const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
        const writer = stdout_file.writer(&stdout_buf);
        try screen.render(writer);
    }

    // Position cursor at input line
    const input_row = layout.dims.height - 1;
    try layout_mod.Layout.moveCursor(stdout, input_row, 1);
    try layout_mod.Layout.showCursor(stdout);
    _ = try std.posix.write(stdout, "> ");

    // Input buffer for command input
    var input_buffer = try std.array_list.AlignedManaged(u8, null).initCapacity(allocator, 256);
    defer input_buffer.deinit();

    // Input history for arrow up/down navigation
    var input_history = status_bar.InputHistory.init(allocator, 100);
    defer input_history.deinit();

    // Running state
    var running: bool = true;

    // Main event loop
    while (running) {
        // Read keyboard input (blocking with 100ms timeout)
        var read_buf: [32]u8 = undefined;
        const nread = std.posix.read(stdin, &read_buf) catch |err| {
            std.debug.print("Read error: {}\n", .{err});
            break;
        };

        if (nread == 0) continue; // Timeout, no input

        // Parse the key event
        const key_event = input.KeyEvent.parse(read_buf[0..nread]);

        // Handle key events
        switch (key_event) {
            .ctrl_c, .ctrl_d => {
                running = false;
            },
            .escape => {
                // ESC key also exits
                running = false;
            },
            .tab => {
                // Toggle thinking mode
                session.toggleThinking();
                const status = if (session.thinking_mode) "ON" else "OFF";
                const msg = try std.fmt.allocPrint(allocator, "\r\n🧠 Thinking mode: {s}\r\n", .{status});
                defer allocator.free(msg);
                _ = try std.posix.write(stdout, msg);
            },
            .enter => {
                // Submit command
                if (input_buffer.items.len > 0) {
                    _ = try std.posix.write(stdout, "\r\n");

                    // Add to history
                    try input_history.add(input_buffer.items);

                    // Parse command
                    const cmd = try commands.Command.parse(allocator, input_buffer.items);
                    defer cmd.deinit(allocator);

                    switch (cmd) {
                        .empty => {},
                        .chat => |message| {
                            // Add user message to history
                            try session.addMessage(.user, message);

                            // Echo user message
                            const user_msg = try std.fmt.allocPrint(allocator, "💬 You: {s}\r\n\r\n", .{message});
                            defer allocator.free(user_msg);
                            _ = try std.posix.write(stdout, user_msg);

                            // Show thinking indicator while waiting for AI
                            var thinking = ThinkingIndicator.init("Thinking...");
                            try thinking.write(stdout);

                            try session.startStreaming();

                            // Get AI response with comprehensive error handling
                            var had_error = false;
                            const ai_response = zeke_instance.chat(message) catch |err| blk: {
                                try ThinkingIndicator.clear(stdout);
                                session.cancelStreaming();
                                had_error = true;

                                // Provide helpful error message with suggestion
                                const error_name = @errorName(err);
                                const error_msg = try std.fmt.allocPrint(
                                    allocator,
                                    "🤖 AI: ❌ Error: {s}\r\n💡 Tip: Type /help for available commands or try /provider to switch providers\r\n",
                                    .{error_name},
                                );
                                break :blk error_msg;
                            };
                            defer allocator.free(ai_response);

                            // If error occurred, the message is already formatted with prefix
                            if (had_error) {
                                _ = try std.posix.write(stdout, ai_response);
                            } else {
                                // Clear thinking indicator and show AI prefix
                                try ThinkingIndicator.clear(stdout);
                                _ = try std.posix.write(stdout, "🤖 AI: ");

                                // Stream response character-by-character
                                for (ai_response) |char| {
                                    const char_buf = [_]u8{char};
                                    _ = try std.posix.write(stdout, &char_buf);
                                    // Small delay for visual effect (10ms per char)
                                    std.Thread.sleep(10 * std.time.ns_per_ms);
                                }

                                _ = try std.posix.write(stdout, "\r\n");

                                // Save to history
                                try session.appendChunk(ai_response);
                                try session.finishStreaming();
                            }
                        },
                        .slash => |slash_cmd| {
                            // Execute slash command
                            const result = try slash_cmd.execute(allocator, &session);
                            defer allocator.free(result);

                            // Handle special commands
                            if (std.mem.eql(u8, result, "[EXIT]")) {
                                running = false;
                            } else if (std.mem.eql(u8, result, "[CLEAR_SCREEN]")) {
                                // Clear and re-render
                                try screen.build();
                                var stdout_buf: [8192]u8 = undefined;
                                const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
                                const writer = stdout_file.writer(&stdout_buf);
                                try screen.render(writer);
                            } else {
                                // Display result
                                const output = try std.fmt.allocPrint(allocator, "ℹ️  {s}\r\n", .{result});
                                defer allocator.free(output);
                                _ = try std.posix.write(stdout, output);
                            }
                        },
                    }

                    // Clear input buffer
                    input_buffer.clearRetainingCapacity();

                    // Show prompt
                    _ = try std.posix.write(stdout, "\r\n> ");
                }
            },
            .backspace => {
                // Remove last character from input buffer
                if (input_buffer.items.len > 0) {
                    _ = input_buffer.pop();
                    // Visual feedback: backspace, space, backspace
                    _ = try std.posix.write(stdout, "\x08 \x08");
                }
            },
            .char => |c| {
                // Add character to input buffer
                try input_buffer.append(c);
                // Echo the character
                const char_buf = [_]u8{c};
                _ = try std.posix.write(stdout, &char_buf);
            },
            .arrow_up => {
                // Navigate to previous history entry
                if (input_history.navigatePrevious()) |prev| {
                    // Clear current line
                    _ = try std.posix.write(stdout, "\r> ");
                    for (0..input_buffer.items.len) |_| {
                        _ = try std.posix.write(stdout, " ");
                    }

                    // Replace with history entry
                    input_buffer.clearRetainingCapacity();
                    try input_buffer.appendSlice(prev);

                    // Render new input
                    _ = try std.posix.write(stdout, "\r> ");
                    _ = try std.posix.write(stdout, prev);
                }
            },
            .arrow_down => {
                // Navigate to next history entry
                if (input_history.navigateNext()) |next| {
                    // Clear current line
                    _ = try std.posix.write(stdout, "\r> ");
                    for (0..input_buffer.items.len) |_| {
                        _ = try std.posix.write(stdout, " ");
                    }

                    // Replace with history entry
                    input_buffer.clearRetainingCapacity();
                    try input_buffer.appendSlice(next);

                    // Render new input
                    _ = try std.posix.write(stdout, "\r> ");
                    _ = try std.posix.write(stdout, next);
                } else {
                    // Reached end of history, clear input
                    _ = try std.posix.write(stdout, "\r> ");
                    for (0..input_buffer.items.len) |_| {
                        _ = try std.posix.write(stdout, " ");
                    }
                    input_buffer.clearRetainingCapacity();
                    _ = try std.posix.write(stdout, "\r> ");
                }
            },
            .ctrl_l => {
                // Clear screen and re-render welcome
                try screen.build();
                var stdout_buf: [16384]u8 = undefined;
                const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
                var file_writer = stdout_file.writer(&stdout_buf);
                try screen.render(&file_writer.interface);
                try file_writer.interface.flush();
            },
            .ctrl_u => {
                // Clear input line
                const clear_len = input_buffer.items.len;
                var i: usize = 0;
                while (i < clear_len) : (i += 1) {
                    _ = try std.posix.write(stdout, "\x08 \x08");
                }
                input_buffer.clearRetainingCapacity();
            },
            else => {
                // Ignore unknown escape sequences
            },
        }
    }

    // Clean exit message
    _ = try std.posix.write(stdout, "\r\n⚡ Goodbye!\r\n");
}

fn handleNvimCommand(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: zeke nvim <subcommand>\n", .{});
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "--rpc")) {
        try handleRPCServer(zeke_instance, allocator);
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
    std.debug.print("🚀 Starting ZEKE GhostRPC server...\n", .{});

    var rpc_server = try zeke.rpc.GhostRPC.init(allocator, zeke_instance);
    defer rpc_server.deinit();

    // Set up graceful shutdown with zsync
    const SignalHandler = struct {
        server: *zeke.rpc.MsgPackRPC,
        // cancel_token: zsync.CancelToken,

        fn init(server: *zeke.rpc.MsgPackRPC) @This() {
            return @This(){
                .server = server,
                // .cancel_token = zsync.CancelToken.init(),
            };
        }

        fn deinit(self: *@This()) void {
            // TODO: Implement proper cleanup when cancel_token is restored
            _ = self;
        }

        fn setup(self: *@This()) void {
            // TODO: Set up actual signal handling with zsync
            _ = self;
        }

        fn handle(self: *@This()) void {
            std.debug.print("\n🛑 Received shutdown signal, stopping RPC server...\n", .{});
            self.server.stop();
            self.cancel_token.cancel();
        }
    };

    var signal_handler = SignalHandler.init(&rpc_server);
    defer signal_handler.deinit();
    signal_handler.setup();

    // Start the RPC server
    try rpc_server.start();

    std.debug.print("✅ RPC server stopped\n", .{});
}

fn handleNvimChat(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, message: []const u8) !void {
    const response = zeke_instance.chat(message) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Chat failed: {}", .{err});
        defer allocator.free(error_msg);

        const json_response = try std.fmt.allocPrint(allocator, "{{\"success\": false, \"error\": \"{s}\", \"content\": null}}", .{error_msg});
        defer allocator.free(json_response);

        std.debug.print("{s}\n", .{json_response});
        return;
    };
    defer allocator.free(response);

    const json_response = try std.fmt.allocPrint(allocator, "{{\"success\": true, \"error\": null, \"content\": \"{s}\"}}", .{response});
    defer allocator.free(json_response);

    std.debug.print("{s}\n", .{json_response});
}

fn handleNvimEdit(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, code: []const u8, instruction: []const u8) !void {
    const edit_prompt = try std.fmt.allocPrint(allocator, "Edit this code according to the instruction.\n\nInstruction: {s}\n\nCode:\n{s}", .{ instruction, code });
    defer allocator.free(edit_prompt);

    const response = zeke_instance.chat(edit_prompt) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Edit failed: {}", .{err});
        defer allocator.free(error_msg);

        const json_response = try std.fmt.allocPrint(allocator, "{{\"success\": false, \"error\": \"{s}\", \"content\": null}}", .{error_msg});
        defer allocator.free(json_response);

        std.debug.print("{s}\n", .{json_response});
        return;
    };
    defer allocator.free(response);

    const json_response = try std.fmt.allocPrint(allocator, "{{\"success\": true, \"error\": null, \"content\": \"{s}\"}}", .{response});
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

        const json_response = try std.fmt.allocPrint(allocator, "{{\"success\": false, \"error\": \"{s}\", \"content\": null}}", .{error_msg});
        defer allocator.free(json_response);

        std.debug.print("{s}\n", .{json_response});
        return;
    };
    defer explanation.deinit(allocator);

    const json_response = try std.fmt.allocPrint(allocator, "{{\"success\": true, \"error\": null, \"content\": \"{s}\"}}", .{explanation.explanation});
    defer allocator.free(json_response);

    std.debug.print("{s}\n", .{json_response});
}

fn handleNvimCreate(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, description: []const u8) !void {
    const create_prompt = try std.fmt.allocPrint(allocator, "Create a file with the following description: {s}", .{description});
    defer allocator.free(create_prompt);

    const response = zeke_instance.chat(create_prompt) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Create failed: {}", .{err});
        defer allocator.free(error_msg);

        const json_response = try std.fmt.allocPrint(allocator, "{{\"success\": false, \"error\": \"{s}\", \"content\": null}}", .{error_msg});
        defer allocator.free(json_response);

        std.debug.print("{s}\n", .{json_response});
        return;
    };
    defer allocator.free(response);

    const json_response = try std.fmt.allocPrint(allocator, "{{\"success\": true, \"error\": null, \"content\": \"{s}\"}}", .{response});
    defer allocator.free(json_response);

    std.debug.print("{s}\n", .{json_response});
}

fn handleGitCommand(allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: zeke git <subcommand>\n", .{});
        return;
    }

    var git_client = git_ops.GitOps.init(allocator);
    defer git_client.deinit();

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "status")) {
        if (!git_client.isGitRepo()) {
            std.debug.print("❌ Not in a git repository\n", .{});
            return;
        }

        const files = git_client.getStatus() catch |err| {
            std.debug.print("❌ Failed to get git status: {}\n", .{err});
            return;
        };
        defer {
            for (files) |*file| {
                file.deinit(allocator);
            }
            allocator.free(files);
        }

        if (files.len == 0) {
            std.debug.print("✅ Working directory is clean\n", .{});
            return;
        }

        std.debug.print("📋 Git Status:\n", .{});
        for (files) |file| {
            const status_icon = switch (file.status) {
                .modified => "🔶",
                .added => "✅",
                .deleted => "❌",
                .renamed => "🔄",
                .untracked => "❓",
                .staged => "📦",
            };
            std.debug.print("  {s} {s}\n", .{ status_icon, file.path });
        }
    } else if (std.mem.eql(u8, subcommand, "diff")) {
        const file_path = if (args.len > 1) args[1] else null;
        const diff = git_client.getDiff(file_path) catch |err| {
            std.debug.print("❌ Failed to get diff: {}\n", .{err});
            return;
        };
        defer allocator.free(diff);

        if (diff.len == 0) {
            std.debug.print("✅ No changes to show\n", .{});
        } else {
            std.debug.print("📝 Git Diff:\n{s}\n", .{diff});
        }
    } else if (std.mem.eql(u8, subcommand, "add")) {
        if (args.len < 2) {
            std.debug.print("Usage: zeke git add <file_path>\n", .{});
            return;
        }

        git_client.addFile(args[1]) catch |err| {
            std.debug.print("❌ Failed to add file: {}\n", .{err});
            return;
        };

        std.debug.print("✅ Added file: {s}\n", .{args[1]});
    } else if (std.mem.eql(u8, subcommand, "commit")) {
        // Smart commit - AI-powered by default!
        if (args.len >= 2) {
            // Manual commit with user-provided message
            git_client.commit(args[1]) catch |err| {
                std.debug.print("❌ Failed to commit: {}\n", .{err});
                return;
            };
            std.debug.print("✅ Committed with message: {s}\n", .{args[1]});
        } else {
            // No message - use AI to generate it
            std.debug.print("🤖 Generating AI-powered commit message...\n", .{});

            var smart_git = tools.SmartGit.init(allocator);
            defer smart_git.deinit();

            smart_git.smartCommit(null) catch |err| {
                std.debug.print("❌ Smart commit failed: {}\n", .{err});
                std.debug.print("💡 Tip: Provide a message with 'zeke git commit \"your message\"'\n", .{});
                return;
            };
        }
    } else if (std.mem.eql(u8, subcommand, "branch")) {
        const branch = git_client.getCurrentBranch() catch |err| {
            std.debug.print("❌ Failed to get current branch: {}\n", .{err});
            return;
        };
        defer allocator.free(branch);

        std.debug.print("🌿 Current branch: {s}\n", .{branch});
    } else if (std.mem.eql(u8, subcommand, "pr")) {
        if (args.len < 3) {
            std.debug.print("Usage: zeke git pr <title> <body> [base_branch]\n", .{});
            return;
        }

        const title = args[1];
        const body = args[2];
        const base_branch = if (args.len > 3) args[3] else "main";

        git_client.createPullRequest(title, body, base_branch) catch |err| {
            std.debug.print("❌ Failed to create PR: {}\n", .{err});
            return;
        };

        std.debug.print("✅ Pull request created successfully\n", .{});
    } else if (std.mem.eql(u8, subcommand, "info")) {
        var git_info = git_client.getGitInfo() catch |err| {
            std.debug.print("❌ Failed to get git info: {}\n", .{err});
            return;
        };
        defer git_info.deinit(allocator);

        std.debug.print("📋 Git Repository Info:\n", .{});
        std.debug.print("  Branch: {s}\n", .{git_info.branch});
        std.debug.print("  Commit: {s}\n", .{git_info.commit_hash[0..8]});
        std.debug.print("  Status: {s}\n", .{if (git_info.is_dirty) "🔶 Dirty" else "✅ Clean"});
    } else if (std.mem.eql(u8, subcommand, "scan") or std.mem.eql(u8, subcommand, "security")) {
        // AI-powered security scan
        std.debug.print("🔒 Running security scan...\n", .{});

        var smart_git = tools.SmartGit.init(allocator);
        defer smart_git.deinit();

        const commit_range = if (args.len > 1) args[1] else null;
        smart_git.securityScan(commit_range) catch |err| {
            std.debug.print("❌ Security scan failed: {}\n", .{err});
            return;
        };
    } else if (std.mem.eql(u8, subcommand, "explain")) {
        // Explain changes in plain English
        const commit_ref = if (args.len > 1) args[1] else null;

        var smart_git = tools.SmartGit.init(allocator);
        defer smart_git.deinit();

        smart_git.explainChanges(commit_ref) catch |err| {
            std.debug.print("❌ Explain failed: {}\n", .{err});
            return;
        };
    } else if (std.mem.eql(u8, subcommand, "changelog")) {
        // Generate changelog
        if (args.len < 3) {
            std.debug.print("Usage: zeke git changelog <from_ref> <to_ref> [output_file]\n", .{});
            return;
        }

        const from_ref = args[1];
        const to_ref = args[2];
        const output_file = if (args.len > 3) args[3] else null;

        var smart_git = tools.SmartGit.init(allocator);
        defer smart_git.deinit();

        smart_git.generateChangelog(from_ref, to_ref, output_file) catch |err| {
            std.debug.print("❌ Changelog generation failed: {}\n", .{err});
            return;
        };
    } else if (std.mem.eql(u8, subcommand, "resolve")) {
        // AI-assisted conflict resolution
        if (args.len < 2) {
            std.debug.print("Usage: zeke git resolve <file_path>\n", .{});
            return;
        }

        var smart_git = tools.SmartGit.init(allocator);
        defer smart_git.deinit();

        smart_git.resolveConflict(args[1]) catch |err| {
            std.debug.print("❌ Conflict resolution failed: {}\n", .{err});
            return;
        };
    } else {
        std.debug.print("Unknown git subcommand: {s}\n", .{subcommand});
        std.debug.print("\n📋 Available Git Commands:\n", .{});
        std.debug.print("  Basic:\n", .{});
        std.debug.print("    status              - Show repository status\n", .{});
        std.debug.print("    diff [file]         - Show changes\n", .{});
        std.debug.print("    add <file>          - Stage file\n", .{});
        std.debug.print("    commit [message]    - Commit (AI-powered if no message)\n", .{});
        std.debug.print("    branch              - Show current branch\n", .{});
        std.debug.print("    info                - Show repo info\n", .{});
        std.debug.print("\n  AI-Powered:\n", .{});
        std.debug.print("    scan                - Security scan for sensitive files\n", .{});
        std.debug.print("    explain [ref]       - Explain changes in plain English\n", .{});
        std.debug.print("    changelog <from> <to> [file] - Generate changelog\n", .{});
        std.debug.print("    resolve <file>      - AI-assisted conflict resolution\n", .{});
        std.debug.print("\n  GitHub:\n", .{});
        std.debug.print("    pr <title> <body> [base] - Create pull request\n", .{});
    }
}

fn handleSearchCommand(allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: zeke search <subcommand>\n", .{});
        return;
    }

    var searcher = search.FileSearch.init(allocator);
    defer searcher.deinit();

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "content")) {
        if (args.len < 2) {
            std.debug.print("Usage: zeke search content <pattern> [path]\n", .{});
            return;
        }

        const pattern = args[1];
        const root_path = if (args.len > 2) args[2] else ".";

        const options = search.SearchOptions{
            .case_sensitive = false,
            .context_lines = 2,
            .max_results = 50,
        };

        const results = searcher.searchInFiles(pattern, root_path, options) catch |err| {
            std.debug.print("❌ Search failed: {}\n", .{err});
            return;
        };
        defer {
            for (results) |*result| {
                result.deinit(allocator);
            }
            allocator.free(results);
        }

        if (results.len == 0) {
            std.debug.print("🔍 No matches found for pattern: {s}\n", .{pattern});
            return;
        }

        std.debug.print("🔍 Found {d} matches for pattern: {s}\n", .{ results.len, pattern });
        for (results) |result| {
            std.debug.print("\n📁 {s}:{d}\n", .{ result.file_path, result.line_number });
            std.debug.print("   {s}\n", .{result.content});
        }
    } else if (std.mem.eql(u8, subcommand, "files")) {
        if (args.len < 2) {
            std.debug.print("Usage: zeke search files <name_pattern> [path]\n", .{});
            return;
        }

        const name_pattern = args[1];
        const root_path = if (args.len > 2) args[2] else ".";

        const files = searcher.findFiles(name_pattern, root_path) catch |err| {
            std.debug.print("❌ File search failed: {}\n", .{err});
            return;
        };
        defer {
            for (files) |file| {
                allocator.free(file);
            }
            allocator.free(files);
        }

        if (files.len == 0) {
            std.debug.print("📁 No files found matching: {s}\n", .{name_pattern});
            return;
        }

        std.debug.print("📁 Found {d} files matching: {s}\n", .{ files.len, name_pattern });
        for (files) |file_path| {
            std.debug.print("  {s}\n", .{file_path});
        }
    } else if (std.mem.eql(u8, subcommand, "grep")) {
        if (args.len < 2) {
            std.debug.print("Usage: zeke search grep <pattern> [file_patterns...]\n", .{});
            return;
        }

        const pattern = args[1];
        const file_patterns = if (args.len > 2) args[2..] else &[_][]const u8{"."};

        const options = search.SearchOptions{
            .case_sensitive = false,
            .context_lines = 1,
            .max_results = 100,
        };

        const results = searcher.grepCommand(pattern, file_patterns, options) catch |err| {
            std.debug.print("❌ Grep search failed: {}\n", .{err});
            // Fallback to internal search
            const fallback_results = searcher.searchInFiles(pattern, ".", options) catch |fallback_err| {
                std.debug.print("❌ Fallback search also failed: {}\n", .{fallback_err});
                return;
            };
            defer {
                for (fallback_results) |*result| {
                    result.deinit(allocator);
                }
                allocator.free(fallback_results);
            }

            std.debug.print("🔍 Fallback search found {d} matches\n", .{fallback_results.len});
            for (fallback_results) |result| {
                std.debug.print("📁 {s}:{d} - {s}\n", .{ result.file_path, result.line_number, result.content });
            }
            return;
        };
        defer {
            for (results) |*result| {
                result.deinit(allocator);
            }
            allocator.free(results);
        }

        if (results.len == 0) {
            std.debug.print("🔍 No matches found\n", .{});
            return;
        }

        std.debug.print("🔍 Found {d} matches\n", .{results.len});
        for (results) |result| {
            std.debug.print("📁 {s}:{d} - {s}\n", .{ result.file_path, result.line_number, result.content });
        }
    } else {
        std.debug.print("Unknown search subcommand: {s}\n", .{subcommand});
        std.debug.print("Available: content, files, grep\n", .{});
    }
}

fn handleBuildCommand(allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: zeke build <subcommand>\n", .{});
        return;
    }

    var builder = build_ops.BuildOps.init(allocator);
    defer builder.deinit();

    const subcommand = args[0];
    const project_path = if (args.len > 1) args[1] else ".";

    if (std.mem.eql(u8, subcommand, "detect")) {
        const build_system = builder.detectBuildSystem(project_path);

        std.debug.print("🔍 Detected build system: {s}\n", .{@tagName(build_system)});

        const recommendations = switch (build_system) {
            .zig => "Use 'zeke build run' to build, 'zeke build test' to run tests",
            .cargo => "Use 'cargo build' to build, 'cargo test' to run tests",
            .npm => "Use 'npm run build' to build, 'npm test' to run tests",
            .make => "Use 'make' to build, 'make test' to run tests",
            .cmake => "Use 'cmake --build build' to build",
            .gradle => "Use './gradlew build' to build, './gradlew test' to run tests",
            .maven => "Use 'mvn compile' to build, 'mvn test' to run tests",
            .go => "Use 'go build ./...' to build, 'go test ./...' to run tests",
            .unknown => "No known build system detected in this directory",
        };

        std.debug.print("💡 {s}\n", .{recommendations});
    } else if (std.mem.eql(u8, subcommand, "run")) {
        std.debug.print("🔨 Building project at: {s}\n", .{project_path});

        var result = builder.build(project_path, null) catch |err| {
            std.debug.print("❌ Build failed with error: {}\n", .{err});
            return;
        };
        defer result.deinit(allocator);

        if (result.success) {
            std.debug.print("✅ Build completed successfully in {}ms\n", .{result.build_time_ms});
            if (result.output.len > 0) {
                std.debug.print("📋 Build Output:\n{s}\n", .{result.output});
            }
        } else {
            std.debug.print("❌ Build failed in {}ms\n", .{result.build_time_ms});
            if (result.errors.len > 0) {
                std.debug.print("🚫 Build Errors:\n{s}\n", .{result.errors});
            }
            if (result.output.len > 0) {
                std.debug.print("📋 Build Output:\n{s}\n", .{result.output});
            }
        }
    } else if (std.mem.eql(u8, subcommand, "test")) {
        std.debug.print("🧪 Running tests for project at: {s}\n", .{project_path});

        var result = builder.test_(project_path, null) catch |err| {
            std.debug.print("❌ Tests failed with error: {}\n", .{err});
            return;
        };
        defer result.deinit(allocator);

        if (result.success) {
            std.debug.print("✅ Tests completed successfully in {}ms\n", .{result.build_time_ms});
            if (result.output.len > 0) {
                std.debug.print("📋 Test Output:\n{s}\n", .{result.output});
            }
        } else {
            std.debug.print("❌ Tests failed in {}ms\n", .{result.build_time_ms});
            if (result.errors.len > 0) {
                std.debug.print("🚫 Test Errors:\n{s}\n", .{result.errors});
            }
            if (result.output.len > 0) {
                std.debug.print("📋 Test Output:\n{s}\n", .{result.output});
            }
        }
    } else if (std.mem.eql(u8, subcommand, "clean")) {
        std.debug.print("🧹 Cleaning project at: {s}\n", .{project_path});

        var result = builder.clean(project_path, null) catch |err| {
            std.debug.print("❌ Clean failed with error: {}\n", .{err});
            return;
        };
        defer result.deinit(allocator);

        if (result.success) {
            std.debug.print("✅ Clean completed successfully in {}ms\n", .{result.build_time_ms});
            if (result.output.len > 0) {
                std.debug.print("📋 Clean Output:\n{s}\n", .{result.output});
            }
        } else {
            std.debug.print("❌ Clean failed in {}ms\n", .{result.build_time_ms});
            if (result.errors.len > 0) {
                std.debug.print("🚫 Clean Errors:\n{s}\n", .{result.errors});
            }
        }
    } else {
        std.debug.print("Unknown build subcommand: {s}\n", .{subcommand});
        std.debug.print("Available: run, test, clean, detect\n", .{});
    }
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

        const json_response = try std.fmt.allocPrint(allocator, "{{\"success\": false, \"error\": \"{s}\", \"content\": null}}", .{error_msg});
        defer allocator.free(json_response);

        std.debug.print("{s}\n", .{json_response});
        return;
    };
    defer analysis.deinit(allocator);

    const json_response = try std.fmt.allocPrint(allocator, "{{\"success\": true, \"error\": null, \"content\": \"{s}\"}}", .{analysis.analysis});
    defer allocator.free(json_response);

    std.debug.print("{s}\n", .{json_response});
}

fn printUsage() !void {
    std.debug.print("⚡ ZEKE v{s}\n", .{VERSION});
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
    std.debug.print("  zeke auth github                      - Start GitHub OAuth flow\n", .{});
    std.debug.print("  zeke auth test <provider>             - Test authentication\n", .{});
    std.debug.print("  zeke auth list                        - List auth providers\n", .{});
    std.debug.print("    Providers: openai, claude, xai, google, azure, ollama\n", .{});
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
    std.debug.print("\n🤖 Agent System:\n", .{});
    std.debug.print("  zeke agent list                       - List all available agents\n", .{});
    std.debug.print("  zeke agent blockchain <command>       - Blockchain operations\n", .{});
    std.debug.print("  zeke agent smartcontract <command>    - Smart contract interactions\n", .{});
    std.debug.print("  zeke agent network <command>          - Network monitoring/scanning\n", .{});
    std.debug.print("  zeke agent security <command>         - Security analysis/hardening\n", .{});
    std.debug.print("\n🔗 Git Integration:\n", .{});
    std.debug.print("  zeke git status                       - Show git repository status\n", .{});
    std.debug.print("  zeke git diff [file]                  - Show git diff for file or all files\n", .{});
    std.debug.print("  zeke git add <file>                   - Add file to git staging area\n", .{});
    std.debug.print("  zeke git commit <message>             - Commit staged changes\n", .{});
    std.debug.print("  zeke git branch                       - Show current git branch\n", .{});
    std.debug.print("  zeke git pr <title> <body> [base]     - Create pull request via GitHub CLI\n", .{});
    std.debug.print("  zeke git info                         - Show detailed git repository info\n", .{});
    std.debug.print("\n🔍 Search & Navigation:\n", .{});
    std.debug.print("  zeke search content <pattern> [path]  - Search for text patterns in files\n", .{});
    std.debug.print("  zeke search files <pattern> [path]    - Find files by name pattern\n", .{});
    std.debug.print("  zeke search grep <pattern> [files...] - Use ripgrep for advanced search\n", .{});
    std.debug.print("\n🔨 Build System Integration:\n", .{});
    std.debug.print("  zeke build detect [path]              - Detect project build system\n", .{});
    std.debug.print("  zeke build run [path]                 - Build the project\n", .{});
    std.debug.print("  zeke build test [path]                - Run project tests\n", .{});
    std.debug.print("  zeke build clean [path]               - Clean build artifacts\n", .{});
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
    std.debug.print("\n🔍 Watch Mode (Revolutionary):\n", .{});
    std.debug.print("  zeke watch                            - Auto-detect issues with Grove\n", .{});
    std.debug.print("  zeke watch --auto-fix                 - Auto-apply fixes via Ollama\n", .{});
    std.debug.print("  zeke watch --auto-commit              - Auto-commit when tests pass\n", .{});
    std.debug.print("\n🚀 Providers: claude, openai, copilot, ollama, xai, google, azure\n", .{});
    std.debug.print("🔍 Analysis: performance, security, style, quality, architecture\n", .{});
    std.debug.print("\n✨ v{s} Features:\n", .{VERSION});
    std.debug.print("  • GitHub Copilot Pro OAuth with 19+ models\n", .{});
    std.debug.print("  • Tokyo Night themes (Night/Moon/Storm)\n", .{});
    std.debug.print("  • Secure API key storage in keyring\n", .{});
    std.debug.print("  • Smart model routing\n", .{});
    std.debug.print("  • Token usage tracking and cost estimation\n", .{});
}

fn handleUsageCommand(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, subcommands: []const [:0]u8) !void {
    _ = allocator;

    if (subcommands.len > 0 and std.mem.eql(u8, subcommands[0], "reset")) {
        zeke_instance.token_tracker.reset();
        std.debug.print("✅ Token usage tracking has been reset.\n", .{});
    } else {
        try zeke_instance.printUsageSummary();
    }
}
