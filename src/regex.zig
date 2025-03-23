const std = @import("std");

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

const RegexMatch = union(enum) {
    succes: []const u8,
    failure: struct {
        source_offset: usize,
        regex_offset: usize,
        message: []const u8,
    },
};

pub fn match(regex: []const u8, source: []const u8) RegexMatch {
    defer if (!arena.reset(.retain_capacity)) {
        _ = arena.reset(.free_all);
    };
    var parser = RegexParser.init(regex);
    const chars = parser.consume(source) catch |err| {
        return RegexMatch{ .failure = .{
            .source_offset = parser.current_index,
            .regex_offset = parser.lexer.current_position,
            .message = errorToMessage(err),
        } };
    };
    return RegexMatch{ .succes = chars };
}

fn errorToMessage(err: Error) []const u8 {
    return switch (err) {
        Error.CharacterMissmatch => "failed to match character",
        Error.CharacterMissmatchChoice => "failed to match character in choice",
        Error.InvalidEscapedChar => "invalid escaped character in regex",
        Error.UnexpectedRegexToken => "unexpected character in regex",
        Error.EndOfInput => "unexpected end of input",
        Error.EndOfRegex => "unexpected end of regex",
        Error.RegexParsingFailed => "invalid regex",
        Error.NotImplemented => "reach a not implemented path",
        Error.OutOfMemory => "out of memory",
    };
}

const TokenKind = enum {
    Char,
    EscapedChar,

    OpenSequence,
    CloseSequence,
    OpenRange,
    RangeMinus,
    CloseRange,
    OpenChoice,
    CloseChoice,
    RepeatOp,
    RepeatPlusOp,
};

const Token = struct {
    kind: TokenKind,
    char: u8,
};

const RegexExpression = union(enum) {
    char: u8,
    range: struct { start: u8, end: u8 },
    seq: []const RegexExpression,
    choice: []const RegexExpression,
    repeat: *const RegexExpression,
    repeat_plus: *const RegexExpression,
};

const Error = error{
    CharacterMissmatch,
    CharacterMissmatchChoice,
    InvalidEscapedChar,
    EndOfInput,
    EndOfRegex,
    RegexParsingFailed,
    UnexpectedRegexToken,
    NotImplemented,
} || std.mem.Allocator.Error;

