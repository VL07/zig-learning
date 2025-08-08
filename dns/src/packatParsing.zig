const std = @import("std");

const BytePacketBuffer = @import("BytePacketBuffer.zig");

pub const ResultCode = enum(u4) {
    noerror = 0,
    formerr = 1,
    servfail = 2,
    nxdomain = 3,
    notimp = 4,
    refused = 5,

    pub fn fromNum(num: u8) ResultCode {
        if (num > 5) {
            return .refused;
        }

        return @enumFromInt(num);
    }
};

pub const DnsHeader = packed struct {
    id: u16,
    recursion_desired: bool,
    truncated_message: bool,
    authoritative_answer: bool,
    opcode: u4,
    response: bool,

    rescode: ResultCode,
    checking_disabled: bool,
    authed_data: bool,
    z: bool,
    recursion_available: bool,

    questions: u16,
    answers: u16,
    authoritative_entries: u16,
    resource_entries: u16,

    pub fn init() DnsHeader {
        return DnsHeader{
            .id = 0,

            .recursion_desired = false,
            .truncated_message = false,
            .authoritative_answer = false,
            .opcode = 0,
            .response = false,

            .rescode = ResultCode.noerror,
            .checking_disabled = false,
            .authed_data = false,
            .z = false,
            .recursion_available = false,

            .questions = 0,
            .answers = 0,
            .authoritative_entries = 0,
            .resource_entries = 0,
        };
    }

    pub fn initRead(buf: *BytePacketBuffer) !DnsHeader {
        var dns_header: DnsHeader = undefined;

        dns_header.id = try buf.readU16();

        const flags = try buf.readU16();
        const a: u8 = @intCast(flags >> 8);
        const b: u8 = @intCast(flags & 0xFF);
        dns_header.recursion_desired = (a & (1 << 0)) != 0;
        dns_header.truncated_message = (a & (1 << 1)) != 0;
        dns_header.authoritative_answer = (a & (1 << 2)) != 0;
        dns_header.opcode = @intCast((a >> 3) & 0x0F);
        dns_header.response = (a & (1 << 7)) != 0;

        dns_header.rescode = ResultCode.fromNum(b & 0x0F);
        dns_header.checking_disabled = (b & (1 << 4)) != 0;
        dns_header.authed_data = (b & (1 << 5)) != 0;
        dns_header.z = (b & (1 << 6)) != 0;
        dns_header.recursion_available = (b & (1 << 7)) != 0;

        dns_header.questions = try buf.readU16();
        dns_header.answers = try buf.readU16();
        dns_header.authoritative_entries = try buf.readU16();
        dns_header.resource_entries = try buf.readU16();

        return dns_header;
    }

    pub fn write(self: *const DnsHeader, buf: *BytePacketBuffer) !void {
        try buf.writeU16(self.id);

        try buf.writeU8(
            @as(u8, @intFromBool(self.recursion_desired)) | (@as(u8, @intFromBool(self.truncated_message)) << 1) | (@as(u8, @intFromBool(self.authoritative_answer)) << 2) | (@as(u8, self.opcode) << 3) | (@as(u8, @intFromBool(self.response)) << 7),
        );

        try buf.writeU8(
            @as(u8, @intFromEnum(self.rescode)) | (@as(u8, @intFromBool(self.checking_disabled)) << 4) | (@as(u8, @intFromBool(self.authed_data)) << 5) | (@as(u8, @intFromBool(self.z)) << 6) | (@as(u8, @intFromBool(self.recursion_available)) << 7),
        );

        try buf.writeU16(self.questions);
        try buf.writeU16(self.answers);
        try buf.writeU16(self.authoritative_entries);
        try buf.writeU16(self.resource_entries);
    }
};

