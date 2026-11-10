const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Io = std.Io;
const log = std.log;

const fatal = std.process.fatal;

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

    const verbose = opts.verbose;

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

    if (opts.list) {
        const device_path = upzi.hidraw.discoverUPS(arena, io) catch {
            fatal("No 0665:5161 device found; check lsusb\n", .{});
        };

        if (verbose) {
            log.info("mode=list", .{});
            log.info("found device: {s}", .{device_path});
        }

        try stdout.print("{s}\n", .{device_path});
        try stdout.flush();
        return;
    }

    if (opts.json) {
        const device_path = upzi.hidraw.discoverUPS(arena, io) catch {
            fatal("No 0665:5161 device found; check lsusb\n", .{});
        };

        const device_fd = upzi.hidraw.openDevice(device_path) catch |err| {
            switch (err) {
                error.AccessDenied => {
                    fatal(
                        "Wrong permissions to open {s}, check your udev rules!\n",
                        .{device_path},
                    );
                },
                error.FileNotFound => {
                    fatal(
                        "Device {s} was not found mounted or was disconnected!\n",
                        .{device_path},
                    );
                },
                else => {
                    fatal(
                        "Unhandled error {}, please send it to the maintainers!\n",
                        .{err},
                    );
                },
            }
        };

        defer _ = upzi.hidraw.closeDevice(device_fd) catch |err| {
            fatal("Failed to close UPS device: {}!\n", .{err});
        };

        if (verbose) {
            log.info("mode=json", .{});
            log.info(
                "device={s} fd={d}",
                .{ device_path, device_fd },
            );
        }

        const query = try upzi.ups.query(device_fd);

        try upzi.ups.printJSON(stdout, query);
        try stdout.flush();
        return;
    }

    if (opts.once) {
        const device_path = upzi.hidraw.discoverUPS(arena, io) catch {
            fatal("No 0665:5161 device found; check lsusb\n", .{});
        };

        const device_fd = upzi.hidraw.openDevice(device_path) catch |err| {
            switch (err) {
                error.AccessDenied => {
                    fatal(
                        "Wrong permissions to open {s}, check your udev rules!\n",
                        .{device_path},
                    );
                },
                error.FileNotFound => {
                    fatal(
                        "Device {s} was not found mounted or was disconnected!\n",
                        .{device_path},
                    );
                },
                else => {
                    fatal(
                        "Unhandled error {}, please send it to the maintainers!\n",
                        .{err},
                    );
                },
            }
        };
        defer _ = upzi.hidraw.closeDevice(device_fd) catch |err| {
            fatal("Failed to close UPS device: {}!\n", .{err});
        };

        if (verbose) {
            log.info("mode=once", .{});
            log.info(
                "device={s} fd={d}",
                .{ device_path, device_fd },
            );
        }

        const query = try upzi.ups.query(device_fd);

        try upzi.ups.printStatus(stdout, query);
    }

    try stdout.flush();
}
