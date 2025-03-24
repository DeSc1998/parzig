const std = @import("std");
const grammar = @import("grammar.zig");

const Rule = grammar.RuleFrom(Rules);
pub const Rules = enum {
    root,
    expression,
    char,
    any_char,
    escaped_char,
    seq,
    choices,
    repeats,
    repeats_plus,
    range,
};

root: Rule =
    .{ .repeat = &[_]Rule{
        .{ .subrule = .expression },
    } },

expression: Rule = .{ .choice = &[_]Rule{
    .{ .subrule = .seq },
    .{ .subrule = .choices },
    .{ .subrule = .repeats },
    .{ .subrule = .repeats_plus },
    .{ .subrule = .range },
    .{ .subrule = .escaped_char },
    .{ .subrule = .any_char },
    .{ .subrule = .char },
} },

seq: Rule = .{ .seq = &[_]Rule{
    .{ .regex = "\\(" },
    .{ .repeat = &[_]Rule{
        .{ .subrule = .expression },
    } },
    .{ .regex = "\\)" },
} },

choices: Rule = .{ .seq = &[_]Rule{
    .{ .regex = "\\[" },
    .{ .repeat = &[_]Rule{
        .{ .subrule = .expression },
    } },
    .{ .regex = "\\]" },
} },

repeats: Rule = .{ .seq = &[_]Rule{
    .{ .regex = "\\*" },
    .{ .subrule = .expression },
} },

repeats_plus: Rule = .{ .seq = &[_]Rule{
    .{ .regex = "\\+" },
    .{ .subrule = .expression },
} },

range: Rule = .{ .seq = &[_]Rule{
    .{ .regex = "\\{" },
    .{ .subrule = .char },
    .{ .regex = "\\-" },
    .{ .subrule = .char },
    .{ .regex = "\\}" },
} },

escaped_char: Rule = .{ .regex = "\\\\." },
any_char: Rule = .{ .regex = "\\." },
char: Rule = .{ .regex = "." },
