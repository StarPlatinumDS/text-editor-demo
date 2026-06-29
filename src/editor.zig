const std = @import("std");
const terminal = @import("terminal.zig");

// cursor's location in window
var cursor_x: usize = 0;
var cursor_y: usize = 0;

// viewport offsets
var rowoff: usize = 0;
var coloff: usize = 0;

// tabs
const tab_stop: usize = 8;

// filename state
var filename: ?[]u8 = null;

const Row = struct {
    // file text, will be editable later on
    chars: []u8,

    // text as it should appear on screen, expand tabs into spaces
    render: []u8,

    fn deinit(self: Row, allocator: std.mem.Allocator) void {
        if (self.chars.len > 0) {
            allocator.free(self.chars);
        }

        if (self.render.len > 0) {
            allocator.free(self.render);
        }
    }
};

var rows: std.ArrayList(Row) = .empty;

pub fn deinit(allocator: std.mem.Allocator) void {
    for (rows.items) |row| {
        row.deinit(allocator);
    }

    rows.deinit(allocator);

    if (filename) |name| {
        allocator.free(name);
        filename = null;
    }
}

// return an obscure ASCII representation of Ctrl + Q if 'q' is passed
fn ctrlKey(comptime c: u8) u8 {
    return c & 0x1f;
}

