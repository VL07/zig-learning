const jetquery = @import("jetzig").jetquery;

pub const Account = jetquery.Model(
    @This(),
    "account",
    struct {
        id: i32,
        username: []const u8,
        password: []const u8,
        last_sign_in_at: ?jetquery.DateTime,
        created_at: jetquery.DateTime,
        updated_at: jetquery.DateTime,
    },
    .{
        .relations = .{
            .email_whitelist = jetquery.hasMany(.EmailWhitelist, .{ .foreign_key = "created_by_account_id" }),
            .email = jetquery.hasMany(.Email, .{}),
            .session = jetquery.hasMany(.Session, .{}),
        },
    },
);

pub const Email = jetquery.Model(
    @This(),
    "email",
    struct {
        id: i32,
        account_id: i32,
        email: []const u8,
        email_whitelist_pattern_id: ?i32,
        verified_at: ?jetquery.DateTime,
        last_sign_in_at: ?jetquery.DateTime,
        is_primary: bool,
        created_at: jetquery.DateTime,
        updated_at: jetquery.DateTime,
    },
    .{
        .relations = .{
            .account = jetquery.belongsTo(.Account, .{}),
            .email_whitelist = jetquery.belongsTo(.EmailWhitelist, .{ .foreign_key = "email_whitelist_pattern_id" }),
            .session = jetquery.hasMany(.Session, .{ .foreign_key = "email_used_id" }),
        },
    },
);

pub const EmailWhitelist = jetquery.Model(
    @This(),
    "email_whitelist",
    struct {
        id: i32,
        pattern: []const u8,
        created_by_account_id: i32,
        created_at: jetquery.DateTime,
        updated_at: jetquery.DateTime,
    },
    .{
        .relations = .{
            .account = jetquery.belongsTo(.Account, .{ .foreign_key = "created_by_account_id" }),
            .email = jetquery.hasMany(.Email, .{ .foreign_key = "email_whitelist_pattern_id" }),
        },
    },
);

pub const Session = jetquery.Model(
    @This(),
    "session",
    struct {
        id: i32,
        account_id: i32,
        token: []const u8,
        email_used_id: i32,
        expires_at: jetquery.DateTime,
        last_used_at: jetquery.DateTime,
        last_used_ip: []const u8,
        is_short_lived: bool,
        created_at: jetquery.DateTime,
        updated_at: jetquery.DateTime,
    },
    .{
        .relations = .{
            .account = jetquery.belongsTo(.Account, .{}),
            .email = jetquery.belongsTo(.Email, .{ .foreign_key = "email_used_id" }),
        },
    },
);

pub const EmailVerification = jetquery.Model(
    @This(),
    "email_verification",
    struct {
        id: i32,
        account_id: ?i32,
        public_id: []const u8,
        hash: []const u8,
        email: []const u8,
        email_whitelist_pattern_id: ?i32,
        created_at: jetquery.DateTime,
        updated_at: jetquery.DateTime,
    },
    .{},
);
