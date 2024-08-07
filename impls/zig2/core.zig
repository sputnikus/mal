const std = @import("std");
const math = std.math;
const mem = std.mem;
const Allocator = std.heap.c_allocator;

const MalErr = @import("error.zig").MalErr;
const MalFun = @import("types.zig").MalFun;
const MalLinkedList = @import("types.zig").MalLinkedList;
const MalType = @import("types.zig").MalType;
const MalTypeValue = @import("types.zig").MalTypeValue;
const apply = @import("types.zig").apply;
const printer = @import("printer.zig");
const read_str = @import("reader.zig").read_str;

pub fn add_int(args: []*MalType) MalErr!*MalType {
    const x = try args[0].to_int();
    const y = try args[1].to_int();
    const res = math.add(i64, x, y) catch return MalErr.Overflow;
    return MalType.new_int(Allocator, res);
}

pub fn sub_int(args: []*MalType) MalErr!*MalType {
    const x = try args[0].to_int();
    const y = try args[1].to_int();
    const res = math.sub(i64, x, y) catch return MalErr.Overflow;
    return MalType.new_int(Allocator, res);
}

pub fn mul_int(args: []*MalType) MalErr!*MalType {
    const x = try args[0].to_int();
    const y = try args[1].to_int();
    const res = math.mul(i64, x, y) catch return MalErr.Overflow;
    return MalType.new_int(Allocator, res);
}

// floored division
pub fn div_int(args: []*MalType) MalErr!*MalType {
    const x = try args[0].to_int();
    const y = try args[1].to_int();
    const res = math.divFloor(i64, x, y) catch return MalErr.Overflow;
    return MalType.new_int(Allocator, res);
}

fn list(args: []*MalType) MalErr!*MalType {
    var new_list = MalLinkedList.init(Allocator);
    errdefer new_list.deinit();
    for (args) |elem| {
        new_list.append(elem) catch return MalErr.OutOfMemory;
    }
    return MalType.new_list(Allocator, new_list);
}

fn isList(args: []*MalType) MalErr!*MalType {
    return MalType.new_bool(Allocator, args[0].data == MalTypeValue.List);
}

fn isEmpty(args: []*MalType) MalErr!*MalType {
    return switch (args[0].data) {
        .List, .Vector => |seq| MalType.new_bool(Allocator, seq.items.len == 0),
        else => MalType.new_bool(Allocator, false),
    };
}

fn count(args: []*MalType) MalErr!*MalType {
    const len: usize = switch (args[0].data) {
        .List, .Vector => |seq| seq.items.len,
        .String => |s| s.len,
        .Nil => 0,
        else => return MalErr.TypeError,
    };
    return MalType.new_int(Allocator, @intCast(len));
}

fn isEqual(args: []*MalType) MalErr!*MalType {
    // sequence comparison
    {
        const left = args[0].to_linked_list() catch null;
        const right = args[1].to_linked_list() catch null;
        if (left != null and right != null) {
            if (left.?.items.len != right.?.items.len) return MalType.new_bool(Allocator, false);
            for (left.?.items, right.?.items) |left_elem, right_elem| {
                var eq_args = [_]*MalType{ left_elem, right_elem };
                const value_eq = try isEqual(&eq_args);
                defer value_eq.destroy(Allocator);
                if (!value_eq.data.Bool) return MalType.new_bool(Allocator, false);
            }
            return MalType.new_bool(Allocator, true);
        }
    }

    if (std.meta.activeTag(args[0].data) != std.meta.activeTag(args[1].data)) {
        return MalType.new_bool(Allocator, false);
    }

    switch (args[0].data) {
        .Bool => |left| {
            return MalType.new_bool(Allocator, left == args[1].data.Bool);
        },
        .Generic => |left| {
            const right = args[1].data.Generic;
            return MalType.new_bool(Allocator, mem.eql(u8, left, right));
        },
        .HashMap => |left| {
            const right = args[1].data.HashMap;
            if (left.count() != right.count()) return MalType.new_bool(Allocator, false);
            var iterator = left.iterator();
            while (iterator.next()) |left_pair| {
                const right_pair = right.getEntry(left_pair.key_ptr.*) orelse return MalType.new_bool(Allocator, false);
                var eq_args = [_]*MalType{ left_pair.value_ptr.*, right_pair.value_ptr.* };
                const value_eq = try isEqual(&eq_args);
                defer value_eq.destroy(Allocator);
                if (!value_eq.data.Bool) return MalType.new_bool(Allocator, false);
            }
            return MalType.new_bool(Allocator, true);
        },
        .Int => |left| {
            return MalType.new_bool(Allocator, left == args[1].data.Int);
        },
        .Keyword => |left| {
            const right = args[1].data.Keyword;
            return MalType.new_bool(Allocator, mem.eql(u8, left, right));
        },
        .Nil => {
            return MalType.new_bool(Allocator, true);
        },
        .String => |left| {
            return MalType.new_bool(Allocator, mem.eql(u8, left, args[1].data.String));
        },
        else => return MalType.new_bool(Allocator, false),
    }
}

