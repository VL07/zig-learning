const std = @import("std");
const jetzig = @import("jetzig");
const secureKeyPair = @import("../../lib/secureKeyPair.zig");
const time = @import("../../lib/time.zig");

pub fn index(request: *jetzig.Request) !jetzig.View {
    const unparsedParams = try request.params();
    var root = try request.data(.object);

    if (unparsedParams.getT(.string, "verification")) |unparsedToken| {
        try root.put("stage", 1);

        const tokenPairParsed = try secureKeyPair.percent_decode(request.allocator, unparsedToken);
        defer request.allocator.free(tokenPairParsed);

        const tokenPair = try secureKeyPair.parse_key_pair(tokenPairParsed) orelse return request.fail(.unprocessable_entity);

        const publicIdString = try secureKeyPair.encode_hash(request.allocator, &tokenPair.id);
        defer request.allocator.free(publicIdString);

        const getEmailVerificationQuery = jetzig.database.Query(.EmailVerification).findBy(.{ .public_id = publicIdString });
        const emailVerificationRow = try request.repo.execute(getEmailVerificationQuery) orelse return request.fail(.unprocessable_entity);
        if (emailVerificationRow.account_id != null) return request.fail(.unprocessable_entity);

        // TODO: Check expiration date

        const emailVerificationRowHashDecoded = try secureKeyPair.decode_hash(request.allocator, emailVerificationRow.hash) orelse unreachable;
        defer request.allocator.free(emailVerificationRowHashDecoded);

        const isValidToken = try secureKeyPair.verify_secure_token_with_hash(request.allocator, emailVerificationRowHashDecoded, tokenPair.token);
        if (!isValidToken) return request.fail(.unprocessable_entity);

        try root.put("email", emailVerificationRow.email);

        return request.render(.ok);
    }

    try root.put("stage", 0);

    return request.render(.ok);
}

