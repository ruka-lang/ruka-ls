const rukals = @import("../root.zig");
const types = rukals.types;

const std = @import("std");

const log = std.log.scoped(.message);

const Message = @This();

tag: enum(u32) {
    request,
    notification,
    response
},
request: ?Request = null,
notification: ?Notification = null,
response: ?Response = null,

pub const Request = struct {
    id: types.RequestId,
    params: Params,

    pub const Params = union(enum) {
        initialize: types.InitializeParams,
        shutdown,
        unknown: []const u8
    };
};

pub const Notification = union(enum) {
    initialized: types.InitializedParams,
    exit,
    unknown: []const u8
};

pub const Response = struct {
    id: types.RequestId,
    data: Data,

    pub const Data = union(enum) {
        result: types.LspAny,
        @"error": types.ResponseError
    };
};

pub fn isBlocking(self: Message) bool {
    switch (self.tag) {
        .request => switch (self.request.?.params) {
            .initialize, .shutdown => return true,
            .unknown => return false
        },
        .notification => switch (self.notification.?) {
            .initialized, .exit => return true,
            .unknown => return false
        },
        .response => return true
    }
}

pub fn jsonParse(
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions
) std.json.ParseError(@TypeOf(source.*))!Message {
    const json_value = try std.json.parseFromTokenSourceLeaky(std.json.Value, allocator, source, options);
    return try jsonParseFromValue(allocator, json_value, options);
}

pub fn jsonParseFromValue(
    allocator: std.mem.Allocator,
    source: std.json.Value,
    options: std.json.ParseOptions
) !Message {
    if (source != .object) return error.UnexpectedToken;
    const object = source.object;

    @setEvalBranchQuota(10_000);
    if (object.get("id")) |id_obj| {
        const msg_id = try std.json.parseFromValueLeaky(types.RequestId, allocator, id_obj, options);

        if (object.get("method")) |method_obj| {
            const msg_method = try std.json.parseFromValueLeaky([]const u8, allocator, method_obj, options);
            const msg_params = object.get("params") orelse .null;
            const fields = @typeInfo(Request.Params).Union.fields;

            inline for (fields) |field| {
                if (std.mem.eql(u8, msg_method, field.name)) {
                    const params = blk: {
                        if (field.type == void) {
                            break :blk void{};
                        } else {
                            break :blk try std.json.parseFromValueLeaky(
                                       field.type, allocator, msg_params, options);
                        }
                    };

                    return .{
                        .tag = .request,
                        .request = .{
                            .id = msg_id,
                            .params = @unionInit(Request.Params, field.name, params)
                        }
                    };
                }
            }

            return .{
                .tag = .request,
                .request = .{
                    .id = msg_id,
                    .params = .{.unknown = msg_method}
                }
            };
        } else {
            const result = object.get("result") orelse .null;
            const error_obj = object.get("error") orelse .null;
            const err = try std.json.parseFromValueLeaky(?types.ResponseError, allocator, error_obj, options);

            if (result != .null and err != null) return error.UnexpectedToken;

            if (err) |e| {
                return .{
                    .tag = .response,
                    .response = .{
                        .id = msg_id,
                        .data = .{.@"error" = e}
                    }
                };
            } else {
                return .{
                    .tag = .response,
                    .response = .{
                        .id = msg_id,
                        .data = .{.result = result}
                    }
                };
            }
        }
    } else {
        const method_obj = object.get("method") orelse return error.UnexpectedToken;
        const msg_method = try std.json.parseFromValueLeaky([]const u8, allocator, method_obj, options);
        const msg_params = object.get("params") orelse .null;
        const fields = @typeInfo(Notification).Union.fields;

        inline for (fields) |field| {
            if (std.mem.eql(u8, msg_method, field.name)) {
                const params = blk: {
                    if (field.type == void) {
                        break :blk void{};
                    } else {
                        break :blk try std.json.parseFromValueLeaky(
                                   field.type, allocator, msg_params, options);
                    }
                };

                return .{
                    .tag = .notification,
                    .notification = @unionInit(Notification, field.name, params)
                };
            }
        }

        return .{
            .tag = .notification,
            .notification = .{.unknown = msg_method}
        };
    }
}
