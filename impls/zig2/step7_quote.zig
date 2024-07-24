const std = @import("std");

const Allocator = std.heap.c_allocator;
const ArrayList = std.ArrayList;
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

fn quasiquote(ast: *MalType) MalErr!*MalType {
    switch (ast.data) {
        .List => |*list| {
            std.debug.print("{0}\n", .{(try ast.seq_len())});
            if ((try ast.seq_len()) == 0) return ast;
            defer ast.destroy(Allocator);
            const symbol = list.items[0].to_symbol() catch "";
            if (std.mem.eql(u8, symbol, "unquote")) {
                (try ast.seq_pop(0)).destroy(Allocator);
                return ast.seq_pop(0);
            } else {
                var acc = try MalType.new_list(Allocator, MalLinkedList.init(Allocator));
                while ((try ast.seq_len()) > 0) {
                    var elem = try ast.last();
                    var new_list = MalLinkedList.init(Allocator);
                    if (try elem.starts_with("splice-unquote")) {
                        (try elem.seq_pop(0)).destroy(Allocator);
                        defer elem.destroy(Allocator);
                        new_list.append(try MalType.new_generic(Allocator, "concat")) catch return MalErr.OutOfMemory;
                        new_list.append(try elem.seq_pop(0)) catch return MalErr.OutOfMemory;
                    } else {
                        new_list.append(try MalType.new_generic(Allocator, "cons")) catch return MalErr.OutOfMemory;
                        new_list.append(try quasiquote(elem)) catch return MalErr.OutOfMemory;
                    }
                    new_list.append(acc) catch return MalErr.OutOfMemory;
                    acc = try MalType.new_list(Allocator, new_list);
                }
                return acc;
            }
        },
        .Vector => {
            defer ast.destroy(Allocator);
            var acc = try MalType.new_list(Allocator, MalLinkedList.init(Allocator));
            while ((try ast.seq_len()) > 0) {
                var elem = try ast.last();
                var new_list = MalLinkedList.init(Allocator);
                if (try elem.starts_with("splice-unquote")) {
                    (try elem.seq_pop(0)).destroy(Allocator);
                    defer elem.destroy(Allocator);
                    new_list.append(try MalType.new_generic(Allocator, "concat")) catch return MalErr.OutOfMemory;
                    new_list.append(try elem.seq_pop(0)) catch return MalErr.OutOfMemory;
                } else {
                    new_list.append(try MalType.new_generic(Allocator, "cons")) catch return MalErr.OutOfMemory;
                    new_list.append(try quasiquote(elem)) catch return MalErr.OutOfMemory;
                }
                new_list.append(acc) catch return MalErr.OutOfMemory;
                acc = try MalType.new_list(Allocator, new_list);
                std.debug.print("{s}\n", .{(try printer.pr_str(acc, false))});
            }
            var vector_wrapper = MalLinkedList.init(Allocator);
            vector_wrapper.append(try MalType.new_generic(Allocator, "vec")) catch return MalErr.OutOfMemory;
            vector_wrapper.append(acc) catch return MalErr.OutOfMemory;
            return MalType.new_list(Allocator, vector_wrapper);
        },
        .HashMap, .Generic => {
            var new_list = MalLinkedList.init(Allocator);
            new_list.append(try MalType.new_generic(Allocator, "quote")) catch return MalErr.OutOfMemory;
            new_list.append(ast) catch return MalErr.OutOfMemory;
            return MalType.new_list(Allocator, new_list);
        },
        else => return ast,
    }
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
                } else if (std.mem.eql(u8, symbol, "quote")) {
                    defer tco_ast.destroy(Allocator);
                    (try tco_ast.seq_pop(0)).destroy(Allocator);
                    return try tco_ast.seq_pop(0);
                } else if (std.mem.eql(u8, symbol, "quasiquoteexpand")) {
                    (try tco_ast.seq_pop(0)).destroy(Allocator);
                    const quote = try tco_ast.seq_pop(0);
                    tco_ast.destroy(Allocator);
                    return try quasiquote(quote);
                } else if (std.mem.eql(u8, symbol, "quasiquote")) {
                    (try tco_ast.seq_pop(0)).destroy(Allocator);
                    const quote = try tco_ast.seq_pop(0);
                    tco_ast.destroy(Allocator);
                    tco_ast = try quasiquote(quote);
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

fn eval(args: []*MalType) MalErr!*MalType {
    return EVAL(try args[0].copy(Allocator), try global_repl_env.copy(Allocator));
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

fn init_env(args: [][]u8) MalErr!*Env {
    global_repl_env = Env.init(Allocator, null, null, null) catch return MalErr.OutOfMemory;
    var builtin_env = global_repl_env;

    for (core.ns) |fun_pair| {
        const fun_mal = try MalType.init(Allocator);
        fun_mal.data = MalData{ .Fun = fun_pair.func };
        try builtin_env.set(fun_pair.name, fun_mal);
    }

    var arg_list = MalLinkedList.init(Allocator);
    errdefer arg_list.deinit();
    if (args.len > 2) {
        for (args[2..]) |arg| {
            const arg_str = try MalType.new_string(Allocator, arg);
            try arg_list.append(arg_str);
        }
    }
    try builtin_env.set("*ARGV*", try MalType.new_list(Allocator, arg_list));

    const eval_fn = try MalType.init(Allocator);
    eval_fn.data = MalData{ .Fun = &eval };
    try builtin_env.set("eval", eval_fn);

    const def_not_string = "(def! not (fn* (a) (if a false true)))";
    var output = try rep(def_not_string);
    Allocator.free(output);

    const def_load_file =
        \\(def! load-file (fn* (f) (eval (read-string (str "(do " (slurp f) "\nnil)")))))
    ;
    output = try rep(def_load_file);
    Allocator.free(output);

    return builtin_env;
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(Allocator);
    defer std.process.argsFree(Allocator, args);
    var env = init_env(args) catch return;
    defer env.destroy(Allocator);

    if (args.len > 1) {
        var run_cmd = ArrayList(u8).init(Allocator);
        try std.fmt.format(run_cmd.writer(), "(load-file \"{s}\")", .{args[1]});
        const line = try run_cmd.toOwnedSlice();
        defer Allocator.free(line);
        _ = try rep(line);
        return;
    }

    while (true) {
        const line = (try getline(Allocator)) orelse break;
        defer Allocator.free(line);
        const output = rep(line) catch continue;
        try stdout.print("{s}\n", .{output});
        Allocator.free(output);
    }
}
