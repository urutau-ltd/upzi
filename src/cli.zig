//! Command line utilities for this tool.
//!
//! This module contains several utilities to parse command line flags and
//! positional arguments from the implementation. They are re-exported by
//! root.zig but it's not really expected that anyone uses them outside
//! upzi.

const std = @import("std");
const mem = std.mem;
const testing = std.testing;

// Most code from here has been stolen from:
// https://sl.urutau-ltd.org/urutau-ltd/forge-cli/src/branch/main/src/lib.zig
//
// Feel free to improve, it might benefit both CLI's :)

pub const USAGE =
    \\usage: upzi [OPTIONS] [ARGS]
    \\
    \\options:
    \\
    \\  --list, -l          list discoverable UPS devices.
    \\  --json              print the UPS status as JSON once, then exit.
    \\  --once, -o          print the UPS status once, then exit.
    \\  --no-colour, -n      remove colored output if applicable.
    \\  --verbose, -vv      enable verbose output.
    \\  --version, -v       print the version and exit.
    \\  --help, -h          print this help screen and exit.
    \\
    \\ Exit code 0 if everything ran successfully. 1 if there's a runtime/device
    \\ failure.
;

/// Represents a parsed collection of CLI arguments for post-processing
pub const Options = struct {
    /// Set when --version/-v is passed, main prints the version and exits
    /// before doing anything else if this flag is passed.
    version: bool = false,

    /// Set when --help/-h is passed, main prints the help screen and exits
    /// before doing anything else if this flag is passed.
    help: bool = false,

    /// main runs just one query and returns the UPS status serialized as
    /// a JSON object when this flag is passed as --json.
    json: bool = false,

    /// main lists all discover devices and returns the first discovered
    /// UPS when this flag is passed as --list.
    list: bool = false,

    /// Set when --no-colour/-n is passed, on colored output modes main will
    /// print plain text instead. It's used only for 'once' and in future
    /// versions for monitor. Never use this on JSON or other modes.
    noColour: bool = false,

    /// main runs just one query and returns the UPS status when this flag
    /// is passed as --once.
    once: bool = false,

    /// Set when --verbose/-vv is passed, main prints detailed operation
    /// information, useful for runtime debugging.
    verbose: bool = false,

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

    if (args.len == 0) {
        opts.help = true;
    }

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
        } else if (mem.eql(u8, arg, "--once") or mem.eql(
            u8,
            arg,
            "-o",
        )) {
            opts.once = true;
        } else if (mem.eql(u8, arg, "--list") or mem.eql(
            u8,
            arg,
            "-l",
        )) {
            opts.list = true;
        } else if (mem.eql(u8, arg, "--verbose") or mem.eql(
            u8,
            arg,
            "-vv",
        )) {
            opts.verbose = true;
        } else if (mem.eql(u8, arg, "--no-colour") or mem.eql(
            u8,
            arg,
            "-n",
        )) {
            opts.noColour = true;
        } else if (mem.eql(u8, arg, "--json")) {
            opts.json = true;
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

/// Standard ANSI foreground colour codes (SGR parameters).
///
/// Used by `Term.setColour` to format escape sequences as `\x1b[<code>m`.
pub const TermColour = enum(u8) {
    black = 30,
    red = 31,
    green = 32,
    yellow = 33,
    blue = 34,
    magenta = 35,
    cyan = 36,
    white = 37,
    default = 39,
};

/// Used as a wrapper to print colored outputs to ANSI terminals. One could
/// worry about compatiblity with this. But `upzi` is writed to fit Linux only
/// for now, and dumb terminals should be using --no-colour anyways.
///
/// Keep usage of this module inside `ups.zig` and `main.zig` modules. Do not
/// import it inside other library modules.
pub const Term = struct {
    /// Called provided underlying output stream.
    out: *std.Io.Writer,
    /// When true, suppresses colour and style escape sequences.
    disabled: bool,

    /// Wraps `out` to initialize a `Term`
    ///
    /// Set `disabled` to true to omit ANSI colour escape sequences, for
    /// example when `UPZI_NO_COLOR` is set or when the output stream is NOT
    /// a tty.
    pub fn init(out: *std.Io.Writer, disabled: bool) Term {
        return .{
            .out = out,
            .disabled = disabled,
        };
    }

    pub fn clear(self: Term) !void {
        try self.out.writeAll("\x1b[2K\r");
    }

    pub fn clearLine(self: Term) !void {
        try self.out.writeAll("\x1b[2K\r");
    }

    pub fn moveTo(self: Term, row: u16, col: u16) !void {
        try self.out.print("\x1b[{d};{d}H", .{ row, col });
    }

    pub fn hideCursor(self: Term) !void {
        try self.out.writeAll("\x1b[?25l");
    }

    pub fn showCursor(self: Term) !void {
        try self.out.writeAll("\x1b[?25h");
    }

    pub fn setColour(self: Term, colour: TermColour) !void {
        if (self.disabled) {
            return;
        }
        try self.out.print("\x1b[{d}m", .{@intFromEnum(colour)});
    }

    pub fn reset(self: Term) !void {
        if (self.disabled) {
            return;
        }
        try self.out.writeAll("\x1b[0m");
    }

    pub fn print(
        self: Term,
        colour: TermColour,
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
        try self.setColour(colour);
        try self.out.print(fmt, args);
        try self.reset();
    }

    pub fn flush(self: Term) !void {
        try self.out.flush();
    }
};

// Tests begin here

test "no args should redirect to --help" {
    const args: []const []const u8 = &[_][]const u8{};
    const opts = try parseFlags(args);

    try testing.expectEqual(0, opts.positional_count);
    try testing.expectEqual(false, opts.json);
    try testing.expectEqual(false, opts.list);
    try testing.expectEqual(false, opts.noColour);
    try testing.expectEqual(false, opts.once);
    try testing.expectEqual(false, opts.version);
    try testing.expectEqual(true, opts.help);
}

test "parseFlags should return the correct structure for --version" {
    const args: []const []const u8 = &[_][]const u8{"--version"};
    const opts = try parseFlags(args);

    try testing.expectEqual(0, opts.positional_count);
    try testing.expectEqual(false, opts.help);
    try testing.expectEqual(false, opts.json);
    try testing.expectEqual(false, opts.list);
    try testing.expectEqual(false, opts.noColour);
    try testing.expectEqual(false, opts.once);
    try testing.expectEqual(true, opts.version);
}

test "parseFlags should return the correct structure for -v" {
    const args: []const []const u8 = &[_][]const u8{"-v"};
    const opts = try parseFlags(args);

    try testing.expectEqual(0, opts.positional_count);
    try testing.expectEqual(false, opts.help);
    try testing.expectEqual(false, opts.json);
    try testing.expectEqual(false, opts.list);
    try testing.expectEqual(false, opts.noColour);
    try testing.expectEqual(false, opts.once);
    try testing.expectEqual(true, opts.version);
}

test "parseFlags should return the correct structure for --help" {
    const args: []const []const u8 = &[_][]const u8{"--help"};
    const opts = try parseFlags(args);

    try testing.expectEqual(0, opts.positional_count);
    try testing.expectEqual(false, opts.json);
    try testing.expectEqual(false, opts.list);
    try testing.expectEqual(false, opts.noColour);
    try testing.expectEqual(false, opts.once);
    try testing.expectEqual(false, opts.version);
    try testing.expectEqual(true, opts.help);
}

test "parseFlags should return the correct structure for -h" {
    const args: []const []const u8 = &[_][]const u8{"-h"};
    const opts = try parseFlags(args);

    try testing.expectEqual(0, opts.positional_count);
    try testing.expectEqual(false, opts.json);
    try testing.expectEqual(false, opts.list);
    try testing.expectEqual(false, opts.noColour);
    try testing.expectEqual(false, opts.once);
    try testing.expectEqual(false, opts.version);
    try testing.expectEqual(true, opts.help);
}

test "parseFlags should return the correct structure for --once" {
    const args: []const []const u8 = &[_][]const u8{"--once"};
    const opts = try parseFlags(args);

    try testing.expectEqual(0, opts.positional_count);
    try testing.expectEqual(false, opts.help);
    try testing.expectEqual(false, opts.json);
    try testing.expectEqual(false, opts.list);
    try testing.expectEqual(false, opts.noColour);
    try testing.expectEqual(false, opts.verbose);
    try testing.expectEqual(false, opts.version);
    try testing.expectEqual(true, opts.once);
}

test "parseFlags should return the correct structure for -o" {
    const args: []const []const u8 = &[_][]const u8{"-o"};
    const opts = try parseFlags(args);

    try testing.expectEqual(0, opts.positional_count);
    try testing.expectEqual(false, opts.help);
    try testing.expectEqual(false, opts.json);
    try testing.expectEqual(false, opts.list);
    try testing.expectEqual(false, opts.noColour);
    try testing.expectEqual(false, opts.verbose);
    try testing.expectEqual(false, opts.version);
    try testing.expectEqual(true, opts.once);
}

test "parseFlags should return the correct structure for --list" {
    const args: []const []const u8 = &[_][]const u8{"--list"};
    const opts = try parseFlags(args);

    try testing.expectEqual(0, opts.positional_count);
    try testing.expectEqual(false, opts.help);
    try testing.expectEqual(false, opts.json);
    try testing.expectEqual(false, opts.noColour);
    try testing.expectEqual(false, opts.once);
    try testing.expectEqual(false, opts.verbose);
    try testing.expectEqual(false, opts.version);
    try testing.expectEqual(true, opts.list);
}

test "parseFlags should return the correct structure for -l" {
    const args: []const []const u8 = &[_][]const u8{"-l"};
    const opts = try parseFlags(args);

    try testing.expectEqual(0, opts.positional_count);
    try testing.expectEqual(false, opts.help);
    try testing.expectEqual(false, opts.json);
    try testing.expectEqual(false, opts.noColour);
    try testing.expectEqual(false, opts.once);
    try testing.expectEqual(false, opts.verbose);
    try testing.expectEqual(false, opts.version);
    try testing.expectEqual(true, opts.list);
}

test "parseFlags should return the correct structure for --json" {
    const args: []const []const u8 = &[_][]const u8{"--json"};
    const opts = try parseFlags(args);

    try testing.expectEqual(0, opts.positional_count);
    try testing.expectEqual(false, opts.help);
    try testing.expectEqual(false, opts.list);
    try testing.expectEqual(false, opts.noColour);
    try testing.expectEqual(false, opts.once);
    try testing.expectEqual(false, opts.verbose);
    try testing.expectEqual(false, opts.version);
    try testing.expectEqual(true, opts.json);
}

test "parseFlags should return the correct structure for --verbose" {
    const args: []const []const u8 = &[_][]const u8{"--verbose"};
    const opts = try parseFlags(args);

    try testing.expectEqual(0, opts.positional_count);
    try testing.expectEqual(false, opts.help);
    try testing.expectEqual(false, opts.json);
    try testing.expectEqual(false, opts.list);
    try testing.expectEqual(false, opts.noColour);
    try testing.expectEqual(false, opts.once);
    try testing.expectEqual(false, opts.version);
    try testing.expectEqual(true, opts.verbose);
}

test "parseFlags should return the correct structure for -vv" {
    const args: []const []const u8 = &[_][]const u8{"-vv"};
    const opts = try parseFlags(args);

    try testing.expectEqual(0, opts.positional_count);
    try testing.expectEqual(false, opts.help);
    try testing.expectEqual(false, opts.json);
    try testing.expectEqual(false, opts.list);
    try testing.expectEqual(false, opts.noColour);
    try testing.expectEqual(false, opts.once);
    try testing.expectEqual(false, opts.version);
    try testing.expectEqual(true, opts.verbose);
}

test "parseFlags should return the correct structure for --no-colour" {
    const args: []const []const u8 = &[_][]const u8{"--no-colour"};
    const opts = try parseFlags(args);

    try testing.expectEqual(0, opts.positional_count);
    try testing.expectEqual(false, opts.help);
    try testing.expectEqual(false, opts.json);
    try testing.expectEqual(false, opts.list);
    try testing.expectEqual(false, opts.once);
    try testing.expectEqual(false, opts.verbose);
    try testing.expectEqual(false, opts.version);
    try testing.expectEqual(true, opts.noColour);
}

test "parseFlags should return the correct structure for -n" {
    const args: []const []const u8 = &[_][]const u8{"-n"};
    const opts = try parseFlags(args);

    try testing.expectEqual(0, opts.positional_count);
    try testing.expectEqual(false, opts.help);
    try testing.expectEqual(false, opts.json);
    try testing.expectEqual(false, opts.list);
    try testing.expectEqual(false, opts.once);
    try testing.expectEqual(false, opts.verbose);
    try testing.expectEqual(false, opts.version);
    try testing.expectEqual(true, opts.noColour);
}

test "parseFlags should return error.UnknownOption for unrecognized flags" {
    const args: []const []const u8 = &[_][]const u8{ "upzi", "--onve" };
    try testing.expectError(
        error.UnknownOption,
        parseFlags(args),
    );
}
