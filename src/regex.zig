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
    CloseRange,
    OpenChoice,
    CloseChoice,
    RepeatOp,
};

const Token = struct {
    kind: TokenKind,
    chars: []const u8,
};

const RegexExpression = union(enum) {
    char: u8,
    range: struct { start: u8, end: u8 },
    seq: []const RegexExpression,
    choice: []const RegexExpression,
    repeat: *const RegexExpression,
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

    const escaped_char_map = std.static_string_map.StaticStringMap(u8).initComptime(.{
        .{ "[", '[' },
        .{ "]", ']' },
        .{ "(", '(' },
        .{ ")", ')' },
        .{ "{", '{' },
        .{ "}", '}' },
        .{ "*", '*' },
    });

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

    fn parse(self: *RegexParser) Error!RegexExpression {
        const token = self.lexer.next() orelse return Error.EndOfRegex;
        switch (token.kind) {
            .Char => {
                return .{ .char = token.chars[0] };
            },
            .EscapedChar => {
                std.debug.assert(token.chars.len == 1);
                const char = RegexParser.escaped_char_map.get(
                    token.chars,
                ) orelse return Error.InvalidEscapedChar;
                return .{ .char = char };
            },
            .OpenSequence => {
                const out = try self.parseSequence();
                const end = self.lexer.next() orelse return Error.EndOfRegex;
                std.debug.assert(end.kind == .CloseSequence);
                return out;
            },
            .OpenChoice => {
                const out = try self.parseChoice();
                const end = self.lexer.next() orelse return Error.EndOfRegex;
                std.debug.assert(end.kind == .CloseChoice);
                return out;
            },
            .OpenRange => {
                const start = self.lexer.next() orelse return Error.EndOfRegex;
                std.debug.assert(start.kind == .Char);
                const end = self.lexer.next() orelse return Error.EndOfRegex;
                std.debug.assert(end.kind == .Char);
                const tmp = self.lexer.next() orelse return Error.EndOfRegex;
                std.debug.assert(tmp.kind == .CloseRange);
                return .{ .range = .{ .start = start.chars[0], .end = end.chars[0] } };
            },
            .RepeatOp => {
                const tmp = try allocator.create(RegexExpression);
                tmp.* = try self.parse();
                return .{ .repeat = tmp };
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
        } else |err| if (err != Error.EndOfRegex) return err;
        return source[0..self.current_index];
    }

    fn skipWhitespace(self: *RegexParser, source: []const u8) void {
        const pos = self.lexer.current_position;
        defer self.lexer.current_position = pos;
        const tmp = self.parse() catch return;
        switch (tmp) {
            .char => |char| {
                if (!std.ascii.isWhitespace(char)) {
                    while (source.len > self.current_index and std.ascii.isWhitespace(source[self.current_index])) {
                        self.current_index += 1;
                    }
                }
            },
            // TODO: assumed non whitespace character. BAD!!!
            else => {
                while (source.len > self.current_index and std.ascii.isWhitespace(source[self.current_index])) {
                    self.current_index += 1;
                }
            },
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
                return current_index;
            },
            .repeat => |e| {
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

    fn newToken(chars: []const u8, kind: TokenKind) Token {
        return .{
            .kind = kind,
            .chars = chars,
        };
    }

    pub fn reset(self: *RegexLexer, index: usize) void {
        self.current_position = index;
    }

    fn peekChar(self: RegexLexer) ?u8 {
        if (self.data.len > self.current_position) {
            return self.data[self.current_position];
        } else {
            return null;
        }
    }

    fn readChar(self: *RegexLexer) ?u8 {
        if (self.data.len > self.current_position) {
            const tmp = self.data[self.current_position];
            self.current_position += 1;
            return tmp;
        } else {
            return null;
        }
    }

    fn next(self: *RegexLexer) ?Token {
        const char = self.peekChar() orelse return null;

        const pos = self.current_position;
        if (char == '(') {
            _ = self.readChar() orelse unreachable;
            return newToken(self.data[pos..self.current_position], .OpenSequence);
        } else if (char == ')') {
            _ = self.readChar() orelse unreachable;
            return newToken(self.data[pos..self.current_position], .CloseSequence);
        } else if (char == '[') {
            _ = self.readChar() orelse unreachable;
            return newToken(self.data[pos..self.current_position], .OpenChoice);
        } else if (char == ']') {
            _ = self.readChar() orelse unreachable;
            return newToken(self.data[pos..self.current_position], .CloseChoice);
        } else if (char == '{') {
            _ = self.readChar() orelse unreachable;
            return newToken(self.data[pos..self.current_position], .OpenRange);
        } else if (char == '}') {
            _ = self.readChar() orelse unreachable;
            return newToken(self.data[pos..self.current_position], .CloseRange);
        } else if (char == '*') {
            _ = self.readChar() orelse unreachable;
            return newToken(self.data[pos..self.current_position], .RepeatOp);
        } else if (char == '\\') {
            _ = self.readChar() orelse unreachable;
            _ = self.readChar() orelse return null;
            return newToken(self.data[pos + 1 .. self.current_position], .EscapedChar);
        } else {
            _ = self.readChar() orelse unreachable;
            return newToken(self.data[pos..self.current_position], .Char);
        }
    }
};