fn isLt(args: []*MalType) MalErr!*MalType {
    const x = try args[0].to_int();
    const y = try args[1].to_int();
    return MalType.new_bool(Allocator, x < y);
}

fn isLte(args: []*MalType) MalErr!*MalType {
    const x = try args[0].to_int();
    const y = try args[1].to_int();
    return MalType.new_bool(Allocator, x <= y);
}

fn isGt(args: []*MalType) MalErr!*MalType {
    const x = try args[0].to_int();
    const y = try args[1].to_int();
    return MalType.new_bool(Allocator, x > y);
}

fn isGte(args: []*MalType) MalErr!*MalType {
    const x = try args[0].to_int();
    const y = try args[1].to_int();
    return MalType.new_bool(Allocator, x >= y);
}

fn prStr(args: []*MalType) MalErr!*MalType {
    var result_string = std.ArrayList(u8).init(Allocator);
    var first_iteration = true;
    for (args) |arg| {
        if (!first_iteration) result_string.append(' ') catch return MalErr.OutOfMemory;
        result_string.appendSlice(try printer.pr_str(arg, true)) catch return MalErr.OutOfMemory;
        first_iteration = false;
    }
    const output = result_string.toOwnedSlice() catch return MalErr.OutOfMemory;
    return MalType.new_string(Allocator, output);
}

fn str(args: []*MalType) MalErr!*MalType {
    var result_string = std.ArrayList(u8).init(Allocator);
    for (args) |arg| {
        result_string.appendSlice(try printer.pr_str(arg, false)) catch return MalErr.OutOfMemory;
    }
    const output = result_string.toOwnedSlice() catch return MalErr.OutOfMemory;
    return MalType.new_string(Allocator, output);
}

fn prn(args: []*MalType) MalErr!*MalType {
    var result_string = std.ArrayList(u8).init(Allocator);
    var first_iteration = true;
    for (args) |arg| {
        if (!first_iteration) result_string.append(' ') catch return MalErr.OutOfMemory;
        result_string.appendSlice(try printer.pr_str(arg, true)) catch return MalErr.OutOfMemory;
        first_iteration = false;
    }
    const stdout = std.io.getStdOut().writer();
    const output = result_string.toOwnedSlice() catch return MalErr.OutOfMemory;
    defer Allocator.free(output);
    stdout.print("{s}\n", .{output}) catch return MalErr.IOError;
    return MalType.init(Allocator);
}

fn println(args: []*MalType) MalErr!*MalType {
    var result_string = std.ArrayList(u8).init(Allocator);
    var first_iteration = true;
    for (args) |arg| {
        if (!first_iteration) result_string.append(' ') catch return MalErr.OutOfMemory;
        result_string.appendSlice(try printer.pr_str(arg, false)) catch return MalErr.OutOfMemory;
        first_iteration = false;
    }
    const stdout = std.io.getStdOut().writer();
    const output = result_string.toOwnedSlice() catch return MalErr.OutOfMemory;
    defer Allocator.free(output);
    stdout.print("{s}\n", .{output}) catch return MalErr.IOError;
    return MalType.init(Allocator);
}

