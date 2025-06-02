const std = @import("std");
const jetzig = @import("jetzig");
const secureKeyPair = @import("../../lib/secureKeyPair.zig");

pub fn index(request: *jetzig.Request) !jetzig.View {
    return request.render(.ok);
}

pub fn post(request: *jetzig.Request) !jetzig.View {
    const SignUpParams = struct { email: []const u8 };

    const params = try request.expectParams(SignUpParams) orelse return request.fail(.unprocessable_entity);

    var root = try request.data(.object);
    try root.put("email", params.email);

    const query = jetzig.database.Query(.EmailWhitelist).where(.{.{ params.email, .ilike, .pattern }}).limit(1);
    std.log.debug("{s}", .{query.sql});

    var result = try request.repo.execute(query);
    defer result.deinit();
    const patternResult = try result.next(query);

    var patternId: ?i32 = null;

    if (patternResult) |p| {
        patternId = p.id;
    } else {
        // Allow if is the first user
        const noUserExistQuery = jetzig.database.Query(.Account).select(.{.id}).limit(1);
        var noUserExistResult = try request.repo.execute(noUserExistQuery);
        if (try noUserExistResult.next(noUserExistQuery)) |_| {} else {
            return request.render(.ok);
        }
    }

    const keyPair = secureKeyPair.generate_key_pair();
    const hash = try secureKeyPair.hash_secure_token(request.allocator, keyPair.token[0..]);
    defer request.allocator.free(hash);

    const insertQuery = jetzig.database.Query(.EmailVerification).insert(.{
        .account_id = null,
        .public_id = keyPair.id[0..],
        .hash = hash,
        .email = params.email,
        .email_whitelist_pattern_id = patternId,
    });
    try request.repo.execute(insertQuery);

    const stringifiedKeyPair = try secureKeyPair.stringify_key_pair(&keyPair);
    std.log.info("{s}", .{stringifiedKeyPair[0..]});

    return request.render(.ok);
}
