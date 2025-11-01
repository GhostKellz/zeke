const std = @import("std");

/// Terminal state management for raw mode input
pub const TerminalState = struct {
    orig_termios: std.posix.termios,
    stdin: std.posix.fd_t,
    stdout: std.posix.fd_t,

    /// Initialize terminal in raw mode
    pub fn init() !TerminalState {
        const stdin = std.posix.STDIN_FILENO;
        const stdout = std.posix.STDOUT_FILENO;

        // Save original terminal state
        const orig_termios = try std.posix.tcgetattr(stdin);

        // Configure raw mode
        var raw = orig_termios;
        raw.lflag.ECHO = false; // Don't echo characters
        raw.lflag.ICANON = false; // No line buffering
        raw.lflag.ISIG = false; // Don't generate signals (Ctrl+C, Ctrl+Z)
        raw.lflag.IEXTEN = false; // Disable extended input processing
        raw.iflag.IXON = false; // Disable flow control (Ctrl+S, Ctrl+Q)
        raw.iflag.ICRNL = false; // Don't translate CR to NL
        raw.iflag.BRKINT = false; // Don't send SIGINT on break
        raw.iflag.INPCK = false; // Disable parity checking
        raw.iflag.ISTRIP = false; // Don't strip 8th bit
        raw.oflag.OPOST = false; // Disable output processing
        raw.cflag.CSIZE = .CS8; // 8-bit characters

        // Set read timeout: return after 100ms or 1 byte
        raw.cc[@intFromEnum(std.posix.V.TIME)] = 1; // 100ms timeout
        raw.cc[@intFromEnum(std.posix.V.MIN)] = 0; // Return with any input

        try std.posix.tcsetattr(stdin, .FLUSH, raw);

        // Hide cursor
        _ = try std.posix.write(stdout, "\x1b[?25l");

        return .{
            .orig_termios = orig_termios,
            .stdin = stdin,
            .stdout = stdout,
        };
    }

    /// Restore terminal to original state
    pub fn deinit(self: *TerminalState) void {
        std.posix.tcsetattr(self.stdin, .FLUSH, self.orig_termios) catch {};
        _ = std.posix.write(self.stdout, "\x1b[?25h") catch {}; // Show cursor
        _ = std.posix.write(self.stdout, "\x1b[0m\n") catch {}; // Reset colors
    }
};

/// Keyboard events
pub const KeyEvent = union(enum) {
    char: u8,
    enter,
    backspace,
    delete,
    tab,
    escape,
    arrow_up,
    arrow_down,
    arrow_left,
    arrow_right,
    page_up,
    page_down,
    home,
    end_key,
    ctrl_c,
    ctrl_d,
    ctrl_l, // Clear screen
    ctrl_u, // Clear line
    unknown: []const u8,

    /// Parse raw bytes into a KeyEvent
    pub fn parse(bytes: []const u8) KeyEvent {
        if (bytes.len == 0) return .{ .unknown = bytes };

        // Single byte keys
        if (bytes.len == 1) {
            return switch (bytes[0]) {
                '\r', '\n' => .enter,
                '\t' => .tab,
                0x7F, 0x08 => .backspace, // DEL or BS
                0x03 => .ctrl_c,
                0x04 => .ctrl_d,
                0x0C => .ctrl_l,
                0x15 => .ctrl_u,
                0x1B => .escape,
                32...126 => .{ .char = bytes[0] },
                else => .{ .unknown = bytes },
            };
        }

        // Escape sequences (2+ bytes starting with ESC)
        if (bytes[0] == 0x1B) {
            // Alt+key (ESC followed by printable char)
            if (bytes.len == 2 and bytes[1] >= 32 and bytes[1] <= 126) {
                return .{ .unknown = bytes };
            }

            // CSI sequences (ESC [)
            if (bytes.len >= 3 and bytes[1] == '[') {
                return switch (bytes[2]) {
                    'A' => .arrow_up,
                    'B' => .arrow_down,
                    'C' => .arrow_right,
                    'D' => .arrow_left,
                    'H' => .home,
                    'F' => .end_key,
                    '1' => if (bytes.len >= 4 and bytes[3] == '~') .home else .{ .unknown = bytes },
                    '3' => if (bytes.len >= 4 and bytes[3] == '~') .delete else .{ .unknown = bytes },
                    '4' => if (bytes.len >= 4 and bytes[3] == '~') .end_key else .{ .unknown = bytes },
                    '5' => if (bytes.len >= 4 and bytes[3] == '~') .page_up else .{ .unknown = bytes },
                    '6' => if (bytes.len >= 4 and bytes[3] == '~') .page_down else .{ .unknown = bytes },
                    else => .{ .unknown = bytes },
                };
            }

            // SS3 sequences (ESC O) - alternate arrow keys
            if (bytes.len >= 3 and bytes[1] == 'O') {
                return switch (bytes[2]) {
                    'A' => .arrow_up,
                    'B' => .arrow_down,
                    'C' => .arrow_right,
                    'D' => .arrow_left,
                    'H' => .home,
                    'F' => .end_key,
                    else => .{ .unknown = bytes },
                };
            }
        }

        return .{ .unknown = bytes };
    }
};

test "KeyEvent parse single char" {
    const key = KeyEvent.parse("a");
    try std.testing.expectEqual(KeyEvent{ .char = 'a' }, key);
}

test "KeyEvent parse enter" {
    const key1 = KeyEvent.parse("\r");
    const key2 = KeyEvent.parse("\n");
    try std.testing.expectEqual(KeyEvent.enter, key1);
    try std.testing.expectEqual(KeyEvent.enter, key2);
}

test "KeyEvent parse arrow up" {
    const key = KeyEvent.parse("\x1b[A");
    try std.testing.expectEqual(KeyEvent.arrow_up, key);
}

test "KeyEvent parse ctrl+c" {
    const key = KeyEvent.parse("\x03");
    try std.testing.expectEqual(KeyEvent.ctrl_c, key);
}
