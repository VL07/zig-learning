const std = @import("std");
const jetzig = @import("jetzig");
const tableRows = @import("../lib/tableRows.zig");
const time = @import("./time.zig");

const encoder = std.base64.standard.Encoder;
const decoder = std.base64.standard.Decoder;

pub const KeyPair = struct {
    id: [16]u8 = undefined, // 128 bit
    token: [32]u8 = undefined, // 256 bit
};

pub fn generate_key_pair() KeyPair {
    var session = KeyPair{};

    std.crypto.random.bytes(session.id[0..]);
    std.crypto.random.bytes(session.token[0..]);

    return session;
}

/// Buffer should be 22 + 43 bytes wide
pub fn stringify_key_pair(keyPair: *const KeyPair) ![65]u8 {
    var encodedId: [22]u8 = undefined;
    var encodedToken: [43]u8 = undefined;

    _ = encoder.encode(&encodedId, keyPair.id[0..]);
    _ = encoder.encode(&encodedToken, keyPair.token[0..]);

    var result: [65]u8 = undefined;
    _ = try std.fmt.bufPrint(&result, "{s}{s}", .{ encodedId, encodedToken });

    return result;
}

pub fn parse_key_pair(source: []const u8) !?KeyPair {
    if (source.len != 65) return null;

    const sessionIdEncoded: [22]u8 = undefined;
    const sessionTokenEncoded: [43]u8 = undefined;

    @memcpy(sessionIdEncoded, source[0..22]);
    @memcpy(sessionTokenEncoded, source[22..65]);

    if (std.mem.len(sessionIdEncoded) != 22 or std.mem.len(sessionTokenEncoded) != 43) return null;

    var session = KeyPair{};

    decoder.decode(session.id[0..], sessionIdEncoded) catch return null;
    decoder.decode(session.token[0..], sessionTokenEncoded) catch return null;

    return session;
}

pub fn verify_secure_token_with_hash(allocator: std.mem.Allocator, hash: []const u8, secret_token: [32]u8) !bool {
    std.crypto.pwhash.argon2.strVerify(
        hash,
        secret_token,
        .{ .allocator = allocator },
    ) catch |err| switch (err) {
        error.AuthenticationFailed, error.PasswordVerificationFailed => return false,
        else => return err,
    };

    return true;
}

/// Stolen from https://github.com/jetzig-framework/jetzig/blob/1cb27ffec8fb648a30a9aa65c1e6128cf967a2f8/src/jetzig/auth.zig#L49
pub fn hash_secure_token(allocator: std.mem.Allocator, token: []const u8) ![]const u8 {
    var buf: [128]u8 = undefined;
    const hash = try std.crypto.pwhash.argon2.strHash(
        token,
        .{
            .allocator = allocator,
            .params = .{ .t = 3, .m = 32, .p = 4 },
        },
        &buf,
    );

    const result = try allocator.alloc(u8, hash.len);
    @memcpy(result, hash);
    return result;
}

/// If no row was returned, the session was invalid.
pub fn verify_and_update_session_get_account_id(request: *jetzig.Request, session: *const [16]u8) !?i32 {
    const query = jetzig.database.Query(.Session).findBy(.{ .token = session.* });
    if (try request.repo.execute(query)) |dbSession| {
        if (dbSession.expires_at.compare(.less_than, jetzig.DateTime.now())) {
            try request.repo.execute(jetzig.database.Query(.Session).delete().where(.{ .token = session.* }));

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

pub fn generate_session_token() [16]u8 {
    const buf: [16]u8 = undefined;
    std.crypto.random.bytes(&buf);

    return buf;
}

pub fn stringify_session(session: *const [16]u8) [22]u8 {
    var buf: [22]u8 = undefined;
    encoder.encode(&buf, session.*);

    return buf;
}

pub fn parse_session(source: []const u8) !?[16]u8 {
    if (source.len != 22) return null;

    var decoded: [16]u8 = undefined;
    decoder.decode(&decoded, source) catch |err| switch (err) {
        error.InvalidCharacter, error.InvalidPadding => return null,
        else => return err,
    };

    return decoded;
}
