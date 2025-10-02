//! Zeke Watch Mode - Continuous AI Development Loop
//!
//! Watches files for changes, parses with Grove, detects issues,
//! suggests fixes via Ollama, and auto-commits when tests pass.
//!
//! Usage:
//!   zeke watch [--auto-fix] [--auto-commit] [--model=ollama]

const std = @import("std");
const grove = @import("grove");
const zap = @import("zap");
const integrations = @import("integrations/mod.zig");
const file_watcher = @import("file_watcher.zig");
const todo_tracker = @import("tools/todo_tracker.zig");

/// Watch mode configuration
pub const WatchConfig = struct {
    /// Automatically apply suggested fixes
    auto_fix: bool = false,

    /// Automatically commit when tests pass
    auto_commit: bool = false,

    /// Model to use for suggestions
    model: []const u8 = "ollama",

    /// Directories to watch (default: current directory)
    watch_paths: []const []const u8 = &[_][]const u8{"."},

    /// File patterns to watch (default: zig files)
    patterns: []const []const u8 = &[_][]const u8{
        "*.zig",
        "*.json",
    },

    /// Ignore patterns
    ignore_patterns: []const []const u8 = &[_][]const u8{
        "zig-cache/**",
        "zig-out/**",
        ".git/**",
        ".zeke/**",
    },
};

/// Issue detected by Grove analysis
pub const Issue = struct {
    severity: Severity,
    message: []const u8,
    file_path: []const u8,
    line: usize,
    column: usize,
    suggestion: ?[]const u8 = null,

    pub const Severity = enum {
        @"error",
        warning,
        info,
        hint,
    };

    pub fn deinit(self: *Issue, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        allocator.free(self.file_path);
        if (self.suggestion) |s| allocator.free(s);
    }
};

