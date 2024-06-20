const std = @import("std");
const fmt = @import("std").fmt;
const mem = @import("std").mem;

const Allocator = @import("std").heap.c_allocator;
const ArrayList = @import("std").ArrayList;
const MalErr = @import("error.zig").MalErr;
const MalType = @import("types.zig").MalType;

pub fn pr_str(mal_tree: ?*MalType, print_readably: bool) MalErr![]const u8 {
    var result_string = ArrayList(u8).init(Allocator);
    defer result_string.deinit();

    switch (mal_tree.?.data) {
        .Bool => |value| {
            try fmt.format(result_string.writer(), "{}", .{value});
        },
        .Generic => |value| {
            try fmt.format(result_string.writer(), "{s}", .{value});
        },
        .HashMap => |hashmap| {
            try result_string.append('{');
            var first_iteration = true;
            var iterator = hashmap.iterator();
            while (iterator.next()) |entry| {
                if (!first_iteration) {
                    try result_string.append(' ');
                }
                const key = entry.key_ptr;
                // disctint between keyword and string keys
                if (key.len > 1 and key.*[0] == 255) {
                    try result_string.append(':');
                    try fmt.format(result_string.writer(), "{s}", .{key.*[1..]});
                } else {
                    const formated = try format_string(key.*, print_readably);
                    try result_string.appendSlice(formated);
                }
                try result_string.append(' ');
                const item = pr_str(entry.value_ptr.*, print_readably) catch "";
                result_string.appendSlice(item) catch return MalErr.OutOfMemory;
                first_iteration = false;
            }
            try result_string.append('}');
        },
        .Int => |value| {
            try fmt.format(result_string.writer(), "{0}", .{value});
        },
        .Keyword => |value| {
            try result_string.append(':');
            try fmt.format(result_string.writer(), "{s}", .{value[1..value.len]});
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
                const item = pr_str(list.items[i], print_readably) catch "";
                result_string.appendSlice(item) catch return MalErr.OutOfMemory;
                first_iteration = false;
                i += 1;
            }
            try result_string.append(')');
        },
        .Nil => {
            try result_string.appendSlice("nil");
        },
        .String => |value| {
            const formated = try format_string(value, print_readably);
            try result_string.appendSlice(formated);
        },
        .Vector => |vector| {
            try result_string.append('[');
            var first_iteration = true;
            var i: usize = 0;
            const vector_len = vector.items.len;
            while (i < vector_len) {
                if (!first_iteration) {
                    try result_string.append(' ');
                }
                const item = pr_str(vector.items[i], print_readably) catch "";
                result_string.appendSlice(item) catch return MalErr.OutOfMemory;
                first_iteration = false;
                i += 1;
            }
            try result_string.append(']');
        },
    }

    const output = result_string.toOwnedSlice() catch return MalErr.OutOfMemory;
    return output;
}

fn format_string(value: []const u8, print_readably: bool) MalErr![]const u8 {
    var result_string = ArrayList(u8).init(Allocator);
    defer result_string.deinit();

    if (print_readably) {
        try result_string.appendSlice("\"");
    }

    for (value) |head| {
        if (print_readably and (head == '"' or head == 92)) {
            try result_string.appendSlice("\\");
        }
        if (print_readably and head == '\n') {
            try result_string.appendSlice("\\n");
        } else {
            try result_string.append(head);
        }
    }

    if (print_readably) {
        try result_string.appendSlice("\"");
    }

    const output = result_string.toOwnedSlice() catch return MalErr.OutOfMemory;
    return output;
}
