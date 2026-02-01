const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Export as a module so other projects can `@import("chesszig")`
    const mod = b.addModule("ChessZig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.addModule("chesssCli", .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/main.zig"),
    });

    const lib = b.addLibrary(.{
        .name = "ChessZig",
        .root_module = mod,
    });

    const exe = b.addExecutable(.{
        .root_module = exe_mod,
        .name = "chesszig-cli",
    });

    b.installArtifact(exe);
    // Install the library
    b.installArtifact(lib);

    // Allow `@import("chesszig")` in main.zig
    exe.root_module.addImport("chessZig", mod);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Build and run the chess engine");
    run_step.dependOn(&run_cmd.step);

    // =========================
    // Tests
    // =========================
    const tests = b.addTest(.{
        .root_module = mod,
    });

    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
