const std = @import("std");
const terminal = @import("terminal.zig");

// cursor's location in window
var cursor_x: usize = 0;
var cursor_y: usize = 0;

// return an obscure ASCII representation of Ctrl + Q if 'q' is passed
fn ctrlKey(comptime c: u8) u8 {
    return c & 0x1f;
}

// processKeypress reads a key press and switches
// depending on it, returns false on quit
pub fn processKeypress() !bool {
    // read one character from input, it may be 'a' or 'ESC [ A'
    const key = try terminal.readKey();

    switch (key) {
        .char => |c| {
            switch (c) {
                // fires on Ctrl + Q and quits, doesn't react on siple 'q' press
                ctrlKey('q') => return false,
                else => {},
            }
        },

        .arrow_left => {
            // prevent moving left after screen edge
            if (cursor_x > 0) {
                cursor_x -= 1;
            }
        },

        // needs loop logic
        .arrow_right => {
            cursor_x += 1;
        },

        .arrow_up => {
            // prevent from moving above top row
            if (cursor_y > 0) {
                cursor_y -= 1;
            }
        },

        // need limit logic
        .arrow_down => {
            cursor_y += 1;
        },

        // ignore regular esc for now
        .escape => {},
    }

    // means editor is runnign
    return true;
}

// ....
pub fn refreshScreen(init: std.process.Init) !void {
    const stdout = std.Io.File.stdout();

    // get terminal size every refresh
    const screen_size = try terminal.getWindowSize();

    // keep cursor_x inside the screen
    if (cursor_x >= screen_size.cols) {
        cursor_x = screen_size.cols - 1;
    }

    // keep cursor_y inside the screen
    if (cursor_y >= screen_size.rows) {
        cursor_y = screen_size.rows - 1;
    }

    // instead of callin writeStreamingAll multiple ties
    // append all commands to call them once
    var append_buf: std.ArrayList(u8) = .empty;
    defer append_buf.deinit(init.gpa);

    // Hide cursor
    try append_buf.appendSlice(init.gpa, "\x1b[?25l");

    // Move cursor to the editor cursor pos
    try append_buf.appendSlice(init.gpa, "\x1b[H");

    // draw all visible rows into append buffer
    try drawRows(init.gpa, &append_buf, screen_size);

    // move cursor to the editor cursor position
    const cursor_position = try std.fmt.allocPrint(init.gpa, "\x1b[{d};{d}H", .{ cursor_y + 1, cursor_x + 1 });
    defer init.gpa.free(cursor_position);

    // Move cursor to the editor cursor pos
    try append_buf.appendSlice(init.gpa, cursor_position);

    // show cursor again
    try append_buf.appendSlice(init.gpa, "\x1b[?25h");

    // write the complete screen update at once
    try stdout.writeStreamingAll(init.io, append_buf.items);
}

// ....
fn drawRows(allocator: std.mem.Allocator, append_buffer: *std.ArrayList(u8), screen_size: terminal.WindowSize) !void {
    var y: usize = 0;
    while (y < screen_size.rows) : (y += 1) {
        // draw welcome message 1/3 down the screen
        if (y == screen_size.rows / 3) {
            try drawWelcome(allocator, append_buffer, screen_size.cols);
        } else {
            // empty rows are shown with "~"
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

// drawWelcome draws either full or truncated message approx in the center of screen
fn drawWelcome(allocator: std.mem.Allocator, append_buffer: *std.ArrayList(u8), cols: usize) !void {
    const welcome = "Text editor -- version 0.0.1";

    // do not draw chars that do not fit in width
    const welcome_len = @min(welcome.len, cols);
    // number of spaces to approx center message
    var padding = (cols - welcome_len) / 2;

    // keep "~" on message row
    if (padding > 0) {
        try append_buffer.appendSlice(allocator, "~");
        padding -= 1;
    }

    // add spces until text is centered
    while (padding > 0) : (padding -= 1) {
        try append_buffer.appendSlice(allocator, " ");
    }

    // draw full or truncated version
    try append_buffer.appendSlice(allocator, welcome[0..welcome_len]);
}
