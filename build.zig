const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const fluentzig = b.addModule("fluentorm", .{
        .root_source_file = b.path("src/root.zig"),
    });

    const pg = b.dependency("pg", .{
        .target = target,
        .optimize = optimize,
    });

    // Generator executable - Standalone model generator
    const gen_exe = b.addExecutable(.{
        .name = "fluentzig-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/generate_model.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "fluentorm", .module = fluentzig },
                .{ .name = "pg", .module = pg.module("pg") },
            },
        }),
    });

    b.installArtifact(gen_exe);

    // Run step for local testing
    const run_cmd = b.addRunArtifact(gen_exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the generator");
    run_step.dependOn(&run_cmd.step);

    // Test step
    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pg", .module = pg.module("pg") },
            },
        }),
    });

    const run_lib_tests = b.addRunArtifact(lib_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_tests.step);

    // Help step
    const help_step = b.step("help", "Show help information");
    _ = help_step;
}
