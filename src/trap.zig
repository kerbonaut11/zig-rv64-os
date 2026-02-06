const std = @import("std");
const uart = @import("uart.zig");
const csr = @import("csr.zig");
const KernelCtx = @import("KernelCtx.zig");
const log = std.log.scoped(.trap);

pub const Cause = enum(u64) {
    pub const interrupt_bit = 1 << 63;

    s_software_interrupt       = interrupt_bit|1,
    m_software_interrupt       = interrupt_bit|3,
    s_timer_interrupt          = interrupt_bit|5,
    m_timer_interrupt          = interrupt_bit|7,
    s_external_interrupt       = interrupt_bit|9,
    m_external_interrupt       = interrupt_bit|11,
    counter_overflow_interrupt = interrupt_bit|13,

    instruction_addres_misalinged = 0,
    instruction_acces_fault,
    illegal_instruction,
    breakpoint,
    load_addres_misaligned,
    load_acces_fault,
    store_addres_misaligned,
    store_acces_fault,
    ecall_from_u_mode,
    ecall_from_s_mode,
    ecall_from_m_mode = 11,
    instruction_page_fault,
    load_page_fault,
    store_page_fault = 15,
    double_trap,
    software_check = 18,
    hardware_error,
    _,
};

pub fn init() void {
    csr.write("mtvec", @intFromPtr(&trap));
    csr.write("medeleg", 0);
    csr.write("mideleg", 0);
    csr.write("mstatus", 0);
}

pub const Frame = extern struct {
    xregs: [32]u64,
    epc: u64,
    cause: Cause,
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
    frame.cause = @enumFromInt(csr.read("mcause"));
    frame.tval = csr.read("mtval");

    log.debug("epc   {x}", .{frame.epc});
    log.debug("cause {}",  .{frame.cause});
    log.debug("tval  {}",  .{frame.tval});

    csr.write("mepc",    frame.epc+4);
    csr.write("mstatus", (1 << 11));
}
