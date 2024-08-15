const std = @import("std");

const Allocator = std.heap.c_allocator;
const Env = @import("env.zig").Env;
const MalData = @import("types.zig").MalData;
const MalErr = @import("error.zig").MalErr;
const MalHashMap = @import("types.zig").MalHashMap;
const MalLinkedList = @import("types.zig").MalLinkedList;
const MalType = @import("types.zig").MalType;
const apply = @import("types.zig").apply;
const builtins = @import("core.zig");
const printer = @import("printer.zig");
const reader = @import("reader.zig");
const getline = @import("readline.zig").getline;

var global_repl_env: *Env = undefined;

fn READ(input: []u8) MalErr!?*MalType {
    return try reader.read_str(input);
}

fn eval_ast(ast: *MalType, repl_env: *Env) MalErr!*MalType {
    switch (ast.data) {
        .Generic => |symbol| {
            defer ast.destroy(Allocator);
            const replacement = repl_env.get(symbol) catch |err| {
                std.debug.print("'{s}' not found.\n", .{symbol});
                return err;
            };
            return replacement.copy(Allocator);
        },
        .HashMap => |*hashmap| {
            var new_hashmap = MalHashMap.init(Allocator);
            errdefer new_hashmap.deinit();
            var iterator = hashmap.iterator();
            while (iterator.next()) |next_mal| {
                const mal_type = try EVAL(next_mal.value_ptr.*, repl_env);
                try new_hashmap.put(next_mal.key_ptr.*, mal_type);
            }
            // cleanup
            hashmap.deinit();
            ast.shallow_destroy(Allocator);

            const new_tree = MalType.new_hashmap(Allocator, new_hashmap);
            return new_tree;
        },
        .List => |*list| {
            var new_list = MalLinkedList.init(Allocator);
            errdefer new_list.deinit();
            for (list.items) |next_mal| {
                const mal_type = try EVAL(next_mal, repl_env);
                try new_list.append(mal_type);
            }
            // cleanup
            list.deinit();
            ast.shallow_destroy(Allocator);

            const new_tree = MalType.new_list(Allocator, new_list);
            return new_tree;
        },
        .Vector => |*vector| {
            var new_vector = MalLinkedList.init(Allocator);
            errdefer new_vector.deinit();
            for (vector.items) |next_mal| {
                const mal_type = try EVAL(next_mal, repl_env);
                try new_vector.append(mal_type);
            }
            // cleanup
            vector.deinit();
            ast.shallow_destroy(Allocator);

            const new_tree = MalType.new_vector(Allocator, new_vector);
            return new_tree;
        },
        else => {
            return ast;
        },
    }
}

fn EVAL(ast: *MalType, repl_env: *Env) MalErr!*MalType {
    switch (ast.data) {
        .List => |*list| {
            if (list.items.len == 0) {
                return ast;
            }
            const symbol = list.items[0].to_symbol() catch "";
            if (std.mem.eql(u8, symbol, "def!")) {
                const definition = try list.items[1].to_symbol();
                const scope_ast = try list.items[2].copy(Allocator);
                const value = try EVAL(scope_ast, repl_env);
                try repl_env.set(definition, value);
                ast.destroy(Allocator);
                return value.copy(Allocator);
            } else if (std.mem.eql(u8, symbol, "let*")) {
                const let_env = try Env.init(Allocator, repl_env, null, null);
                defer let_env.destroy(Allocator);
                var binding_seq = try list.items[1].to_linked_list();
                var i: usize = 0;
                const scope_ast = try list.items[2].copy(Allocator);
                while (i < binding_seq.items.len) {
                    const mal_key = binding_seq.items[i];
                    defer mal_key.destroy(Allocator);
                    const let = try mal_key.to_symbol();
                    i += 1;
                    const evaluated = try EVAL(binding_seq.items[i], let_env);
                    try let_env.set(let, evaluated);
                    i += 1;
                }
                // cleanup
                binding_seq.deinit();
                list.items[1].data = MalData{ .Nil = undefined };
                ast.destroy(Allocator);
                // Eval let scope
                return EVAL(scope_ast, let_env);
            } else {
                const evaluated = try eval_ast(ast, repl_env);
                return apply(try evaluated.to_linked_list());
            }
        },
        else => {
            return eval_ast(ast, repl_env);
        },
    }
    return ast;
}

fn PRINT(input: *MalType) MalErr![]const u8 {
    return printer.pr_str(input, true);
}

fn rep(input: []u8) MalErr![]const u8 {
    const opt_read_output = try READ(input);
    if (opt_read_output) |read_output| {
        const eval_output = try EVAL(read_output, global_repl_env);
        const print_output = try PRINT(eval_output);
        eval_output.destroy(Allocator);
        return print_output;
    }
    return MalErr.BadInput;
}

fn init_env() MalErr!*Env {
    global_repl_env = Env.init(Allocator, null, null, null) catch return MalErr.OutOfMemory;
    var builtin_env = global_repl_env;

    const mapping = [_]struct { []const u8, *const fn (args: []*MalType) MalErr!*MalType }{
        .{ "+", &builtins.addInt },
        .{ "-", &builtins.subInt },
        .{ "*", &builtins.mulInt },
        .{ "/", &builtins.divInt },
    };

    for (mapping) |fun_pair| {
        const fun_mal = try MalType.init(Allocator);
        fun_mal.data = MalData{ .Fun = fun_pair[1] };
        builtin_env.set(fun_pair[0], fun_mal) catch return MalErr.OutOfMemory;
    }

    return builtin_env;
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var env = init_env() catch return;
    defer env.destroy(Allocator);
    while (true) {
        const line = (try getline(Allocator)) orelse break;
        defer Allocator.free(line);
        const output = rep(line) catch continue;
        try stdout.print("{s}\n", .{output});
        Allocator.free(output);
    }
}
