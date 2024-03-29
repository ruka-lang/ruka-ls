const std = @import("std");

pub const LspAny = std.json.Value;

pub const RequestId = union(enum) {
    integer: i64,
    string: []const u8,
    pub usingnamespace UnionParser(@This());
    
    pub fn format(id: RequestId, comptime fmt_str: []const u8, options: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        _ = options;
        if (fmt_str.len != 0) std.fmt.invalidFmtError(fmt_str, id);
        switch (id) {
            .integer => |number| try writer.print("{d}", .{number}),
            .string => |str| try writer.writeAll(str)
        }
    }
};

pub const ResponseError = struct {
    code: i64,
    message: []const u8,
    data: std.json.Value = .null
};

pub const InitializeParams = struct {};
pub const InitializeResult = struct {
    capabilities: ServerCapabilities,
    serverInfo: ?ServerInfo = null
};

pub const ServerCapabilities = struct {

};

pub const ServerInfo = struct {
    name: []const u8,
    version: ?[]const u8 = null
};

pub const InitializedParams = struct {};

pub fn UnionParser(comptime T: type) type {
    return struct {
        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!T {
            const json_value = try std.json.Value.jsonParse(allocator, source, options);
            return try jsonParseFromValue(allocator, json_value, options);
        }

        pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) std.json.ParseFromValueError!T {
            inline for (std.meta.fields(T)) |field| {
                if (std.json.parseFromValueLeaky(field.type, allocator, source, options)) |result| {
                    return @unionInit(T, field.name, result);
                } else |_| {}
            }
            return error.UnexpectedToken;
        }

        pub fn jsonStringify(self: T, stream: anytype) @TypeOf(stream.*).Error!void {
            switch (self) {
                inline else => |value| try stream.write(value),
            }
        }
    };
}
