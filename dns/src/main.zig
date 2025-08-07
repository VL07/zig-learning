const std = @import("std");

const packetParsing = @import("packatParsing.zig");
const BytePacketBuffer = @import("BytePacketBuffer.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const qname = "google.com";
    const qtype = packetParsing.QueryTypeEnum.a;

    // const client_addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 43210);
    var server_addr = std.net.Address.initIp4(.{ 8, 8, 8, 8 }, 53);
    const server_addr_len = server_addr.getOsSockLen();

    const socket = try std.posix.socket(
        std.posix.AF.INET,
        std.posix.SOCK.DGRAM,
        std.posix.IPPROTO.UDP,
    );
    defer std.posix.close(socket);

    // try std.posix.bind(socket, &client_addr.any, client_addr.getOsSockLen());

    var dns_packet = try packetParsing.DnsPacket.init(allocator);
    defer dns_packet.deinit();

    dns_packet.header.id = 6666;
    dns_packet.header.questions = 1;
    dns_packet.header.recursion_desired = true;
    try dns_packet.questions.append(try packetParsing.DnsQuestion.init(
        allocator,
        qname,
        qtype,
    ));

    var req_buf = BytePacketBuffer.init();
    try dns_packet.write(&req_buf);

    try server_addr.format("", .{}, std.io.getStdOut().writer());

    try std.posix.connect(socket, &server_addr.any, server_addr_len);

    _ = try std.posix.send(
        socket,
        req_buf.buf[0..],
        0,
    );

    var res_buf = BytePacketBuffer.init();
    _ = try std.posix.recv(
        socket,
        res_buf.buf[0..],
        0,
    );

    const res_packet = try packetParsing.DnsPacket.initFromBuf(allocator, &res_buf);
    defer res_packet.deinit();

    std.debug.print("{any}", .{res_packet.header});

    for (res_packet.answers.items) |answer| {
        std.debug.print("{any}", .{answer});
    }
}
