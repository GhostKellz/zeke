const std = @import("std");

pub const GitInfo = struct {
    branch: []const u8,
    commit_hash: []const u8,
    is_dirty: bool,
    
    pub fn deinit(self: *GitInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.branch);
        allocator.free(self.commit_hash);
    }
};

pub const GitFile = struct {
    path: []const u8,
    status: GitFileStatus,
    
    pub fn deinit(self: *GitFile, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

pub const GitFileStatus = enum {
    modified,
    added,
    deleted,
    renamed,
    untracked,
    staged,
};

pub const GitOps = struct {
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
    
    pub fn getStatus(self: *Self) ![]GitFile {
        var files = std.ArrayList(GitFile){};
        defer {
            for (files.items) |*file| {
                file.deinit(self.allocator);
            }
            files.deinit(self.allocator);
        }
        
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"git", "status", "--porcelain"},
        }) catch |err| {
            std.log.err("Failed to run git status: {}", .{err});
            return error.GitCommandFailed;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            std.log.err("Git status failed: {s}", .{result.stderr});
            return error.GitCommandFailed;
        }
        
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            if (line.len < 3) continue;
            
            const status_code = line[0..2];
            const file_path = std.mem.trim(u8, line[3..], " ");
            
            if (file_path.len == 0) continue;
            
            const status = parseGitStatus(status_code);
            const path_copy = try self.allocator.dupe(u8, file_path);
            
            try files.append(self.allocator, GitFile{
                .path = path_copy,
                .status = status,
            });
        }
        
        return files.toOwnedSlice(self.allocator);
    }
    
    pub fn getCurrentBranch(self: *Self) ![]const u8 {
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"git", "rev-parse", "--abbrev-ref", "HEAD"},
        }) catch |err| {
            std.log.err("Failed to get current branch: {}", .{err});
            return error.GitCommandFailed;
        };
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            defer self.allocator.free(result.stdout);
            std.log.err("Git branch command failed: {s}", .{result.stderr});
            return error.GitCommandFailed;
        }
        
        const branch = std.mem.trim(u8, result.stdout, " \n\r\t");
        return try self.allocator.dupe(u8, branch);
    }
    
    pub fn getCurrentCommit(self: *Self) ![]const u8 {
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"git", "rev-parse", "HEAD"},
        }) catch |err| {
            std.log.err("Failed to get current commit: {}", .{err});
            return error.GitCommandFailed;
        };
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            defer self.allocator.free(result.stdout);
            std.log.err("Git commit command failed: {s}", .{result.stderr});
            return error.GitCommandFailed;
        }
        
        const commit_hash = std.mem.trim(u8, result.stdout, " \n\r\t");
        return try self.allocator.dupe(u8, commit_hash);
    }
    
    pub fn getDiff(self: *Self, file_path: ?[]const u8) ![]const u8 {
        var argv = std.ArrayList([]const u8){};
        defer argv.deinit(self.allocator);
        
        try argv.appendSlice(self.allocator, &[_][]const u8{"git", "diff"});
        if (file_path) |path| {
            try argv.append(self.allocator, path);
        }
        
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = argv.items,
        }) catch |err| {
            std.log.err("Failed to get git diff: {}", .{err});
            return error.GitCommandFailed;
        };
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            defer self.allocator.free(result.stdout);
            std.log.err("Git diff command failed: {s}", .{result.stderr});
            return error.GitCommandFailed;
        }
        
        return result.stdout;
    }
    
    pub fn addFile(self: *Self, file_path: []const u8) !void {
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"git", "add", file_path},
        }) catch |err| {
            std.log.err("Failed to add file: {}", .{err});
            return error.GitCommandFailed;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            std.log.err("Git add command failed: {s}", .{result.stderr});
            return error.GitCommandFailed;
        }
    }
    
    pub fn commit(self: *Self, message: []const u8) !void {
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"git", "commit", "-m", message},
        }) catch |err| {
            std.log.err("Failed to commit: {}", .{err});
            return error.GitCommandFailed;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            std.log.err("Git commit command failed: {s}", .{result.stderr});
            return error.GitCommandFailed;
        }
    }
    
    pub fn createPullRequest(self: *Self, title: []const u8, body: []const u8, base_branch: []const u8) !void {
        // Using GitHub CLI to create PR
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"gh", "pr", "create", "--title", title, "--body", body, "--base", base_branch},
        }) catch |err| {
            std.log.err("Failed to create PR: {}", .{err});
            return error.GitCommandFailed;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            std.log.err("GitHub PR creation failed: {s}", .{result.stderr});
            return error.GitCommandFailed;
        }
    }
    
    pub fn getGitInfo(self: *Self) !GitInfo {
        const branch = try self.getCurrentBranch();
        const commit_hash = try self.getCurrentCommit();
        
        // Check if working directory is dirty
        const files = try self.getStatus();
        defer {
            for (files) |*file| {
                file.deinit(self.allocator);
            }
            self.allocator.free(files);
        }
        
        const is_dirty = files.len > 0;
        
        return GitInfo{
            .branch = branch,
            .commit_hash = commit_hash,
            .is_dirty = is_dirty,
        };
    }
    
    pub fn isGitRepo(self: *Self) bool {
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{"git", "rev-parse", "--git-dir"},
        }) catch return false;
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        return result.term.Exited == 0;
    }
    
    fn parseGitStatus(status_code: []const u8) GitFileStatus {
        return switch (status_code[0]) {
            'M' => .modified,
            'A' => .added,
            'D' => .deleted,
            'R' => .renamed,
            '?' => .untracked,
            else => switch (status_code[1]) {
                'M' => .modified,
                'A' => .staged,
                'D' => .deleted,
                else => .untracked,
            },
        };
    }
};