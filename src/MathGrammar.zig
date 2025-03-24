const std = @import("std");
const grammar = @import("grammar.zig");

const Rule = grammar.RuleFrom(Rules);
pub const Rules = enum {
    root,
    expression,
    value,
    number,
    identifier,
    operator,
};

pub fn ignore_whitespace() void {}

root: Rule = .{ .subrule = .expression },

expression: Rule = .{ .choice = &[_]Rule{
    .{ .seq = &[_]Rule{
        .{ .regex = "\\(" },
        .{ .subrule = .expression },
        .{ .regex = "\\)" },
    } },
    .{ .seq = &[_]Rule{
        .{ .subrule = .value },
        .{ .repeat = &[_]Rule{
            .{ .subrule = .operator },
            .{ .subrule = .expression },
        } },
    } },
} },

operator: Rule = .{ .regex = "[\\-/\\*\\+^]" },

value: Rule = .{ .choice = &[_]Rule{
    .{ .subrule = .identifier },
    .{ .subrule = .number },
} },

number: Rule = .{ .regex = "+{0-9}" },
identifier: Rule = .{ .regex = "+[_{a-z}{A-Z}]" },
