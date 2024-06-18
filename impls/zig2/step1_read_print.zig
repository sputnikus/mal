const std = @import("std");

const Allocator = @import("std").heap.c_allocator;
const MalErr = @import("error.zig").MalErr;
const MalType = @import("types.zig").MalType;
const printer = @import("printer.zig");
const reader = @import("reader.zig");
const getline = @import("readline.zig").getline;

fn READ(input: []u8) MalErr!?*MalType {
    return try reader.read_str(input);
}

fn EVAL(input: ?*MalType) ?*MalType {
    return input;
}

fn PRINT(input: ?*MalType) ![]const u8 {
    const output = printer.pr_str(input) catch "Allocation error";
    return output;
}

fn rep(input: []u8) []const u8 {
    const read_output = READ(input) catch return "EOF";
    const eval_output = EVAL(read_output);
    const print_output = PRINT(eval_output);
    if (eval_output) |mal| {
        mal.destroy(Allocator);
    }
    return print_output catch "EOF";
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    while (true) {
        const line = (try getline(Allocator)) orelse break;
        defer Allocator.free(line);
        const output = rep(line);
        try stdout.print("{s}\n", .{output});
    }
}
