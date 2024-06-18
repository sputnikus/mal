const std = @import("std");
const fmt = @import("std").fmt;
const mem = @import("std").mem;

const Allocator = @import("std").heap.c_allocator;
const ArrayList = @import("std").ArrayList;
const MalErr = @import("error.zig").MalErr;
const MalType = @import("types.zig").MalType;

pub fn pr_str(mal_tree: ?*MalType) MalErr![]const u8 {
    var result_string = ArrayList(u8).init(Allocator);
    defer result_string.deinit();

    switch (mal_tree.?.data) {
        .Int => |value| {
            try fmt.format(result_string.writer(), "{0}", .{value});
        },
        .List => |list| {
            try result_string.append('(');
            var first_iteration = true;
            var i: usize = 0;
            const list_len = list.items.len;
            while (i < list_len) {
                if (!first_iteration) {
                    try result_string.append(' ');
                }
                const item = pr_str(list.items[i]) catch "";
                result_string.appendSlice(item) catch return MalErr.OutOfMemory;
                first_iteration = false;
                i += 1;
            }
            try result_string.append(')');
        },
        .Nil => {
            try result_string.appendSlice("nil");
        },
        .Symbol => |value| {
            try fmt.format(result_string.writer(), "{s}", .{value});
        },
    }

    const output = result_string.toOwnedSlice();
    return output;
}
