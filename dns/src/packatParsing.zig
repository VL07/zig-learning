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

const DnsHeader = packed struct {
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
};

pub const QueryTypeEnum = enum { unknown, a };
pub const QueryType = union(QueryTypeEnum) {
    unknown: u16,
    a: void,

    pub fn initNum(num: u16) QueryType {
        return switch (num) {
            1 => QueryType{ .a = undefined },
            else => |val| QueryType{ .unknown = val },
        };
    }

    pub fn toNum(self: QueryType) u16 {
        return switch (self) {
            .unknown => |val| val,
            .a => 1,
        };
    }
};

pub const DnsQuestion = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    qtype: QueryType,

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
};

const DnsRecordEnum = enum {
    unknown,
    a,
};
pub const DnsRecord = union(DnsRecordEnum) {
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
        addr: std.net.Ip4Address,
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
                const addr = std.net.Ip4Address.init([_]u8{
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
            .unknown => {
                self.unknown.allocator.free(self.unknown.domain);
            },
            .a => {
                self.a.allocator.free(self.a.domain);
            },
        }
    }
};

pub const DnsPacket = struct {
    allocator: std.mem.Allocator,
    header: DnsHeader,
    questions: []DnsQuestion,
    answers: []DnsRecord,
    authorities: []DnsRecord,
    resources: []DnsRecord,

    pub fn initFromBuf(allocator: std.mem.Allocator, buf: *BytePacketBuffer) !DnsPacket {
        const header = try DnsHeader.initRead(buf);
        const dns_packet = DnsPacket{
            .allocator = allocator,
            .header = header,
            .questions = try allocator.alloc(DnsQuestion, header.questions),
            .answers = try allocator.alloc(DnsRecord, header.answers),
            .authorities = try allocator.alloc(DnsRecord, header.authoritative_entries),
            .resources = try allocator.alloc(DnsRecord, header.resource_entries),
        };

        for (0..header.questions) |i| {
            dns_packet.questions[i] = try DnsQuestion.initRead(allocator, buf);
        }

        for (0..header.answers) |i| {
            dns_packet.answers[i] = try DnsRecord.initRead(allocator, buf);
        }

        for (0..header.authoritative_entries) |i| {
            dns_packet.authorities[i] = try DnsRecord.initRead(allocator, buf);
        }

        for (0..header.resource_entries) |i| {
            dns_packet.resources[i] = try DnsRecord.initRead(allocator, buf);
        }

        return dns_packet;
    }

    pub fn deinit(self: *const DnsPacket) void {
        for (self.questions) |question| {
            question.deinit();
        }

        for (self.answers) |answer| {
            answer.deinit();
        }

        for (self.authorities) |authority| {
            authority.deinit();
        }

        for (self.resources) |resource| {
            resource.deinit();
        }

        self.allocator.free(self.questions);
        self.allocator.free(self.answers);
        self.allocator.free(self.authorities);
        self.allocator.free(self.resources);
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

    const question = packet.questions[0];
    try std.testing.expectEqualSlices(
        u8,
        "google.com",
        question.name,
    );
    try std.testing.expectEqual(question.qtype, QueryType{ .a = undefined });

    const answer = packet.answers[0];
    switch (answer) {
        .a => |a| {
            try std.testing.expectEqualSlices(u8, "google.com", a.domain);
            try std.testing.expectEqual(std.net.Ip4Address.init(.{ 142, 250, 74, 14 }, 0), a.addr);
            try std.testing.expectEqual(300, a.ttl);
        },
        else => try std.testing.expect(false),
    }
}
