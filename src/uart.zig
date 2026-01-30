const std = @import("std");
const Writer = std.io.Writer;

const InterruptEnable = packed struct(u8) {
    data_read: bool,
    thr_empty: bool,
    line_rcv_status: bool,
    mode_status: bool,
    _pad: u2 = 0,
    dma_rx_end: bool,
    dma_tx_end: bool,
};

const FifoControl = packed struct(u8) {
    fifo_enable: bool,
    _pad: u7 = 0,
};

const LineControl = packed struct(u8) {
    word_len: u2,
    _pad: u6 = 0,
};

const LineStatus = packed struct(u8) {
    data_ready: bool,
    overrun_error: bool,
    parity_error: bool,
    framing_error: bool,
    break_interrupt: bool,
    thr_empty: bool,
    transmitter_empty: bool,
    fifo_data_error: bool,
};

const base_addr: [*]u8 = @ptrFromInt(0x10000000);
const data_reg: *volatile u8 = @ptrCast(base_addr+0);
const interrupt_enable: *volatile InterruptEnable = @ptrCast(base_addr+1);
const interrupt_status: *const volatile u8 = @ptrCast(base_addr+2);
const fifo_control: *volatile FifoControl = @ptrCast(base_addr+2);
const line_control: *volatile LineControl = @ptrCast(base_addr+3);
const modem_control: *volatile u8 = @ptrCast(base_addr+4);
const line_status: *const volatile LineStatus = @ptrCast(base_addr+5);
const modem_status: *const volatile u8 = base_addr+6;

pub fn init() void {
    interrupt_enable.* = .{
        .thr_empty = false,
        .data_read = false,
        .dma_rx_end = false,
        .dma_tx_end = false,
        .line_rcv_status = false,
        .mode_status = false,
    };

    fifo_control.* = .{
        .fifo_enable = true,
    };

    line_control.* = .{
        .word_len = 2,
    };
}


pub const writer: *Writer = &writer_inst;
var writer_buf: [64]u8 = undefined;
var writer_inst = std.io.Writer{
    .buffer = &writer_buf,
    .end = 0,
    .vtable = &.{
        .drain = &drain,
        .flush = &flush,
    },
};

fn drain(w: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
    const buffer = w.buffer[0..w.end];
    var bytes_written: usize = buffer.len;

    for (buffer) |byte| writeCh(byte);
    w.end = 0;

    for (data[0..data.len-1]) |bytes| {
        for (bytes) |byte| writeCh(byte);
        bytes_written += bytes.len;
    }

    for (0..splat) |_| {
        const bytes = data[data.len-1];
        for (bytes) |byte| writeCh(byte);
        bytes_written += bytes.len;
    }

    return bytes_written;
}

fn flush(w: *Writer) Writer.Error!void {
    for (w.buffer[0..w.end]) |byte| writeCh(byte);
    w.end = 0;
}


fn writeCh(ch: u8) void {
    while (!line_status.thr_empty) {}
    data_reg.* = ch;
}
