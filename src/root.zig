//! By convention, root.zig is the root source file when making a package.
pub const hidraw = @import("hidraw.zig");
pub const protocol = @import("protocol.zig");

// Make zig pick up the hidraw module tests
test {
    _ = hidraw;
}

// Make zig pick up the protocol module tests
test {
    _ = protocol;
}
