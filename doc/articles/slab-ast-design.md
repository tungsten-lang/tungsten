# The Slab AST — One Word Per Node Reference, Zero Bytes of Header

Tungsten's compiler is written in Tungsten, and for most of its life its
AST was the obvious thing for a dynamic self-hosted language: a hash per
node, `{node: :call, name: "puts", args: [...]}`, heap-allocated,
pointer-chased, garbage. The slab-AST migration replaced that with an
arena-and-handle design in the same weight class as the most aggressively
data-oriented compiler frontends shipping today (Zig's stage2, Carbon's
toolchain) — while keeping every node a first-class value the self-hosted
compiler can pass through its own arrays, hashes, and closures.

This article documents the design as it stands, the numbers behind each
decision, and how it compares to other production compilers.

## The handle: a NaN-boxed word with the kind inside

A node reference is a single 64-bit `WValue` — a NaN-boxed packed value
(subtype `W_PACKED_NODE`) whose 45-bit payload is:

```
 44 43───────36 35──34 33──32 31───────────────────────0
┌──┬───────────┬──────┬──────┬─────────────────────────┐
│ 0│   kind    │sclass│ rsvd │         offset          │
│  │  (8 bit)  │(2bit)│(2bit)│    (32 bit, in nodes)   │
└──┴───────────┴──────┴──────┴─────────────────────────┘
  └ prefix bit: 1 = compact tier (5-bit kind, 39-bit payload)
```

Two properties fall out of this that no pointer-based AST gets:

**Kind dispatch never touches memory.** `case node.kind` masks bits
already in a register. Clang loads a kind field (often behind a vptr),
Zig and Carbon load a tag from a side array; Tungsten's kind check is
free. Combined with interned-symbol `case` dispatch compiling to a real
LLVM `switch i64`, the compiler's per-node dispatch is a jump table on
register bits.

**Nodes have zero header bytes.** The arena slots hold fields only —
16/32/64/128 B strides by size class (SC_2/SC_4/SC_8/SC_16), assigned
from each kind's constructor field count. There is no kind word, no
vptr, no GC header. The flip side is a real constraint: there is nowhere
to put mutable per-node metadata, and a node's kind can never change in
place. Rewrites that change a node's kind *return the replacement* and
the parent writes it back into the schema slot — a discipline that
forced all the tree-rewriting passes into a functional style
(`substitute_vars_in_ast` and friends return nodes; the metal emitter's
`@schedule` rewriters were the last holdouts, repaired during preview
hardening).

## The arenas: offsets, not pointers

Each size class is one bump arena that grows by realloc-doubling.
Handles store *offsets* into the arena, not pointers, so growth
invalidates nothing — the base pointer is re-read on every access, and
the emitter inlines that read (`g_node_arena[sc].base` + stride
multiply) wherever the kind is statically known. Initial capacities are
sized from a self-compile measurement so the common case incurs zero
reallocs. Compile-over: `w_node_arena_reset` frees everything in O(1).

A full self-host parse (185K live + transient node allocations before
the interning work below) fits in a **pre-sized ~3.7 MiB**. There is no
per-node free, no fragmentation, and the loader cache embeds a schema
hash so any layout change invalidates stale caches automatically.

## The schema: field names → slot indices, plus two magic sentinels

Field layout lives in one table in `ast_schema.w`:
`KIND_ASSIGN => {:target => 0, :value => 1, :type_hint => 2}`. Accessors
(`node.value`) resolve through `ast_get`, which turns the field symbol
into a slot index — or into one of two sentinels that mean "this field
is not in memory at all":

- **`256` (inline int)** — the payload lives in the handle's offset
  bits. `:char`, `:parg`, `:lambda_arity`, `:superscript`,
  `:regex_capture` nodes are pure bit patterns; constructing one
  allocates nothing.
- **`257` (inline interned string)** — the offset bits hold a dense id
  into a content-addressed string-intern table. This is the workhorse:
  `var`, `ivar`, `cvar`, `symbol`, and `string` nodes — the five
  single-string leaf kinds — are handle-only.

The `257` tier landed after `--ast-stats` showed what leaf kinds
actually cost. On a self-compile of `tungsten.w`:

```
                     before          after
var nodes (tree)     42,728          42,728   (23% of the whole AST)
distinct var names    2,690           2,690
SC_2 allocations    110,960          12,856   (-88%)
total slab bytes    5,148 KB        3,617 KB  (-30%)
total allocations   185,146          87,076   (-53%)
```

The arena counters drop far more than the tree-walk counts because they
include transient parse-time nodes — every one of which was a leaf that
now costs nothing. Interning also dedups the payload strings themselves:
42,728 var names collapse to 2,690 interned copies. The intern table is
deliberately *never* reset — ids are content-stable, so REPL and JIT
recompiles re-intern to the same ids and the table amortizes.

