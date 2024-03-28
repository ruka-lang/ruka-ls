const ruka_ls = @import("../root.zig");

const std = @import("std");
const json = std.json;

in: std.io.BufferedReader(4096, std.io.AnyReader),
out: std.io.AnyWriter,

const Transport = @This();

const log = std.log.scoped(.transport);

pub fn init(in: std.io.AnyReader, out: std.io.AnyWriter) Transport {
    return .{
        .in = std.io.bufferedReader(in),
        .out = out
    };
}

const Header = struct {
    length: usize,
    
    pub fn parse(allocator: std.mem.Allocator, reader: anytype) !Header {
        var h = Header{
            .length = undefined
        }; 

        while (true) {
            const header = try reader.readUntilDelimiterAlloc(allocator, '\n', 0x100);
            defer allocator.free(header);

            if (header.len == 0 or header[header.len - 1] != '\r') 
                return error.MissingCarrigeReturn;

            if (header.len == 1) break;

            log.info("{s}", .{header});
            const length = std.fmt.parseUnsigned(usize, header[16..header.len - 1], 10) 
                catch return error.CouldNotParseContentLength;

            h.length = length; 
        }

        return h;
    }
};

pub fn encodeMessage(_: *const Transport, allocator: std.mem.Allocator, msg: anytype) ![]const u8 {
    const content = try json.stringifyAlloc(allocator, msg, .{});
    defer allocator.free(content);
    const content_length = content.len;
    
    const result = try std.fmt.allocPrint(allocator, "Content-Length: {d}\r\n\r\n{s}", 
        .{content_length, content});

    return result;
}

pub fn sendJsonMesage(_: *Transport, _: std.mem.Allocator, _: anytype) !void {

}

/// Returns the json content from the request sent to the `Transport`'s reader.
/// Caller is responsible for the returned memory when successful
pub fn readJsonMessage(self: *Transport, allocator: std.mem.Allocator) ![]u8 {
    const reader = self.in.reader();
    const header = try Header.parse(allocator, reader);

    const content = try allocator.alloc(u8, header.length);
    errdefer allocator.free(content);
    try reader.readNoEof(content);

    return content;
}

test encodeMessage {
    const stdin = std.io.getStdIn().reader().any();
    const stdout = std.io.getStdOut().writer().any();
    const t = Transport.init(stdin, stdout);

    const allocator = std.testing.allocator;

    const expected = "Content-Length: 16\r\n\r\n{\"testing\":true}";

    const actual = try t.encodeMessage(allocator, .{
        .testing = true
    });
    defer allocator.free(actual);

    try std.testing.expect(std.mem.eql(u8, expected, actual));
}

test readJsonMessage {
    const buf = "Content-Length: 27\r\n\r\n{\"method\":\"initialization\"}";
    var source = std.io.fixedBufferStream(buf);
    const expected = "{\"method\":\"initialization\"}";

    const stdin = source.reader().any();
    const stdout = std.io.getStdOut().writer().any();
    const allocator = std.testing.allocator;

    var t = Transport.init(stdin, stdout);

    const actual = try t.readJsonMessage(allocator);
    defer allocator.free(actual);

    try std.testing.expect(std.mem.eql(u8, expected, actual));
}
