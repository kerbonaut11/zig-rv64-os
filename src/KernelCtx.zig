const std = @import("std");
const trap = @import("trap.zig");
const uart = @import("uart.zig");
const csr = @import("csr.zig");
const Ctx = @This();

trap_frame: trap.Frame,
gp: u64,

var instance: Ctx = undefined;

pub fn init() void {
    instance.trap_frame = std.mem.zeroes(trap.Frame);
    instance.gp = asm ("mv %[ret], gp" : [ret] "=r" (-> u64));
    csr.write("sscratch", @intFromPtr(&instance));
}

pub fn get() *Ctx {
    return @ptrFromInt(csr.read("sscratch"));
}
