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

pub const Config = struct {
    ignore_whitespace: bool = false,
};

pub fn RuleMap(comptime Grammar: type) StringMap(RuleFrom(RulesEnum(Grammar))) {
    isValid(Grammar);
    isLeftRecursive(Grammar);
    const Rule = RuleFrom(RulesEnum(Grammar));
    const Map = StringMap(RuleFrom(RulesEnum(Grammar)));
    const info = @typeInfo(Grammar);
    const tmp = Grammar{};
    var out: [info.@"struct".fields.len]struct { []const u8, Rule } = undefined;
    for (&out, info.@"struct".fields) |*entry, field| {
        entry.* = .{ field.name, @field(tmp, field.name) };
    }
    return Map.initComptime(out);
}

pub fn ParserNodeKind(comptime Grammar: type) type {
    const info = @typeInfo(RulesEnum(Grammar)).@"enum";
    const fields = info.fields;
    const count = fields.len;
    const EnumEntry = std.builtin.Type.EnumField;
    var out_fields: [count + 3]EnumEntry = undefined;
    @memcpy(out_fields[0..count], fields);
    out_fields[count] = EnumEntry{
        .name = "regex",
        .value = count,
    };
    out_fields[count + 1] = EnumEntry{
        .name = "repeat",
        .value = count + 1,
    };
    out_fields[count + 2] = EnumEntry{
        .name = "sequence",
        .value = count + 2,
    };
    const int_info = @typeInfo(info.tag_type).int;
    return @Type(std.builtin.Type{ .@"enum" = .{
        .tag_type = @Type(std.builtin.Type{ .int = .{
            .signedness = int_info.signedness,
            .bits = int_info.bits + 2,
        } }),
        .fields = out_fields[0..],
        .decls = info.decls,
        .is_exhaustive = true,
    } });
}

pub fn configOf(comptime Grammar: type) Config {
    if (@hasDecl(Grammar, "config")) {
        return Grammar.config();
    } else {
        return .{};
    }
}

pub fn shouldIgnoreWhitespace(comptime Grammar: type) bool {
    const config = configOf(Grammar);
    return config.ignore_whitespace;
}

/// Checks if the definitions of `grammar` are sound.
///
/// ex.: Supose we have a grammar with a subrule in a definition which
/// has no definition in that grammar then the compilation fails.
fn isValid(comptime grammar: type) void {
    comptime {
        const info = @typeInfo(grammar);
        if (info != .@"struct") @compileError("The provided grammar must be a struct");
        if (!@hasField(grammar, "root")) @compileError("Grammar has no initial rule called 'root'");
        if (@hasField(grammar, "repeat"))
            @compileError("'repeat' is a reserved keyword and can not be used as a rule.");
        if (@hasField(grammar, "sequence"))
            @compileError("'sequence' is a reserved keyword and can not be used as a rule.");
        if (@hasField(grammar, "regex"))
            @compileError("'regex' is a reserved keyword and can not be used as a rule.");
        const inner_info = @typeInfo(RulesEnum(grammar));
        for (inner_info.@"enum".fields) |field| {
            if (!@hasField(grammar, field.name)) comptimeLog(
                "declared rule '{s}' does not exist in the grammar",
                .{field.name},
            );
        }
        for (info.@"struct".fields) |field| {
            const type_info = @typeInfo(field.type);
            if (type_info != .@"union") comptimeLog(
                "rule '{s}' is not a union type from 'fn RuleFrom(Enum)'",
                .{field.name},
            );
            const Tmp = RuleFrom(@Type(inner_info));
            const tmp_info = @typeInfo(Tmp).@"union";
            for (type_info.@"union".fields, tmp_info.fields) |act, exp| {
                if (!std.mem.eql(u8, act.name, exp.name)) comptimeLog(
                    "in rule '{s}': fields '{s}' and '{s}' differ. Please use 'fn RuleFrom(Enum)'",
                    .{ field.name, act.name, exp.name },
                );
            }
        }
    }
}

fn concatUnique(
    comptime grammar: type,
    left: []const RulesEnum(grammar),
    right: []const RulesEnum(grammar),
) []const RulesEnum(grammar) {
    const max_rule_count = @typeInfo(RulesEnum(grammar)).@"enum".fields.len;
    var out: [max_rule_count]RulesEnum(grammar) = undefined;
    @memcpy(out[0..left.len], left);

    var index: usize = left.len;
    for (right) |r| {
        if (!std.mem.containsAtLeastScalar(RulesEnum(grammar), out[0..left.len], 1, r)) {
            out[index] = r;
            index += 1;
        }
    }
    return out[0..index];
}

fn firstRuleOf(comptime grammar: type, rule: RuleFrom(RulesEnum(grammar))) []const RulesEnum(grammar) {
    return comptime switch (rule) {
        .subrule => |r| &.{r},
        .regex => &.{},
        .repeat, .seq => |rules| if (rules.len > 0) firstRuleOf(grammar, rules[0]) else &.{},
        .choice => |rules| b: {
            var tmp: []const RulesEnum(grammar) = &.{};
            for (rules) |r| {
                const t = firstRuleOf(grammar, r);
                tmp = concatUnique(grammar, tmp, t);
            }
            break :b tmp;
        },
    };
}

fn referencedSymbols(comptime grammar: type, rule: RuleFrom(RulesEnum(grammar))) []const RulesEnum(grammar) {
    return comptime switch (rule) {
        .subrule => |r| &.{r},
        .regex => &.{},
        .repeat, .seq, .choice => |rules| b: {
            var out: []const RulesEnum(grammar) = &.{};
            for (rules) |r| {
                const tmp = referencedSymbols(grammar, r);
                out = concatUnique(grammar, out, tmp);
            }
            break :b out;
        },
    };
}

/// Fails to compile if the grammar is left-recursive.
/// It is assumed that `grammar` has been validated with `fn isValid`.
fn isLeftRecursive(comptime grammar: type) void {
    // NOTE: branch quota of 1000 is quickly exceeded even by relativly small grammars
    @setEvalBranchQuota(32000);
    const rules_info = @typeInfo(RulesEnum(grammar));
    const g = grammar{};
    var seen: [rules_info.@"enum".fields.len + 1]RulesEnum(grammar) = undefined;
    var seen_size: usize = 1;
    seen[0] = .root;
    var referenced: []const RulesEnum(grammar) = &.{.root};
    var current_index: usize = 0;
    while (current_index < referenced.len) : (current_index += 1) {
        const current_rule = referenced[current_index];
        const current_seen_size = seen_size;
        const first = firstRuleOf(grammar, @field(g, @tagName(current_rule)));
        for (first) |e| {
            if (std.mem.containsAtLeastScalar(RulesEnum(grammar), seen[0..current_seen_size], 1, e)) {
                comptimeLog(
                    "left recursion detected in rule '{s}': recursive loop starts with '{s}'",
                    .{ @tagName(current_rule), @tagName(e) },
                );
            }
            if (!std.mem.containsAtLeastScalar(RulesEnum(grammar), seen[0..seen_size], 1, e)) {
                seen[seen_size] = e;
                seen_size += 1;
            }
        }
        referenced = concatUnique(
            grammar,
            referenced,
            referencedSymbols(grammar, @field(g, @tagName(current_rule))),
        );
    }
}
