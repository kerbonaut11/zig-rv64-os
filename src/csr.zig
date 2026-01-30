pub inline fn write(comptime name: []const u8, val: u64) void {
    asm volatile (
        "csrrw zero, " ++ name ++ ", %[val]" :: [val] "r" (val)
    );
}

pub inline fn clear(comptime name: []const u8, val: u64) void {
    asm volatile (
        "csrrc zero, " ++ name ++ ", %[val]" :: [val] "r" (val)
    );
}

pub inline fn set(comptime name: []const u8, val: u64) void {
    asm volatile (
        "csrrs zero, " ++ name ++ ", %[val]" :: [val] "r" (val)
    );
}

pub inline fn read(comptime name: []const u8) u64 {
    return asm volatile (
        "csrrsi %[ret], " ++ name ++ ", 0" : [ret] "=r" (-> u64) :
    );
}
