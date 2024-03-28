const ruka_ls = @import("root.zig");
const Transport = ruka_ls.Transport;
const Server = ruka_ls.Server;

const std = @import("std");

pub const std_options = .{
    .log_level = switch (@import("builtin").mode) {
        .Debug => .debug,
        else => .info
    },
    .logFn = ruka_ls.log
};

pub fn main() !void {
    const stdin = std.io.getStdIn().reader().any();
    const stdout = std.io.getStdOut().writer().any();

    const allocator = std.heap.page_allocator;

    try ruka_ls.setup_logs(allocator);

    std.log.scoped(.exe).info("I'm alive", .{});

    var transport = Transport.init(stdin, stdout);
    var server = try Server.init(allocator, &transport);
    defer server.deinit();

    try server.loop();
}

