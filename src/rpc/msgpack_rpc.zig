const std = @import("std");
const msgpack = @import("msgpack");
const api = @import("../api/client.zig");
const streaming = @import("../streaming/mod.zig");
const concurrent = @import("../concurrent/mod.zig");
const error_handling = @import("../error_handling/mod.zig");
const providers = @import("../providers/mod.zig");
const auth = @import("../auth/mod.zig");
const config = @import("../config/mod.zig");
const context = @import("../context/mod.zig");

const Zeke = @import("../root.zig").Zeke;

/// MessagePack-RPC server for Neovim plugin communication
pub const MsgPackRPC = struct {
    allocator: std.mem.Allocator,
    stdin: std.fs.File.Reader,
    stdout: std.fs.File.Writer,
    zeke_instance: *Zeke,
    running: bool,
    request_id_counter: std.atomic.Value(u64),
    active_requests: std.HashMap(u64, *ActiveRequest, std.hash_map.StringContext, 80),
    
    const Self = @This();
    
    pub const RPCError = error{
        InvalidRequest,
        MethodNotFound,
        InvalidParams,
        InternalError,
        ParseError,
        InvalidResponse,
        RequestCancelled,
    };
    
    pub const Request = struct {
        jsonrpc: []const u8 = "2.0",
        method: []const u8,
        params: ?std.json.Value = null,
        id: ?std.json.Value = null,
        
        pub fn deinit(self: *Request, allocator: std.mem.Allocator) void {
            if (self.params) |params| {
                params.deinit(allocator);
            }
            if (self.id) |id| {
                id.deinit(allocator);
            }
        }
    };
    
    pub const Response = struct {
        jsonrpc: []const u8 = "2.0",
        result: ?std.json.Value = null,
        @"error": ?RPCErrorResponse = null,
        id: ?std.json.Value = null,
        
        pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
            if (self.result) |result| {
                result.deinit(allocator);
            }
            if (self.@"error") |error_response| {
                error_response.deinit(allocator);
            }
            if (self.id) |id| {
                id.deinit(allocator);
            }
        }
    };
    
    pub const RPCErrorResponse = struct {
        code: i32,
        message: []const u8,
        data: ?std.json.Value = null,
        
        pub fn deinit(self: *RPCErrorResponse, allocator: std.mem.Allocator) void {
            if (self.data) |data| {
                data.deinit(allocator);
            }
        }
    };
    
    pub const StreamChunk = struct {
        id: u64,
        chunk: []const u8,
        done: bool,
        timestamp: i64,
    };
    
    pub const ActiveRequest = struct {
        id: u64,
        method: []const u8,
        start_time: i64,
        cancelled: bool,
        
        pub fn deinit(self: *ActiveRequest, allocator: std.mem.Allocator) void {
            allocator.free(self.method);
        }
    };
    
    // Context structures for different operations
    pub const BufferContext = struct {
        filename: []const u8,
        language: []const u8,
        cursor_line: u32,
        cursor_col: u32,
        selection: ?struct {
            start_line: u32,
            start_col: u32,
            end_line: u32,
            end_col: u32,
        } = null,
        surrounding_lines: [][]const u8,
        
        pub fn deinit(self: *BufferContext, allocator: std.mem.Allocator) void {
            allocator.free(self.filename);
            allocator.free(self.language);
            for (self.surrounding_lines) |line| {
                allocator.free(line);
            }
            allocator.free(self.surrounding_lines);
        }
    };
    
    pub const ChatParams = struct {
        message: []const u8,
        context: ?BufferContext = null,
        stream: bool = true,
        
        pub fn deinit(self: *ChatParams, allocator: std.mem.Allocator) void {
            allocator.free(self.message);
            if (self.context) |*ctx| {
                ctx.deinit(allocator);
            }
        }
    };
    
    pub const EditParams = struct {
        instruction: []const u8,
        code: []const u8,
        context: ?BufferContext = null,
        
        pub fn deinit(self: *EditParams, allocator: std.mem.Allocator) void {
            allocator.free(self.instruction);
            allocator.free(self.code);
            if (self.context) |*ctx| {
                ctx.deinit(allocator);
            }
        }
    };
    
    pub const CreateFileParams = struct {
        description: []const u8,
        language: ?[]const u8 = null,
        project_path: ?[]const u8 = null,
        
        pub fn deinit(self: *CreateFileParams, allocator: std.mem.Allocator) void {
            allocator.free(self.description);
            if (self.language) |lang| {
                allocator.free(lang);
            }
            if (self.project_path) |path| {
                allocator.free(path);
            }
        }
    };
    
    pub const AnalyzeParams = struct {
        code: []const u8,
        analysis_type: []const u8,
        context: ?BufferContext = null,
        
        pub fn deinit(self: *AnalyzeParams, allocator: std.mem.Allocator) void {
            allocator.free(self.code);
            allocator.free(self.analysis_type);
            if (self.context) |*ctx| {
                ctx.deinit(allocator);
            }
        }
    };
    
    pub fn init(allocator: std.mem.Allocator, zeke_instance: *Zeke) !Self {
        const stdin = std.io.getStdIn().reader();
        const stdout = std.io.getStdOut().writer();
        
        return Self{
            .allocator = allocator,
            .stdin = stdin,
            .stdout = stdout,
            .zeke_instance = zeke_instance,
            .running = false,
            .request_id_counter = std.atomic.Value(u64).init(0),
            .active_requests = std.HashMap(u64, *ActiveRequest, std.hash_map.HashMap(u64, *ActiveRequest, std.hash_map.DefaultContext(u64), 80).Context, 80).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        // Cancel all active requests
        var iter = self.active_requests.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.cancelled = true;
            entry.value_ptr.*.deinit(self.allocator);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.active_requests.deinit();
    }
    
    pub fn start(self: *Self) !void {
        self.running = true;
        std.log.info("MessagePack-RPC server started", .{});
        
        while (self.running) {
            self.processMessage() catch |err| {
                std.log.err("Error processing message: {}", .{err});
                // Continue processing other messages
            };
        }
    }
    
    pub fn stop(self: *Self) void {
        self.running = false;
        std.log.info("MessagePack-RPC server stopped", .{});
    }
    
    fn processMessage(self: *Self) !void {
        // Read message length (4 bytes, big-endian)
        var length_bytes: [4]u8 = undefined;
        _ = try self.stdin.readAll(&length_bytes);
        const message_length = std.mem.readInt(u32, &length_bytes, .big);
        
        // Read message content
        const message_data = try self.allocator.alloc(u8, message_length);
        defer self.allocator.free(message_data);
        _ = try self.stdin.readAll(message_data);
        
        // Parse MessagePack data
        var stream = std.io.fixedBufferStream(message_data);
        var deserializer = msgpack.Deserializer.init(stream.reader());
        
        const request = deserializer.deserialize(Request) catch |err| {
            try self.sendError(null, -32700, "Parse error", null);
            return err;
        };
        defer request.deinit(self.allocator);
        
        // Handle the request
        try self.handleRequest(request);
    }
    
    fn handleRequest(self: *Self, request: Request) !void {
        const request_id = if (request.id) |id| self.extractRequestId(id) else null;
        
        // Route to appropriate handler
        if (std.mem.eql(u8, request.method, "chat")) {
            try self.handleChat(request, request_id);
        } else if (std.mem.eql(u8, request.method, "edit")) {
            try self.handleEdit(request, request_id);
        } else if (std.mem.eql(u8, request.method, "explain")) {
            try self.handleExplain(request, request_id);
        } else if (std.mem.eql(u8, request.method, "create_file")) {
            try self.handleCreateFile(request, request_id);
        } else if (std.mem.eql(u8, request.method, "analyze")) {
            try self.handleAnalyze(request, request_id);
        } else if (std.mem.eql(u8, request.method, "cancel")) {
            try self.handleCancel(request, request_id);
        } else if (std.mem.eql(u8, request.method, "status")) {
            try self.handleStatus(request, request_id);
        } else {
            try self.sendError(request_id, -32601, "Method not found", null);
        }
    }
    
    fn handleChat(self: *Self, request: Request, request_id: ?u64) !void {
        const params = try self.parseParams(ChatParams, request.params);
        defer params.deinit(self.allocator);
        
        if (request_id) |id| {
            const active_request = try self.allocator.create(ActiveRequest);
            active_request.* = ActiveRequest{
                .id = id,
                .method = try self.allocator.dupe(u8, "chat"),
                .start_time = std.time.timestamp(),
                .cancelled = false,
            };
            try self.active_requests.put(id, active_request);
        }
        
        if (params.stream) {
            // Streaming response
            const StreamHandler = struct {
                rpc: *Self,
                req_id: ?u64,
                
                fn callback(handler: @This(), chunk: streaming.StreamChunk) void {
                    handler.rpc.sendStreamChunk(handler.req_id, chunk.content, chunk.is_final) catch |err| {
                        std.log.err("Failed to send stream chunk: {}", .{err});
                    };
                }
            };
            
            const handler = StreamHandler{ .rpc = self, .req_id = request_id };
            
            self.zeke_instance.streamChat(params.message, handler.callback) catch |err| {
                try self.sendError(request_id, -32603, "Internal error", null);
                std.log.err("Stream chat failed: {}", .{err});
            };
        } else {
            // Regular response
            const response = self.zeke_instance.chat(params.message) catch |err| {
                try self.sendError(request_id, -32603, "Internal error", null);
                std.log.err("Chat failed: {}", .{err});
                return;
            };
            defer self.allocator.free(response);
            
            const result = std.json.Value{ .string = response };
            try self.sendResult(request_id, result);
        }
        
        // Remove from active requests
        if (request_id) |id| {
            if (self.active_requests.fetchRemove(id)) |entry| {
                entry.value.deinit(self.allocator);
                self.allocator.destroy(entry.value);
            }
        }
    }
    
    fn handleEdit(self: *Self, request: Request, request_id: ?u64) !void {
        const params = try self.parseParams(EditParams, request.params);
        defer params.deinit(self.allocator);
        
        // Create edit request for AI
        const edit_prompt = try std.fmt.allocPrint(self.allocator, 
            "Edit this code according to the instruction.\n\nInstruction: {s}\n\nCode:\n{s}", 
            .{ params.instruction, params.code });
        defer self.allocator.free(edit_prompt);
        
        const response = self.zeke_instance.chat(edit_prompt) catch |err| {
            try self.sendError(request_id, -32603, "Internal error", null);
            std.log.err("Edit failed: {}", .{err});
            return;
        };
        defer self.allocator.free(response);
        
        // Parse response into structured format
        const edit_result = std.json.Value{ .object = std.json.ObjectMap.init(self.allocator) };
        try edit_result.object.put("original", std.json.Value{ .string = params.code });
        try edit_result.object.put("edited", std.json.Value{ .string = response });
        
        try self.sendResult(request_id, edit_result);
    }
    
    fn handleExplain(self: *Self, request: Request, request_id: ?u64) !void {
        const params = try self.parseParams(struct {
            code: []const u8,
            context: ?BufferContext = null,
        }, request.params);
        defer {
            self.allocator.free(params.code);
            if (params.context) |*ctx| {
                ctx.deinit(self.allocator);
            }
        }
        
        const code_context = api.CodeContext{
            .file_path = if (params.context) |ctx| ctx.filename else null,
            .language = if (params.context) |ctx| ctx.language else null,
            .cursor_position = null,
            .surrounding_code = null,
        };
        
        var explanation = self.zeke_instance.explainCode(params.code, code_context) catch |err| {
            try self.sendError(request_id, -32603, "Internal error", null);
            std.log.err("Explain failed: {}", .{err});
            return;
        };
        defer explanation.deinit(self.allocator);
        
        const result = std.json.Value{ .string = explanation.explanation };
        try self.sendResult(request_id, result);
    }
    
    fn handleCreateFile(self: *Self, request: Request, request_id: ?u64) !void {
        const params = try self.parseParams(CreateFileParams, request.params);
        defer params.deinit(self.allocator);
        
        const create_prompt = try std.fmt.allocPrint(self.allocator, 
            "Create a file with the following description: {s}", 
            .{params.description});
        defer self.allocator.free(create_prompt);
        
        const response = self.zeke_instance.chat(create_prompt) catch |err| {
            try self.sendError(request_id, -32603, "Internal error", null);
            std.log.err("Create file failed: {}", .{err});
            return;
        };
        defer self.allocator.free(response);
        
        // Parse response to extract filename and content
        const file_result = std.json.Value{ .object = std.json.ObjectMap.init(self.allocator) };
        try file_result.object.put("content", std.json.Value{ .string = response });
        try file_result.object.put("language", std.json.Value{ .string = params.language orelse "text" });
        
        try self.sendResult(request_id, file_result);
    }
    
    fn handleAnalyze(self: *Self, request: Request, request_id: ?u64) !void {
        const params = try self.parseParams(AnalyzeParams, request.params);
        defer params.deinit(self.allocator);
        
        const analysis_type = if (std.mem.eql(u8, params.analysis_type, "security"))
            api.AnalysisType.security
        else if (std.mem.eql(u8, params.analysis_type, "performance"))
            api.AnalysisType.performance
        else
            api.AnalysisType.quality;
        
        const project_context = api.ProjectContext{
            .project_path = std.fs.cwd().realpathAlloc(self.allocator, ".") catch null,
            .git_info = null,
            .dependencies = null,
            .framework = null,
        };
        
        var analysis = self.zeke_instance.analyzeCode(params.code, analysis_type, project_context) catch |err| {
            try self.sendError(request_id, -32603, "Internal error", null);
            std.log.err("Analyze failed: {}", .{err});
            return;
        };
        defer analysis.deinit(self.allocator);
        
        const result = std.json.Value{ .object = std.json.ObjectMap.init(self.allocator) };
        try result.object.put("analysis", std.json.Value{ .string = analysis.analysis });
        
        var suggestions = std.json.Array.init(self.allocator);
        for (analysis.suggestions) |suggestion| {
            try suggestions.append(std.json.Value{ .string = suggestion });
        }
        try result.object.put("suggestions", std.json.Value{ .array = suggestions });
        
        try self.sendResult(request_id, result);
    }
    
    fn handleCancel(self: *Self, request: Request, request_id: ?u64) !void {
        const params = try self.parseParams(struct {
            cancel_id: u64,
        }, request.params);
        
        if (self.active_requests.getPtr(params.cancel_id)) |active_request| {
            active_request.cancelled = true;
            try self.sendResult(request_id, std.json.Value{ .bool = true });
        } else {
            try self.sendResult(request_id, std.json.Value{ .bool = false });
        }
    }
    
    fn handleStatus(self: *Self, request: Request, request_id: ?u64) !void {
        _ = request;
        
        const status = std.json.Value{ .object = std.json.ObjectMap.init(self.allocator) };
        try status.object.put("version", std.json.Value{ .string = "0.2.1" });
        try status.object.put("active_requests", std.json.Value{ .integer = @intCast(self.active_requests.count()) });
        try status.object.put("current_provider", std.json.Value{ .string = @tagName(self.zeke_instance.current_provider) });
        try status.object.put("current_model", std.json.Value{ .string = self.zeke_instance.current_model });
        
        try self.sendResult(request_id, status);
    }
    
    fn parseParams(self: *Self, comptime T: type, params: ?std.json.Value) !T {
        if (params) |p| {
            return try std.json.parseFromValue(T, self.allocator, p, .{});
        }
        return error.InvalidParams;
    }
    
    fn extractRequestId(self: *Self, id_value: std.json.Value) ?u64 {
        _ = self;
        return switch (id_value) {
            .integer => |int| @intCast(int),
            .string => |str| std.fmt.parseInt(u64, str, 10) catch null,
            else => null,
        };
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
        
        const error_response = RPCErrorResponse{
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
    
    fn sendStreamChunk(self: *Self, request_id: ?u64, content: []const u8, is_final: bool) !void {
        const chunk = StreamChunk{
            .id = request_id orelse 0,
            .chunk = content,
            .done = is_final,
            .timestamp = std.time.timestamp(),
        };
        
        // Serialize chunk
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();
        
        var serializer = msgpack.Serializer.init(buffer.writer());
        try serializer.serialize(chunk);
        
        // Send length + data
        const length_bytes = std.mem.toBytes(@as(u32, @intCast(buffer.items.len)));
        try self.stdout.writeAll(&length_bytes);
        try self.stdout.writeAll(buffer.items);
    }
    
    fn sendResponse(self: *Self, response: Response) !void {
        // Serialize response
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();
        
        var serializer = msgpack.Serializer.init(buffer.writer());
        try serializer.serialize(response);
        
        // Send length + data
        const length_bytes = std.mem.toBytes(@as(u32, @intCast(buffer.items.len)));
        try self.stdout.writeAll(&length_bytes);
        try self.stdout.writeAll(buffer.items);
    }
};