const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const integrated_test_mod = b.createModule(.{
        .root_source_file = b.path("test/integrated.zig"),
        .target = target,
        .optimize = optimize,
    });

    integrated_test_mod.addImport("http_lib", lib_mod);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "http",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const integrated_test = b.addExecutable(.{ .name = "integrated_test", .root_module = integrated_test_mod });

    b.installArtifact(integrated_test);

    const run_integrated_test_cmd = b.addRunArtifact(integrated_test);
    run_integrated_test_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_integrated_test_cmd.addArgs(args);
    }

    const integrated_test_step = b.step("integrated-test", "Run integrated test");
    integrated_test_step.dependOn(&run_integrated_test_cmd.step);
}
