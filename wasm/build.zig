const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard optimization options
    const optimize = b.standardOptimizeOption(.{});
    
    // WASM target
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    
    // Create WASM library
    const wasm_lib = b.addStaticLibrary(.{
        .name = "zeke-wasm",
        .root_source_file = b.path("src/wasm.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    
    // Add dependencies
    const zsync = b.dependency("zsync", .{});
    const zqlite = b.dependency("zqlite", .{});
    const flash = b.dependency("flash", .{});
    const zcrypto = b.dependency("zcrypto", .{});
    const phantom = b.dependency("phantom", .{});
    const shroud = b.dependency("shroud", .{});
    
    wasm_lib.root_module.addImport("zsync", zsync.module("zsync"));
    wasm_lib.root_module.addImport("zqlite", zqlite.module("zqlite"));
    wasm_lib.root_module.addImport("flash", flash.module("flash"));
    wasm_lib.root_module.addImport("zcrypto", zcrypto.module("zcrypto"));
    wasm_lib.root_module.addImport("phantom", phantom.module("phantom"));
    wasm_lib.root_module.addImport("shroud", shroud.module("shroud"));
    
    // Configure for WASM
    wasm_lib.entry = .disabled;
    wasm_lib.rdynamic = true;
    
    // Install WASM artifact
    b.installArtifact(wasm_lib);
    
    // Create JavaScript bindings
    const js_step = b.addRunArtifact(wasm_lib);
    js_step.step.dependOn(&wasm_lib.step);
    
    // Test step for WASM
    const wasm_test = b.addTest(.{
        .root_source_file = b.path("src/wasm.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    
    const run_wasm_test = b.addRunArtifact(wasm_test);
    const test_step = b.step("test-wasm", "Run WASM tests");
    test_step.dependOn(&run_wasm_test.step);
    
    // Regular native build
    const native_target = b.standardTargetOptions(.{});
    
    const exe = b.addExecutable(.{
        .name = "zeke",
        .root_source_file = b.path("src/main.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    
    exe.root_module.addImport("zsync", zsync.module("zsync"));
    exe.root_module.addImport("zqlite", zqlite.module("zqlite"));
    exe.root_module.addImport("flash", flash.module("flash"));
    exe.root_module.addImport("zcrypto", zcrypto.module("zcrypto"));
    exe.root_module.addImport("phantom", phantom.module("phantom"));
    exe.root_module.addImport("shroud", shroud.module("shroud"));
    
    b.installArtifact(exe);
    
    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
    
    // Tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_native_step = b.step("test", "Run unit tests");
    test_native_step.dependOn(&run_unit_tests.step);
    
    // Arch Linux package step
    const arch_step = b.step("arch-package", "Build Arch Linux package");
    const arch_cmd = b.addSystemCommand(&.{
        "makepkg", "-f", "--clean", "--install"
    });
    arch_cmd.cwd = b.path("packaging/arch");
    arch_step.dependOn(&arch_cmd.step);
    
    // Performance benchmark step
    const bench_exe = b.addExecutable(.{
        .name = "zeke-bench",
        .root_source_file = b.path("benchmark/main.zig"),
        .target = native_target,
        .optimize = .ReleaseFast,
    });
    
    const bench_run = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run performance benchmarks");
    bench_step.dependOn(&bench_run.step);
}