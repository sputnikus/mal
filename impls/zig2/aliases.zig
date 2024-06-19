pub const Alias = struct {
    name: []const u8,
    value: []const u8,
    count: u8,
};

pub const macros = [_]Alias{
    Alias{ .name = "@", .value = "deref", .count = 1 },
    Alias{ .name = "\'", .value = "quote", .count = 1 },
    Alias{ .name = "`", .value = "quasiquote", .count = 1 },
    Alias{ .name = "~", .value = "unquote", .count = 1 },
    Alias{ .name = "~@", .value = "splice-unquote", .count = 1 },
    Alias{ .name = "^", .value = "with-meta", .count = 2 },
};

const alias_shortcuts = [_]u8{ '@', '\'', '`', '~', '^' };

pub fn is_alias(token: u8) bool {
    for (alias_shortcuts) |alias| {
        if (token == alias) {
            return true;
        }
    }
    return false;
}
