const std = @import("std");

const RegexMatch = union(enum) {
    succes: []const u8,
    failure: struct {
        source_offset: usize,
        regex_offset: usize,
        message: []const u8,
    },
};

pub fn match(regex: []const u8, source: []const u8) RegexMatch {
    var parser = RegexParser.init(regex);
    const chars = parser.consume(source) catch |err| {
        const message = switch (err) {
            Error.CharacterMissmatch => "failed to match character",
            Error.CharacterMissmatchChoice => "failed to match character in choice",
            Error.InvalidEscapedChar => "invalid escaped character in regex",
            Error.EndOfInput => "unexpected end of input",
            Error.RegexParsingFailed => "invalid regex",
            Error.NotImplemented => "reach an unimplemented path",
        };
        return RegexMatch{ .failure = .{
            .source_offset = parser.current_index,
            .regex_offset = parser.lexer.current_position,
            .message = message,
        } };
    };
    return RegexMatch{ .succes = chars };
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

const RegexExpression = struct {
    kind: enum { Char, EscapedChar, Repeat, Sequence, Choice },
    data: union(enum) {
        char: u8,
        slice: []const u8,
    },
};

const Error = error{
    CharacterMissmatch,
    CharacterMissmatchChoice,
    InvalidEscapedChar,
    EndOfInput,
    RegexParsingFailed,
    NotImplemented,
};

const RegexParser = struct {
    current_index: usize = 0,
    lexer: RegexLexer,

    const escaped_char_map = std.static_string_map.StaticStringMap(u8).initComptime(.{
        .{ "n", '\n' },
        .{ "t", '\t' },
        .{ "r", '\r' },
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

    fn consume(self: *RegexParser, source: []const u8) Error![]const u8 {
        while (self.lexer.next()) |token| {
            if (self.current_index >= source.len) return Error.EndOfInput;
            switch (token.kind) {
                .Char => {
                    std.debug.assert(token.chars.len == 1);
                    if (source[self.current_index] == token.chars[0]) {
                        self.current_index += 1;
                    } else return Error.CharacterMissmatch;
                },
                .EscapedChar => {
                    std.debug.assert(token.chars.len == 1);
                    const char = RegexParser.escaped_char_map.get(
                        token.chars,
                    ) orelse return Error.InvalidEscapedChar;
                    if (source[self.current_index] == char) {
                        self.current_index += 1;
                    } else return Error.CharacterMissmatch;
                },
                else => return Error.NotImplemented,
            }
        }
        return if (self.lexer.current_position == self.lexer.data.len)
            source[0..self.current_index]
        else
            Error.RegexParsingFailed;
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
