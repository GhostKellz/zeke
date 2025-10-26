const std = @import("std");

/// Code Generator - Template-based code generation with AI enhancement
/// Supports multiple languages and frameworks
pub const CodeGenerator = struct {
    allocator: std.mem.Allocator,
    template_registry: TemplateRegistry,
    ai_chat_fn: ?*const fn ([]const u8) anyerror![]const u8 = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
            .template_registry = try TemplateRegistry.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.template_registry.deinit();
    }

    /// Generate code from a template
    pub fn generateFromTemplate(
        self: *Self,
        template_name: []const u8,
        context: TemplateContext,
    ) !GeneratedCode {
        const template = try self.template_registry.getTemplate(template_name);

        // Render template with context
        const code = try self.renderTemplate(template, context);

        return GeneratedCode{
            .code = code,
            .language = template.language,
            .file_path = if (context.file_path) |fp|
                try self.allocator.dupe(u8, fp)
            else
                null,
        };
    }

    /// Generate code from natural language description using AI
    pub fn generateFromDescription(
        self: *Self,
        description: []const u8,
        language: Language,
        options: GenerateOptions,
    ) !GeneratedCode {
        if (self.ai_chat_fn == null) return error.NoAIClientConfigured;

        const prompt = try self.buildPrompt(description, language, options);
        defer self.allocator.free(prompt);

        const response = try self.ai_chat_fn.?(prompt);
        defer self.allocator.free(response);

        // Extract code from response (handle markdown code blocks)
        const code = try self.extractCode(response);

        return GeneratedCode{
            .code = code,
            .language = language,
            .file_path = if (options.file_path) |fp|
                try self.allocator.dupe(u8, fp)
            else
                null,
        };
    }

    /// Generate multiple related files (e.g., API + tests + docs)
    pub fn generateMultiFile(
        self: *Self,
        spec: MultiFileSpec,
    ) ![]GeneratedCode {
        var results = std.ArrayList(GeneratedCode).init(self.allocator);
        errdefer {
            for (results.items) |*r| r.deinit(self.allocator);
            results.deinit();
        }

        for (spec.files) |file_spec| {
            const code = try self.generateFromDescription(
                file_spec.description,
                file_spec.language,
                .{
                    .file_path = file_spec.file_path,
                    .include_tests = file_spec.include_tests,
                    .include_docs = file_spec.include_docs,
                },
            );
            try results.append(code);
        }

        return results.toOwnedSlice();
    }

    /// Generate boilerplate for common patterns
    pub fn generateBoilerplate(
        self: *Self,
        pattern: BoilerplatePattern,
        config: BoilerplateConfig,
    ) !GeneratedCode {
        const template_name = switch (pattern) {
            .api_endpoint => "api_endpoint",
            .database_model => "database_model",
            .cli_command => "cli_command",
            .unit_test => "unit_test",
            .integration_test => "integration_test",
            .dockerfile => "dockerfile",
            .github_action => "github_action",
            .readme => "readme",
        };

        const context = try self.buildBoilerplateContext(pattern, config);
        defer context.deinit(self.allocator);

        return try self.generateFromTemplate(template_name, context);
    }

    // ===== Private Implementation =====

    fn renderTemplate(
        self: *Self,
        template: Template,
        context: TemplateContext,
    ) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        const writer = result.writer();

        // Simple template engine - replace {{var}} with context values
        var iter = std.mem.splitSequence(u8, template.content, "{{");

        const first = iter.next() orelse "";
        try writer.writeAll(first);

        while (iter.next()) |segment| {
            if (std.mem.indexOf(u8, segment, "}}")) |end_idx| {
                const var_name = segment[0..end_idx];
                const rest = segment[end_idx + 2 ..];

                // Look up variable in context
                if (context.variables.get(var_name)) |value| {
                    try writer.writeAll(value);
                } else {
                    try writer.print("{{{{{s}}}}}", .{var_name}); // Keep original if not found
                }

                try writer.writeAll(rest);
            } else {
                try writer.print("{{{{{s}", .{segment});
            }
        }

        return result.toOwnedSlice();
    }

    fn buildPrompt(
        self: *Self,
        description: []const u8,
        language: Language,
        options: GenerateOptions,
    ) ![]const u8 {
        var prompt = std.ArrayList(u8).init(self.allocator);
        errdefer prompt.deinit();

        const writer = prompt.writer();

        try writer.print("Generate {s} code for the following:\n\n", .{@tagName(language)});
        try writer.writeAll(description);
        try writer.writeAll("\n\n");

        if (options.include_tests) {
            try writer.writeAll("Include comprehensive unit tests.\n");
        }

        if (options.include_docs) {
            try writer.writeAll("Include detailed documentation comments.\n");
        }

        if (options.include_error_handling) {
            try writer.writeAll("Include proper error handling.\n");
        }

        try writer.writeAll("\nProvide only the code, wrapped in a markdown code block.\n");

        return prompt.toOwnedSlice();
    }

    fn extractCode(self: *Self, response: []const u8) ![]const u8 {
        // Look for markdown code block
        const start_marker = "```";
        const start_idx = std.mem.indexOf(u8, response, start_marker);

        if (start_idx) |start| {
            // Skip language identifier on first line
            const code_start = std.mem.indexOfScalarPos(u8, response, start + 3, '\n');
            if (code_start) |cs| {
                const end_marker = "```";
                const end_idx = std.mem.indexOfPos(u8, response, cs, end_marker);

                if (end_idx) |end| {
                    return try self.allocator.dupe(u8, response[cs + 1 .. end]);
                }
            }
        }

        // No code block found, return entire response
        return try self.allocator.dupe(u8, response);
    }

    fn buildBoilerplateContext(
        self: *Self,
        pattern: BoilerplatePattern,
        config: BoilerplateConfig,
    ) !TemplateContext {
        var variables = std.StringHashMap([]const u8).init(self.allocator);
        errdefer variables.deinit();

        // Common variables
        try variables.put("project_name", config.project_name);
        try variables.put("author", config.author orelse "Unknown");

        // Pattern-specific variables
        switch (pattern) {
            .api_endpoint => {
                try variables.put("endpoint_path", config.endpoint_path orelse "/api");
                try variables.put("method", config.http_method orelse "GET");
            },
            .database_model => {
                try variables.put("model_name", config.model_name orelse "Model");
                try variables.put("table_name", config.table_name orelse "models");
            },
            .cli_command => {
                try variables.put("command_name", config.command_name orelse "command");
            },
            else => {},
        }

        return TemplateContext{
            .variables = variables,
            .file_path = config.output_path,
        };
    }
};

