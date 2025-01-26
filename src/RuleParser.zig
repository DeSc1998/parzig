const std = @import("std");

const RuleLexer = @import("RuleLexer.zig");
const RuleParser = @This();

const ParserError = error{
    EndOfRule,
    RuleDoesNotExist,
    UnexpectedToken,
};

const BuildinKind = enum {
    Sequence,
    Choice,
    Repeat,
};

pub const Buildin = struct {
    kind: BuildinKind,
    subrules: [SUBRULE_BUFFER_CAPACITY]usize = undefined,
    rule_count: usize = 0,

    pub fn rules(self: Buildin) []const usize {
        return self.subrules[0..self.rule_count];
    }
};

pub const Subrule = union(enum) {
    rule: []const u8,
    buildin: Buildin,
    regex: []const u8,
};

pub const Rule = struct {
    rules: [SUBRULE_BUFFER_CAPACITY]Subrule = undefined,
    rule_count: usize = 0,
    internal: [RULE_BUFFER_CAPACITY]Subrule = undefined,

    pub fn subrules(self: Rule) []const Subrule {
        return self.rules[0..self.rule_count];
    }
};

grammar: type,
current_rule: []const u8,
lexer: RuleLexer,
subrule_buffer: [RULE_BUFFER_CAPACITY]Subrule = undefined,
subrule_buffer_count: usize = 0,

last_unexpected_token: ?RuleLexer.Token = null,
recursive_depth: usize = 0,

// TODO: chosing more reasonable sizes for these buffers
const RULE_BUFFER_CAPACITY: usize = 128;
const SUBRULE_BUFFER_CAPACITY: usize = 16;

fn push(self: *RuleParser, rule: Subrule) usize {
    if (self.subrule_buffer_count >= self.subrule_buffer.len) errorOut("exeeded internal subrule buffer", .{});
    self.subrule_buffer[self.subrule_buffer_count] = rule;
    self.subrule_buffer_count += 1;
    return self.subrule_buffer_count - 1;
}

fn write_buffer(self: RuleParser, out: *[RULE_BUFFER_CAPACITY]Subrule) void {
    @memcpy((out.*)[0..], self.subrule_buffer[0..]);
}

/// We assume `grammar` is validated by `fn isGrammar(comptime grammar: type)`
pub fn init(comptime grammar: type, comptime rule: []const u8) RuleParser {
    const tmp = grammar{};
    const field = @field(tmp, rule);
    return .{
        .grammar = grammar,
        .current_rule = rule,
        .lexer = RuleLexer.init(field),
    };
}

fn errorOut(comptime format: []const u8, comptime args: anytype) noreturn {
    var buffer: [2048]u8 = undefined;
    const msg = std.fmt.bufPrint(
        buffer[0..],
        format,
        args,
    ) catch @compileError("format error during comptime logging");
    @compileError(msg);
}

fn expect(self: *RuleParser, kind: RuleLexer.TokenKind) ParserError!RuleLexer.Token {
    if (self.lexer.data.len <= self.lexer.current_position) return ParserError.EndOfRule;

    const pos = self.lexer.current_position;
    const token = self.lexer.next() orelse return ParserError.EndOfRule;
    if (token.kind == kind) {
        return token;
    } else {
        self.lexer.reset(pos);
        self.last_unexpected_token = token;
        return ParserError.UnexpectedToken;
    }
}

fn parseBuildinSubrules(self: *RuleParser, out: *Buildin) ParserError!void {
    self.recursive_depth += 1;
    while (self.nextSubrule()) |rule| {
        if (out.subrules.len <= out.rule_count) errorOut("too many subrules in '{s}'", .{self.current_rule});
        out.subrules[out.rule_count] = self.push(rule);
        out.rule_count += 1;
    } else |err| {
        self.recursive_depth -= 1;
        if (err != ParserError.UnexpectedToken) return err;
    }
}

fn nextSubrule(self: *RuleParser) ParserError!Subrule {
    const pos = self.lexer.current_position;
    const token = self.lexer.next() orelse return ParserError.EndOfRule;
    switch (token.kind) {
        .Identifier => return if (@hasField(self.grammar, token.chars)) .{ .rule = token.chars } else ParserError.RuleDoesNotExist,
        .Regex => return .{ .regex = token.chars },
        .RepeatOp => {
            const expr = try self.nextSubrule();
            var out: Subrule = .{ .buildin = .{
                .kind = .Repeat,
            } };
            out.buildin.subrules[0] = self.push(expr);
            out.buildin.rule_count = 1;
            return out;
        },
        .OpenChoice => {
            var out: Subrule = .{ .buildin = .{
                .kind = .Choice,
            } };
            self.parseBuildinSubrules(&out.buildin) catch |err| @compileLog(err);
            _ = self.expect(.CloseChoice) catch |err| @compileLog(err);
            return out;
        },
        .OpenSequence => {
            var out: Subrule = .{ .buildin = .{
                .kind = .Sequence,
            } };
            self.parseBuildinSubrules(&out.buildin) catch |err| @compileLog(err);
            _ = self.expect(.CloseSequence) catch |err| @compileLog(err);
            return out;
        },
        else => {
            self.lexer.reset(pos);
            self.last_unexpected_token = token;
            return ParserError.UnexpectedToken;
        },
    }
}

fn validateSubrulesIndexed(self: RuleParser, rules: []const usize) void {
    for (rules) |subrule| {
        switch (self.subrule_buffer[subrule]) {
            .rule => |r| {
                if (!@hasField(self.grammar, r)) errorOut(
                    "in rule '{s}': subrule '{s}' not found in grammar",
                    .{ self.current_rule, r },
                );
            },
            .buildin => |b| {
                self.validateSubrulesIndexed(b.rules());
            },
            else => {},
        }
    }
}

fn validateSubrules(self: RuleParser, rules: []const Subrule) void {
    for (rules) |subrule| {
        switch (subrule) {
            .rule => |r| {
                if (!@hasField(self.grammar, r)) errorOut(
                    "in rule '{s}': subrule '{s}' not found in grammar",
                    .{ self.current_rule, r },
                );
            },
            .buildin => |b| {
                self.validateSubrulesIndexed(b.rules());
            },
            else => {},
        }
    }
}

pub fn parse(self: *RuleParser) ParserError!Rule {
    var out = Rule{};
    while (self.nextSubrule()) |rule| {
        if (out.rules.len <= out.rule_count) errorOut("too many subrules in '{s}'", .{self.current_rule});
        out.rules[out.rule_count] = rule;
        out.rule_count += 1;
    } else |err| {
        if (err == ParserError.EndOfRule and out.rule_count != 0) {
            validateSubrules(self.*, out.subrules());
            self.write_buffer(&out.internal);
            return out;
        }
        if (err == ParserError.UnexpectedToken) {
            const token = self.last_unexpected_token orelse unreachable;
            errorOut(
                "in rule '{s}': unexpected token kind {s} ('{s}')",
                .{ self.current_rule, @tagName(token.kind), token.chars },
            );
        }
        return null;
    }
    unreachable;
}
