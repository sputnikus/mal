const std = @import("std");
const math = std.math;
const mem = std.mem;
const Allocator = std.heap.c_allocator;
const milliTimestamp = std.time.milliTimestamp;

const MalErr = @import("error.zig").MalErr;
const MalFun = @import("types.zig").MalFun;
const MalHashMap = @import("types.zig").MalHashMap;
const MalLinkedList = @import("types.zig").MalLinkedList;
const MalType = @import("types.zig").MalType;
const MalTypeValue = @import("types.zig").MalTypeValue;
const apply = @import("types.zig").apply;
const printer = @import("printer.zig");
const read_str = @import("reader.zig").read_str;
const getprompt = @import("readline.zig").getprompt;

pub fn addInt(args: []*MalType) MalErr!*MalType {
    if (args.len < 2) return MalErr.InvalidArgs;
    const x = try args[0].to_int();
    const y = try args[1].to_int();
    const res = math.add(i64, x, y) catch return MalErr.Overflow;
    return MalType.new_int(Allocator, res);
}

pub fn subInt(args: []*MalType) MalErr!*MalType {
    if (args.len < 2) return MalErr.InvalidArgs;
    const x = try args[0].to_int();
    const y = try args[1].to_int();
    const res = math.sub(i64, x, y) catch return MalErr.Overflow;
    return MalType.new_int(Allocator, res);
}

pub fn mulInt(args: []*MalType) MalErr!*MalType {
    if (args.len < 2) return MalErr.InvalidArgs;
    const x = try args[0].to_int();
    const y = try args[1].to_int();
    const res = math.mul(i64, x, y) catch return MalErr.Overflow;
    return MalType.new_int(Allocator, res);
}

// floored division
pub fn divInt(args: []*MalType) MalErr!*MalType {
    if (args.len < 2) return MalErr.InvalidArgs;
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
    if (args.len < 1) return MalErr.InvalidArgs;
    return MalType.new_bool(Allocator, args[0].data == MalTypeValue.List);
}

fn isEmpty(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    return switch (args[0].data) {
        .List, .Vector => |seq| MalType.new_bool(Allocator, seq.items.len == 0),
        else => MalType.new_bool(Allocator, false),
    };
}

fn count(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    const len: usize = switch (args[0].data) {
        .List, .Vector => |seq| seq.items.len,
        .String => |s| s.len,
        .Nil => 0,
        else => return MalErr.TypeError,
    };
    return MalType.new_int(Allocator, @intCast(len));
}

fn isEqual(args: []*MalType) MalErr!*MalType {
    if (args.len < 2) return MalErr.InvalidArgs;
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
    if (args.len < 2) return MalErr.InvalidArgs;
    const x = try args[0].to_int();
    const y = try args[1].to_int();
    return MalType.new_bool(Allocator, x < y);
}

fn isLte(args: []*MalType) MalErr!*MalType {
    if (args.len < 2) return MalErr.InvalidArgs;
    const x = try args[0].to_int();
    const y = try args[1].to_int();
    return MalType.new_bool(Allocator, x <= y);
}

fn isGt(args: []*MalType) MalErr!*MalType {
    if (args.len < 2) return MalErr.InvalidArgs;
    const x = try args[0].to_int();
    const y = try args[1].to_int();
    return MalType.new_bool(Allocator, x > y);
}

fn isGte(args: []*MalType) MalErr!*MalType {
    if (args.len < 2) return MalErr.InvalidArgs;
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
    if (args.len < 1) return MalErr.InvalidArgs;
    const string_input = try args[0].to_string();
    return (try read_str(string_input)) orelse return MalType.init(Allocator);
}

fn slurp(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
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
    if (args.len < 1) return MalErr.InvalidArgs;
    return MalType.new_atom(Allocator, args[0]);
}

fn isAtom(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    return MalType.new_bool(Allocator, args[0].data == MalTypeValue.Atom);
}

fn deref(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    return switch (args[0].data) {
        .Atom => |atom_val| atom_val.*.copy(Allocator),
        else => MalErr.TypeError,
    };
}

