const std = @import("std");
const AuthManager = @import("../auth/manager.zig").AuthManager;
const GitHubOAuth = @import("../auth/github_oauth.zig").GitHubOAuth;

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        printUsage();
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "claude")) {
        // Anthropic OAuth login
        var auth = AuthManager.init(allocator);
        defer auth.deinit();

        std.debug.print("\n🔐 Authenticating with Anthropic Claude...\n", .{});
        try auth.loginAnthropic();
        std.debug.print("\n✅ Successfully authenticated with Claude!\n\n", .{});
    } else if (std.mem.eql(u8, subcommand, "copilot") or std.mem.eql(u8, subcommand, "github")) {
        // GitHub Copilot OAuth login (device flow)
        var github_oauth = GitHubOAuth.init(allocator);

        var tokens = try github_oauth.authorize();
        defer tokens.deinit(allocator);

        // Store the GitHub token using AuthManager's keyring
        var auth = AuthManager.init(allocator);
        defer auth.deinit();

        // Store GitHub access token in keyring
        try auth.keyring.set("zeke", "github", tokens.access_token);

        // Optionally store expiry info
        const now = std.time.timestamp();
        const expires_at = now + (90 * 24 * 60 * 60); // 90 days typical GitHub token expiry
        const expires_str = try std.fmt.allocPrint(allocator, "{d}", .{expires_at});
        defer allocator.free(expires_str);
        try auth.keyring.set("zeke", "github_expires", expires_str);

        std.debug.print("\n✅ Successfully authenticated with GitHub Copilot!\n", .{});
        std.debug.print("   Token will expire in ~90 days\n\n", .{});
    } else if (std.mem.eql(u8, subcommand, "status")) {
        // Show authentication status
        var auth = AuthManager.init(allocator);
        defer auth.deinit();
        try auth.printStatus();
    } else if (std.mem.eql(u8, subcommand, "logout")) {
        // Logout from provider
        if (args.len < 2) {
            std.debug.print("Usage: zeke auth logout <provider>\n", .{});
            std.debug.print("Example: zeke auth logout anthropic\n", .{});
            std.debug.print("Example: zeke auth logout github\n", .{});
            return;
        }

        const provider = args[1];
        var auth = AuthManager.init(allocator);
        defer auth.deinit();

        try auth.logout(provider);
    } else {
        printUsage();
    }
}

fn printUsage() void {
    std.debug.print(
        \\
        \\🔐 Zeke Authentication
        \\
        \\OAuth (for premium providers):
        \\  zeke auth claude                    - Authenticate with Anthropic Claude (OAuth PKCE)
        \\  zeke auth copilot                   - Authenticate with GitHub Copilot (Device Flow)
        \\  zeke auth github                    - Alias for 'copilot'
        \\
        \\Status:
        \\  zeke auth status                    - Show authentication status for all providers
        \\
        \\Logout:
        \\  zeke auth logout <provider>         - Remove OAuth tokens for a provider
        \\                                        (providers: anthropic, github)
        \\
        \\Note: API keys can still be set via environment variables:
        \\  - OPENAI_API_KEY          - OpenAI API key
        \\  - ANTHROPIC_API_KEY       - Anthropic API key
        \\  - GOOGLE_API_KEY          - Google API key
        \\  - XAI_API_KEY             - xAI API key
        \\  - Ollama is always available locally (no auth needed)
        \\
        \\Premium Subscriptions:
        \\  With OAuth, you can use your existing Claude Max or GitHub Copilot Pro
        \\  subscriptions without paying separately for API access!
        \\
        \\
    , .{});
}
