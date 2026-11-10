const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const testing = std.testing;
const linux = std.os.linux;

const hidraw = @import("hidraw.zig");

/// Hackers:
/// This is the Megatec Q1/QS Protocol response parser.
/// https://networkupstools.org/protocols/megatec.html
/// https://networkupstools.org/protocols/voltronic-qs.html
///
/// Fields:
///   BBB.B - Input Voltage (V)
///   CCC.C - Input Fault Voltage (V)
///   DDD.D - Output Voltage (V)
///   EEE   - Load (%)
///   FF.F  - Line Frequency (Hz)
///   GG.G  - Battery Voltage (V)
///   HH.H  - Temperature (C)
///   8bits - Status Flags (b7..b0)
///
/// Status Bits (b7 = leftmost):
///   b7 - Utility Fail (AC input lost)
///   b6 - Battery Low
///   b5 - Boost or Buck active
///   b4 - UPS Failed
///   b3 - Line Interactive (vs Standby)
///   b2 - Test in Progress
///   b1 - Shutdown Active
///   b0 - Beeper On
///
/// The protocol definition is repeated per-struct field for easier
/// symbol navigation on the IDE.
pub const UpsStatus = struct {
    /// Input voltage (in Volts)
    input_voltage: f32,

    /// Input fault voltage (in Volts)
    fault_voltage: f32,

    /// Output voltage (in Volts)
    output_voltage: f32,

    /// Load (stress) percentage
    load_percent: u8,

    /// Line frequency (in Hertz)
    frequency: f32,

    /// Battery voltage (in Volts)
    battery_voltage: f32,

    /// Temperature (in Celcius)
    /// NOTE: To library users, if translating to Spanish, please do not call
    /// these 'Centígrados', everytime you do so a ziguana dies of thirst.
    temperature: ?f32,

    // Status bits
    /// AC Input Lost
    utility_fail: bool,

    /// Battery is low
    battery_low: bool,

    /// Boost/Buck is active
    boost_buck: bool,

    /// UPS Failure
    ups_failed: bool,

    /// Line interactive topolgy or standby
    line_interactive: bool,

    /// UPS tests are running
    test_in_progress: bool,

    /// Shutdown active
    shutdown_active: bool,

    /// UPS beeper is on
    beeper_on: bool,
};

/// Send a command string to the UPS, 8 byte chunks per packet.
/// For the Megatec/Cypress protocol each char should be sent as:
/// [Q 1 \r 0 0 0 0 0].
pub fn sendCommand(fd: i32, cmd_str: []const u8) !void {
    var offset: usize = 0;

    while (offset < cmd_str.len) {
        const n = @min(8, cmd_str.len - offset);
        var report = [_]u8{0} ** 8;

        @memcpy(report[0..n], cmd_str[offset .. offset + n]);
        _ = try hidraw.writePacket(fd, &report);
        offset += n;
    }
}

/// Accumulate HID input packets until CR or retries are exhausted.
/// The caller must provide a LINUX non-blocking hidraw descriptor, otherwise
/// the `readPacket` function inside will block and the retry loop won't kick in.
///
/// The caller must also provide a caller-owned buffer. The response is written
/// into `out`, `out` must outlive the returned slice, the `out.len` field is
/// the maximum response size, a full buffer will return
/// `error.ResponseTooLong`.
///
/// Mind that retry_sleep_ns is in nanoseconds and used only when `readPacket`
/// returns no data, valid range for this is 0 <= n < 1_000_000_000. 0 means
/// busy loop.
///
/// The returned slice includes the terminating `0x0D`.
///
/// If the loop ends with no bytes the function returns an `error.Timeout` or
/// an `error.IncompleteResponse` if returned partial bytes and no CR is
/// present. The loop ends when `max_retries` limit is reached, each iteration
/// increments the retry counter, it doesn't matter if a packet arrived or if
/// the call slept. Successful packet reads count too.
pub fn readResponse(
    fd: i32,
    out: []u8,
    max_retries: usize,
    retry_sleep_ns: i64,
) ![]const u8 {
    var index: usize = 0;
    var retry: usize = 0;

    var packet_buf: [8]u8 = undefined;

    const ts = linux.timespec{
        .sec = 0,
        .nsec = retry_sleep_ns,
    };

    while (retry < max_retries) : (retry += 1) {
        if (try hidraw.readPacket(fd, &packet_buf)) |packet| {
            for (packet.packet[0..packet.len]) |byte| {
                if (index >= out.len) {
                    return error.ResponseTooLong;
                }
                out[index] = byte;
                index += 1;

                if (byte == 0x0D) {
                    return out[0..index];
                }
            }
        } else {
            var sl_res = linux.nanosleep(&ts, null);
            var err = linux.errno(sl_res);

            while (err != .SUCCESS) {
                switch (err) {
                    .INTR => {
                        // Interrupted, retry
                        sl_res = linux.nanosleep(&ts, null);
                        err = linux.errno(sl_res);
                        continue;
                    },
                    .TIMEDOUT => {
                        return error.Timeout;
                    },
                    else => {
                        return error.Unhandled;
                    },
                }
            }
        }
    }

    if (index == 0) {
        return error.Timeout;
    } else {
        return error.IncompleteResponse;
    }
}