Two kinds that look like candidates deliberately stay allocated:
`class_ref` (monomorphization renames it in place — identity must not be
shared) and `int` (it carries `:format` and `:raw`, which aren't
derivable from the value).

Singletons round out the zero-allocation set: `nil`, `self`, `break`,
`next`, `return_nil`, and the view markers are one constant bit pattern
each, and `bool` caches its two nodes.

## Rare fields: the sparse side-table

Zero header bytes means no room for occasionally-present fields
(`:loc_end` on literals, `:axis_name` on `@schedule`-tagged assigns,
`:type_args` on generic class refs). Those live in a C-side
open-addressed map keyed by the node's handle bits, chaining
`(symbol, value)` records in a bump arena. Absent reads cost one probe
and return nil; nodes that never touch the table cost nothing. The
table resets with the node arenas — handle bits get reused across
compiles, so it must.

## Child lists: a packed reference, not a pointer

The last piece of the AST living on the heap was child lists —
`:args`, `:expressions`, `:body` arrays, tens of thousands per compile.
The first cut at fixing this copied each array's `WArray` header and
slots into an arena on first store, keeping the existing pointer-boxed
representation — a real win (one allocation instead of two, arena
locality), but still a pointer chase behind a 24-byte header.

The header turned out to be unnecessary for exactly the reason the
node handle already proved: `w_box_ptr`'s 16-byte-alignment
requirement exists solely so it can steal a machine pointer's low
nibble for a subtype tag. An arena-relative offset isn't a pointer —
it's an integer packed directly into the value, the same trick
`W_PACKED_NODE` already uses for individual nodes. So child lists now
skip the pointer entirely: a frozen array becomes one `W_PACKED_BODY`
value (packed subtype 6, previously reserved) — **24-bit offset + 21-bit
length**, no kind/mode bits needed since there's only one shape, no
`ebits`/`start`/`cap` since every frozen array is already homogeneous
w64 slots (the freeze guard requires it) and immutable once frozen.

```
63        48 47 45 44                31 30                 10
┌──────────┬─────┬────────────────────┬──────────────────────┐
│  0xFFFE  │  6  │   offset (24b)     │    length (21b)      │
└──────────┴─────┴────────────────────┴──────────────────────┘
```

Dropping the pointer let the arena itself simplify. The earlier
chunked, non-moving design existed *only* because a `WArray`'s `slots`
field pointed at memory right after its own header — relocating the
chunk would dangle that self-reference. A packed offset has no such
problem: every access re-derives the address from a freshly-read
arena base, exactly like node field access already does. So the body
arena collapsed to a single realloc-doubling buffer, structurally
identical to `g_node_arena`'s own growth model — simpler code, not
more.

**Transparency was the whole design constraint.** Every existing
`type(x) == "Array"` check across the compiler — `ast_children`,
`ast_array_fields`, `ast_to_tree`, `ast_deep_clone`, the metal
emitter's rewriters — needed *zero* changes, because `type()` now
reports `"Array"` for a packed-body value (one added line), and
`[]`/`[]=`/`.size`/`.each` plus a dozen read-only Enumerable methods
(`map`/`select`/`reject`/`find`/`reduce`/`any?`/`all?`/`none?`/
`compact`/`dup`/`empty?`) all resolve transparently — either through
the two runtime primitives every `[]`/`[]=` unconditionally lowers to
(widened to recognize the packed form), or through a new IC-dispatch
table at key `0xE6`, which `w_dispatch_key` already generated
generically for every packed subtype without any change.

Measured on the same self-compile: **38,214 arrays, 84,809 w64 slots,
662.6 KB total** — down from 2,047 KB with the header-carrying
design. Removing the header outright, rather than just relocating it,
cut the arena to under a third of its previous size.

### The mutation bugs this surfaced

Immutability is only free if nothing relies on mutating a frozen list
in place. An initial grep-based audit found zero such call sites, but
the empirical gate — the same self-hosting build that has caught
every representational mismatch this design has ever introduced —
found five genuine ones, all some form of "read a schema array field,
then mutate the array object directly," which stopped being possible
the moment that field held a value instead of a pointer:

