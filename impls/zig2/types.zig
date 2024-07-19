const std = @import("std");
const mem = @import("std").mem;
const Allocator = @import("std").heap.c_allocator;
const ArrayList = @import("std").ArrayList;
const HashMap = @import("std").StringHashMap;

const Env = @import("env.zig").Env;
const MalErr = @import("error.zig").MalErr;

pub const MalHashMap = HashMap(*MalType);
pub const MalLinkedList = ArrayList(*MalType);
pub const MalFun = *const fn (args: []*MalType) MalErr!*MalType;
// replacement for user defined function closures
pub const MalDefFun = struct {
    args: *MalType,
    body: *MalType,
    env: *Env,
    eval_fn: ?(*const fn (ast: *MalType, env: *Env) MalErr!*MalType),
};

pub const MalTypeValue = enum {
    Bool,
    DefFun,
    Fun,
    Generic,
    HashMap,
    Int,
    Keyword,
    List,
    Nil,
    String,
    Vector,
};

pub const MalData = union(MalTypeValue) {
    Bool: bool,
    DefFun: MalDefFun,
    Fun: MalFun,
    Generic: []const u8,
    HashMap: MalHashMap,
    Int: i64,
    Keyword: []const u8,
    List: MalLinkedList,
    Nil: void,
    String: []const u8,
    Vector: MalLinkedList,
};

