const std = @import("std");

const RuleParser = @import("RuleParser.zig");

pub const ParsedRule = RuleParser.Rule;
pub const Subrule = RuleParser.Subrule;
pub const BuildinRule = RuleParser.Buildin;

pub const Rule = []const u8;
const RuleMap = std.static_string_map.StaticStringMap(RuleParser.Rule);
const Grammar = @This();

parsed_rules: RuleMap,

pub fn init(comptime grammar: type) Grammar {
    _ = isValid(grammar);
    @setEvalBranchQuota(2000); // NOTE: the default of 1000 is not enough
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

pub fn get(g: Grammar, node: []const u8) ?RuleParser.Rule {
    return g.parsed_rules.get(node);
}

fn comptimeLog(comptime format: []const u8, comptime args: anytype) noreturn {
    var buffer: [2048]u8 = undefined;
    const msg = std.fmt.bufPrint(buffer[0..], format, args) catch @compileError("format error during comptime logging");
    @compileError(msg);
}

/// Checks if the definitions of `grammar` are sound.
///
/// ex.: Supose we have a grammar with a subrule in a definition which
/// has no definition in that grammar then the compilation fails.
fn isValid(comptime grammar: type) void {
    comptime {
        const info = @typeInfo(grammar);
        if (info != .Struct) @compileError("The provided grammar must be a struct");
        if (!@hasField(grammar, "root")) @compileError("Grammar has no initial rule called 'root'");
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
}

/// fails to compile if the grammar is left-recursive
fn isLeftRecursive(comptime grammar: Grammar) void {
    _ = grammar;
    comptimeLog("TODO: implement 'isLeftRecursive'", .{});
}
