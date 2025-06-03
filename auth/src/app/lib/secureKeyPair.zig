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

/// Buffer should be 24 + 44 bytes wide
pub fn stringify_key_pair(keyPair: *const KeyPair) ![68]u8 {
    std.log.info("{d} {d}", .{ encoder.calcSize(keyPair.id.len), encoder.calcSize(keyPair.token.len) });
    var encodedId: [24]u8 = undefined;
    var encodedToken: [44]u8 = undefined;

    _ = encoder.encode(&encodedId, keyPair.id[0..]);
    _ = encoder.encode(&encodedToken, keyPair.token[0..]);

    var result: [68]u8 = undefined;
    _ = try std.fmt.bufPrint(&result, "{s}{s}", .{ encodedId, encodedToken });

    return result;
}

pub fn parse_key_pair(source: []const u8) !?KeyPair {
    if (source.len != 68) return null;

    var sessionIdEncoded: [24]u8 = undefined;
    var sessionTokenEncoded: [44]u8 = undefined;

    @memcpy(&sessionIdEncoded, source[0..24]);
    @memcpy(&sessionTokenEncoded, source[24..68]);

    // if (std.mem.len(sessionIdEncoded) != 24 or std.mem.len(sessionTokenEncoded) != 44) return null;

    var session = KeyPair{};

    decoder.decode(&session.id, &sessionIdEncoded) catch return null;
    decoder.decode(&session.token, &sessionTokenEncoded) catch return null;

    return session;
}

pub fn verify_secure_token_with_hash(allocator: std.mem.Allocator, hash: []const u8, secret_token: [32]u8) !bool {
    std.crypto.pwhash.argon2.strVerify(
        hash,
        &secret_token,
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

/// If no row was returned, the session was invalid. First return arg is account id and the other is the new session_token. The third is expiratiuon date
pub fn verify_and_update_session_get_account_id_new_session_token(request: *jetzig.Request, session: *const [16]u8) !?struct { i32, [16]u8, jetzig.DateTime } {
    const sessionEncoded = stringify_session(session);
    const query = jetzig.database.Query(.Session).findBy(.{ .token = &sessionEncoded });
    if (try request.repo.execute(query)) |dbSession| {
        if (dbSession.expires_at.compare(.less_than, jetzig.DateTime.now())) {
            try request.repo.execute(jetzig.database.Query(.Session).delete().where(.{ .token = session.* }));

            return null;
        }

        var newExpirationDate = dbSession.expires_at;
        var newSession: [16]u8 = undefined;
        @memcpy(&newSession, session);

        const secondsLeftThreshold: i32 = if (dbSession.is_short_lived) 10 * 60 else 3 * 24 * 60 * 60;
        if (dbSession.expires_at.compare(.less_than, time.add_seconds(jetzig.DateTime.now(), secondsLeftThreshold))) {
            const secondsToAdd: i32 = if (dbSession.is_short_lived) 60 * 60 else 7 * 24 * 60 * 60;
            newExpirationDate = time.add_seconds(jetzig.DateTime.now(), secondsToAdd);

            newSession = generate_session_token();
        }

        const newSessionString = stringify_session(&newSession);

        var ipList = std.ArrayList(u8).init(request.allocator);
        defer ipList.deinit();

        try request.httpz_request.address.format("", .{}, ipList.writer());

        try request.repo.execute(jetzig.database.Query(.Session).update(.{
            .token = &newSessionString,
            .expires_at = newExpirationDate,
            .last_used_at = jetzig.DateTime.now(),
            .last_used_ip = ipList.items,
        }).where(.{ .id = dbSession.id }));

        return .{
            dbSession.account_id,
            newSession,
            newExpirationDate,
        };
    }

    return null;
}

pub fn generate_session_token() [16]u8 {
    var buf: [16]u8 = undefined;
    std.crypto.random.bytes(&buf);

    return buf;
}

pub fn stringify_session(session: *const [16]u8) [24]u8 {
    var buf: [24]u8 = undefined;
    _ = encoder.encode(&buf, session);

    return buf;
}

pub fn parse_session(source: []const u8) !?[16]u8 {
    if (source.len != 24) return null;

    var decoded: [16]u8 = undefined;
    decoder.decode(&decoded, source) catch |err| switch (err) {
        error.InvalidCharacter, error.InvalidPadding => return null,
        else => return err,
    };

    return decoded;
}

pub fn encode_hash(allocator: std.mem.Allocator, hash: []const u8) ![]const u8 {
    const size = encoder.calcSize(hash.len);
    const buf = try allocator.alloc(u8, size);

    _ = encoder.encode(buf, hash);

    return buf;
}

pub fn decode_hash(allocator: std.mem.Allocator, encoded: []const u8) !?[]const u8 {
    const size = decoder.calcSizeForSlice(encoded) catch return null;
    const buf = try allocator.alloc(u8, size);

    try decoder.decode(buf, encoded);

    return buf;
}

fn is_valid_uri_char(c: u8) bool {
    return switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '-', '.', '_', '~' => true,
        else => false,
    };
}

pub fn percent_encode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var res = std.ArrayList(u8).init(allocator);

    try std.Uri.Component.percentEncode(res.writer(), input, is_valid_uri_char);

    return res.toOwnedSlice();
}

pub fn percent_decode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const buf = try allocator.alloc(u8, input.len);
    defer allocator.free(buf);

    const bufSlice = std.Uri.percentDecodeBackwards(buf, input);
    const res = try allocator.alloc(u8, bufSlice.len);

    @memcpy(res, bufSlice);

    return res;
}
