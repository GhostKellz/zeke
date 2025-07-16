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
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .tokens = std.ArrayList(TokenEntry).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        for (self.tokens.items) |entry| {
            self.allocator.free(entry.token);
        }
        self.tokens.deinit();
    }
    
    pub fn setToken(self: *Self, provider: AuthProvider, token: []const u8) !void {
        // Remove existing token for this provider
        self.removeToken(provider);
        
        const encoded_token = try self.encodeToken(token);
        try self.tokens.append(TokenEntry{
            .provider = provider,
            .token = encoded_token,
        });
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
};

pub const GitHubAuth = struct {
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        _ = self;
    }
    
    pub fn exchangeToken(self: *Self, github_token: []const u8) ![]const u8 {
        // For now, return a mock token - will implement proper HTTP later
        const mock_token = try std.fmt.allocPrint(self.allocator, "mock_copilot_token_{s}", .{github_token[0..@min(8, github_token.len)]});
        return mock_token;
    }
    
    pub fn validateToken(self: *Self, token: []const u8) !bool {
        // For now, return true for mock validation
        _ = self;
        _ = token;
        return true;
    }
};

pub const GoogleAuth = struct {
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        _ = self;
    }
    
    pub fn startOAuthFlow(self: *Self) ![]const u8 {
        // OAuth flow for Google (Claude API)
        const client_id = "your-client-id"; // Should be in config
        const redirect_uri = "http://localhost:8080/callback";
        const scope = "https://www.googleapis.com/auth/cloud-platform";
        
        const auth_url = try std.fmt.allocPrint(
            self.allocator,
            "https://accounts.google.com/o/oauth2/v2/auth?client_id={s}&redirect_uri={s}&response_type=code&scope={s}",
            .{ client_id, redirect_uri, scope }
        );
        
        return auth_url;
    }
    
    pub fn exchangeCodeForToken(self: *Self, code: []const u8) ![]const u8 {
        // For now, return a mock token
        const mock_token = try std.fmt.allocPrint(self.allocator, "mock_google_token_{s}", .{code[0..@min(8, code.len)]});
        return mock_token;
    }
};

pub const AuthManager = struct {
    allocator: std.mem.Allocator,
    token_storage: TokenStorage,
    github_auth: GitHubAuth,
    google_auth: GoogleAuth,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .token_storage = TokenStorage.init(allocator),
            .github_auth = try GitHubAuth.init(allocator),
            .google_auth = try GoogleAuth.init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.token_storage.deinit();
        self.github_auth.deinit();
        self.google_auth.deinit();
    }
    
    pub fn authenticateGitHub(self: *Self, token: []const u8) !void {
        const copilot_token = try self.github_auth.exchangeToken(token);
        defer self.allocator.free(copilot_token);
        
        try self.token_storage.setToken(.github, copilot_token);
    }
    
    pub fn authenticateGoogle(self: *Self, auth_code: []const u8) !void {
        const access_token = try self.google_auth.exchangeCodeForToken(auth_code);
        defer self.allocator.free(access_token);
        
        try self.token_storage.setToken(.google, access_token);
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
                .github => try self.github_auth.validateToken(token),
                .google, .openai => true, // Simplified validation
                .local => true,
            };
        }
        return false;
    }
};