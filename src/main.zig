const std = @import("std");
const uart = @import("uart.zig");
const trap = @import("trap.zig");
const KernelCtx = @import("KernelCtx.zig");

pub const panic = std.debug.FullPanic(panicHandler);
fn panicHandler(msg: []const u8, return_addr: ?usize) noreturn {
    _ = return_addr;
    uart.writer.print("\npanic: {s}", .{msg}) catch {};
    uart.writer.flush() catch {};
    while (true) {}
}


export fn kmain() noreturn {
    uart.init();
    KernelCtx.init();
    trap.init();

    asm volatile ("ecall");
    while (true) {}
}
