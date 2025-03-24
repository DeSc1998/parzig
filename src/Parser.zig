const std = @import("std");

const gram = @import("grammar.zig");
const regex = @import("regex.zig");

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

    pub fn dumpTo(self: Tree, out: std.io.AnyWriter) !void {
        const root = self.nodes[self.root];
        for (root.children) |child| {
            try self.dumpNodeTo(child, out, 1);
        }
    }
    pub fn dumpNodeTo(self: Tree, index: usize, out: std.io.AnyWriter, indent_level: usize) !void {
        var buffer: [512]u8 = undefined;
        const indent_chars = try indent(&buffer, 2, indent_level);
        const n = self.node(index);
        const cs = self.chars(index);
        if (isBuildinNode(n.kind)) {
            try out.print("{s}{s}\n", .{ indent_chars, n.kind });
        } else {
            try out.print("{s}{s}: {s}\n", .{ indent_chars, n.kind, cs });
        }
        for (n.children) |child| {
            try self.dumpNodeTo(child, out, indent_level + 1);
        }
    }

    fn indent(out: []u8, space_count: usize, level: usize) ![]const u8 {
        var tmp = level;
        if (level * space_count >= out.len) return error.NotEnoughSpaceInTmpBuffer;

        while (tmp > 0) {
            for (0..space_count) |index| {
                out[tmp * space_count + index] = ' ';
            }
            tmp -= 1;
        }
        return out[0 .. level * space_count];
    }

    fn isBuildinNode(cs: []const u8) bool {
        const types: []const []const u8 = &.{ "repeat", "sequence" };
        for (types) |t| {
            if (std.mem.eql(u8, cs, t)) return true;
        }
        return false;
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

pub fn Parser(comptime Grammar: type) type {
    return struct {
        const RuleType = gram.RuleType(Grammar);
        const RuleEnum: type = gram.RulesEnum(Grammar);

        const Self = Parser(Grammar);

        allocator: std.mem.Allocator,
        source: []const u8,
        rule_map: gram.StringMap(RuleType),
        current_position: usize = 0,
        node_buffer: std.ArrayList(Node),
        with_debug: bool = false,

        var context: ?ErrorContext = null;

        /// `source` must be a managed resource from `allocator`
        pub fn init(allocator: std.mem.Allocator, source: []const u8) Self {
            return .{
                .allocator = allocator,
                .source = source,
                .node_buffer = std.ArrayList(Node).init(allocator),
                .rule_map = comptime gram.RuleMap(Grammar),
            };
        }

        pub fn initDebug(allocator: std.mem.Allocator, source: []const u8) Self {
            return .{
                .allocator = allocator,
                .source = source,
                .node_buffer = std.ArrayList(Node).init(allocator),
                .rule_map = comptime gram.RuleMap(Grammar),
                .with_debug = true,
            };
        }

        /// The retruned `Tree` owns all resources allocated by `allocator`
        ///
        /// NOTE: If the parser encounters a whitespace which is not handled
        /// by the currently reachable grammar rules then it is ignored.
        pub fn parse(self: *Self) Error!Tree {
            const out = try self.parseNode("root");
            return .{
                .allocator = self.allocator,
                .root = out,
                .source = self.source,
                .nodes = try self.node_buffer.toOwnedSlice(),
            };
        }

        pub fn unparsed(self: Self) []const u8 {
            return self.source[self.current_position..];
        }

        pub fn printErrorContext(self: Self) !void {
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

        fn parseNode(self: *Self, kind: []const u8) Error!usize {
            const rule = self.rule_map.get(kind) orelse unreachable;
            const pos = self.current_position;
            var out = std.ArrayList(usize).init(self.allocator);
            const index = switch (rule) {
                .regex => |expr| self.parseRegex(expr),
                .subrule => |subrule| self.parseNode(@tagName(subrule)),
                .choice, .seq, .repeat => self.parseBuildin(rule),
            } catch |err| {
                if (context) |*c| {
                    if (c.node.len == 0)
                        c.node = kind;
                }
                return err;
            };
            try out.append(index);
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

        fn parseSubrule(self: *Self, subrule: Self.RuleType) Error!usize {
            return switch (subrule) {
                .subrule => |r| self.parseNode(@tagName(r)),
                .seq, .choice, .repeat => self.parseBuildin(subrule),
                .regex => |r| self.parseRegex(r),
            };
        }

        fn parseBuildin(self: *Self, buildin: Self.RuleType) Error!usize {
            const pos = self.current_position;
            switch (buildin) {
                .repeat => |rules| {
                    const rule = rules[0];
                    var buffer = std.ArrayList(usize).init(self.allocator);
                    while (self.parseSubrule(rule)) |index| {
                        try buffer.append(index);
                        for (rules[1..]) |r| {
                            const tmp_index = try self.parseSubrule(r);
                            try buffer.append(tmp_index);
                        }
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
                .seq => |rules| {
                    var buffer = std.ArrayList(usize).init(self.allocator);
                    for (rules) |rule| {
                        try buffer.append(try self.parseSubrule(rule));
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
                .choice => |rules| {
                    for (rules) |rule| {
                        return self.parseSubrule(rule) catch continue;
                    }
                    return Error.RegexMatch;
                },
                else => unreachable,
            }
        }

        fn parseRegex(self: *Self, expr: []const u8) Error!usize {
            switch (regex.match(expr, self.source[self.current_position..])) {
                .succes => |out| {
                    if (self.with_debug) {
                        std.log.info("matched expression '{s}'", .{expr});
                        std.log.info("result is '{s}'", .{out.match});
                    }
                    const node: Node = .{
                        .kind = "regex",
                        .allocator = self.allocator,
                        .start_index = self.current_position + out.consumed - out.match.len,
                        .end_index = self.current_position + out.consumed,
                    };
                    self.current_position += out.consumed;
                    const index = self.node_buffer.items.len;
                    try self.node_buffer.append(node);
                    return index;
                },
                .failure => |f| {
                    if (self.with_debug) {
                        std.log.info("current source offset: {}", .{self.current_position});
                        std.log.info("regex was: '{s}'", .{expr});
                        std.log.info("message was: '{s}'", .{f.message});
                    }
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

        fn nextLine(self: Self, node: Node) ?[]const u8 {
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

        fn currentLine(self: Self, node: Node) LineContext {
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

        fn previousLine(self: Self, node: Node) ?[]const u8 {
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

        pub fn printContext(self: Self, out: std.io.AnyWriter, node: Node) !void {
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
    };
}
