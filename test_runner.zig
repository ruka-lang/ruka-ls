const std = @import("std");
const builtin = @import("builtin");

const BORDER = "=" ** 80;

const Status = enum {
    pass,
    fail,
    skip,
    text,
};

fn getenvOwned(alloc: std.mem.Allocator, key: []const u8) ?[]u8 {
    const v = std.process.getEnvVarOwned(alloc, key) catch |err| {
        if (err == error.EnvironmentVariableNotFound) {
            return null;
        }
        std.log.warn("failed to get env var {s} due to err {}", .{ key, err });
        return null;
    };
    return v;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 12 }){};
    const alloc = gpa.allocator();
    const fail_first = blk: {
        if (getenvOwned(alloc, "TEST_FAIL_FIRST")) |e| {
            defer alloc.free(e);
            break :blk std.mem.eql(u8, e, "true");
        }
        break :blk false;
    };
    const filter = getenvOwned(alloc, "TEST_FILTER");
    defer if (filter) |f| alloc.free(f);

    // Print out test suite name
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    _ = args.skip();
    const name = args.next().?;

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const out = bw.writer();

    fmt(out.any(), "\r\x1b[0K", .{}); // beginning of line and clear to end of line
    wstatus(out.any(), .skip, "Running test suite: {s}\n", .{name[8..]});

    var pass: usize = 0;
    var fail: usize = 0;
    var skip: usize = 0;
    var leak: usize = 0;

    for (builtin.test_functions) |t| {
        std.testing.allocator_instance = .{};
        var status = Status.pass;

        if (filter) |f| {
            if (std.mem.indexOf(u8, t.name, f) == null) {
                continue;
            }
        }

        const test_name = t.name[0..];
        fmt(out.any(), "Testing {s}: ", .{test_name});
        const result = t.func();

        if (std.testing.allocator_instance.deinit() == .leak) {
            leak += 1;
            wstatus(out.any(), .fail, "\n{s}\n\"{s}\" - Memory Leak\n{s}\n", .{ BORDER, test_name, BORDER });
        }

        if (result) |_| {
            pass += 1;
        } else |err| {
            switch (err) {
                error.SkipZigTest => {
                    skip += 1;
                    status = .skip;
                },
                else => {
                    status = .fail;
                    fail += 1;
                    wstatus(out.any(), .fail, "\n{s}\n\"{s}\" - {s}\n{s}\n", .{ BORDER, test_name, @errorName(err), BORDER });
                    if (@errorReturnTrace()) |trace| {
                        std.debug.dumpStackTrace(trace.*);
                    }
                    if (fail_first) {
                        break;
                    }
                },
            }
        }

        wstatus(out.any(), status, "[{s}]\n", .{@tagName(status)});
    }

    const total_tests = pass + fail;
    const status: Status = if (fail == 0) .pass else .fail;
    wstatus(out.any(), status, "{d} of {d} test{s} passed\n", .{ pass, total_tests, if (total_tests != 1) "s" else "" });
    if (skip > 0) {
        wstatus(out.any(), .skip, "{d} test{s} skipped\n", .{ skip, if (skip != 1) "s" else "" });
    }
    if (leak > 0) {
        wstatus(out.any(), .fail, "{d} test{s} leaked\n", .{ leak, if (leak != 1) "s" else "" });
    }

    try bw.flush();

    std.os.exit(if (fail == 0) 0 else 1);
}

fn fmt(self: std.io.AnyWriter, comptime format: []const u8, args: anytype) void {
    self.print(format, args) catch unreachable;
}

fn wstatus(self: std.io.AnyWriter, s: Status, comptime format: []const u8, args: anytype) void {
    const color = switch (s) {
        .pass => "\x1b[32m",
        .fail => "\x1b[31m",
        .skip => "\x1b[33m",
        else => "",
    };
    self.writeAll(color) catch @panic("writeAll failed?!");
    self.print(format, args) catch @panic("std.fmt.format failed?!");
    fmt(self, "\x1b[0m", .{});
}
