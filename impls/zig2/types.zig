const std = @import("std");
const mem = @import("std").mem;

const Allocator = @import("std").heap.c_allocator;
const ArrayList = @import("std").ArrayList;
const MalErr = @import("error.zig").MalErr;

pub const MalLinkedList = ArrayList(*MalType);

pub const MalTypeValue = enum {
    Bool,
    Generic,
    Int,
    List,
    Nil,
    String,
    Symbol,
};

pub const MalData = union(MalTypeValue) {
    Bool: bool,
    Generic: []const u8,
    Int: i64,
    List: MalLinkedList,
    Nil: void,
    String: []const u8,
    Symbol: []const u8,
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
        errdefer allocator.destroy(mal_type);
        const value_copy = mem.Allocator.dupe(allocator, u8, value) catch return MalErr.OutOfMemory;
        errdefer allocator.destroy(value_copy);
        mal_type.data = MalData{ .Generic = value_copy };
        return mal_type;
    }

    pub fn new_int(allocator: @TypeOf(Allocator), value: i64) MalErr!*MalType {
        const mal_type = try MalType.init(allocator);
        mal_type.data = MalData{ .Int = value };
        return mal_type;
    }

    pub fn new_string(allocator: @TypeOf(Allocator), value: []const u8) MalErr!*MalType {
        const mal_type = try MalType.init(allocator);
        errdefer allocator.destroy(mal_type);
        const value_copy = mem.Allocator.dupe(allocator, u8, value) catch return MalErr.OutOfMemory;
        errdefer allocator.destroy(value_copy);
        mal_type.data = MalData{ .String = value_copy };
        return mal_type;
    }

    pub fn new_symbol(allocator: @TypeOf(Allocator), value: []const u8) MalErr!*MalType {
        const mal_type = try MalType.init(allocator);
        errdefer allocator.destroy(mal_type);
        const value_copy = mem.Allocator.dupe(allocator, u8, value) catch return MalErr.OutOfMemory;
        errdefer allocator.destroy(value_copy);
        mal_type.data = MalData{ .Symbol = value_copy };
        return mal_type;
    }

    pub fn new_list(allocator: @TypeOf(Allocator), linked_list: MalLinkedList) MalErr!*MalType {
        const mal = try MalType.init(allocator);
        mal.data = MalData{ .List = linked_list };
        return mal;
    }

    pub fn destroy(self: *MalType, allocator: @TypeOf(Allocator)) void {
        switch (self.data) {
            .List => |*linked_list| {
                const ll_slice = linked_list.items;
                var i: usize = 0;
                while (i < ll_slice.len) {
                    ll_slice[i].destroy(allocator);
                    i += 1;
                }
                linked_list.deinit();
            },
            .Symbol => |string| {
                allocator.free(string);
            },
            else => {},
        }
        if (self.meta) |mal_meta| {
            mal_meta.destroy(allocator);
        }
        allocator.destroy(self);
    }
};
