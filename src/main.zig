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
    const source = try allocator.dupe(u8, "tes aoeusnthaoeu");
    errdefer allocator.free(source);
    var parser = Parser.init(Grammar.init(G), allocator, source);
    const tree = parser.parse() catch |err| {
        std.log.err("{}", .{err});
        try parser.printErrorContext();
        arena.deinit();
        std.process.exit(1);
    };
    defer tree.deinit();
    print_tree(tree);
    std.log.info("\nrest of input: {s}", .{tree.source[parser.current_position..]});
}

fn print_tree(tree: Parser.Tree) void {
    const root = tree.node(tree.root);
    std.log.info("{s}", .{root.kind});
    for (root.children) |child_index| {
        print_node(tree, child_index, 1);
    }
}

fn print_node(
    tree: Parser.Tree,
    node_index: usize,
    indent: usize,
) void {
    const tmp: []u8 = allocator.alloc(u8, 2 * indent) catch @panic("OOM");
    defer allocator.free(tmp);
    for (tmp) |*char| {
        char.* = ' ';
    }
    const node = tree.node(node_index);
    const chars = tree.chars(node_index);
    std.log.info("{s}{s}: {s}", .{ tmp, node.kind, chars });
    for (node.children) |child_index| {
        print_node(tree, child_index, indent + 1);
    }
}
