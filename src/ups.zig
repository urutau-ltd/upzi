const std = @import("std");
const Io = std.Io;
const protocol = @import("protocol.zig");

pub fn query(fd: i32) !protocol.UpsStatus {
    _ = try protocol.sendCommand(fd, "QS\r");

    var res_buf: [64]u8 = undefined;

    const response = try protocol.readResponse(
        fd,
        &res_buf,
        100,
        20_000_000,
    );

    const result = try protocol.parseStatus(response);
    return result;
}

pub fn printStatus(writer: *Io.Writer, s: protocol.UpsStatus) !void {
    try writer.print(
        \\
        \\ ┌─────────────────────────────┐
        \\ │        ⚡️ UPZI - UPS        │
        \\ ├─────────────────────────────┤
        \\ │ Input voltage   {:7.1} V   │
        \\ │ Output voltage  {:7.1} V   │
        \\ │ Battery voltage {:7.1} V   │
        \\ │ Load            {:7}%    │
        \\ │ Frequency       {:7.1} Hz  │
        \\ │ Temperature     {:7.1} °C  │
        \\ ├─────────────────────────────┤
        \\ │ AC Fail    {s:<5}             │
        \\ │ Battery Lo {s:<5}             │
        \\ │ Boost/Buck {s:<5}            │
        \\ │ UPS Failed {s:<5}             │
        \\ └─────────────────────────────┘
        \\    
    ,
        .{
            s.input_voltage,
            s.output_voltage,
            s.battery_voltage,
            s.load_percent,
            s.frequency,
            s.temperature,
            if (s.utility_fail) "❗️" else "✅",
            if (s.battery_low) "❗️" else "✅",
            if (s.boost_buck) "YES" else "no",
            if (s.ups_failed) "❗️" else "✅",
        },
    );
}

test "query should fail if an invalid file descriptor is provided" {
    try std.testing.expectError(
        error.BadFileDescriptor,
        query(-1),
    );
}
