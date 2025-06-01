const std = @import("std");
const jetzig = @import("jetzig");
const session = @import("../lib/session.zig");
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

    if (cookies.get("session")) |sessionCookie| {
        const decodedSession = try session.decode_session(sessionCookie.value) orelse {
            cookies.delete("session") catch return;
            return;
        };

        const accountId = try session.verify_and_update_session_get_account_id(request, &decodedSession) orelse {
            cookies.delete("session") catch return;
            return;
        };

        // if (1 == 1) @compileError(std.fmt.comptimePrint("{s}", .{@typeInfo(@TypeOf(jetzig.database.Query(.Account).select(.{ .id, .username }).find(0)).ResultType).@"struct".fields[1].name}));
        const accountQuery = jetzig.database.Query(.Account).select(.{ .id, .username }).find(accountId);
        const account = try request.repo.execute(accountQuery) orelse {
            _ = request.fail(.internal_server_error);
            return;
        };

        self.account = account;
    }
}

pub fn deinit(self: *AuthMiddleware, request: *jetzig.http.Request) void {
    request.allocator.destroy(self);
}
