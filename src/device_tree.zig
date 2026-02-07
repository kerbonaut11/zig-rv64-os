const std = @import("std");
const log = std.log.scoped(.device_tree);

pub const Header = extern struct {
    pub const expected_magic = 0xd00dfeed;
    magic: u32,
    totalsize: u32,
    off_dt_struct: u32,
    off_dt_strings: u32,
    off_mem_rsvmap: u32,
    version: u32,
    last_comp_version: u32,
    boot_cpuid_phys: u32,
    size_dt_strings: u32,
    size_dt_struct: u32,
};

pub const ReserveEntry = extern struct {
    addres: u64,
    size: u64,
};

pub const begin_node_token: u32 = 1;
pub const end_node_token: u32 = 2;
pub const prop_token: u32 = 3;
pub const nop_token: u32 = 4;
pub const end_token: u32 = 9;

pub const Prop = extern struct {
    len: u32,
    nameoff: u32,

    const Name = enum {
        @"#address-cells",
        @"#size-cells",
        phandle,
        model,
        compatible,
        reg,
        unkown,
    };
};


pub const Node = struct {
    const RegEntry = struct {ptr: ?*anyopaque, size: usize};

    name: []const u8,
    compatible: []const u8 = "",
    model: []const u8 = "",
    phandle: u32 = 0,
    reg: []RegEntry = &.{},
};

const Error = error{BadDeviceTree}||std.mem.Allocator.Error;

pub fn parse(fdt: *anyopaque) Error!*Node {
    const header: *Header = @ptrCast(@alignCast(fdt));
    std.mem.byteSwapAllFields(Header, header);

    if (header.magic != Header.expected_magic) {
        return error.BadDeviceTree;
    }

    const mem_rsvmap_start: [*]ReserveEntry = @ptrFromInt(@intFromPtr(header) + header.off_mem_rsvmap);
    const mem_rsvmap_len = (header.off_dt_struct-header.off_mem_rsvmap)/@sizeOf(ReserveEntry);
    const mem_rsvmap = mem_rsvmap_start[0..mem_rsvmap_len];
    std.mem.byteSwapAllElements(ReserveEntry, mem_rsvmap);

    const dt_strings = @as([*]u8, @ptrCast(header))[header.off_dt_strings..][0..header.size_dt_strings];

    const dt_ptr: [*]u32 = @ptrFromInt(@intFromPtr(header) + header.off_dt_struct);
    var allocator = std.heap.FixedBufferAllocator.init(&buffer);
    var p = Parser{.ptr = dt_ptr, .strings = dt_strings, .allocator = allocator.allocator()};

    const root = p.parseNode() catch unreachable;
    if (p.nextToken() != end_token) {
        return error.BadDeviceTree;
    }

    return root;
}

fn cstrToSlice(ptr: [*c]const u8) [:0]const u8 {
    return ptr[0..std.mem.indexOfSentinel(u8, 0, ptr) :0];
}

var buffer: [4*4096]u8 = undefined;

const Parser = struct {
    ptr: [*]u32,
    strings: []const u8,
    address_cells: u32 = 0,
    size_cells: u32 = 0,
    allocator: std.mem.Allocator,

    pub fn nextToken(p: *Parser) u32 {
        const token = p.peekToken();
        p.ptr += 1;
        return token;
    }

    pub fn peekToken(p: *Parser) u32 {
        p.skipNops();
        return std.mem.bigToNative(u32, p.ptr[0]);
    }

    pub fn skipNops(p: *Parser) void {
        while (std.mem.bigToNative(u32, p.ptr[0]) == nop_token) {
            p.ptr += 1;
        }
    }

    pub fn alignForward(p: *Parser, bytes: usize) void {
        const size = std.mem.alignForward(usize, bytes, 4)/4;
        p.ptr += size;
    }

    pub fn takeNameAlloc(p: *Parser) Error![]u8 {
        const name = cstrToSlice(@ptrCast(p.ptr));
        const alloc = try p.allocator.alloc(u8, name.len);
        @memcpy(alloc, name);
        p.alignForward(name.len+1);
        return alloc;
    }

    pub fn parseNode(p: *Parser) Error!*Node {
        if (p.nextToken() != begin_node_token) {
            return error.BadDeviceTree;
        }

        var node = try p.allocator.create(Node);
        node.* = .{.name = try p.takeNameAlloc()};
        if (node.name.len == 0) node.name = "/";

        const parent_address_cells = p.address_cells;
        const parent_size_cells = p.size_cells;

        while (p.peekToken() == prop_token) {
            _ = p.nextToken();

            const prop: *Prop = @ptrCast(p.ptr);
            std.mem.byteSwapAllFields(Prop, prop);
            p.ptr += 2;

            const name = cstrToSlice(@ptrCast(p.strings[prop.nameoff..]));

            switch (std.meta.stringToEnum(Prop.Name, name) orelse Prop.Name.unkown) {
                .@"#address-cells" => p.address_cells = std.mem.bigToNative(u32, p.ptr[0]),
                .@"#size-cells" => p.size_cells = std.mem.bigToNative(u32, p.ptr[0]),
                .phandle => node.phandle = std.mem.bigToNative(u32, p.ptr[0]),

                .model => {
                    const model =  try p.allocator.alloc(u8, prop.len-1);
                    @memcpy(model, @as([*]u8, @ptrCast(p.ptr))[0..prop.len-1]);
                    node.model = model;
                },
                .compatible => {
                    const compatible = try p.allocator.alloc(u8, prop.len-1);
                    @memcpy(compatible, @as([*]u8, @ptrCast(p.ptr))[0..prop.len-1]);
                    node.compatible = compatible;
                },

                .reg => {
                    const cells_per_entry = parent_address_cells+parent_size_cells;
                    node.reg = try p.allocator.alloc(Node.RegEntry, @divExact(prop.len, cells_per_entry*@sizeOf(u32)));

                    for (node.reg, 0..) |*reg, i| {
                        const ptr = @as([*]u8, @ptrCast(p.ptr)) + i*cells_per_entry;

                        reg.ptr = switch (parent_address_cells) {
                            0 => null,
                            1 => @ptrFromInt(std.mem.readInt(u32, @ptrCast(ptr), .big)),
                            2 => @ptrFromInt(std.mem.readInt(u64, @ptrCast(ptr), .big)),
                            else => return error.BadDeviceTree,
                        };

                        reg.size = switch (parent_size_cells) {
                            0 => 0,
                            1 => std.mem.readInt(u32, @ptrCast(ptr+parent_address_cells), .big),
                            2 => std.mem.readInt(u64, @ptrCast(ptr+parent_address_cells), .big),
                            else => return error.BadDeviceTree,
                        };
                    }

                },

                .unkown => log.warn("unkown property {s} on {s}", .{name, node.name}),
            }

            p.alignForward(prop.len);
        }

        log.debug("{{\n name: {s}\n model: {s}\n compatible: {s}\n}}", .{node.name, node.model, node.compatible});

        while (p.peekToken() != end_node_token) {
            _ = try parseNode(p);
        }
        _ = p.nextToken();

        return node;
    }
};
