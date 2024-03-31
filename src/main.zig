const rukals = @import("root.zig");
const Transport = rukals.Transport;
const Server = rukals.Server;

const std = @import("std");

const log = std.log.scoped(.exe);

pub const std_options = .{
    .log_level = switch (@import("builtin").mode) {
        .Debug => .debug,
        else => .info
    },
    .logFn = rukals.log
};

pub fn main() !void {
    const stdin = std.io.getStdIn().reader().any();
    const stdout = std.io.getStdOut().writer().any();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer log.info("{any}", .{gpa.deinit()});

    const allocator = gpa.allocator();

    try rukals.setup_logs(allocator);

    log.info("I'm alive", .{});

    var transport = Transport.init(stdin, stdout);
    var server = try Server.init(allocator, &transport);
    defer server.deinit();

    try server.loop();
    log.info("shutdown", .{});
}
