const std = @import("std");
const jetzig = @import("jetzig");

pub const defaults: jetzig.mail.DefaultMailParams = .{
    .from = .{ .email = "no-reply@localhost" },
    .subject = "Verify your email to continue registration",
};

pub fn deliver(
    allocator: std.mem.Allocator,
    mail: *jetzig.mail.MailParams,
    params: *jetzig.data.Value,
    env: jetzig.jobs.JobEnv,
) !void {
    _ = allocator;
    _ = mail;
    _ = params;
    _ = env;
}
