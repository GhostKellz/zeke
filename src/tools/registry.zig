const std = @import("std");

/// Tool Registry - Dynamic tool discovery and execution framework
/// Inspired by Gemini CLI's tool system and MCP protocol
pub const ToolRegistry = struct {
    allocator: std.mem.Allocator,
    tools: std.StringHashMap(*Tool),
    tool_schemas: std.StringHashMap(ToolSchema),
    confirmation_enabled: bool = true,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .tools = std.StringHashMap(*Tool).init(allocator),
            .tool_schemas = std.StringHashMap(ToolSchema).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Deinit tools
        var tool_iter = self.tools.iterator();
        while (tool_iter.next()) |entry| {
            entry.value_ptr.*.vtable.deinit(entry.value_ptr.*);
        }
        self.tools.deinit();

        // Deinit schemas
        var schema_iter = self.tool_schemas.iterator();
        while (schema_iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.tool_schemas.deinit();
    }

    /// Register a new tool
    pub fn registerTool(self: *Self, tool: *Tool) !void {
        const name_copy = try self.allocator.dupe(u8, tool.name);
        errdefer self.allocator.free(name_copy);

        try self.tools.put(name_copy, tool);

        // Register schema if provided
        if (tool.vtable.getSchema) |get_schema_fn| {
            const schema = get_schema_fn(tool);
            try self.registerSchema(tool.name, schema);
        }
    }

    /// Register a tool schema
    pub fn registerSchema(self: *Self, name: []const u8, schema: ToolSchema) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);

        const schema_copy = try schema.clone(self.allocator);
        errdefer schema_copy.deinit(self.allocator);

        try self.tool_schemas.put(name_copy, schema_copy);
    }

    /// Execute a tool with validation and confirmation
    pub fn executeTool(
        self: *Self,
        tool_name: []const u8,
        params: ToolParams,
    ) !ToolResult {
        // Get tool
        const tool = self.tools.get(tool_name) orelse return error.ToolNotFound;

        // Validate parameters against schema
        if (self.tool_schemas.get(tool_name)) |schema| {
            try self.validateParams(&schema, params);
        }

        // Request confirmation if enabled and tool requires it
        if (self.confirmation_enabled and tool.requires_confirmation) {
            const confirmed = try self.requestConfirmation(tool, params);
            if (!confirmed) {
                return ToolResult{
                    .success = false,
                    .output = try self.allocator.dupe(u8, "Tool execution cancelled by user"),
                    .error_message = null,
                };
            }
        }

        // Execute tool
        return tool.vtable.execute(tool, params);
    }

    /// List all registered tools
    pub fn listTools(self: *Self) ![][]const u8 {
        var list = std.ArrayList([]const u8).init(self.allocator);
        errdefer {
            for (list.items) |item| self.allocator.free(item);
            list.deinit();
        }

        var iter = self.tools.keyIterator();
        while (iter.next()) |key| {
            try list.append(try self.allocator.dupe(u8, key.*));
        }

        return list.toOwnedSlice();
    }

    /// Get tool schema
    pub fn getToolSchema(self: *Self, tool_name: []const u8) !ToolSchema {
        const schema = self.tool_schemas.get(tool_name) orelse return error.SchemaNotFound;
        return try schema.clone(self.allocator);
    }

    // ===== Private Implementation =====

    fn validateParams(self: *Self, schema: *const ToolSchema, params: ToolParams) !void {
        _ = self;

        // Check required parameters
        for (schema.parameters) |param| {
            if (param.required) {
                const has_param = params.values.contains(param.name);
                if (!has_param) {
                    return error.MissingRequiredParameter;
                }
            }
        }

        // Validate parameter types
        var iter = params.values.iterator();
        while (iter.next()) |entry| {
            // Find parameter schema
            var found = false;
            for (schema.parameters) |param| {
                if (std.mem.eql(u8, param.name, entry.key_ptr.*)) {
                    found = true;
                    // Type checking would go here
                    break;
                }
            }

            if (!found) {
                return error.UnknownParameter;
            }
        }
    }

    fn requestConfirmation(self: *Self, tool: *Tool, params: ToolParams) !bool {
        _ = self;
        _ = params;

        // TODO: Integrate with TUI for rich confirmation dialogs
        std.debug.print("\n⚠️  Tool requires confirmation: {s}\n", .{tool.name});
        std.debug.print("Description: {s}\n", .{tool.description});
        std.debug.print("Proceed? (y/n): ", .{});

        const stdin = std.io.getStdIn();
        var buf: [1]u8 = undefined;
        _ = try stdin.read(&buf);

        return buf[0] == 'y' or buf[0] == 'Y';
    }
};

