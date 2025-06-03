const std = @import("std");
const jetzig = @import("jetzig");

pub fn index(request: *jetzig.Request) !jetzig.View {
    const account = request.middleware(.auth).account orelse return request.fail(.unauthorized);

    const root = try request.data(.object);
    try root.put("username", account.username);

    return request.render(.ok);
}
