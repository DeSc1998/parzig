# parzig

A parser generator which constructs its parsers at comptime.

The way parsers and grammars written and used is heavily inspired by
[tree-sitter](https://github.com/tree-sitter/tree-sitter).

# Usage

## Minimal Example

Assume this code here is in a file:

```zig
const parzig = @import("parzig");

const Rule = parzig.RuleFrom(Rules);
pub const Rules = enum {
    root,
};

root: Rule = .{ .regex = "" },
```

when using the parser:

```zig
const parzig = @import("parzig");
const Parser = parzig.ParserFrom(@import("path/to/grammar.zig"));
// ... in a function
    var parser = Parser.init(allocator, content);
    const tree = parser.parse() catch |err| {
        // ... handle error
    };
    // ... use the returned tree
```

This grammar just tries to match the internal regex `""`.

## Walking the Tree

Available functions of the parsed tree:

```zig
const Tree = struct {
    // frees all resources of the tree
    fn deinit(self: Tree) void;
    // recive the node of `node_index`
    fn node(self: Tree, node_index: usize) Node;
    // recive the kind of `node_index`
    fn nodeKind(self: Tree, node_index: usize) []const u8;
    // recive the children of `node_index`
    fn children(self: Tree, node_index: usize) []const usize;
    // recive the matched characters of `node_index`
    fn chars(self: Tree, node_index: usize) []const u8;

    // prints the full tree to `out`
    fn dumpTo(self: Tree, out: std.io.AnyWriter) !void;
    // prints the node given by `node_index` to `out` with `indent_level` of whitespace padding
    fn dumpNodeTo(self: Tree, node_index: usize, out: std.io.AnyWriter, indent_level: usize) !void;
};

const Node = struct {
    kind: []const u8, // string representation of the enum value, 'sequence', 'repeat' or 'regex'
    start_index: usize,
    end_index: usize,
    children: []const usize,
};
```

The functions `node`, `nodeKind`, `children` and `chars` are provided for easy access but are not
nessecary to be used. \
For example these two are aquivalant:

```zig
const node_chars = tree.chars(index);
```

```zig
const node = tree.nodes[index];
const node_chars = tree.source[node.start_index .. node.end_index];
```