pub const QueryTypeEnum = enum {
    unknown,
    a,
    ns,
    cname,
    mx,
    aaaa,
};
pub const QueryType = union(QueryTypeEnum) {
    unknown: u16,
    a: void,
    ns: void,
    cname: void,
    mx: void,
    aaaa: void,

    pub fn initNum(num: u16) QueryType {
        return switch (num) {
            1 => QueryType{ .a = undefined },
            2 => QueryType{ .ns = undefined },
            5 => QueryType{ .cname = undefined },
            15 => QueryType{ .mx = undefined },
            28 => QueryType{ .aaaa = undefined },
            else => |val| QueryType{ .unknown = val },
        };
    }

    pub fn toNum(self: QueryType) u16 {
        return switch (self) {
            .unknown => |val| val,
            .a => 1,
            .ns => 2,
            .cname => 5,
            .mx => 15,
            .aaaa => 28,
        };
    }
};

pub const DnsQuestion = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    qtype: QueryType,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, qtype: QueryType) !DnsQuestion {
        return DnsQuestion{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .qtype = qtype,
        };
    }

    pub fn initRead(allocator: std.mem.Allocator, buf: *BytePacketBuffer) !DnsQuestion {
        const dns_question = DnsQuestion{
            .allocator = allocator,
            .name = try buf.readQname(allocator),
            .qtype = QueryType.initNum(try buf.readU16()),
        };

        _ = try buf.readU16();

        return dns_question;
    }

    pub fn deinit(self: *const DnsQuestion) void {
        self.allocator.free(self.name);
    }

    pub fn write(self: *const DnsQuestion, buf: *BytePacketBuffer) !void {
        try buf.writeQname(self.name);

        const type_num = self.qtype.toNum();
        try buf.writeU16(type_num);
        try buf.writeU16(1);
    }
};

