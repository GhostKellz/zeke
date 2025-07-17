const std = @import("std");

pub const AuthProvider = enum {
    github,
    google,
    openai,
    local,
};

const TokenEntry = struct {
    provider: AuthProvider,
    token: []const u8,
};

pub const TokenStorage = struct {
    allocator: std.mem.Allocator,
    tokens: std.ArrayList(TokenEntry),
    storage_path: []const u8,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch |err| {
            std.log.warn("Failed to get HOME directory: {}", .{err});
            return Self{
                .allocator = allocator,
                .tokens = std.ArrayList(TokenEntry).init(allocator),
                .storage_path = allocator.dupe(u8, "/tmp/.zeke_tokens") catch "",
            };
        };
        
        const storage_path = std.fmt.allocPrint(allocator, "{s}/.zeke_tokens", .{home_dir}) catch |err| {
            std.log.warn("Failed to create storage path: {}", .{err});
            allocator.free(home_dir);
            return Self{
                .allocator = allocator,
                .tokens = std.ArrayList(TokenEntry).init(allocator),
                .storage_path = allocator.dupe(u8, "/tmp/.zeke_tokens") catch "",
            };
        };
        allocator.free(home_dir);
        
        var self = Self{
            .allocator = allocator,
            .tokens = std.ArrayList(TokenEntry).init(allocator),
            .storage_path = storage_path,
        };
        
        self.loadFromFile() catch |err| {
            std.log.warn("Failed to load tokens from file: {}", .{err});
        };
        
        return self;
    }
    
    pub fn deinit(self: *Self) void {
        self.saveToFile() catch |err| {
            std.log.warn("Failed to save tokens to file: {}", .{err});
        };
        
        for (self.tokens.items) |entry| {
            self.allocator.free(entry.token);
        }
        self.tokens.deinit();
        self.allocator.free(self.storage_path);
    }
    
    pub fn setToken(self: *Self, provider: AuthProvider, token: []const u8) !void {
        // Remove existing token for this provider
        self.removeToken(provider);
        
        const encoded_token = try self.encodeToken(token);
        try self.tokens.append(TokenEntry{
            .provider = provider,
            .token = encoded_token,
        });
        
        // Save to file
        try self.saveToFile();
    }
    
    pub fn getToken(self: *Self, provider: AuthProvider) !?[]const u8 {
        for (self.tokens.items) |entry| {
            if (entry.provider == provider) {
                return try self.decodeToken(entry.token);
            }
        }
        return null;
    }
    
    pub fn removeToken(self: *Self, provider: AuthProvider) void {
        var i: usize = 0;
        while (i < self.tokens.items.len) {
            if (self.tokens.items[i].provider == provider) {
                const entry = self.tokens.swapRemove(i);
                self.allocator.free(entry.token);
                return;
            }
            i += 1;
        }
    }
    
    fn encodeToken(self: *Self, token: []const u8) ![]const u8 {
        // Simple base64 encoding for now
        const encoder = std.base64.standard.Encoder;
        const encoded_len = encoder.calcSize(token.len);
        const encoded = try self.allocator.alloc(u8, encoded_len);
        _ = encoder.encode(encoded, token);
        return encoded;
    }
    
    fn decodeToken(self: *Self, encoded: []const u8) ![]const u8 {
        const decoder = std.base64.standard.Decoder;
        const decoded_len = try decoder.calcSizeForSlice(encoded);
        const decoded = try self.allocator.alloc(u8, decoded_len);
        try decoder.decode(decoded, encoded);
        return decoded;
    }
    
    fn saveToFile(self: *Self) !void {
        const file = std.fs.cwd().createFile(self.storage_path, .{}) catch |err| {
            std.log.warn("Failed to create token storage file: {}", .{err});
            return;
        };
        defer file.close();
        
        // Create JSON object with tokens
        var json_tokens = std.ArrayList(u8).init(self.allocator);
        defer json_tokens.deinit();
        
        try json_tokens.appendSlice("{\n");
        for (self.tokens.items, 0..) |entry, i| {
            if (i > 0) try json_tokens.appendSlice(",\n");
            
            const provider_str = switch (entry.provider) {
                .github => "github",
                .google => "google",
                .openai => "openai",
                .local => "local",
            };
            
            try json_tokens.writer().print("  \"{s}\": \"{s}\"", .{ provider_str, entry.token });
        }
        try json_tokens.appendSlice("\n}\n");
        
        try file.writeAll(json_tokens.items);
    }
    
    fn loadFromFile(self: *Self) !void {
        const file = std.fs.cwd().openFile(self.storage_path, .{}) catch |err| {
            // File doesn't exist, which is fine for first run
            if (err == error.FileNotFound) return;
            return err;
        };
        defer file.close();
        
        const file_contents = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(file_contents);
        
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, file_contents, .{}) catch |err| {
            std.log.warn("Failed to parse token file: {}", .{err});
            return;
        };
        defer parsed.deinit();
        
        const root = parsed.value.object;
        
        const providers = [_]struct { name: []const u8, provider: AuthProvider }{
            .{ .name = "github", .provider = .github },
            .{ .name = "google", .provider = .google },
            .{ .name = "openai", .provider = .openai },
            .{ .name = "local", .provider = .local },
        };
        
        for (providers) |provider_info| {
            if (root.get(provider_info.name)) |token_value| {
                const token = try self.allocator.dupe(u8, token_value.string);
                try self.tokens.append(TokenEntry{
                    .provider = provider_info.provider,
                    .token = token,
                });
            }
        }
    }
};

