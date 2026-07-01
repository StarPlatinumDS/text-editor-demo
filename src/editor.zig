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

// number of unsaved changes
var dirty: usize = 0;
// how many ctrl+q presses on unsaved changes
const quit_times_default: usize = 3;
var quit_times: usize = quit_times_default;

const status_message_clock: std.Io.Clock = .awake;
const status_message_timeout_seconds = 5;

var status_message: ?[]u8 = null;
var status_message_time: ?std.Io.Timestamp = null;

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

// ....
var rows: std.ArrayList(Row) = .empty;

// ....
pub fn deinit(allocator: std.mem.Allocator) void {
    for (rows.items) |row| {
        row.deinit(allocator);
    }

    rows.deinit(allocator);

    if (filename) |name| {
        allocator.free(name);
        filename = null;
    }

    if (status_message) |message| {
        allocator.free(message);
        status_message = null;
    }

    status_message_time = null;
}

// return an obscure ASCII representation of Ctrl + Q if 'q' is passed
pub fn ctrlKey(comptime c: u8) u8 {
    return c & 0x1f;
}

// callback for search
const PromptCallback = *const fn (
    query: []const u8,
    key: terminal.Key,
) anyerror!void;

// when searching and there are multiple choices
const SearchDirection = enum {
    forward,
    backward,
};

var search_last_match: ?usize = null;
var search_direction: SearchDirection = .forward;

