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
    const stdout = std.io.getStdOut().writer();
    try tree.dumpTo(stdout.any());
    std.log.info("rest of input: {s}", .{p.unparsed()});
}
