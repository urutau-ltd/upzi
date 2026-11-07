const std = @import("std");
const mem = std.mem;
const posix = std.posix;
const fmt = std.fmt;
const linux = std.os.linux;
const testing = std.testing;
const Io = std.Io;

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

/// Send an 8 byte HID report as: [0 XX XX XX XX XX XX XX XX]. The leading zero
/// is the HID report number.
pub fn writePacket(fd: i32, bytes: *const [8]u8) !usize {
    const BUFFER_SIZE: usize = 9;

    var buffer = [_]u8{0} ** BUFFER_SIZE;
    buffer[0] = 0;

    // Copy the bytes into the temporary buffer we do it from index 1 since
    // we need the first byte to be always zero.
    @memcpy(buffer[1..], bytes);

    var result = linux.write(fd, &buffer, BUFFER_SIZE);

    var err = linux.errno(result);

    while (err != .SUCCESS) {
        switch (err) {
            .INTR => {
                // Interrupted, retry
                result = linux.write(fd, &buffer, BUFFER_SIZE);
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

    if (result != BUFFER_SIZE) {
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

/// Scan for mounted devices and check if any of them is a compatible UPS
/// for this implementation. The function returns a zero-terminated slice with
/// the path for the UPS device at `/dev/hidrawN`.
///
/// The caller must provide an allocator and an Io interface. If the function
/// fails to autodiscover a device it will return a `error.DeviceNotFound` which
/// the caller should handle. Right now the discovery capabilities are very
/// limited and it only searches for `INNO TECH` present in the device name
/// and a specific HID ID. Support for more devices is always welcome.
pub fn discoverUPS(allocator: mem.Allocator, io: std.Io) ![:0]u8 {
    var i: usize = 0;

    while (i < 32) : (i += 1) {
        const dev_path = try fmt.allocPrint(
            allocator,
            "/dev/hidraw{d}",
            .{i},
        );

        defer allocator.free(dev_path);

        const sysfs_path = try fmt.allocPrint(
            allocator,
            "/sys/class/hidraw/hidraw{d}/device/uevent",
            .{i},
        );
        defer allocator.free(sysfs_path);

        var buffer: [1024]u8 = undefined;
        const content = Io.Dir.cwd().readFile(
            io,
            sysfs_path,
            &buffer,
        ) catch continue;

        if (mem.indexOf(
            u8,
            content,
            "INNO TECH",
        ) != null or
            mem.indexOf(
                u8,
                content,
                "0003:00000665:00005161",
            ) != null)
        {
            return allocator.dupeZ(u8, dev_path);
        }
    }

    return error.DeviceNotFound;
}

// Tests begin here

test "open a hidraw device file descriptor" {
    const result = try openDevice("/dev/null");

    try testing.expect(result == 3);
}

test "openDevice fails when an unknown file descriptor is provided" {
    const result = openDevice("/dev/hidrawNaN");

    try testing.expectError(
        error.FileNotFound,
        result,
    );
}

test "closeDevice fails with an invalid file descriptor" {
    const fake_fd: i32 = 9999;

    try testing.expectError(
        error.BadFileDescriptor,
        closeDevice(fake_fd),
    );
}

test "writePacket fails if trying to write to a bad file descriptor" {
    const bytes = &[_]u8{ 'Q', '1', '\r', 0, 0, 0, 0, 0 };
    try testing.expectError(
        error.BadFileDescriptor,
        writePacket(
            -1,
            bytes,
        ),
    );
}

test "readPacket fails if trying to read a bad file descriptor" {
    var buffer: [8]u8 = undefined;
    try testing.expectError(
        error.BadFileDescriptor,
        readPacket(
            -1,
            &buffer,
        ),
    );
}

test "discoverUPS returns a present UPS path when called" {
    const allocator = testing.allocator;
    const io = testing.io;

    const result = try discoverUPS(allocator, io);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("/dev/hidraw0", result);
}
