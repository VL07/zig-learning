const std = @import("std");
const jetquery = @import("jetquery");
const t = jetquery.schema.table;

pub fn up(repo: anytype) !void {
    try repo.createTable(
        "account",
        &.{
            t.primaryKey("id", .{}),
            t.column("username", .string, .{ .length = 32, .index = true, .optional = false }),
            t.column("password", .text, .{ .optional = false }),
            t.column("last_sign_in_at", .datetime, .{ .optional = true }),
            t.timestamps(.{}),
        },
        .{},
    );
}

pub fn down(repo: anytype) !void {
    try repo.dropTable("account", .{});
}
