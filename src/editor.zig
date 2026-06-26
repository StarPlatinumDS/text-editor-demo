const std = @import("std");
const terminal = @import("terminal.zig");

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

    // instead of callin writeStreamingAll multiple ties
    // append all commands to call them once
    var append_buf: std.ArrayList(u8) = .empty;
    defer append_buf.deinit(init.gpa);

    // Hide cursor
    try append_buf.appendSlice(init.gpa, "\x1b[?25l");

    // Move cursor to the top-left
    try append_buf.appendSlice(init.gpa, "\x1b[H");

    try drawRows(init.gpa, &append_buf, screen_size);

    // Move cursor back to top-left
    try append_buf.appendSlice(init.gpa, "\x1b[H");

    // show cursor again
    try append_buf.appendSlice(init.gpa, "\x1b[?25h");

    // write the complete screen update at once
    try stdout.writeStreamingAll(init.io, append_buf.items);
}

// ....
fn drawRows(allocator: std.mem.Allocator, append_buffer: *std.ArrayList(u8), screen_size: terminal.WindowSize) !void {
    var y: usize = 0;
    while (y < screen_size.rows) : (y += 1) {
        if (y == screen_size.rows / 3) {
            try drawWelcome(allocator, append_buffer, screen_size.cols);
        } else {
            try append_buffer.appendSlice(allocator, "~");
        }

        // clear the restof the line
        try append_buffer.appendSlice(allocator, "\x1b[K");

        // this is needed so that terminal doesn't scroll
        // by one line after end
        if (y + 1 < screen_size.rows) {
            try append_buffer.appendSlice(allocator, "\r\n");
        }
    }
}

fn drawWelcome(allocator: std.mem.Allocator, append_buffer: *std.ArrayList(u8), cols: usize) !void {
    const welcome = "Text editor -- version 0.0.1";

    const welcome_len = @min(welcome.len, cols);
    var padding = (cols - welcome_len) / 2;

    if (padding > 0) {
        try append_buffer.appendSlice(allocator, "~");
        padding -= 1;
    }

    while (padding > 0) : (padding -= 1) {
        try append_buffer.appendSlice(allocator, " ");
    }

    try append_buffer.appendSlice(allocator, welcome[0..welcome_len]);
}