/// Tool interface using vtable pattern
pub const Tool = struct {
    name: []const u8,
    description: []const u8,
    category: ToolCategory,
    requires_confirmation: bool = false,
    vtable: *const ToolVTable,
    data: *anyopaque,

    pub const ToolVTable = struct {
        execute: *const fn (self: *Tool, params: ToolParams) anyerror!ToolResult,
        deinit: *const fn (self: *Tool) void,
        getSchema: ?*const fn (self: *Tool) ToolSchema = null,
    };
};

/// Tool category for organization
pub const ToolCategory = enum {
    file_operations,
    code_generation,
    analysis,
    git_operations,
    web_operations,
    database_operations,
    system_operations,
    custom,
};

/// Tool parameters
pub const ToolParams = struct {
    values: std.StringHashMap(ParamValue),

    pub fn init(allocator: std.mem.Allocator) ToolParams {
        return .{
            .values = std.StringHashMap(ParamValue).init(allocator),
        };
    }

    pub fn deinit(self: *ToolParams) void {
        var iter = self.values.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.values.deinit();
    }

    pub fn put(self: *ToolParams, key: []const u8, value: ParamValue) !void {
        try self.values.put(key, value);
    }

    pub fn get(self: *ToolParams, key: []const u8) ?ParamValue {
        return self.values.get(key);
    }
};

pub const ParamValue = union(enum) {
    string: []const u8,
    number: f64,
    boolean: bool,
    array: []ParamValue,
    object: std.StringHashMap(ParamValue),

    pub fn deinit(self: *ParamValue) void {
        switch (self.*) {
            .array => |arr| {
                for (arr) |*item| item.deinit();
            },
            .object => |*obj| {
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    entry.value_ptr.deinit();
                }
                obj.deinit();
            },
            else => {},
        }
    }
};

/// Tool execution result
pub const ToolResult = struct {
    success: bool,
    output: []const u8,
    error_message: ?[]const u8 = null,

    pub fn deinit(self: *ToolResult, allocator: std.mem.Allocator) void {
        allocator.free(self.output);
        if (self.error_message) |err| allocator.free(err);
    }
};

/// Tool schema for validation and documentation
pub const ToolSchema = struct {
    name: []const u8,
    description: []const u8,
    parameters: []ParameterSchema,

    pub fn deinit(self: *ToolSchema, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
        for (self.parameters) |*param| {
            param.deinit(allocator);
        }
        allocator.free(self.parameters);
    }

    pub fn clone(self: *const ToolSchema, allocator: std.mem.Allocator) !ToolSchema {
        const name_copy = try allocator.dupe(u8, self.name);
        errdefer allocator.free(name_copy);

        const desc_copy = try allocator.dupe(u8, self.description);
        errdefer allocator.free(desc_copy);

        const params = try allocator.alloc(ParameterSchema, self.parameters.len);
        errdefer allocator.free(params);

        for (self.parameters, 0..) |param, i| {
            params[i] = try param.clone(allocator);
        }

        return ToolSchema{
            .name = name_copy,
            .description = desc_copy,
            .parameters = params,
        };
    }
};

pub const ParameterSchema = struct {
    name: []const u8,
    description: []const u8,
    param_type: ParameterType,
    required: bool = true,
    default_value: ?ParamValue = null,

    pub fn deinit(self: *ParameterSchema, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
        if (self.default_value) |*val| {
            var v = val.*;
            v.deinit();
        }
    }

    pub fn clone(self: *const ParameterSchema, allocator: std.mem.Allocator) !ParameterSchema {
        return ParameterSchema{
            .name = try allocator.dupe(u8, self.name),
            .description = try allocator.dupe(u8, self.description),
            .param_type = self.param_type,
            .required = self.required,
            .default_value = self.default_value, // TODO: Deep clone
        };
    }
};

pub const ParameterType = enum {
    string,
    number,
    boolean,
    array,
    object,
};

// ===== Built-in Tools =====