const RegexParser = struct {
    current_index: usize = 0,
    lexer: RegexLexer,

    fn init(data: []const u8) RegexParser {
        return .{ .lexer = RegexLexer.init(data) };
    }

    fn doNotExpect(self: *RegexParser, kind: TokenKind) Error!TokenKind {
        const pos = self.lexer.current_position;
        defer self.lexer.current_position = pos;
        const current = self.lexer.next() orelse return Error.EndOfRegex;
        if (current.kind != kind) {
            return current.kind;
        } else {
            return Error.UnexpectedRegexToken;
        }
    }

    fn expect(self: *RegexParser, kind: TokenKind) Error!Token {
        const pos = self.lexer.current_position;
        const current = self.lexer.next() orelse return Error.EndOfRegex;
        if (current.kind == kind) {
            return current;
        } else {
            self.lexer.current_position = pos;
            return Error.UnexpectedRegexToken;
        }
    }

    fn parse(self: *RegexParser) Error!RegexExpression {
        const token = self.lexer.next() orelse return Error.EndOfRegex;
        switch (token.kind) {
            .Char => {
                return .{ .char = token.char };
            },
            .EscapedChar => {
                const tmp = self.lexer.next() orelse return Error.EndOfRegex;
                return .{ .char = tmp.char };
            },
            .OpenSequence => {
                const out = try self.parseSequence();
                _ = try self.expect(.CloseSequence);
                return out;
            },
            .OpenChoice => {
                const out = try self.parseChoice();
                _ = try self.expect(.CloseChoice);
                return out;
            },
            .OpenRange => {
                const start = try self.expect(.Char);
                _ = try self.expect(.RangeMinus);
                const end = try self.expect(.Char);
                _ = try self.expect(.CloseRange);
                return .{ .range = .{ .start = start.char, .end = end.char } };
            },
            .RepeatOp => {
                const tmp = try allocator.create(RegexExpression);
                tmp.* = try self.parse();
                return .{ .repeat = tmp };
            },
            .RepeatPlusOp => {
                const tmp = try allocator.create(RegexExpression);
                tmp.* = try self.parse();
                return .{ .repeat_plus = tmp };
            },
            else => return Error.UnexpectedRegexToken,
        }
    }

    fn parseSequence(self: *RegexParser) Error!RegexExpression {
        var array = std.ArrayList(RegexExpression).init(allocator);
        while (doNotExpect(self, .CloseSequence)) |_| {
            try array.append(try self.parse());
        } else |err| {
            if (err != Error.UnexpectedRegexToken) return err;
            return .{ .seq = try array.toOwnedSlice() };
        }
    }

    fn parseChoice(self: *RegexParser) Error!RegexExpression {
        var array = std.ArrayList(RegexExpression).init(allocator);
        while (doNotExpect(self, .CloseChoice)) |_| {
            try array.append(try self.parse());
        } else |err| {
            if (err != Error.UnexpectedRegexToken) return err;
            return .{ .choice = try array.toOwnedSlice() };
        }
    }

    fn consume(self: *RegexParser, source: []const u8) Error![]const u8 {
        self.skipWhitespace(source);
        while (self.parse()) |expr| {
            const consumed = try self.consumeExpr(expr, source[self.current_index..]);
            self.current_index += consumed;
            if (self.current_index < source.len) std.log.info("source = {s}", .{source[self.current_index..]});
        } else |err| if (err != Error.EndOfRegex) return err;
        return source[0..self.current_index];
    }

    fn matchesWhitespace(expr: RegexExpression) bool {
        return switch (expr) {
            .char => |c| std.ascii.isWhitespace(c),
            .choice => |cs| b: {
                for (cs) |c| {
                    if (matchesWhitespace(c)) {
                        break :b true;
                    }
                }
                break :b false;
            },
            .range => false, // TODO: proper checking for ranges
            .seq => |cs| cs.len > 0 and matchesWhitespace(cs[0]),
            .repeat => |c| matchesWhitespace(c.*),
            .repeat_plus => |c| matchesWhitespace(c.*),
        };
    }

    fn skipWhitespace(self: *RegexParser, source: []const u8) void {
        const pos = self.lexer.current_position;
        defer self.lexer.current_position = pos;
        const tmp = self.parse() catch return;
        if (!matchesWhitespace(tmp)) {
            while (source.len > self.current_index and std.ascii.isWhitespace(source[self.current_index])) {
                self.current_index += 1;
            }
        }
    }

    fn consumeExpr(
        self: RegexParser,
        expr: RegexExpression,
        source: []const u8,
    ) Error!usize {
        var current_index: usize = 0;
        if (source.len == 0) return Error.EndOfInput;
        switch (expr) {
            .char => |c| {
                if (std.mem.containsAtLeast(u8, "()*", 1, &.{c})) std.log.info("char = {c}, source = '{s}'", .{ c, source });
                return if (source[current_index] == c) current_index + 1 else Error.CharacterMissmatch;
            },
            .range => |r| {
                const char = source[current_index];
                if (r.start <= char and char <= r.end) return current_index + 1;
                return Error.CharacterMissmatch;
            },
            .seq => |exprs| {
                for (exprs) |e| {
                    const comsumed = try self.consumeExpr(e, source[current_index..]);
                    current_index += comsumed;
                }
                return current_index;
            },
            .choice => |exprs| {
                for (exprs) |e| {
                    const comsumed = self.consumeExpr(e, source[current_index..]) catch continue;
                    current_index += comsumed;
                    break;
                }
                return if (current_index != 0) current_index else Error.CharacterMissmatchChoice;
            },
            .repeat => |e| {
                while (self.consumeExpr(e.*, source[current_index..])) |consumed| {
                    current_index += consumed;
                } else |_| {}
                return current_index;
            },
            .repeat_plus => |e| {
                current_index += try self.consumeExpr(e.*, source[current_index..]);
                while (self.consumeExpr(e.*, source[current_index..])) |consumed| {
                    current_index += consumed;
                } else |_| {}
                return current_index;
            },
        }
    }
};

const RegexLexer = struct {
    current_position: usize = 0,
    data: []const u8,

    fn init(data: []const u8) RegexLexer {
        return .{
            .data = data,
        };
    }

    fn newToken(char: u8, kind: TokenKind) Token {
        return .{
            .kind = kind,
            .char = char,
        };
    }

    fn peekChar(self: RegexLexer) ?u8 {
        if (self.current_position < self.data.len) {
            return self.data[self.current_position];
        } else {
            return null;
        }
    }

    fn readChar(self: *RegexLexer) ?u8 {
        if (self.current_position < self.data.len) {
            const tmp = self.data[self.current_position];
            self.current_position += 1;
            return tmp;
        } else {
            return null;
        }
    }

    fn kindOf(char: u8) TokenKind {
        return switch (char) {
            '(' => .OpenSequence,
            ')' => .CloseSequence,
            '[' => .OpenChoice,
            ']' => .CloseChoice,
            '{' => .OpenRange,
            '}' => .CloseRange,
            '*' => .RepeatOp,
            '+' => .RepeatPlusOp,
            '-' => .RangeMinus,
            '\\' => .EscapedChar,
            else => .Char,
        };
    }

    fn next(self: *RegexLexer) ?Token {
        const char = self.readChar() orelse return null;
        return newToken(char, kindOf(char));
    }
};