- A GPU-kernel rewriter (`apply_simd_reduce`) cleared a kernel body via
  `pop()`-until-empty then rebuilt it with `push()` — its own comment
  already called this a workaround ("Tungsten arrays don't expose
  clear"). Converted to return-the-replacement, same as every
  kind-changing node rewrite already does.
- Two generic-specialization walkers and a Σ-notation desugaring pass
  index-assigned into an array field read via `ast_get`. All three
  converted to build-fresh-and-`ast_set`-back.
- The loader's autoload pass aliased the parsed `Program`'s
  `expressions` field directly and accumulated newly-autoloaded files
  into it via `push` across up to 64 iterations — the actual root
  cause behind every crash surfaced while building this feature, since
  it fires on any compile that autoloads anything. Fixed by
  materializing a real growable copy; the function already built a
  fresh `Program` at the end regardless.

None of these were represented as edge cases in the design — they were
straightforwardly incompatible with "a child list is a value, not a
mutable object," and the self-host build turned each one into a loud,
precisely diagnosable crash rather than silent corruption.

## Locations: one packed word, with room saved for byte offsets

Source locations are packed `W_PACKED_LOCATION` values — one word, no
allocation, stored in `:loc`/`:loc_end` slots or sparse entries. The
45-bit payload uses a 2-bit mode field (bits 44:43) rather than the
original 1-bit one: bit 44 sat unused above every existing encoding
(Point and File payloads both top out at 43 bits), so widening the
mode field cost nothing and left both legacy encodings' bit patterns
unchanged.

```
Point (00):       [21 x][22 y]                     — non-source positions
File (01):        [14 file_id][18 line][11 col]     — line/col, in use today
FileOffset (10):  [14 file_id][29 byte offset]      — reserved for spans
```

`FileOffset` is the byte-offset representation rustc/Clang/Go use —
one 512-MiB-per-file offset per point, with line/col reconstructed
lazily at error-render time from a per-file newline-offset table
(built once, binary-searched) rather than stored per node. It exists
in the encoding now but nothing constructs it yet; `compile_error_for_node`
still walks File-mode line/col. Wiring the parser's `make_loc_here` /
`make_end_loc` over to it — and adding the line-table reconstruction —
is the natural next step, and the reason bit 44 was banked rather than
spent on something narrower: File mode's 18-bit line / 11-bit column
ceiling is the kind of limit generated or minified sources eventually
find, and the fix was worth reserving room for before it was needed.

## Verification: byte-identity as a differential test

The design's twin risk is that pieces of it exist twice: the arena,
sparse table, and intern table each have one implementation in
`runtime/runtime.c` (linked into compiled stages) and a mirror in
`implementations/c/src/node_arena.c` (linked into the stage-0 C VM).
The bootstrap turns that risk into the strongest gate in the repo:
stage 1 is emitted by the *VM-interpreted* compiler using the VM's
copies, stage 2 by the *compiled* stage 1 using the runtime's copies,
and the build fails unless the two `.ll` outputs are byte-identical.
Every build is a full differential test of both implementations — and
of behavioral changes like the child-list freeze, which stage 0
deliberately does not perform.

## How it compares

| Compiler | Node ref | Per-node overhead | Layout | Locations |
|---|---|---|---|---|
| **Tungsten** | 8 B handle, kind inside | 0 B | AoS, 4 size-classed arenas | 1 word packed |
| Zig stage2 | 4 B index | ~1 B tag + 4 B token | SoA (MultiArrayList) + extra_data | token → byte offset |
| Carbon | 4 B index | ~4 B kind+token | flat postorder array | byte offset |
| rustc | arena ptr | fat | AoS arenas + interning | 4 B interval-packed span |
| Clang | pointer | kind bits (+vptr) | bump arena + TrailingObjects | 4 B SourceLocation |
| Roslyn/Swift | pointer | fat | immutable red-green trees | computed widths |
| V8 | zone ptr | vptr | Zone arena, discarded wholesale | byte offset |

Zig and Carbon get 4-byte indices because their compilers are written in
statically-typed host languages; a self-hosted dynamic language can't do
better than one NaN-boxable word, and 45 payload bits is what that word
affords. In exchange, Tungsten nodes flow through generic Tungsten code
unboxed, and kind dispatch beats even the index-based designs (their tag
lives in a side array; ours lives in the handle).

The deliberate divergence from Zig/Carbon is AoS over SoA. SoA pays off
when passes sweep all nodes column-wise; Tungsten's walkers are
recursive and schema-driven, and the load SoA exists to avoid — the tag
fetch — is already free here. The industry direction is unambiguous
(TypeScript's Go port, Zig, and Carbon all abandoned pointer-object
ASTs for index+arena designs, citing 2–4× memory wins); the slab AST
gets there without giving up self-hosting.

## What's deliberately not done

- **Red-green trees / incremental reparse** (Roslyn, SwiftSyntax): wrong
  trade for this compiler. Arena reset is O(1) and the SIMD lexer makes
  whole-file reparse the right incrementality model — the position Zig
  takes as well.
- **SoA node storage**: see above; revisit only if a profile shows a
  pass that sweeps all nodes uniformly.
- **Byte-offset spans**: the encoding exists (`FileOffset` mode above)
  but nothing constructs it yet — the clearest remaining gap versus
  rustc/Clang/Go. `compile_error_for_node` already centralizes
  rendering, so the line-table lookup has exactly one home once the
  parser switches over.
