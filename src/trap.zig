const std = @import("std");
const uart = @import("uart.zig");
const csr = @import("csr.zig");
const KernelCtx = @import("KernelCtx.zig");
const log = std.log.scoped(.trap);

pub fn init() void {
    csr.write("mtvec", @intFromPtr(&trap));
    csr.write("medeleg", 0);
    csr.write("mideleg", 0);
    csr.write("mstatus", 0);
}

pub const Frame = extern struct {
    xregs: [32]u64,
    epc: u64,
    cause: u64,
    tval: u64,
};

pub fn loadRegsAsm() []const u8 {
    comptime var code: []const u8 = "\n";
    for (1..31) |i| {
        code = code ++ std.fmt.comptimePrint("sd x{}, {}(x31)\n", .{i, i*@sizeOf(u64)});
    }

    return code;
}

pub fn restoreRegsAsm() []const u8 {
    comptime var code: []const u8 = "\n";
    for (1..32) |i| {
        code = code ++ std.fmt.comptimePrint("ld x{}, {}(x31)\n", .{i, i*@sizeOf(u64)});
    }

    return code;
}

pub export fn trap() align(4) callconv(.naked) void {
    @setEvalBranchQuota(1_000_000);
    asm volatile (
        \\csrrw x31, sscratch, x31
        ++ loadRegsAsm() ++
        \\mv t0, x31
        \\csrrw x31, sscratch, x31
        \\sd x31, 8*31(t0)
        \\ld gp, %[gp_offset](t0)
        \\la sp, stack_top
        \\call trapInner
        \\csrr x31, sscratch
        ++ restoreRegsAsm() ++ 
        \\mret
        :: [gp_offset] "i" (@offsetOf(KernelCtx, "gp")),
    );
}

export fn trapInner() void {
    const frame: *Frame = &KernelCtx.get().trap_frame;
    frame.epc = csr.read("mepc");
    frame.cause = csr.read("mcause");
    frame.tval = csr.read("mtval");

    log.debug("epc   {x}", .{frame.epc});
    log.debug("cause {}",  .{frame.cause});
    log.debug("tval  {}",  .{frame.tval});

    csr.write("mepc",    frame.epc+4);
    csr.write("mstatus", (1 << 11));
}
