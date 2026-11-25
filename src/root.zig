//! By convention, root.zig is the root source file when making a package.
pub const hidraw = @import("hidraw.zig");
pub const protocol = @import("protocol.zig");
pub const ups = @import("ups.zig");
pub const cli = @import("cli.zig");

test {
    _ = hidraw;
}

test {
    _ = protocol;
}

test {
    _ = ups;
}

test {
    _ = cli;
}
