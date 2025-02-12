const std = @import("std");
const grammar = @import("grammar.zig");

const Rule = grammar.RuleFrom(Rules);
pub const Rules = enum {
    root,
    _test,
    test2,
    test3,
    test4,
    test5,
};

root: Rule = .{ .seq = &[_]Rule{
    .{ .repeat = &[_]Rule{
        .{ .subrule = ._test },
    } },
    .{ .subrule = .test2 },
    .{ .subrule = .test3 },
    .{ .subrule = .test4 },
    .{ .subrule = .test5 },
} },
_test: Rule = .{ .regex = "test" },
test2: Rule = .{ .regex = "(aoeu)" },
test3: Rule = .{ .regex = "*s" },
test4: Rule = .{ .regex = "[stnh]" },
test5: Rule = .{ .regex = "{az}" },
