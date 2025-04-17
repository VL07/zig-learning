const std = @import("std");
pub const server = @import("server.zig");

test {
    std.testing.refAllDecls(@This());
}
