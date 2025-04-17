const std = @import("std");
const request = @import("request.zig");

pub const Server = struct {
    allocator: std.mem.Allocator,
    address: std.net.Address,

    pub fn init(allocator: std.mem.Allocator, address: std.net.Address) Server {
        return Server{
            .allocator = allocator,
            .address = address,
        };
    }

    pub fn listen(this: *Server, callback_fn: fn (*const Server) anyerror!void) !void {
        var server = try this.address.listen(.{ .reuse_address = true });
        defer server.deinit();

        try callback_fn(this);

        while (true) {
            const connection = server.accept() catch |err| {
                std.log.err("Failed to accept connection: {s}", .{@errorName(err)});

                continue;
            };

            _ = std.Thread.spawn(.{}, accept, .{ this, connection }) catch |err| {
                std.log.err("Unable to spawn connection thread: {s}", .{@errorName(err)});
                connection.stream.close();

                continue;
            };
        }
    }
};

fn accept(this: *Server, connection: std.net.Server.Connection) !void {
    defer connection.stream.close();

    var accepted_request = try request.parse_request_headers_to_request(this.allocator, connection.stream.reader().any());
    defer accepted_request.deinit();

    std.debug.print("Incomming request: {s} {s}\n", .{ @tagName(accepted_request.method), accepted_request.uri });
}
