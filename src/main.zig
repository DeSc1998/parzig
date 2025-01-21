const std = @import("std");

// const RuleParser = @import("RuleParser.zig");
const Parser = @import("Parser.zig");
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

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

pub fn main() !void {
    const source = try allocator.dupe(u8, "test aoeusnthaoeu");
    errdefer allocator.free(source);
    var parser = Parser.init(Grammar.init(G), allocator, source);
    const tree = try parser.parse();
    defer tree.deinit();
    print_tree(tree);
    std.log.info("\nrest of input: {s}", .{tree.source[parser.current_position..]});
}

fn print_tree(tree: Parser.Tree) void {
    const root = tree.nodes[tree.root];
    std.log.info("{s}", .{root.kind});
    for (root.children) |child_index| {
        const child = tree.nodes[child_index];
        print_node(tree, child, 1);
    }
}

fn print_node(
    tree: Parser.Tree,
    node: Parser.Node,
    indent: usize,
) void {
    const tmp: []u8 = allocator.alloc(u8, 2 * indent) catch @panic("OOM");
    defer allocator.free(tmp);
    for (tmp) |*char| {
        char.* = ' ';
    }
    std.log.info("{s}{s}:", .{ tmp, node.kind });
    const chars = tree.source[node.start_index..node.end_index];
    std.log.info("{s}chars: {s}", .{ tmp, chars });
    for (node.children) |child_index| {
        const child = tree.nodes[child_index];
        print_node(tree, child, indent + 1);
    }
}