fn readString(args: []*MalType) MalErr!*MalType {
    const string_input = try args[0].to_string();
    return (try read_str(string_input)) orelse return MalType.init(Allocator);
}

fn slurp(args: []*MalType) MalErr!*MalType {
    switch (args[0].data) {
        .String => |path| {
            var file = std.fs.cwd().openFile(path, .{}) catch return MalErr.IOError;
            defer file.close();

            const stat = file.stat() catch return MalErr.IOError;
            const buffer = file.readToEndAlloc(Allocator, stat.size) catch return MalErr.IOError;
            defer Allocator.free(buffer);

            return MalType.new_string(Allocator, buffer);
        },
        else => return MalErr.TypeError,
    }
}

fn atom(args: []*MalType) MalErr!*MalType {
    return MalType.new_atom(Allocator, args[0]);
}

fn isAtom(args: []*MalType) MalErr!*MalType {
    return MalType.new_bool(Allocator, args[0].data == MalTypeValue.Atom);
}

fn deref(args: []*MalType) MalErr!*MalType {
    return switch (args[0].data) {
        .Atom => |atom_val| atom_val.*.copy(Allocator),
        else => MalErr.TypeError,
    };
}

fn atomReset(args: []*MalType) MalErr!*MalType {
    switch (args[0].data) {
        .Atom => |*old_value| {
            var new_value = try args[1].copy(Allocator);
            old_value.*.*.destroy(Allocator);
            old_value.*.* = new_value;
            return new_value.copy(Allocator);
        },
        else => return MalErr.TypeError,
    }
}

fn atomSwap(args: []*MalType) MalErr!*MalType {
    const args_len = args.len;
    if (args_len < 2) return MalErr.InvalidArgs;
    var new_args = MalLinkedList.init(Allocator);
    defer {
        const ll_slice = new_args.items;
        // first element gets freed by apply()
        // think about fixing this to make freeing more consistent
        for (ll_slice[1..]) |item| {
            item.destroy(Allocator);
        }
        new_args.deinit();
    }
    // args 1 is swap function
    try new_args.append(try args[1].copy(Allocator));
    // deref operates on args 0
    try new_args.append(try deref(args));
    var i: usize = 2;
    while (i < args_len) {
        try new_args.append(try args[i].copy(Allocator));
        i += 1;
    }
    const result = try apply(&new_args);
    var reset_args = [_]*MalType{ args[0], result };
    const new_atom_value = atomReset(&reset_args);
    return new_atom_value;
}

fn cons(args: []*MalType) MalErr!*MalType {
    const args_len = args.len;
    if (args_len < 2) return MalErr.InvalidArgs;
    switch (args[1].data) {
        .List, .Vector => |*linked_list| {
            var acc = MalLinkedList.init(Allocator);
            acc.append(try args[0].copy(Allocator)) catch return MalErr.OutOfMemory;
            const slice = linked_list.toOwnedSlice() catch return MalErr.OutOfMemory;
            acc.appendSlice(slice) catch return MalErr.OutOfMemory;
            return MalType.new_list(Allocator, acc);
        },
        else => return MalErr.TypeError,
    }
}

fn concat(args: []*MalType) MalErr!*MalType {
    var acc = MalLinkedList.init(Allocator);
    for (args) |arg| {
        switch (arg.data) {
            .List, .Vector => |*linked_list| {
                const slice = linked_list.toOwnedSlice() catch return MalErr.OutOfMemory;
                acc.appendSlice(slice) catch return MalErr.OutOfMemory;
            },
            else => return MalErr.TypeError,
        }
    }
    return MalType.new_list(Allocator, acc);
}

