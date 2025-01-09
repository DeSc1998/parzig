const std = @import("std");

const RuleLexer = @import("RuleLexer.zig");
const RuleParser = @This();

const ParserError = error{
    EndOfRule,
    UnexpectedToken,
};

const macros = .{
    "choice",
    "prec",
};

const Macro = struct {
    name: []const u8,
    subrules: [16]usize = undefined,
    rule_count: usize = 0,
};

const Subrule = union(enum) {
    rule: []const u8,
    macro: Macro,
    regex: []const u8,
};

const Rule = struct {
    rules: [32]Subrule = undefined,
    rule_count: usize = 0,
    internal: [512]Subrule = undefined,

    pub fn subrules(self: Rule) []const Subrule {
        return self.rules[0..self.rule_count];
    }
};

grammar: type,
current_rule: []const u8,
lexer: RuleLexer,

var subrule_buffer: [512]Subrule = undefined;
var subrule_buffer_count: usize = 0;

fn push(rule: Subrule) usize {
    subrule_buffer[subrule_buffer_count] = rule;
    subrule_buffer_count += 1;
    return subrule_buffer_count - 1;
}

fn write_buffer(out: *[512]Subrule) void {
    @memcpy(out.*, subrule_buffer);
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

fn expect(self: *RuleParser, kind: RuleLexer.TokenKind) ParserError!RuleLexer.TokenKind {
    if (self.lexer.data.len <= self.lexer.current_position) return ParserError.EndOfRule;

    const pos = self.lexer.current_position;
    const token = self.lexer.next() orelse return ParserError.EndOfRule;
    if (token.kind == kind) {
        return token;
    } else {
        self.lexer.reset(pos);
        return ParserError.UnexpectedToken;
    }
}

fn parseMacroSubrules(self: *RuleParser, out: *Macro) ParserError!void {
    while (self.nextSubrule()) |rule| {
        if (out.subrules.len <= out.rule_count) errorOut("too many subrules in '{s}'", .{self.current_rule});
        self.expect(.Comma) catch {
            try self.expect(.CloseParen);
            out.subrules[out.rule_count] = push(rule);
            out.rule_count += 1;
            return;
        };
        out.subrules[out.rule_count] = push(rule);
        out.rule_count += 1;
    } else |err| {
        return err;
    }
}

fn nextSubrule(self: *RuleParser) ParserError!Subrule {
    const token = self.lexer.next() orelse return ParserError.EndOfRule;
    switch (token.kind) {
        .Identifier => {
            _ = self.expect(.OpenParen) catch return .{
                .rule = token.chars,
            };
            var macro = .{ .macro = .{
                .name = token.chars,
            } };
            try self.parseMacroSubrules(&macro);
            return macro;
        },
        .Regex => return .{ .regex = token.chars },
        else => errorOut(
            "in rule '{s}': unexpected token kind {s} ('{s}')",
            .{ self.current_rule, @tagName(token.kind), token.chars },
        ),
    }
}

fn isAny(macro: []const u8, internals: []const []const u8) bool {
    for (internals) |internal| {
        if (std.mem.eql(u8, macro, internal)) return true;
    }
    return false;
}

fn validateSubrulesIndexed(self: RuleParser, rules: []usize) void {
    for (rules) |subrule| {
        switch (subrule_buffer[subrule]) {
            .rule => |r| {
                if (!@hasField(self.grammar, r)) errorOut(
                    "in rule '{s}': subrule '{s}' not found in grammar",
                    .{ self.current_rule, r },
                );
            },
            .macro => |m| {
                if (!isAny(m.name, macros)) errorOut(
                    "in rule '{s}': invalid macro '{s}'",
                    .{ self.current_rule, m.name },
                );
                validateSubrulesIndexed(self, m.subrules[0..m.rule_count]);
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
            .macro => |m| {
                if (!isAny(m.name, macros)) errorOut(
                    "in rule '{s}': invalid macro '{s}'",
                    .{ self.current_rule, m.name },
                );
                validateSubrulesIndexed(self, m.subrules[0..m.rule_count]);
            },
            else => {},
        }
    }
}

pub fn parse(self: *RuleParser) ?Rule {
    var out = Rule{};
    while (self.nextSubrule()) |rule| {
        if (out.rules.len <= out.rule_count) errorOut("too many subrules in '{s}'", .{self.current_rule});
        out.rules[out.rule_count] = rule;
        out.rule_count += 1;
    } else |err| {
        if (err == ParserError.EndOfRule and out.rule_count != 0) {
            validateSubrules(self.*, out.subrules());
            return out;
        }
        return null;
    }
    unreachable;
}
