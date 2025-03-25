const std = @import("std");
const parzig = @import("parzig");

const Rule = parzig.RuleFrom(Rules);
pub const Rules = enum {
    root,
    _test,
};

pub fn ignore_whitespace() void {}

root: Rule = .{ .subrule = ._test },
_test: Rule = .{ .subrule = .root },
