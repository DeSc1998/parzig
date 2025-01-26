const std = @import("std");

const Grammar = @import("Grammar.zig");
const regex = @import("regex.zig");
const Parser = @This();

const Error = error{
    NotImplemented,
    RegexMatch,
    EndOfInput,
} || std.mem.Allocator.Error;

pub const Node = struct {
    allocator: std.mem.Allocator,
    kind: []const u8,
    start_index: usize,
    end_index: usize,

    children: []const usize = ([0]usize{})[0..],

    pub fn deinit(self: Node) void {
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
        for (self.nodes) |n| {
            n.deinit();
        }
        self.allocator.free(self.nodes);
    }

    pub fn node(self: Tree, node_index: usize) Node {
        return self.nodes[node_index];
    }

    pub fn nodeKind(self: Tree, node_index: usize) []const u8 {
        return self.nodes[node_index].kind;
    }

    pub fn children(self: Tree, node_index: usize) []const usize {
        return self.nodes[node_index].children;
    }

    pub fn chars(self: Tree, node_index: usize) []const u8 {
        const n = self.nodes[node_index];
        return self.source[n.start_index..n.end_index];
    }
};

const ErrorContext = struct {
    message: []const u8,
    node: []const u8,
    source_offset: usize,
    char_count: usize,
    regex_expr: []const u8 = "",
    regex_offset: usize = 0,
};

grammar: Grammar,
allocator: std.mem.Allocator,
source: []const u8,
current_position: usize = 0,
node_buffer: std.ArrayList(Node),

var context: ?ErrorContext = null;

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
    const out = self.parseNode("root") catch |err| {
        return err;
    };
    return .{
        .allocator = self.allocator,
        .root = out,
        .source = self.source,
        .nodes = try self.node_buffer.toOwnedSlice(),
    };
}

pub fn unparsed(self: Parser) []const u8 {
    return self.source[self.current_position..];
}

pub fn printErrorContext(self: Parser) !void {
    if (context) |c| {
        const tmp_node: Node = .{
            .allocator = self.allocator,
            .kind = "regex",
            .start_index = c.source_offset,
            .end_index = c.source_offset + c.char_count,
        };
        std.log.err("failed to parse in node '{s}': {s}", .{ c.node, c.message });
        const stderr = std.io.getStdErr().writer();
        const tty_config = std.io.tty.detectConfig(std.io.getStdErr());
        if (c.regex_expr.len != 0) {
            _ = try stderr.write("       tried to match regex: '");
            try std.io.tty.Config.setColor(tty_config, stderr, .green);
            _ = try stderr.write(c.regex_expr[0..c.regex_offset]);
            try std.io.tty.Config.setColor(tty_config, stderr, .red);
            _ = try stderr.write(c.regex_expr[c.regex_offset..]);
            try std.io.tty.Config.setColor(tty_config, stderr, .reset);
            _ = try stderr.write("'\n");
        }
        try self.printContext(stderr.any(), tmp_node);
    }
}

fn parseNode(self: *Parser, kind: []const u8) Error!usize {
    const rule = self.grammar.get(kind) orelse unreachable;
    const pos = self.current_position;
    var out = std.ArrayList(usize).init(self.allocator);
    for (rule.subrules()) |subrule| {
        const index = self.parseSubrule(rule, subrule) catch |err| {
            if (context) |*c| {
                if (c.node.len == 0)
                    c.node = kind;
            }
            return err;
        };
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
        .rule => |r| self.parseNode(r),
        .buildin => |b| self.parseBuildin(parent, b),
        .regex => |r| self.parseRegex(r),
    } catch |err| {
        return err;
    };
}

fn parseBuildin(
    self: *Parser,
    rule_context: Grammar.ParsedRule,
    buildin: Grammar.BuildinRule,
) Error!usize {
    const pos = self.current_position;
    switch (buildin.kind) {
        .Repeat => {
            const rule_index = (buildin.rules())[0];
            const rule = rule_context.internal[rule_index];
            var buffer = std.ArrayList(usize).init(self.allocator);
            while (self.parseSubrule(rule_context, rule)) |index| {
                try buffer.append(index);
            } else |err| {
                switch (err) {
                    Error.EndOfInput, Error.RegexMatch => {
                        const repeat_node: Node = .{
                            .kind = "repeat",
                            .allocator = self.allocator,
                            .children = try buffer.toOwnedSlice(),
                            .start_index = pos,
                            .end_index = self.current_position,
                        };
                        const repeat_index = self.node_buffer.items.len;
                        try self.node_buffer.append(repeat_node);
                        return repeat_index;
                    },
                    else => return err,
                }
            }
        },
        .Sequence => {
            var buffer = std.ArrayList(usize).init(self.allocator);
            for (buildin.rules()) |rule_index| {
                const rule = rule_context.internal[rule_index];
                const parsed_index = try self.parseSubrule(rule_context, rule);
                try buffer.append(parsed_index);
            }
            const seq_node: Node = .{
                .kind = "sequence",
                .allocator = self.allocator,
                .children = try buffer.toOwnedSlice(),
                .start_index = pos,
                .end_index = self.current_position,
            };
            const index = self.node_buffer.items.len;
            try self.node_buffer.append(seq_node);
            return index;
        },
        .Choice => {
            var buffer = std.ArrayList(usize).init(self.allocator);
            for (buildin.rules()) |rule_index| {
                const rule = rule_context.internal[rule_index];
                const parsed_index = self.parseSubrule(rule_context, rule) catch continue;
                try buffer.append(parsed_index);
                const seq_node: Node = .{
                    .kind = "choice",
                    .allocator = self.allocator,
                    .children = try buffer.toOwnedSlice(),
                    .start_index = pos,
                    .end_index = self.current_position,
                };
                const index = self.node_buffer.items.len;
                try self.node_buffer.append(seq_node);
                return index;
            }
            return Error.RegexMatch;
        },
    }
}