pub fn post(request: *jetzig.Request) !jetzig.View {
    const unparsedQuery = try request.queryParams();
    var root = try request.data(.object);

    if (unparsedQuery.getT(.string, "verification")) |unparsedToken| {
        const tokenPairParsed = try secureKeyPair.percent_decode(request.allocator, unparsedToken);
        defer request.allocator.free(tokenPairParsed);

        const tokenPair = try secureKeyPair.parse_key_pair(tokenPairParsed) orelse return request.fail(.unprocessable_entity);

        const publicIdString = try secureKeyPair.encode_hash(request.allocator, &tokenPair.id);
        defer request.allocator.free(publicIdString);

        const getEmailVerificationQuery = jetzig.database.Query(.EmailVerification).findBy(.{ .public_id = publicIdString });
        const emailVerificationRow = try request.repo.execute(getEmailVerificationQuery) orelse return request.fail(.unprocessable_entity);
        if (emailVerificationRow.account_id != null) return request.fail(.unprocessable_entity);

        // TODO: Check expiration date

        const emailVerificationRowHashDecoded = try secureKeyPair.decode_hash(request.allocator, emailVerificationRow.hash) orelse unreachable;
        defer request.allocator.free(emailVerificationRowHashDecoded);

        // std.log.debug("{s} {s}", .{ std.fmt.bytesToHex(@as([256]u8, emailVerificationRowHashDecoded), .lower), std.fmt.bytesToHex(@as([256]u8, tokenPair.token), .lower) });

        const isValidToken = try secureKeyPair.verify_secure_token_with_hash(request.allocator, emailVerificationRowHashDecoded, tokenPair.token);
        if (!isValidToken) return request.fail(.unprocessable_entity);

        const SignUpParams = struct { username: []const u8, password: []const u8 };
        const params = try request.expectParams(SignUpParams) orelse return request.fail(.unprocessable_entity);

        std.log.debug("LENS: {d} {d}", .{ params.password.len, params.username.len });

        if (params.password.len < 8 or params.password.len > 100 or params.username.len < 2 or params.username.len > 30) return request.fail(.unprocessable_entity);

        std.log.debug("HERE!!!", .{});

        const takenUsernameQuery = jetzig.database.Query(.Account).select(.{.id}).where(.{.{ params.username, .ilike, .username }}).limit(1);
        var takenUsername = try request.repo.execute(takenUsernameQuery);
        if (try takenUsername.next(takenUsernameQuery)) |_| return request.fail(.unprocessable_entity);

        const emailVerificationDeleteQuery = jetzig.database.Query(.EmailVerification).delete().where(.{.{ .id = emailVerificationRow.id }});
        try request.repo.execute(emailVerificationDeleteQuery);

        const passwordHash = try secureKeyPair.hash_secure_token(request.allocator, params.password);
        defer request.allocator.free(passwordHash);

        const passwordHashString = try secureKeyPair.encode_hash(request.allocator, passwordHash);
        defer request.allocator.free(passwordHash);

        const accountInsertQuery = jetzig.database.Query(.Account).insert(.{
            .username = params.username,
            .password = passwordHashString,
            .last_sign_in_at = jetzig.DateTime.now(),
        });
        try request.repo.execute(accountInsertQuery);

        const getAccountIdQuery = jetzig.database.Query(.Account).select(.{.id}).findBy(.{ .username = params.username });
        const account = try request.repo.execute(getAccountIdQuery) orelse unreachable;

        const emailInsertQuery = jetzig.database.Query(.Email).insert(.{
            .account_id = account.id,
            .email = emailVerificationRow.email,
            .email_whitelist_pattern_id = emailVerificationRow.email_whitelist_pattern_id,
            .verified_at = jetzig.DateTime.now(),
            .last_sign_in_at = jetzig.DateTime.now(),
            .is_primary = true,
        });
        try request.repo.execute(emailInsertQuery);

        const emailGetIdQuery = jetzig.database.Query(.Email).select(.{.id}).findBy(.{ .email = emailVerificationRow.email });
        const insertedEmail = try request.repo.execute(emailGetIdQuery) orelse unreachable;

        const sessionToken = secureKeyPair.generate_session_token();
        const sessionTokenString = secureKeyPair.stringify_session(&sessionToken);

        var ipList = std.ArrayList(u8).init(request.allocator);
        defer ipList.deinit();

        try request.httpz_request.address.format("", .{}, ipList.writer());

        const expiresAt = time.add_seconds(jetzig.DateTime.now(), 7 * 24 * 60 * 60);

        const insertSessionQuery = jetzig.database.Query(.Session).insert(.{
            .account_id = account.id,
            .token = &sessionTokenString,
            .email_used_id = insertedEmail.id,
            .expires_at = expiresAt,
            .last_used_at = jetzig.DateTime.now(),
            .last_used_ip = ipList.items,
            .is_short_lived = false,
        });
        try request.repo.execute(insertSessionQuery);

        const cookies = try request.cookies();

        const sessionTokenEncoded = try secureKeyPair.percent_encode(request.allocator, &sessionTokenString);
        defer request.allocator.free(sessionTokenEncoded);

        try cookies.put(.{ .name = "session_token", .value = sessionTokenEncoded, .expires = expiresAt.unix(.seconds) });

        return request.redirect("/", .moved_permanently);
    } else {
        const SignUpParams = struct { email: []const u8 };
        const params = try request.expectParams(SignUpParams) orelse return request.fail(.unprocessable_entity);

        try root.put("email", params.email);

        const query = jetzig.database.Query(.EmailWhitelist).where(.{.{ params.email, .ilike, .pattern }}).limit(1);

        var result = try request.repo.execute(query);
        defer result.deinit();
        const patternResult = try result.next(query);

        var patternId: ?i32 = null;

        if (patternResult) |p| {
            patternId = p.id;
        } else {
            // Allow if is the first user
            const noUserExistQuery = jetzig.database.Query(.Account).select(.{.id}).limit(1);
            var userExistsResult = try request.repo.execute(noUserExistQuery);
            if (try userExistsResult.next(noUserExistQuery)) |_| {
                return request.render(.ok);
            }
        }

        const emailAlreadyInUseQuery = jetzig.database.Query(.Email).findBy(.{ .email = params.email });
        if (try request.repo.execute(emailAlreadyInUseQuery)) |_| return request.fail(.unprocessable_entity);

        const keyPair = secureKeyPair.generate_key_pair();
        const hash = try secureKeyPair.hash_secure_token(request.allocator, keyPair.token[0..]);
        defer request.allocator.free(hash);

        const hashString = try secureKeyPair.encode_hash(request.allocator, hash);
        defer request.allocator.free(hashString);

        const publicIdString = try secureKeyPair.encode_hash(request.allocator, &keyPair.id);
        defer request.allocator.free(publicIdString);

        const insertQuery = jetzig.database.Query(.EmailVerification).insert(.{
            .account_id = null,
            .public_id = publicIdString,
            .hash = hashString,
            .email = params.email,
            .email_whitelist_pattern_id = patternId,
        });
        try request.repo.execute(insertQuery);

        const stringifiedKeyPair = try secureKeyPair.stringify_key_pair(&keyPair);
        const uriEncodedStringifiedKeyPair = try secureKeyPair.percent_encode(request.allocator, &stringifiedKeyPair);
        defer request.allocator.free(uriEncodedStringifiedKeyPair);

        std.log.info("{s}", .{uriEncodedStringifiedKeyPair});

        try root.put("token", uriEncodedStringifiedKeyPair[0..]);

        const mail = request.mail("signUp", .{ .to = &.{.{ .email = params.email }} });
        try mail.deliver(.background, .{});

        return request.render(.ok);
    }
}