// processKeypress reads a key press and switches
// depending on it, returns false on quit
pub fn processKeypress(screen_size: terminal.WindowSize) !bool {
    const editor_size = editorAreaSize(screen_size);

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
        => moveCursor(key, editor_size),

        // up/down
        .page_up => {
            if (cursor_y > editor_size.rows) {
                cursor_y -= editor_size.rows;
            } else {
                cursor_y = 0;
            }
        },

        .page_down => {
            if (rows.items.len > 0) {
                cursor_y = @min(cursor_y + editor_size.rows, rows.items.len - 1);
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

    const editor_size = editorAreaSize(screen_size);
    const render_x = editorScroll(screen_size);

    // instead of callin writeStreamingAll multiple ties
    // append all commands to call them once
    var append_buf: std.ArrayList(u8) = .empty;
    defer append_buf.deinit(init.gpa);

    // Hide cursor
    try append_buf.appendSlice(init.gpa, "\x1b[?25l");

    // Move cursor to the editor cursor pos
    try append_buf.appendSlice(init.gpa, "\x1b[H");

    // draw all visible rows into append buffer
    try drawRows(init.gpa, &append_buf, editor_size);

    // status + message bar
    try drawStatusBar(init.gpa, &append_buf, screen_size);
    try drawMessageBar(init.gpa, &append_buf, screen_size);

    // move cursor to the editor cursor position
    const cursor_position = try std.fmt.allocPrint(init.gpa, "\x1b[{d};{d}H", .{ cursor_y - rowoff + 1, render_x - coloff + 1 });
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

            if (coloff < row.render.len) {
                const visible = row.render[coloff..];
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
        try append_buffer.appendSlice(allocator, "\r\n");
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

// ....
fn drawMessageBar(
    allocator: std.mem.Allocator,
    append_buffer: *std.ArrayList(u8),
    screen_size: terminal.WindowSize,
) !void {
    try append_buffer.appendSlice(allocator, "\r\n");
    try append_buffer.appendSlice(allocator, "\x1b[K");

    const message = "HELP: Ctrl+Q = quit";

    const leng = @min(message.len, screen_size.cols);
    try append_buffer.appendSlice(allocator, message[0..leng]);
}

pub fn openFile(init: std.process.Init, allocator: std.mem.Allocator, path: []const u8) !void {
    const owned_filename = try allocator.dupe(u8, path);
    errdefer allocator.free(owned_filename);
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

    if (filename) |old_name| {
        allocator.free(old_name);
    }

    filename = owned_filename;
}

// .....
fn appendRow(allocator: std.mem.Allocator, line: []const u8) !void {
    var row = Row{
        .chars = try allocator.dupe(u8, line),

        //placeholder for now
        .render = @constCast(&[_]u8{}),
    };

    errdefer row.deinit(allocator);

    try updateRow(allocator, &row);

    try rows.append(allocator, row);
}

// ....
fn updateRow(allocator: std.mem.Allocator, row: *Row) !void {
    // builds the rendered version of the row
    var render_buf: std.ArrayList(u8) = .empty;
    defer render_buf.deinit(allocator);

    var render_col: usize = 0;

    for (row.chars) |c| {
        if (c == '\t') {
            // try to add at least one space
            try render_buf.append(allocator, ' ');
            render_col += 1;

            // keep adding until render meets tab stop
            while (render_col % tab_stop != 0) {
                try render_buf.append(allocator, ' ');
                render_col += 1;
            }
        } else {
            try render_buf.append(allocator, c);
            render_col += 1;
        }
    }

    const new_render = try allocator.dupe(u8, render_buf.items);

    if (row.render.len > 0) {
        allocator.free(row.render);
    }

    row.render = new_render;
}

// ....
fn editorScroll(screen_size: terminal.WindowSize) usize {
    var render_x = cursor_x;

    if (cursor_y < rows.items.len) {
        render_x = rowCxToRx(rows.items[cursor_y], cursor_x);
    }

    if (cursor_y < rowoff) {
        rowoff = cursor_y;
    }

    if (cursor_y >= rowoff + screen_size.rows) {
        rowoff = cursor_y - screen_size.rows + 1;
    }

    if (render_x < coloff) {
        coloff = render_x;
    }

    if (render_x >= coloff + screen_size.cols) {
        coloff = render_x - screen_size.cols + 1;
    }

    return render_x;
}

// helper for conversion of cursor_x to render
fn rowCxToRx(row: Row, cx: usize) usize {
    var rx: usize = 0;

    const limit = @min(cx, row.chars.len);

    var i: usize = 0;
    while (i < limit) : (i += 1) {
        if (row.chars[i] == '\t') {
            //move rx forward to before tab stop - 1
            rx += (tab_stop - 1) - (rx % tab_stop);
        }

        rx += 1;
    }

    return rx;
}

// reserver for status bar
fn editorAreaSize(screen_size: terminal.WindowSize) terminal.WindowSize {
    // ned 2 rows for status bar and for messages
    const reserved_rows: usize = if (screen_size.rows > 2) 2 else 0;

    return .{
        .rows = screen_size.rows - reserved_rows,
        .cols = screen_size.cols,
    };
}

// ....
fn drawStatusBar(
    allocator: std.mem.Allocator,
    append_buffer: *std.ArrayList(u8),
    screen_size: terminal.WindowSize,
) !void {

    // same as
    // var name: []const u8 = undefined;
    // if (filename) |stored_filename| {
    //     name = stored_filename;
    // } else {
    //     name = "[No Name]";
    // }
    const name: []const u8 = if (filename) |f| f else "[No Name]";
    const short_name = name[0..@min(name.len, 20)];

    const status = try std.fmt.allocPrint(
        allocator,
        "{s} - {d} lines",
        .{ short_name, rows.items.len },
    );
    defer allocator.free(status);

    //same as
    // var current_line: usize = 0;
    // if (rows.items.len > 0) {
    //     const one_based_cursor_y = cursor_y + 1;
    //     current_line = @min(one_based_cursor_y, rows.items.len);
    // }
    const current_line: usize = if (rows.items.len == 0)
        0
    else
        @min(cursor_y + 1, rows.items.len);

    const right_status = try std.fmt.allocPrint(
        allocator,
        "{d}/{d}",
        .{ current_line, rows.items.len },
    );
    defer allocator.free(right_status);

    //invert colors
    try append_buffer.appendSlice(allocator, "\x1b[7m");

    var leng: usize = @min(status.len, screen_size.cols);
    try append_buffer.appendSlice(allocator, status[0..leng]);

    while (leng < screen_size.cols) {
        const remaining = screen_size.cols - leng;

        if (right_status.len <= remaining and remaining == right_status.len) {
            try append_buffer.appendSlice(allocator, right_status);
            leng += right_status.len;
            break;
        } else {
            try append_buffer.append(allocator, ' ');
            leng += 1;
        }
    }

    try append_buffer.appendSlice(allocator, "\x1b[m");
}