/// Helper function to validate floats inside a response string.
fn validUpsFloat(val: []const u8) !f32 {
    const result = try fmt.parseFloat(f32, val);

    if (!std.math.isFinite(result)) {
        return error.InvalidUPSFloat;
    }

    return result;
}

/// Helper function for optional floats that can be "--.-"
fn optionalUpsFloat(val: []const u8) !?f32 {
    if (mem.eql(u8, val, "--.-")) {
        return null;
    }
    return try validUpsFloat(val);
}

/// Parse a raw QS reply frame into a `UpsStatus` struct.
/// The caller must provide the reply frame itself.
///
/// NOTE: Callers must be aware that, if the temperature is missing on the
/// provided reply frame (which is marked when the field itself sends a slice
/// that's `--.-`) the function will actually return the `UpsStatus` value with
/// the `temperature` field set to `null`. How you
/// deal with this result is up to you as a user of this library.
pub fn parseStatus(response: []const u8) !UpsStatus {
    var sanitized_response = mem.trimEnd(
        u8,
        response,
        "\r\n",
    );

    if (sanitized_response.len == 0) {
        return error.EmptyResponse;
    }

    if (sanitized_response[0] != '(') {
        return error.MissingLeadingByte;
    }

    if (sanitized_response.len == 1 or sanitized_response[1] == '(') {
        return error.BadFormat;
    }

    sanitized_response = mem.trimStart(
        u8,
        sanitized_response,
        "(",
    );

    var tokens = mem.tokenizeScalar(
        u8,
        sanitized_response,
        ' ',
    );

    // Split into fields
    const input_v = tokens.next() orelse return error.MissingInputVoltage;
    const fault_v = tokens.next() orelse return error.MissingFaultVoltage;
    const output_v = tokens.next() orelse return error.MissingOutputVoltage;
    const load_perc = tokens.next() orelse return error.MissingLoadPercentage;
    const freq = tokens.next() orelse return error.MissingFrequency;
    const bat_v = tokens.next() orelse return error.MissingBatteryVoltage;
    const temp = tokens.next() orelse return error.MissingTemperature;
    const status_indicators = tokens.next() orelse return error.InvalidFormat;

    const extra = tokens.next();

    if (extra != null) {
        return error.ExtraField;
    }

    if (status_indicators.len < 8 or status_indicators.len > 8) {
        return error.InvalidStatusIndicatorsLength;
    }

    for (status_indicators) |stat| {
        if (stat != '0' and stat != '1') {
            return error.InvalidStatusIndicatorFormat;
        }
    }

    const load_percent = try fmt.parseUnsigned(u8, load_perc, 10);

    if (load_percent > 100) {
        return error.InvalidLoadPercentage;
    }

    return UpsStatus{
        .input_voltage = try validUpsFloat(input_v),
        .fault_voltage = try validUpsFloat(fault_v),
        .output_voltage = try validUpsFloat(output_v),
        .load_percent = load_percent,
        .frequency = try validUpsFloat(freq),
        .battery_voltage = try validUpsFloat(bat_v),
        .temperature = try optionalUpsFloat(temp),

        // NOTE: true and false carry different meanings in the protocol itself
        // line_interactive and beeper on are descriptive. The rest raise some
        // alarms
        .utility_fail = status_indicators[0] == '1',
        .battery_low = status_indicators[1] == '1',
        .boost_buck = status_indicators[2] == '1',
        .ups_failed = status_indicators[3] == '1',
        .line_interactive = status_indicators[4] == '1',
        .test_in_progress = status_indicators[5] == '1',
        .shutdown_active = status_indicators[6] == '1',
        .beeper_on = status_indicators[7] == '1',
    };
}

// Tests begin here
test "sendCommand errors when using a bad file descriptor" {
    try testing.expectError(
        error.BadFileDescriptor,
        sendCommand(-1, "Q"),
    );
}

