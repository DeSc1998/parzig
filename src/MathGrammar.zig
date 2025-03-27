const std = @import("std");
const parzig = @import("parzig");

const Rule = parzig.RuleFrom(Rules);
pub const Rules = enum {
    root,
    expression,
    value,
    number,
    identifier,
    operator,
};

pub fn config() parzig.Config {
    return .{
        .ignore_whitespace = true,
    };
}

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

operator: Rule = .{ .regex = "[\\-/\\*\\+\\^]" },

value: Rule = .{ .choice = &[_]Rule{
    .{ .subrule = .identifier },
    .{ .subrule = .number },
} },

number: Rule = .{ .regex = "+{0-9}" },
identifier: Rule = .{ .regex = "+[_{a-z}{A-Z}]" },
