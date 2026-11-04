const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

pub const PACKET_SIZE = 8;

/// Represents a response returned from the UPS protocol.
pub const MegatecResponse = struct {
    /// The octect vector response itself.
    packet: [8]u8,
    /// The length of the octet vector.
    len: usize,
};

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
/// ATTEMPT TO CLOSE IT AGAIN. Even though the openDevice uses the posix
/// interface, there is no posix.close() on zig and we are resorting to close
/// using linux file descriptors.
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
                return 0;
            },
            else => {
                return error.Unhandled;
            },
        }
    }

    return result;
}

/// Send an 8 byte HID report as: [first-byte 0 0 0 0 0 0 0 ]
pub fn writePacket(fd: i32, first_byte: u8) !usize {
    // Initialize a zero-filled array acting as a buffer.
    // NOTE: It seems [8]u8 is invalid.
    var buffer = [_]u8{0} ** PACKET_SIZE;
    buffer[0] = first_byte;

    var result = linux.write(fd, &buffer, PACKET_SIZE);

    var err = linux.errno(result);

    while (err != .SUCCESS) {
        switch (err) {
            .INTR => {
                // Interrupted, retry
                result = linux.write(fd, &buffer, PACKET_SIZE);
                err = linux.errno(result);
                continue;
            },
            .AGAIN => {
                return error.WouldBlock;
            },
            .BADF => {
                return error.BadFileDescriptor;
            },
            else => {
                return error.Unhandled;
            },
        }
    }

    if (result != PACKET_SIZE) {
        return error.ShortWrite;
    }

    return result;
}

/// Read up to 8 bytes of the endpoint interrupt IN. Return a packet or null if
/// no data was found.
pub fn readPacket(fd: i32, buffer: *[8]u8) !?MegatecResponse {
    var result = linux.read(fd, buffer, PACKET_SIZE);

    var err = linux.errno(result);

    while (err != .SUCCESS) {
        switch (err) {
            .INTR => {
                // Interrupted, retry
                result = linux.read(fd, buffer, PACKET_SIZE);
                err = linux.errno(result);
                continue;
            },
            .AGAIN => {
                // No data yet
                return null;
            },
            .BADF => {
                return error.BadFileDescriptor;
            },
            else => {
                return error.Unhandled;
            },
        }
    }

    if (result == 0) {
        return error.EOF;
    }

    const response = MegatecResponse{
        .packet = buffer.*,
        .len = result,
    };

    return response;
}

// Tests begin here

test "open a hidraw device file descriptor" {
    const result = try openDevice("/dev/null");

    try std.testing.expect(result == 3);
}

test "openDevice fails when an unknown file descriptor is provided" {
    const result = openDevice("/dev/hidrawNaN");

    try std.testing.expectError(
        error.FileNotFound,
        result,
    );
}

test "closeDevice fails with an invalid file descriptor" {
    const fake_fd: i32 = 9999;

    try std.testing.expectError(
        error.BadFileDescriptor,
        closeDevice(fake_fd),
    );
}

test "writePacket fails if trying to write to a bad file descriptor" {
    try std.testing.expectError(
        error.BadFileDescriptor,
        writePacket(
            -1,
            'Q',
        ),
    );
}

test "readPacket fails if trying to read a bad file descriptor" {
    var buffer: [8]u8 = undefined;
    try std.testing.expectError(
        error.BadFileDescriptor,
        readPacket(
            -1,
            &buffer,
        ),
    );
}
