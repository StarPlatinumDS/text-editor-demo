const std = @import("std");
const terminal = @import("terminal.zig");
const editor = @import("editor.zig");

pub fn main(init: std.process.Init) !void {
    const stdout = std.Io.File.stdout();
    // enable raw mode
    const raw = try terminal.RawMode.enable(terminal.stdin_fd);
    // restore terminal before main exits
    defer raw.restore();

    defer editor.deinit(init.gpa);

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len >= 2) {
        try editor.openFile(init, init.gpa, args[1]);
    }

    try stdout.writeStreamingAll(init.io, "\x1b[?1049h");
    defer stdout.writeStreamingAll(init.io, "\x1b[?25h\x1b[?1049l") catch {};

    while (true) {
        const screen_size = try terminal.getWindowSize();

        try editor.refreshScreen(init, screen_size);

        const keep_running = try editor.processKeypress(screen_size);

        if (!keep_running) break;
    }
}
