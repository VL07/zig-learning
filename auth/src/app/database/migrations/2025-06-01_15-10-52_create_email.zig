const std = @import("std");
const jetquery = @import("jetquery");
const t = jetquery.schema.table;

pub fn up(repo: anytype) !void {
    try repo.createTable(
        "email",
        &.{
            t.primaryKey("id", .{}),
            t.column("account_id", .integer, .{ .reference = .{ "account", "id" }, .index = true, .optional = false }),
            t.column("email", .string, .{ .length = 100, .unique = true, .index = true, .optional = false }),
            t.column("verified_at", .datetime, .{ .optional = true }),
            t.column("last_sign_in_at", .datetime, .{ .optional = true }),
            t.column("is_primary", .boolean, .{ .optional = false }),
            t.timestamps(.{}),
        },
        .{},
    );
}

pub fn down(repo: anytype) !void {
    try repo.dropTable("email", .{});
}