fn atomReset(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
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
    if (args.len < 2) return MalErr.InvalidArgs;
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
    if (args.len < 1) return MalErr.InvalidArgs;
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
    if (args.len < 2) return MalErr.InvalidArgs;
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
    if (args.len < 1) return MalErr.InvalidArgs;
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
    if (args.len < 1) return MalErr.InvalidArgs;
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

fn coreApply(args: []*MalType) MalErr!*MalType {
    if (args.len < 2) return MalErr.InvalidArgs;
    // TODO check if last argument is List/Vector
    var apply_args = MalLinkedList.init(Allocator);
    defer apply_args.deinit();
    for (args) |arg| {
        switch (arg.data) {
            .List, .Vector => |*linked_list| {
                const slice = linked_list.toOwnedSlice() catch return MalErr.OutOfMemory;
                apply_args.appendSlice(slice) catch return MalErr.OutOfMemory;
            },
            else => apply_args.append(try arg.copy(Allocator)) catch return MalErr.OutOfMemory,
        }
    }
    return apply(&apply_args);
}

fn map(args: []*MalType) MalErr!*MalType {
    if (args.len < 2) return MalErr.InvalidArgs;
    var map_results = MalLinkedList.init(Allocator);
    errdefer map_results.deinit();
    const map_fn = args[0];
    const map_sequence = try args[1].to_linked_list();
    for (map_sequence.items) |elem| {
        var apply_args = MalLinkedList.initCapacity(Allocator, 2) catch return MalErr.OutOfMemory;
        defer apply_args.deinit();
        apply_args.append(try map_fn.copy(Allocator)) catch return MalErr.OutOfMemory;
        apply_args.append(elem) catch return MalErr.OutOfMemory;
        map_results.append(try apply(&apply_args)) catch return MalErr.OutOfMemory;
    }
    return MalType.new_list(Allocator, map_results);
}

fn isNil(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    return switch (args[0].data) {
        .Nil => MalType.new_bool(Allocator, true),
        else => MalType.new_bool(Allocator, false),
    };
}

fn isTrue(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    return switch (args[0].data) {
        .Bool => |val| MalType.new_bool(Allocator, val),
        else => MalType.new_bool(Allocator, false),
    };
}

fn isFalse(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    return switch (args[0].data) {
        .Bool => |val| MalType.new_bool(Allocator, !val),
        else => MalType.new_bool(Allocator, false),
    };
}

fn isSymbol(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    return switch (args[0].data) {
        .Generic => MalType.new_bool(Allocator, true),
        else => MalType.new_bool(Allocator, false),
    };
}

fn toSymbol(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    return switch (args[0].data) {
        .String => |string| MalType.new_generic(Allocator, string),
        else => MalErr.InvalidArgs,
    };
}

fn toKeyword(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    return switch (args[0].data) {
        .String => |string| MalType.new_keyword(Allocator, string),
        .Keyword => |keyword| MalType.new_keyword(Allocator, keyword[1..]),
        else => MalErr.InvalidArgs,
    };
}

fn isKeyword(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    return switch (args[0].data) {
        .Keyword => MalType.new_bool(Allocator, true),
        else => MalType.new_bool(Allocator, false),
    };
}

fn toVector(args: []*MalType) MalErr!*MalType {
    var new_list = MalLinkedList.init(Allocator);
    errdefer new_list.deinit();
    for (args) |elem| {
        new_list.append(elem) catch return MalErr.OutOfMemory;
    }
    return MalType.new_vector(Allocator, new_list);
}

fn isVector(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    return MalType.new_bool(Allocator, args[0].data == MalTypeValue.Vector);
}

fn isSeq(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    return MalType.new_bool(Allocator, args[0].data == MalTypeValue.Vector or args[0].data == MalTypeValue.List);
}

fn toHashMap(args: []*MalType) MalErr!*MalType {
    const args_len = args.len;
    if (@rem(args_len, 2) != 0) return MalErr.InvalidArgs;
    var i: usize = 0;
    var new_map = MalHashMap.init(Allocator);
    errdefer new_map.deinit();
    while (i < args_len) {
        const key = switch (args[i].data) {
            .String => |s| s,
            .Keyword => |kwd| kwd,
            else => return MalErr.TypeError,
        };
        i += 1;
        new_map.put(key, try args[i].copy(Allocator)) catch return MalErr.OutOfMemory;
        i += 1;
    }
    return MalType.new_hashmap(Allocator, new_map);
}

fn isHashMap(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    return MalType.new_bool(Allocator, args[0].data == MalTypeValue.HashMap);
}

fn assoc(args: []*MalType) MalErr!*MalType {
    if (args[0].data != MalTypeValue.HashMap or @rem(args[1..].len, 2) != 0) return MalErr.InvalidArgs;
    var new_map = args[0].data.HashMap.clone() catch return MalErr.OutOfMemory;
    errdefer new_map.deinit();
    var i: usize = 1;
    const args_len = args.len;
    while (i < args_len) {
        const key = switch (args[i].data) {
            .String => |s| s,
            .Keyword => |kwd| kwd,
            else => return MalErr.TypeError,
        };
        i += 1;
        new_map.put(key, try args[i].copy(Allocator)) catch return MalErr.OutOfMemory;
        i += 1;
    }
    return MalType.new_hashmap(Allocator, new_map);
}

fn dissoc(args: []*MalType) MalErr!*MalType {
    const args_len = args.len;
    if (args_len < 2 or args[0].data != MalTypeValue.HashMap) return MalErr.InvalidArgs;
    var new_map = args[0].data.HashMap.clone() catch return MalErr.OutOfMemory;
    errdefer new_map.deinit();
    for (args[1..]) |key_type| {
        const key = switch (key_type.data) {
            .String => |s| s,
            .Keyword => |kwd| kwd,
            else => return MalErr.TypeError,
        };
        _ = new_map.remove(key);
    }
    return MalType.new_hashmap(Allocator, new_map);
}

fn getHashMapKey(args: []*MalType) MalErr!*MalType {
    if (args.len < 2) return MalErr.InvalidArgs;
    if (args[0].data != MalTypeValue.HashMap) return MalType.init(Allocator);
    const key = switch (args[1].data) {
        .String => |s| s,
        .Keyword => |kwd| kwd,
        else => return MalErr.TypeError,
    };
    if (args[0].data.HashMap.get(key)) |value| {
        return value.copy(Allocator);
    } else {
        return MalType.init(Allocator);
    }
}

fn isHashMapKey(args: []*MalType) MalErr!*MalType {
    if (args.len < 2 or args[0].data != MalTypeValue.HashMap) return MalErr.InvalidArgs;
    const key = switch (args[1].data) {
        .String => |s| s,
        .Keyword => |kwd| kwd,
        else => return MalErr.TypeError,
    };
    const opt_value = args[0].data.HashMap.get(key);
    if (opt_value) |_| {
        return MalType.new_bool(Allocator, true);
    } else {
        return MalType.new_bool(Allocator, false);
    }
}

fn listHashMapKeys(args: []*MalType) MalErr!*MalType {
    if (args.len < 1 or args[0].data != MalTypeValue.HashMap) return MalErr.InvalidArgs;
    var key_list = MalLinkedList.init(Allocator);
    var iterator = args[0].data.HashMap.keyIterator();
    while (iterator.next()) |key| {
        if (key.*[0] == 255) {
            key_list.append(try MalType.new_keyword(Allocator, key.*[1..])) catch return MalErr.OutOfMemory;
        } else {
            key_list.append(try MalType.new_string(Allocator, key.*)) catch return MalErr.OutOfMemory;
        }
    }
    return MalType.new_list(Allocator, key_list);
}

fn listHashMapValues(args: []*MalType) MalErr!*MalType {
    if (args.len < 1 or args[0].data != MalTypeValue.HashMap) return MalErr.InvalidArgs;
    var value_list = MalLinkedList.init(Allocator);
    var iterator = args[0].data.HashMap.valueIterator();
    while (iterator.next()) |value| {
        value_list.append(try value.*.copy(Allocator)) catch return MalErr.OutOfMemory;
    }
    return MalType.new_list(Allocator, value_list);
}

fn coreReadline(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    const user_prompt = args[0].to_string() catch return MalErr.InvalidArgs;
    const opt_line = getprompt(Allocator, user_prompt) catch return MalErr.IOError;
    if (opt_line) |line| {
        return MalType.new_string(Allocator, line);
    }
    return MalType.init(Allocator);
}

fn getMeta(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    switch (args[0].data) {
        .Fun, .DefFun, .List, .Vector, .HashMap => {
            if (args[0].meta) |meta| return meta
            else return MalType.init(Allocator);
        },
        else => return MalErr.InvalidArgs,
    }
}

fn withMeta(args: []*MalType) MalErr!*MalType {
    if (args.len < 2) return MalErr.InvalidArgs;
    switch (args[0].data) {
        .Fun, .DefFun, .List, .Vector, .HashMap => {
            var type_copy = try args[0].copy(Allocator);
            type_copy.meta = args[1];
            return type_copy;
        },
        else => return MalErr.InvalidArgs,
    }
}

fn getEpoch(args: []*MalType) MalErr!*MalType {
    if (args.len > 1) return MalErr.InvalidArgs;
    return MalType.new_int(Allocator, milliTimestamp());
}

fn conj(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    switch (args[0].data) {
        .List => |linked_list| {
            var new_list = linked_list.clone() catch return MalErr.OutOfMemory;
            errdefer new_list.deinit();
            for (args[1..]) |elem| {
                new_list.insert(0, elem) catch return MalErr.OutOfMemory;
            }
            return MalType.new_list(Allocator, new_list);
        },
        .Vector => |vector| {
            var new_vector = vector.clone() catch return MalErr.OutOfMemory;
            errdefer new_vector.deinit();
            for (args[1..]) |elem| {
                new_vector.append(elem) catch return MalErr.OutOfMemory;
            }
            return MalType.new_vector(Allocator, new_vector);
        },
        else => return MalErr.InvalidArgs,
    }
}

fn isString(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    return MalType.new_bool(Allocator, args[0].data == MalTypeValue.String);
}

fn isNumber(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    return MalType.new_bool(Allocator, args[0].data == MalTypeValue.Int);
}

fn isFunction(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    return switch (args[0].data) {
        .DefFun => |def_fun| MalType.new_bool(Allocator, !def_fun.is_macro),
        .Fun => MalType.new_bool(Allocator, true),
        else => MalType.new_bool(Allocator, false),
    };
}

fn isMacro(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    return switch (args[0].data) {
        .DefFun => |def_fun| MalType.new_bool(Allocator, def_fun.is_macro),
        else => MalType.new_bool(Allocator, false),
    };
}

fn toList(args: []*MalType) MalErr!*MalType {
    if (args.len < 1) return MalErr.InvalidArgs;
    switch (args[0].data) {
        .List => |linked_list| {
            if (linked_list.items.len == 0) return MalType.init(Allocator);
            return args[0];
        },
        .Vector => |vector| {
            if (vector.items.len == 0) return MalType.init(Allocator);
            var new_list = vector.clone() catch return MalErr.OutOfMemory;
            errdefer new_list.deinit();
            return MalType.new_list(Allocator, new_list);
        },
        .String => |string| {
            if (string.len == 0) return MalType.init(Allocator);
            var new_list = MalLinkedList.init(Allocator);
            errdefer new_list.deinit();
            var iter = std.mem.window(u8, string, 1, 1);
            while (iter.next()) |char| {
                new_list.append(try MalType.new_string(Allocator, char)) catch return MalErr.OutOfMemory;
            }
            return MalType.new_list(Allocator, new_list);
        },
        .Nil => return args[0],
        else => return MalErr.InvalidArgs,
    }
}

pub const NamespaceMapping = struct {
    name: []const u8,
    func: MalFun,
};

pub const ns = [_]NamespaceMapping{
    NamespaceMapping{ .name = "+", .func = &addInt },
    NamespaceMapping{ .name = "-", .func = &subInt },
    NamespaceMapping{ .name = "*", .func = &mulInt },
    NamespaceMapping{ .name = "/", .func = &divInt },

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

    // step 9 core functions
    NamespaceMapping{ .name = "apply", .func = &coreApply },
    NamespaceMapping{ .name = "map", .func = &map },
    NamespaceMapping{ .name = "nil?", .func = &isNil },
    NamespaceMapping{ .name = "true?", .func = &isTrue },
    NamespaceMapping{ .name = "false?", .func = &isFalse },
    NamespaceMapping{ .name = "symbol?", .func = &isSymbol },

    // step 9 deferrable functions
    NamespaceMapping{ .name = "symbol", .func = &toSymbol },
    NamespaceMapping{ .name = "keyword", .func = &toKeyword },
    NamespaceMapping{ .name = "keyword?", .func = &isKeyword },
    NamespaceMapping{ .name = "vector", .func = &toVector },
    NamespaceMapping{ .name = "vector?", .func = &isVector },
    NamespaceMapping{ .name = "sequential?", .func = &isSeq },
    NamespaceMapping{ .name = "hash-map", .func = &toHashMap },
    NamespaceMapping{ .name = "map?", .func = &isHashMap },
    NamespaceMapping{ .name = "assoc", .func = &assoc },
    NamespaceMapping{ .name = "dissoc", .func = &dissoc },
    NamespaceMapping{ .name = "get", .func = &getHashMapKey },
    NamespaceMapping{ .name = "contains?", .func = &isHashMapKey },
    NamespaceMapping{ .name = "keys", .func = &listHashMapKeys },
    NamespaceMapping{ .name = "vals", .func = &listHashMapValues },

    // step A core functions
    NamespaceMapping{ .name = "readline", .func = &coreReadline },

    // step A optional functions
    NamespaceMapping{ .name = "meta", .func = &getMeta },
    NamespaceMapping{ .name = "with-meta", .func = &withMeta },
    NamespaceMapping{ .name = "time-ms", .func = &getEpoch },
    NamespaceMapping{ .name = "conj", .func = &conj },
    NamespaceMapping{ .name = "string?", .func = &isString },
    NamespaceMapping{ .name = "number?", .func = &isNumber },
    NamespaceMapping{ .name = "fn?", .func = &isFunction },
    NamespaceMapping{ .name = "macro?", .func = &isMacro },
    NamespaceMapping{ .name = "seq", .func = &toList },
};
