const std = @import("std");

const Allocator = @import("std").heap.c_allocator;
const MalData = @import("types.zig").MalData;
const MalErr = @import("error.zig").MalErr;
const MalHashMap = @import("types.zig").MalHashMap;
const MalLinkedList = @import("types.zig").MalLinkedList;
const MalType = @import("types.zig").MalType;
const apply = @import("types.zig").apply;
const builtins = @import("builtins.zig");
const printer = @import("printer.zig");
const reader = @import("reader.zig");
const getline = @import("readline.zig").getline;

fn READ(input: []u8) MalErr!?*MalType {
    return try reader.read_str(input);
}

fn eval_ast(ast: ?*MalType, repl_env: *MalHashMap) MalErr!?*MalType {
    switch (ast.?.data) {
        .Generic => |symbol| {
            defer ast.?.destroy(Allocator);
            const optional_fun = repl_env.get(symbol);
            if (optional_fun) |fun| {
                return fun;
            }
            return MalErr.LookupError;
        },
        .HashMap => |*hashmap| {
            var new_hashmap = MalHashMap.init(Allocator);
            errdefer new_hashmap.deinit();
            var iterator = hashmap.iterator();
            while (iterator.next()) |next_mal| {
                const optional_mal_type = try EVAL(next_mal.value_ptr.*, repl_env);
                if (optional_mal_type) |mal_type| {
                    try new_hashmap.put(next_mal.key_ptr.*, mal_type);
                }
            }
            // cleanup
            Allocator.destroy(hashmap);

            const new_tree = MalType.new_hashmap(Allocator, new_hashmap);
            return new_tree;
        },
        .List => |*linked_list| {
            var new_list = MalLinkedList.init(Allocator);
            errdefer new_list.deinit();
            for (linked_list.items) |next_mal| {
                const optional_mal_type = try EVAL(next_mal, repl_env);
                if (optional_mal_type) |mal_type| {
                    try new_list.append(mal_type);
                }
            }
            // cleanup
            Allocator.destroy(linked_list);

            const new_tree = MalType.new_list(Allocator, new_list);
            return new_tree;
        },
        .Vector => |*vector| {
            var new_vector = MalLinkedList.init(Allocator);
            errdefer new_vector.deinit();
            for (vector.items) |next_mal| {
                const optional_mal_type = try EVAL(next_mal, repl_env);
                if (optional_mal_type) |mal_type| {
                    try new_vector.append(mal_type);
                }
            }
            // cleanup
            Allocator.destroy(vector);

            const new_tree = MalType.new_vector(Allocator, new_vector);
            return new_tree;
        },
        else => {
            return ast;
        },
    }
}

fn EVAL(ast: ?*MalType, repl_env: *MalHashMap) MalErr!?*MalType {
    switch (ast.?.data) {
        .List => |*linked_list| {
            if (linked_list.items.len == 0) {
                return ast;
            }
            const optional_evaluated = try eval_ast(ast, repl_env);
            if (optional_evaluated) |evaluated| {
                return apply(try evaluated.to_linked_list());
            }
        },
        else => {
            return eval_ast(ast, repl_env);
        },
    }
    return ast;
}

fn PRINT(input: ?*MalType) ![]const u8 {
    const output = printer.pr_str(input, true) catch "Allocation error";
    return output;
}

fn rep(input: []u8) []const u8 {
    const read_output = READ(input) catch return "EOF";
    const repl_env = init_env() catch return "Invalid environment";
    const eval_output = EVAL(read_output, repl_env) catch return "Eval error";
    const print_output = PRINT(eval_output);
    if (eval_output) |mal| {
        mal.destroy(Allocator);
    }
    return print_output catch "EOF";
}

fn init_env() MalErr!*MalHashMap {
    var builtin_env = Allocator.create(MalHashMap) catch return MalErr.OutOfMemory;
    builtin_env.* = MalHashMap.init(Allocator);

    const mapping = [_]struct { []const u8, *const fn (args: []*MalType) MalErr!*MalType }{
        .{ "+", &builtins.add_int },
        .{ "-", &builtins.sub_int },
        .{ "*", &builtins.mul_int },
        .{ "/", &builtins.div_int },
    };

    for (mapping) |fun_pair| {
        const fun_mal = try MalType.init(Allocator);
        fun_mal.data = MalData{ .Fun = fun_pair[1] };
        builtin_env.put(fun_pair[0], fun_mal) catch return MalErr.OutOfMemory;
    }

    return builtin_env;
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
