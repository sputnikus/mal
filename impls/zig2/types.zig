const std = @import("std");
const mem = @import("std").mem;

const Allocator = @import("std").heap.c_allocator;
const ArrayList = @import("std").ArrayList;
const HashMap = @import("std").StringHashMap;
const MalErr = @import("error.zig").MalErr;

pub const MalHashMap = HashMap(*MalType);
pub const MalLinkedList = ArrayList(*MalType);

pub const MalTypeValue = enum {
    Bool,
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
            .List => |*linked_list| {
                const ll_slice = linked_list.items;
                var i: usize = 0;
                while (i < ll_slice.len) {
                    ll_slice[i].destroy(allocator);
                    i += 1;
                }
                linked_list.deinit();
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
        if (self.meta) |mal_meta| {
            mal_meta.destroy(allocator);
        }
        allocator.destroy(self);
    }
};