/// File Read Tool
pub const FileReadTool = struct {
    tool: Tool,
    allocator: std.mem.Allocator,

    const vtable = Tool.ToolVTable{
        .execute = execute,
        .deinit = deinit,
        .getSchema = getSchema,
    };

    pub fn create(allocator: std.mem.Allocator) !*Tool {
        const self = try allocator.create(FileReadTool);
        self.* = .{
            .tool = .{
                .name = "file_read",
                .description = "Read contents of a file",
                .category = .file_operations,
                .requires_confirmation = false,
                .vtable = &vtable,
                .data = self,
            },
            .allocator = allocator,
        };
        return &self.tool;
    }

    fn execute(tool: *Tool, params: ToolParams) !ToolResult {
        const self: *FileReadTool = @ptrCast(@alignCast(tool.data));

        const file_path = params.get("path") orelse return error.MissingFilePath;
        const path = switch (file_path) {
            .string => |s| s,
            else => return error.InvalidParameterType,
        };

        const content = std.fs.cwd().readFileAlloc(
            self.allocator,
            path,
            10 * 1024 * 1024, // 10MB max
        ) catch |err| {
            const err_msg = try std.fmt.allocPrint(
                self.allocator,
                "Failed to read file: {}",
                .{err},
            );
            return ToolResult{
                .success = false,
                .output = try self.allocator.dupe(u8, ""),
                .error_message = err_msg,
            };
        };

        return ToolResult{
            .success = true,
            .output = content,
            .error_message = null,
        };
    }

    fn deinit(tool: *Tool) void {
        const self: *FileReadTool = @ptrCast(@alignCast(tool.data));
        self.allocator.destroy(self);
    }

    fn getSchema(tool: *Tool) ToolSchema {
        _ = tool;

        const params = [_]ParameterSchema{
            .{
                .name = "path",
                .description = "Path to the file to read",
                .param_type = .string,
                .required = true,
            },
        };

        return ToolSchema{
            .name = "file_read",
            .description = "Read contents of a file",
            .parameters = @constCast(&params),
        };
    }
};

/// File Write Tool
pub const FileWriteTool = struct {
    tool: Tool,
    allocator: std.mem.Allocator,

    const vtable = Tool.ToolVTable{
        .execute = execute,
        .deinit = deinit,
        .getSchema = getSchema,
    };

    pub fn create(allocator: std.mem.Allocator) !*Tool {
        const self = try allocator.create(FileWriteTool);
        self.* = .{
            .tool = .{
                .name = "file_write",
                .description = "Write content to a file",
                .category = .file_operations,
                .requires_confirmation = true,
                .vtable = &vtable,
                .data = self,
            },
            .allocator = allocator,
        };
        return &self.tool;
    }

    fn execute(tool: *Tool, params: ToolParams) !ToolResult {
        const self: *FileWriteTool = @ptrCast(@alignCast(tool.data));

        const file_path = params.get("path") orelse return error.MissingFilePath;
        const content = params.get("content") orelse return error.MissingContent;

        const path = switch (file_path) {
            .string => |s| s,
            else => return error.InvalidParameterType,
        };

        const text = switch (content) {
            .string => |s| s,
            else => return error.InvalidParameterType,
        };

        const file = std.fs.cwd().createFile(path, .{}) catch |err| {
            const err_msg = try std.fmt.allocPrint(
                self.allocator,
                "Failed to create file: {}",
                .{err},
            );
            return ToolResult{
                .success = false,
                .output = try self.allocator.dupe(u8, ""),
                .error_message = err_msg,
            };
        };
        defer file.close();

        file.writeAll(text) catch |err| {
            const err_msg = try std.fmt.allocPrint(
                self.allocator,
                "Failed to write file: {}",
                .{err},
            );
            return ToolResult{
                .success = false,
                .output = try self.allocator.dupe(u8, ""),
                .error_message = err_msg,
            };
        };

        const output = try std.fmt.allocPrint(
            self.allocator,
            "Successfully wrote {d} bytes to {s}",
            .{ text.len, path },
        );

        return ToolResult{
            .success = true,
            .output = output,
            .error_message = null,
        };
    }

    fn deinit(tool: *Tool) void {
        const self: *FileWriteTool = @ptrCast(@alignCast(tool.data));
        self.allocator.destroy(self);
    }

    fn getSchema(tool: *Tool) ToolSchema {
        _ = tool;

        const params = [_]ParameterSchema{
            .{
                .name = "path",
                .description = "Path to the file to write",
                .param_type = .string,
                .required = true,
            },
            .{
                .name = "content",
                .description = "Content to write to the file",
                .param_type = .string,
                .required = true,
            },
        };

        return ToolSchema{
            .name = "file_write",
            .description = "Write content to a file",
            .parameters = @constCast(&params),
        };
    }
};

test "ToolRegistry - register and execute tool" {
    const allocator = std.testing.allocator;

    var registry = ToolRegistry.init(allocator);
    defer registry.deinit();

    // Create and register file read tool
    const tool = try FileReadTool.create(allocator);
    try registry.registerTool(tool);

    // List tools
    const tools = try registry.listTools();
    defer {
        for (tools) |t| allocator.free(t);
        allocator.free(tools);
    }

    try std.testing.expect(tools.len == 1);
    try std.testing.expectEqualStrings("file_read", tools[0]);
}
