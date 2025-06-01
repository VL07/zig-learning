const jetzig = @import("jetzig");

pub fn get_table_row_type(comptime model: anytype) type {
    return @TypeOf(jetzig.database.Query(model).find(0)).ResultType;
}

pub const AccountRow = get_table_row_type(.Account);
pub const EmailRow = get_table_row_type(.Email);
pub const SessionRow = get_table_row_type(.Session);
