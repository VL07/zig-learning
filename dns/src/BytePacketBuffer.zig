const std = @import("std");

const BytePacketBuffer = @This();

pub const BytePacketBufferError = error{
    EndOfBuffer,
    JumpLimitExceeded,
    LabelTooLong,
};

buf: [512]u8,
pos: usize,

pub fn init() BytePacketBuffer {
    return BytePacketBuffer{
        .buf = undefined,
        .pos = 0,
    };
}

pub fn step(self: *BytePacketBuffer, steps: usize) BytePacketBufferError!void {
    self.pos += steps;
}

pub fn seek(self: *BytePacketBuffer, pos: usize) BytePacketBufferError!void {
    self.pos = pos;
}

pub fn read(self: *BytePacketBuffer) BytePacketBufferError!u8 {
    if (self.pos >= 512) {
        return BytePacketBufferError.EndOfBuffer;
    }

    const res = self.buf[self.pos];
    self.pos += 1;

    return res;
}

pub fn get(self: *BytePacketBuffer, pos: usize) BytePacketBufferError!u8 {
    if (pos >= 512) {
        return BytePacketBufferError.EndOfBuffer;
    }

    return self.buf[pos];
}

pub fn getRange(self: *BytePacketBuffer, start: usize, len: usize) BytePacketBufferError![]const u8 {
    if (start + len >= 512) {
        return BytePacketBufferError.EndOfBuffer;
    }

    return self.buf[start..(start + len)];
}

pub fn readRange(self: *BytePacketBuffer, len: usize) BytePacketBufferError![]const u8 {
    const slice = try self.getRange(self.pos, len);
    self.pos += len;

    return slice;
}

pub fn readU16(self: *BytePacketBuffer) BytePacketBufferError!u16 {
    const high = @as(u16, try self.read()) << 8;
    const low = @as(u16, try self.read());

    return high | low;
}

pub fn readU32(self: *BytePacketBuffer) BytePacketBufferError!u32 {
    const res = (@as(u32, try self.read()) << 24) | (@as(u32, try self.read()) << 16) | (@as(u32, try self.read()) << 8) | (@as(u32, try self.read()));

    return res;
}

pub fn readQname(self: *BytePacketBuffer, allocator: std.mem.Allocator) ![]u8 {
    var out_str = std.ArrayList(u8).init(allocator);
    defer out_str.deinit();

    var pos = self.pos;
    var jumped = false;
    const max_jumps = 5;
    var jumps_performed: u8 = 0;

    var add_delim = false;

    while (true) {
        if (jumps_performed > max_jumps) {
            return BytePacketBufferError.JumpLimitExceeded;
        }

        const len = try self.get(pos);

        if ((len & 0xC0) == 0xC0) {
            if (!jumped) {
                try self.seek(pos + 2);

                jumped = true;
            }

            const b2 = @as(u16, try self.get(pos + 1));
            const offset = ((@as(u16, len) ^ 0xC0) << 8) | b2;
            pos = @as(usize, offset);

            jumps_performed += 1;

            continue;
        }

        pos += 1;
        if (len == 0) {
            break;
        }

        if (add_delim) {
            try out_str.append('.');
        }

        const label_slice = try self.getRange(pos, @as(usize, len));
        const label_slice_lower = try allocator.alloc(u8, label_slice.len);
        defer allocator.free(label_slice_lower);

        _ = std.ascii.lowerString(label_slice_lower, label_slice);
        try out_str.appendSlice(label_slice_lower);

        add_delim = true;
        pos += @as(usize, len);
    }

    if (!jumped) {
        try self.seek(pos);
    }

    return out_str.toOwnedSlice();
}

pub fn writeU8(self: *BytePacketBuffer, val: u8) BytePacketBufferError!void {
    if (self.pos >= 512) {
        return BytePacketBufferError.EndOfBuffer;
    }

    self.buf[self.pos] = val;
    self.pos += 1;
}

pub fn writeU16(self: *BytePacketBuffer, val: u16) BytePacketBufferError!void {
    try self.writeU8(@intCast(val >> 8));
    try self.writeU8(@intCast(val & 0xFF));
}

pub fn writeU32(self: *BytePacketBuffer, val: u32) BytePacketBufferError!void {
    try self.writeU16(@intCast(val >> 16));
    try self.writeU16(@intCast(val & 0xFF));
}

pub fn write_qname(self: *BytePacketBuffer, qname: []const u8) BytePacketBufferError!void {
    var iterator = std.mem.splitScalar(u8, qname, '.');
    while (iterator.next()) |label| {
        if (label.len >= 0x3F) {
            return BytePacketBufferError.LabelTooLong;
        }

        try self.writeU8(@intCast(label.len));
        for (label) |byte| {
            try self.writeU8(byte);
        }
    }

    try self.writeU8(0);
}
