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
    } else if (std.mem.eql(u8, subcommand, "set-key")) {
        // Store API key in keyring
        if (args.len < 3) {
            std.debug.print("Usage: zeke auth set-key <provider> <api-key>\n", .{});
            std.debug.print("Example: zeke auth set-key google AIzaSy...\n", .{});
            std.debug.print("Example: zeke auth set-key openai sk-proj-...\n", .{});
            std.debug.print("\nSupported providers: openai, google, xai\n", .{});
            return;
        }

        const provider = args[1];
        const api_key = args[2];

        var auth = AuthManager.init(allocator);
        defer auth.deinit();

        // Store in keyring
        try auth.keyring.set("zeke", provider, api_key);

        std.debug.print("\n✅ API key for {s} stored securely in keyring\n", .{provider});
        std.debug.print("   (no longer need to set environment variable)\n\n", .{});
    } else if (std.mem.eql(u8, subcommand, "get-key")) {
        // Retrieve API key from keyring (for debugging)
        if (args.len < 2) {
            std.debug.print("Usage: zeke auth get-key <provider>\n", .{});
            std.debug.print("Example: zeke auth get-key google\n", .{});
            return;
        }

        const provider = args[1];
        var auth = AuthManager.init(allocator);
        defer auth.deinit();

        if (try auth.keyring.get("zeke", provider)) |key| {
            defer allocator.free(key);
            std.debug.print("\n🔑 API key for {s}: {s}\n\n", .{ provider, key });
        } else {
            std.debug.print("\n❌ No API key found for {s}\n\n", .{provider});
        }
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
        \\API Key Management (secure keyring storage):
        \\  zeke auth set-key <provider> <key>  - Store API key securely in system keyring
        \\  zeke auth get-key <provider>        - Retrieve stored API key (for debugging)
        \\
        \\Status:
        \\  zeke auth status                    - Show authentication status for all providers
        \\
        \\Logout:
        \\  zeke auth logout <provider>         - Remove OAuth tokens for a provider
        \\                                        (providers: anthropic, github)
        \\
        \\Examples:
        \\  zeke auth set-key google AIzaSy...   - Store Google Gemini API key
        \\  zeke auth set-key openai sk-proj-... - Store OpenAI API key
        \\  zeke auth set-key xai xai-...        - Store xAI API key
        \\
        \\Note: API keys can also be set via environment variables:
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
