//! Smart Git Tools - Zap Integration
//!
//! High-level Git operations powered by Zap AI

const std = @import("std");
const zeke = @import("zeke");
const integrations = @import("../integrations/mod.zig");
const git_ops = zeke.git;

/// Smart Git tool using Zap AI
pub const SmartGit = struct {
    allocator: std.mem.Allocator,
    zap_git: integrations.ZapGit,
    git_ops: git_ops.GitOps,

    pub fn init(allocator: std.mem.Allocator) SmartGit {
        return .{
            .allocator = allocator,
            .zap_git = integrations.ZapGit.init(allocator),
            .git_ops = git_ops.GitOps.init(allocator),
        };
    }

    pub fn deinit(self: *SmartGit) void {
        self.zap_git.deinit();
        self.git_ops.deinit();
    }

    /// Generate a smart commit with AI-generated message
    pub fn smartCommit(self: *SmartGit, files: ?[]const []const u8) !void {
        // Stage files if provided
        if (files) |file_list| {
            for (file_list) |file| {
                try self.git_ops.addFile(file);
            }
        } else {
            // Stage all changes (add .)
            try self.git_ops.addFile(".");
        }

        // Get the diff
        const diff = try self.git_ops.getDiff(null);
        defer self.allocator.free(diff);

        if (diff.len == 0) {
            std.log.warn("No changes to commit", .{});
            return error.NoChanges;
        }

        // Generate commit message using Zap AI
        const commit_msg = try self.zap_git.generateCommitMessage(diff, null);
        defer self.allocator.free(commit_msg);

        std.log.info("Generated commit message:\n{s}", .{commit_msg});

        // Confirm with user (in future, add interactive prompt)
        std.log.info("Creating commit...", .{});

        // Create the commit
        try self.git_ops.commit(commit_msg);

        std.log.info("✅ Smart commit created successfully!", .{});
    }

    /// Analyze and resolve merge conflicts with AI assistance
    pub fn resolveConflict(self: *SmartGit, file_path: []const u8) !void {
        _ = self;
        // TODO: Fix file reading API for this Zig version
        std.log.info("Conflict resolution for {s} - coming soon!", .{file_path});
    }

    /// Run security scan on recent commits
    pub fn securityScan(self: *SmartGit, commit_range: ?[]const u8) !void {
        const repo_path = try std.fs.cwd().realpathAlloc(self.allocator, ".");
        defer self.allocator.free(repo_path);

        var report = try self.zap_git.securityReview(repo_path, commit_range);
        defer report.deinit(self.allocator);

        std.log.info("🔒 Security Scan Results", .{});
        std.log.info("Scanned: {s}", .{report.repo_path});
        std.log.info("Issues found: {d}", .{report.issues.len});

        if (report.issues.len > 0) {
            std.log.warn("\n⚠️  Security Issues:", .{});
            for (report.issues) |issue| {
                const severity_icon = switch (issue.severity) {
                    .critical => "🔴",
                    .high => "🟠",
                    .medium => "🟡",
                    .low => "🔵",
                };
                std.log.warn("{s} [{s}] {s}: {s}", .{
                    severity_icon,
                    @tagName(issue.severity),
                    issue.file_path,
                    issue.description,
                });
            }
        } else {
            std.log.info("✅ No security issues detected", .{});
        }
    }

    /// Generate changelog between two refs
    pub fn generateChangelog(
        self: *SmartGit,
        from_ref: []const u8,
        to_ref: []const u8,
        output_file: ?[]const u8,
    ) !void {
        const changelog = try self.zap_git.generateChangelog(from_ref, to_ref);
        defer self.allocator.free(changelog);

        if (output_file) |path| {
            try std.fs.cwd().writeFile(.{ .sub_path = path, .data = changelog });
            std.log.info("✅ Changelog written to {s}", .{path});
        } else {
            std.log.info("Changelog:\n{s}", .{changelog});
        }
    }

    /// Explain what changed in a commit or diff
    pub fn explainChanges(self: *SmartGit, commit_ref: ?[]const u8) !void {
        _ = commit_ref; // TODO: Implement diff for specific commit
        const diff = try self.git_ops.getDiff(null);
        defer self.allocator.free(diff);

        const explanation = try self.zap_git.explainChanges(diff);
        defer self.allocator.free(explanation);

        std.log.info("📝 Change Explanation:\n{s}", .{explanation});
    }
};

test "SmartGit init" {
    const allocator = std.testing.allocator;
    var smart_git = SmartGit.init(allocator);
    defer smart_git.deinit();
}
