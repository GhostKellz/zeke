const std = @import("std");

/// Enhanced help system with colors
pub const Help = struct {
    allocator: std.mem.Allocator,
    use_color: bool,

    const Color = struct {
        const reset = "\x1b[0m";
        const bold = "\x1b[1m";
        const dim = "\x1b[2m";
        const red = "\x1b[31m";
        const green = "\x1b[32m";
        const yellow = "\x1b[33m";
        const blue = "\x1b[34m";
        const magenta = "\x1b[35m";
        const cyan = "\x1b[36m";
    };

    pub fn init(allocator: std.mem.Allocator) Help {
        // Detect if stdout is a TTY
        const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
        const config = std.Io.tty.detectConfig(stdout_file);
        const use_color = config != .no_color;
        return .{
            .allocator = allocator,
            .use_color = use_color,
        };
    }

    pub fn showMain(self: Help) !void {
        const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
        var buf: [8192]u8 = undefined;
        var writer_struct = stdout_file.writer(&buf);
        const stdout = &writer_struct.interface;

        try self.printHeader(stdout);
        try stdout.writeAll("\n");
        try self.printUsage(stdout);
        try stdout.writeAll("\n");
        try self.printCommands(stdout);
        try stdout.writeAll("\n");
        try self.printOptions(stdout);
        try stdout.writeAll("\n");
        try self.printExamples(stdout);
        try stdout.writeAll("\n");
        try self.printFooter(stdout);
        try stdout.flush();
    }

    fn printHeader(self: Help, writer: anytype) !void {
        if (self.use_color) {
            try writer.print("{s}{s}⚡ ZEKE{s} v0.3.2\n", .{ Color.bold, Color.cyan, Color.reset });
        } else {
            try writer.writeAll("ZEKE v0.3.2\n");
        }
    }

    fn printUsage(self: Help, writer: anytype) !void {
        if (self.use_color) {
            try writer.print("{s}USAGE:{s}\n", .{ Color.bold, Color.reset });
        } else {
            try writer.writeAll("USAGE:\n");
        }
        try writer.writeAll("    zeke <COMMAND> [OPTIONS] [ARGS]\n");
    }

    fn printCommands(self: Help, writer: anytype) !void {
        if (self.use_color) {
            try writer.print("{s}COMMANDS:{s}\n", .{ Color.bold, Color.reset });
        } else {
            try writer.writeAll("COMMANDS:\n");
        }

        const commands = [_]struct { name: []const u8, emoji: []const u8, desc: []const u8 }{
            .{ .name = "chat", .emoji = "💬", .desc = "Chat with AI assistant" },
            .{ .name = "serve", .emoji = "🌐", .desc = "Start HTTP server (default: port 7878)" },
            .{ .name = "auth", .emoji = "🔑", .desc = "Manage provider authentication" },
            .{ .name = "config", .emoji = "⚙️ ", .desc = "View and modify configuration" },
            .{ .name = "doctor", .emoji = "🏥", .desc = "System health diagnostics" },
            .{ .name = "models", .emoji = "🤖", .desc = "List available AI models" },
            .{ .name = "provider", .emoji = "🔌", .desc = "Manage AI providers" },
            .{ .name = "analyze", .emoji = "🔍", .desc = "Analyze code quality and security" },
            .{ .name = "edit", .emoji = "✏️ ", .desc = "Edit files with AI assistance" },
            .{ .name = "refactor", .emoji = "♻️ ", .desc = "Refactor code with AI" },
            .{ .name = "generate", .emoji = "🏗️ ", .desc = "Generate code from templates" },
            .{ .name = "completion", .emoji = "📋", .desc = "Generate shell completions" },
        };

        for (commands) |cmd| {
            if (self.use_color) {
                try writer.print("    {s} {s}{s:<12}{s}  {s}{s}{s}\n", .{
                    cmd.emoji,
                    Color.green,
                    cmd.name,
                    Color.reset,
                    Color.dim,
                    cmd.desc,
                    Color.reset,
                });
            } else {
                try writer.print("    {s:<12}  {s}\n", .{ cmd.name, cmd.desc });
            }
        }
    }

    fn printOptions(self: Help, writer: anytype) !void {
        if (self.use_color) {
            try writer.print("{s}OPTIONS:{s}\n", .{ Color.bold, Color.reset });
        } else {
            try writer.writeAll("OPTIONS:\n");
        }

        const options = [_]struct { short: []const u8, long: []const u8, desc: []const u8 }{
            .{ .short = "-h", .long = "--help", .desc = "Show this help message" },
            .{ .short = "-v", .long = "--version", .desc = "Show version information" },
            .{ .short = "-m", .long = "--model <MODEL>", .desc = "Select AI model (auto, fast, smart, balanced, local)" },
            .{ .short = "-p", .long = "--provider <PROVIDER>", .desc = "Select AI provider (ollama, claude, openai, etc.)" },
            .{ .short = "", .long = "--log-level <LEVEL>", .desc = "Set logging level (debug, info, warn, error)" },
            .{ .short = "", .long = "--port <PORT>", .desc = "Server port for 'serve' command" },
            .{ .short = "", .long = "--config <FILE>", .desc = "Path to configuration file" },
        };

        for (options) |opt| {
            if (self.use_color) {
                if (opt.short.len > 0) {
                    try writer.print("    {s}{s}{s}, {s}{s:<20}{s}  {s}{s}{s}\n", .{
                        Color.yellow,
                        opt.short,
                        Color.reset,
                        Color.yellow,
                        opt.long,
                        Color.reset,
                        Color.dim,
                        opt.desc,
                        Color.reset,
                    });
                } else {
                    try writer.print("        {s}{s:<20}{s}  {s}{s}{s}\n", .{
                        Color.yellow,
                        opt.long,
                        Color.reset,
                        Color.dim,
                        opt.desc,
                        Color.reset,
                    });
                }
            } else {
                if (opt.short.len > 0) {
                    try writer.print("    {s}, {s:<20}  {s}\n", .{ opt.short, opt.long, opt.desc });
                } else {
                    try writer.print("        {s:<20}  {s}\n", .{ opt.long, opt.desc });
                }
            }
        }
    }

    fn printExamples(self: Help, writer: anytype) !void {
        if (self.use_color) {
            try writer.print("{s}EXAMPLES:{s}\n", .{ Color.bold, Color.reset });
        } else {
            try writer.writeAll("EXAMPLES:\n");
        }

        const examples = [_]struct { desc: []const u8, cmd: []const u8 }{
            .{ .desc = "Chat with AI about code", .cmd = "zeke chat \"How do I implement async in Zig?\"" },
            .{ .desc = "Start HTTP server", .cmd = "zeke serve" },
            .{ .desc = "Authenticate with Claude", .cmd = "zeke auth google" },
            .{ .desc = "Check system health", .cmd = "zeke doctor" },
            .{ .desc = "Edit a file", .cmd = "zeke edit src/main.zig \"add error handling\"" },
            .{ .desc = "Generate completions", .cmd = "zeke completion bash > /etc/bash_completion.d/zeke" },
        };

        for (examples) |ex| {
            if (self.use_color) {
                try writer.print("    {s}# {s}{s}\n", .{ Color.dim, ex.desc, Color.reset });
                try writer.print("    {s}$ {s}{s}{s}\n\n", .{ Color.dim, Color.green, ex.cmd, Color.reset });
            } else {
                try writer.print("    # {s}\n", .{ex.desc});
                try writer.print("    $ {s}\n\n", .{ex.cmd});
            }
        }
    }

    fn printFooter(self: Help, writer: anytype) !void {
        if (self.use_color) {
            try writer.print("{s}For more help on a specific command:{s}\n", .{ Color.dim, Color.reset });
            try writer.print("    {s}zeke <COMMAND> --help{s}\n\n", .{ Color.green, Color.reset });
            try writer.print("{s}Documentation:{s} https://github.com/ghostkellz/zeke\n", .{ Color.dim, Color.reset });
        } else {
            try writer.writeAll("For more help on a specific command:\n");
            try writer.writeAll("    zeke <COMMAND> --help\n\n");
            try writer.writeAll("Documentation: https://github.com/ghostkellz/zeke\n");
        }
    }

    /// Show help for specific command
    pub fn showCommand(self: Help, command: []const u8) !void {
        const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
        var buf: [8192]u8 = undefined;
        var writer_struct = stdout_file.writer(&buf);
        const stdout = &writer_struct.interface;

        if (std.mem.eql(u8, command, "chat")) {
            try self.showChatHelp(stdout);
        } else if (std.mem.eql(u8, command, "serve")) {
            try self.showServeHelp(stdout);
        } else if (std.mem.eql(u8, command, "auth")) {
            try self.showAuthHelp(stdout);
        } else if (std.mem.eql(u8, command, "config")) {
            try self.showConfigHelp(stdout);
        } else if (std.mem.eql(u8, command, "doctor")) {
            try self.showDoctorHelp(stdout);
        } else if (std.mem.eql(u8, command, "edit")) {
            try self.showEditHelp(stdout);
        } else {
            try stdout.print("No detailed help available for '{s}'\n", .{command});
            try stdout.writeAll("Run 'zeke --help' for general help\n");
        }
        try stdout.flush();
    }

    fn showChatHelp(self: Help, writer: anytype) !void {
        if (self.use_color) {
            try writer.print("{s}💬 zeke chat{s} - Chat with AI assistant\n\n", .{ Color.bold ++ Color.cyan, Color.reset });
        } else {
            try writer.writeAll("zeke chat - Chat with AI assistant\n\n");
        }

        try writer.writeAll("USAGE:\n");
        try writer.writeAll("    zeke chat [OPTIONS] <MESSAGE>\n\n");

        try writer.writeAll("OPTIONS:\n");
        try writer.writeAll("    -m, --model <MODEL>        AI model to use\n");
        try writer.writeAll("    -p, --provider <PROVIDER>  AI provider to use\n");
        try writer.writeAll("    --stream                   Stream response\n");
        try writer.writeAll("    --temperature <TEMP>       Response creativity (0.0-2.0)\n\n");

        try writer.writeAll("EXAMPLES:\n");
        try writer.writeAll("    zeke chat \"Explain async/await in Zig\"\n");
        try writer.writeAll("    zeke chat --model smart \"Design a REST API\"\n");
        try writer.writeAll("    zeke chat --provider ollama --stream \"Hello\"\n");
    }

    fn showServeHelp(self: Help, writer: anytype) !void {
        if (self.use_color) {
            try writer.print("{s}🌐 zeke serve{s} - Start HTTP server\n\n", .{ Color.bold ++ Color.cyan, Color.reset });
        } else {
            try writer.writeAll("zeke serve - Start HTTP server\n\n");
        }

        try writer.writeAll("USAGE:\n");
        try writer.writeAll("    zeke serve [OPTIONS]\n\n");

        try writer.writeAll("OPTIONS:\n");
        try writer.writeAll("    --port <PORT>      Server port (default: 7878)\n");
        try writer.writeAll("    --host <HOST>      Host address (default: 127.0.0.1)\n");
        try writer.writeAll("    --watch            Auto-reload on config changes\n\n");

        try writer.writeAll("EXAMPLES:\n");
        try writer.writeAll("    zeke serve\n");
        try writer.writeAll("    zeke serve --port 8080\n");
        try writer.writeAll("    zeke serve --watch\n");
    }

    fn showAuthHelp(self: Help, writer: anytype) !void {
        if (self.use_color) {
            try writer.print("{s}🔑 zeke auth{s} - Manage provider authentication\n\n", .{ Color.bold ++ Color.cyan, Color.reset });
        } else {
            try writer.writeAll("zeke auth - Manage provider authentication\n\n");
        }

        try writer.writeAll("USAGE:\n");
        try writer.writeAll("    zeke auth <SUBCOMMAND> [ARGS]\n\n");

        try writer.writeAll("SUBCOMMANDS:\n");
        try writer.writeAll("    google              Authenticate with Google OAuth\n");
        try writer.writeAll("    github              Authenticate with GitHub OAuth\n");
        try writer.writeAll("    openai <KEY>        Add OpenAI API key\n");
        try writer.writeAll("    anthropic <KEY>     Add Anthropic API key\n");
        try writer.writeAll("    xai <KEY>           Add xAI API key\n");
        try writer.writeAll("    azure <KEY>         Configure Azure OpenAI\n");
        try writer.writeAll("    list                List configured providers\n");
        try writer.writeAll("    test <PROVIDER>     Test authentication\n\n");

        try writer.writeAll("EXAMPLES:\n");
        try writer.writeAll("    zeke auth google\n");
        try writer.writeAll("    zeke auth openai sk-proj-...\n");
        try writer.writeAll("    zeke auth list\n");
        try writer.writeAll("    zeke auth test claude\n");
    }

    fn showConfigHelp(self: Help, writer: anytype) !void {
        if (self.use_color) {
            try writer.print("{s}⚙️  zeke config{s} - View and modify configuration\n\n", .{ Color.bold ++ Color.cyan, Color.reset });
        } else {
            try writer.writeAll("zeke config - View and modify configuration\n\n");
        }

        try writer.writeAll("USAGE:\n");
        try writer.writeAll("    zeke config <SUBCOMMAND> [ARGS]\n\n");

        try writer.writeAll("SUBCOMMANDS:\n");
        try writer.writeAll("    get <KEY>           Get configuration value\n");
        try writer.writeAll("    set <KEY> <VALUE>   Set configuration value\n");
        try writer.writeAll("    validate            Validate configuration file\n");
        try writer.writeAll("    show                Show current configuration\n");
        try writer.writeAll("    edit                Open configuration in editor\n\n");

        try writer.writeAll("EXAMPLES:\n");
        try writer.writeAll("    zeke config get default.provider\n");
        try writer.writeAll("    zeke config set providers.ollama.model qwen2.5-coder:7b\n");
        try writer.writeAll("    zeke config validate\n");
        try writer.writeAll("    zeke config show\n");
    }

    fn showDoctorHelp(self: Help, writer: anytype) !void {
        if (self.use_color) {
            try writer.print("{s}🏥 zeke doctor{s} - System health diagnostics\n\n", .{ Color.bold ++ Color.cyan, Color.reset });
        } else {
            try writer.writeAll("zeke doctor - System health diagnostics\n\n");
        }

        try writer.writeAll("USAGE:\n");
        try writer.writeAll("    zeke doctor [OPTIONS]\n\n");

        try writer.writeAll("DESCRIPTION:\n");
        try writer.writeAll("    Checks system health and provider availability.\n");
        try writer.writeAll("    Tests configuration, database, and all configured providers.\n\n");

        try writer.writeAll("OPTIONS:\n");
        try writer.writeAll("    --verbose          Show detailed diagnostic information\n");
        try writer.writeAll("    --fix              Attempt to fix common issues\n\n");

        try writer.writeAll("EXAMPLES:\n");
        try writer.writeAll("    zeke doctor\n");
        try writer.writeAll("    zeke doctor --verbose\n");
        try writer.writeAll("    zeke doctor --fix\n");
    }

    fn showEditHelp(self: Help, writer: anytype) !void {
        if (self.use_color) {
            try writer.print("{s}✏️  zeke edit{s} - Edit files with AI assistance\n\n", .{ Color.bold ++ Color.cyan, Color.reset });
        } else {
            try writer.writeAll("zeke edit - Edit files with AI assistance\n\n");
        }

        try writer.writeAll("USAGE:\n");
        try writer.writeAll("    zeke edit <FILE> <INSTRUCTION>\n\n");

        try writer.writeAll("OPTIONS:\n");
        try writer.writeAll("    --dry-run          Show diff without applying\n");
        try writer.writeAll("    --backup           Create backup before editing\n");
        try writer.writeAll("    --model <MODEL>    AI model to use\n\n");

        try writer.writeAll("EXAMPLES:\n");
        try writer.writeAll("    zeke edit src/main.zig \"add error handling\"\n");
        try writer.writeAll("    zeke edit --dry-run config.zig \"add comments\"\n");
        try writer.writeAll("    zeke edit --model smart app.rs \"refactor to async\"\n");
    }
};

/// Show main help
pub fn showHelp(allocator: std.mem.Allocator) !void {
    const help = Help.init(allocator);
    try help.showMain();
}

/// Show command-specific help
pub fn showCommandHelp(allocator: std.mem.Allocator, command: []const u8) !void {
    const help = Help.init(allocator);
    try help.showCommand(command);
}