// processKeypress reads a key press and switches
// depending on it, returns false on quit
pub fn processKeypress(
    init: std.process.Init,
    screen_size: terminal.WindowSize,
) !bool {
    const editor_size = editorAreaSize(screen_size);

    // read one character from input, it may be 'a' or 'ESC [ A'
    const key = try terminal.readKey();

    switch (key) {
        .char => |c| {
            switch (c) {
                // fires on Ctrl + Q and quits, doesn't react on siple 'q' press
                ctrlKey('q') => {
                    if (dirty > 0 and quit_times > 0) {
                        try setStatusMessage(
                            init,
                            init.gpa,
                            "Warning! File has unsaved. Press Ctrl+Q {d} more time(s) to quit.",
                            .{quit_times},
                        );

                        quit_times -= 1;
                        return true;
                    }
                    return false;
                },
                ctrlKey('s') => {
                    try saveFile(init, init.gpa);
                },
                ctrlKey('f') => {
                    try editorFind(init, init.gpa);
                },
                '\r' => {
                    try editorInsertNewline(init.gpa);
                },
                else => {
                    // rn insert only printable chars
                    if (!std.ascii.isControl(c)) {
                        try editorInsertChar(init.gpa, c);
                    }
                },
            }
        },

        .arrow_left,
        .arrow_right,
        .arrow_up,
        .arrow_down,
        => moveCursor(key),

        // up/down
        .page_up => {
            if (cursor_y > editor_size.rows) {
                cursor_y -= editor_size.rows;
            } else {
                cursor_y = 0;
            }

            snapCursorToRow();
        },

        .page_down => {
            if (rows.items.len > 0) {
                cursor_y = @min(cursor_y + editor_size.rows, rows.items.len - 1);
            }

            snapCursorToRow();
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

        // backspace
        .backspace => {
            try editorDeleteChar(init.gpa);
        },

        //delete
        .delete => {
            moveCursor(.arrow_right);
            try editorDeleteChar(init.gpa);
        },

        // ignore regular esc for now
        .escape => {},
    }

    quit_times = quit_times_default;
    // means editor is runnign
    return true;
}

fn moveCursor(key: terminal.Key) void {
    switch (key) {
        .arrow_left => {
            // prevent moving left after screen edge
            if (cursor_x > 0) {
                cursor_x -= 1;
            } else if (cursor_y > 0) {
                cursor_y -= 1;
                cursor_x = currentRowLen();
            }
        },

        // loop logic
        .arrow_right => {
            if (cursor_y < rows.items.len) {
                const row = rows.items[cursor_y];

                if (cursor_x < row.chars.len) {
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

    snapCursorToRow();
}

// ....
pub fn refreshScreen(init: std.process.Init, screen_size: terminal.WindowSize) !void {
    const stdout = std.Io.File.stdout();

    const editor_size = editorAreaSize(screen_size);
    const render_x = editorScroll(editor_size);

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
    try append_buf.appendSlice(init.gpa, "\r\n");
    try drawMessageBar(init, init.gpa, &append_buf, screen_size);

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
    init: std.process.Init,
    allocator: std.mem.Allocator,
    append_buffer: *std.ArrayList(u8),
    screen_size: terminal.WindowSize,
) !void {
    try append_buffer.appendSlice(allocator, "\x1b[K");

    if (!statusMessageIsFresh(init)) {
        return;
    }

    const message = status_message orelse return;
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

    // show filename
    try setStatusMessage(init, allocator, "Opened {s}", .{path});

    if (filename) |old_name| {
        allocator.free(old_name);
    }

    filename = owned_filename;

    // opening doesn't count as a change
    dirty = 0;
}

// ....
pub fn saveFile(init: std.process.Init, allocator: std.mem.Allocator) !void {
    if (filename == null) {
        try setStatusMessage(init, allocator, "Save failed: no filename", .{});
        return;
    }

    const contents = try editorRowsToString(allocator);
    defer allocator.free(contents);

    const file = try std.Io.Dir.cwd().createFile(init.io, filename.?, .{});
    defer file.close(init.io);

    var file_writer = file.writer(init.io, &.{});
    try file_writer.interface.writeAll(contents);

    // reset the changed/unchanged flag
    dirty = 0;

    try setStatusMessage(init, allocator, "{d} bytes written to disk", .{contents.len});
}

// .....
fn appendRow(allocator: std.mem.Allocator, line: []const u8) !void {
    try insertRow(allocator, rows.items.len, line);
}

fn insertRow(
    allocator: std.mem.Allocator,
    at: usize,
    line: []const u8,
) !void {
    if (at > rows.items.len) {
        return;
    }

    var row = Row{
        .chars = try allocator.dupe(u8, line),
        .render = @constCast(&[_]u8{}),
    };
    errdefer row.deinit(allocator);

    try updateRow(allocator, &row);

    try rows.insert(allocator, at, row);
}

// ....
fn editorRowsToString(allocator: std.mem.Allocator) ![]u8 {
    // reconstruct file contents from in-memory rows
    var total_len: usize = 0;

    for (rows.items) |row| {
        total_len += row.chars.len + 1;
    }

    // allocate buffer that'll contain the whole file
    const buffer = try allocator.alloc(u8, total_len);
    errdefer allocator.free(buffer);

    // copy each row to output followed by '\n'
    var index: usize = 0;

    for (rows.items) |row| {
        if (row.chars.len > 0) {
            @memcpy(buffer[index .. index + row.chars.len], row.chars);
            index += row.chars.len;
        }

        buffer[index] = '\n';
        index += 1;
    }

    return buffer;
}

// ....
fn editorInsertChar(allocator: std.mem.Allocator, c: u8) !void {
    // creates row if ther's none
    if (cursor_y == rows.items.len) {
        try appendRow(allocator, "");
    }

    // safety guard, cursor_y should point at valid row
    if (cursor_y >= rows.items.len) {
        return;
    }

    const row = &rows.items[cursor_y];

    const insert_at = @min(cursor_x, row.chars.len);

    const new_chars = try allocator.alloc(u8, row.chars.len + 1);
    errdefer allocator.free(new_chars);

    if (insert_at > 0) {
        @memcpy(new_chars[0..insert_at], row.chars[0..insert_at]);
    }

    new_chars[insert_at] = c;

    if (insert_at < row.chars.len) {
        @memcpy(
            new_chars[insert_at + 1 ..],
            row.chars[insert_at..],
        );
    }

    // replace the old row text
    if (row.chars.len > 0) {
        allocator.free(row.chars);
    }

    row.chars = new_chars;

    try updateRow(allocator, row);

    // mark changed/unchanged
    dirty += 1;

    cursor_x = insert_at + 1;
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

    var modified_marker: []const u8 = "";

    if (dirty > 0) {
        modified_marker = " (modified)";
    }

    const status = try std.fmt.allocPrint(
        allocator,
        "{s} - {d} lines{s}",
        .{ short_name, rows.items.len, modified_marker },
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

// ....
fn nowStatusTime(init: std.process.Init) std.Io.Timestamp {
    return std.Io.Clock.now(status_message_clock, init.io);
}

// ....
pub fn setStatusMessage(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const new_message = try std.fmt.allocPrint(allocator, fmt, args);
    errdefer allocator.free(new_message);

    if (status_message) |old_message| {
        allocator.free(old_message);
    }

    status_message = new_message;
    status_message_time = nowStatusTime(init);
}

// ....
fn statusMessageIsFresh(init: std.process.Init) bool {
    if (status_message == null) {
        return false;
    }

    const message_time = status_message_time orelse return true;
    const now = nowStatusTime(init);

    const age = message_time.durationTo(now);

    return age.toSeconds() < status_message_timeout_seconds;
}

// ....
fn currentRowLen() usize {
    if (cursor_y < rows.items.len) {
        return rows.items[cursor_y].chars.len;
    }

    return 0;
}

// ....
fn snapCursorToRow() void {
    cursor_x = @min(cursor_x, currentRowLen());
}

fn rowDelChar(
    allocator: std.mem.Allocator,
    row: *Row,
    at: usize,
) !void {
    if (at >= row.chars.len) {
        return;
    }

    const new_len = row.chars.len - 1;
    var new_chars: []u8 = @constCast(&[_]u8{});

    if (new_len > 0) {
        new_chars = try allocator.alloc(u8, new_len);
        errdefer allocator.free(new_chars);

        if (at > 0) {
            @memcpy(new_chars[0..at], row.chars[0..at]);
        }

        if (at + 1 < row.chars.len) {
            @memcpy(new_chars[at..], row.chars[at + 1 ..]);
        }
    }

    if (row.chars.len > 0) {
        allocator.free(row.chars);
    }

    row.chars = new_chars;

    try updateRow(allocator, row);
}

fn rowAppendString(
    allocator: std.mem.Allocator,
    row: *Row,
    text: []const u8,
) !void {
    if (text.len == 0) {
        return;
    }

    const old_len = row.chars.len;
    const new_chars = try allocator.alloc(u8, old_len + text.len);
    errdefer allocator.free(new_chars);

    if (old_len > 0) {
        @memcpy(new_chars[0..old_len], row.chars);
    }

    @memcpy(new_chars[old_len..], text);

    if (row.chars.len > 0) {
        allocator.free(row.chars);
    }

    row.chars = new_chars;

    try updateRow(allocator, row);
}

// ....
fn editorDeleteChar(allocator: std.mem.Allocator) !void {
    // if nothing  to del
    if (cursor_y >= rows.items.len) {
        return;
    }

    if (cursor_x == 0 and cursor_y == 0) {
        return;
    }

    if (cursor_x > 0) {
        //del the char before the cursor
        const row = &rows.items[cursor_y];

        try rowDelChar(allocator, row, cursor_x - 1);

        cursor_x -= 1;
    } else {
        // at the beggining of a row, backspace joins it to prev
        const previous_row_len = rows.items[cursor_y - 1].chars.len;

        const current_row = rows.items[cursor_y];

        try rowAppendString(
            allocator,
            &rows.items[cursor_y - 1],
            current_row.chars,
        );

        const removed_row = rows.orderedRemove(cursor_y);
        removed_row.deinit(allocator);

        cursor_y -= 1;
        cursor_x = previous_row_len;
    }

    dirty += 1;
}

// ....
fn editorInsertNewline(allocator: std.mem.Allocator) !void {
    if (cursor_y >= rows.items.len) {
        try appendRow(allocator, "");

        cursor_y = rows.items.len - 1;
        cursor_x = 0;
        dirty += 1;

        return;
    }

    if (cursor_x == 0) {
        try insertRow(allocator, cursor_y, "");
    } else {
        const old_chars = rows.items[cursor_y].chars;

        const split_at = @min(cursor_x, old_chars.len);

        const left = old_chars[0..split_at];
        const right = old_chars[split_at..];

        var left_row = Row{
            .chars = try allocator.dupe(u8, left),
            .render = @constCast(&[_]u8{}),
        };
        errdefer left_row.deinit(allocator);

        try updateRow(allocator, &left_row);

        var right_row = Row{
            .chars = try allocator.dupe(u8, right),
            .render = @constCast(&[_]u8{}),
        };
        errdefer right_row.deinit(allocator);

        try updateRow(allocator, &right_row);

        try rows.insert(allocator, cursor_y + 1, right_row);

        const row = &rows.items[cursor_y];
        row.deinit(allocator);
        row.* = left_row;
    }

    cursor_y += 1;
    cursor_x = 0;
    dirty += 1;
}

// ....
fn editorPrompt(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    prompt: []const u8,
    callback: ?PromptCallback,
) !?[]u8 {
    var buffer: std.ArrayList(u8) = .empty;
    errdefer buffer.deinit(allocator);

    while (true) {
        try setStatusMessage(
            init,
            allocator,
            "{s} : {s}",
            .{ prompt, buffer.items },
        );

        const screen_size = try terminal.getWindowSize();
        try refreshScreen(init, screen_size);

        const key = try terminal.readKey();

        switch (key) {
            .char => |c| {
                switch (c) {
                    '\r' => {
                        if (buffer.items.len == 0) {
                            continue;
                        }
                        if (callback) |cb| {
                            try cb(buffer.items, key);
                        }

                        try setStatusMessage(init, allocator, "", .{});

                        return try buffer.toOwnedSlice(allocator);
                    },

                    else => {
                        if (!std.ascii.isControl(c)) {
                            try buffer.append(allocator, c);
                        }
                    },
                }
            },

            .backspace => {
                if (buffer.items.len > 0) {
                    _ = buffer.pop();
                }
            },

            .escape => {
                if (callback) |cb| {
                    try cb(buffer.items, key);
                }

                try setStatusMessage(init, allocator, "", .{});
                buffer.deinit(allocator);
                return null;
            },

            else => {},
        }

        if (callback) |cb| {
            try cb(buffer.items, key);
        }
    }
}

// ....
fn editorFindCallback(
    query: []const u8,
    key: terminal.Key,
) !void {
    if (query.len == 0) {
        search_last_match = null;
        search_direction = .forward;
        return;
    }

    switch (key) {
        .char => |c| {
            if (c == '\r') {
                search_last_match = null;
                search_direction = .forward;
                return;
            }

            search_last_match = null;
            search_direction = .forward;
        },

        .escape => {
            search_last_match = null;
            search_direction = .forward;
            return;
        },

        .arrow_right,
        .arrow_down,
        => {
            search_direction = .forward;
        },

        .arrow_left,
        .arrow_up,
        => {
            search_direction = .backward;
        },

        .backspace => {
            search_last_match = null;
            search_direction = .forward;
        },

        else => {
            search_last_match = null;
            search_direction = .forward;
        },
    }

    if (rows.items.len == 0) {
        return;
    }

    var current: usize = undefined;

    if (search_last_match) |last_match| {
        current = last_match;
    } else {
        current = switch (search_direction) {
            .forward => rows.items.len - 1,
            .backward => 0,
        };
    }

    var searched: usize = 0;

    while (searched < rows.items.len) : (searched += 1) {
        switch (search_direction) {
            .forward => {
                if (current + 1 >= rows.items.len) {
                    current = 0;
                } else {
                    current += 1;
                }
            },

            .backward => {
                if (current == 0) {
                    current = rows.items.len - 1;
                } else {
                    current -= 1;
                }
            },
        }

        const row = rows.items[current];

        if (std.mem.indexOf(u8, row.render, query)) |match_index| {
            search_last_match = current;

            cursor_y = current;
            cursor_x = rowRxToCx(row, match_index);

            rowoff = rows.items.len;
            coloff = 0;

            break;
        }
    }
}

// ....
fn editorFind(
    init: std.process.Init,
    allocator: std.mem.Allocator,
) !void {
    const saved_cursor_x = cursor_x;
    const saved_cursor_y = cursor_y;
    const saved_rowoff = rowoff;
    const saved_coloff = coloff;

    search_last_match = null;
    search_direction = .forward;

    const query = try editorPrompt(
        init,
        allocator,
        "Search, use ESC/Arrows/Enter",
        editorFindCallback,
    );

    if (query) |owned_query| {
        allocator.free(owned_query);
    } else {
        cursor_x = saved_cursor_x;
        cursor_y = saved_cursor_y;
        rowoff = saved_rowoff;
        coloff = saved_coloff;
    }

    search_last_match = null;
    search_direction = .forward;
}

// ....
fn rowRxToCx(row: Row, rx: usize) usize {
    var current_rx: usize = 0;
    var cx: usize = 0;

    while (cx < row.chars.len) : (cx += 1) {
        if (row.chars[cx] == '\t') {
            current_rx += (tab_stop - 1) - (current_rx % tab_stop);
        }

        current_rx += 1;

        if (current_rx > rx) {
            return cx;
        }
    }

    return cx;
}
