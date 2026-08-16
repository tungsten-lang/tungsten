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

**Stage 0 — correctness (small, land first):** emitter metadata-state
reset per emission; `compile-batch` runtime pathing + cached-archive
reuse. Gates: forced identity, battery, and a batch-vs-solo `.ll`
byte-compare oracle over a spec shard.

**Stage 1 — prelude-stability contract (the real work):** make core
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
reopening a core class and generics instantiating core templates. Lowering
options such as fast/precise math, slab mode, method locking, and build defines
are exact compatibility-key variants rather than structural fallbacks.

`Tungsten.PROTECT_THE_CORE!` now implements the Stage-1 ownership boundary in
the type-facts branch. It partitions registration and SCC inference, permits
only Core-to-Core parameter observation, exports Core globals independently of
user reads, attaches declaring-file provenance to generated WIRE workers, and
emits a deterministic Core ABI fingerprint. Unsupported program contexts are
reported as explicit monolithic fallbacks. This establishes compatibility and
correctness metadata; it intentionally does **not** claim a compile-time win
until Stage 2 reuses the lowered partition.

**Stage 2 — in-process reuse:** with Stage 1's contract, retain each exact
lowered Core closure once per compiler process. A cache miss lowers Core and
the program normally, completes every destructive mid-end pass, then freezes
the selected post-pass Core functions below a WIRE-arena watermark. A hit
rewinds only the fresh overlay, attaches those immutable functions, relowers
Core top-level startup plus the program, and skips mutation-oriented passes for
the frozen prefix.

There is deliberately no deep copy or copy-on-write graph. `PROTECT_THE_CORE!`
is the ownership promise that makes the cached functions immutable; a program
that cannot satisfy the stable ABI contract takes the monolithic path. Multiple
exact closures may coexist in one process. The retained high-water mark is
process-wide, so a new closure currently retains some miss-program overlay
records along with its Core cohort. That is bounded for the common one-closure
spec batch, but should become a compact Core-only arena image in Stage 3.

The in-process key is built from the sorted Core manifest. Every file row
contains path, nanosecond mtime, ctime, size, and a content digest; digests are
memoized while that stat tuple is unchanged. The key also covers lowering and
release modes, closed-world contracts, build defines, relevant environment
options, target selection, and the AST schema. A hit still recomputes and
checks the Stage-1 Core ABI fingerprint before emission.

**Stage 3 — cross-process artifacts, then parallel:** persist the immutable
Stage-2 Core cohort so a fresh compiler process can reconstruct it before
lowering the entry program. The first implementation is a checksummed logical
graph snapshot, not a raw arena mmap: current packed WIRE fields still point at
heap Strings, Arrays and Hashes. The format preserves sharing/cycles among
those containers, rebuilds WIRE into the arena, rejects every other heap type,
and publishes with fsync plus same-filesystem rename. It is scoped by exact
compiler-executable metadata; the ordinary Core key still covers source
path/mtime/ctime/size/content, lowering modes, target, contracts and schema.

A later fully packed Core template can replace reconstruction with mmap. Stable
prelude symbol names and a cached bitcode/object partition can then keep Core
out of user emission and clang. Deterministic pre-assigned ID ranges (strings,
block ids, IC slots) make method-level lowering parallelizable and
order-independent — same bytes serial or parallel, which is what stage identity
requires (stage 0 has no threads).

## What already landed

- Spec battery parallelized (11min → ~3min under load; FAST tier ~3s);
  aggregation is deterministic and lane-collision-safe.
- Phase timing instrumentation exists (`--verbose`), and the per-spec
  cost model above is reproducible from it.
- Stage 0 is implemented: emission resets loop/alias metadata per module,
  `compile-batch` uses correct scratch/runtime object paths, and
  `scripts/batch_vs_solo_oracle.sh` compares fresh-process and batch `.ll`.
- Stage 2 is implemented behind `PROTECT_THE_CORE!`: `compile-batch` retains an
  immutable post-pass Core WIRE cohort, uses manifest/stat/content identity for
  invalidation, and preserves cold-vs-warm `.ll` and symbol-sidecar bytes.
- The first Stage-3 artifact is implemented: a fresh native compiler process
  can load the frozen Core graph from the selected compiler cache. Corrupt,
  incompatible, or structurally invalid snapshots fail closed and are rebuilt.
- Release/LTO batches compile the shared runtime once into a private object
  bundle and pass its objects directly to each link. This avoids macOS `ar`
  dropping LTO-bitcode members when native bridge objects are also present.

## Stable Core ABI contract

`Tungsten.PROTECT_THE_CORE!` is the Stage-1 boundary. It is a prospective,
program-wide declaration: the complete source graph promises not to replace or
reopen canonical Core definitions. The parser already records declaring-file
provenance in its sparse AST metadata, so the earlier experimental Loader-owned
origin sidecar and `TUNGSTEN_INCREMENTAL_LOWERING` switch are obsolete.

Protected lowering partitions Core from program expressions, reaches Core
return facts before analyzing the program, prevents program call sites from
specializing Core parameters, and publishes every Core global that a cached
artifact may expose. It then emits `core_abi_hash`, a deterministic fingerprint
covering callable signatures, class layouts, exported globals, math/fast/slab
variants, build defines, and the type/method closure contracts.

The fingerprint is the cache compatibility key, not file provenance itself.
Source content, compiler/runtime identity, target, and dependency mtimes remain
manifest inputs. On a cache lookup, all of those inputs must match and the
cached artifact's ABI fingerprint must equal the program's requested Core ABI.
Unsupported shapes retain ordinary semantics by selecting an explicit
monolithic fallback, including user subclasses of Core classes, Core generic
specialization, global collisions, and `constant_alias` coupling.

