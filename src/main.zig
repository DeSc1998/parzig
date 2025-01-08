const std = @import("std");

fn isString(comptime value: anytype) bool {
    // @TypeOf(string lit.) = *const [_:0]u8
    const string_info = @typeInfo(@TypeOf(value));
    return switch (string_info) {
        .Pointer => |ptr| b: {
            if (!ptr.is_const) break :b false;
            const child_info = @typeInfo(ptr.child);

            switch (child_info) {
                .Opaque => break :b true,
                else => break :b false,
            }
        },
        else => false,
    };
}

fn validateParserRule(comptime string: []const u8) void {
    if (string.len == 0 or std.mem.count(u8, string, " ") == string.len) @compileError("Rule value is empty");
}

fn validateFields(comptime fields: []const std.builtin.Type.StructField) void {
    for (fields) |f| {
        if (std.mem.eql(u8, f.name, "root")) continue;
        if (f.type != Rule) {
            var buffer: [1024]u8 = undefined;
            const msg = std.fmt.bufPrint(
                buffer[0..],
                "Error: field '{s}' is not a Rule: type is '{s}'",
                .{ f.name, @typeName(f.type) },
            ) catch @compileError("format error");
            @compileError(msg);
        }
        const default = f.default_value orelse @compileError("Rule has no value");
        // NOTE: verified by the compiler
        const casted = @as(*[]const u8, @ptrCast(@alignCast(@constCast(default))));
        validateParserRule(casted.*);
    }
}

fn fromOpaq(comptime T: type, ptr: ?*anyopaque) *T {
    return @ptrCast(@alignCast(ptr));
}

const Rule = []const u8;

const G = struct {
    root: Rule = "test",
    test_rule: Rule =
        \\test
    ,
};

const t = "aoeuao";

fn isGrammar(comptime grammar: type) bool {
    comptime {
        const info = @typeInfo(grammar);
        if (info != .Struct) @compileError("The provided grammar must be a struct");
        if (!@hasField(grammar, "root")) @compileError("Grammar has no root rule");
        const tmp = grammar{};
        if (@TypeOf(@field(tmp, "root")) != Rule) @compileError("The field 'root' is not a rule");
        validateFields(info.Struct.fields);
    }
    return true;
}

pub fn main() !void {
    const g = isGrammar(G);
    _ = g;
}
