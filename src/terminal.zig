const std = @import("std");
const posix = std.posix;

// Unix/POSIX convention:
//   0 = stdin
//   1 = stdout
//   2 = stderr
// system's API
pub const stdin_fd: posix.fd_t = 0;
pub const stdout_fd: posix.fd_t = 1;

// A keypress is not always just one byte.
// examples: 'a', 'q', '\r', 'ESC [ A' -> three bytes
// to address that I return Key union instead of u8
pub const Key = union(enum) {
    // normal keypress
    char: u8,
    // simply ESC or an unrecognized input
    escape,

    // arrow key sequences
    arrow_left,
    arrow_right,
    arrow_up,
    arrow_down,

    // special row keys
    page_up,
    page_down,
    home,
    end,
    delete,
};

// WindowSize is a wrapper around terminal's window size
pub const WindowSize = struct {
    rows: usize,
    cols: usize,
};

// ....
pub fn getWindowSize() !WindowSize {
    // posix.winsize is the OS-level struct filled by ioctl()
    var ws: posix.winsize = .{
        .row = 0,
        .col = 0,
        .xpixel = 0,
        .ypixel = 0,
    };

    // get window size
    const result = posix.system.ioctl(
        stdout_fd,
        posix.T.IOCGWINSZ,
        // send an adress of ws to ioctl
        @intFromPtr(&ws),
    );

    // ioctl reports success/failure through an errno-style result
    // Also reject row/col == 0 because a zero-sized terminal would make later
    // cursor math invalid
    if (posix.errno(result) != .SUCCESS or ws.row == 0 or ws.col == 0) {
        return error.WindowSizeUnavailable;
    }

    // Convert from the OS integer type to usize because the editor uses usize
    // for indexes and loop counters
    return .{
        .rows = @intCast(ws.row),
        .cols = @intCast(ws.col),
    };
}

// RawMode owns the terminal state change
pub const RawMode = struct {
    fd: posix.fd_t,
    original: posix.termios,

    pub fn enable(fd: posix.fd_t) !RawMode {
        const original = try posix.tcgetattr(fd);
        var raw = original;

        // turn off echo, icanon, ISIG, IEXTEN
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.ISIG = false;
        raw.lflag.IEXTEN = false;

        // disable Ctrl-S / Ctrl-Q
        raw.iflag.IXON = false;
        // disable '\r' to '\n'
        raw.iflag.ICRNL = false;
        // disable break condition
        raw.iflag.BRKINT = false;
        // disable parity checking
        raw.iflag.INPCK = false;
        // disable stripping 8th bit from each input byte
        raw.iflag.ISTRIP = false;
        // use 8-bit characters
        raw.cflag.CSIZE = .CS8;
        // disable output post-processing
        raw.oflag.OPOST = false;

        raw.cc[@intFromEnum(posix.V.MIN)] = 0;
        raw.cc[@intFromEnum(posix.V.TIME)] = 1;

        // Apply the modified terminal settings.
        try posix.tcsetattr(fd, posix.TCSA.FLUSH, raw);

        return .{
            .fd = fd,
            .original = original,
        };
    }

    // Restore the terminal settings we saved before entering raw mode.
    pub fn restore(self: RawMode) void {
        posix.tcsetattr(self.fd, posix.TCSA.FLUSH, self.original) catch {};
    }
};

// ....
pub fn readKey() !Key {
    var buf: [1]u8 = undefined;

    while (true) {
        // Read one byte from stdin

        // In raw mode keypress is read instantly, no wait for Enter
        const n = try posix.read(stdin_fd, buf[0..]);

        // timeout allowed
        if (n == 0) continue;

        // char from input
        const c = buf[0];

        // arrows and other special chars begin w/ esc
        if (c == 0x1b) {
            var seq: [3]u8 = undefined;

            // try to acntch esc + char

            //if no char after esc  standalone esc
            const n1 = try posix.read(stdin_fd, seq[0..1]);
            if (n1 == 0) return .escape;

            // if I can read third byte (which is most likely an arrow)
            const n2 = try posix.read(stdin_fd, seq[1..2]);
            if (n2 == 0) return .escape;

            // CSI sequence for arrow keys
            if (seq[0] == '[') {
                if (seq[1] >= '0' and seq[1] <= '9') {
                    const n3 = try posix.read(stdin_fd, seq[2..3]);
                    if (n3 == 0) return .escape;

                    if (seq[2] == '~') {
                        switch (seq[1]) {
                            '1' => return .home,
                            '3' => return .delete,
                            '4' => return .end,
                            '5' => return .page_up,
                            '6' => return .page_down,
                            '7' => return .home,
                            '8' => return .end,
                            else => {},
                        }
                    }
                } else {
                    switch (seq[1]) {
                        'A' => return .arrow_up,
                        'B' => return .arrow_down,
                        'C' => return .arrow_right,
                        'D' => return .arrow_left,
                        'H' => return .home,
                        'F' => return .end,
                        else => {},
                    }
                }
            } else if (seq[0] == 'O') {
                switch (seq[1]) {
                    'H' => return .home,
                    'F' => return .end,
                    else => {},
                }
            }

            // this is return for a simple esc
            return .escape;
        }

        // return for a regular char
        return .{ .char = c };
    }
}