fn parseRegex(
    self: *Parser,
    expr: []const u8,
) Error!usize {
    switch (regex.match(expr, self.source[self.current_position..])) {
        .succes => |out| {
            const node: Node = .{
                .kind = "regex",
                .allocator = self.allocator,
                .start_index = self.current_position,
                .end_index = self.current_position + out.len,
            };
            self.current_position += out.len;
            const index = self.node_buffer.items.len;
            try self.node_buffer.append(node);
            return index;
        },
        .failure => |f| {
            context = .{
                .message = f.message,
                .node = "",
                .source_offset = self.current_position,
                .char_count = f.source_offset,
                .regex_expr = expr,
                .regex_offset = f.regex_offset - 1,
            };
            return Error.RegexMatch;
        },
    }
    unreachable;
}

fn nextLine(self: Parser, node: Node) ?[]const u8 {
    var pos = node.start_index;
    while (pos < self.source.len) : (pos += 1) {
        if (self.source[pos] == '\n') {
            break;
        }
    }

    if (pos == self.source.len)
        return null;

    const line_begin = pos + 1;
    var line_end = pos + 1;

    while (line_end < self.source.len) : (line_end += 1) {
        if (self.source[line_end] == '\n')
            break;
    }
    return self.source[line_begin..line_end];
}

const LineContext = struct {
    chars: []const u8,
    token_offset: usize,
};

fn currentLine(self: Parser, node: Node) LineContext {
    var line_begin = node.start_index;
    var line_end = node.start_index;

    while (line_begin > 0) : (line_begin -= 1) {
        if (self.source[line_begin] == '\n') {
            line_begin += 1;
            break;
        }
    }

    while (line_end < self.source.len) : (line_end += 1) {
        if (self.source[line_end] == '\n')
            break;
    }
    line_begin = if (line_begin > line_end) line_end else line_begin;
    const tmp = self.source[line_begin..line_end];
    return .{
        .chars = tmp,
        .token_offset = if (tmp.len == 0) 0 else node.start_index - line_begin,
    };
}

fn previousLine(self: Parser, node: Node) ?[]const u8 {
    var pos = node.start_index;

    while (pos > 0) : (pos -= 1) {
        if (self.source[pos] == '\n') {
            break;
        }
    }

    if (pos == 0)
        return null;

    var line_begin = pos - 1;
    const line_end = pos;
    while (line_begin > 0) : (line_begin -= 1) {
        if (self.source[line_begin] == '\n') {
            line_begin += 1;
            break;
        }
    }

    return self.source[line_begin..line_end];
}

pub fn printContext(self: Parser, out: std.io.AnyWriter, node: Node) !void {
    const tty_config = std.io.tty.detectConfig(std.io.getStdErr());
    const line = std.mem.count(u8, self.source[0..node.start_index], "\n") + 1;
    if (previousLine(self, node)) |previous| {
        try out.print("{d:5}:{s}\n", .{ line - 1, previous });
    }
    const ctxt = currentLine(self, node);
    const line_chars = ctxt.chars;

    try out.print("{d:5}:{s}", .{ line, line_chars[0..ctxt.token_offset] });
    if (line_chars.len != 0) {
        const node_len = node.end_index - node.start_index;
        try std.io.tty.Config.setColor(tty_config, out, .red);
        try std.io.tty.Config.setColor(tty_config, out, .bold);
        try out.print("{s}", .{line_chars[ctxt.token_offset .. ctxt.token_offset + node_len]});
        try std.io.tty.Config.setColor(tty_config, out, .reset);
        try out.print("{s}\n", .{line_chars[ctxt.token_offset + node_len ..]});
    } else {
        _ = try out.write("\n");
    }

    if (nextLine(self, node)) |next| {
        try out.print("{d:5}:{s}\n", .{ line + 1, next });
    }
}
