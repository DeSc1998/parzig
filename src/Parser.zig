const std = @import("std");

const Grammar = @import("Grammar.zig");
const Parser = @This();

const Error = error{
    NotImplemented,
    RegexMatch,
    EndOfInput,
} || std.mem.Allocator.Error;

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
    root: usize,
    source: []const u8,
    nodes: []const Node,

    pub fn deinit(self: Tree) void {
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
node_buffer: std.ArrayList(Node),

/// `source` must be a managed resource from `allocator`
pub fn init(comptime grammar: Grammar, allocator: std.mem.Allocator, source: []const u8) Parser {
    return .{
        .grammar = grammar,
        .allocator = allocator,
        .source = source,
        .node_buffer = std.ArrayList(Node).init(allocator),
    };
}

/// The retruned `Tree` owns all resources allocated by `allocator`
///
/// NOTE: If the parser encounters a whitespace which is not handled
/// by the currently reachable grammar rules then it is ignored.
pub fn parse(self: *Parser) Error!Tree {
    const out = try self.parseNode("root");
    return .{
        .allocator = self.allocator,
        .root = out,
        .source = self.source,
        .nodes = try self.node_buffer.toOwnedSlice(),
    };
}

fn parseNode(self: *Parser, kind: []const u8) Error!usize {
    const rule = self.grammar.get(kind) orelse unreachable;
    const pos = self.current_position;
    var out = std.ArrayList(usize).init(self.allocator);
    for (rule.subrules()) |subrule| {
        const index = try self.parseSubrule(rule, subrule);
        try out.append(index);
    }
    const node: Node = .{
        .allocator = self.allocator,
        .kind = kind,
        .children = try out.toOwnedSlice(),
        .start_index = pos,
        .end_index = self.current_position,
    };
    const node_index = self.node_buffer.items.len;
    try self.node_buffer.append(node);
    return node_index;
}

fn parseSubrule(self: *Parser, parent: Grammar.ParsedRule, subrule: Grammar.Subrule) Error!usize {
    return switch (subrule) {
        .rule => |r| try self.parseNode(r),
        .buildin => |b| try self.parseBuildin(parent, b),
        .regex => |r| try self.parseRegex(r),
    };
}

fn parseBuildin(
    self: *Parser,
    rule_context: Grammar.ParsedRule,
    buildin: Grammar.BuildinRule,
) Error!usize {
    _ = self;
    _ = rule_context;
    _ = buildin;
    return Error.NotImplemented;
}

fn parseRegex(
    self: *Parser,
    regex: []const u8,
) Error!usize {
    _ = self;
    _ = regex;
    return Error.NotImplemented;
}
