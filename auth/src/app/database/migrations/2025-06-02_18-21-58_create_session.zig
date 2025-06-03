const std = @import("std");
const jetquery = @import("jetquery");
const t = jetquery.schema.table;

pub fn up(repo: anytype) !void {
    try repo.createTable(
        "session",
        &.{
            t.primaryKey("id", .{}),
            t.column("account_id", .integer, .{ .reference = .{ "account", "id" }, .index = true, .optional = false }),
            t.column("token", .string, .{ .index = true, .unique = true, .optional = false }),
            t.column("email_used_id", .integer, .{ .reference = .{ "email", "id" }, .optional = false }),
            t.column("expires_at", .datetime, .{ .optional = false }),
            t.column("last_used_at", .datetime, .{ .optional = false }),
            t.column("last_used_ip", .string, .{ .length = 50, .optional = false }),
            t.column("is_short_lived", .boolean, .{ .optional = false }),
            t.timestamps(.{}),
        },
        .{},
    );
}

pub fn down(repo: anytype) !void {
    try repo.dropTable("session", .{});
}
