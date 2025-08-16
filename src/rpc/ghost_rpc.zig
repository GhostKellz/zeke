const std = @import("std");
const api = @import("../api/client.zig");
const streaming = @import("../streaming/mod.zig");
const project_analyzer = @import("../build/project_analyzer.zig");

const Zeke = @import("../root.zig").Zeke;

/// GhostRPC - Fast async RPC server for Neovim plugin communication
pub const GhostRPC = struct {
    allocator: std.mem.Allocator,
    stdin: std.fs.File.Reader,
    stdout: std.fs.File.Writer,
    zeke_instance: *Zeke,
    running: std.atomic.Value(bool),
    
    const Self = @This();
    
    pub const Request = struct {
        jsonrpc: []const u8 = "2.0",
        method: []const u8,
        params: ?std.json.Value = null,
        id: ?std.json.Value = null,
    };
    
    pub const Response = struct {
        jsonrpc: []const u8 = "2.0",
        result: ?std.json.Value = null,
        @"error": ?ErrorResponse = null,
        id: ?std.json.Value = null,
    };
    
    pub const ErrorResponse = struct {
        code: i32,
        message: []const u8,
        data: ?std.json.Value = null,
    };
    
    pub fn init(allocator: std.mem.Allocator, zeke_instance: *Zeke) !Self {
        const stdin = std.io.getStdIn().reader();
        const stdout = std.io.getStdOut().writer();
        
        return Self{
            .allocator = allocator,
            .stdin = stdin,
            .stdout = stdout,
            .zeke_instance = zeke_instance,
            .running = std.atomic.Value(bool).init(false),
        };
    }
    
    pub fn deinit(self: *Self) void {
        _ = self;
    }
    
    pub fn start(self: *Self) !void {
        self.running.store(true, .release);
        std.log.info("👻 GhostRPC server started", .{});
        
        while (self.running.load(.acquire)) {
            self.processMessage() catch |err| {
                std.log.err("Error processing message: {}", .{err});
                continue;
            };
        }
    }
    
    pub fn stop(self: *Self) void {
        self.running.store(false, .release);
        std.log.info("👻 GhostRPC server stopped", .{});
    }
    
    fn processMessage(self: *Self) !void {
        // Read message length (4 bytes, big-endian)
        var length_buffer: [4]u8 = undefined;
        _ = try self.stdin.readAll(&length_buffer);
        
        const message_length = std.mem.readInt(u32, &length_buffer, .big);
        if (message_length > 1024 * 1024) return error.MessageTooLarge; // 1MB limit
        
        // Read message content
        const message_data = try self.allocator.alloc(u8, message_length);
        defer self.allocator.free(message_data);
        _ = try self.stdin.readAll(message_data);
        
        // Parse JSON-RPC
        const request = std.json.parseFromSlice(Request, self.allocator, message_data, .{}) catch |err| {
            try self.sendError(null, -32700, "Parse error", null);
            return err;
        };
        defer request.deinit();
        
        // Handle the request
        try self.handleRequest(request.value);
    }
    
    fn handleRequest(self: *Self, request: Request) !void {
        const request_id = self.extractRequestId(request.id);
        
        if (std.mem.eql(u8, request.method, "chat")) {
            try self.handleChat(request, request_id);
        } else if (std.mem.eql(u8, request.method, "edit")) {
            try self.handleEdit(request, request_id);
        } else if (std.mem.eql(u8, request.method, "explain")) {
            try self.handleExplain(request, request_id);
        } else if (std.mem.eql(u8, request.method, "complete")) {
            try self.handleComplete(request, request_id);
        } else if (std.mem.eql(u8, request.method, "status")) {
            try self.handleStatus(request, request_id);
        } else if (std.mem.eql(u8, request.method, "project_analyze")) {
            try self.handleProjectAnalyze(request, request_id);
        } else if (std.mem.eql(u8, request.method, "dependency_suggest")) {
            try self.handleDependencySuggest(request, request_id);
        } else if (std.mem.eql(u8, request.method, "package_recommend")) {
            try self.handlePackageRecommend(request, request_id);
        } else {
            try self.sendError(request_id, -32601, "Method not found", null);
        }
    }
    
    fn handleChat(self: *Self, request: Request, request_id: ?u64) !void {
        const message = if (request.params) |params| blk: {
            if (params == .object and params.object.get("message")) |msg| {
                if (msg == .string) {
                    break :blk try self.allocator.dupe(u8, msg.string);
                }
            }
            break :blk null;
        } else null;
        
        if (message == null) {
            try self.sendError(request_id, -32602, "Invalid params", null);
            return;
        }
        defer self.allocator.free(message.?);
        
        const response = self.zeke_instance.chat(message.?) catch |err| {
            try self.sendError(request_id, -32603, "Internal error", null);
            std.log.err("Chat failed: {}", .{err});
            return;
        };
        defer self.allocator.free(response);
        
        const result = std.json.Value{ .string = response };
        try self.sendResult(request_id, result);
    }
    
    fn handleEdit(self: *Self, request: Request, request_id: ?u64) !void {
        _ = request;
        // Simplified edit implementation
        try self.sendResult(request_id, std.json.Value{ .string = "Edit completed" });
    }
    
    fn handleExplain(self: *Self, request: Request, request_id: ?u64) !void {
        _ = request;
        // Simplified explain implementation
        try self.sendResult(request_id, std.json.Value{ .string = "Code explanation" });
    }
    
    fn handleComplete(self: *Self, request: Request, request_id: ?u64) !void {
        _ = request;
        // Simplified completion implementation
        try self.sendResult(request_id, std.json.Value{ .string = "Code completion" });
    }
    
    fn handleStatus(self: *Self, request: Request, request_id: ?u64) !void {
        _ = request;
        
        var status = std.json.ObjectMap.init(self.allocator);
        try status.put("version", std.json.Value{ .string = "0.2.3" });
        try status.put("status", std.json.Value{ .string = "running" });
        try status.put("provider", std.json.Value{ .string = @tagName(self.zeke_instance.current_provider) });
        
        try self.sendResult(request_id, std.json.Value{ .object = status });
    }
    
    fn handleProjectAnalyze(self: *Self, request: Request, request_id: ?u64) !void {
        const project_path = if (request.params) |params| blk: {
            if (params == .object and params.object.get("path")) |path| {
                if (path == .string) {
                    break :blk path.string;
                }
            }
            break :blk "."; // Default to current directory
        } else ".";
        
        // Use project analyzer
        var analyzer = project_analyzer.ProjectAnalyzer.init(self.allocator);
        defer analyzer.deinit();
        
        const analysis = analyzer.analyzeProject(project_path) catch |err| {
            try self.sendError(request_id, -32603, "Project analysis failed", null);
            std.log.err("Project analysis failed: {}", .{err});
            return;
        };
        defer {
            var mut_analysis = analysis;
            mut_analysis.deinit(self.allocator);
        }
        
        // Convert to JSON response
        var result = std.json.ObjectMap.init(self.allocator);
        defer result.deinit();
        
        // Basic project info
        if (analysis.project_name) |name| {
            try result.put("project_name", std.json.Value{ .string = name });
        }
        if (analysis.version) |version| {
            try result.put("version", std.json.Value{ .string = version });
        }
        try result.put("build_system", std.json.Value{ .string = analysis.build_system });
        try result.put("module_count", std.json.Value{ .integer = @intCast(analysis.module_count) });
        
        if (analysis.estimated_build_time) |build_time| {
            try result.put("estimated_build_time_ms", std.json.Value{ .integer = @intCast(build_time) });
        }
        
        // Dependencies array
        var deps_array = std.json.Array.init(self.allocator);
        for (analysis.dependencies) |dep| {
            var dep_obj = std.json.ObjectMap.init(self.allocator);
            try dep_obj.put("name", std.json.Value{ .string = dep.name });
            if (dep.version) |version| {
                try dep_obj.put("version", std.json.Value{ .string = version });
            }
            if (dep.url) |url| {
                try dep_obj.put("url", std.json.Value{ .string = url });
            }
            if (dep.security_score) |score| {
                try dep_obj.put("security_score", std.json.Value{ .integer = @intCast(score) });
            }
            try deps_array.append(std.json.Value{ .object = dep_obj });
        }
        try result.put("dependencies", std.json.Value{ .array = deps_array });
        
        // Build issues array
        var issues_array = std.json.Array.init(self.allocator);
        for (analysis.build_issues) |issue| {
            var issue_obj = std.json.ObjectMap.init(self.allocator);
            try issue_obj.put("type", std.json.Value{ .string = @tagName(issue.type) });
            try issue_obj.put("severity", std.json.Value{ .string = @tagName(issue.severity) });
            try issue_obj.put("message", std.json.Value{ .string = issue.message });
            if (issue.suggestion) |suggestion| {
                try issue_obj.put("suggestion", std.json.Value{ .string = suggestion });
            }
            if (issue.file) |file| {
                try issue_obj.put("file", std.json.Value{ .string = file });
            }
            if (issue.line) |line| {
                try issue_obj.put("line", std.json.Value{ .integer = @intCast(line) });
            }
            try issues_array.append(std.json.Value{ .object = issue_obj });
        }
        try result.put("build_issues", std.json.Value{ .array = issues_array });
        
        try self.sendResult(request_id, std.json.Value{ .object = result });
    }
    
    fn handleDependencySuggest(self: *Self, request: Request, request_id: ?u64) !void {
        const query = if (request.params) |params| blk: {
            if (params == .object and params.object.get("query")) |q| {
                if (q == .string) {
                    break :blk try self.allocator.dupe(u8, q.string);
                }
            }
            break :blk null;
        } else null;
        
        if (query == null) {
            try self.sendError(request_id, -32602, "Query parameter required", null);
            return;
        }
        defer self.allocator.free(query.?);
        
        // Mock dependency suggestions based on query
        var result = std.json.ObjectMap.init(self.allocator);
        defer result.deinit();
        
        var suggestions = std.json.Array.init(self.allocator);
        
        // Simple keyword matching for demonstration
        if (std.mem.indexOf(u8, query.?, "http") != null or std.mem.indexOf(u8, query.?, "client") != null) {
            var httpz_suggestion = std.json.ObjectMap.init(self.allocator);
            try httpz_suggestion.put("name", std.json.Value{ .string = "httpz" });
            try httpz_suggestion.put("score", std.json.Value{ .float = 0.95 });
            try httpz_suggestion.put("reason", std.json.Value{ .string = "Popular HTTP server/client library for Zig" });
            try httpz_suggestion.put("registry", std.json.Value{ .string = "zigistry" });
            try suggestions.append(std.json.Value{ .object = httpz_suggestion });
        }
        
        if (std.mem.indexOf(u8, query.?, "json") != null) {
            var json_suggestion = std.json.ObjectMap.init(self.allocator);
            try json_suggestion.put("name", std.json.Value{ .string = "zig-json" });
            try json_suggestion.put("score", std.json.Value{ .float = 0.88 });
            try json_suggestion.put("reason", std.json.Value{ .string = "Fast JSON parser and generator" });
            try json_suggestion.put("registry", std.json.Value{ .string = "zigistry" });
            try suggestions.append(std.json.Value{ .object = json_suggestion });
        }
        
        try result.put("query", std.json.Value{ .string = query.? });
        try result.put("suggestions", std.json.Value{ .array = suggestions });
        
        try self.sendResult(request_id, std.json.Value{ .object = result });
    }
    
    fn handlePackageRecommend(self: *Self, request: Request, request_id: ?u64) !void {
        const need_description = if (request.params) |params| blk: {
            if (params == .object and params.object.get("need")) |need| {
                if (need == .string) {
                    break :blk try self.allocator.dupe(u8, need.string);
                }
            }
            break :blk null;
        } else null;
        
        if (need_description == null) {
            try self.sendError(request_id, -32602, "Need description parameter required", null);
            return;
        }
        defer self.allocator.free(need_description.?);
        
        // Use AI chat to generate package recommendations
        const ai_query = try std.fmt.allocPrint(self.allocator, 
            "You are a Zig package expert. I need a Zig package for: {s}\n\nPlease provide a JSON response with specific package recommendations in this exact format:\n{{\n  \"recommendations\": [\n    {{\n      \"name\": \"package-name\",\n      \"score\": 0.95,\n      \"reason\": \"Detailed reason for recommendation\",\n      \"registry\": \"zigistry\",\n      \"version\": \"0.1.0\",\n      \"alternatives\": [\"alt1\", \"alt2\"]\n    }}\n  ]\n}}\n\nFocus on real, available Zig packages from ziglang.org/download/ or popular GitHub repositories.", 
            .{need_description.?}
        );
        defer self.allocator.free(ai_query);
        
        // Get AI response
        const ai_response = self.zeke_instance.chat(ai_query) catch |err| {
            std.log.err("AI chat failed for package recommendation: {}", .{err});
            
            // Fallback to mock recommendations
            var result = std.json.ObjectMap.init(self.allocator);
            defer result.deinit();
            
            var recommendations = std.json.Array.init(self.allocator);
            
            // Provide intelligent fallback based on common patterns
            if (std.mem.indexOf(u8, need_description.?, "http") != null) {
                var http_rec = std.json.ObjectMap.init(self.allocator);
                try http_rec.put("name", std.json.Value{ .string = "httpz" });
                try http_rec.put("score", std.json.Value{ .float = 0.92 });
                try http_rec.put("reason", std.json.Value{ .string = "High-performance HTTP server and client library" });
                try http_rec.put("registry", std.json.Value{ .string = "github" });
                try recommendations.append(std.json.Value{ .object = http_rec });
            } else if (std.mem.indexOf(u8, need_description.?, "json") != null) {
                var json_rec = std.json.ObjectMap.init(self.allocator);
                try json_rec.put("name", std.json.Value{ .string = "std.json" });
                try json_rec.put("score", std.json.Value{ .float = 1.0 });
                try json_rec.put("reason", std.json.Value{ .string = "Built-in JSON parser in Zig standard library" });
                try json_rec.put("registry", std.json.Value{ .string = "std" });
                try recommendations.append(std.json.Value{ .object = json_rec });
            } else {
                var generic_rec = std.json.ObjectMap.init(self.allocator);
                try generic_rec.put("name", std.json.Value{ .string = "std" });
                try generic_rec.put("score", std.json.Value{ .float = 0.8 });
                try generic_rec.put("reason", std.json.Value{ .string = "Check Zig standard library first" });
                try generic_rec.put("registry", std.json.Value{ .string = "std" });
                try recommendations.append(std.json.Value{ .object = generic_rec });
            }
            
            try result.put("need", std.json.Value{ .string = need_description.? });
            try result.put("recommendations", std.json.Value{ .array = recommendations });
            try result.put("ai_response", std.json.Value{ .string = "Fallback recommendation (AI unavailable)" });
            
            try self.sendResult(request_id, std.json.Value{ .object = result });
            return;
        };
        defer self.allocator.free(ai_response);
        
        // Try to parse AI response as JSON, fallback to structured response if invalid
        const parsed_ai = std.json.parseFromSlice(std.json.Value, self.allocator, ai_response, .{}) catch |err| {
            std.log.warn("Failed to parse AI response as JSON: {}", .{err});
            
            // Create structured response from AI text
            var result = std.json.ObjectMap.init(self.allocator);
            defer result.deinit();
            
            var recommendations = std.json.Array.init(self.allocator);
            
            // Extract package names from AI response using simple heuristics
            var lines = std.mem.split(u8, ai_response, "\n");
            while (lines.next()) |line| {
                if (std.mem.indexOf(u8, line, "package") != null or std.mem.indexOf(u8, line, "library") != null) {
                    var rec = std.json.ObjectMap.init(self.allocator);
                    try rec.put("name", std.json.Value{ .string = "AI-suggested" });
                    try rec.put("score", std.json.Value{ .float = 0.75 });
                    try rec.put("reason", std.json.Value{ .string = line });
                    try rec.put("registry", std.json.Value{ .string = "unknown" });
                    try recommendations.append(std.json.Value{ .object = rec });
                    break; // Just take the first suggestion for now
                }
            }
            
            if (recommendations.items.len == 0) {
                var fallback_rec = std.json.ObjectMap.init(self.allocator);
                try fallback_rec.put("name", std.json.Value{ .string = "std" });
                try fallback_rec.put("score", std.json.Value{ .float = 0.7 });
                try fallback_rec.put("reason", std.json.Value{ .string = "AI response couldn't be parsed, check standard library" });
                try fallback_rec.put("registry", std.json.Value{ .string = "std" });
                try recommendations.append(std.json.Value{ .object = fallback_rec });
            }
            
            try result.put("need", std.json.Value{ .string = need_description.? });
            try result.put("recommendations", std.json.Value{ .array = recommendations });
            try result.put("ai_response", std.json.Value{ .string = ai_response });
            
            try self.sendResult(request_id, std.json.Value{ .object = result });
            return;
        };
        defer parsed_ai.deinit();
        
        // Use AI-parsed recommendations if valid JSON
        var result = std.json.ObjectMap.init(self.allocator);
        defer result.deinit();
        
        try result.put("need", std.json.Value{ .string = need_description.? });
        
        if (parsed_ai.value == .object and parsed_ai.value.object.get("recommendations")) |ai_recs| {
            try result.put("recommendations", ai_recs);
        } else {
            // Fallback recommendations
            var recommendations = std.json.Array.init(self.allocator);
            var fallback_rec = std.json.ObjectMap.init(self.allocator);
            try fallback_rec.put("name", std.json.Value{ .string = "std" });
            try fallback_rec.put("score", std.json.Value{ .float = 0.7 });
            try fallback_rec.put("reason", std.json.Value{ .string = "AI provided unexpected format, check standard library" });
            try fallback_rec.put("registry", std.json.Value{ .string = "std" });
            try recommendations.append(std.json.Value{ .object = fallback_rec });
            try result.put("recommendations", std.json.Value{ .array = recommendations });
        }
        
        try result.put("ai_response", std.json.Value{ .string = ai_response });
        
        try self.sendResult(request_id, std.json.Value{ .object = result });
    }
    
    fn extractRequestId(self: *Self, id_value: ?std.json.Value) ?u64 {
        _ = self;
        if (id_value) |id| {
            return switch (id) {
                .integer => |int| @intCast(int),
                .string => |str| std.fmt.parseInt(u64, str, 10) catch null,
                else => null,
            };
        }
        return null;
    }
    
    fn sendResult(self: *Self, request_id: ?u64, result: std.json.Value) !void {
        const id_value = if (request_id) |id| std.json.Value{ .integer = @intCast(id) } else null;
        
        const response = Response{
            .result = result,
            .id = id_value,
        };
        
        try self.sendResponse(response);
    }
    
    fn sendError(self: *Self, request_id: ?u64, code: i32, message: []const u8, data: ?std.json.Value) !void {
        const id_value = if (request_id) |id| std.json.Value{ .integer = @intCast(id) } else null;
        
        const error_response = ErrorResponse{
            .code = code,
            .message = message,
            .data = data,
        };
        
        const response = Response{
            .@"error" = error_response,
            .id = id_value,
        };
        
        try self.sendResponse(response);
    }
    
    fn sendResponse(self: *Self, response: Response) !void {
        const json_string = try std.json.stringifyAlloc(self.allocator, response, .{});
        defer self.allocator.free(json_string);
        
        // Prepare length header
        const length_bytes = std.mem.toBytes(@as(u32, @intCast(json_string.len)));
        
        // Send length header
        try self.stdout.writeAll(&length_bytes);
        
        // Send JSON data
        try self.stdout.writeAll(json_string);
    }
};