/// Template Registry - Manages code generation templates
pub const TemplateRegistry = struct {
    allocator: std.mem.Allocator,
    templates: std.StringHashMap(Template),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        var templates = std.StringHashMap(Template).init(allocator);
        errdefer templates.deinit();

        // Register built-in templates
        try registerBuiltinTemplates(&templates, allocator);

        return .{
            .allocator = allocator,
            .templates = templates,
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.templates.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.name);
            self.allocator.free(entry.value_ptr.content);
        }
        self.templates.deinit();
    }

    pub fn getTemplate(self: *Self, name: []const u8) !Template {
        return self.templates.get(name) orelse error.TemplateNotFound;
    }

    pub fn registerTemplate(self: *Self, template: Template) !void {
        const name_copy = try self.allocator.dupe(u8, template.name);
        errdefer self.allocator.free(name_copy);

        const content_copy = try self.allocator.dupe(u8, template.content);
        errdefer self.allocator.free(content_copy);

        try self.templates.put(name_copy, Template{
            .name = name_copy,
            .content = content_copy,
            .language = template.language,
        });
    }
};

fn registerBuiltinTemplates(
    templates: *std.StringHashMap(Template),
    allocator: std.mem.Allocator,
) !void {
    // API Endpoint template
    const api_endpoint = Template{
        .name = "api_endpoint",
        .content =
        \\const std = @import("std");
        \\
        \\pub fn {{endpoint_name}}(req: *Request, res: *Response) !void {
        \\    // TODO: Implement {{endpoint_name}}
        \\    try res.json(.{
        \\        .message = "{{endpoint_name}} endpoint",
        \\        .status = "success",
        \\    });
        \\}
        \\
        \\test "{{endpoint_name}}" {
        \\    // TODO: Add tests
        \\}
        ,
        .language = .zig,
    };
    try templates.put(
        try allocator.dupe(u8, api_endpoint.name),
        .{
            .name = try allocator.dupe(u8, api_endpoint.name),
            .content = try allocator.dupe(u8, api_endpoint.content),
            .language = api_endpoint.language,
        },
    );

    // CLI Command template
    const cli_command = Template{
        .name = "cli_command",
        .content =
        \\const std = @import("std");
        \\
        \\pub const {{command_name}}Command = struct {
        \\    allocator: std.mem.Allocator,
        \\
        \\    pub fn init(allocator: std.mem.Allocator) @This() {
        \\        return .{ .allocator = allocator };
        \\    }
        \\
        \\    pub fn execute(self: *@This(), args: []const []const u8) !void {
        \\        _ = self;
        \\        _ = args;
        \\        // TODO: Implement {{command_name}} command
        \\        std.debug.print("Executing {{command_name}}\n", .{});
        \\    }
        \\};
        ,
        .language = .zig,
    };
    try templates.put(
        try allocator.dupe(u8, cli_command.name),
        .{
            .name = try allocator.dupe(u8, cli_command.name),
            .content = try allocator.dupe(u8, cli_command.content),
            .language = cli_command.language,
        },
    );

    // Unit Test template
    const unit_test = Template{
        .name = "unit_test",
        .content =
        \\const std = @import("std");
        \\const testing = std.testing;
        \\
        \\test "{{test_name}}" {
        \\    // Arrange
        \\    const allocator = testing.allocator;
        \\
        \\    // Act
        \\    // TODO: Implement test logic
        \\
        \\    // Assert
        \\    try testing.expect(true);
        \\}
        ,
        .language = .zig,
    };
    try templates.put(
        try allocator.dupe(u8, unit_test.name),
        .{
            .name = try allocator.dupe(u8, unit_test.name),
            .content = try allocator.dupe(u8, unit_test.content),
            .language = unit_test.language,
        },
    );
}

