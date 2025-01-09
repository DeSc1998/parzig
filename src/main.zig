const std = @import("std");

const RuleParser = @import("RuleParser.zig");
const Grammar = @import("Grammar.zig");

const Rule = Grammar.Rule;

const G = struct {
    root: Rule = "_test",
    test_rule: Rule = "_test",
    _test: Rule = "'test'",
};

pub fn main() !void {
    const g = Grammar.init(G);
    std.log.info("{}", .{g.parsed_rules.keys().len});
    for (g.parsed_rules.keys()) |key| {
        std.log.info("{s}", .{key});
    }
}
