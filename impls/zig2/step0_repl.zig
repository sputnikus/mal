const std = @import("std");
const getline = @import("readline.zig").getline;

const Allocator = @import("std").heap.c_allocator;

fn READ(input: []u8) []u8 {
    return input;
}

fn EVAL(input: []u8) []u8 {
    return input;
}

fn PRINT(input: []u8) []u8 {
    return input;
}

fn rep(input: []u8) []u8 {
    const read_output = READ(input);
    const eval_output = EVAL(read_output);
    const print_output = PRINT(eval_output);
    return print_output;
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    while (true) {
        const line = (try getline(Allocator)) orelse break;
        const output = rep(line);
        defer Allocator.free(output);
        try stdout.print("{s}", .{output});
        try stdout.print("\n", .{});
    }
}
