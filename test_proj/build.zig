const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get the fluentorm dependency (which brings pg.zig transitively)
    const fluentorm_dep = b.dependency("fluentorm", .{
        .target = target,
        .optimize = optimize,
    });

    const fluentorm = fluentorm_dep.module("fluentorm");

    // Library module
    const mod = b.addModule("test_proj", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    mod.addImport("fluentorm", fluentorm);

    // Main executable
    const exe = b.addExecutable(.{
        .name = "test_proj",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "test_proj", .module = mod },
                .{ .name = "fluentorm", .module = fluentorm },
            },
        }),
    });

    b.installArtifact(exe);

    // Run step
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Generate step - uses the fluentzig-gen CLI from the dependency
    // Step 1: Generate registry.zig and runner.zig
    const gen_step = b.step("generate", "Generate registry and runner from schemas");
    const gen_exe = fluentorm_dep.artifact("fluentzig-gen");
    const gen_cmd = b.addRunArtifact(gen_exe);
    gen_cmd.addArgs(&.{ "schemas", "src/models/generated", "migrations" });
    gen_step.dependOn(&gen_cmd.step);

    // Step 2: Run the generated runner to create model files
    const runner_exe = b.addExecutable(.{
        .name = "model-runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("schemas/runner.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "fluentorm", .module = fluentorm },
            },
        }),
    });
    const gen_models_step = b.step("generate-models", "Generate model files from schemas");
    gen_models_step.dependOn(&b.addRunArtifact(runner_exe).step);

    // Test step
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