pub const MalType = struct {
    data: MalData,
    meta: ?*MalType,

    // nil type
    pub fn init(allocator: @TypeOf(Allocator)) MalErr!*MalType {
        const mal_type: *MalType = allocator.create(MalType) catch return MalErr.OutOfMemory;
        errdefer allocator.destroy(mal_type);
        mal_type.data = MalData{ .Nil = undefined };
        mal_type.meta = null;
        return mal_type;
    }

    pub fn new_bool(allocator: @TypeOf(Allocator), value: bool) MalErr!*MalType {
        const mal_type = try MalType.init(allocator);
        mal_type.data = MalData{ .Bool = value };
        return mal_type;
    }

    // create new user defined function
    pub fn new_function(allocator: @TypeOf(Allocator), ast: *MalType, env: *Env, eval_fn: ?(*const fn (ast: *MalType, env: *Env) MalErr!*MalType)) MalErr!*MalType {
        const mal_type = try MalType.init(allocator);
        const ast_list = try ast.to_linked_list();
        const args = ast_list.items[1].copy(allocator) catch return MalErr.OutOfMemory;
        const body = ast_list.items[2].copy(allocator) catch return MalErr.OutOfMemory;
        mal_type.data = MalData{ .DefFun = MalDefFun{ .args = args, .body = body, .env = env, .eval_fn = eval_fn } };
        return mal_type;
    }

    pub fn new_generic(allocator: @TypeOf(Allocator), value: []const u8) MalErr!*MalType {
        const mal_type = try MalType.init(allocator);
        const value_copy = mem.Allocator.dupe(allocator, u8, value) catch return MalErr.OutOfMemory;
        mal_type.data = MalData{ .Generic = value_copy };
        return mal_type;
    }

    pub fn new_hashmap(allocator: @TypeOf(Allocator), hashmap: MalHashMap) MalErr!*MalType {
        const mal_type = try MalType.init(allocator);
        mal_type.data = MalData{ .HashMap = hashmap };
        return mal_type;
    }

    pub fn new_int(allocator: @TypeOf(Allocator), value: i64) MalErr!*MalType {
        const mal_type = try MalType.init(allocator);
        mal_type.data = MalData{ .Int = value };
        return mal_type;
    }

    pub fn new_keyword(allocator: @TypeOf(Allocator), value: []const u8) MalErr!*MalType {
        const mal_type = try MalType.init(allocator);
        const kwd_prefix = [_]u8{255};
        const kwd_copy = mem.concat(allocator, u8, &[_][]const u8{ &kwd_prefix, value }) catch return MalErr.OutOfMemory;
        mal_type.data = MalData{ .Keyword = kwd_copy };
        return mal_type;
    }

    pub fn new_list(allocator: @TypeOf(Allocator), linked_list: MalLinkedList) MalErr!*MalType {
        const mal_type = try MalType.init(allocator);
        mal_type.data = MalData{ .List = linked_list };
        return mal_type;
    }

    pub fn new_string(allocator: @TypeOf(Allocator), value: []const u8) MalErr!*MalType {
        const mal_type = try MalType.init(allocator);
        const value_copy = mem.Allocator.dupe(allocator, u8, value) catch return MalErr.OutOfMemory;
        mal_type.data = MalData{ .String = value_copy };
        return mal_type;
    }

    pub fn new_vector(allocator: @TypeOf(Allocator), vector: MalLinkedList) MalErr!*MalType {
        const mal_type = try MalType.init(allocator);
        mal_type.data = MalData{ .Vector = vector };
        return mal_type;
    }

    pub fn to_int(self: *MalType) MalErr!i64 {
        return switch (self.data) {
            .Int => |int| int,
            else => MalErr.TypeError,
        };
    }

    pub fn to_linked_list(self: *MalType) MalErr!*MalLinkedList {
        return switch (self.data) {
            .List => |*l| l,
            .Vector => |*v| v,
            else => MalErr.TypeError,
        };
    }

    pub fn to_symbol(self: *MalType) MalErr![]const u8 {
        return switch (self.data) {
            .Generic => |g| g,
            else => MalErr.TypeError,
        };
    }

    // If type is list, return list without list head
    pub fn rest(self: *MalType) MalErr!*MalType {
        var list = switch (self.data) {
            .List => |*l| l,
            else => return MalErr.TypeError,
        };
        if (list.items.len == 0) {
            return MalErr.OutOfBounds;
        } else {
            const first = list.orderedRemove(0);
            first.destroy(Allocator);
        }

        return self;
    }

    // If type is list, pop last element
    pub fn last(self: *MalType) MalErr!*MalType {
        var list = switch (self.data) {
            .List => |*l| l,
            else => return MalErr.TypeError,
        };
        if (list.items.len == 0) {
            return MalErr.OutOfBounds;
        }
        return list.pop();
    }

    // If type is list, get list head
    pub fn head(self: *MalType) MalErr!*MalType {
        const list = switch (self.data) {
            .List => |*l| l,
            else => return MalErr.TypeError,
        };
        if (list.items.len == 0) {
            return MalErr.OutOfBounds;
        }
        return list.items[0].copy(Allocator);
    }

    pub fn copy(self: *MalType, allocator: @TypeOf(Allocator)) MalErr!*MalType {
        var mal_copy = try MalType.init(allocator);
        if (self.meta) |meta| {
            mal_copy.meta = try meta.copy(allocator);
        } else {
            mal_copy.meta = null;
        }

        switch (self.data) {
            .Bool => |boolean| {
                mal_copy.data = MalData{ .Bool = boolean };
            },
            .DefFun => |def_fun| {
                const args = try def_fun.args.copy(allocator);
                const body = try def_fun.body.copy(allocator);
                const def_fun_copy = MalDefFun{
                    .args = args,
                    .body = body,
                    .env = try def_fun.env.copy(allocator),
                    .eval_fn = def_fun.eval_fn,
                };
                mal_copy.data = MalData{ .DefFun = def_fun_copy };
            },
            .Fun => |function| {
                mal_copy.data = MalData{ .Fun = function };
            },
            .Generic => |generic| {
                const generic_copy = mem.Allocator.dupe(allocator, u8, generic) catch return MalErr.OutOfMemory;
                mal_copy.data = MalData{ .Generic = generic_copy };
            },
            .HashMap => |*hashmap| {
                var hashmap_copy = MalHashMap.init(allocator);
                var iterator = hashmap.iterator();
                while (iterator.next()) |pair| {
                    const key = mem.Allocator.dupe(allocator, u8, pair.key_ptr.*) catch return MalErr.OutOfMemory;
                    const value = try pair.value_ptr.*.copy(allocator);
                    hashmap_copy.put(key, value) catch return MalErr.OutOfMemory;
                }
                mal_copy.data = MalData{ .HashMap = hashmap_copy };
            },
            .Int => |integer| {
                mal_copy.data = MalData{ .Int = integer };
            },
            .Keyword => |keyword| {
                const keyword_copy = mem.Allocator.dupe(allocator, u8, keyword) catch return MalErr.OutOfMemory;
                mal_copy.data = MalData{ .Keyword = keyword_copy };
            },
            .List => |*list| {
                var list_copy = MalLinkedList.init(Allocator);
                errdefer list_copy.deinit();
                for (list.items) |elem| {
                    const elem_copy = try elem.copy(allocator);
                    try list_copy.append(elem_copy);
                }
                mal_copy.data = MalData{ .List = list_copy };
            },
            .String => |string| {
                const string_copy = mem.Allocator.dupe(allocator, u8, string) catch return MalErr.OutOfMemory;
                mal_copy.data = MalData{ .String = string_copy };
            },
            .Vector => |*vector| {
                var vector_copy = MalLinkedList.init(Allocator);
                errdefer vector_copy.deinit();
                for (vector.items) |elem| {
                    const elem_copy = try elem.copy(allocator);
                    try vector_copy.append(elem_copy);
                }
                mal_copy.data = MalData{ .Vector = vector_copy };
            },
            else => {
                // to prevent accidental Nil copy
                mal_copy.data = self.data;
            },
        }

        return mal_copy;
    }

    pub fn shallow_destroy(self: *MalType, allocator: @TypeOf(Allocator)) void {
        if (self.meta) |meta| {
            meta.destroy(allocator);
        }
        allocator.destroy(self);
    }

    pub fn destroy(self: *MalType, allocator: @TypeOf(Allocator)) void {
        switch (self.data) {
            .Generic => |string| {
                allocator.free(string);
            },
            .HashMap => |*hashmap| {
                var iterator = hashmap.iterator();

                while (iterator.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    entry.value_ptr.*.destroy(allocator);
                }
                hashmap.deinit();
            },
            .Keyword => |string| {
                allocator.free(string);
            },
            .List => |*list| {
                const ll_slice = list.items;
                var i: usize = 0;
                while (i < ll_slice.len) {
                    ll_slice[i].destroy(allocator);
                    i += 1;
                }
                list.deinit();
            },
            .String => |string| {
                allocator.free(string);
            },
            .Vector => |*vector| {
                const vec_slice = vector.items;
                var i: usize = 0;
                while (i < vec_slice.len) {
                    vec_slice[i].destroy(allocator);
                    i += 1;
                }
                vector.deinit();
            },
            else => {},
        }
        self.shallow_destroy(allocator);
    }
};

// applies first element of list onto the rest
pub fn apply(args: *MalLinkedList) MalErr!*MalType {
    var args_clone = try args.clone();
    defer args_clone.deinit();
    var apply_slice = try args_clone.toOwnedSlice();
    const mal_fun = apply_slice[0];
    const mal_arguments = apply_slice[1..];

    switch (mal_fun.data) {
        .DefFun => |def_fun| {
            const arg_vars = try def_fun.args.to_linked_list();
            const env = def_fun.env;
            // can't eval without eval function
            const eval_fn = def_fun.eval_fn orelse return MalErr.TypeError;
            const scope_args = arg_vars.toOwnedSlice() catch return MalErr.OutOfMemory;
            const scope_env = try Env.init(Allocator, env, scope_args, mal_arguments);

            const new_body = try def_fun.body.copy(Allocator);
            mal_fun.destroy(Allocator);
            return eval_fn(new_body, scope_env);
        },
        .Fun => |core_fun| {
            return core_fun(mal_arguments);
        },
        else => {
            return MalErr.InvalidArgs;
        },
    }
}
