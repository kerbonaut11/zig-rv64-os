const std = @import("std");
const uart = @import("uart.zig");

pub const panic = std.debug.FullPanic(panicHandler);
fn panicHandler(msg: []const u8, return_addr: ?usize) noreturn {
    _ = return_addr;
    uart.writer.print("\npanic: {s}", .{msg}) catch {};
    uart.writer.flush() catch {};
    while (true) {}
}


export fn kmain() noreturn {
    _ = uart.writer.print("Hello, World!", .{}) catch {};
    uart.writer.flush() catch {};

    while (true) {}
}
