const std = @import("std");
const posix = std.posix;

// Unix/POSIX convention:
//   0 = stdin
//   1 = stdout
//   2 = stderr
// system's API
pub const stdin_fd: posix.fd_t = 0;
pub const stdout_fd: posix.fd_t = 1;

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

    // ....
    pub fn restore(self: RawMode) void {
        posix.tcsetattr(self.fd, posix.TCSA.FLUSH, self.original) catch {};
    }
};

pub fn readKey() !u8 {
    var buf: [1]u8 = undefined;

    while (true) {
        const n = try posix.read(stdin_fd, buf[0..]);

        if (n == 0) continue;

        return buf[0];
    }
}

pub fn writeAll(fd: posix.fd_t, bytes: []const u8) !void {
    var remaining = bytes;

    while (remaining.len > 0) {
        const written = try posix.write(fd, remaining);
        remaining = remaining[written..];
    }
}
