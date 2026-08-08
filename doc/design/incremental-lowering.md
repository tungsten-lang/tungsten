# Module-level incremental lowering — design and phased plan

Goal: stop re-lowering each program's core autoload chain from scratch.
Measured motivation (2026-08-08, M-series, contended): a typical numeric
spec pays ~0.9s wall per compile — ~0.46s compiler front (0.234s
lowering, 0.086s parse, 0.065s content hash, 0.059s emit for ~423
functions of which ~a dozen are the spec's own), ~0.2s clang, the rest
link+wrapper. A null program is 1 function / 0.05s: there is **no
unconditional prelude** — the cost is the per-program autoload closure,
heavily overlapping across programs. The spec battery pays this floor
~150x per run.

## Why the naive design is wrong

"Lower the core once, snapshot `mod`, roll back per program" fails on
three structural facts (full inventory: the 2026-08-08 mod-mutation
audit; summarized here because each item is a design constraint):

1. **Core lowering is whole-program coupled.** User code changes how
   core lowers: call-site param-type observation feeds core fn
   signatures (`collect_param_type_observations`), `mark_fn_overload_groups`
   stamps `typed_overload` onto core AST nodes when a user def shares a
   name/arity, ivar offsets accumulate across reopens into the class
   layout sidecar, the return-type fixed point sweeps all inferable
   methods, `collect_extern_var_refs` decides global demotion from
   whole-program reads, monomorphization instantiates from user usage,
   and `exact_tag_name_subclassed?` memoizes an answer that a user
   subclass invalidates. A core snapshot taken under program A is
   semantically wrong for program B.

2. **The post-lowering passes destructively rewrite shared WIRE.**
   `content_hash_pass` deletes deduped functions, renames the rest to
   content symbols and marks them `llvm_internal`, and rewrites
   instruction operands and the `known_*` maps in place. Free insertion
   is not idempotent (a second run double-frees). SSA rewrites blocks in
   place. Release mode strips debug metadata irreversibly. Reusing a
   lowered core requires either deep-copying `functions` per program or
   restructuring these passes to run on per-program copies.

3. **Symbols are program-dependent.** Compact `__wy_` names derive from
   the module-wide hash set and everything is `define internal`
   (functions, `@global.*`, `@.ic`, memo tables, reuse slots), so a
   cached prelude object exports nothing and its names aren't stable
   across programs anyway.

## Known bugs found during the audit (fix independent of this project)

- `emitter.w` process-global metadata state leaks across compiles in one
  process: `novec_md_state` accumulates loop-metadata nodes forever
  (bloat), and `ewscope_md_state` caches alias-scope lists keyed by
  `mod[:next_fuse_site]` ids that restart at 0 per module — under
  `compile-batch`, program 2's fused loops can REUSE program 1's
  `!alias.scope`/`!noalias` lists. Miscompile hazard. Fix: reset both at
  emission entry.
- `compile-batch` derives its runtime-objects output path from the first
  input file's directory (`ar: spec/numeric/runtime.a`) and rebuilds the
  runtime instead of using the cached dev archive; currently slower than
  sequential `compile` and broken outside the repo root layout.
- `compiler.w` sets `mod[:no_static_slab]` after `lower_ast` returns,
  but lowering reads it — the flag is dead as wired.

## Phased plan

**Phase 0 — correctness (small, land first):** emitter metadata-state
reset per emission; `compile-batch` runtime pathing + cached-archive
reuse. Gates: forced identity, battery, and a batch-vs-solo `.ll`
byte-compare oracle over a spec shard.

**Phase 1 — prelude-stability contract (the real work):** make core
lowering independent of user code, behind a flag, by contract:
- no param-type observation from user call sites into core fns
  (`TUNGSTEN_PARAM_INFER` already exists as a lever and cache key);
- overload-group marking, duplicate checks, and the return-type fixed
  point scoped to (core, user+boundary) instead of the flat list;
- ivar-offset layouts of core classes frozen (user reopens that add
  ivars to core classes → fall back to monolithic compile);
- `extern_var_refs` demotion decided per module;
- `exact_tag_subclassed`/`prepared_class_bodies` recomputed per program
  (cheap) rather than snapshotted.
Program-context triggers that force monolithic fallback: subclassing or
reopening a core class, generics instantiating core templates, build
defines / math mode divergence.

**Phase 2 — in-process reuse:** with Phase 1's contract, warm a curated
core union once per process; per program: append user expressions, run
the (now decoupled) user-side analyses, lower user code only, deep-copy
or copy-on-write the function list for the destructive passes, emit.
Oracle: batch-vs-solo byte-identical `.ll` across the whole spec corpus.

**Phase 3 — cross-process and parallel:** stable prelude symbol names
(skip compaction for the warm set, pin linkage) enable a cached prelude
object so clang sees only user code; deterministic pre-assigned ID
ranges (strings, block ids, IC slots) make method-level lowering
parallelizable AND order-independent — same bytes serial or parallel,
which is what stage identity requires (stage 0 has no threads).

## What already landed

- Spec battery parallelized (11min → ~3min under load; FAST tier ~3s);
  aggregation is deterministic and lane-collision-safe.
- Phase timing instrumentation exists (`--verbose`), and the per-spec
  cost model above is reproducible from it.