pub const DnsRecord = union(QueryTypeEnum) {
    unknown: struct {
        allocator: std.mem.Allocator,
        domain: []const u8,
        qtype: u16,
        data_len: u16,
        ttl: u32,
    },
    a: struct {
        allocator: std.mem.Allocator,
        domain: []const u8,
        addr: std.net.Address,
        ttl: u32,
    },
    ns: struct {
        allocator: std.mem.Allocator,
        domain: []const u8,
        host: []const u8,
        ttl: u32,
    },
    cname: struct {
        allocator: std.mem.Allocator,
        domain: []const u8,
        host: []const u8,
        ttl: u32,
    },
    mx: struct {
        allocator: std.mem.Allocator,
        domain: []const u8,
        priority: u16,
        host: []const u8,
        ttl: u32,
    },
    aaaa: struct {
        allocator: std.mem.Allocator,
        domain: []const u8,
        addr: std.net.Address,
        ttl: u32,
    },

    pub fn initRead(allocator: std.mem.Allocator, buf: *BytePacketBuffer) !DnsRecord {
        const domain = try buf.readQname(allocator);

        const qtype_num = try buf.readU16();
        const qtype = QueryType.initNum(qtype_num);
        _ = try buf.readU16();
        const ttl = try buf.readU32();
        const data_len = try buf.readU16();

        switch (qtype) {
            .a => {
                const raw_addr = try buf.readU32();
                const addr = std.net.Address.initIp4([_]u8{
                    @intCast((raw_addr >> 24) & 0xFF),
                    @intCast((raw_addr >> 16) & 0xFF),
                    @intCast((raw_addr >> 8) & 0xFF),
                    @intCast(raw_addr & 0xFF),
                }, 0);

                return DnsRecord{ .a = .{
                    .allocator = allocator,
                    .domain = domain,
                    .addr = addr,
                    .ttl = ttl,
                } };
            },
            .aaaa => {
                var ip: [16]u8 = undefined;
                for (0..ip.len) |i| {
                    ip[i] = try buf.read();
                }

                const addr = std.net.Address.initIp6(ip, 0, 0, 0);

                return DnsRecord{ .aaaa = .{ .allocator = allocator, .domain = domain, .addr = addr, .ttl = ttl } };
            },
            .ns => {
                const ns = try buf.readQname(allocator);
                errdefer allocator.free(ns);

                return DnsRecord{ .ns = .{
                    .allocator = allocator,
                    .domain = domain,
                    .host = ns,
                    .ttl = ttl,
                } };
            },
            .cname => {
                const cname = try buf.readQname(allocator);
                errdefer allocator.free(cname);

                return DnsRecord{ .cname = .{
                    .allocator = allocator,
                    .domain = domain,
                    .host = cname,
                    .ttl = ttl,
                } };
            },
            .mx => {
                const priority = try buf.readU16();
                const mx = try buf.readQname(allocator);
                errdefer allocator.free(mx);

                return DnsRecord{ .mx = .{
                    .allocator = allocator,
                    .domain = domain,
                    .priority = priority,
                    .host = mx,
                    .ttl = ttl,
                } };
            },
            else => {
                try buf.step(@intCast(data_len));

                return DnsRecord{ .unknown = .{
                    .allocator = allocator,
                    .domain = domain,
                    .qtype = qtype_num,
                    .data_len = data_len,
                    .ttl = ttl,
                } };
            },
        }
    }

    pub fn deinit(self: *const DnsRecord) void {
        switch (self.*) {
            .unknown => self.unknown.allocator.free(self.unknown.domain),
            .a => self.a.allocator.free(self.a.domain),
            .ns => {
                self.ns.allocator.free(self.ns.domain);
                self.ns.allocator.free(self.ns.host);
            },
            .cname => {
                self.cname.allocator.free(self.cname.domain);
                self.cname.allocator.free(self.cname.host);
            },
            .mx => {
                self.mx.allocator.free(self.mx.domain);
                self.mx.allocator.free(self.mx.host);
            },
            .aaaa => self.aaaa.allocator.free(self.aaaa.domain),
        }
    }

    pub fn clone(self: *const DnsRecord, allocator: std.mem.Allocator) !DnsRecord {
        return switch (self.*) {
            .unknown => |unknown| DnsRecord{ .unknown = .{
                .allocator = allocator,
                .domain = try allocator.dupe(u8, unknown.domain),
                .qtype = unknown.qtype,
                .data_len = unknown.data_len,
                .ttl = unknown.ttl,
            } },
            .a => |a| DnsRecord{ .a = .{
                .allocator = allocator,
                .domain = try allocator.dupe(u8, a.domain),
                .addr = a.addr,
                .ttl = a.ttl,
            } },
            .ns => |ns| DnsRecord{ .ns = .{
                .allocator = allocator,
                .domain = try allocator.dupe(u8, ns.domain),
                .host = try allocator.dupe(u8, ns.host),
                .ttl = ns.ttl,
            } },
            .cname => |cname| DnsRecord{ .cname = .{
                .allocator = allocator,
                .domain = try allocator.dupe(u8, cname.domain),
                .host = try allocator.dupe(u8, cname.host),
                .ttl = cname.ttl,
            } },
            .mx => |mx| DnsRecord{ .mx = .{
                .allocator = allocator,
                .domain = try allocator.dupe(u8, mx.domain),
                .priority = mx.priority,
                .host = try allocator.dupe(u8, mx.host),
                .ttl = mx.ttl,
            } },
            .aaaa => |aaaa| DnsRecord{ .aaaa = .{
                .allocator = allocator,
                .domain = try allocator.dupe(u8, aaaa.domain),
                .addr = aaaa.addr,
                .ttl = aaaa.ttl,
            } },
        };
    }

    pub fn write(self: *const DnsRecord, buf: *BytePacketBuffer) !usize {
        const start_pos = buf.pos;

        switch (self.*) {
            .a => |a| {
                try buf.writeQname(a.domain);

                const query_type_num = (QueryType{ .a = undefined }).toNum();
                try buf.writeU16(query_type_num);

                try buf.writeU16(1);
                try buf.writeU32(a.ttl);
                try buf.writeU16(4);

                try buf.writeU32(std.mem.nativeToBig(u32, a.addr.in.sa.addr));
            },
            .ns => |ns| {
                try buf.writeQname(ns.domain);
                try buf.writeU16((QueryType{ .ns = undefined }).toNum());
                try buf.writeU16(1);
                try buf.writeU32(ns.ttl);

                const pos = buf.pos;
                try buf.writeU16(0);

                try buf.writeQname(ns.host);

                const size = buf.pos - (pos + 2);
                try buf.setU16(pos, @intCast(size));
            },
            .cname => |cname| {
                try buf.writeQname(cname.domain);
                try buf.writeU16((QueryType{ .cname = undefined }).toNum());
                try buf.writeU16(1);
                try buf.writeU32(cname.ttl);

                const pos = buf.pos;
                try buf.writeU16(0);

                try buf.writeQname(cname.host);

                const size = buf.pos - (pos + 2);
                try buf.setU16(pos, @intCast(size));
            },
            .mx => |mx| {
                try buf.writeQname(mx.domain);
                try buf.writeU16((QueryType{ .mx = undefined }).toNum());
                try buf.writeU16(1);
                try buf.writeU32(mx.ttl);

                const pos = buf.pos;
                try buf.writeU16(0);

                try buf.writeU16(mx.priority);
                try buf.writeQname(mx.host);

                const size = buf.pos - (pos + 2);
                try buf.setU16(pos, @intCast(size));
            },
            .aaaa => |aaaa| {
                try buf.writeQname(aaaa.domain);
                try buf.writeU16((QueryType{ .aaaa = undefined }).toNum());
                try buf.writeU16(1);
                try buf.writeU32(aaaa.ttl);
                try buf.writeU16(16);

                for (aaaa.addr.in6.sa.addr) |segment| {
                    try buf.writeU8(segment);
                }
            },
            .unknown => |_| {
                // Do nothing
            },
        }

        return buf.pos - start_pos;
    }
};

