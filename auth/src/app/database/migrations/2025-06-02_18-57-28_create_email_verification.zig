const std = @import("std");
const jetquery = @import("jetquery");
const t = jetquery.schema.table;

pub fn up(repo: anytype) !void {
    try repo.createTable(
        "email_verification",
        &.{
            t.primaryKey("id", .{}),
            t.column("account_id", .integer, .{ .reference = .{ "account", "id" }, .optional = true }),
            t.column("public_id", .string, .{ .optional = false }),
            t.column("hash", .string, .{ .optional = false }),
            t.column("email", .string, .{ .index = true, .optional = false }),
            t.column("email_whitelist_pattern_id", .integer, .{ .index = true, .reference = .{ "email_whitelist", "id" }, .optional = true }),
            t.timestamps(.{}),
        },
        .{},
    );
}

pub fn down(repo: anytype) !void {
    try repo.dropTable("email_verification", .{});
}
