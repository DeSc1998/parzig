const std = @import("std");
const parzig = @import("parzig");

const Rule = parzig.RuleFrom(Rules);
pub const Rules = enum {
    root,
    _test,
    test2,
    test3,
    test4,
    test5,
};

pub fn config() parzig.Config {
    return .{
        .ignore_whitespace = true,
    };
}

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
test5: Rule = .{ .regex = "{a-z}" },
