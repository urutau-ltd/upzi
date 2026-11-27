const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const fmt = std.fmt;
const json = std.json;

const protocol = @import("protocol.zig");
const cli = @import("cli.zig");

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

/// Helper Function to print colored columns in the ASCII box.
fn statusRow(
    term: cli.Term,
    writer: *Io.Writer,
    label: []const u8,
    value: []const u8,
    color: cli.TermColour,
) !void {
    try writer.print(" │ {s:<18}", .{label});
    try term.print(color, "{s:<5}", .{value});
    try writer.writeAll("     │\n");
}

pub fn printStatus(
    writer: *Io.Writer,
    s: protocol.UpsStatus,
    disable_colour: bool,
) !void {
    var temp_buf: [6]u8 = undefined;
    const temp_str: []const u8 = if (s.temperature) |t|
        try fmt.bufPrint(&temp_buf, "{d:.1}", .{t})
    else
        "--.-";

    const term = cli.Term.init(writer, disable_colour);

    try writer.writeAll(
        \\
        \\ ┌─────────────────────────────┐
        \\
    );

    // TODO: Cleanup this ugly mess of a print.
    try writer.writeAll(" │");
    try term.print(
        .yellow,
        "{s:^29}",
        .{"UPZI - UPS"},
    );
    try writer.writeAll("│\n");

    try writer.writeAll(" ├─────────────────────────────┤\n");

    try writer.print(
        \\ │ Input voltage   {:7.1} V   │
        \\ │ Output voltage  {:7.1} V   │
        \\ │ Battery voltage {:7.1} V   │
        \\ │ UPS Load          {:7}%  │
        \\ │ Frequency       {:7.1} Hz  │
        \\ │ Temperature     {s:>7} °C  │
        \\
    ,
        .{
            s.input_voltage,
            s.output_voltage,
            s.battery_voltage,
            s.load_percent,
            s.frequency,
            temp_str,
        },
    );

    try writer.writeAll(" ├───────────");
    try term.print(
        .cyan,
        "{s}",
        .{"[STATUS]"},
    );
    try writer.writeAll("──────────┤\n");

    try statusRow(
        term,
        writer,
        "Input Fail",
        if (s.utility_fail) "YES" else "NO",
        if (s.utility_fail) .red else .green,
    );

    try statusRow(
        term,
        writer,
        "Battery Low",
        if (s.battery_low) "YES" else "NO",
        if (s.battery_low) .yellow else .green,
    );

    try statusRow(
        term,
        writer,
        "Boost/Buck",
        if (s.boost_buck) "YES" else "NO",
        if (s.boost_buck) .cyan else .green,
    );

    try statusRow(
        term,
        writer,
        "Self Test",
        if (s.test_in_progress) "YES" else "NO",
        if (s.test_in_progress) .yellow else .default,
    );

    try statusRow(
        term,
        writer,
        "Shutdown pending?",
        if (s.shutdown_active) "YES" else "NO",
        if (s.shutdown_active) .red else .default,
    );

    try statusRow(
        term,
        writer,
        "Beeper",
        if (s.beeper_on) "YES" else "NO",
        if (s.beeper_on) .cyan else .red,
    );

    try statusRow(
        term,
        writer,
        "UPS Fault",
        if (s.ups_failed) "YES" else "NO",
        if (s.ups_failed) .red else .green,
    );

    try writer.writeAll(
        \\ └─────────────────────────────┘
        \\
    );
}

test "query should fail if an invalid file descriptor is provided" {
    try testing.expectError(
        error.BadFileDescriptor,
        query(-1),
    );
}

test "printStatus print plain text when noColour is set" {
    var buffer: [4096]u8 = undefined;

    var writer: Io.Writer = .fixed(&buffer);

    const status = protocol.UpsStatus{
        .input_voltage = 230.0,
        .fault_voltage = 230.0,
        .output_voltage = 230.0,
        .load_percent = 100,
        .frequency = 60.0,
        .battery_voltage = 13.50,
        .temperature = null,
        .utility_fail = false,
        .battery_low = false,
        .boost_buck = false,
        .ups_failed = false,
        .line_interactive = false,
        .test_in_progress = false,
        .shutdown_active = false,
        .beeper_on = false,
    };

    try printStatus(&writer, status, true);
    const out = writer.buffered();
    try testing.expect(std.mem.indexOf(
        u8,
        out,
        "\x1b",
    ) == null);

    const plain_sep = std.mem.indexOf(
        u8,
        out,
        "├─────────────────────────────┤",
    ) orelse std.math.maxInt(usize);

    const first_num = std.mem.indexOf(
        u8,
        out,
        "│ Input voltage",
    ) orelse std.math.maxInt(usize);

    const status_sep = std.mem.indexOf(
        u8,
        out,
        "[STATUS]",
    ) orelse std.math.maxInt(usize);

    const first_flag = std.mem.indexOf(
        u8,
        out,
        "│ Input Fail",
    ) orelse std.math.maxInt(usize);

    try testing.expect(plain_sep < first_num);
    try testing.expect(first_num < status_sep);
    try testing.expect(status_sep < first_flag);
}
