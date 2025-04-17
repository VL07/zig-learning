const std = @import("std");
const http = @import("http_lib");

const allocator = std.heap.page_allocator;

pub fn main() !void {
    var server = http.Server.init(allocator, std.net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, 3333));

    const callback = struct {
        fn callback(s: *const http.Server) !void {
            std.debug.print("Listening at: http://{any}\n", .{s.address});
        }
    }.callback;

    try server.listen(callback, handler);
}

fn handler(req: *http.Request, res: *http.Response) !void {
    std.debug.print("Incomming request: {s} {s}\n", .{ @tagName(req.method), req.uri });

    var headers = std.StringHashMap([]const u8).init(allocator);
    try headers.put("Content-Type", "text/html");
    try headers.put("X-Hello-World", "Hello-World");

    if (req.method == .get and std.mem.eql(u8, req.uri, "/")) {
        try res.respond(
            .ok,
            headers,
            "<html><body><h1>Hello World</h1></body></html>",
        );

        return;
    }

    try res.respond(
        .not_found,
        headers,
        "<html><head><style>h1{color:red;}</style></head><body><h1>404 Page not found</h1></body></html>",
    );
}
