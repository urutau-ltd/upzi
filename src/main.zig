const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Io = std.Io;
const build_options = @import("build_options");

const upzi = @import("upzi");

pub fn main(init: std.process.Init) !void {
    const minimal = init.minimal;
    const arena: Allocator = init.arena.allocator();

    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(
        .stdout(),
        io,
        &stdout_buffer,
    );
    const stdout = &stdout_file_writer.interface;

    const args = (try minimal.args.toSlice(arena))[1..];
    const opts = try upzi.cli.parseFlags(args);

    if (opts.version) {
        try stdout.print("upzi {s}\n", .{build_options.version});
        try stdout.flush();
        return;
    }

    if (opts.help) {
        try stdout.print("{s}\n", .{upzi.cli.USAGE});
        try stdout.flush();
        return;
    }

    if (opts.once) {
        const device_path = try upzi.hidraw.discoverUPS(arena, io);
        const device_fd = try upzi.hidraw.openDevice(device_path);
        defer _ = upzi.hidraw.closeDevice(device_fd) catch |err| {
            std.debug.print("Failed to close UPS device: {}!\n", .{err});
        };

        const query = try upzi.ups.query(device_fd);

        try upzi.ups.printStatus(stdout, query);
    }

    try stdout.flush();
}
