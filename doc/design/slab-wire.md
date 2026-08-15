# Slab WIRE

WIRE records now use one-word handles backed by a resettable word arena. The
handle carries a stable nine-bit kind ID and a 29-bit arena offset. Modules,
functions, blocks, and instructions share the representation; `wire_schema.w`
is the append-only opcode/kind registry.

The arena stores an inline count/capacity header followed by symbol/value
pairs. Modules, functions, and blocks reserve space for analysis fields that
are attached after construction. Instructions reserve two fields. Existing
fields are rewritten in place, while `w_wire_clone` provides the copy-on-write
primitive needed by incremental lowering.

`[]` and `[]=` intentionally remain representation primitives in both the
native runtime and the C VM. That keeps lowering, CFG, ownership, content hash,
and emission source-compatible while the migration is staged. Packed WIRE
values are explicitly excluded from the packed-AST predicate even though both
use the otherwise-full packed-node NaN-box subtype.

## Current boundary

This change moves the persistent WIRE graph off heap Hash nodes and makes
mid-end clones arena-local. Lowerers still form short-lived Hash literals at
the `emit_instruction` boundary; `wire_instruction` copies those fields into
the arena immediately. Removing those construction temporaries is a separate,
mechanical constructor-generation pass. Content hashing likewise continues to
use its field-aware canonical form so cached symbol names remain byte-for-byte
stable; a byte-walk hash requires a canonical field schema rather than the
transitional symbol/value layout.

The arena is one compilation generation. `wire_module` resets it before
building a module, and `compile-batch` finishes emission before starting the
next module. Holding a WIRE handle across that boundary is invalid.

## Validation contract

- `runtime/tests/test_node_arena.c` covers handle classification, field access,
  clone independence, and high-water buffer reuse.
- The C VM must lower and emit through packed WIRE, including its specialized
  index and bracket-assignment opcodes.
- Representative programs must produce byte-identical LLVM compared with the
  pre-slab compiler, and clang must accept that LLVM.
