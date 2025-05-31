const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const z2z = b.addExecutable(.{
        .name = "z2z",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zig_aio = b.dependency("aio", .{});

    z2z.root_module.addImport("aio", zig_aio.module("aio"));
    z2z.root_module.addImport("coro", zig_aio.module("coro"));

    const flags = b.dependency("flags", .{ .target = target, .optimize = optimize });
    z2z.root_module.addImport("flags", flags.module("flags"));

    b.installArtifact(z2z);

    const run_z2z_cmd = b.addRunArtifact(z2z);

    run_z2z_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_z2z_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_z2z_step = b.step("z2z", "Run the app");
    run_z2z_step.dependOn(&run_z2z_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("test/tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    test_step.dependOn(&run_exe_unit_tests.step);
}
