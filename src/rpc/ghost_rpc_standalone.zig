/// GhostRPC - Fast RPC server for Neovim plugin communication (standalone version)
const builtin_std = @import("std");
const std = builtin_std;
const api = @import("../api/client.zig");

pub const GhostRPC = struct {
    allocator: std.mem.Allocator,
    stdin: std.fs.File.Reader,
    stdout: std.fs.File.Writer,
    zeke_instance: *anyopaque,
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
    
    pub fn init(allocator: std.mem.Allocator, zeke_instance: anytype) !Self {
        // TODO: Fix stdin/stdout initialization after resolving std.io namespace collision
        return Self{
            .allocator = allocator,
            .stdin = undefined, // TODO: Fix std.io namespace collision
            .stdout = undefined, // TODO: Fix std.io namespace collision  
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
        // TODO: Fix after resolving stdin initialization
        // Dummy initialization to avoid compilation error
        length_buffer = [_]u8{0} ** 4;
        
        const message_length = std.mem.readInt(u32, &length_buffer, .big);
        if (message_length > 1024 * 1024) return error.MessageTooLarge; // 1MB limit
        
        // Read message content
        const message_data = try self.allocator.alloc(u8, message_length);
        defer self.allocator.free(message_data);
        // TODO: Fix after resolving stdin initialization
        // Use dummy message for now to avoid compilation error
        const dummy_message = "{}";
        
        // Parse JSON-RPC
        const request = std.json.parseFromSlice(Request, self.allocator, dummy_message, .{}) catch |err| {
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
        } else {
            try self.sendError(request_id, -32601, "Method not found", null);
        }
    }
    
    fn handleChat(self: *Self, request: Request, request_id: ?u64) !void {
        const message = if (request.params) |params| blk: {
            if (params == .object) {
                if (params.object.get("message")) |msg| {
                    if (msg == .string) {
                        break :blk try self.allocator.dupe(u8, msg.string);
                    }
                }
            }
            break :blk null;
        } else null;
        
        if (message == null) {
            try self.sendError(request_id, -32602, "Invalid params", null);
            return;
        }
        defer self.allocator.free(message.?);
        
        // TODO: Fix zeke_instance pointer casting and method calls
        _ = self.zeke_instance;
        const response = "Test response from GhostRPC";
        
        const result = std.json.Value{ .string = response };
        try self.sendResult(request_id, result);
    }
    
    fn handleEdit(self: *Self, request: Request, request_id: ?u64) !void {
        const code = if (request.params) |params| blk: {
            if (params == .object) {
                if (params.object.get("code")) |c| {
                    if (c == .string) {
                        break :blk try self.allocator.dupe(u8, c.string);
                    }
                }
            }
            break :blk null;
        } else null;
        
        const instruction = if (request.params) |params| blk: {
            if (params == .object) {
                if (params.object.get("instruction")) |i| {
                    if (i == .string) {
                        break :blk try self.allocator.dupe(u8, i.string);
                    }
                }
            }
            break :blk null;
        } else null;
        
        if (code == null or instruction == null) {
            try self.sendError(request_id, -32602, "Invalid params", null);
            return;
        }
        defer self.allocator.free(code.?);
        defer self.allocator.free(instruction.?);
        
        const edit_prompt = try std.fmt.allocPrint(self.allocator, 
            "Edit this code according to the instruction.\\n\\nInstruction: {s}\\n\\nCode:\\n{s}", 
            .{ instruction.?, code.? });
        defer self.allocator.free(edit_prompt);
        
        _ = self.zeke_instance;
        const response = "Test edit response from GhostRPC";
        
        const result = std.json.Value{ .string = response };
        try self.sendResult(request_id, result);
    }
    
    fn handleExplain(self: *Self, request: Request, request_id: ?u64) !void {
        const code = if (request.params) |params| blk: {
            if (params == .object) {
                if (params.object.get("code")) |c| {
                    if (c == .string) {
                        break :blk try self.allocator.dupe(u8, c.string);
                    }
                }
            }
            break :blk null;
        } else null;
        
        if (code == null) {
            try self.sendError(request_id, -32602, "Invalid params", null);
            return;
        }
        defer self.allocator.free(code.?);
        
        const explain_prompt = try std.fmt.allocPrint(self.allocator, 
            "Explain this code in detail:\\n\\n{s}", 
            .{code.?});
        defer self.allocator.free(explain_prompt);
        
        _ = self.zeke_instance;
        const response = "Test explain response from GhostRPC";
        
        const result = std.json.Value{ .string = response };
        try self.sendResult(request_id, result);
    }
    
    fn handleComplete(self: *Self, request: Request, request_id: ?u64) !void {
        const code = if (request.params) |params| blk: {
            if (params == .object) {
                if (params.object.get("code")) |c| {
                    if (c == .string) {
                        break :blk try self.allocator.dupe(u8, c.string);
                    }
                }
            }
            break :blk null;
        } else null;
        
        if (code == null) {
            try self.sendError(request_id, -32602, "Invalid params", null);
            return;
        }
        defer self.allocator.free(code.?);
        
        const complete_prompt = try std.fmt.allocPrint(self.allocator, 
            "Complete this code:\\n\\n{s}", 
            .{code.?});
        defer self.allocator.free(complete_prompt);
        
        _ = self.zeke_instance;
        const response = "Test completion response from GhostRPC";
        
        const result = std.json.Value{ .string = response };
        try self.sendResult(request_id, result);
    }
    
    fn handleStatus(self: *Self, request: Request, request_id: ?u64) !void {
        _ = request;
        
        var status = std.json.ObjectMap.init(self.allocator);
        try status.put("version", std.json.Value{ .string = "0.2.3" });
        try status.put("status", std.json.Value{ .string = "running" });
        // TODO: Fix zeke_instance pointer casting to access current_provider
        _ = self.zeke_instance;
        try status.put("provider", std.json.Value{ .string = "ghostllm" });
        try status.put("rpc_type", std.json.Value{ .string = "GhostRPC" });
        
        try self.sendResult(request_id, std.json.Value{ .object = status });
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
        // For now, just log the response since we can't write to stdout
        std.log.info("RPC Response: {s}", .{json_string});
    }
};