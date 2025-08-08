const std = @import("std");

const packetParsing = @import("packatParsing.zig");
const BytePacketBuffer = @import("BytePacketBuffer.zig");

fn lookup(allocator: std.mem.Allocator, qname: []const u8, qtype: packetParsing.QueryType) !packetParsing.DnsPacket {
    var server_addr = std.net.Address.initIp4(.{ 8, 8, 8, 8 }, 53);

    const socket = try std.posix.socket(
        std.posix.AF.INET,
        std.posix.SOCK.DGRAM,
        std.posix.IPPROTO.UDP,
    );
    defer std.posix.close(socket);

    try std.posix.connect(socket, &server_addr.any, server_addr.getOsSockLen());

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

    return res_packet;
}

fn handleQuery(allocator: std.mem.Allocator, socket: anytype) !void {
    var req_buf = BytePacketBuffer.init();

    var client_addr: std.posix.sockaddr = undefined;
    var client_addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);

    _ = try std.posix.recvfrom(
        socket,
        &req_buf.buf,
        0,
        &client_addr,
        &client_addr_len,
    );

    var req_packet = try packetParsing.DnsPacket.initFromBuf(allocator, &req_buf);
    defer req_packet.deinit();

    var res_packet = try packetParsing.DnsPacket.init(allocator);
    defer res_packet.deinit();

    res_packet.header.id = req_packet.header.id;
    res_packet.header.recursion_desired = true;
    res_packet.header.recursion_available = true;
    res_packet.header.response = true;

    if (req_packet.questions.pop()) |question| {
        std.debug.print("Got query for {s}\n", .{question.name});

        if (lookup(
            allocator,
            question.name,
            question.qtype,
        )) |lookup_res| {
            try res_packet.questions.append(try packetParsing.DnsQuestion.init(
                allocator,
                question.name,
                question.qtype,
            ));
            res_packet.header.rescode = lookup_res.header.rescode;

            for (lookup_res.answers.items) |answer| {
                std.debug.print("{any}\n", .{answer});
                try res_packet.answers.append(try answer.clone(allocator));
            }

            for (lookup_res.authorities.items) |authority| {
                std.debug.print("{any}\n", .{authority});
                try res_packet.authorities.append(try authority.clone(allocator));
            }

            for (lookup_res.resources.items) |resource| {
                std.debug.print("{any}\n", .{resource});
                try res_packet.resources.append(try resource.clone(allocator));
            }
        } else |_| {
            res_packet.header.rescode = packetParsing.ResultCode.servfail;
        }
    } else {
        res_packet.header.rescode = packetParsing.ResultCode.formerr;
    }

    var res_buf = BytePacketBuffer.init();
    try res_packet.write(&res_buf);

    const len = res_buf.pos;
    const data = res_buf.buf[0..len];

    _ = try std.posix.sendto(
        socket,
        data,
        0,
        &client_addr,
        client_addr_len,
    );
}

pub fn serverLoop(allocator: std.mem.Allocator) !void {
    std.debug.print("Listening...\n", .{});

    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 2053);
    const socket = try std.posix.socket(
        std.posix.AF.INET,
        std.posix.SOCK.DGRAM,
        std.posix.IPPROTO.UDP,
    );
    defer std.posix.close(socket);

    try std.posix.bind(socket, &addr.any, addr.getOsSockLen());

    while (true) {
        handleQuery(allocator, socket) catch |err| {
            std.debug.print("An error occurred: {s}", .{@errorName(err)});
        };
    }
}
