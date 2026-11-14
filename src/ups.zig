const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const fmt = std.fmt;
const json = std.json;

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

pub fn printJSON(
    writer: *Io.Writer,
    s: protocol.UpsStatus,
) !void {
    try json.Stringify.value(
        s,
        .{ .whitespace = .minified },
        writer,
    );
    try writer.writeAll("\n");
}

pub fn printStatus(writer: *Io.Writer, s: protocol.UpsStatus) !void {
    var temp_buf: [6]u8 = undefined;
    const temp_str: []const u8 = if (s.temperature) |t|
        try fmt.bufPrint(&temp_buf, "{d:.1}", .{t})
    else
        "--.-";

    try writer.print(
        \\
        \\ ┌─────────────────────────────┐
        \\ │         UPZI - UPS          │
        \\ ├─────────────────────────────┤
        \\ │ Input voltage   {:7.1} V   │
        \\ │ Output voltage  {:7.1} V   │
        \\ │ Battery voltage {:7.1} V   │
        \\ │ UPS Load          {:7}%  │
        \\ │ Frequency       {:7.1} Hz  │
        \\ │ Temperature     {s:>7} °C  │
        \\ ├────────────STATUS───────────┤
        \\ │ Input Fail        {s:<5}     │
        \\ │ Battery Low       {s:<5}     │
        \\ │ Boost/Buck        {s:<5}     │
        \\ │ Self-test         {s:<5}     │
        \\ │ Shutdown pending? {s:<5}     │
        \\ │ Beeper            {s:<5}     │
        \\ │ UPS Fault         {s:<5}     │
        \\ └─────────────────────────────┘
        \\
    ,
        .{
            s.input_voltage,
            s.output_voltage,
            s.battery_voltage,
            s.load_percent,
            s.frequency,
            temp_str,
            if (s.utility_fail) "YES" else "NO",
            if (s.battery_low) "YES" else "NO",
            if (s.boost_buck) "YES" else "NO",
            if (s.test_in_progress) "YES" else "NO",
            if (s.shutdown_active) "YES" else "NO",
            if (s.beeper_on) "ON" else "OFF",
            if (s.ups_failed) "YES" else "NO",
        },
    );
}

test "query should fail if an invalid file descriptor is provided" {
    try testing.expectError(
        error.BadFileDescriptor,
        query(-1),
    );
}
