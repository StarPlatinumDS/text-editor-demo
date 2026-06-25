const std = @import("std");
const posix = std.posix;

// system's API
pub const stdin_fd: posix.fd_t = 0;

// ....
pub const RawMode = struct {
    fd: posix.fd_t,
    original: posix.termios,

    pub fn enable(fd: posix.fd_t) !RawMode {
        const original = try posix.tcgetattr(fd);
        var raw = original;

        // turn off echo and icanon
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;

        // ....
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
