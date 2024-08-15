const std = @import("std");
const Allocator = std.mem.Allocator;
const readline = @cImport({
    @cInclude("stdio.h");
    @cInclude("readline/readline.h");
});
const rl_hist = @cImport({
    @cInclude("stdio.h");
    @cInclude("readline/history.h");
});
const free = std.c.free;

pub fn slice_from_cstr(allocator: Allocator, str: [*]const u8) ![]u8 {
    var length: usize = 0;
    while (true) {
        if (str[length] == 0)
            break;
        length += 1;
    }
    // TODO: check for 0-length
    const slice = try allocator.alloc(u8, length);
    var i: usize = 0;
    while (i < length) {
        slice[i] = str[i];
        i += 1;
    }
    return slice;
}

pub fn getline(allocator: Allocator) !?[]u8 {
    const input: ?[*]u8 = readline.readline("user> ");
    if (input) |actual| {
        const aslice = try slice_from_cstr(allocator, actual);
        rl_hist.add_history(actual);
        free(actual);
        return aslice;
    }
    return null;
}

// Same as getline but we are providing user input
pub fn getprompt(allocator: Allocator, prompt: []const u8) !?[]u8 {
    const null_terminated_prompt = try allocator.alloc(u8, prompt.len);
    defer allocator.free(null_terminated_prompt);
    for (null_terminated_prompt) |*d| d.* = 0;
    std.mem.copyForwards(u8, null_terminated_prompt, prompt);
    const input: ?[*] u8 = readline.readline(null_terminated_prompt.ptr);
    if(input) |actual| {
        const aslice = try slice_from_cstr(allocator, actual);
        rl_hist.add_history(actual);
        free(actual);
        return aslice;
    }
    return null;
}
