pub usingnamespace @import("grammar.zig");
const parser = @import("Parser.zig");

pub fn ParserFrom(comptime grammer: type) type {
    return parser.Parser(grammer);
}
