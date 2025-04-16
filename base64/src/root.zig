//! A simple base64 encoder and deocder library. Doesn't support custom charsets.

const std = @import("std");

/// Base struct for handling base64.
pub const Base64 = struct {
    _table: *const [64]u8,

    pub fn init() Base64 {
        const upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        const lower = "abcdefghijklmnopqrstuvwxyz";
        const numbers_symb = "0123456789+/";

        return Base64{ ._table = upper ++ lower ++ numbers_symb };
    }

    /// Encodes base64.
    pub fn encode(self: Base64, allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        if (input.len == 0) return "";

        const n_out = try calc_encode_length(input);
        var out = try allocator.alloc(u8, n_out);
        var buf = [3]u8{ 0, 0, 0 };
        var count: u8 = 0;
        var iout: u64 = 0;

        for (input, 0..) |_, i| {
            buf[count] = input[i];
            count += 1;

            if (count != 3) continue;

            out[iout] = self.char_at(buf[0] >> 2);
            out[iout + 1] = self.char_at(((buf[0] & 0x03) << 4) + (buf[1] >> 4));
            out[iout + 2] = self.char_at(((buf[1] & 0xf) << 2) + (buf[2] >> 6));
            out[iout + 3] = self.char_at(buf[2] & 0x3f);

            iout += 4;
            count = 0;
        }

        if (count == 1) {
            out[iout] = self.char_at(buf[0] >> 2);
            out[iout + 1] = self.char_at((buf[0] & 0x03) << 4);
            out[iout + 2] = '=';
            out[iout + 3] = '=';
        }

        if (count == 2) {
            out[iout] = self.char_at(buf[0] >> 2);
            out[iout + 1] = self.char_at(((buf[0] & 0x03) << 4) + (buf[1] >> 4));
            out[iout + 2] = self.char_at((buf[1] & 0x0f) << 2);
            out[iout + 3] = '=';
            iout += 4;
        }

        return out;
    }

    /// Decodes base64.
    pub fn decode(self: Base64, allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        if (input.len == 0) return "";

        const n_out = try calc_decode_length(input);
        var out = try allocator.alloc(u8, n_out);
        var count: u8 = 0;
        var iout: u64 = 0;
        var buf = [4]u8{ 0, 0, 0, 0 };

        for (0..input.len) |i| {
            buf[count] = self.char_index(input[i]);
            count += 1;

            if (count != 4) continue;

            out[iout] = (buf[0] << 2) + (buf[1] >> 4);
            if (buf[2] != 64) {
                out[iout + 1] = (buf[1] << 4) + (buf[2] >> 2);
            }
            if (buf[3] != 64) {
                out[iout + 2] = (buf[2] << 6) + buf[3];
            }

            iout += 3;
            count = 0;
        }

        return out;
    }

    fn char_at(self: Base64, index: usize) u8 {
        return self._table[index];
    }

    fn char_index(self: Base64, char: u8) u8 {
        if (char == '=') return 64;

        var index: u8 = 0;
        for (0..63) |i| {
            if (self.char_at(i) == char) break;

            index += 1;
        }

        return index;
    }
};

fn calc_encode_length(input: []const u8) !usize {
    if (input.len < 3) return 4;

    const n_groups = try std.math.divCeil(usize, input.len, 3);

    return n_groups * 4;
}

fn calc_decode_length(input: []const u8) !usize {
    if (input.len < 4) return 3;

    const n_groups = try std.math.divFloor(usize, input.len, 4);
    var multiple_groups: usize = n_groups * 3;
    var i: usize = input.len - 1;

    while (i > 0) : (i -= 1) {
        if (input[i] != '=') break;

        multiple_groups -= 1;
    }

    return multiple_groups;
}

test "expect correct character at index 28" {
    const base64 = Base64.init();

    try std.testing.expectEqual('c', base64.char_at(28));
}

test "expect correct index for character 'c'" {
    const base64 = Base64.init();

    try std.testing.expectEqual(28, base64.char_index('c'));
}

test "expect correct encode" {
    const base64 = Base64.init();

    const payload = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. ";
    const expected = "TG9yZW0gaXBzdW0gZG9sb3Igc2l0IGFtZXQsIGNvbnNlY3RldHVyIGFkaXBpc2NpbmcgZWxpdCwgc2VkIGRvIGVpdXNtb2QgdGVtcG9yIGluY2lkaWR1bnQgdXQgbGFib3JlIGV0IGRvbG9yZSBtYWduYSBhbGlxdWEuIA==";

    const encoded = try base64.encode(std.testing.allocator, payload);
    defer std.testing.allocator.free(encoded);

    try std.testing.expectEqualStrings(expected, encoded);
}

test "expect correct decode" {
    const base64 = Base64.init();

    const payload = "TG9yZW0gaXBzdW0gZG9sb3Igc2l0IGFtZXQsIGNvbnNlY3RldHVyIGFkaXBpc2NpbmcgZWxpdCwgc2VkIGRvIGVpdXNtb2QgdGVtcG9yIGluY2lkaWR1bnQgdXQgbGFib3JlIGV0IGRvbG9yZSBtYWduYSBhbGlxdWEuIA==";
    const expected = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. ";

    const decoded = try base64.decode(std.testing.allocator, payload);
    defer std.testing.allocator.free(decoded);

    try std.testing.expectEqualStrings(expected, decoded);
}

test "expect correct encode and decode" {
    const base64 = Base64.init();

    const payload = "This is a payload with some special characters also. 123abcåäö";

    const encoded = try base64.encode(std.testing.allocator, payload);
    defer std.testing.allocator.free(encoded);

    const decoded = try base64.decode(std.testing.allocator, encoded);
    defer std.testing.allocator.free(decoded);

    try std.testing.expectEqualStrings(payload, decoded);
}

test "expect correct encoded and decoded empty payload" {
    const base64 = Base64.init();

    const payload = "";

    const encoded = try base64.encode(std.testing.allocator, payload);
    defer std.testing.allocator.free(encoded);

    const decoded = try base64.decode(std.testing.allocator, encoded);
    defer std.testing.allocator.free(decoded);

    try std.testing.expectEqualStrings(payload, decoded);
}
