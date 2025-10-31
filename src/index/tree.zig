// Tree Generator - Creates balanced directory tree for AI context
// Adapted from OpenCode's ripgrep tree generation algorithm

const std = @import("std");

/// Tree node representing a file or directory
pub const TreeNode = struct {
    name: []const u8,
    is_dir: bool,
    children: std.ArrayList(*TreeNode),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, is_dir: bool) !*TreeNode {
        const node = try allocator.create(TreeNode);
        node.* = .{
            .name = try allocator.dupe(u8, name),
            .is_dir = is_dir,
            .children = std.ArrayList(*TreeNode).empty,
            .allocator = allocator,
        };
        return node;
    }

    pub fn deinit(self: *TreeNode) void {
        for (self.children.items) |child| {
            child.deinit();
        }
        self.children.deinit(self.allocator);
        self.allocator.free(self.name);
        self.allocator.destroy(self);
    }

    /// Sort children: directories first, then alphabetically
    pub fn sortChildren(self: *TreeNode) void {
        std.mem.sort(*TreeNode, self.children.items, {}, struct {
            fn lessThan(_: void, a: *TreeNode, b: *TreeNode) bool {
                // Directories before files
                if (a.is_dir and !b.is_dir) return true;
                if (!a.is_dir and b.is_dir) return false;
                // Alphabetically within same type
                return std.mem.lessThan(u8, a.name, b.name);
            }
        }.lessThan);

        // Recursively sort children's children
        for (self.children.items) |child| {
            if (child.is_dir) {
                child.sortChildren();
            }
        }
    }
};

/// Tree builder with depth limiting
pub const TreeBuilder = struct {
    allocator: std.mem.Allocator,
    max_depth: usize,
    max_files_per_dir: usize,

    pub fn init(allocator: std.mem.Allocator) TreeBuilder {
        return .{
            .allocator = allocator,
            .max_depth = 4, // Default depth limit
            .max_files_per_dir = 50, // Prevent overwhelming output
        };
    }

    /// Build tree from list of file paths
    pub fn buildFromPaths(self: *TreeBuilder, paths: []const []const u8) !*TreeNode {
        const root = try TreeNode.init(self.allocator, ".", true);
        errdefer root.deinit();

        for (paths) |path| {
            try self.insertPath(root, path, 0);
        }

        root.sortChildren();
        return root;
    }

    /// Insert a path into the tree
    fn insertPath(self: *TreeBuilder, node: *TreeNode, path: []const u8, depth: usize) !void {
        if (depth >= self.max_depth) return;

        // Split path into components
        var parts = std.mem.splitScalar(u8, path, '/');
        const first = parts.next() orelse return;

        if (parts.peek() == null) {
            // This is a file
            if (node.children.items.len >= self.max_files_per_dir) return;

            // Check if already exists
            for (node.children.items) |child| {
                if (std.mem.eql(u8, child.name, first)) return;
            }

            const file_node = try TreeNode.init(self.allocator, first, false);
            try node.children.append(self.allocator, file_node);
        } else {
            // This is a directory
            var dir_node: ?*TreeNode = null;

            // Find or create directory node
            for (node.children.items) |child| {
                if (child.is_dir and std.mem.eql(u8, child.name, first)) {
                    dir_node = child;
                    break;
                }
            }

            if (dir_node == null) {
                const new_dir = try TreeNode.init(self.allocator, first, true);
                try node.children.append(self.allocator, new_dir);
                dir_node = new_dir;
            }

            // Recurse with remaining path
            const remaining = path[first.len + 1 ..];
            try self.insertPath(dir_node.?, remaining, depth + 1);
        }
    }

    /// Render tree to string with box-drawing characters
    pub fn renderTree(self: *TreeBuilder, root: *TreeNode) ![]const u8 {
        var output = std.ArrayList(u8).empty;
        defer output.deinit(self.allocator);

        try self.renderNode(root, &output, "", true, 0);
        return output.toOwnedSlice(self.allocator);
    }

    fn renderNode(
        self: *TreeBuilder,
        node: *TreeNode,
        output: *std.ArrayList(u8),
        prefix: []const u8,
        is_last: bool,
        depth: usize,
    ) !void {
        if (depth >= self.max_depth) {
            try output.writer().print("{s}└── ... (depth limit reached)\n", .{prefix});
            return;
        }

        // Don't print root name
        if (depth > 0) {
            const connector = if (is_last) "└── " else "├── ";
            const icon = if (node.is_dir) "📁 " else "📄 ";
            try output.writer().print("{s}{s}{s}{s}\n", .{ prefix, connector, icon, node.name });
        }

        // Calculate new prefix for children
        var new_prefix = std.ArrayList(u8).empty;
        defer new_prefix.deinit(self.allocator);

        if (depth > 0) {
            try new_prefix.appendSlice(self.allocator, prefix);
            try new_prefix.appendSlice(self.allocator, if (is_last) "    " else "│   ");
        }

        // Render children
        const child_count = node.children.items.len;
        var shown: usize = 0;
        var truncated: usize = 0;

        for (node.children.items, 0..) |child, i| {
            if (shown >= self.max_files_per_dir) {
                truncated += 1;
                continue;
            }

            const child_is_last = (i == child_count - 1) and truncated == 0;
            try self.renderNode(child, output, new_prefix.items, child_is_last, depth + 1);
            shown += 1;
        }

        if (truncated > 0) {
            const connector = "└── ";
            try output.writer().print("{s}{s}... ({} more files truncated)\n", .{ new_prefix.items, connector, truncated });
        }
    }
};

/// Generate a concise tree view for AI context
pub fn generateContextTree(
    allocator: std.mem.Allocator,
    file_paths: []const []const u8,
    max_depth: usize,
) ![]const u8 {
    var builder = TreeBuilder.init(allocator);
    builder.max_depth = max_depth;

    const root = try builder.buildFromPaths(file_paths);
    defer root.deinit();

    return try builder.renderTree(root);
}

// Tests
test "TreeBuilder: basic tree" {
    const allocator = std.testing.allocator;

    const paths = [_][]const u8{
        "src/main.zig",
        "src/utils.zig",
        "src/core/index.zig",
        "src/core/search.zig",
        "README.md",
    };

    var builder = TreeBuilder.init(allocator);
    const root = try builder.buildFromPaths(&paths);
    defer root.deinit();

    try std.testing.expectEqual(@as(usize, 2), root.children.items.len); // src and README.md
}

test "TreeBuilder: depth limiting" {
    const allocator = std.testing.allocator;

    const paths = [_][]const u8{
        "a/b/c/d/e/f/file.zig",
    };

    var builder = TreeBuilder.init(allocator);
    builder.max_depth = 3;

    const root = try builder.buildFromPaths(&paths);
    defer root.deinit();

    const rendered = try builder.renderTree(root);
    defer allocator.free(rendered);

    // Should contain depth limit message
    try std.testing.expect(std.mem.indexOf(u8, rendered, "depth limit") != null);
}