// ===== Types =====

pub const Template = struct {
    name: []const u8,
    content: []const u8,
    language: Language,
};

pub const TemplateContext = struct {
    variables: std.StringHashMap([]const u8),
    file_path: ?[]const u8 = null,

    pub fn deinit(self: *TemplateContext, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.variables.deinit();
    }
};

pub const GeneratedCode = struct {
    code: []const u8,
    language: Language,
    file_path: ?[]const u8 = null,

    pub fn deinit(self: *GeneratedCode, allocator: std.mem.Allocator) void {
        allocator.free(self.code);
        if (self.file_path) |fp| allocator.free(fp);
    }
};

pub const Language = enum {
    zig,
    rust,
    go,
    javascript,
    typescript,
    python,
    c,
    cpp,
    java,
    csharp,
};

pub const GenerateOptions = struct {
    file_path: ?[]const u8 = null,
    include_tests: bool = false,
    include_docs: bool = false,
    include_error_handling: bool = true,
};

pub const MultiFileSpec = struct {
    files: []const FileSpec,
};

pub const FileSpec = struct {
    description: []const u8,
    language: Language,
    file_path: ?[]const u8 = null,
    include_tests: bool = false,
    include_docs: bool = false,
};

pub const BoilerplatePattern = enum {
    api_endpoint,
    database_model,
    cli_command,
    unit_test,
    integration_test,
    dockerfile,
    github_action,
    readme,
};

pub const BoilerplateConfig = struct {
    project_name: []const u8,
    author: ?[]const u8 = null,
    output_path: ?[]const u8 = null,

    // Pattern-specific fields
    endpoint_path: ?[]const u8 = null,
    http_method: ?[]const u8 = null,
    model_name: ?[]const u8 = null,
    table_name: ?[]const u8 = null,
    command_name: ?[]const u8 = null,
};

test "TemplateRegistry - register and retrieve" {
    const allocator = std.testing.allocator;

    var registry = try TemplateRegistry.init(allocator);
    defer registry.deinit();

    const template = try registry.getTemplate("api_endpoint");
    try std.testing.expectEqualStrings("api_endpoint", template.name);
}

test "CodeGenerator - simple template rendering" {
    const allocator = std.testing.allocator;

    var generator = try CodeGenerator.init(allocator);
    defer generator.deinit();

    var variables = std.StringHashMap([]const u8).init(allocator);
    defer variables.deinit();
    try variables.put("endpoint_name", "getUserById");

    const context = TemplateContext{
        .variables = variables,
    };

    const result = try generator.generateFromTemplate("api_endpoint", context);
    defer result.deinit(allocator);

    try std.testing.expect(std.mem.indexOf(u8, result.code, "getUserById") != null);
}
