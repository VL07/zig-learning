const std = @import("std");
const jetquery = @import("jetquery");
const t = jetquery.schema.table;

pub fn up(repo: anytype) !void {
    try repo.createTable(
        "email_whitelist",
        &.{
            t.primaryKey("id", .{}),
            t.column("pattern", .string, .{ .optional = false }),
            t.column("created_by_account_id", .integer, .{ .reference = .{ "account", "id" }, .optional = false }),
            t.timestamps(.{}),
        },
        .{},
    );
}

pub fn down(repo: anytype) !void {
    try repo.dropTable("email_whitelist", .{});
}
