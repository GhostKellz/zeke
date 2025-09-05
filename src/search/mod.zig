const std = @import("std");

pub const SearchResult = struct {
    file_path: []const u8,
    line_number: u32,
    content: []const u8,
    context_before: []const u8,
    context_after: []const u8,
    
    pub fn deinit(self: *SearchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.file_path);
        allocator.free(self.content);
        allocator.free(self.context_before);
        allocator.free(self.context_after);
    }
};

pub const SearchOptions = struct {
    case_sensitive: bool = false,
    regex: bool = false,
    context_lines: u8 = 3,
    include_binary: bool = false,
    max_results: u32 = 1000,
    file_patterns: []const []const u8 = &[_][]const u8{},
    exclude_patterns: []const []const u8 = &[_][]const u8{".git", "node_modules", "target", "zig-cache", "zig-out"},
};

pub const FileSearch = struct {
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        _ = self;
    }
    
    pub fn searchInFiles(self: *Self, pattern: []const u8, root_path: []const u8, options: SearchOptions) ![]SearchResult {
        var results = std.ArrayList(SearchResult){};
        defer {
            for (results.items) |*result| {
                result.deinit(self.allocator);
            }
            results.deinit(self.allocator);
        }
        
        try self.searchInDirectory(pattern, root_path, options, &results);
        
        return results.toOwnedSlice(self.allocator);
    }
    
    pub fn searchInFile(self: *Self, pattern: []const u8, file_path: []const u8, options: SearchOptions) ![]SearchResult {
        var results = std.ArrayList(SearchResult){};
        defer {
            for (results.items) |*result| {
                result.deinit(self.allocator);
            }
            results.deinit(self.allocator);
        }
        
        try self.searchFileContent(pattern, file_path, options, &results);
        
        return results.toOwnedSlice(self.allocator);
    }
    
    pub fn findFiles(self: *Self, name_pattern: []const u8, root_path: []const u8) ![][]const u8 {
        var files = std.ArrayList([]const u8){};
        defer {
            for (files.items) |file| {
                self.allocator.free(file);
            }
            files.deinit(self.allocator);
        }
        
        try self.findFilesInDirectory(name_pattern, root_path, &files);
        
        return files.toOwnedSlice(self.allocator);
    }
    
    pub fn grepCommand(self: *Self, pattern: []const u8, file_patterns: []const []const u8, options: SearchOptions) ![]SearchResult {
        var argv = std.ArrayList([]const u8){};
        defer argv.deinit(self.allocator);
        
        try argv.appendSlice(self.allocator, &[_][]const u8{"rg", "--json"});
        
        if (!options.case_sensitive) {
            try argv.append(self.allocator, "-i");
        }
        
        if (options.context_lines > 0) {
            const context_arg = try std.fmt.allocPrint(self.allocator, "-C{d}", .{options.context_lines});
            defer self.allocator.free(context_arg);
            try argv.append(self.allocator, context_arg);
        }
        
        try argv.append(self.allocator, pattern);
        
        for (file_patterns) |file_pattern| {
            try argv.append(self.allocator, file_pattern);
        }
        
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = argv.items,
        }) catch |err| {
            std.log.err("Failed to run rg command: {}", .{err});
            return error.SearchCommandFailed;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0 and result.term.Exited != 1) {
            std.log.err("Ripgrep command failed: {s}", .{result.stderr});
            return error.SearchCommandFailed;
        }
        
        return try self.parseRgOutput(result.stdout);
    }
    
    fn searchInDirectory(self: *Self, pattern: []const u8, dir_path: []const u8, options: SearchOptions, results: *std.ArrayList(SearchResult)) !void {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
            std.log.warn("Failed to open directory {s}: {}", .{ dir_path, err });
            return;
        };
        defer dir.close();
        
        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            const entry_path = try std.fs.path.join(self.allocator, &[_][]const u8{ dir_path, entry.name });
            defer self.allocator.free(entry_path);
            
            // Check exclude patterns
            var should_exclude = false;
            for (options.exclude_patterns) |exclude| {
                if (std.mem.indexOf(u8, entry_path, exclude) != null) {
                    should_exclude = true;
                    break;
                }
            }
            if (should_exclude) continue;
            
            switch (entry.kind) {
                .directory => {
                    try self.searchInDirectory(pattern, entry_path, options, results);
                },
                .file => {
                    if (self.shouldSearchFile(entry_path, options)) {
                        try self.searchFileContent(pattern, entry_path, options, results);
                    }
                },
                else => continue,
            }
            
            if (results.items.len >= options.max_results) break;
        }
    }
    
    fn searchFileContent(self: *Self, pattern: []const u8, file_path: []const u8, options: SearchOptions, results: *std.ArrayList(SearchResult)) !void {
        const content = std.fs.cwd().readFileAlloc(file_path, self.allocator, @as(std.Io.Limit, @enumFromInt(10 * 1024 * 1024))) catch |err| {
            if (err != error.FileTooBig) {
                std.log.warn("Failed to read file {s}: {}", .{ file_path, err });
            }
            return;
        };
        defer self.allocator.free(content);
        
        // Check for binary content
        if (!options.include_binary and self.isBinaryContent(content)) {
            return;
        }
        
        var lines = std.mem.splitScalar(u8, content, '\n');
        var line_contents = std.ArrayList([]const u8){};
        defer line_contents.deinit(self.allocator);
        
        // Store lines for context
        while (lines.next()) |line| {
            try line_contents.append(self.allocator, line);
        }
        
        // Search through lines
        for (line_contents.items, 0..) |line, i| {
            const line_num = @as(u32, @intCast(i + 1));
            
            const found = if (options.case_sensitive)
                std.mem.indexOf(u8, line, pattern) != null
            else
                std.ascii.indexOfIgnoreCase(line, pattern) != null;
            
            if (found) {
                const context_start = if (i >= options.context_lines) i - options.context_lines else 0;
                const context_end = @min(i + options.context_lines + 1, line_contents.items.len);
                
                var context_before = std.ArrayList(u8){};
                defer context_before.deinit(self.allocator);
                
                var context_after = std.ArrayList(u8){};
                defer context_after.deinit(self.allocator);
                
                // Collect context before
                for (line_contents.items[context_start..i]) |ctx_line| {
                    try context_before.appendSlice(self.allocator, ctx_line);
                    try context_before.append(self.allocator, '\n');
                }
                
                // Collect context after
                for (line_contents.items[i + 1..context_end]) |ctx_line| {
                    try context_after.appendSlice(self.allocator, ctx_line);
                    try context_after.append(self.allocator, '\n');
                }
                
                try results.append(self.allocator, SearchResult{
                    .file_path = try self.allocator.dupe(u8, file_path),
                    .line_number = line_num,
                    .content = try self.allocator.dupe(u8, line),
                    .context_before = try context_before.toOwnedSlice(self.allocator),
                    .context_after = try context_after.toOwnedSlice(self.allocator),
                });
            }
            
            if (results.items.len >= options.max_results) break;
        }
    }
    
    fn findFilesInDirectory(self: *Self, name_pattern: []const u8, dir_path: []const u8, files: *std.ArrayList([]const u8)) !void {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
            std.log.warn("Failed to open directory {s}: {}", .{ dir_path, err });
            return;
        };
        defer dir.close();
        
        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            const entry_path = try std.fs.path.join(self.allocator, &[_][]const u8{ dir_path, entry.name });
            
            switch (entry.kind) {
                .directory => {
                    if (!std.mem.eql(u8, entry.name, ".git") and !std.mem.eql(u8, entry.name, "node_modules")) {
                        try self.findFilesInDirectory(name_pattern, entry_path, files);
                    }
                    self.allocator.free(entry_path);
                },
                .file => {
                    if (std.mem.indexOf(u8, entry.name, name_pattern) != null) {
                        try files.append(self.allocator, entry_path);
                    } else {
                        self.allocator.free(entry_path);
                    }
                },
                else => {
                    self.allocator.free(entry_path);
                },
            }
        }
    }
    
    fn shouldSearchFile(self: *Self, file_path: []const u8, options: SearchOptions) bool {
        _ = self;
        
        // Check file patterns if specified
        if (options.file_patterns.len > 0) {
            var matches = false;
            for (options.file_patterns) |pattern| {
                if (std.mem.indexOf(u8, file_path, pattern) != null) {
                    matches = true;
                    break;
                }
            }
            if (!matches) return false;
        }
        
        // Skip known binary extensions
        const extension = std.fs.path.extension(file_path);
        const binary_extensions = [_][]const u8{ ".exe", ".bin", ".so", ".dll", ".dylib", ".a", ".o", ".obj", ".png", ".jpg", ".jpeg", ".gif", ".pdf", ".zip", ".tar", ".gz" };
        
        for (binary_extensions) |bin_ext| {
            if (std.mem.eql(u8, extension, bin_ext)) {
                return false;
            }
        }
        
        return true;
    }
    
    fn isBinaryContent(self: *Self, content: []const u8) bool {
        _ = self;
        
        // Simple heuristic: if more than 1% of bytes are non-printable, consider it binary
        var non_printable: u32 = 0;
        const sample_size = @min(content.len, 1024);
        
        for (content[0..sample_size]) |byte| {
            if (byte < 32 and byte != '\n' and byte != '\r' and byte != '\t') {
                non_printable += 1;
            }
        }
        
        return (non_printable * 100) / sample_size > 1;
    }
    
    fn parseRgOutput(self: *Self, output: []const u8) ![]SearchResult {
        var results = std.ArrayList(SearchResult){};
        defer {
            for (results.items) |*result| {
                result.deinit(self.allocator);
            }
            results.deinit(self.allocator);
        }
        
        var lines = std.mem.splitScalar(u8, output, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            
            // Parse JSON output from ripgrep using new std.json API
            const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, line, .{}) catch continue;
            defer parsed.deinit();
            
            const root = parsed.value;
            if (root != .object) continue;
            
            const obj = root.object;
            const type_value = obj.get("type") orelse continue;
            if (type_value != .string or !std.mem.eql(u8, type_value.string, "match")) continue;
            
            const data = obj.get("data") orelse continue;
            if (data != .object) continue;
            
            const data_obj = data.object;
            
            const path_value = data_obj.get("path") orelse continue;
            const line_number_value = data_obj.get("line_number") orelse continue;
            const lines_value = data_obj.get("lines") orelse continue;
            
            if (path_value != .string or line_number_value != .integer or lines_value != .object) continue;
            
            const lines_obj = lines_value.object;
            const text_value = lines_obj.get("text") orelse continue;
            if (text_value != .string) continue;
            
            try results.append(self.allocator, SearchResult{
                .file_path = try self.allocator.dupe(u8, path_value.string),
                .line_number = @as(u32, @intCast(line_number_value.integer)),
                .content = try self.allocator.dupe(u8, text_value.string),
                .context_before = try self.allocator.dupe(u8, ""),
                .context_after = try self.allocator.dupe(u8, ""),
            });
        }
        
        return results.toOwnedSlice(self.allocator);
    }
};