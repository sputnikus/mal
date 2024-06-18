const std = @import("std");

pub const pcre = @cImport({
    @cInclude("pcre.h");
});

const Allocator = @import("std").heap.c_allocator;
const MalData = @import("types.zig").MalData;
const MalErr = @import("error.zig").MalErr;
const MalLinkedList = @import("types.zig").MalLinkedList;
const MalType = @import("types.zig").MalType;

// PCRE shenanigans
const match: [*]const u8 =
    \\[\s,]*(~@|[\[\]{}()'`~^@]|"(?:\\.|[^\\"])*"?|;.*|[^\s\[\]{}('"`,;)]*)
;
var error_msg: [*c]const u8 = undefined;
var erroroffset: c_int = 0;
var re: ?*pcre.pcre = null;

pub const Reader = struct {
    position: u32,
    string: []const u8,
    tokens: []usize,

    pub fn init(string: []const u8, tokens: []usize) Reader {
        return Reader{
            .position = 0,
            .string = string,
            .tokens = tokens,
        };
    }

    // Returns the token at the current position and increments the position
    pub fn next(self: *Reader) []const u8 {
        const current_token = self.peek();
        self.position += 2;
        return current_token;
    }

    // Returns the token at the current position
    pub fn peek(self: *Reader) []const u8 {
        if (!self.eol()) {
            const start_slice = self.tokens[self.position];
            const end_slice = self.tokens[self.position + 1];
            return self.string[start_slice..end_slice];
        }
        return "";
    }

    // End of input detection
    pub fn eol(self: *Reader) bool {
        return (self.position >= self.tokens.len);
    }
};

pub fn read_str(string: []const u8) MalErr!?*MalType {
    const tokens = try tokenize(string);
    var reader = Reader.init(string, tokens);
    return read_form(&reader);
}

pub fn tokenize(string: []const u8) MalErr![]usize {
    if (re == null) {
        re = pcre.pcre_compile(&match[0], 0, &error_msg, &erroroffset, 0);
    }

    // start_match + end_match
    const buffer_size: usize = 3 * string.len + 10;
    var indices: []c_int = Allocator.alloc(c_int, buffer_size) catch return MalErr.OutOfMemory;
    defer Allocator.free(indices);
    var match_buffer: []usize = Allocator.alloc(usize, buffer_size) catch return MalErr.OutOfMemory;
    var current_match: usize = 0;
    var start_pos: c_int = 0;

    var rc: c_int = 0;
    var start_match: usize = 0;
    var end_match: usize = 0;
    const subject_size: c_int = @intCast(string.len);

    while (start_pos < subject_size) {
        rc = pcre.pcre_exec(re, 0, &string[0], subject_size, start_pos, 0, &indices[0], @intCast(buffer_size));
        if (rc <= 0)
            break;
        start_pos = indices[1];
        start_match = @intCast(indices[2]);
        end_match = @intCast(indices[3]);
        match_buffer[current_match] = start_match;
        match_buffer[current_match + 1] = end_match;
        current_match += 2;
    }

    // exact size of resulting matches
    var matches: []usize = Allocator.alloc(usize, current_match) catch return MalErr.OutOfMemory;
    var i: usize = 0;
    while (i < current_match) {
        matches[i] = match_buffer[i];
        i += 1;
    }
    return matches;
}

pub fn read_form(reader: *Reader) MalErr!?*MalType {
    if (reader.eol()) {
        return null;
    }
    const token = reader.peek();
    if (token[0] == '(') {
        return read_list(reader);
    }

    return read_symbol(reader);
}

fn read_list(reader: *Reader) MalErr!?*MalType {
    // we know we are in list, skip opening paren
    _ = reader.next();
    var new_list = MalLinkedList.init(Allocator);
    errdefer new_list.deinit();

    while (!reader.eol()) {
        const next_token = reader.peek();

        // ended inside of a list
        if (next_token.len < 1) {
            return MalErr.UnmatchedParen;
        }

        if (next_token[0] == ')') {
            // skip closing paren
            _ = reader.next();
            return MalType.new_list(Allocator, new_list);
        }

        const mal_type = (try read_form(reader)) orelse return MalErr.BadInput;
        try new_list.append(mal_type);
    }

    return MalErr.UnmatchedParen;
}

fn read_symbol(reader: *Reader) MalErr!?*MalType {
    const token = reader.next();
    return try MalType.new_symbol(Allocator, token);
}
