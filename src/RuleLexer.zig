const std = @import("std");

const RuleLexer = @This();

pub const TokenKind = enum {
    Identifier,
    Number,
    Regex,

    OpenSequence,
    CloseSequence,
    OpenChoice,
    CloseChoice,
    RepeatOp,
    Comma,
};

pub const Token = struct {
    kind: TokenKind,
    chars: []const u8,
};

current_position: usize = 0,
data: []const u8,

pub fn init(comptime data: []const u8) RuleLexer {
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

fn advanceWhile(self: *RuleLexer, pred: *const fn (u8) bool) void {
    while (self.data.len > self.current_position and pred(self.data[self.current_position])) {
        self.current_position += 1;
    }
}

pub fn reset(self: *RuleLexer, index: usize) void {
    self.current_position = index;
}

fn peekChar(self: RuleLexer) ?u8 {
    if (self.data.len > self.current_position) {
        return self.data[self.current_position];
    } else {
        return null;
    }
}

fn readChar(self: *RuleLexer) ?u8 {
    if (self.data.len > self.current_position) {
        const tmp = self.data[self.current_position];
        self.current_position += 1;
        return tmp;
    } else {
        return null;
    }
}

fn isWhitespace(char: u8) bool {
    return std.ascii.isWhitespace(char);
}

fn isIdentifierChar(char: u8) bool {
    return std.ascii.isAlphanumeric(char) or char == '_';
}

fn isRegex(char: u8) bool {
    return char != '\'';
}

fn isNumberChar(char: u8) bool {
    return std.ascii.isDigit(char);
}

pub fn next(self: *RuleLexer) ?Token {
    self.advanceWhile(&isWhitespace);
    const char = self.peekChar() orelse return null;

    const pos = self.current_position;
    if (std.ascii.isDigit(char)) {
        self.advanceWhile(&isNumberChar);
        return newToken(self.data[pos..self.current_position], .Number);
    } else if (std.ascii.isAlphanumeric(char) or char == '_') {
        self.advanceWhile(&isIdentifierChar);
        return newToken(self.data[pos..self.current_position], .Identifier);
    } else if (char == '(') {
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
    } else if (char == '\'') {
        _ = self.readChar() orelse unreachable; // ignore initial `'`
        self.advanceWhile(&isRegex);
        const quote = self.readChar() orelse return null; // ignore final `'`
        if (quote != '\'') return null;
        return newToken(self.data[pos + 1 .. self.current_position - 1], .Regex);
    } else {
        errorOut("unexpected character '{}'", .{char});
    }
}

fn errorOut(comptime format: []const u8, comptime args: anytype) noreturn {
    var buffer: [2048]u8 = undefined;
    const msg = std.fmt.bufPrint(buffer[0..], format, args) catch @compileError("format error during comptime logging");
    @compileError(msg);
}
