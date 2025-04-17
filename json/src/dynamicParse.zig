const std = @import("std");

const testing = std.testing;

// std.json.parseFromSlice(comptime T: type, allocator: Allocator, s: []const u8, options: ParseOptions)
// std.json.parsefromste

/// Options for parsing json
pub const DynamicParserOptions = struct {
    /// Maximum number of values in a parsed json object. Counts values in arrays and objects aswell as the arrays and objects.
    max_values: usize = 10_000,

    /// Max size in bytes a string can be
    max_string_size: ?usize = 1_000_000,
};

const DynamicParserError = error{
    InvalidJson,
    InternalError,
    TooManyValues,
    StringTooBig,
};

const DynamicValueType = enum {
    string,
    integer,
    float,
};

const DynamicValue = union(DynamicValueType) {
    string: []const u8,
    integer: i64,
    float: f64,
};

const DynamicParsed = struct {
    arena: *std.heap.ArenaAllocator,
    base_dynamic_value: *DynamicValue,

    pub fn init(arena: *std.heap.ArenaAllocator, base_dynamic_value: *DynamicValue) DynamicParsed {
        return DynamicParsed{
            .arena = arena,
            .base_dynamic_value = base_dynamic_value,
        };
    }

    pub fn deinit(this: *DynamicParsed) void {
        this.arena.deinit();
    }
};

const DynamicParser = struct {
    arena: *std.heap.ArenaAllocator,
    reader: std.io.AnyReader,
    options: DynamicParserOptions,

    pub fn init(arena: *std.heap.ArenaAllocator, reader: std.io.AnyReader, options: DynamicParserOptions) DynamicParser {
        return DynamicParser{
            .arena = arena,
            .reader = reader,
            .options = options,
        };
    }

    pub fn parse(this: *DynamicParser) DynamicParserError!DynamicParsed {
        const dynamic_value = try this.parse_value();

        return DynamicParsed.init(this.arena, dynamic_value);
    }

    /// Reads from the reader untill no whitespace is found returning the last character.
    fn consume_whitespace(this: *DynamicParser) DynamicParserError!u8 {
        var last_char: u8 = ' ';
        while (is_whitespace(last_char)) {
            last_char = this.reader.readByte() catch |err| {
                std.debug.print("Error while reading byte: {}", .{err});

                return DynamicParserError.InvalidJson;
            };
        }

        return last_char;
    }

    /// Make a string or return `DynamicParserError` error if not possible.
    fn read_string(this: *DynamicParser, delimiter: u8) DynamicParserError![]const u8 {
        var string_chars_array = std.ArrayList(u8).init(this.arena.allocator());
        defer string_chars_array.deinit();

        this.reader.streamUntilDelimiter(string_chars_array.writer(), delimiter, this.options.max_string_size) catch |err| {
            if (err == error.StreamTooLong) return DynamicParserError.StringTooBig;

            std.debug.print("Error reading string value: {}", .{err});

            return DynamicParserError.InternalError;
        };

        const as_slice = string_chars_array.toOwnedSlice() catch |err| {
            std.debug.panic("Error allocating: {}", .{err});

            return DynamicParserError.InternalError;
        };

        return as_slice;
    }

    /// Consume and parse a single value, for example a string or a object. Stores the parsed value on the heap using arena allocator.
    fn parse_value(this: *DynamicParser) DynamicParserError!*DynamicValue {
        const current_char = try this.consume_whitespace();

        const dynamic_value_ptr = this.arena.allocator().alloc(DynamicValue, 1) catch |err| {
            std.debug.print("Error while allocating: {}", .{err});

            return DynamicParserError.InternalError;
        };

        dynamic_value_ptr[0] = try switch (current_char) {
            '"', '\'' => this.make_string_dynamic_value(current_char),
            else => return DynamicParserError.InvalidJson,
        };

        return &dynamic_value_ptr[0];
    }

    fn make_string_dynamic_value(this: *DynamicParser, delimiter: u8) DynamicParserError!DynamicValue {
        return DynamicValue{
            .string = try this.read_string(delimiter),
        };
    }
};

fn is_whitespace(char: u8) bool {
    return char == ' ' or char == '\t' or char == '\n';
}

pub fn parse_dynamic_from_slice(slice: []const u8, arena: *std.heap.ArenaAllocator, options: DynamicParserOptions) DynamicParserError!DynamicParsed {
    var fbs = std.io.fixedBufferStream(slice);
    const reader = fbs.reader().any();
    var parser = DynamicParser.init(arena, reader, options);

    return try parser.parse();
}

test "should parse simple string json" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    var parsed = try parse_dynamic_from_slice("\"Hello world\"", &arena, .{});
    defer parsed.deinit();

    try testing.expect(parsed.base_dynamic_value.* == .string);
    try testing.expectEqualStrings("Hello world", parsed.base_dynamic_value.string);
}
