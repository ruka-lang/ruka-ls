const ruka_ls = @import("../root.zig");
const Transport = ruka_ls.Transport;

const std = @import("std");

allocator: std.mem.Allocator,
transport: *Transport,
status: Status = .uninitialized,
pool: std.Thread.Pool,
wait_group: std.Thread.WaitGroup,

const Server = @This();

const log = std.log.scoped(.server);

pub const Message = struct {
    method: []const u8,

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.method);
    }
};

const Status = enum {
    /// The server has not received a `initialize` request
    uninitialized,
    /// The server has received a `initialize` request
    initializing,
    /// The server has been initialized and is ready to receive requests
    initialized,
    /// The server has been shutdown and can't handle any more requests
    shutdown,
    /// The server has received a `exit` notification and has been shutdown
    exiting_success,
    /// The server has received a `exit` notification but has not been shutdown
    exiting_failure
};

pub fn init(allocator: std.mem.Allocator, transport: *Transport) !*Server {
    const server = try allocator.create(Server);
    server.* =  Server{
        .allocator = allocator,
        .transport = transport,
        .pool = undefined,
        .wait_group = .{}
    };

    try server.pool.init(.{
        .allocator = allocator,
        .n_jobs = 4
    });

    return server;
}

pub fn deinit(self: *Server) void {
    self.wait_group.wait();
    self.pool.deinit();
    self.allocator.destroy(self);
}

pub fn keepRunning(self: *Server) bool {
    switch (self.status) {
        .exiting_success, .exiting_failure => return false,
        else => return true
    }
}

pub fn loop(self: *Server) !void {
    while (self.keepRunning()) { 
        const message = try self.decodeMessage();
        defer message.deinit(self.allocator);
        
        log.info("{s}", .{message.method});
    }
}

fn decodeMessage(self: *Server) !Message {
    var message: Message = undefined;

    const json_message = try self.transport.readJsonMessage(self.allocator);
    defer self.allocator.free(json_message);

    const parsed = try std.json.parseFromSlice(Message, self.allocator, json_message, 
        .{.ignore_unknown_fields = true, .max_value_len = null});
    defer parsed.deinit();

    message.method = try self.allocator.dupe(u8, parsed.value.method);

    return message;
}

test "decode method" {
    const buf = "Content-Length: 27\r\n\r\n{\"method\":\"initialization\"}";
    var source = std.io.fixedBufferStream(buf);

    const expected = Message{
        .method = "initialization"
    };

    const stdin = source.reader().any();
    const stdout = std.io.getStdOut().writer().any();
    const allocator = std.testing.allocator;

    var t = Transport.init(stdin, stdout);
    var server = try Server.init(allocator, &t);
    defer server.deinit();

    const actual = try server.decodeMessage();
    defer actual.deinit(allocator);

    try std.testing.expect(std.mem.eql(u8, expected.method, actual.method));
}
