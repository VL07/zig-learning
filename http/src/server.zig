const std = @import("std");
const request = @import("request.zig");
const response = @import("response.zig");

const Handler = fn (*request.Request, *response.Response) anyerror!void;

pub const Server = struct {
    allocator: std.mem.Allocator,
    address: std.net.Address,

    pub fn init(allocator: std.mem.Allocator, address: std.net.Address) Server {
        return Server{
            .allocator = allocator,
            .address = address,
        };
    }

    pub fn listen(this: *Server, callback_fn: fn (*const Server) anyerror!void, handler: Handler) !void {
        var server = try this.address.listen(.{ .reuse_address = true });
        defer server.deinit();

        try callback_fn(this);

        while (true) {
            const connection = server.accept() catch |err| {
                std.log.err("Failed to accept connection: {s}", .{@errorName(err)});

                continue;
            };

            _ = std.Thread.spawn(.{}, accept, .{ this, connection, handler }) catch |err| {
                std.log.err("Unable to spawn connection thread: {s}", .{@errorName(err)});
                connection.stream.close();

                continue;
            };
        }
    }
};

fn accept(this: *Server, connection: std.net.Server.Connection, handler: Handler) !void {
    defer connection.stream.close();

    var res = response.Response.init(connection.stream.writer().any(), request.HttpVersion.http1_1);

    var req = request.parse_request_headers_to_request(this.allocator, connection.stream.reader().any()) catch |err| {
        var headers = std.StringHashMap([]const u8).init(this.allocator);
        defer headers.deinit();

        try headers.put("Content-Type", "text/plain; charset=UTF-8");

        try switch (err) {
            request.RequestError.InternalError => res.respond(response.StatusCode.internal_server_error, headers, "Internal server error"),
            request.RequestError.InvalidRequest => res.respond(response.StatusCode.bad_request, headers, "Bad request"),
            request.RequestError.EntityTooLarge => res.respond(response.StatusCode.content_too_large, headers, "Content too large"),
            request.RequestError.UnsupportedMethod => res.respond(response.StatusCode.method_not_allowed, headers, "Method not allowed"),
            request.RequestError.UnsupportedHttpVersion => res.respond(response.StatusCode.http_version_not_supported, headers, "Http version not supported"),
        };

        return;
    };
    defer req.deinit();

    handler(&req, &res) catch |err| {
        std.log.err("Handler error: {s}", .{@errorName(err)});
    };

    std.debug.print("closed req? {any}\n\n\n\n\n\n", .{res.has_responded});
}
