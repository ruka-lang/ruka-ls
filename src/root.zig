const std = @import("std");

pub const Transport = @import("transport/transport.zig");
pub const Server = @import("server/server.zig");
pub const Message = @import("server/message.zig");
pub const types = @import("types.zig");

var time: i64 = undefined;

pub fn setup_logs(allocator: std.mem.Allocator) !void {
    const home = std.os.getenv("HOME") orelse {
        std.debug.print("Failed to read $HOME.\n", .{});
        return;
    };
    var homedir = try std.fs.openDirAbsolute(home, .{});
    defer homedir.close();

    time = std.time.timestamp();

    const logspath = ".local/share/ruka-ls/logs";
    try homedir.makePath(logspath);

    var logs = try homedir.openDir(logspath, .{});
    defer logs.close();

    const filename = std.fmt.allocPrint(allocator, "{d}.log", .{time})
    catch |err| {
        std.debug.print("Failed to format log filename: {}\n", .{err});
        return;
    };
    defer allocator.free(filename);

    const file = logs.createFile(filename, .{}) catch |err| {
        std.debug.print("Failed to create log file: {}\n", .{err});
        return;
    };
    file.close();
}

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype
) void {
    const allocator = std.heap.page_allocator;
    const home = std.os.getenv("HOME") orelse {
        std.debug.print("Failed to read $HOME.\n", .{});
        return;
    };

    var homedir = std.fs.openDirAbsolute(home, .{}) catch |err| {
        std.debug.print("Failed to create log file path: {}\n", .{err});
        return;
    };
    defer homedir.close();

    const path = std.fmt.allocPrint(allocator, "{s}/{d}.log",
        .{".local/share/ruka-ls/logs", time})
    catch |err| {
        std.debug.print("Failed to create log file path: {}\n", .{err});
        return;
    };
    defer allocator.free(path);

    const file = homedir.openFile(path, .{ .mode = .read_write }) catch |err| {
        std.debug.print("Failed to open log file: {}\n", .{err});
        return;
    };
    defer file.close();

    const stat = file.stat() catch |err| {
        std.debug.print("Failed to get stat of log file: {}\n", .{err});
        return;
    };
    file.seekTo(stat.size) catch |err| {
        std.debug.print("Failed to seek log file: {}\n", .{err});
        return;
    };

    const prefix = "[" ++ comptime level.asText() ++ "] " ++ "(" ++ @tagName(scope) ++ ") ";

    var buffer: [4096]u8 = undefined;
    const message = std.fmt.bufPrint(buffer[0..], prefix ++ format ++ "\n", args) catch |err| {
        std.debug.print("Failed to format log message with args: {}\n", .{err});
        return;
    };
    file.writeAll(message) catch |err| {
        std.debug.print("Failed to write to log file: {}\n", .{err});
    };
}

test "ruka-ls" {
    std.testing.refAllDecls(@This());
}
