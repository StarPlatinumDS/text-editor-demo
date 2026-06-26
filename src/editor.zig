const std = @import("std");
const terminal = @import("terminal.zig");
const posix = std.posix;

fn ctrlKey(comptime c: u8) u8 {
    return c & 0x1f;
}

// Returns false on quit
pub fn processKeypress() !bool {
    const c = try terminal.readKey();

    switch (c) {
        ctrlKey('q') => return false,
        else => {},
    }

    // temporary part
    if (std.ascii.isControl(c)) {
        std.debug.print("{d}\r\n", .{c});
    } else {
        std.debug.print("{d} ('{c}')\r\n", .{ c, c });
    }

    return true;
}

pub fn refreshScreen() !void {
    try posix.writeAll(terminal.stdout_fd, "\x1b[2J");
    try terminal.writeAll(terminal.stdout_fd, "\x1b[H");
}
