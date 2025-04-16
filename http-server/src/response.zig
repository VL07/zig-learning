const std = @import("std");

const Connection = std.net.Server.Connection;

pub fn respond_to_request(statusCode: u16, statusMessage: []const u8, conn: Connection, body: []const u8) !void {
    _ = try conn.stream.writer().print(
        \\ HTTP/1.1 {d} {s}
        \\ Content-Type: text/html
        \\ Connection: Closed
        \\
        \\ {s}    
    , .{ statusCode, statusMessage, body });
}
