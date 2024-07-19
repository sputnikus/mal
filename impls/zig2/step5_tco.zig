const std = @import("std");

const Allocator = std.heap.c_allocator;
const Env = @import("env.zig").Env;
const MalData = @import("types.zig").MalData;
const MalErr = @import("error.zig").MalErr;
const MalHashMap = @import("types.zig").MalHashMap;
const MalLinkedList = @import("types.zig").MalLinkedList;
const MalType = @import("types.zig").MalType;
const apply = @import("types.zig").apply;
const core = @import("core.zig");
const printer = @import("printer.zig");
const reader = @import("reader.zig");
const getline = @import("readline.zig").getline;

var global_repl_env: *Env = undefined;

fn READ(input: []const u8) MalErr!?*MalType {
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
    var tco_ast = ast;
    var tco_env = repl_env;
    while (true) {
        switch (tco_ast.data) {
            .List => |*list| {
                if (list.items.len == 0) {
                    return tco_ast;
                }
                const symbol = list.items[0].to_symbol() catch "";
                if (std.mem.eql(u8, symbol, "def!")) {
                    const definition = try list.items[1].to_symbol();
                    const scope_ast = try list.items[2].copy(Allocator);
                    const value = try EVAL(scope_ast, repl_env);
                    try tco_env.set(definition, value);
                    tco_ast.destroy(Allocator);
                    return value.copy(Allocator);
                } else if (std.mem.eql(u8, symbol, "let*")) {
                    const let_env = try Env.init(Allocator, tco_env, null, null);
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
                    tco_ast.destroy(Allocator);
                    // Propagate new ast and env
                    tco_ast = scope_ast;
                    tco_env = let_env;
                    continue;
                } else if (std.mem.eql(u8, symbol, "do")) {
                    const rest = try tco_ast.rest();
                    const last = try rest.last();
                    var do_result = try eval_ast(rest, tco_env);
                    defer do_result.destroy(Allocator);
                    tco_ast = last;
                    continue;
                } else if (std.mem.eql(u8, symbol, "if")) {
                    const condition = try list.items[1].copy(Allocator);
                    const evaled_cond = try EVAL(condition, tco_env);
                    const branch = switch (evaled_cond.data) {
                        .Bool => |boolean| boolean,
                        .Nil => false,
                        else => true,
                    };
                    if (branch) {
                        tco_ast = try list.items[2].copy(Allocator);
                    } else if (list.items.len >= 4) {
                        tco_ast = try list.items[3].copy(Allocator);
                    }
                    continue;
                } else if (std.mem.eql(u8, symbol, "fn*")) {
                    defer tco_ast.destroy(Allocator);
                    const mal_fun = try MalType.new_function(Allocator, tco_ast, tco_env, &EVAL);
                    return mal_fun;
                } else {
                    const evaluated = try eval_ast(tco_ast, tco_env);
                    const evaluated_list = try evaluated.to_linked_list();
                    switch (evaluated_list.items[0].data) {
                        .DefFun => |def_fun| {
                            tco_ast = def_fun.body;
                            const arg_vars = try def_fun.args.to_linked_list();
                            const scope_args = arg_vars.toOwnedSlice() catch return MalErr.OutOfMemory;
                            tco_env = try Env.init(Allocator, def_fun.env, scope_args, evaluated_list.items[1..]);
                            continue;
                        },
                        .Fun => {
                            return apply(evaluated_list);
                        },
                        else => {
                            std.debug.print("Cannot evaluate non-function symbol\n", .{});
                            return MalErr.TypeError;
                        },
                    }
                }
            },
            else => {
                return eval_ast(tco_ast, tco_env);
            },
        }
    }
}

fn PRINT(input: *MalType) MalErr![]const u8 {
    return printer.pr_str(input, true);
}

fn rep(input: []const u8) MalErr![]const u8 {
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

    for (core.ns) |fun_pair| {
        const fun_mal = try MalType.init(Allocator);
        fun_mal.data = MalData{ .Fun = fun_pair.func };
        builtin_env.set(fun_pair.name, fun_mal) catch return MalErr.OutOfMemory;
    }

    const def_not_string = "(def! not (fn* (a) (if a false true)))";
    const output = try rep(def_not_string);
    Allocator.free(output);

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
