const std = @import("std");
const http = @import("http_lib");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var server = http.server.Server.init(allocator, std.net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, 3333));

    const callback = struct {
        fn callback(s: *const http.server.Server) !void {
            std.debug.print("Listening at: http://{any}\n", .{s.address});
        }
    }.callback;

    try server.listen(callback);
}
