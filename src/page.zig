const std = @import("std");
const csr = @import("csr.zig");

pub const Entry = packed struct(u64) {
    valid: bool = true,
    read: bool = true,
    write: bool = true,
    exec: bool = true,
    user: bool = false,
    global: bool = true,
    accesed: bool = false,
    dirty: bool = false,
    _pad1: u2 = 0,
    addr: u44,
    _pad2: u10 = 0,
};

pub const Table = [512]Entry;

pub var l3 align(4096) = std.mem.zeroes(Table);

pub fn init() void {
    //if we dont do this QEMU will raise an illegal-instruction-flault for mret
    csr.write("pmpcfg0", 0b00001111);
    csr.write("pmpaddr0", std.math.maxInt(u64));

    for (&l3, 0..) |*entry, i| {
        entry.* = .{
            .addr = @as(u44, @intCast(i)) << 18,
        };
    }

    asm volatile ("sfence.vma zero, zero");
    csr.write("satp", (@intFromPtr(&l3) >> 12) | (8 << 60));
    csr.write("mstatus", (1 << 11) | (1 << 5));

    asm volatile (
        \\auipc t0, 0
        \\addi  t0, t0, 16
        \\csrw  mepc, t0
        \\mret
    );
}
