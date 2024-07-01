const mem = @import("std").mem;

const Allocator = @import("std").heap.c_allocator;
const MalErr = @import("error.zig").MalErr;
const MalHashMap = @import("types.zig").MalHashMap;
const MalType = @import("types.zig").MalType;

pub const Env = struct {
    outer: ?**Env,
    data: *MalHashMap,
    ref_counter: *i64,

    pub fn init(allocator: @TypeOf(Allocator), opt_outer: ?*Env) MalErr!*Env {
        const new_env: *Env = allocator.create(Env) catch return MalErr.OutOfMemory;
        new_env.ref_counter = allocator.create(i64) catch return MalErr.OutOfMemory;
        new_env.ref_counter.* = 1;
        new_env.outer = null;
        if (opt_outer) |outer| {
            const env_copy = allocator.create(*Env) catch return MalErr.OutOfMemory;
            env_copy.* = try outer.copy(allocator);
            new_env.outer = env_copy;
        }
        new_env.data = allocator.create(MalHashMap) catch return MalErr.OutOfMemory;
        new_env.data.* = MalHashMap.init(allocator);
        return new_env;
    }

    pub fn set(self: *Env, symbol: []const u8, value: *MalType) MalErr!void {
        const old_data = self.data.get(symbol);
        const symbol_copy = mem.Allocator.dupe(Allocator, u8, symbol) catch return MalErr.OutOfMemory;
        if (old_data) |existing| {
            existing.destroy(Allocator);
        }

        self.data.put(symbol_copy, value) catch return MalErr.OutOfMemory;
    }

    pub fn find(self: *Env, symbol: []const u8) MalErr!bool {
        const opt_lookup = self.data.get(symbol);
        if (opt_lookup) {
            return true;
        }
        if (self.outer) |outer| {
            return outer.*.find(symbol);
        }
        return false;
    }

    pub fn get(self: *Env, symbol: []const u8) MalErr!*MalType {
        const opt_lookup = self.data.get(symbol);
        if (opt_lookup) |lookup| {
            return lookup;
        }
        if (self.outer) |outer| {
            return outer.*.get(symbol);
        }
        return MalErr.LookupError;
    }

    pub fn destroy(self: *Env, allocator: @TypeOf(Allocator)) void {
        self.ref_counter.* -= 1;
        if (self.ref_counter.* <= 0) {
            if (self.outer) |*outer| {
                outer.*.*.destroy(allocator);
                allocator.destroy(self.outer.?);
            }

            var iterator = self.data.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.*.destroy(allocator);
            }
            self.data.deinit();
            allocator.destroy(self.data);
            allocator.destroy(self.ref_counter);
        }
        allocator.destroy(self);
    }

    pub fn copy(self: *Env, allocator: @TypeOf(Allocator)) MalErr!*Env {
        const env_copy: *Env = allocator.create(Env) catch return MalErr.OutOfMemory;
        env_copy.ref_counter = self.ref_counter;
        self.ref_counter.* += 1;
        env_copy.outer = self.outer;
        env_copy.data = self.data;
        return env_copy;
    }
};