test "parseStatus should succeed on a base valid response" {
    const response = "(229.0 229.0 229.0 000 50.0 13.50 25.0 00000000\r";

    const result = try parseStatus(response);

    try testing.expectEqual(229.0, result.input_voltage);
    try testing.expectEqual(229.0, result.fault_voltage);
    try testing.expectEqual(229.0, result.output_voltage);
    try testing.expectEqual(0, result.load_percent);
    try testing.expectEqual(50.0, result.frequency);
    try testing.expectEqual(13.50, result.battery_voltage);
    try testing.expectEqual(25.0, result.temperature);
    try testing.expectEqual(false, result.utility_fail);
    try testing.expectEqual(false, result.battery_low);
    try testing.expectEqual(false, result.boost_buck);
    try testing.expectEqual(false, result.ups_failed);
    try testing.expectEqual(false, result.line_interactive);
    try testing.expectEqual(false, result.test_in_progress);
    try testing.expectEqual(false, result.shutdown_active);
    try testing.expectEqual(false, result.beeper_on);
}

test "parseStatus should succeed on a second base valid response" {
    const response = "(230.0 230.0 230.0 100 60.0 13.5 30.0 10000000\r";

    const result = try parseStatus(response);

    try testing.expectEqual(230.0, result.input_voltage);
    try testing.expectEqual(230.0, result.fault_voltage);
    try testing.expectEqual(230.0, result.output_voltage);
    try testing.expectEqual(100, result.load_percent);
    try testing.expectEqual(60.0, result.frequency);
    try testing.expectEqual(13.50, result.battery_voltage);
    try testing.expectEqual(30.0, result.temperature);
    try testing.expectEqual(true, result.utility_fail);
    try testing.expectEqual(false, result.battery_low);
    try testing.expectEqual(false, result.boost_buck);
    try testing.expectEqual(false, result.ups_failed);
    try testing.expectEqual(false, result.line_interactive);
    try testing.expectEqual(false, result.test_in_progress);
    try testing.expectEqual(false, result.shutdown_active);
    try testing.expectEqual(false, result.beeper_on);
}

test "parseStatus should trim CRLF the same as CR" {
    const response = "(229.0 229.0 229.0 000 50.0 13.50 25.0 00000000\r\n";
    const result = try parseStatus(response);

    try testing.expectEqual(229.0, result.input_voltage);
    try testing.expectEqual(229.0, result.fault_voltage);
    try testing.expectEqual(229.0, result.output_voltage);
    try testing.expectEqual(0, result.load_percent);
    try testing.expectEqual(50.0, result.frequency);
    try testing.expectEqual(13.50, result.battery_voltage);
    try testing.expectEqual(25.0, result.temperature);
    try testing.expectEqual(false, result.utility_fail);
    try testing.expectEqual(false, result.battery_low);
    try testing.expectEqual(false, result.boost_buck);
    try testing.expectEqual(false, result.ups_failed);
    try testing.expectEqual(false, result.line_interactive);
    try testing.expectEqual(false, result.test_in_progress);
    try testing.expectEqual(false, result.shutdown_active);
    try testing.expectEqual(false, result.beeper_on);
}

test "parseStatus should allow if no terminator is present" {
    const response = "(229.0 229.0 229.0 000 50.0 13.50 25.0 00000000";
    const result = try parseStatus(response);

    try testing.expectEqual(229.0, result.input_voltage);
    try testing.expectEqual(229.0, result.fault_voltage);
    try testing.expectEqual(229.0, result.output_voltage);
    try testing.expectEqual(0, result.load_percent);
    try testing.expectEqual(50.0, result.frequency);
    try testing.expectEqual(13.50, result.battery_voltage);
    try testing.expectEqual(25.0, result.temperature);
    try testing.expectEqual(false, result.utility_fail);
    try testing.expectEqual(false, result.battery_low);
    try testing.expectEqual(false, result.boost_buck);
    try testing.expectEqual(false, result.ups_failed);
    try testing.expectEqual(false, result.line_interactive);
    try testing.expectEqual(false, result.test_in_progress);
    try testing.expectEqual(false, result.shutdown_active);
    try testing.expectEqual(false, result.beeper_on);
}

test "parseStatus should fail if no leading ( is present" {
    const response = "229.0 229.0 229.0 000 50.0 13.50 25.0 00000000\r";
    try testing.expectError(
        error.MissingLeadingByte,
        parseStatus(response),
    );
}

test "parseStatus should fail if the indicator flags are incomplete" {
    const response = "(229.0 229.0 229.0 000 50.0 13.50 25.0 0000000\r";
    try testing.expectError(
        error.InvalidStatusIndicatorsLength,
        parseStatus(response),
    );
}

test "parseStatus should fail if an invalid flag character is present" {
    const response = "(229.0 229.0 229.0 000 50.0 13.50 25.0 0000000X\r";
    try testing.expectError(
        error.InvalidStatusIndicatorFormat,
        parseStatus(response),
    );
}

