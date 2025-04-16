const std = @import("std");

const Connection = std.net.Server.Connection;
const StaticStringMap = std.static_string_map.StaticStringMap;

/// Maping mehod name to `Method` enum.
const MethodMap = StaticStringMap(Method).initComptime(.{.{ "GET", Method.GET }});

const RequestError = error{
    MissingMethod,
    MissingUri,
    MissingVersion,
    UnsupportedMethod,
};

/// Request methods
pub const Method = enum {
    GET,

    /// Initialize the method from the name of the method.
    pub fn init(text: []const u8) RequestError!Method {
        return MethodMap.get(text) orelse RequestError.UnsupportedMethod;
    }

    /// Checks if the method is supported.
    pub fn is_supported(method_text: []const u8) bool {
        const method = MethodMap.get(method_text);
        if (method) |_| return true;

        return false;
    }
};

/// Request object that handles parsing.
const Request = struct {
    /// The method of the http request.
    method: Method,

    /// Which http version the request is using.
    version: []const u8,

    /// Path of the uri. Does not include domain, only path and query params.
    uri: []const u8,

    pub fn init(method: Method, uri: []const u8, version: []const u8) Request {
        return Request{ .method = method, .uri = uri, .version = version };
    }
};

/// Reads the data from the connection and saves it into the buffer.
pub fn read_request(conn: Connection, buffer: []u8) !void {
    const reader = conn.stream.reader();
    _ = try reader.read(buffer);
}

pub fn parse_request(text: []u8) RequestError!Request {
    const line_index = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
    var iterator = std.mem.splitScalar(u8, text[0..line_index], ' ');

    const method = try Method.init(iterator.next() orelse return RequestError.MissingMethod);
    const uri = iterator.next() orelse return RequestError.MissingUri;
    const version = iterator.next() orelse return RequestError.MissingVersion;
    const request = Request.init(method, uri, version);

    return request;
}
