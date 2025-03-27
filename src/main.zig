const std = @import("std");

const parzig = @import("parzig");

const G = @import("TestGrammar.zig");
const TestParser = parzig.ParserFrom(G);

const M = @import("MathGrammar.zig");
const MathParser = parzig.ParserFrom(M);

const R = @import("InnerRegexGrammar.zig");
const RegexParser = parzig.ParserFrom(R);

const Rec = @import("RecursiveGrammar.zig");
const Recursive = parzig.ParserFrom(Rec);

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

pub fn main() !void {
    try testExample();
    try mathExample();
    try innerRegexExample();
    // try recursiveExample();
}

fn testExample() !void {
    std.log.info("running test example", .{});
    const source2 = try allocator.dupe(u8, " test test test aoeussssnthaoeu");
    errdefer allocator.free(source2);
    var p2 = TestParser.init(allocator, source2);
    const tree = p2.parse() catch |err| {
        std.log.err("{}", .{err});
        try p2.printErrorContext();
        std.log.info("\nrest of input: {s}", .{p2.unparsed()});
        arena.deinit();
        std.process.exit(1);
    };
    defer tree.deinit();
    try tree.dumpTo(std.io.getStdOut().writer().any());

    std.log.info("test example: testing access via enum", .{});
    const root_node = tree.node(tree.root);
    const seq_node = tree.node(root_node.children[0]);
    std.log.info("first node in root: {}", .{seq_node.kind});
    const repeat_node = tree.node(seq_node.children[0]);
    std.log.info("first node in seqence: {s}", .{@tagName(repeat_node.kind)});
    const _test_node = tree.node(repeat_node.children[0]);
    std.debug.assert(_test_node.kind == ._test);

    std.log.info("rest of input: {s}", .{p2.unparsed()});
}

fn mathExample() !void {
    std.log.info("running math expression example", .{});
    const source = try allocator.dupe(u8, "15 + (7 - (0 * 23) ^ 4)");
    errdefer allocator.free(source);
    var p = MathParser.init(allocator, source);
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

fn innerRegexExample() !void {
    std.log.info("running inner regex example", .{});
    // const source = try allocator.dupe(u8, "test *[(aoeu)1234{a-z}]");
    const source = try allocator.dupe(u8, "test   [1234{a-z}]*(aoeu) ");
    errdefer allocator.free(source);
    std.log.info("source is: '{s}'", .{source});
    var p = RegexParser.init(allocator, source);
    // var p = RegexParser.initDebug(allocator, source);
    const tree = p.parse() catch |err| {
        std.log.err("{}", .{err});
        try p.printErrorContext();
        arena.deinit();
        std.process.exit(1);
    };
    defer tree.deinit();
    const stdout = std.io.getStdOut().writer();
    try tree.dumpTo(stdout.any());
    std.log.info("node count: {}", .{tree.nodes.len});
    // for (0..tree.nodes.len) |index| {
    //     try tree.dumpNodeTo(index, stdout.any(), 2);
    // }
    std.log.info("rest of input: {s}", .{p.unparsed()});
}

fn recursiveExample() !void {
    std.log.info("running recursive example", .{});
    const p = Recursive.init(allocator, "");
    _ = p;
}
