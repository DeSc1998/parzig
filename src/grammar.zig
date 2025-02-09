const std = @import("std");

fn comptimeLog(comptime format: []const u8, comptime args: anytype) noreturn {
    var buffer: [2048]u8 = undefined;
    const msg = std.fmt.bufPrint(buffer[0..], format, args) catch @compileError("format error during comptime logging");
    @compileError(msg);
}

pub fn RuleFrom(comptime Enum: type) type {
    return union(enum) {
        seq: []const RuleFrom(Enum),
        choice: []const RuleFrom(Enum),
        repeat: []const RuleFrom(Enum),
        subrule: Enum,
        regex: []const u8,
    };
}

pub fn RuleType(comptime grammar: type) type {
    return RuleFrom(RulesEnum(grammar));
}

pub fn RulesEnum(comptime grammar: type) type {
    return grammar.Rules;
}

pub fn StringMap(comptime Type: type) type {
    return std.static_string_map.StaticStringMap(Type);
}

pub fn RuleMap(comptime Grammar: type) StringMap(RuleFrom(RulesEnum(Grammar))) {
    isValid(Grammar);
    const Rule = RuleFrom(RulesEnum(Grammar));
    const Map = StringMap(RuleFrom(RulesEnum(Grammar)));
    const info = @typeInfo(Grammar);
    const tmp = Grammar{};
    var out: [info.Struct.fields.len]struct { []const u8, Rule } = undefined;
    for (&out, info.Struct.fields) |*entry, field| {
        entry.* = .{ field.name, @field(tmp, field.name) };
    }
    return Map.initComptime(out);
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
        const inner_info = @typeInfo(RulesEnum(grammar));
        for (inner_info.Enum.fields) |field| {
            if (!@hasField(grammar, field.name)) comptimeLog(
                "declared rule '{s}' does not exist in the grammar",
                .{field.name},
            );
        }
        for (info.Struct.fields) |field| {
            const type_info = @typeInfo(field.type);
            if (type_info != .Union) comptimeLog(
                "rule '{s}' is not a union type from 'fn RuleFrom(Enum)'",
                .{field.name},
            );
            const Tmp = RuleFrom(@Type(inner_info));
            const tmp_info = @typeInfo(Tmp).Union;
            for (type_info.Union.fields, tmp_info.fields) |act, exp| {
                if (!std.mem.eql(u8, act.name, exp.name)) comptimeLog(
                    "in rule '{s}': fields '{s}' and '{s}' differ. Please use 'fn RuleFrom(Enum)'",
                    .{ field.name, act.name, exp.name },
                );
            }
        }
    }
}

/// fails to compile if the grammar is left-recursive
fn isLeftRecursive(comptime grammar: type) void {
    _ = grammar;
    comptimeLog("TODO: implement 'isLeftRecursive'", .{});
}
