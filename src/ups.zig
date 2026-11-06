const std = @import("std");
const protocol = @import("protocol.zig");

pub fn query(fd: i32) !protocol.UpsStatus {
    _ = try protocol.sendCommand(fd, "Q\r");

    var res_buf: [64]u8 = undefined;

    const response = try protocol.readResponse(
        fd,
        &res_buf,
        100,
        20_000_000,
    );

    const result = try protocol.parseQ1(response);
    return result;
}

test "query should fail if an invalid file descriptor is provided" {
    try std.testing.expectError(
        error.BadFileDescriptor,
        query(-1),
    );
}
