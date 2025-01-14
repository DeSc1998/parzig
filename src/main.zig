const std = @import("std");

const RuleParser = @import("RuleParser.zig");
const Grammar = @import("Grammar.zig");

const Rule = Grammar.Rule;

const G = struct {
    root: Rule = "_test",
    test_rule: Rule = "_test",
    _test: Rule = "'test'",
    repeat: Rule = "_test *test_rule",
    choice: Rule = "_test [test_rule test_rule]",
    seq: Rule = "_test (test_rule test_rule)",
};

pub fn main() !void {
    const g = Grammar.init(G);
    std.log.info("{}", .{g.parsed_rules.keys().len});
    for (g.parsed_rules.keys()) |key| {
        std.log.info("{s}", .{key});
        const tmp = g.parsed_rules.get(key) orelse unreachable;
        for (tmp.subrules()) |rule| {
            switch (rule) {
                .rule => |r| {
                    std.log.info("  Rule: {s}", .{r});
                },
                .regex => |r| {
                    std.log.info("  Regex: '{s}'", .{r});
                },
                .buildin => |b| {
                    std.log.info("  Buildin({s}): {any}", .{
                        @tagName(b.kind),
                        b.subrules[0..b.rule_count],
                    });
                },
            }
        }
    }
}
