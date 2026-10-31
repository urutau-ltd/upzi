//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;
const posix = std.posix;

/// This is a documentation comment to explain the `printAnotherMessage` function below.
///
/// Accepting an `Io.Writer` instance is a handy way to write reusable code.
pub fn printAnotherMessage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.print("Run `zig build test` to run the tests.\n", .{});
}

pub const PACKET_SIZE = 8;

/// Open a new /dev/hidrawN device provided optionally.
pub fn openDevice(path: ?[:0]const u8) !posix.fd_t {
    const hidraw_device = path orelse "/dev/hidraw0";

    const result = try posix.openat(
        posix.AT.FDCWD,
        hidraw_device,
        .{
            .ACCMODE = .RDWR,
            .NONBLOCK = true,
        },
        0o600,
    );

    return result;
}

test "open a hidraw device file descriptor" {
    const result = try openDevice("/dev/hidraw0");

    try std.testing.expect(result == 3);
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
