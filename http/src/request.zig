const std = @import("std");

const RequestError = error{
    InternalError,
    InvalidRequest,
    EntityTooLarge,
    UnsupportedMethod,
    UnsupportedHttpVersion,
};

const Method = enum {
    const staticMap = std.StaticStringMap(Method).initComptime(.{
        .{ "GET", Method.get },
        .{ "POST", Method.post },
        .{ "PUT", Method.put },
        .{ "PATCH", Method.patch },
        .{ "DELETE", Method.delete },
    });

    get,
    post,
    put,
    patch,
    delete,

    pub fn from_string(name: []const u8) RequestError!Method {
        const method = Method.staticMap.get(name) orelse return RequestError.UnsupportedMethod;

        return method;
    }
};

const HttpVersion = enum {
    const staticMap = std.StaticStringMap(HttpVersion).initComptime(.{
        .{ "HTTP/1.1", HttpVersion.http1_1 },
    });

    http1_1,

    pub fn from_string(name: []const u8) RequestError!HttpVersion {
        const version = HttpVersion.staticMap.get(name) orelse return RequestError.UnsupportedHttpVersion;

        return version;
    }
};

pub const Request = struct {
    allocator: std.mem.Allocator,
    method: Method,
    uri: []const u8,
    http_version: HttpVersion,
    headers: std.StringHashMap([]const u8),
    reader: std.io.AnyReader,

    pub fn init(
        allocator: std.mem.Allocator,
        method: Method,
        uri: []const u8,
        http_version: HttpVersion,
        headers: std.StringHashMap([]const u8),
        reader: std.io.AnyReader,
    ) RequestError!Request {
        return Request{
            .allocator = allocator,
            .method = method,
            .uri = uri,
            .http_version = http_version,
            .headers = headers,
            .reader = reader,
        };
    }

    pub fn deinit(this: *Request) void {
        this.allocator.free(this.uri);

        var headers_iterator = this.headers.iterator();
        while (headers_iterator.next()) |entry| {
            this.allocator.free(entry.key_ptr.*);
            this.allocator.free(entry.value_ptr.*);
        }

        this.headers.deinit();
    }
};

fn is_whitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r' or c == '\n';
}

fn strip_slice_whitespace(s: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = s.len;

    while (start < end and is_whitespace(s[start])) : (start += 1) {}
    while (end > start and is_whitespace(s[end - 1])) : (end -= 1) {}

    return s[start..end];
}

fn read_request_header_line(reader: std.io.AnyReader) RequestError![]const u8 {
    var request_line: [8193]u8 = undefined; // 8192 + 1
    var request_line_stream = std.io.fixedBufferStream(&request_line);
    const writer = request_line_stream.writer();

    reader.streamUntilDelimiter(writer, '\n', request_line.len) catch |err| {
        if (err == error.StreamTooLong) return RequestError.EntityTooLarge;
        if (err != error.EndOfStream) return RequestError.InternalError;
    };

    const line = strip_slice_whitespace(request_line[0..request_line_stream.pos]);

    return line;
}

pub fn parse_request_headers_to_request(allocator: std.mem.Allocator, reader: std.io.AnyReader) RequestError!Request {
    const request_line = try read_request_header_line(reader);
    var total_length: usize = request_line.len;
    if (total_length > 8192) return RequestError.EntityTooLarge;

    var iterator = std.mem.splitScalar(u8, request_line, ' ');
    const method = try Method.from_string(iterator.next() orelse return RequestError.InvalidRequest);
    const uri_slice = iterator.next() orelse return RequestError.InvalidRequest;
    const uri = allocator.dupe(u8, uri_slice) catch return RequestError.InternalError;
    errdefer allocator.free(uri);
    const http_version = try HttpVersion.from_string(iterator.next() orelse return RequestError.InvalidRequest);

    var headers = std.StringHashMap([]const u8).init(allocator);
    errdefer {
        var headers_iterator = headers.iterator();
        while (headers_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }

        headers.deinit();
    }

    while (true) {
        const header_line = try read_request_header_line(reader);
        if (header_line.len == 0 or std.mem.eql(u8, header_line, "\n")) break;

        total_length += header_line.len;
        if (total_length > 8192) return RequestError.EntityTooLarge;

        const header_split_index = std.mem.indexOfScalar(u8, header_line, ':') orelse return RequestError.InvalidRequest;

        const key = allocator.dupe(u8, strip_slice_whitespace(header_line[0..header_split_index])) catch return RequestError.InternalError;
        const value = allocator.dupe(u8, strip_slice_whitespace(header_line[(header_split_index + 1)..header_line.len])) catch return RequestError.InternalError;

        // TODO: Allow for multiple headers with same key
        headers.put(key, value) catch |err| {
            std.log.err("Error while putting header in map: {s}", .{@errorName(err)});

            return RequestError.InternalError;
        };
    }

    return Request.init(allocator, method, uri, http_version, headers, reader);
}

fn are_request_headers_equal(a: std.StringHashMap([]const u8), b: std.StringHashMap([]const u8)) bool {
    if (a.count() != b.count()) return false;

    var iterator = a.keyIterator();
    while (iterator.next()) |key| {
        const a_value = a.get(key.*) orelse unreachable;
        const b_value = b.get(key.*) orelse return false;

        if (!std.mem.eql(u8, a_value, b_value)) return false;
    }

    return true;
}

test "should parse request headers correctly" {
    const request_payload: []const u8 =
        \\ GET /hello HTTP/1.1
        \\ Host: example.com
        \\ User-Agent: curl/8.6.0
        \\ Accept: */*
    ;
    var reqeustStream = std.io.fixedBufferStream(request_payload);
    const requestReader = reqeustStream.reader().any();

    var expected_headers_map = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer expected_headers_map.deinit();
    try expected_headers_map.put("Host", "example.com");
    try expected_headers_map.put("User-Agent", "curl/8.6.0");
    try expected_headers_map.put("Accept", "*/*");

    var request = try parse_request_headers_to_request(std.testing.allocator, requestReader);
    defer request.deinit();

    try std.testing.expectEqual(Method.get, request.method);
    try std.testing.expectEqualStrings("/hello", request.uri);
    try std.testing.expectEqual(HttpVersion.http1_1, request.http_version);
    try std.testing.expect(are_request_headers_equal(expected_headers_map, request.headers));
}

test "should handle unsupported method" {
    const request_payload: []const u8 =
        \\ ROBLOX /hello HTTP/1.1
        \\ Host: example.com
    ;

    var reqeustStream = std.io.fixedBufferStream(request_payload);
    const requestReader = reqeustStream.reader().any();

    try std.testing.expectError(RequestError.UnsupportedMethod, parse_request_headers_to_request(std.testing.allocator, requestReader));
}

test "should handle unsupported http version" {
    const request_payload: []const u8 =
        \\ POST /hello HTTP/2
        \\ Host: example.com
    ;

    var reqeustStream = std.io.fixedBufferStream(request_payload);
    const requestReader = reqeustStream.reader().any();

    try std.testing.expectError(RequestError.UnsupportedHttpVersion, parse_request_headers_to_request(std.testing.allocator, requestReader));
}

test "should handle too big requests" {
    const request_payload: []const u8 =
        \\ POST /hello HTTP/1.1
        \\ Host: example.com
        \\ Big-Header: 
    ++ ([_]u8{'a'} ** 10000);

    var reqeustStream = std.io.fixedBufferStream(request_payload);
    const requestReader = reqeustStream.reader().any();

    try std.testing.expectError(RequestError.EntityTooLarge, parse_request_headers_to_request(std.testing.allocator, requestReader));
}
