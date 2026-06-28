const std = @import("std");
const terminal = @import("terminal.zig");
const editor = @import("editor.zig");

pub fn main(init: std.process.Init) !void {
    // enable raw mode
    const raw = try terminal.RawMode.enable(terminal.stdin_fd);
    // restore terminal before main exits
    defer raw.restore();

    try std.Io.File.stdout().writeStreamingAll(init.io, "\x1b[?1049h");

    while (true) {
        try editor.refreshScreen(init);

        const keep_running = try editor.processKeypress();

        if (!keep_running) break;
    }
}