pub const GitHubAuth = struct {
    allocator: std.mem.Allocator,
    client_id: []const u8,
    client_secret: []const u8,
    redirect_uri: []const u8,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, client_id: []const u8, client_secret: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .client_id = try allocator.dupe(u8, client_id),
            .client_secret = try allocator.dupe(u8, client_secret),
            .redirect_uri = try allocator.dupe(u8, "http://localhost:8080/callback"),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.client_id);
        self.allocator.free(self.client_secret);
        self.allocator.free(self.redirect_uri);
    }
    
    pub fn startOAuthFlow(self: *Self) ![]const u8 {
        // GitHub OAuth flow for Copilot access
        const scope = "copilot";
        const state = try self.generateState();
        defer self.allocator.free(state);
        
        const auth_url = try std.fmt.allocPrint(
            self.allocator,
            "https://github.com/login/oauth/authorize?client_id={s}&redirect_uri={s}&scope={s}&state={s}",
            .{ self.client_id, self.redirect_uri, scope, state }
        );
        
        return auth_url;
    }
    
    pub fn exchangeCodeForToken(self: *Self, code: []const u8) ![]const u8 {
        // In real implementation, this would make an HTTP request to GitHub's token endpoint
        const mock_token = try std.fmt.allocPrint(self.allocator, 
            "{{\"access_token\":\"ghp_mock_github_token_{s}\",\"token_type\":\"bearer\",\"scope\":\"copilot\"}}", 
            .{code[0..@min(8, code.len)]});
        return mock_token;
    }
    
    pub fn exchangeToken(self: *Self, github_token: []const u8) ![]const u8 {
        // Exchange GitHub token for Copilot token
        const copilot_token = try std.fmt.allocPrint(self.allocator, "ghu_copilot_token_{s}", .{github_token[0..@min(8, github_token.len)]});
        return copilot_token;
    }
    
    pub fn validateToken(self: *Self, token: []const u8) !bool {
        // In real implementation, this would validate against GitHub API
        _ = self;
        return token.len > 10; // Simple validation for now
    }
    
    fn generateState(self: *Self) ![]const u8 {
        // Generate a random state for CSRF protection
        var random_bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&random_bytes);
        
        const encoder = std.base64.url_safe.Encoder;
        const encoded_len = encoder.calcSize(random_bytes.len);
        const state = try self.allocator.alloc(u8, encoded_len);
        _ = encoder.encode(state, &random_bytes);
        return state;
    }
};

pub const GoogleAuth = struct {
    allocator: std.mem.Allocator,
    client_id: []const u8,
    client_secret: []const u8,
    redirect_uri: []const u8,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, client_id: []const u8, client_secret: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .client_id = try allocator.dupe(u8, client_id),
            .client_secret = try allocator.dupe(u8, client_secret),
            .redirect_uri = try allocator.dupe(u8, "http://localhost:8080/callback"),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.client_id);
        self.allocator.free(self.client_secret);
        self.allocator.free(self.redirect_uri);
    }
    
    pub fn startOAuthFlow(self: *Self) ![]const u8 {
        // OAuth flow for Google (Claude API)
        const scope = "https://www.googleapis.com/auth/cloud-platform";
        const state = try self.generateState();
        defer self.allocator.free(state);
        
        const auth_url = try std.fmt.allocPrint(
            self.allocator,
            "https://accounts.google.com/o/oauth2/v2/auth?client_id={s}&redirect_uri={s}&response_type=code&scope={s}&state={s}&access_type=offline",
            .{ self.client_id, self.redirect_uri, scope, state }
        );
        
        return auth_url;
    }
    
    pub fn exchangeCodeForToken(self: *Self, code: []const u8) ![]const u8 {
        // In real implementation, this would make an HTTP request to Google's token endpoint
        // For now, return a structured mock token
        const mock_token = try std.fmt.allocPrint(self.allocator, 
            "{{\"access_token\":\"ya29.mock_google_token_{s}\",\"token_type\":\"Bearer\",\"expires_in\":3599,\"refresh_token\":\"1//mock_refresh_token\"}}", 
            .{code[0..@min(8, code.len)]});
        return mock_token;
    }
    
    pub fn refreshToken(self: *Self, refresh_token: []const u8) ![]const u8 {
        // Implementation for token refresh
        _ = refresh_token;
        const refreshed_token = try std.fmt.allocPrint(self.allocator, 
            "{{\"access_token\":\"ya29.refreshed_token\",\"token_type\":\"Bearer\",\"expires_in\":3599}}");
        return refreshed_token;
    }
    
    fn generateState(self: *Self) ![]const u8 {
        // Generate a random state for CSRF protection
        var random_bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&random_bytes);
        
        const encoder = std.base64.url_safe.Encoder;
        const encoded_len = encoder.calcSize(random_bytes.len);
        const state = try self.allocator.alloc(u8, encoded_len);
        _ = encoder.encode(state, &random_bytes);
        return state;
    }
};