/// Watch mode state
pub const WatchMode = struct {
    allocator: std.mem.Allocator,
    config: WatchConfig,
    grove_ast: *integrations.GroveAST,
    zap_git: integrations.ZapGit,
    file_watcher: ?*file_watcher.FileWatcher,
    running: bool,

    pub fn init(allocator: std.mem.Allocator, config: WatchConfig) !*WatchMode {
        const self = try allocator.create(WatchMode);
        errdefer allocator.destroy(self);

        // Initialize Grove AST
        const grove_ast = try allocator.create(integrations.GroveAST);
        errdefer allocator.destroy(grove_ast);
        grove_ast.* = try integrations.GroveAST.init(allocator);

        // Initialize Zap for AI-powered suggestions
        var zap_git = integrations.ZapGit.init(allocator);
        zap_git.initOllama(null, config.model) catch |err| {
            std.log.warn("Failed to initialize Ollama: {}. AI suggestions disabled.", .{err});
        };

        self.* = .{
            .allocator = allocator,
            .config = config,
            .grove_ast = grove_ast,
            .zap_git = zap_git,
            .file_watcher = null,
            .running = false,
        };

        return self;
    }

    pub fn deinit(self: *WatchMode) void {
        if (self.file_watcher) |watcher| {
            watcher.deinit();
            self.allocator.destroy(watcher);
        }
        self.zap_git.deinit();
        self.grove_ast.deinit();
        self.allocator.destroy(self.grove_ast);
        self.allocator.destroy(self);
    }

    /// Start watching files
    pub fn start(self: *WatchMode) !void {
        self.running = true;

        std.log.info("⚡ Zeke Watch Mode started", .{});
        std.log.info("📂 Watching: {s}", .{self.config.watch_paths[0]});
        std.log.info("🔧 Auto-fix: {}", .{self.config.auto_fix});
        std.log.info("📝 Auto-commit: {}", .{self.config.auto_commit});

        // Initial scan
        std.log.info("🔍 Running initial scan...", .{});
        try self.scanDirectory(".");
        std.log.info("✅ Initial scan complete", .{});

        // Initialize file watcher
        const watcher = try self.allocator.create(file_watcher.FileWatcher);
        errdefer self.allocator.destroy(watcher);

        watcher.* = try file_watcher.FileWatcher.init(
            self.allocator,
            self.config.watch_paths,
            self.config.ignore_patterns,
        );
        self.file_watcher = watcher;

        // Start watching for changes
        try watcher.start();
        std.log.info("👁️  Watching for file changes... (press Ctrl+C to stop)", .{});

        // Event loop
        while (self.running) {
            if (try watcher.nextEvent()) |event| {
                defer {
                    var mut_event = event;
                    mut_event.deinit();
                }

                const event_icon = switch (event.event_type) {
                    .created => "✨",
                    .modified => "📝",
                    .deleted => "🗑️ ",
                    .renamed => "📦",
                };

                std.log.info("{s} {s} - {s}", .{
                    event_icon,
                    @tagName(event.event_type),
                    event.path,
                });

                // Analyze the changed file
                if (event.event_type == .modified or event.event_type == .created) {
                    self.analyzeFile(event.path) catch |err| {
                        std.log.err("Failed to analyze {s}: {}", .{ event.path, err });
                    };
                }
            }
        }
    }

    /// Generate AI-powered fix suggestion for an issue
    fn generateFixSuggestion(self: *WatchMode, issue: *Issue, file_content: []const u8) !?[]const u8 {
        // Build context for the AI
        const prompt = try std.fmt.allocPrint(
            self.allocator,
            "File analysis found an issue:\n" ++
                "Severity: {s}\n" ++
                "Message: {s}\n" ++
                "Location: {s}:{d}:{d}\n\n" ++
                "File content:\n{s}\n\n" ++
                "Provide a concise fix suggestion (1-2 sentences):",
            .{
                @tagName(issue.severity),
                issue.message,
                issue.file_path,
                issue.line,
                issue.column,
                file_content,
            },
        );
        defer self.allocator.free(prompt);

        // Try to get AI suggestion
        if (self.zap_git.ollama_client) |*client| {
            const request = zap.ollama.GenerateRequest{
                .model = "deepseek-coder:33b",
                .prompt = prompt,
                .stream = false,
            };

            const suggestion = client.generate(request) catch |err| {
                std.log.warn("Failed to generate AI suggestion: {}", .{err});
                return null;
            };
            return suggestion;
        }

        return null;
    }

    /// Apply auto-fix to a file based on issue and suggestion
    fn applyAutoFix(self: *WatchMode, issue: *const Issue, suggestion: []const u8) !void {
        if (!self.config.auto_fix) return;

        std.log.info("🔧 Auto-fixing {s}:{d}:{d}", .{ issue.file_path, issue.line, issue.column });
        std.log.info("   Fix: {s}", .{suggestion});

        // TODO: Implement actual code transformation using Grove AST
        // For now, just log what would be done
        std.log.info("   ⚠️  Auto-fix not yet implemented - would apply: {s}", .{suggestion});
    }

    /// Run tests to verify changes are safe
    fn runTests(self: *WatchMode) !bool {
        // Try to run zig build test
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "zig", "build", "test" },
            .cwd = ".",
        }) catch |err| {
            std.log.warn("Failed to run tests: {}", .{err});
            return false;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        const passed = result.term.Exited == 0;
        if (passed) {
            std.log.info("✅ All tests passed", .{});
        } else {
            std.log.err("❌ Tests failed:\n{s}", .{result.stderr});
        }

        return passed;
    }

    /// Auto-commit fixes after tests pass
    fn autoCommit(self: *WatchMode, file_path: []const u8, fix_count: usize) !void {
        std.log.info("📝 Auto-committing {d} fix(es) in {s}...", .{ fix_count, file_path });

        // Stage the file
        const add_result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "git", "add", file_path },
            .cwd = ".",
        }) catch |err| {
            return err;
        };
        defer self.allocator.free(add_result.stdout);
        defer self.allocator.free(add_result.stderr);

        if (add_result.term.Exited != 0) {
            std.log.err("Failed to git add: {s}", .{add_result.stderr});
            return error.GitAddFailed;
        }

        // Generate commit message
        const commit_message = try std.fmt.allocPrint(
            self.allocator,
            "fix: auto-fix {d} issue(s) in {s}\n\n" ++
                "Automatically fixed by Zeke Watch Mode\n" ++
                "- Applied AI-suggested fixes\n" ++
                "- All tests passed\n\n" ++
                "🤖 Generated with Zeke Watch Mode",
            .{ fix_count, std.fs.path.basename(file_path) },
        );
        defer self.allocator.free(commit_message);

        // Create commit
        const commit_result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "git", "commit", "-m", commit_message },
            .cwd = ".",
        }) catch |err| {
            return err;
        };
        defer self.allocator.free(commit_result.stdout);
        defer self.allocator.free(commit_result.stderr);

        if (commit_result.term.Exited == 0) {
            std.log.info("✅ Auto-commit successful!", .{});
        } else {
            std.log.err("Failed to commit: {s}", .{commit_result.stderr});
            return error.GitCommitFailed;
        }
    }

    /// Scan a directory for files to analyze
    fn scanDirectory(self: *WatchMode, dir_path: []const u8) !void {
        var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
        defer dir.close();

        var iterator = dir.iterate();
        var file_count: usize = 0;

        while (try iterator.next()) |entry| {
            // Skip ignored patterns
            if (self.shouldIgnore(entry.name)) continue;

            const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ dir_path, entry.name });
            defer self.allocator.free(full_path);

            switch (entry.kind) {
                .directory => {
                    // Recurse into subdirectories
                    try self.scanDirectory(full_path);
                },
                .file => {
                    // Check if file matches patterns
                    if (self.matchesPattern(entry.name)) {
                        try self.analyzeFile(full_path);
                        file_count += 1;
                    }
                },
                else => {},
            }
        }

        if (file_count > 0) {
            std.log.info("📊 Analyzed {d} files in {s}", .{ file_count, dir_path });
        }
    }

    /// Check if path should be ignored
    fn shouldIgnore(self: *WatchMode, path: []const u8) bool {
        for (self.config.ignore_patterns) |pattern| {
            // Simple prefix matching for now
            // TODO: Implement glob pattern matching
            if (std.mem.startsWith(u8, pattern, path)) return true;
            if (std.mem.indexOf(u8, pattern, "**") != null) {
                // Handle ** pattern (matches any directory depth)
                const prefix = std.mem.sliceTo(pattern, '*');
                if (std.mem.startsWith(u8, path, prefix)) return true;
            }
        }
        return false;
    }

    /// Check if filename matches watch patterns
    fn matchesPattern(self: *WatchMode, filename: []const u8) bool {
        for (self.config.patterns) |pattern| {
            if (std.mem.endsWith(u8, filename, std.mem.sliceTo(pattern, '*'))) {
                return true;
            }
        }
        return false;
    }

    /// Analyze a single file with Grove
    fn analyzeFile(self: *WatchMode, file_path: []const u8) !void {
        // Determine language from extension
        const ext = std.fs.path.extension(file_path);
        const language = integrations.grove.Language.fromFileExtension(ext) orelse {
            std.log.debug("Skipping {s}: unsupported language", .{file_path});
            return;
        };

        std.log.info("🔍 Analyzing {s}...", .{file_path});

        // Parse file with Grove
        const parsed = self.grove_ast.parseFile(file_path, language) catch |err| {
            std.log.err("Failed to parse {s}: {}", .{ file_path, err });
            return;
        };
        defer parsed.deinit();

        // Detect issues using Grove queries
        const issues = try self.detectIssues(parsed, file_path);
        defer {
            for (issues) |*issue| issue.deinit(self.allocator);
            self.allocator.free(issues);
        }

        if (issues.len == 0) {
            std.log.info("✅ {s} - No issues found", .{file_path});
            return;
        }

        // Report issues and get AI suggestions
        var fixed_count: usize = 0;
        for (issues) |*issue| {
            const severity_icon = switch (issue.severity) {
                .@"error" => "❌",
                .warning => "⚠️ ",
                .info => "ℹ️ ",
                .hint => "💡",
            };

            std.log.info("{s} {s}:{d}:{d} - {s}", .{
                severity_icon,
                issue.file_path,
                issue.line,
                issue.column,
                issue.message,
            });

            // Show existing suggestion if present
            if (issue.suggestion) |suggestion| {
                std.log.info("   💡 Suggestion: {s}", .{suggestion});
            }

            // Try to get AI-powered suggestion if enabled and no suggestion exists
            if (issue.suggestion == null and self.zap_git.ollama_client != null) {
                const ai_suggestion = self.generateFixSuggestion(issue, parsed.source) catch |err| {
                    std.log.warn("   ⚠️  Failed to generate AI suggestion: {}", .{err});
                    continue;
                };

                if (ai_suggestion) |suggestion| {
                    defer self.allocator.free(suggestion);
                    std.log.info("   🤖 AI Suggestion: {s}", .{suggestion});

                    // Apply auto-fix if enabled
                    if (self.config.auto_fix) {
                        self.applyAutoFix(issue, suggestion) catch |err| {
                            std.log.err("   ❌ Failed to apply fix: {}", .{err});
                            continue;
                        };
                        fixed_count += 1;
                    }
                }
            }
        }

        // Auto-commit if fixes were applied and tests pass
        if (fixed_count > 0 and self.config.auto_commit) {
            std.log.info("🧪 Running tests before auto-commit...", .{});
            const tests_passed = self.runTests() catch false;

            if (tests_passed) {
                self.autoCommit(file_path, fixed_count) catch |err| {
                    std.log.err("❌ Failed to auto-commit: {}", .{err});
                };
            } else {
                std.log.warn("⚠️  Tests failed, skipping auto-commit", .{});
            }
        }
    }

    /// Detect issues in parsed code using Grove queries
    fn detectIssues(self: *WatchMode, parsed: *integrations.grove.ParsedFile, file_path: []const u8) ![]Issue {
        var issues_list: std.ArrayList(Issue) = .{};
        errdefer issues_list.deinit(self.allocator);

        // Query 1: Find unused variables (Zig-specific)
        if (parsed.language == .zig) {
            try self.detectUnusedVariables(parsed, file_path, &issues_list);
        }

        // Query 2: Find TODO comments
        try self.detectTodoComments(parsed, file_path, &issues_list);

        // Query 3: Find functions without error handling
        // TODO: Implement with Grove queries

        // Query 4: Find functions without tests
        // TODO: Implement by checking for corresponding test files

        return try issues_list.toOwnedSlice(self.allocator);
    }

    /// Detect unused variables using Grove
    fn detectUnusedVariables(
        self: *WatchMode,
        parsed: *integrations.grove.ParsedFile,
        file_path: []const u8,
        issues: *std.ArrayList(Issue),
    ) !void {
        _ = self;
        _ = file_path;
        _ = issues;

        // For now, use simple text-based detection
        // TODO: Use Grove query to find variable declarations and check usage

        var lines = std.mem.splitScalar(u8, parsed.source, '\n');
        var line_no: usize = 1;

        while (lines.next()) |line| : (line_no += 1) {
            // Simple heuristic: look for "const x = " or "var x = " where x is not used later
            if (std.mem.indexOf(u8, line, "const ") != null or
                std.mem.indexOf(u8, line, "var ") != null)
            {
                // Check if it starts with underscore (intentionally unused)
                const trimmed = std.mem.trim(u8, line, " \t");
                if (std.mem.indexOf(u8, trimmed, "_ =") != null) continue;

                // This is a placeholder - real implementation would use Grove queries
                // to check if the variable is actually used
            }
        }
    }

    /// Detect TODO comments with rich tracking
    fn detectTodoComments(
        self: *WatchMode,
        parsed: *integrations.grove.ParsedFile,
        file_path: []const u8,
        issues: *std.ArrayList(Issue),
    ) !void {
        var tracker = todo_tracker.TodoTracker.init(self.allocator);
        defer tracker.deinit();

        // Extract all TODOs from the file
        try tracker.extractTodos(file_path, parsed.source);

        // Convert TODOs to issues with priority-based severity
        for (tracker.todos.items) |todo| {
            const severity: Issue.Severity = switch (todo.priority) {
                .critical => .@"error",
                .high => .warning,
                .medium, .low, .normal => .info,
            };

            const category_str: []const u8 = switch (todo.category) {
                .bug_fix => "Bug Fix",
                .refactor => "Refactor",
                .optimization => "Optimization",
                .documentation => "Documentation",
                .feature => "Feature",
                .security => "Security",
                .@"test" => "Test",
                .hack => "Hack/Workaround",
                .unknown => "TODO",
            };

            // Build detailed message
            const message = if (todo.assignee) |assignee| blk: {
                if (todo.issue_ref) |issue_ref| {
                    break :blk try std.fmt.allocPrint(
                        self.allocator,
                        "{s} [{s}]: {s} (@{s}) (#{s})",
                        .{ todo.marker, category_str, todo.message, assignee, issue_ref },
                    );
                } else {
                    break :blk try std.fmt.allocPrint(
                        self.allocator,
                        "{s} [{s}]: {s} (@{s})",
                        .{ todo.marker, category_str, todo.message, assignee },
                    );
                }
            } else if (todo.issue_ref) |issue_ref| blk: {
                break :blk try std.fmt.allocPrint(
                    self.allocator,
                    "{s} [{s}]: {s} (#{s})",
                    .{ todo.marker, category_str, todo.message, issue_ref },
                );
            } else try std.fmt.allocPrint(
                self.allocator,
                "{s} [{s}]: {s}",
                .{ todo.marker, category_str, todo.message },
            );

            // Generate context-aware suggestion
            const suggestion = try self.generateTodoSuggestion(todo);

            try issues.append(self.allocator, .{
                .severity = severity,
                .message = message,
                .file_path = try self.allocator.dupe(u8, file_path),
                .line = todo.line,
                .column = todo.column,
                .suggestion = suggestion,
            });
        }
    }

    /// Generate smart suggestions for TODO items
    fn generateTodoSuggestion(self: *WatchMode, todo: todo_tracker.TodoItem) !?[]const u8 {
        const suggestion = switch (todo.category) {
            .bug_fix => "Consider creating a GitHub issue to track this bug fix",
            .refactor => "Consider creating a refactoring task and planning the changes",
            .optimization => "Profile this code section to identify the bottleneck before optimizing",
            .documentation => "Add comprehensive documentation with examples",
            .feature => if (todo.issue_ref != null)
                try std.fmt.allocPrint(
                    self.allocator,
                    "Implement feature tracked in issue #{s}",
                    .{todo.issue_ref.?},
                )
            else
                "Consider creating a GitHub issue to track this feature",
            .security => "URGENT: Address this security concern immediately",
            .@"test" => "Add test coverage for this code path",
            .hack => "Replace this workaround with a proper solution",
            .unknown => "Consider creating a GitHub issue or implementing this",
        };

        // Return owned string
        if (todo.category == .feature and todo.issue_ref != null) {
            return suggestion; // Already allocated
        }
        return try self.allocator.dupe(u8, suggestion);
    }
};

/// Entry point for watch mode
pub fn runWatchMode(allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    var config = WatchConfig{};

    // Parse command-line arguments
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--auto-fix")) {
            config.auto_fix = true;
        } else if (std.mem.eql(u8, arg, "--auto-commit")) {
            config.auto_commit = true;
        } else if (std.mem.startsWith(u8, arg, "--model=")) {
            config.model = arg[8..];
        }
    }

    var watch_mode = try WatchMode.init(allocator, config);
    defer watch_mode.deinit();

    try watch_mode.start();

    // Keep running until interrupted
    // TODO: Implement signal handling for graceful shutdown
}

test "WatchMode init" {
    const allocator = std.testing.allocator;
    const config = WatchConfig{};
    var watch_mode = try WatchMode.init(allocator, config);
    defer watch_mode.deinit();
}
