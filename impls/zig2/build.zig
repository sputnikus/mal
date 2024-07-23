const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const exes = [_]*std.Build.Step.Compile{
        b.addExecutable(.{
            .name = "step0_repl",
            .root_source_file = b.path("step0_repl.zig"),
            .target = target,
            .optimize = optimize,
        }),
        b.addExecutable(.{
            .name = "step1_read_print",
            .root_source_file = b.path("step1_read_print.zig"),
            .target = target,
            .optimize = optimize,
        }),
        b.addExecutable(.{
            .name = "step2_eval",
            .root_source_file = b.path("step2_eval.zig"),
            .target = target,
            .optimize = optimize,
        }),
        b.addExecutable(.{
            .name = "step3_env",
            .root_source_file = b.path("step3_env.zig"),
            .target = target,
            .optimize = optimize,
        }),
        b.addExecutable(.{
            .name = "step4_if_fn_do",
            .root_source_file = b.path("step4_if_fn_do.zig"),
            .target = target,
            .optimize = optimize,
        }),
        b.addExecutable(.{
            .name = "step5_tco",
            .root_source_file = b.path("step5_tco.zig"),
            .target = target,
            .optimize = optimize,
        }),
        b.addExecutable(.{
            .name = "step6_file",
            .root_source_file = b.path("step6_file.zig"),
            .target = target,
            .optimize = optimize,
        }),
    };

    for (exes) |exe| {
        exe.linkLibC();
        exe.linkSystemLibrary("pcre");
        exe.linkSystemLibrary("readline");
        const run_cmd = b.addRunArtifact(exe);
        const step = b.step(exe.name, exe.name);
        step.dependOn(&run_cmd.step);
        b.default_step.dependOn(&exe.step);
        b.installArtifact(exe);
    }
}
