const std = @import("std");
const request = @import("request.zig");

// Thank you ChatGPT for this boilerplate.
pub const StatusCode = enum(u16) {
    continue_ = 100,
    switching_protocols = 101,
    processing = 102,
    early_hints = 103,

    ok = 200,
    created = 201,
    accepted = 202,
    non_authoritative_information = 203,
    no_content = 204,
    reset_content = 205,
    partial_content = 206,

    multiple_choices = 300,
    moved_permanently = 301,
    found = 302,
    see_other = 303,
    not_modified = 304,
    temporary_redirect = 307,
    permanent_redirect = 308,

    bad_request = 400,
    unauthorized = 401,
    payment_required = 402,
    forbidden = 403,
    not_found = 404,
    method_not_allowed = 405,
    not_acceptable = 406,
    request_timeout = 408,
    conflict = 409,
    gone = 410,
    content_too_large = 413,
    uri_too_long = 414,
    unsupported_media_type = 415,
    too_many_requests = 429,

    internal_server_error = 500,
    not_implemented = 501,
    bad_gateway = 502,
    service_unavailable = 503,
    gateway_timeout = 504,
    http_version_not_supported = 505,

    fn to_status_message(this: StatusCode) []const u8 {
        return switch (this) {
            .continue_ => "Continue",
            .switching_protocols => "Switching Protocols",
            .processing => "Processing",
            .early_hints => "Early Hints",

            .ok => "OK",
            .created => "Created",
            .accepted => "Accepted",
            .non_authoritative_information => "Non-Authoritative Information",
            .no_content => "No Content",
            .reset_content => "Reset Content",
            .partial_content => "Partial Content",

            .multiple_choices => "Multiple Choices",
            .moved_permanently => "Moved Permanently",
            .found => "Found",
            .see_other => "See Other",
            .not_modified => "Not Modified",
            .temporary_redirect => "Temporary Redirect",
            .permanent_redirect => "Permanent Redirect",

            .bad_request => "Bad Request",
            .unauthorized => "Unauthorized",
            .payment_required => "Payment Required",
            .forbidden => "Forbidden",
            .not_found => "Not Found",
            .method_not_allowed => "Method Not Allowed",
            .not_acceptable => "Not Acceptable",
            .request_timeout => "Request Timeout",
            .conflict => "Conflict",
            .gone => "Gone",
            .content_too_large => "Content Too Large",
            .uri_too_long => "URI Too Long",
            .unsupported_media_type => "Unsupported Media Type",
            .too_many_requests => "Too Many Requests",

            .internal_server_error => "Internal Server Error",
            .not_implemented => "Not Implemented",
            .bad_gateway => "Bad Gateway",
            .service_unavailable => "Service Unavailable",
            .gateway_timeout => "Gateway Timeout",
            .http_version_not_supported => "HTTP Version Not Supported",
        };
    }
};

pub const Response = struct {
    writer: std.io.AnyWriter,
    http_version: request.HttpVersion,
    has_responded: bool,

    pub fn init(writer: std.io.AnyWriter, http_version: request.HttpVersion) Response {
        return Response{
            .writer = writer,
            .http_version = http_version,
            .has_responded = false,
        };
    }

    pub fn respond(this: *Response, status: StatusCode, headers: std.StringHashMap([]const u8), body: []const u8) !void {
        if (this.has_responded) {
            std.log.err("Response to this request has already been sent. Can only respond to a request once. ", .{});

            return;
        }

        this.has_responded = true;

        try this.writer.print("{s} {d} {s}\n", .{
            this.http_version.to_string(),
            @intFromEnum(status),
            status.to_status_message(),
        });

        var header_iterator = headers.iterator();
        while (header_iterator.next()) |entry| {
            try this.writer.print("{s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        try this.writer.print("Content-Length: {d}\n\n", .{body.len});
        try this.writer.writeAll(body);
    }
};
