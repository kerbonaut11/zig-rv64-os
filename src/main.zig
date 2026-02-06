const std = @import("std");
const uart = @import("uart.zig");
const trap = @import("trap.zig");
const page = @import("page.zig");
const KernelCtx = @import("KernelCtx.zig");
pub const std_options: std.Options = .{
    .logFn = logFn,
};

fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    uart.writer.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
    uart.writer.flush() catch return;
}

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
    page.init();

    asm volatile ("ecall");
    asm volatile ("ecall");
    while (true) {}
}
