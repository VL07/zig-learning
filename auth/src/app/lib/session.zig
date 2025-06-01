const std = @import("std");
const jetzig = @import("jetzig");
const tableRows = @import("../lib/tableRows.zig");
const time = @import("./time.zig");

const encoder = std.base64.standard.Encoder;
const decoder = std.base64.standard.Decoder;

pub const Session = struct {
    id: [16]u8 = std.mem.zeroes([16]u8), // 128 bit
    token: [32]u8 = std.mem.zeroes([32]u8), // 256 bit
};

pub fn generate_session() Session {
    const session = Session{};

    std.crypto.random.bytes(&session.id);
    std.crypto.random.bytes(&session.token);

    return session;
}

/// Buffer should be 22 + 44 + 1 bytes wide
pub fn stringify_session(buf: [67]u8, session: *Session) !void {
    const encodedId = [22]u8{};
    const encodedToken = [44]u8{};

    encoder.encode(&encodedId, session.id);
    encoder.encode(&encodedToken, session.token);

    try std.fmt.bufPrint(buf, "{}:{}", .{ encodedId, encodedToken });
}

pub fn decode_session(source: []const u8) !?Session {
    var it = std.mem.splitScalar(u8, source, ':');

    const sessionIdEncoded = it.next() orelse return null;
    const sessionTokenEncoded = it.next() orelse return null;

    if (sessionIdEncoded.len != 22 or sessionTokenEncoded.len != 44) return null;

    var session = Session{};

    decoder.decode(session.id[0..], sessionIdEncoded) catch return null;
    decoder.decode(session.token[0..], sessionTokenEncoded) catch return null;

    return session;
}

/// If no row was returned, the session was invalid.
pub fn verify_and_update_session_get_account_id(request: *jetzig.Request, session: *const Session) !?i32 {
    const query = jetzig.database.Query(.Session).findBy(.{ .public_id = session.id });
    if (try request.repo.execute(query)) |dbSession| {
        if (dbSession.expires_at.compare(.less_than, jetzig.DateTime.now())) {
            try request.repo.execute(jetzig.database.Query(.Session).delete().where(.{ .public_id = session.id }));

            return null;
        }

        var newExpirationDate = dbSession.expires_at;

        const secondsLeftThreshold: i32 = if (dbSession.is_short_lived) 10 * 60 else 3 * 24 * 60 * 60;
        if (dbSession.expires_at.compare(.less_than, time.add_seconds(jetzig.DateTime.now(), secondsLeftThreshold))) {
            const secondsToAdd: i32 = if (dbSession.is_short_lived) 60 * 60 else 7 * 24 * 60 * 60;
            newExpirationDate = time.add_seconds(jetzig.DateTime.now(), secondsToAdd);
        }

        var ipList = std.ArrayList(u8).init(request.allocator);
        defer ipList.deinit();

        try request.httpz_request.address.format("", .{}, ipList.writer());

        try request.repo.execute(jetzig.database.Query(.Session).update(.{
            .expires_at = newExpirationDate,
            .last_used_at = jetzig.DateTime.now(),
            .last_used_ip = ipList.items,
        }).where(.{ .id = dbSession.id }));

        return dbSession.account_id;
    }

    return null;
}
