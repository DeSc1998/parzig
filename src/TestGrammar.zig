const std = @import("std");
const grammar = @import("grammar.zig");

const Rule = grammar.RuleFrom(Rules);
pub const Rules = enum {
    root,
    _test,
};

root: Rule = .{ .repeat = &[_]Rule{
    .{ .subrule = ._test },
} },
_test: Rule = .{ .regex = "test" },
