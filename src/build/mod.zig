const std = @import("std");

pub const BuildSystem = enum {
    zig,
    cargo,
    npm,
    make,
    cmake,
    gradle,
    maven,
    go,
    unknown,
};

pub const BuildResult = struct {
    success: bool,
    output: []const u8,
    errors: []const u8,
    build_time_ms: u64,
    
    pub fn deinit(self: *BuildResult, allocator: std.mem.Allocator) void {
        allocator.free(self.output);
        allocator.free(self.errors);
    }
};

pub const BuildOps = struct {
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
    
    pub fn detectBuildSystem(self: *Self, project_path: []const u8) BuildSystem {
        // Check for various build system files
        if (self.fileExists(project_path, "build.zig")) return .zig;
        if (self.fileExists(project_path, "Cargo.toml")) return .cargo;
        if (self.fileExists(project_path, "package.json")) return .npm;
        if (self.fileExists(project_path, "Makefile") or self.fileExists(project_path, "makefile")) return .make;
        if (self.fileExists(project_path, "CMakeLists.txt")) return .cmake;
        if (self.fileExists(project_path, "build.gradle") or self.fileExists(project_path, "build.gradle.kts")) return .gradle;
        if (self.fileExists(project_path, "pom.xml")) return .maven;
        if (self.fileExists(project_path, "go.mod")) return .go;
        
        return .unknown;
    }
    
    pub fn build(self: *Self, project_path: []const u8, build_system: ?BuildSystem) !BuildResult {
        const system = build_system orelse self.detectBuildSystem(project_path);
        
        const start_time = std.time.milliTimestamp();
        
        const result = switch (system) {
            .zig => try self.runZigBuild(project_path),
            .cargo => try self.runCargoBuild(project_path),
            .npm => try self.runNpmBuild(project_path),
            .make => try self.runMakeBuild(project_path),
            .cmake => try self.runCmakeBuild(project_path),
            .gradle => try self.runGradleBuild(project_path),
            .maven => try self.runMavenBuild(project_path),
            .go => try self.runGoBuild(project_path),
            .unknown => return error.UnknownBuildSystem,
        };
        
        const end_time = std.time.milliTimestamp();
        const build_time: u64 = @intCast(end_time - start_time);
        
        return BuildResult{
            .success = result.term.Exited == 0,
            .output = result.stdout,
            .errors = result.stderr,
            .build_time_ms = build_time,
        };
    }
    
    pub fn test_(self: *Self, project_path: []const u8, build_system: ?BuildSystem) !BuildResult {
        const system = build_system orelse self.detectBuildSystem(project_path);
        
        const start_time = std.time.milliTimestamp();
        
        const result = switch (system) {
            .zig => try self.runZigTest(project_path),
            .cargo => try self.runCargoTest(project_path),
            .npm => try self.runNpmTest(project_path),
            .make => try self.runMakeTest(project_path),
            .gradle => try self.runGradleTest(project_path),
            .maven => try self.runMavenTest(project_path),
            .go => try self.runGoTest(project_path),
            .cmake, .unknown => return error.TestsNotSupported,
        };
        
        const end_time = std.time.milliTimestamp();
        const build_time: u64 = @intCast(end_time - start_time);
        
        return BuildResult{
            .success = result.term.Exited == 0,
            .output = result.stdout,
            .errors = result.stderr,
            .build_time_ms = build_time,
        };
    }
    
    pub fn clean(self: *Self, project_path: []const u8, build_system: ?BuildSystem) !BuildResult {
        const system = build_system orelse self.detectBuildSystem(project_path);
        
        const start_time = std.time.milliTimestamp();
        
        const result = switch (system) {
            .zig => try self.runZigClean(project_path),
            .cargo => try self.runCargoClean(project_path),
            .npm => try self.runNpmClean(project_path),
            .make => try self.runMakeClean(project_path),
            .gradle => try self.runGradleClean(project_path),
            .maven => try self.runMavenClean(project_path),
            .go => try self.runGoClean(project_path),
            .cmake, .unknown => return error.CleanNotSupported,
        };
        
        const end_time = std.time.milliTimestamp();
        const build_time: u64 = @intCast(end_time - start_time);
        
        return BuildResult{
            .success = result.term.Exited == 0,
            .output = result.stdout,
            .errors = result.stderr,
            .build_time_ms = build_time,
        };
    }
    
    fn fileExists(self: *Self, project_path: []const u8, filename: []const u8) bool {
        const full_path = std.fs.path.join(self.allocator, &[_][]const u8{ project_path, filename }) catch return false;
        defer self.allocator.free(full_path);
        
        std.fs.cwd().access(full_path, .{}) catch return false;
        return true;
    }
    
    fn runZigBuild(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"zig", "build"},
            .cwd = project_path,
        });
    }
    
    fn runZigTest(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"zig", "build", "test"},
            .cwd = project_path,
        });
    }
    
    fn runZigClean(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        // Zig doesn't have a built-in clean command, so we remove common build artifacts
        const cache_dir = std.fs.path.join(self.allocator, &[_][]const u8{ project_path, ".zig-cache" }) catch return error.OutOfMemory;
        defer self.allocator.free(cache_dir);
        
        const out_dir = std.fs.path.join(self.allocator, &[_][]const u8{ project_path, "zig-out" }) catch return error.OutOfMemory;
        defer self.allocator.free(out_dir);
        
        // Try to remove directories
        std.fs.cwd().deleteTree(cache_dir) catch {};
        std.fs.cwd().deleteTree(out_dir) catch {};
        
        return std.process.Child.RunResult{
            .term = std.process.Child.Term{ .Exited = 0 },
            .stdout = try self.allocator.dupe(u8, "Cleaned zig build artifacts\n"),
            .stderr = try self.allocator.dupe(u8, ""),
        };
    }
    
    fn runCargoBuild(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"cargo", "build"},
            .cwd = project_path,
        });
    }
    
    fn runCargoTest(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"cargo", "test"},
            .cwd = project_path,
        });
    }
    
    fn runCargoClean(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"cargo", "clean"},
            .cwd = project_path,
        });
    }
    
    fn runNpmBuild(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"npm", "run", "build"},
            .cwd = project_path,
        });
    }
    
    fn runNpmTest(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"npm", "test"},
            .cwd = project_path,
        });
    }
    
    fn runNpmClean(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"npm", "run", "clean"},
            .cwd = project_path,
        });
    }
    
    fn runMakeBuild(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"make"},
            .cwd = project_path,
        });
    }
    
    fn runMakeTest(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"make", "test"},
            .cwd = project_path,
        });
    }
    
    fn runMakeClean(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"make", "clean"},
            .cwd = project_path,
        });
    }
    
    fn runCmakeBuild(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        // Assume build directory exists
        const build_dir = std.fs.path.join(self.allocator, &[_][]const u8{ project_path, "build" }) catch return error.OutOfMemory;
        defer self.allocator.free(build_dir);
        
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"cmake", "--build", build_dir},
            .cwd = project_path,
        });
    }
    
    fn runGradleBuild(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"./gradlew", "build"},
            .cwd = project_path,
        });
    }
    
    fn runGradleTest(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"./gradlew", "test"},
            .cwd = project_path,
        });
    }
    
    fn runGradleClean(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"./gradlew", "clean"},
            .cwd = project_path,
        });
    }
    
    fn runMavenBuild(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"mvn", "compile"},
            .cwd = project_path,
        });
    }
    
    fn runMavenTest(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"mvn", "test"},
            .cwd = project_path,
        });
    }
    
    fn runMavenClean(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"mvn", "clean"},
            .cwd = project_path,
        });
    }
    
    fn runGoBuild(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"go", "build", "./..."},
            .cwd = project_path,
        });
    }
    
    fn runGoTest(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"go", "test", "./..."},
            .cwd = project_path,
        });
    }
    
    fn runGoClean(self: *Self, project_path: []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"go", "clean", "./..."},
            .cwd = project_path,
        });
    }
};