test "parseStatus should fail if a flag string is longer than expected" {
    const response = "(229.0 229.0 229.0 000 50.0 13.50 25.0 000000000\r";
    try testing.expectError(
        error.InvalidStatusIndicatorsLength,
        parseStatus(response),
    );
}

test "parseStatus should fail if the response contains an extra field" {
    const response = "(229.0 229.0 229.0 000 50.0 13.50 25.0 00000000 extra\r";
    try testing.expectError(
        error.ExtraField,
        parseStatus(response),
    );
}

test "parseStatus should fail if the voltage is wrong/impossible" {
    const response = "(abc.0 229.0 229.0 000 50.0 13.50 25.0 00000000\r";
    try testing.expectError(
        error.InvalidCharacter,
        parseStatus(response),
    );
}

test "parseStatus should fail if you overflow the u8" {
    const response = "(229.0 229.0 229.0 999999 50.0 13.50 25.0 00000000\r";
    try testing.expectError(
        error.Overflow,
        parseStatus(response),
    );
}

test "parseStatus should fail if a bad float is provided" {
    const response = "(229.0 229.0 229.0 000 60,0 13.50 25.0 00000000\r";
    try testing.expectError(
        error.InvalidCharacter,
        parseStatus(response),
    );
}

test "parseStatus should fail if an empty response is provided" {
    const response = "";
    try testing.expectError(
        error.EmptyResponse,
        parseStatus(response),
    );

    const response_r = "\r";
    try testing.expectError(
        error.EmptyResponse,
        parseStatus(response_r),
    );
}

test "parseStatus should fail if the load is over 100%" {
    const response = "(229.0 229.0 229.0 101 50.0 13.50 25.0 00000000\r";
    try testing.expectError(
        error.InvalidLoadPercentage,
        parseStatus(response),
    );
}

test "parseStatus should fail if for some magic reason an extra parentheses is present" {
    const response = "((229.0 229.0 229.0 100 50.0 13.50 25.0 00000000\r";
    try testing.expectError(
        error.BadFormat,
        parseStatus(response),
    );
}

test "parseStatus should fail if for some magic reason a single parentheses response is present" {
    try testing.expectError(
        error.BadFormat,
        parseStatus("("),
    );
}

test "parseStatus should fail if any float is 'nan' or 'inf'" {
    const response = "(nan inf 229.0 100 50.0 13.50 25.0 00000000\r";
    try testing.expectError(
        error.InvalidUPSFloat,
        parseStatus(response),
    );
}

test "validUpsFloat should return the corresponding slices to floats" {
    const test_values = [_][]const u8{
        "0.0",
        "1.0",
        "+1.0",
        "-1.0",
        "100",
        "123456",
        "-5000.0",
        "0.1",
        "-0.25",
        "3.14159265",
        "2.71828182",
        "0.000001",
    };
    const expected_results = [_]f32{
        0.0,
        1.0,
        1.0,
        -1.0,
        100.0,
        123456.0,
        -5000.0,
        0.1,
        -0.25,
        3.14159265,
        2.71828182,
        0.000001,
    };

    // The test arrays must be the same length
    try testing.expectEqual(test_values.len, expected_results.len);

    for (0..test_values.len) |i| {
        const value = test_values[i];
        try testing.expectEqual(
            validUpsFloat(value),
            expected_results[i],
        );
    }
}

test "validUpsFloat should return an error with 'nan' or 'inf' as values" {
    try testing.expectError(
        error.InvalidUPSFloat,
        validUpsFloat("nan"),
    );
    try testing.expectError(
        error.InvalidUPSFloat,
        validUpsFloat("inf"),
    );
}

test "optionalUpsFloat should return null if '--.-' is passed" {
    try testing.expectEqual(null, optionalUpsFloat("--.-"));
}

test "optionalUpsFloat should return a valid f32 if a correct float is passed" {
    const test_values = [_][]const u8{
        "0.0",
        "1.0",
        "+1.0",
        "-1.0",
        "100",
        "123456",
        "-5000.0",
        "0.1",
        "-0.25",
        "3.14159265",
        "2.71828182",
        "0.000001",
    };
    const expected_results = [_]f32{
        0.0,
        1.0,
        1.0,
        -1.0,
        100.0,
        123456.0,
        -5000.0,
        0.1,
        -0.25,
        3.14159265,
        2.71828182,
        0.000001,
    };

    // The test arrays must be the same length
    try testing.expectEqual(test_values.len, expected_results.len);

    for (0..test_values.len) |i| {
        const value = test_values[i];
        try testing.expectEqual(
            optionalUpsFloat(value),
            expected_results[i],
        );
    }
}
