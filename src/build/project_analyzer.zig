const std = @import("std");

/// Project Analysis for Zig projects - parses build.zig and build.zig.zon
pub const ProjectAnalyzer = struct {
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub const Dependency = struct {
        name: []const u8,
        version: ?[]const u8 = null,
        url: ?[]const u8 = null,
        hash: ?[]const u8 = null,
        registry: ?[]const u8 = null,
        security_score: ?u8 = null,
        alternatives: [][]const u8 = &[_][]const u8{},
        
        pub fn deinit(self: *Dependency, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            if (self.version) |v| allocator.free(v);
            if (self.url) |u| allocator.free(u);
            if (self.hash) |h| allocator.free(h);
            if (self.registry) |r| allocator.free(r);
            for (self.alternatives) |alt| allocator.free(alt);
            allocator.free(self.alternatives);
        }
    };
    
    pub const BuildIssue = struct {
        type: IssueType,
        severity: Severity,
        message: []const u8,
        suggestion: ?[]const u8 = null,
        file: ?[]const u8 = null,
        line: ?u32 = null,
        
        pub const IssueType = enum {
            performance,
            security,
            compatibility,
            optimization,
            dependency,
        };
        
        pub const Severity = enum {
            low,
            medium,
            high,
            critical,
        };
        
        pub fn deinit(self: *BuildIssue, allocator: std.mem.Allocator) void {
            allocator.free(self.message);
            if (self.suggestion) |s| allocator.free(s);
            if (self.file) |f| allocator.free(f);
        }
    };
    
    pub const ProjectAnalysis = struct {
        project_name: ?[]const u8 = null,
        version: ?[]const u8 = null,
        build_system: []const u8,
        dependencies: []Dependency,
        build_issues: []BuildIssue,
        optimization_level: ?[]const u8 = null,
        target_info: ?[]const u8 = null,
        module_count: u32 = 0,
        estimated_build_time: ?u64 = null,
        
        pub fn deinit(self: *ProjectAnalysis, allocator: std.mem.Allocator) void {
            if (self.project_name) |name| allocator.free(name);
            if (self.version) |v| allocator.free(v);
            allocator.free(self.build_system);
            
            for (self.dependencies) |*dep| dep.deinit(allocator);
            allocator.free(self.dependencies);
            
            for (self.build_issues) |*issue| issue.deinit(allocator);
            allocator.free(self.build_issues);
            
            if (self.optimization_level) |opt| allocator.free(opt);
            if (self.target_info) |target| allocator.free(target);
        }
    };
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        _ = self;
    }
    
    pub fn analyzeProject(self: *Self, project_path: []const u8) !ProjectAnalysis {
        var analysis = ProjectAnalysis{
            .build_system = try self.allocator.dupe(u8, "zig"),
            .dependencies = &[_]Dependency{},
            .build_issues = &[_]BuildIssue{},
        };
        
        // Parse build.zig.zon for dependencies
        if (self.fileExists(project_path, "build.zig.zon")) {
            const deps = try self.parseBuildZon(project_path);
            analysis.dependencies = deps;
        }
        
        // Parse build.zig for configuration and issues
        if (self.fileExists(project_path, "build.zig")) {
            const build_info = try self.parseBuildZig(project_path);
            analysis.optimization_level = build_info.optimization_level;
            analysis.target_info = build_info.target_info;
            analysis.build_issues = build_info.issues;
        }
        
        // Count source modules
        analysis.module_count = try self.countZigModules(project_path);
        
        // Estimate build time based on dependencies and module count
        analysis.estimated_build_time = self.estimateBuildTime(analysis.dependencies.len, analysis.module_count);
        
        return analysis;
    }
    
    fn parseBuildZon(self: *Self, project_path: []const u8) ![]Dependency {
        const zon_path = try std.fs.path.join(self.allocator, &[_][]const u8{ project_path, "build.zig.zon" });
        defer self.allocator.free(zon_path);
        
        const file_content = std.fs.cwd().readFileAlloc(self.allocator, zon_path, 1024 * 1024) catch |err| {
            std.log.warn("Failed to read build.zig.zon: {}", .{err});
            return &[_]Dependency{};
        };
        defer self.allocator.free(file_content);
        
        // Simple parsing - look for dependency patterns
        var dependencies = std.ArrayList(Dependency).init(self.allocator);
        errdefer {
            for (dependencies.items) |*dep| dep.deinit(self.allocator);
            dependencies.deinit();
        }
        
        // Parse dependencies from .dependencies section
        if (std.mem.indexOf(u8, file_content, ".dependencies")) |deps_start| {
            const deps_section = file_content[deps_start..];
            
            // Look for dependency entries
            var line_iter = std.mem.split(u8, deps_section, "\n");
            while (line_iter.next()) |line| {
                const trimmed = std.mem.trim(u8, line, " \t");
                
                // Look for pattern: .name = .{ .url = "...", .hash = "..." }
                if (std.mem.startsWith(u8, trimmed, ".") and std.mem.indexOf(u8, trimmed, "=")) |_| {
                    const dep = try self.parseDepLine(trimmed);
                    if (dep) |d| {
                        try dependencies.append(d);
                    }
                }
            }
        }
        
        return dependencies.toOwnedSlice();
    }
    
    fn parseDepLine(self: *Self, line: []const u8) !?Dependency {
        // Extract dependency name from .name = pattern
        if (std.mem.indexOf(u8, line, ".")) |dot_pos| {
            if (std.mem.indexOf(u8, line[dot_pos + 1..], " ")) |space_pos| {
                const name_end = dot_pos + 1 + space_pos;
                const name = try self.allocator.dupe(u8, line[dot_pos + 1..name_end]);
                
                var dep = Dependency{
                    .name = name,
                };
                
                // Extract URL if present
                if (std.mem.indexOf(u8, line, ".url = \"")) |url_start| {
                    const url_begin = url_start + 8;
                    if (std.mem.indexOf(u8, line[url_begin..], "\"")) |url_end| {
                        dep.url = try self.allocator.dupe(u8, line[url_begin..url_begin + url_end]);
                    }
                }
                
                // Extract hash if present
                if (std.mem.indexOf(u8, line, ".hash = \"")) |hash_start| {
                    const hash_begin = hash_start + 9;
                    if (std.mem.indexOf(u8, line[hash_begin..], "\"")) |hash_end| {
                        dep.hash = try self.allocator.dupe(u8, line[hash_begin..hash_begin + hash_end]);
                    }
                }
                
                // Set some mock data for demonstration
                dep.security_score = 85; // Mock security score
                dep.registry = try self.allocator.dupe(u8, "zigistry");
                dep.alternatives = try self.allocator.alloc([]const u8, 0);
                
                return dep;
            }
        }
        return null;
    }
    
    const BuildInfo = struct {
        optimization_level: ?[]const u8 = null,
        target_info: ?[]const u8 = null,
        issues: []BuildIssue,
    };
    
    fn parseBuildZig(self: *Self, project_path: []const u8) !BuildInfo {
        const build_path = try std.fs.path.join(self.allocator, &[_][]const u8{ project_path, "build.zig" });
        defer self.allocator.free(build_path);
        
        const file_content = std.fs.cwd().readFileAlloc(self.allocator, build_path, 1024 * 1024) catch |err| {
            std.log.warn("Failed to read build.zig: {}", .{err});
            return BuildInfo{ .issues = &[_]BuildIssue{} };
        };
        defer self.allocator.free(file_content);
        
        var issues = std.ArrayList(BuildIssue).init(self.allocator);
        errdefer {
            for (issues.items) |*issue| issue.deinit(self.allocator);
            issues.deinit();
        }
        
        var opt_level: ?[]const u8 = null;
        var target_info: ?[]const u8 = null;
        
        // Analyze build.zig content for common patterns and issues
        var line_iter = std.mem.split(u8, file_content, "\n");
        var line_num: u32 = 0;
        
        while (line_iter.next()) |line| {
            line_num += 1;
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Check for optimization settings
            if (std.mem.indexOf(u8, trimmed, "optimize")) |_| {
                if (std.mem.indexOf(u8, trimmed, "Debug")) |_| {
                    opt_level = try self.allocator.dupe(u8, "Debug");
                    
                    // Suggest performance optimization
                    try issues.append(BuildIssue{
                        .type = .performance,
                        .severity = .medium,
                        .message = try self.allocator.dupe(u8, "Project is configured for Debug mode"),
                        .suggestion = try self.allocator.dupe(u8, "Consider using ReleaseFast for production builds"),
                        .file = try self.allocator.dupe(u8, "build.zig"),
                        .line = line_num,
                    });
                } else if (std.mem.indexOf(u8, trimmed, "ReleaseFast")) |_| {
                    opt_level = try self.allocator.dupe(u8, "ReleaseFast");
                } else if (std.mem.indexOf(u8, trimmed, "ReleaseSafe")) |_| {
                    opt_level = try self.allocator.dupe(u8, "ReleaseSafe");
                } else if (std.mem.indexOf(u8, trimmed, "ReleaseSmall")) |_| {
                    opt_level = try self.allocator.dupe(u8, "ReleaseSmall");
                }
            }
            
            // Check for target configuration
            if (std.mem.indexOf(u8, trimmed, "standardTargetOptions")) |_| {
                target_info = try self.allocator.dupe(u8, "native (default)");
            }
            
            // Check for potential security issues
            if (std.mem.indexOf(u8, trimmed, "addSystemLibrary") != null and std.mem.indexOf(u8, trimmed, "ssl") != null) {
                try issues.append(BuildIssue{
                    .type = .security,
                    .severity = .medium,
                    .message = try self.allocator.dupe(u8, "System SSL library usage detected"),
                    .suggestion = try self.allocator.dupe(u8, "Consider using a specific SSL/TLS library version for better security control"),
                    .file = try self.allocator.dupe(u8, "build.zig"),
                    .line = line_num,
                });
            }
        }
        
        return BuildInfo{
            .optimization_level = opt_level,
            .target_info = target_info,
            .issues = try issues.toOwnedSlice(),
        };
    }
    
    fn countZigModules(self: *Self, project_path: []const u8) !u32 {
        const src_path = try std.fs.path.join(self.allocator, &[_][]const u8{ project_path, "src" });
        defer self.allocator.free(src_path);
        
        var count: u32 = 0;
        
        // Simple approach - count .zig files in src directory
        var dir = std.fs.cwd().openDir(src_path, .{ .iterate = true }) catch {
            return 0; // No src directory
        };
        defer dir.close();
        
        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
                count += 1;
            }
        }
        
        return count;
    }
    
    fn estimateBuildTime(self: *Self, dep_count: usize, module_count: u32) u64 {
        _ = self;
        // Simple estimation formula
        const base_time: u64 = 1000; // 1 second base
        const dep_factor: u64 = @intCast(dep_count * 500); // 500ms per dependency
        const module_factor: u64 = module_count * 200; // 200ms per module
        
        return base_time + dep_factor + module_factor;
    }
    
    fn fileExists(self: *Self, project_path: []const u8, filename: []const u8) bool {
        const full_path = std.fs.path.join(self.allocator, &[_][]const u8{ project_path, filename }) catch return false;
        defer self.allocator.free(full_path);
        
        std.fs.cwd().access(full_path, .{}) catch return false;
        return true;
    }
};