const std = @import("std");
const zon = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    // Disable suppoort for other operating systems
    if (target.result.os.tag == .windows) {
        @panic("Mocosoft Winbugs is ESPECIALLY not supported!");
    }

    if (target.result.os.tag != .linux) {
        @panic("Only GNU/Linux-libre and GNU/Linux systems are supported!");
    }

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", zon.version);

    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("upzi", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "upzi",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = true,
            .imports = &.{
                .{ .name = "upzi", .module = mod },
            },
        }),
    });

    exe.root_module.addOptions("build_options", build_options);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