fn vec(args: []*MalType) MalErr!*MalType {
    const args_len = args.len;
    if (args_len < 1) return MalErr.InvalidArgs;
    switch (args[0].data) {
        .List => |linked_list| {
            return MalType.new_vector(Allocator, linked_list);
        },
        .Vector => {
            return args[0];
        },
        else => return MalErr.TypeError,
    }
}

fn nth(args: []*MalType) MalErr!*MalType {
    const args_len = args.len;
    if (args_len < 2) return MalErr.InvalidArgs;
    switch (args[0].data) {
        .List, .Vector => {
            const index = switch (args[1].data) {
                .Int => |i| i,
                else => return MalErr.TypeError,
            };
            return args[0].seq_pop(@intCast(index));
        },
        else => return MalErr.TypeError,
    }
}

fn first(args: []*MalType) MalErr!*MalType {
    const args_len = args.len;
    if (args_len < 1) return MalErr.InvalidArgs;
    switch (args[0].data) {
        .List, .Vector => {
            return args[0].seq_pop(0) catch |err| switch (err) {
                MalErr.OutOfBounds => MalType.init(Allocator),
                else => err,
            };
        },
        .Nil => return MalType.init(Allocator),
        else => return MalErr.TypeError,
    }
}

fn rest(args: []*MalType) MalErr!*MalType {
    const args_len = args.len;
    if (args_len < 1) return MalErr.InvalidArgs;
    switch (args[0].data) {
        .List, .Vector => {
            return args[0].rest() catch |err| switch (err) {
                MalErr.OutOfBounds => MalType.new_list(Allocator, MalLinkedList.init(Allocator)),
                else => err,
            };
        },
        .Nil => return MalType.new_list(Allocator, MalLinkedList.init(Allocator)),
        else => return MalErr.TypeError,
    }
}

pub const NamespaceMapping = struct {
    name: []const u8,
    func: MalFun,
};

pub const ns = [_]NamespaceMapping{
    NamespaceMapping{ .name = "+", .func = &add_int },
    NamespaceMapping{ .name = "-", .func = &sub_int },
    NamespaceMapping{ .name = "*", .func = &mul_int },
    NamespaceMapping{ .name = "/", .func = &div_int },

    // step 4 core functions
    NamespaceMapping{ .name = "list", .func = &list },
    NamespaceMapping{ .name = "list?", .func = &isList },
    NamespaceMapping{ .name = "empty?", .func = &isEmpty },
    NamespaceMapping{ .name = "count", .func = &count },
    NamespaceMapping{ .name = "=", .func = &isEqual },
    NamespaceMapping{ .name = "<", .func = &isLt },
    NamespaceMapping{ .name = "<=", .func = &isLte },
    NamespaceMapping{ .name = ">", .func = &isGt },
    NamespaceMapping{ .name = ">=", .func = &isGte },

    // step 4 deferrable functions
    NamespaceMapping{ .name = "pr-str", .func = &prStr },
    NamespaceMapping{ .name = "str", .func = &str },
    NamespaceMapping{ .name = "prn", .func = &prn },
    NamespaceMapping{ .name = "println", .func = &println },

    // step 6 core functions
    NamespaceMapping{ .name = "read-string", .func = &readString },
    NamespaceMapping{ .name = "slurp", .func = &slurp },
    NamespaceMapping{ .name = "atom", .func = &atom },
    NamespaceMapping{ .name = "atom?", .func = &isAtom },
    NamespaceMapping{ .name = "deref", .func = &deref },
    NamespaceMapping{ .name = "reset!", .func = &atomReset },
    NamespaceMapping{ .name = "swap!", .func = &atomSwap },

    // step 7 core functions
    NamespaceMapping{ .name = "cons", .func = &cons },
    NamespaceMapping{ .name = "concat", .func = &concat },
    NamespaceMapping{ .name = "vec", .func = &vec },

    // step 8 deferrable functions
    NamespaceMapping{ .name = "nth", .func = &nth },
    NamespaceMapping{ .name = "first", .func = &first },
    NamespaceMapping{ .name = "rest", .func = &rest },
};
