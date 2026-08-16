# Slab WIRE

WIRE records now use one-word handles backed by a resettable word arena. The
handle carries a stable nine-bit kind ID and a 29-bit arena offset. Modules,
functions, blocks, and instructions share the representation; `wire_schema.w`
is the append-only opcode/kind registry.

The arena stores an inline count/capacity header followed by symbol/value
pairs. Instruction fields have a canonical per-op order recorded in
`compiler/wire_instruction_schema.json`; generated `wire_make_<op>` and
`emit_wire_<op>` functions write those positions directly. Dynamic machine-op
selectors use the same direct-arena path with canonical lexical field order.
Modules, functions, and blocks reserve space for analysis fields that are
attached after construction. Instructions reserve six late-pass fields
(source location plus mid-end/emitter metadata). Existing fields are rewritten
in place, while `w_wire_clone` provides the copy-on-write primitive needed by
incremental lowering.

Allocation writes only the count/capacity header. Words beyond `count` are
unobservable and are filled by `store_at` before publication, so the arena
does not clear live or reserved pairs on every bump allocation.

`[]` and `[]=` intentionally remain representation primitives in both the
native runtime and the C VM for hand-built/bootstrap compatibility and
late-pass rewrites. Normal lowering does not construct instruction Hashes.
Packed WIRE values are explicitly excluded from the packed-AST predicate even
though both use the otherwise-full packed-node NaN-box subtype.

Mid-end and emitter opcode tests use `wire_kind`, which reads the kind directly
from the handle instead of routing the hottest field through hash-compatible
`[]` dispatch.

## Generated layout contract

`scripts/gen_wire_constructors.rb` owns the mechanical boundary. The committed
schema is append/update reviewed data; `--update-schema` learns fields from
new emission sites, `--write` regenerates constructors, `--rewrite` migrates
newly added literal instruction hashes, and `--check` rejects stale generated
output or a literal instruction Hash left in `compiler/lib`. Per-op fields are
lexical so their arena offsets are stable regardless of the order used at an
emission site.

Content hashing preserves the existing canonical byte stream and therefore
the content-addressed LLVM symbol names. Instead of probing the full metadata
key universe through Hash-compatible lookup for every instruction, it walks
the packed record's canonical symbol/value ordinals once and selects the
codegen-relevant fields. Specialized operand encodings still handle temp and
label normalization.

`wire_instruction(Hash)` remains a compatibility adapter for external tests
and hand-built/bootstrap callers. Production lowerers reach it only when an
already-packed instruction is passed through the generic `emit_instruction`
helper; no temporary instruction Hash is allocated on that path.

The arena is one compilation generation. `wire_module` resets it before
building a module, and `compile-batch` finishes emission before starting the
next module. Holding a WIRE handle across that boundary is invalid.

## Validation contract

- `runtime/tests/test_node_arena.c` covers handle classification, field access,
  canonical ordinal walking, clone independence, and high-water buffer reuse.
- `ruby scripts/gen_wire_constructors.rb --check` verifies generated layouts
  and rejects reintroduced literal instruction hashes in compiler workers.
- The C VM must lower and emit through packed WIRE, including its specialized
  index, bracket-assignment, and raw ccall opcodes.
- Representative programs must produce byte-identical LLVM compared with the
  pre-slab compiler, and clang must accept that LLVM.
