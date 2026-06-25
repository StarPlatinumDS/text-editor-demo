const std = @import("std");
// add posix def
const posix = std.posix;

const terminal = @import("terminal.zig");

pub fn main() !void {
    // enable raw mode
    const raw = try terminal.RawMode.enable(terminal.stdin_fd);
    // restore terminal before main exits
    defer raw.restore();

    // a buffer to hold keypress
    var buf: [1]u8 = undefined;

    // read up to 1 byte from stdin into buf.
    while (true) {
        // number of bytes actually read
        const n = try posix.read(terminal.stdin_fd, buf[0..]);

        // n == 0 means EOF, no more input
        if (n == 0) break;

        const c = buf[0];

        if (c == 'q') break;

        // display numeric value and display the char if printable
        if (std.ascii.isControl(c)) {
            std.debug.print("{d}\r\n", .{c});
        } else {
            std.debug.print("{d} ('{c}')\r\n", .{ c, c });
        }
    }
}
