const std = @import("std");

// const RuleParser = @import("RuleParser.zig");
const parser = @import("Parser.zig");

// const G = @import("TestGrammar.zig");
const H = @import("RecursiveTestGrammar.zig");
// const Parser = parser.Parser(G);
const RecParser = parser.Parser(H);

const G = @import("MathGrammar.zig");
const Parser = parser.Parser(G);

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

// pub fn main() !void {
//     const source = try allocator.dupe(u8, " test test test aoeussssnthaoeu");
//     errdefer allocator.free(source);
//     var p = Parser.init(allocator, source);
//     const tree = p.parse() catch |err| {
//         std.log.err("{}", .{err});
//         try p.printErrorContext();
//         arena.deinit();
//         std.process.exit(1);
//     };
//     defer tree.deinit();
//     print_tree(tree);
//     std.log.info("\nrest of input: {s}", .{p.unparsed()});
// }

// pub fn main() !void {
//     const source2 = try allocator.dupe(u8, " test test test aoeussssnthaoeu");
//     errdefer allocator.free(source2);
//     var p2 = RecParser.init(allocator, source2);
//     const tree2 = p2.parse() catch |err| {
//         std.log.err("{}", .{err});
//         try p2.printErrorContext();
//         std.log.info("\nrest of input: {s}", .{p2.unparsed()});
//         arena.deinit();
//         std.process.exit(1);
//     };
//     defer tree2.deinit();
//     print_tree(tree2);
//     std.log.info("\nrest of input: {s}", .{p2.unparsed()});
// }

pub fn main() !void {
    const source = try allocator.dupe(u8, "15 + (7 - (0 * 23) ^ 4)");
    errdefer allocator.free(source);
    var p = Parser.init(allocator, source);
    const tree = p.parse() catch |err| {
        std.log.err("{}", .{err});
        try p.printErrorContext();
        arena.deinit();
        std.process.exit(1);
    };
    defer tree.deinit();
    print_tree(tree);
    std.log.info("\nrest of input: {s}", .{p.unparsed()});
}

fn print_tree(tree: parser.Tree) void {
    const root = tree.node(tree.root);
    std.log.info("{s}", .{root.kind});
    for (root.children) |child_index| {
        print_node(tree, child_index, 1);
    }
}

fn print_node(
    tree: parser.Tree,
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
    if (isBuildinNode(node.kind)) {
        std.log.info("{s}{s}", .{ tmp, node.kind });
    } else {
        std.log.info("{s}{s}: {s}", .{ tmp, node.kind, chars });
    }
    for (node.children) |child_index| {
        print_node(tree, child_index, indent + 1);
    }
}

fn isBuildinNode(chars: []const u8) bool {
    const types: []const []const u8 = &.{ "repeat", "sequence", "choice" };
    for (types) |t| {
        if (std.mem.eql(u8, chars, t)) return true;
    }
    return false;
}
