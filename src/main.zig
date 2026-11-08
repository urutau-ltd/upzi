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
        const device_path = upzi.hidraw.discoverUPS(arena, io) catch {
            std.debug.print("No 0665:5161 device found; check lsusb\n", .{});
            return;
        };
        const device_fd = upzi.hidraw.openDevice(device_path) catch |err| {
            switch (err) {
                error.AccessDenied => {
                    std.debug.print(
                        "Wrong permissions to open {s}, check your udev rules!\n",
                        .{device_path},
                    );
                    return;
                },
                error.FileNotFound => {
                    std.debug.print(
                        "Device {s} was not found mounted or was disconnected!\n",
                        .{device_path},
                    );
                    return;
                },
                else => {
                    std.debug.print(
                        "Unhandled error {}, please send it to the maintainers!\n",
                        .{err},
                    );
                    return;
                },
            }
        };
        defer _ = upzi.hidraw.closeDevice(device_fd) catch |err| {
            std.debug.print("Failed to close UPS device: {}!\n", .{err});
        };

        const query = try upzi.ups.query(device_fd);

        try upzi.ups.printStatus(stdout, query);
    }

    try stdout.flush();
}
