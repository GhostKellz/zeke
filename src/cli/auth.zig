const std = @import("std");
const zeke = @import("zeke");
const AuthManager = zeke.auth.AuthManager;
const AuthProvider = zeke.auth.AuthProvider;

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        printUsage();
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "google")) {
        var auth = try AuthManager.init(allocator);
        defer auth.deinit();
        const cred = try auth.authorizeGoogle();
        defer auth.freeCredential(cred);
        try auth.upsertCredential(cred);
    } else if (std.mem.eql(u8, subcommand, "github")) {
        var auth = try AuthManager.init(allocator);
        defer auth.deinit();
        const cred = try auth.authorizeGitHub();
        defer auth.freeCredential(cred);
        try auth.upsertCredential(cred);
    } else if (std.mem.eql(u8, subcommand, "openai") or
               std.mem.eql(u8, subcommand, "anthropic") or
               std.mem.eql(u8, subcommand, "azure")) {
        if (args.len < 2) {
            std.log.err("Usage: zeke auth {s} <api-key>", .{subcommand});
            return error.MissingApiKey;
        }

        const provider: AuthProvider = if (std.mem.eql(u8, subcommand, "openai"))
            .openai
        else if (std.mem.eql(u8, subcommand, "anthropic"))
            .anthropic
        else
            .azure;

        var auth = try AuthManager.init(allocator);
        defer auth.deinit();
        try auth.setApiKey(provider, args[1]);
    } else if (std.mem.eql(u8, subcommand, "list")) {
        var auth = try AuthManager.init(allocator);
        defer auth.deinit();

        std.log.info("🔑 Stored Credentials:", .{});
        inline for (@typeInfo(AuthProvider).@"enum".fields) |field| {
            const provider: AuthProvider = @enumFromInt(field.value);
            if (try auth.getCredential(provider)) |cred| {
                const has_key = cred.api_key != null;
                const has_token = cred.access_token != null;
                std.log.info("  • {s}: {s}", .{ 
                    @tagName(provider),
                    if (has_key) "API Key ✓" else if (has_token) "OAuth Token ✓" else "None"
                });
            }
        }
    } else {
        printUsage();
    }
}

fn printUsage() void {
    std.log.info(
        \\🔐 Zeke Authentication
        \\
        \\OAuth (for subscriptions):
        \\  zeke auth google                    - Google OAuth for Claude Max + ChatGPT Pro
        \\  zeke auth github                    - GitHub OAuth for Copilot Pro
        \\
        \\API Keys (for API access):
        \\  zeke auth openai <api-key>          - OpenAI API key
        \\  zeke auth anthropic <api-key>       - Anthropic API key (different from Claude Max!)
        \\  zeke auth azure <api-key>           - Azure OpenAI API key
        \\
        \\Other:
        \\  zeke auth list                      - List all stored credentials
        \\
        \\Note: Claude Max subscription uses Google OAuth, not API key!
        \\
        , .{});
}
