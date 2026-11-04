//! By convention, root.zig is the root source file when making a package.
pub const hidraw = @import("hidraw.zig");

// Make zig pick up the hidraw module tests
test {
    _ = hidraw;
}
