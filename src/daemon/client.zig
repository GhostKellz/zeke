// Daemon Client - Communicates with Zeke daemon via Unix socket

const std = @import("std");
const daemon = @import("daemon.zig");

/// Send a request to the daemon and get response
pub fn sendRequest(allocator: std.mem.Allocator, request_json: []const u8) ![]const u8 {
    // Connect to daemon
    const address = try std.net.Address.initUnix(daemon.SOCKET_PATH);
    const stream = try std.net.tcpConnectToAddress(address);
    defer stream.close();

    // Send request
    _ = try stream.write(request_json);

    // Read response
    var buf: [65536]u8 = undefined;
    const n = try stream.read(&buf);

    return try allocator.dupe(u8, buf[0..n]);
}

/// Check if daemon is running
pub fn isDaemonRunning() bool {
    std.fs.cwd().access(daemon.SOCKET_PATH, .{}) catch return false;
    return true;
}

/// Send a ping to check daemon responsiveness
pub fn ping(allocator: std.mem.Allocator) ![]const u8 {
    const request = "{\"method\":\"ping\"}";
    return try sendRequest(allocator, request);
}

/// Request LSP diagnostics
pub fn requestDiagnostics(
    allocator: std.mem.Allocator,
    file_uri: []const u8,
    root_path: []const u8,
) ![]const u8 {
    const request = try std.fmt.allocPrint(
        allocator,
        "{{\"method\":\"lsp/diagnostics\",\"file_uri\":\"{s}\",\"root_path\":\"{s}\"}}",
        .{ file_uri, root_path },
    );
    defer allocator.free(request);

    return try sendRequest(allocator, request);
}

/// Request LSP hover information
pub fn requestHover(
    allocator: std.mem.Allocator,
    file_uri: []const u8,
    root_path: []const u8,
    line: u32,
    character: u32,
) ![]const u8 {
    const request = try std.fmt.allocPrint(
        allocator,
        "{{\"method\":\"lsp/hover\",\"file_uri\":\"{s}\",\"root_path\":\"{s}\",\"line\":{},\"character\":{}}}",
        .{ file_uri, root_path, line, character },
    );
    defer allocator.free(request);

    return try sendRequest(allocator, request);
}

/// Request goto definition
pub fn requestDefinition(
    allocator: std.mem.Allocator,
    file_uri: []const u8,
    root_path: []const u8,
    line: u32,
    character: u32,
) ![]const u8 {
    const request = try std.fmt.allocPrint(
        allocator,
        "{{\"method\":\"lsp/definition\",\"file_uri\":\"{s}\",\"root_path\":\"{s}\",\"line\":{},\"character\":{}}}",
        .{ file_uri, root_path, line, character },
    );
    defer allocator.free(request);

    return try sendRequest(allocator, request);
}

/// Request find references
pub fn requestReferences(
    allocator: std.mem.Allocator,
    file_uri: []const u8,
    root_path: []const u8,
    line: u32,
    character: u32,
) ![]const u8 {
    const request = try std.fmt.allocPrint(
        allocator,
        "{{\"method\":\"lsp/references\",\"file_uri\":\"{s}\",\"root_path\":\"{s}\",\"line\":{},\"character\":{}}}",
        .{ file_uri, root_path, line, character },
    );
    defer allocator.free(request);

    return try sendRequest(allocator, request);
}
