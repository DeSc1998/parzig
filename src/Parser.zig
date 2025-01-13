const std = @import("std");

const Grammar = @import("Grammar.zig");
const Parser = @This();

const Node = struct {
    allocator: std.mem.Allocator,
    kind: []const u8,
    start_index: usize,
    end_index: usize,

    children: []const usize,

    pub fn deinit(self: Tree) void {
        self.allocator.free(self.children);
    }
};

pub const Tree = struct {
    allocator: std.mem.Allocator,
    root_children: []const usize,
    source: []const u8,
    nodes: []const Node,

    pub fn deinit(self: Tree) void {
        self.allocator.free(self.root_children);
        self.allocator.free(self.source);
        for (self.nodes) |node| {
            node.deinit();
        }
        self.allocator.free(self.nodes);
    }
};

grammar: Grammar,
allocator: std.mem.Allocator,
source: []const u8,
current_position: usize = 0,

/// `source` must be a managed resource from `allocator`
pub fn init(comptime grammar: Grammar, allocator: std.mem.Allocator, source: []const u8) Parser {
    return .{
        .grammar = grammar,
        .allocator = allocator,
        .source = source,
    };
}

/// If the parser was initialized with an outside, allocated `source` that source
/// is owned by the returned `Tree`.
///
/// NOTE: If the parser encounters a whitespace which is not handled
/// by the currently reachable grammar rules then it is ignored.
pub fn parse(self: *Parser) Tree {
    _ = self;
    @compileError("Not implemented: `fn parse` in Parser");
}