pub const AuthManager = struct {
    allocator: std.mem.Allocator,
    token_storage: TokenStorage,
    github_auth: ?GitHubAuth,
    google_auth: ?GoogleAuth,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .token_storage = TokenStorage.init(allocator),
            .github_auth = null,
            .google_auth = null,
        };
    }
    
    pub fn initOAuth(self: *Self, github_client_id: ?[]const u8, github_client_secret: ?[]const u8, google_client_id: ?[]const u8, google_client_secret: ?[]const u8) !void {
        if (github_client_id != null and github_client_secret != null) {
            self.github_auth = try GitHubAuth.init(self.allocator, github_client_id.?, github_client_secret.?);
        }
        
        if (google_client_id != null and google_client_secret != null) {
            self.google_auth = try GoogleAuth.init(self.allocator, google_client_id.?, google_client_secret.?);
        }
    }
    
    pub fn deinit(self: *Self) void {
        self.token_storage.deinit();
        if (self.github_auth) |*auth| {
            auth.deinit();
        }
        if (self.google_auth) |*auth| {
            auth.deinit();
        }
    }
    
    pub fn authenticateGitHub(self: *Self, token: []const u8) !void {
        if (self.github_auth) |*auth| {
            const copilot_token = try auth.exchangeToken(token);
            defer self.allocator.free(copilot_token);
            try self.token_storage.setToken(.github, copilot_token);
        } else {
            // Direct token storage if OAuth not configured
            try self.token_storage.setToken(.github, token);
        }
    }
    
    pub fn authenticateGoogle(self: *Self, auth_code: []const u8) !void {
        if (self.google_auth) |*auth| {
            const access_token = try auth.exchangeCodeForToken(auth_code);
            defer self.allocator.free(access_token);
            try self.token_storage.setToken(.google, access_token);
        } else {
            return error.OAuthNotConfigured;
        }
    }
    
    pub fn startGitHubOAuth(self: *Self) ![]const u8 {
        if (self.github_auth) |*auth| {
            return try auth.startOAuthFlow();
        } else {
            return error.OAuthNotConfigured;
        }
    }
    
    pub fn startGoogleOAuth(self: *Self) ![]const u8 {
        if (self.google_auth) |*auth| {
            return try auth.startOAuthFlow();
        } else {
            return error.OAuthNotConfigured;
        }
    }
    
    pub fn exchangeGitHubCode(self: *Self, code: []const u8) !void {
        if (self.github_auth) |*auth| {
            const token_response = try auth.exchangeCodeForToken(code);
            defer self.allocator.free(token_response);
            
            // Parse JSON response to extract access token
            const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, token_response, .{});
            defer parsed.deinit();
            
            if (parsed.value.object.get("access_token")) |token_value| {
                try self.token_storage.setToken(.github, token_value.string);
            }
        } else {
            return error.OAuthNotConfigured;
        }
    }
    
    pub fn exchangeGoogleCode(self: *Self, code: []const u8) !void {
        if (self.google_auth) |*auth| {
            const token_response = try auth.exchangeCodeForToken(code);
            defer self.allocator.free(token_response);
            
            // Parse JSON response to extract access token
            const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, token_response, .{});
            defer parsed.deinit();
            
            if (parsed.value.object.get("access_token")) |token_value| {
                try self.token_storage.setToken(.google, token_value.string);
            }
        } else {
            return error.OAuthNotConfigured;
        }
    }
    
    pub fn setOpenAIToken(self: *Self, token: []const u8) !void {
        try self.token_storage.setToken(.openai, token);
    }
    
    pub fn getToken(self: *Self, provider: AuthProvider) !?[]const u8 {
        return try self.token_storage.getToken(provider);
    }
    
    pub fn isAuthenticated(self: *Self, provider: AuthProvider) !bool {
        if (try self.getToken(provider)) |token| {
            defer self.allocator.free(token);
            
            return switch (provider) {
                .github => if (self.github_auth) |*auth| try auth.validateToken(token) else true,
                .google, .openai => true, // Simplified validation
                .local => true,
            };
        }
        return false;
    }
};