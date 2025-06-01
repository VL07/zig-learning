const jetzig = @import("jetzig");

pub fn add_seconds(time: jetzig.DateTime, seconds: i64) jetzig.DateTime {
    return jetzig.DateTime.fromUnix(time.unix(.seconds) + seconds, .seconds) catch unreachable;
}
