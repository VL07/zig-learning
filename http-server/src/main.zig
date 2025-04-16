const std = @import("std");
const config = @import("config.zig");
const request = @import("request.zig");
const response = @import("response.zig");

const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    const socket = try config.Socket.init();
    try stdout.print("Server addr: {any}\n", .{socket.address});

    var server = try socket.address.listen(.{});
    defer server.deinit();

    while (true) {
        const connection = try server.accept();
        defer connection.stream.close();

        var buffer = [_]u8{0} ** 1000;

        try request.read_request(connection, buffer[0..]);
        const req = request.parse_request(buffer[0..]) catch |err| {
            std.debug.print("{}\n", .{err});

            try response.respond_to_request(400, "Bad Request", connection,
                \\ <html><body><h1>Bad request!</h1></body></html>
            );

            continue;
        };

        if (req.method == .GET) {
            if (std.mem.eql(u8, req.uri, "/")) {
                try response.respond_to_request(200, "Ok", connection,
                    \\ <html><body><h1>Hello world!</h1><form method="POST"><button type="submit">POST</button></form></body></html>
                );
            } else {
                try response.respond_to_request(404, "Not Found", connection,
                    \\ <html><body><h1>Not found!</h1></body></html>
                );
            }
        } else {
            try response.respond_to_request(405, "Method Not Allowed", connection,
                \\ <html><body><h1>Method not allowed!</h1></body></html>
            );
        }
    }
}
