//! ZEKE - The Zig-Native AI Dev Companion
const std = @import("std");
const zsync = @import("zsync");
const ghostnet = @import("ghostnet");

// Re-export all modules
pub const api = @import("api/client.zig");
pub const auth = @import("auth/mod.zig");
pub const config = @import("config/mod.zig");

pub const ZekeError = error{
    InitializationFailed,
    AuthenticationFailed,
    ConfigLoadFailed,
    NetworkError,
    InvalidModel,
    TokenExchangeFailed,
    UnexpectedResponse,
};

pub const Zeke = struct {
    allocator: std.mem.Allocator,
    config: config.Config,
    auth_manager: auth.AuthManager,
    api_client: api.ApiClient,
    current_model: []const u8,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) !Self {
        const zeke_config = config.loadConfig(allocator) catch |err| {
            std.log.err("Failed to load config: {}", .{err});
            return ZekeError.ConfigLoadFailed;
        };
        
        const auth_manager = auth.AuthManager.init(allocator) catch |err| {
            std.log.err("Failed to initialize auth manager: {}", .{err});
            return ZekeError.InitializationFailed;
        };
        
        // Initialize with default provider (OpenAI)
        const api_client = api.ApiClient.init(allocator, .openai) catch |err| {
            std.log.err("Failed to initialize API client: {}", .{err});
            return ZekeError.InitializationFailed;
        };
        
        return Self{
            .allocator = allocator,
            .config = zeke_config,
            .auth_manager = auth_manager,
            .api_client = api_client,
            .current_model = zeke_config.default_model,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.config.deinit();
        self.auth_manager.deinit();
        self.api_client.deinit();
    }
    
    pub fn setModel(self: *Self, model_name: []const u8) !void {
        const model_config = self.config.getModel(model_name) orelse return ZekeError.InvalidModel;
        
        // Switch API client based on provider
        self.api_client.deinit();
        
        const provider = if (std.mem.eql(u8, model_config.provider, "openai")) 
            api.ApiProvider.openai
        else if (std.mem.eql(u8, model_config.provider, "claude")) 
            api.ApiProvider.claude
        else if (std.mem.eql(u8, model_config.provider, "copilot")) 
            api.ApiProvider.copilot
        else if (std.mem.eql(u8, model_config.provider, "ghostllm")) 
            api.ApiProvider.ghostllm
        else 
            api.ApiProvider.ollama;
        
        self.api_client = api.ApiClient.init(self.allocator, provider) catch |err| {
            std.log.err("Failed to switch API client: {}", .{err});
            return ZekeError.InitializationFailed;
        };
        
        // Set auth token for new provider
        const auth_provider = switch (provider) {
            .openai => auth.AuthProvider.openai,
            .claude => auth.AuthProvider.google,
            .copilot => auth.AuthProvider.github,
            .ollama => auth.AuthProvider.local,
            .ghostllm => auth.AuthProvider.local, // GhostLLM can use local auth or API key
        };
        
        if (try self.auth_manager.getToken(auth_provider)) |token| {
            defer self.allocator.free(token);
            try self.api_client.setAuth(token);
        }
        
        self.current_model = model_name;
    }
    
    pub fn chat(self: *Self, message: []const u8) ![]const u8 {
        const messages = [_]api.ChatMessage{
            .{ .role = "user", .content = message },
        };
        
        const response = try self.api_client.chatCompletion(&messages, self.current_model);
        // Note: caller must free response.content
        return response.content;
    }
    
    pub fn completeCode(self: *Self, prompt: []const u8, context: api.CodeContext) ![]const u8 {
        const response = try self.api_client.codeCompletion(prompt, context);
        return response.text;
    }
    
    pub fn streamChat(self: *Self, message: []const u8, callback: *const fn ([]const u8) void) !void {
        const messages = [_]api.ChatMessage{
            .{ .role = "user", .content = message },
        };
        
        try self.api_client.streamChat(&messages, self.current_model, callback);
    }
    
    pub fn authenticateGitHub(self: *Self, token: []const u8) !void {
        try self.auth_manager.authenticateGitHub(token);
    }
    
    pub fn authenticateGoogle(self: *Self, auth_code: []const u8) !void {
        try self.auth_manager.authenticateGoogle(auth_code);
    }
    
    pub fn setOpenAIKey(self: *Self, key: []const u8) !void {
        try self.auth_manager.setOpenAIToken(key);
    }
    
    // GhostLLM-specific methods for enhanced AI capabilities
    pub fn analyzeCode(self: *Self, file_contents: []const u8, analysis_type: api.AnalysisType, context: api.ProjectContext) !api.AnalysisResponse {
        return try self.api_client.analyzeCode(file_contents, analysis_type, context);
    }
    
    pub fn explainCode(self: *Self, code: []const u8, context: api.CodeContext) !api.ExplanationResponse {
        return try self.api_client.explainCode(code, context);
    }
    
    pub fn refactorCode(self: *Self, code: []const u8, refactor_type: api.RefactorType, context: api.CodeContext) !api.RefactorResponse {
        return try self.api_client.refactorCode(code, refactor_type, context);
    }
    
    pub fn generateTests(self: *Self, code: []const u8, context: api.CodeContext) !api.TestResponse {
        return try self.api_client.generateTests(code, context);
    }
    
    pub fn setGhostLLMEndpoint(self: *Self, endpoint: []const u8) !void {
        // Update base URL for GhostLLM provider
        if (self.api_client.provider == .ghostllm) {
            // This would need to be implemented in the API client
            std.log.info("GhostLLM endpoint set to: {s}", .{endpoint});
        }
    }
};

pub fn bufferedPrint() !void {
    const stdout_file = std.fs.File.stdout().deprecatedWriter();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("⚡ ZEKE - The Zig-Native AI Dev Companion\n", .{});
    try stdout.print("Ready to assist with your coding workflow!\n", .{});

    try bw.flush();
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}

test "zeke initialization" {
    var zeke = try Zeke.init(std.testing.allocator);
    defer zeke.deinit();
    
    try std.testing.expect(std.mem.eql(u8, zeke.current_model, "gpt-4"));
}
