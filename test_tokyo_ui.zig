const std = @import("std");
const tokyo = @import("src/tui/tokyo_night.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();

    // Get username
    const username = std.posix.getenv("USER") orelse "User";

    // Get current directory
    var cwd_buf: [1024]u8 = undefined;
    const cwd = try std.fs.cwd().realpath(".", &cwd_buf);

    var screen = tokyo.WelcomeScreen.init(
        allocator,
        username,
        "Sonnet 4.5 • Claude Max",
        cwd,
    );

    try screen.render(stdout);
}
