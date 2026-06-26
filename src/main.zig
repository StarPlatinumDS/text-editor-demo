const std = @import("std");
// add posix def
const posix = std.posix;

const terminal = @import("terminal.zig");

pub fn main() !void {
    // enable raw mode
    const raw = try terminal.RawMode.enable(terminal.stdin_fd);
    // restore terminal before main exits
    defer raw.restore();

    // read up to 1 byte from stdin into buf.
    while (true) {
        const c = try terminal.readKey();

        if (c == ctrlKey('q')) break;

        // display numeric value and display the char if printable
        if (std.ascii.isControl(c)) {
            std.debug.print("{d}\r\n", .{c});
        } else {
            std.debug.print("{d} ('{c}')\r\n", .{ c, c });
        }
    }
}

fn ctrlKey(comptime c: u8) u8 {
    return c & 0x1f;
}