`scripts/test-incremental-lowering-contract.sh` verifies that two different
programs with the same protected Core produce the same canonical ABI and hash,
that a lowering-mode variant changes the key, and that a structurally coupled
program falls back. `scripts/test-incremental-core-cache.sh` additionally checks
miss/hit/multi-cohort behavior, exact manifest keys, the disabled path, and
byte-identical LLVM and symbol sidecars against fresh compiler processes. It
also links and executes independent release binaries for a miss and a hit.

## Stage-2 benchmark

On 2026-08-16, `scripts/bench-incremental-core-cache.sh` was run as five
alternating cache-off/cache-on pairs over 150 copies of the protected
`core_abi_stable_b.w` fixture. Every compile used
`--release --native --fast --no-debug --emit-ll --ll`; the median wall time was
47.969s without Core reuse and 35.802s with it: 12.167s saved, 25.36% faster,
or 1.340x throughput.

One instrumented 150-file pair attributed the change as follows: lowering
13.680s -> 4.680s, CFG/SSA 1.860s -> 0.011s, free insertion 0.354s -> 0.002s,
and content hashing 5.377s -> 2.285s. Emission regressed 9.202s -> 13.189s,
leaving a clear follow-on target even though aggregate compiler time improved
41.206s -> 29.273s in that profiled pair. These numbers measure a homogeneous
protected-Core batch, not arbitrary single-file compilation.

## Stage-3 persistent-WIRE benchmark

On 2026-08-16, `scripts/bench-persistent-core-cache.sh` ran twelve alternating
fresh-process pairs over `core_abi_stable_b.w`, using
`--release --native --fast --no-debug --emit-ll --ll`. The snapshot was warmed
outside the measured pairs. Median wall time fell from 0.463063s with the disk
cache disabled to 0.360221s with a persistent Core hit: 0.102842s saved,
22.21% faster, or 1.285x throughput. The snapshot for this 929-function Core
closure was 4,568,417 bytes. Cold and warm LLVM were byte-identical. This
measures compiler front-end/artifact generation for one protected fixture; it
does not include clang/link work and is not a claim about unprotected programs.

## Cached Core code experiment (not retained)

On 2026-08-16, a follow-on prototype split the 929 stable Core functions into
a cross-process LLVM bitcode module with hidden, content-derived symbols. The
per-program module retained the globals and startup code, and both modules
entered the ordinary release LTO link.

Keeping FullLTO preserved runtime optimization, but eight alternating matched
build pairs were effectively flat: 11.605832s monolithic versus 11.584335s
with cached Core bitcode, only 0.19% faster. FullLTO still combines and
optimizes the complete program, so avoiding one textual parse was not the
dominant cost.

ThinLTO plus ld64's module cache made the warm link much faster (10.96s to a
3.74s median in the initial repeated probe), but created a real code-quality
boundary. Ten alternating runtime pairs regressed the String empty-slice path
from 3.9519 to 5.1534 ns/op (+30.4%) and its inline-five-byte path from 21.5646
to 22.5688 ns/op (+4.7%). Bignum multiply/divide and the boolean sieve were
neutral, demonstrating that a narrow arithmetic screen would have missed the
regression. Raising ThinLTO's import-instruction budget as high as 250,000 did
not restore the String fast path.

The bitcode-cache implementation was therefore removed. A useful code cache
needs either profile-guided boundary selection or a smaller emitted Core
closure. Function-level Core reachability is the next experiment because it
reduces FullLTO input without preventing any reachable Core/runtime inlining.

## Closed-world Core reachability

The retained follow-on emits only the Core function closure reachable when a
program declares both `PROTECT_THE_CORE!` and `LOCK_THE_DOORS!`. Every program
function is a root. The pass then follows direct calls, closure bodies, function
addresses, memo workers, constructor/devirtualization targets, and the Core
method registrations matching literal dynamic sends. It also retains runtime
language hooks such as arithmetic, indexing, construction, `to_s`, comparison,
and `method_missing`.

Reachability fails closed. Live reflective method-table access or an opaque
runtime-dispatch call selects the complete Core cohort. An external C source
named by `TUNGSTEN_C_INCLUDES` may call runtime dispatch using a computed method
name, so that boundary conservatively retains every registered Core method.
Unregistered helpers can still be pruned. Registration pruning is an
emission-only view: the complete post-pass Core graph is restored before the
persistent WIRE cache is finalized.

On 2026-08-16, eight alternating forced build pairs compiled the pure Tungsten
`benchmarks/big_math/program_loops.w` workload with
`--release --native --fast --no-debug`. Median wall time fell from 11.219948s
with complete Core emission to 10.388879s with the reachable closure: 0.831069s
saved, 7.41% faster, or 1.080x throughput. The emitted LLVM shrank from
1,662,552 to 492,728 bytes (70.36%) and from 992 to 221 definitions; 161 of 929
Core functions were retained.

Eight alternating runtime pairs had identical checksums. Four principal bignum
kernels moved between -0.01% and +0.16%, which is neutral at this sample size;
one sign-chain kernel was 6.25% faster, plausibly from layout, but is not treated
as a general runtime claim. Longer String screens also avoided the earlier
ThinLTO regression: empty-slice improved 2.60% over twenty pairs and the
inline-five-byte path improved 1.84% over fifteen pairs.

The C-assisted native bignum lane deliberately showed no build win: six
alternating pairs measured 11.170s with full Core and 11.215s with reachability
(0.40% slower). Its C bridge triggers the conservative external-dispatch rule
and keeps 909 of 929 Core functions. The retained claim is therefore a
closed-world pure-Tungsten build improvement, not an FFI-wide speedup.
