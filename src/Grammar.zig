const std = @import("std");

const RuleParser = @import("RuleParser.zig");

pub const Rule = []const u8;
const RuleMap = std.static_string_map.StaticStringMap(RuleParser.Rule);
const Grammar = @This();

parsed_rules: RuleMap,

pub fn init(comptime grammar: type) Grammar {
    _ = isValid(grammar);
    const info = @typeInfo(grammar);
    return .{
        .parsed_rules = comptime b: {
            var out: [info.Struct.fields.len]struct { []const u8, RuleParser.Rule } = undefined;
            for (&out, info.Struct.fields) |*entry, field| {
                var rule_parser = RuleParser.init(grammar, field.name);
                const out_rule = rule_parser.parse() orelse unreachable; // NOTE: verified by 'isValid'
                entry.* = .{ field.name, out_rule };
            }
            break :b RuleMap.initComptime(out);
        },
    };
}

fn comptimeLog(comptime format: []const u8, comptime args: anytype) noreturn {
    var buffer: [2048]u8 = undefined;
    const msg = std.fmt.bufPrint(buffer[0..], format, args) catch @compileError("format error during comptime logging");
    @compileError(msg);
}

fn isValid(comptime grammar: type) bool {
    comptime {
        const info = @typeInfo(grammar);
        if (info != .Struct) @compileError("The provided grammar must be a struct");
        if (!@hasField(grammar, "root")) @compileError("Grammar has no root rule");
        const tmp = grammar{};
        if (@TypeOf(@field(tmp, "root")) != Rule) @compileError("The field 'root' is not a rule");
        for (info.Struct.fields) |f| {
            if (f.type != Rule) {
                comptimeLog(
                    "'{s}' is not a Rule: type is '{s}'",
                    .{ f.name, @typeName(f.type) },
                );
            }
            const default = f.default_value orelse @compileError("Rule has no value");
            // NOTE: verified by the compiler
            const casted = @as(*[]const u8, @ptrCast(@alignCast(@constCast(default))));
            _ = casted.*;
            var parser = RuleParser.init(grammar, f.name);
            _ = parser.parse() orelse comptimeLog(
                "rule '{s}' has no definition or is invalid",
                .{f.name},
            );
        }
    }
    return true;
}