pub const DnsPacket = struct {
    allocator: std.mem.Allocator,
    header: DnsHeader,
    questions: std.ArrayList(DnsQuestion),
    answers: std.ArrayList(DnsRecord),
    authorities: std.ArrayList(DnsRecord),
    resources: std.ArrayList(DnsRecord),

    pub fn init(allocator: std.mem.Allocator) !DnsPacket {
        return DnsPacket{
            .allocator = allocator,
            .header = DnsHeader.init(),
            .questions = .init(allocator),
            .answers = .init(allocator),
            .authorities = .init(allocator),
            .resources = .init(allocator),
        };
    }

    pub fn initFromBuf(allocator: std.mem.Allocator, buf: *BytePacketBuffer) !DnsPacket {
        const header = try DnsHeader.initRead(buf);
        var dns_packet = DnsPacket{
            .allocator = allocator,
            .header = header,
            .questions = try .initCapacity(allocator, header.questions),
            .answers = try .initCapacity(allocator, header.answers),
            .authorities = try .initCapacity(allocator, header.authoritative_entries),
            .resources = try .initCapacity(allocator, header.resource_entries),
        };

        for (0..header.questions) |_| {
            try dns_packet.questions.append(try DnsQuestion.initRead(allocator, buf));
        }

        for (0..header.answers) |_| {
            try dns_packet.answers.append(try DnsRecord.initRead(allocator, buf));
        }

        for (0..header.authoritative_entries) |_| {
            try dns_packet.authorities.append(try DnsRecord.initRead(allocator, buf));
        }

        for (0..header.resource_entries) |_| {
            try dns_packet.resources.append(try DnsRecord.initRead(allocator, buf));
        }

        return dns_packet;
    }

    pub fn deinit(self: *const DnsPacket) void {
        for (self.questions.items) |question| {
            question.deinit();
        }

        for (self.answers.items) |answer| {
            answer.deinit();
        }

        for (self.authorities.items) |authority| {
            authority.deinit();
        }

        for (self.resources.items) |resource| {
            resource.deinit();
        }

        self.questions.deinit();
        self.answers.deinit();
        self.authorities.deinit();
        self.resources.deinit();
    }

    pub fn write(self: *DnsPacket, buf: *BytePacketBuffer) !void {
        self.header.questions = @intCast(self.questions.items.len);
        self.header.answers = @intCast(self.answers.items.len);
        self.header.authoritative_entries = @intCast(self.authorities.items.len);
        self.header.resource_entries = @intCast(self.resources.items.len);

        try self.header.write(buf);

        for (self.questions.items) |question| {
            try question.write(buf);
        }

        for (self.answers.items) |answer| {
            _ = try answer.write(buf);
        }

        for (self.authorities.items) |authority| {
            _ = try authority.write(buf);
        }

        for (self.resources.items) |resource| {
            _ = try resource.write(buf);
        }
    }
};

