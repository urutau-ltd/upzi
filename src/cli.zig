const std = @import("std");
const mem = std.mem;
const testing = std.testing;

// Most code from here has been stolen from:
// https://sl.urutau-ltd.org/urutau-ltd/forge-cli/src/branch/main/src/lib.zig
//
// Feel free to improve, it might benefit both CLI's :)

pub const USAGE =
    \\usage: upzi [OPTIONS]
    \\
    \\options:
    \\  --once, -o      print the UPS status once, then exit.
    \\  --version, -v   print the version and exit.
    \\  --help, -h      print this help screen and exit.
    \\
    \\ Exit code 0 if everything ran successfully. 1 if there's a runtime/device
    \\ failure. 2 for usage error.
;

/// Represents a parsed collection of CLI arguments for post-processing
pub const Options = struct {
    /// Set when --version/-v is passed, main prints the version and exits
    /// before doing anything else if this flag is passed.
    version: bool = false,

    /// Set when --help/-h is passed, main prints the help screen and exits
    /// before doing anything else if this flag is passed.
    help: bool = false,

    /// main runs just one query and returns the UPS status when this flag
    /// is passed as --once.
    once: bool = false,

    /// Represents the positional arguments for the CLI. We do not need more
    /// than 5 in the entire program's lifecycle AFAIK.
    positionals: [5][]const u8 = undefined,

    /// Counter for positional arguments, used for safety/correct operations.
    positional_count: usize = 0,
};

/// Receives the process CLI arguments passed by the shell and serializes them
/// into the `Options` structure.
///
/// Note: Positional args are stored using a fixed inline buffer inside the
/// `Options` struct. This avoids the need for dynamic memory allocation and a
/// corresponding deinit lifecycle. For standard CLI usage, an arbitrary limit
/// like 16 simplifies memory management significantly...for me at least.
pub fn parseFlags(args: []const []const u8) !Options {
    var opts = Options{};
    var i: usize = 0;

    while (i < args.len) : (i += 1) {
        const arg: []const u8 = args[i];

        if (mem.eql(u8, arg, "--version") or mem.eql(
            u8,
            arg,
            "-v",
        )) {
            opts.version = true;
        } else if (mem.eql(u8, arg, "--help") or mem.eql(
            u8,
            arg,
            "-h",
        )) {
            opts.help = true;
        } else if (mem.eql(u8, arg, "--once") or mem.eql(u8, arg, "-o")) {
            opts.once = true;
        } else if (arg.len > 0 and arg[0] == '-') {
            return error.UnknownOption;
        } else {
            // Unrecognized flags or regular values are treated as positional
            // arguments
            if (opts.positional_count >= opts.positionals.len) {
                return error.TooManyPositionalArguments;
            }

            opts.positionals[opts.positional_count] = arg;
            opts.positional_count += 1;
        }
    }

    return opts;
}

// Tests begin here

test "parseFlags should return the correct structure for --version" {
    const args: []const []const u8 = &[_][]const u8{ "upzi", "--version" };
    const opts = try parseFlags(args);

    try testing.expectEqual(true, opts.version);
    try testing.expectEqual(false, opts.once);
    try testing.expectEqual(false, opts.help);
    try testing.expectEqual(1, opts.positional_count);
}

test "parseFlags should return the correct structure for -v" {
    const args: []const []const u8 = &[_][]const u8{ "upzi", "-v" };
    const opts = try parseFlags(args);

    try testing.expectEqual(true, opts.version);
    try testing.expectEqual(false, opts.once);
    try testing.expectEqual(false, opts.help);
    try testing.expectEqual(1, opts.positional_count);
}

test "parseFlags should return the correct structure for --help or -h" {
    const args: []const []const u8 = &[_][]const u8{ "upzi", "--help" };
    const opts = try parseFlags(args);

    try testing.expectEqual(true, opts.help);
    try testing.expectEqual(false, opts.version);
    try testing.expectEqual(false, opts.once);
    try testing.expectEqual(1, opts.positional_count);
}

test "parseFlags should return the correct structure for -h" {
    const args: []const []const u8 = &[_][]const u8{ "upzi", "-h" };
    const opts = try parseFlags(args);

    try testing.expectEqual(true, opts.help);
    try testing.expectEqual(false, opts.version);
    try testing.expectEqual(false, opts.once);
    try testing.expectEqual(1, opts.positional_count);
}

test "parseFlags should return the correct structure for --once or -o" {
    const args: []const []const u8 = &[_][]const u8{ "upzi", "--once" };
    const opts = try parseFlags(args);

    try testing.expectEqual(true, opts.once);
    try testing.expectEqual(false, opts.help);
    try testing.expectEqual(false, opts.version);
    try testing.expectEqual(1, opts.positional_count);
}

test "parseFlags should return the correct structure for -o" {
    const args: []const []const u8 = &[_][]const u8{ "upzi", "-o" };
    const opts = try parseFlags(args);

    try testing.expectEqual(true, opts.once);
    try testing.expectEqual(false, opts.help);
    try testing.expectEqual(false, opts.version);
    try testing.expectEqual(1, opts.positional_count);
}

test "parseFlags should return error.UnknownOption for unrecognized flags" {
    const args: []const []const u8 = &[_][]const u8{ "upzi", "--onve" };
    try testing.expectError(error.UnknownOption, parseFlags(args));
}
