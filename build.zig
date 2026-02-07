const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .riscv64,
        .os_tag = .freestanding,
        .cpu_features_sub = std.Target.riscv.featureSet(&.{.c}),
    });

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_module = b.addModule("kernel", .{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = b.standardOptimizeOption(.{}),
            .omit_frame_pointer = true,
            .code_model = .medany,
        }),
    });
    
    kernel.root_module.addAssemblyFile(b.path("src/boot.S"));
    kernel.setLinkerScript(b.path("linker.ld"));

    b.installArtifact(kernel);

    const debug = b.option(bool, "qemu-gdb", "") != null;

    const run_command = b.addSystemCommand(&.{"qemu-system-riscv64", "-machine", "virt", "-bios", "none", "-nographic",});
    run_command.addArg("-kernel");
    run_command.addFileArg(kernel.getEmittedBin());
    if (debug) run_command.addArgs(&.{"-s", "-S"});
    const run_step = b.step("run", "run the os with qemu");
    run_step.dependOn(&run_command.step);
}
