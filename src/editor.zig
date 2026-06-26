const std = @import("std");
const terminal = @import("terminal.zig");
const posix = std.posix;

// ....
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

    return true;
}

// ....
pub fn refreshScreen(init: std.process.Init) !void {
    const stdout = std.Io.File.stdout();
    const screen_size = try terminal.getWindowSize();

    // Hide cursor while redrawing the screen.
    try stdout.writeStreamingAll(init.io, "\x1b[?25l");

    // Move cursor to the top-left
    try stdout.writeStreamingAll(init.io, "\x1b[H");

    try drawRows(init, screen_size.rows);

    // Move cursor back to top-left
    try stdout.writeStreamingAll(init.io, "\x1b[H");

    // Show cursor again after refresh.
    try stdout.writeStreamingAll(init.io, "\x1b[?25l");
}

// ....
fn drawRows(init: std.process.Init, rows: usize) !void {
    const stdout = std.Io.File.stdout();

    var y: usize = 0;
    while (y < rows) : (y += 1) {
        try stdout.writeStreamingAll(init.io, "~");

        // clear the restof the line
        try stdout.writeStreamingAll(init.io, "\x1b[K");

        // this is needed so that terminal doesn't scroll
        // by one line after end
        if (y < rows - 1) {
            try stdout.writeStreamingAll(init.io, "\r\n");
        }
    }
}
