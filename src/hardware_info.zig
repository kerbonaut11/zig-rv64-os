const dev_tree = @import("device_tree.zig");

var device_tree: *dev_tree.Node = undefined;

pub fn init(fdt: *anyopaque) void {
    device_tree = dev_tree.parse(fdt) catch unreachable;
}
