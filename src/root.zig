//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;
const posix = std.posix;
const linux = std.os.linux;

/// This is a documentation comment to explain the `printAnotherMessage` function below.
///
/// Accepting an `Io.Writer` instance is a handy way to write reusable code.
pub fn printAnotherMessage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.print("Run `zig build test` to run the tests.\n", .{});
}

pub const PACKET_SIZE = 8;

/// Open a new /dev/hidrawN device provided.
pub fn openDevice(path: [:0]const u8) !posix.fd_t {
    const result = try posix.openat(
        posix.AT.FDCWD,
        path,
        .{
            .ACCMODE = .RDWR,
            .NONBLOCK = true,
        },
        0o600,
    );

    return result;
}

/// Close a /dev/hidrawN device provided. If the caller gets an EINTR, DO NOT
/// ATTEMPT TO CLOSE IT AGAIN.
pub fn closeDevice(fd: i32) !usize {
    const result = linux.close(fd);

    const err = linux.errno(result);

    if (err != .SUCCESS) {
        switch (err) {
            .BADF => {
                return error.BadFileDescriptor;
            },
            .IO => {
                return error.BadIO;
            },
            .INTR => {
                return error.Interrupted;
            },
            else => {
                return error.Unhandled;
            },
        }
    }

    return result;
}

// Tests begin here

test "open a hidraw device file descriptor" {
    const result = try openDevice("/dev/hidraw0");

    try std.testing.expect(result == 3);
}

test "openDevice fails when an unknown file descriptor is provided" {
    const result = openDevice("/dev/hidrawNaN");

    try std.testing.expectError(error.FileNotFound, result);
}

test "closeDevice fails with an invalid file descriptor" {
    const fake_fd: i32 = 9999;

    try std.testing.expectError(error.BadFileDescriptor, closeDevice(fake_fd));
}
