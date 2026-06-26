const terminal = @import("terminal.zig");
const editor = @import("editor.zig");

pub fn main() !void {
    // enable raw mode
    const raw = try terminal.RawMode.enable(terminal.stdin_fd);
    // restore terminal before main exits
    defer raw.restore();

    while (true) {
        const keep_running = try editor.processKeypress();

        if (!keep_running) break;
    }
}
