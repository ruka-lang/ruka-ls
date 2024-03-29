const ruka_ls = @import("../root.zig");
const Transport = ruka_ls.Transport;

const std = @import("std");

allocator: std.mem.Allocator,
transport: *Transport,
status: Status = .uninitialized,

thread_pool: std.Thread.Pool,
wait_group: std.Thread.WaitGroup,

job_queue: std.fifo.LinearFifo(Job, .Dynamic),
job_queue_lock: std.Thread.Mutex = .{},

const Server = @This();

const log = std.log.scoped(.server);

pub const Message = struct {
    method: enum {
        initialize,
        shutdown,
        unknown
    },

    pub fn deinit(_: Message, _: std.mem.Allocator) void {
        //allocator.free(self.method);
    }

    pub fn isBlocking(self: Message) bool {
        switch (self.method) {
            .initialize, .shutdown => return true,
            else => return false
        }
    }

    // can add custom json parsing by adding jsonParse and jsonParseFromValue methods
    // jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!Message
    // jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !Message
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

const Job = union(enum) {
    incoming_message: std.json.Parsed(Message),

    fn deinit(self: Job) void {
        switch (self) {
            .incoming_message => |parsed_message| parsed_message.deinit(),
        }
    }

    const SynchronizationMode = enum {
        exclusive,
        shared,
        atomic
    };

    fn syncMode(self: Job) SynchronizationMode {
        return switch (self) {
            .incoming_message => |message| if (message.value.isBlocking()) .exclusive else .shared,
        };
    }
};

pub fn init(allocator: std.mem.Allocator, transport: *Transport) !*Server {
    const server = try allocator.create(Server);
    errdefer server.deinit();

    server.* =  Server{
        .allocator = allocator,
        .transport = transport,
        .thread_pool = undefined,
        .wait_group = .{},
        .job_queue = std.fifo.LinearFifo(Job, .Dynamic).init(allocator)
    };

    try server.thread_pool.init(.{
        .allocator = allocator,
        .n_jobs = 4
    });

    return server;
}

pub fn deinit(self: *Server) void {
    self.wait_group.wait();
    self.thread_pool.deinit();
    while (self.job_queue.readItem()) |job| job.deinit();
    self.job_queue.deinit();
    self.allocator.destroy(self);
}

pub fn keepRunning(self: *Server) bool {
    switch (self.status) {
        .exiting_success, .exiting_failure => return false,
        else => return true
    }
}

pub fn waitAndWork(self: *Server) void {
    self.thread_pool.waitAndWork(&self.wait_group);
    self.wait_group.reset();
}

fn shutdown(self: *Server) void {
    self.status = .exiting_success;
    log.info("shutdown successfully", .{});
}

pub fn loop(self: *Server) !void {
    while (self.keepRunning()) { 
        const json_message = try self.transport.readJsonMessage(self.allocator);
        defer self.allocator.free(json_message);
        try self.sendJsonMessage(json_message);

        while (self.job_queue.readItem()) |job| {
            switch (job.syncMode()) {
                .exclusive => {
                    self.waitAndWork();
                    self.processJob(job, null);
                },
                .shared => {
                    self.wait_group.start();
                    errdefer job.deinit();
                    try self.thread_pool.spawn(processJob, .{self, job, &self.wait_group});
                },
                .atomic => {
                    errdefer job.deinit();
                    try self.thread_pool.spawn(processJob, .{self, job, null});
                }
            }
        }
    }
}

fn sendJsonMessage(self: *Server, json_message: []u8) !void {
    try self.job_queue.ensureUnusedCapacity(1);

    const parsed = std.json.parseFromSlice(Message, self.allocator, json_message, 
        .{.ignore_unknown_fields = true, .max_value_len = null}) 
    catch |err| {
        log.err("json parse error: {any}", .{err});
        return err;
    };

    self.job_queue.writeItemAssumeCapacity(.{ .incoming_message = parsed });
}

fn processJob(self: *Server, job: Job, wait_group: ?*std.Thread.WaitGroup) void {
    defer if (wait_group != null) wait_group.?.finish();

    defer job.deinit();

    switch (job) {
        .incoming_message => |parsed_message| {
            switch (parsed_message.value.method) {
                .initialize => {
                    self.status = .initializing;
                    return log.info("initialize", .{});
                },
                .shutdown => {
                    self.status = .shutdown;
                    log.info("shutting down", .{});
                    return self.shutdown();
                },
                .unknown => { 
                    return log.err("Unknown request", .{});
                }
            }
        }
    }
}

//test "decode method" {
//    const buf = "Content-Length: 27\r\n\r\n{\"method\":\"initialization\"}";
//    var source = std.io.fixedBufferStream(buf);
//
//    const expected = Message{
//        .method = "initialization"
//    };
//
//    const stdin = source.reader().any();
//    const stdout = std.io.getStdOut().writer().any();
//    const allocator = std.testing.allocator;
//
//    var t = Transport.init(stdin, stdout);
//    var server = try Server.init(allocator, &t);
//    defer server.deinit();
//
//    const actual = try server.decodeMessage();
//    defer actual.deinit(allocator);
//
//    try std.testing.expect(std.mem.eql(u8, expected.method, actual.method));
//}
