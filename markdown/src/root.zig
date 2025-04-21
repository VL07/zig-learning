const std = @import("std");
// std.io.Reader(comptime Context: type, comptime ReadError: type, comptime readFn: fn(context:Context, buffer:[]u8)ReadError!usize)
// std.io.Writer(comptime Context: type, comptime WriteError: type, comptime writeFn: fn(context:Context, bytes:[]const u8)WriteError!usize)
pub const MarkdownError = error{InvalidMarkdown};

pub const Markdown = struct {
    reader_done: bool = false,
    bytes_written: usize = 0,

    pub fn init() Markdown {
        return Markdown{};
    }

    pub fn parseMarkdown(this: *Markdown, reader: anytype, writer: anytype) anyerror!usize {
        while (!this.reader_done) {
            try this.parseSatement(reader, writer);
        }

        return this.bytes_written;
    }

    fn readChar(this: *Markdown, reader: anytype) ?u8 {
        const char = reader.readByte() catch {
            this.reader_done = true;

            return null;
        };

        return char;
    }

    fn writeCharOrBreakString(this: *Markdown, writer: anytype, char: u8) anyerror!void {
        if (getBreakString(char)) |break_string| {
            try writer.writeAll(break_string);
            this.bytes_written += break_string.len;
        } else {
            try writer.writeByte(char);
            this.bytes_written += 1;
        }
    }

    fn skipWhitespaceReadChar(this: *Markdown, reader: anytype) ?u8 {
        while (true) {
            const char = this.readChar(reader) orelse return null;

            if (!isWhitespace(char)) return char;
        }
    }

    fn skipNonNewLineWhitespaceReadChar(this: *Markdown, reader: anytype) ?u8 {
        while (true) {
            const char = this.readChar(reader) orelse return null;

            if (char == '\n' or !isWhitespace(char)) return char;
        }
    }

    fn readWriteUntilCharSkipWhitespace(this: *Markdown, reader: anytype, writer: anytype, break_char: u8) anyerror!?u8 {
        var last_was_whitespace = false;
        while (this.readChar(reader)) |char| {
            if (char == break_char) return char;

            if (isWhitespace(char)) {
                if (last_was_whitespace) continue;

                last_was_whitespace = true;

                try writer.writeByte(' ');
                this.bytes_written += 1;
                continue;
            }

            last_was_whitespace = false;

            try this.writeCharOrBreakString(writer, char);
        }

        return null;
    }

    fn parseSatement(this: *Markdown, reader: anytype, writer: anytype) anyerror!void {
        const char = this.skipWhitespaceReadChar(reader) orelse return;

        try switch (char) {
            '#' => this.makeHeading(reader, writer),
            else => this.makeParagraph(reader, writer, char),
        };
    }

    fn makeHeading(this: *Markdown, reader: anytype, writer: anytype) anyerror!void {
        var headingType: u8 = 1;

        while (this.readChar(reader) orelse return == '#') {
            headingType += 1;

            if (headingType > 6) {
                std.log.warn("Invalid heading type", .{});

                return MarkdownError.InvalidMarkdown;
            }
        }

        try writer.print("<h{d}>", .{headingType});
        this.bytes_written += 4;

        _ = try this.readWriteUntilCharSkipWhitespace(reader, writer, '\n');

        try writer.print("</h{d}>\n", .{headingType});
        this.bytes_written += 6;
    }

    fn makeParagraph(this: *Markdown, reader: anytype, writer: anytype, start_char: u8) anyerror!void {
        try writer.writeAll("<p>");
        this.bytes_written += 3;

        try this.writeCharOrBreakString(writer, start_char);

        while (true) {
            _ = try this.readWriteUntilCharSkipWhitespace(reader, writer, '\n') orelse break;
            const char = this.skipNonNewLineWhitespaceReadChar(reader) orelse break;

            if (char == '\n') break;

            try writer.writeAll("<br>");
            this.bytes_written += 4;

            try this.writeCharOrBreakString(writer, char);
        }

        try writer.writeAll("</p>\n");
        this.bytes_written += 5;
    }
};

fn isWhitespace(char: u8) bool {
    return char == ' ' or char == '\t' or char == '\n';
}

fn getBreakString(char: u8) ?[]const u8 {
    switch (char) {
        '<' => return "&lt;",
        '>' => return "&gt;",
        else => return null,
    }
}

fn testParse(input: []const u8, expectd_output: []const u8) anyerror!void {
    var input_stream = std.io.fixedBufferStream(input);
    var input_reader = std.io.bufferedReader(input_stream.reader());

    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    const list_writer = list.writer();
    var buffered_writer = std.io.BufferedWriter(1024, @TypeOf(list_writer)){ .unbuffered_writer = list_writer };

    var markdown = Markdown.init();
    const bytes_written = try markdown.parseMarkdown(input_reader.reader(), buffered_writer.writer());

    try buffered_writer.flush();

    try std.testing.expectEqualStrings(expectd_output, list.items);
    try std.testing.expectEqual(list.items.len, bytes_written);
}

test "should parse heading correctly" {
    try testParse("# Hello world", "<h1>Hello world</h1>\n");
    try testParse("## Hello world", "<h2>Hello world</h2>\n");
    try testParse("### Hello world", "<h3>Hello world</h3>\n");
}

test "should parse paragraph correctly" {
    try testParse("Hello world", "<p>Hello world</p>\n");
    try testParse("Hello\n world", "<p>Hello<br>world</p>\n");
    try testParse("Hello\n\nworld", "<p>Hello</p>\n<p>world</p>\n");
}

test "should parse header and paragraph correctly" {
    try testParse(
        \\ # Document
        \\
        \\ This document        is about something     and i don't care.
        \\ 
        \\ ## Subheading
        \\ 
        \\ This is a subheading.
        \\ Oh newline.
        \\
        \\ New paragraph.
        \\
        \\ ## Another subheading
        \\ 
        \\ Subheading nr <2>
    ,
        \\<h1>Document</h1>
        \\<p>This document is about something and i don't care.</p>
        \\<h2>Subheading</h2>
        \\<p>This is a subheading.<br>Oh newline.</p>
        \\<p>New paragraph.</p>
        \\<h2>Another subheading</h2>
        \\<p>Subheading nr &lt;2&gt;</p>
        \\
    );
}
