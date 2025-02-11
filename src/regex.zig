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
        Error.EndOfInput => "unexpected end of input",
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
    seq: []const RegexExpression,
    choice: []const RegexExpression,
    repeat: *const RegexExpression,
};

const Error = error{
    CharacterMissmatch,
    CharacterMissmatchChoice,
    InvalidEscapedChar,
    EndOfInput,
    RegexParsingFailed,
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

    fn parse(self: *RegexParser) Error!RegexExpression {
        const token = self.lexer.next() orelse return Error.EndOfInput;
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
            else => return Error.NotImplemented,
        }
    }

    fn consume(self: *RegexParser, source: []const u8) Error![]const u8 {
        self.current_index = 0;
        while (self.parse()) |expr| {
            const consumed = try self.consumeExpr(expr, source[self.current_index..]);
            self.current_index += consumed;
        } else |err| if (err != Error.EndOfInput) return err;
        return source[0..self.current_index];
    }

    fn consumeExpr(
        self: RegexParser,
        expr: RegexExpression,
        source: []const u8,
    ) Error!usize {
        var current_index: usize = 0;
        std.debug.assert(source.len > 0);
        switch (expr) {
            .char => |c| {
                if (!std.ascii.isWhitespace(c) and std.ascii.isWhitespace(source[0])) {
                    var char = if (source.len > current_index) source[current_index] else return Error.EndOfInput;
                    while (std.ascii.isWhitespace(char)) {
                        current_index += 1;
                        char = if (source.len > current_index) source[current_index] else return Error.EndOfInput;
                    }
                }
                return if (source[current_index] == c) current_index + 1 else Error.CharacterMissmatch;
            },
            .seq => |exprs| {
                for (exprs) |e| {
                    const comsumed = try self.consumeExpr(e, source[current_index..]);
                    current_index += comsumed;
                }
                return current_index;
            },
            else => return Error.NotImplemented,
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
