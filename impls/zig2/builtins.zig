const math = @import("std").math;

const Allocator = @import("std").heap.c_allocator;
const MalErr = @import("error.zig").MalErr;
const MalType = @import("types.zig").MalType;

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
