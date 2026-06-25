const std = @import("std");
// add posix def
const posix = std.posix;

const terminal = @import("terminal.zig");

pub fn main() !void {
    // probably a buffer to hold keypress
    var buf: [1]u8 = undefined;

    while (true) {
        const n = try posix.read(terminal.stdin_fd, buf[0..]);

        if (n == 0) break;
        if (buf[0] == 'q') break;
    }
}
