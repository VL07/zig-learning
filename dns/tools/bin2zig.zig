const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const file = try std.fs.cwd().openFile("response_packet.txt", .{});
    defer file.close();

    const data = try file.readToEndAlloc(allocator, 1 << 24);
    defer allocator.free(data);

    try std.io.getStdOut().writer().print("const bin_data: []const u8 = &[_]u8{{\n", .{});
    var i: usize = 0;
    for (data) |b| {
        try std.io.getStdOut().writer().print("0x{X:0>2}", .{b});
        if (i != data.len - 1) try std.io.getStdOut().writer().writeAll(", ");
        if ((i + 1) % 12 == 0) try std.io.getStdOut().writer().writeAll("\n");

        i += 1;
    }
    try std.io.getStdOut().writer().print("\n}};\n", .{});
}
