const std = @import("std");
const jetzig = @import("jetzig");
const secureKeyPair = @import("../lib/secureKeyPair.zig");
const tableRows = @import("../lib/tableRows.zig");

pub const middleware_name = "auth";

account: ?@TypeOf(jetzig.database.Query(.Account).select(.{ .id, .username }).find(0)).ResultType,

const AuthMiddleware = @This();

pub fn init(request: *jetzig.Request) !*AuthMiddleware {
    const middleware = try request.allocator.create(AuthMiddleware);
    middleware.* = .{ .account = null };
    return middleware;
}

pub fn afterRequest(self: *AuthMiddleware, request: *jetzig.Request) !void {
    const cookies = try request.cookies();

    try cookies.format("", "", std.io.getStdOut().writer());

    if (cookies.get("session_token")) |sessionCookieEncoded| {
        const sessionCookie = try secureKeyPair.percent_decode(request.allocator, sessionCookieEncoded.value);
        defer request.allocator.free(sessionCookie);

        std.debug.print("here", .{});
        const decodedSession = try secureKeyPair.parse_session(sessionCookie) orelse {
            cookies.delete("session_token") catch return;
            return;
        };

        const verifyResponse = try secureKeyPair.verify_and_update_session_get_account_id_new_session_token(request, &decodedSession) orelse {
            cookies.delete("session_token") catch return;
            return;
        };

        const accountId = verifyResponse[0];
        const newSessionToken = verifyResponse[1];
        const newExpirationDate = verifyResponse[2];

        // if (1 == 1) @compileError(std.fmt.comptimePrint("{s}", .{@typeInfo(@TypeOf(jetzig.database.Query(.Account).select(.{ .id, .username }).find(0)).ResultType).@"struct".fields[1].name}));
        const accountQuery = jetzig.database.Query(.Account).select(.{ .id, .username }).find(accountId);
        const account = try request.repo.execute(accountQuery) orelse {
            cookies.delete("session_token") catch return; // User might have deleted account?

            _ = request.fail(.internal_server_error);
            return;
        };

        const newSessionTokenStringified = secureKeyPair.stringify_session(&newSessionToken);
        const sessionTokenEncoded = try secureKeyPair.percent_encode(request.allocator, &newSessionTokenStringified);
        defer request.allocator.free(sessionTokenEncoded);

        try cookies.put(.{ .name = "session_token", .value = sessionTokenEncoded, .expires = newExpirationDate.unix(.seconds) });

        self.account = account;
    }
}

pub fn deinit(self: *AuthMiddleware, request: *jetzig.http.Request) void {
    request.allocator.destroy(self);
}
