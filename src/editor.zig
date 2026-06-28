const std = @import("std");
const terminal = @import("terminal.zig");

// cursor's location in window
var cursor_x: usize = 0;
var cursor_y: usize = 0;

// viewport offsets
var rowoff: usize = 0;
var coloff: usize = 0;

const Row = struct {
    chars: []u8,

    fn deinit(self: Row, allocator: std.mem.Allocator) void {
        allocator.free(self.chars);
    }
};

var rows: std.ArrayList(Row) = .empty;

pub fn deinit(allocator: std.mem.Allocator) void {
    for (rows.items) |row| {
        row.deinit(allocator);
    }

    rows.deinit(allocator);
}

// return an obscure ASCII representation of Ctrl + Q if 'q' is passed
fn ctrlKey(comptime c: u8) u8 {
    return c & 0x1f;
}

// processKeypress reads a key press and switches
// depending on it, returns false on quit
pub fn processKeypress(screen_size: terminal.WindowSize) !bool {
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

        .arrow_left,
        .arrow_right,
        .arrow_up,
        .arrow_down,
        => moveCursor(key, screen_size),

        // up/down
        .page_up => {
            if (cursor_y > screen_size.rows) {
                cursor_y -= screen_size.rows;
            } else {
                cursor_y = 0;
            }
        },

        .page_down => {
            if (rows.items.len > 0) {
                cursor_y = @min(cursor_y + screen_size.rows, rows.items.len - 1);
            }
        },

        // home/end
        .home => {
            cursor_x = 0;
            cursor_y = 0;
            rowoff = 0;
            coloff = 0;
        },

        .end => {
            if (cursor_y < rows.items.len) {
                cursor_x = rows.items[cursor_y].chars.len;
            }
        },

        //delete
        .delete => {},

        // ignore regular esc for now
        .escape => {},
    }

    // means editor is runnign
    return true;
}

fn moveCursor(key: terminal.Key, screen_size: terminal.WindowSize) void {
    switch (key) {
        .arrow_left => {
            // prevent moving left after screen edge
            if (cursor_x > 0) {
                cursor_x -= 1;
            } else if (cursor_y > 0) {
                cursor_y -= 1;
                cursor_x = screen_size.cols - 1;
            }
        },

        // loop logic
        .arrow_right => {
            if (cursor_y < rows.items.len) {
                const row = rows.items[cursor_y];

                if (cursor_x + 1 < row.chars.len) {
                    cursor_x += 1;
                } else if (cursor_y + 1 < rows.items.len) {
                    cursor_y += 1;
                    cursor_x = 0;
                }
            }
        },

        .arrow_up => {
            // prevent from moving above top row
            if (cursor_y > 0) {
                cursor_y -= 1;
            }
        },

        // need limit logic
        .arrow_down => {
            if (rows.items.len > 0) {
                if (cursor_y + 1 < rows.items.len) {
                    cursor_y += 1;
                }
            }
        },

        else => {},
    }
}

// ....
pub fn refreshScreen(init: std.process.Init, screen_size: terminal.WindowSize) !void {
    const stdout = std.Io.File.stdout();

    editorScroll(screen_size);

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
    const cursor_position = try std.fmt.allocPrint(init.gpa, "\x1b[{d};{d}H", .{ cursor_y - rowoff + 1, cursor_x - coloff + 1 });
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
        const filerow = y + rowoff;
        if (filerow < rows.items.len) {
            const row = rows.items[filerow];

            if (coloff < row.chars.len) {
                const visible = row.chars[coloff..];
                const len = @min(visible.len, screen_size.cols);

                try append_buffer.appendSlice(allocator, visible[0..len]);
            }
        } else {
            // draw welcome message 1/3 down the screen
            if (rows.items.len == 0 and y == screen_size.rows / 3) {
                try drawWelcome(allocator, append_buffer, screen_size.cols);
            } else {
                // empty rows are shown with "~"
                try append_buffer.appendSlice(allocator, "~");
            }
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

pub fn openFile(init: std.process.Init, allocator: std.mem.Allocator, path: []const u8) !void {
    // for now read the. whole file into memory
    // hardcoded limit for now ~ 1GB
    const max_file_size = 1024 * 1024 * 1024;

    const contents = try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(max_file_size));
    defer allocator.free(contents);

    var start: usize = 0;

    while (std.mem.indexOfScalarPos(u8, contents, start, '\n')) |end| {
        var line = contents[start..end];

        if (line.len > 0 and line[line.len - 1] == '\r') {
            line = line[0 .. line.len - 1];
        }

        try appendRow(allocator, line);

        start = end + 1;
    }

    if (start < contents.len) {
        var line = contents[start..];

        if (line.len > 0 and line[line.len - 1] == '\r') {
            line = line[0 .. line.len - 1];
        }

        try appendRow(allocator, line);
    }
}

fn appendRow(allocator: std.mem.Allocator, line: []const u8) !void {
    const owned_chars = try allocator.dupe(u8, line);

    try rows.append(allocator, .{
        .chars = owned_chars,
    });
}

fn editorScroll(screen_size: terminal.WindowSize) void {
    if (cursor_y < rowoff) {
        rowoff = cursor_y;
    }

    if (cursor_y >= rowoff + screen_size.rows) {
        rowoff = cursor_y - screen_size.rows + 1;
    }

    if (cursor_x < coloff) {
        coloff = cursor_x;
    }

    if (cursor_x >= coloff + screen_size.rows) {
        coloff = cursor_x - screen_size.rows + 1;
    }
}