test "parse packet" {
    const raw_packet = [_]u8{ 0x1B, 0x69, 0x81, 0x80, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x06, 0x67, 0x6F, 0x6F, 0x67, 0x6C, 0x65, 0x03, 0x63, 0x6F, 0x6D, 0x00, 0x00, 0x01, 0x00, 0x01, 0xC0, 0x0C, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x01, 0x2C, 0x00, 0x04, 0x8E, 0xFA, 0x4A, 0x0E };
    var raw_packet_padded = [_]u8{0} ** 512;
    @memcpy(raw_packet_padded[0..raw_packet.len], &raw_packet);
    var buf = BytePacketBuffer.init();
    buf.buf = raw_packet_padded;

    const packet = try DnsPacket.initFromBuf(std.testing.allocator, &buf);
    defer packet.deinit();

    try std.testing.expectEqualDeep(DnsHeader{
        .id = 7017,
        .recursion_desired = true,
        .truncated_message = false,
        .authoritative_answer = false,
        .opcode = 0,
        .response = true,
        .rescode = .noerror,
        .checking_disabled = false,
        .authed_data = false,
        .z = false,
        .recursion_available = true,
        .questions = 1,
        .answers = 1,
        .authoritative_entries = 0,
        .resource_entries = 0,
    }, packet.header);

    const question = packet.questions.items[0];
    try std.testing.expectEqualSlices(
        u8,
        "google.com",
        question.name,
    );
    try std.testing.expectEqual(question.qtype, QueryType{ .a = undefined });

    const answer = packet.answers.items[0];
    switch (answer) {
        .a => |a| {
            try std.testing.expectEqualSlices(u8, "google.com", a.domain);
            try std.testing.expectEqual(std.net.Address.initIp4(.{ 142, 250, 74, 14 }, 0).in.sa.addr, a.addr.in.sa.addr);
            try std.testing.expectEqual(300, a.ttl);
        },
        else => try std.testing.expect(false),
    }
}

test "write packet" {
    var packet = try DnsPacket.init(std.testing.allocator);
    defer packet.deinit();

    packet.header.id = 7017;
    packet.header.recursion_desired = true;
    packet.header.truncated_message = false;
    packet.header.authoritative_answer = false;
    packet.header.opcode = 0;
    packet.header.response = true;
    packet.header.rescode = .noerror;
    packet.header.checking_disabled = false;
    packet.header.authed_data = false;
    packet.header.z = false;
    packet.header.recursion_available = true;
    packet.header.questions = 1;
    packet.header.answers = 1;
    packet.header.authoritative_entries = 0;
    packet.header.resource_entries = 0;

    try packet.questions.append(try DnsQuestion.init(std.testing.allocator, "google.com"[0..], QueryType{ .a = undefined }));
    try packet.answers.append(DnsRecord{ .a = .{
        .allocator = std.testing.allocator,
        .domain = try std.testing.allocator.dupe(u8, "google.com"[0..]),
        .addr = std.net.Address.initIp4(.{ 142, 250, 74, 14 }, 0),
        .ttl = 300,
    } });

    var buf = BytePacketBuffer.init();
    try packet.write(&buf);

    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{ 0x1B, 0x69, 0x81, 0x80, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x06, 0x67, 0x6F, 0x6F, 0x67, 0x6C, 0x65, 0x03, 0x63, 0x6F, 0x6D, 0x00, 0x00, 0x01, 0x00, 0x01, 0x06, 0x67, 0x6F, 0x6F, 0x67, 0x6C, 0x65, 0x03, 0x63, 0x6F, 0x6D, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x01, 0x2C, 0x00, 0x04, 0x8E, 0xFA, 0x4A, 0x0E },
        buf.buf[0..buf.pos],
    );
}
