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

## Cached content-hash work set

A persistent Core hit already supplies canonical hashes for every frozen Core
function. The content-hash pass now keeps those hashes in its complete symbol
map, but excludes the frozen bodies from call-graph construction and
topological ordering. This preserves compact symbols and symbol sidecars
exactly. A cold miss still hashes the complete Core closure before publishing
it, and `TUNGSTEN_LAZY_CONTENT_HASH=0` retains the former full-graph path for
matched comparisons.

On 2026-08-16, twenty alternating artifact-only pairs compiled
`benchmarks/big_math/program_loops.w` with
`--release --native --fast --no-debug --emit-ll`. The final self-hosted
candidate reduced the median from 0.311802s to 0.310317s: 1.485ms saved, 0.48%
faster, or 1.005x throughput. A phase probe reduced content hashing from 10ms
to 8ms by shrinking its graph work set from 949 functions to 20. LLVM and the
symbol sidemap were byte-identical with the optimization disabled and enabled.

As expected, eight alternating full native-link pairs were flat: 10.399720s
before and 10.400036s after (a 0.003% difference). The optimization is retained
as a small, exact-output frontend cleanup; it does not claim a measurable
whole-build improvement under FullLTO.

## In-process parsed-file cache

`compile-batch` now retains a pristine, unflattened slab AST for each parsed
source file. A new Loader deep-clones that AST before import expansion and
lowering, so program-specific analysis cannot mutate the cached template. The
cheap hit gate compares path, nanosecond mtime, ctime, and size. If metadata
changes, Loader reads the source as it would on a miss and compares a content
fingerprint; identical bytes update the stat tuple without lexing or parsing,
while changed bytes replace the entry. `TUNGSTEN_FRONTEND_PARSE_CACHE=0`
disables reuse for A/B and diagnosis.

This tranche is intentionally process-local. It accelerates the spec suite's
single `compile-batch` process without introducing a second persistent AST
format. A later cross-process cache can reuse the same manifest policy once it
can reconstruct packed AST nodes, bodies, sparse metadata, and location-file
state safely.

On 2026-08-16, five alternating pairs compiled 150 copies of
`compiler/test/fixtures/core_abi_stable_b.w` with
`--release --native --fast --no-debug --emit-ll`; the persistent Core WIRE
snapshot was populated before every measured series. Median wall time fell
from 35.923276s to 32.833317s: 3.089959s saved, 8.60% faster, or 1.094x
throughput. A separate 150-program peak-memory pair measured 9,927,491,584
bytes without parse reuse and 8,009,711,616 bytes with it, saving 1,917,779,968
bytes (19.32%).

The cache is enabled only by `compile-batch`; ordinary single-file compilation
does not retain a pristine clone. Twenty alternating single-file artifact pairs
were neutral at 0.296550s before and 0.295843s after (-0.24%, within noise).

Cache-off/on LLVM and symbol sidecars were byte-identical. The broader
eight-program batch-vs-solo oracle also matched fresh-process LLVM for fusion,
bignum, typed overload, rational, loop, and math-mode fixtures. A focused
compiled-runtime test covers stat hits, same-content fingerprint hits, and
real-content invalidation.

## In-process rendered Core-function cache

Even after Core reachability and parsed-AST reuse, `compile-batch` rendered the
same immutable Core WIRE bodies into LLVM text for every entry program. The
emitter now retains each eligible Core function's rendered text in process and
replays it into the next program's single monolithic LLVM module. This avoids
repeated emitter work without splitting the module or weakening FullLTO's
whole-program view. `TUNGSTEN_FUNCTION_EMIT_CACHE=0` restores direct rendering
for matched comparisons.

The cache is deliberately narrower than "memoize emit_function":

- Its bucket key includes the lowered-Core identity, target layout/triple,
  host function attributes, frame policy, architecture-dependent selection,
  static-slab mode, and floating-point mode.
- A cache entry records every raw string-pointer id discovered while rendering;
  hits replay those dependencies before string constants are emitted.
- Functions carrying render-order-numbered loop or fused-elementwise alias
  metadata bypass reuse. Their metadata ids still come from the ordinary
  deterministic module-order renderer.
- Debug modules bypass the cache completely. Frame-pointer debug builds retain
  `noinline`, disabled tail calls, and unwind-table attributes for source
  backtraces.

On 2026-08-16, five alternating cache-off/on pairs compiled 150 copies of
`compiler/test/fixtures/core_abi_stable_b.w` with a prewarmed persistent Core
snapshot, parsed-AST reuse enabled, and
`--release --native --fast --no-debug --emit-ll`. Median wall time fell from
31.568724s to 23.703029s: 7.865695s saved, 24.92% faster, or 1.332x throughput.
After the first entry populated the render bucket, each subsequent program
reused 928 Core functions while three context-dependent or program functions
bypassed it.

A separate 150-program peak-memory pair measured 8,009,416,704 bytes without
render reuse and 5,934,071,808 bytes with it, saving 2,075,344,896 bytes
(25.91%). Retaining one canonical copy of each rendered Core body is much
smaller than repeatedly allocating and discarding those bodies while the
batch's AST/WIRE arenas remain live.

Cache-off/on LLVM and symbol sidecars were byte-identical for two distinct
entry programs sharing a Core artifact. A closed-world bignum fixture likewise
matched exactly while reusing 161 reachable Core functions. The focused test
also proves that debug emission bypasses reuse and retains its physical-frame
attributes.

## Deterministic parallel batch emission

Entry programs are independent after the compiler executable and persistent
Core artifact are available; functions inside one lowering are not. They share
module counters, class tables, and the AST/WIRE arenas. `compile-batch` now
parallelizes at that safe boundary: it assigns contiguous source shards to
long-lived child compiler processes, each child parses/lowers/emits its shard,
and the parent retains runtime compilation and source-order linking. This
preserves the one-runtime-per-batch property and avoids making shared mutable
lowering state concurrent.

Workers write to parent-assigned private LLVM paths, return only complete files
with `.done` markers, and keep symbol sidecars at their ordinary source-derived
paths. The parent waits for every worker, replays stdout/stderr in shard order,
then scans and links LLVM in original source order. Thus scheduling changes
wall time, not artifacts or observable ordering. `--jobs N` selects an exact
worker count; `TUNGSTEN_BATCH_JOBS` supplies the same policy by environment,
and `TUNGSTEN_BATCH_PARALLEL=0` forces the serial path.

Auto mode uses roughly one worker per 16 entries, capped by the file count,
logical CPUs, and eight workers. Small batches therefore stay in process. The
driver also stays serial for stage-0 execution, duplicate source paths,
`--emit-wire`, AST statistics, caller-owned LLVM/Metal paths, source-adjacent
`--ll`, and single-file diagnostic reports such as `TUNGSTEN_SSA_REPORT`.

On 2026-08-16, five alternating pairs compiled 150 copies of
`compiler/test/fixtures/core_abi_stable_b.w` with prewarmed Core WIRE and
`--release --native --fast --no-debug --emit-ll`. The already-optimized serial
median was 23.849750s; eight deterministic workers took 3.432063s, saving
20.417687s (85.61%, 6.949x throughput). Single probes showed the scaling curve:
23.85s at one worker, 11.74s at two, 6.13s at four, and 3.43s at eight.

Aggregate peak RSS rose from the rendered-cache serial measurement of
5,934,071,808 bytes to 6,363,103,232 bytes with eight workers: 429,031,424
bytes, or 7.23%. This is bounded because every worker retains only its shard's
ASTs; it is not eight copies of the serial batch high-water mark.

A separate three-pair, 32-program standalone-binary lane used
`--release --native --fast --no-debug --no-lto`. Four workers reduced the
median from 32.528178s to 29.056358s (10.67%, 1.119x), with source-order linking
left serial. That smaller whole-build gain identifies the next bottleneck:
object/link reuse, not more unsafe concurrency inside lowering.

Serial and parallel LLVM plus symbol sidecars are byte-identical in release and
debug modes. Focused coverage also verifies debug frame attributes, zstd slab
rewriting, deterministic diagnostics on stderr, and parent-linked standalone
executables.

## Cross-process native Core object experiment (not retained)

Reachability made a native Core object worth retesting: the bignum program now
emits only 161 of 929 Core functions. A prototype partition kept the 33-function
program-reachable Core closure in the ordinary LLVM overlay and precompiled the
remaining 128 cold functions plus 19 private helper dependencies into one
native object. LLVM verification proved that the hidden-symbol object and
overlay rejoined correctly, with no duplicated mutable globals.

The build-time result was too small for the code-quality cost. Six alternating
`--release --native --fast --no-debug` link pairs measured 10.647425s for the
current all-bitcode FullLTO link and 10.504489s with the cached native Core
object: 1.34% faster. Fifteen alternating runtime pairs then regressed the
bignum `wordchain4` lane from 5.6601 to 6.4463 ns/op; the paired median was
12.65% slower. Checksums remained identical.

An empty unrelated native object reproduced the regression. On the tested
Apple clang/ld64 FullLTO path, merely mixing a native object into the link made
the generated program retain calls to `w_bigint_add_word_dest` and
`w_bigint_sub_word_dest` that the all-bitcode link inlined. The empty-object
lane was 14.09% slower by paired median. This is a linker-pipeline boundary,
not a bad Core partition. ld64's `-cache_path_lto` was also flat for FullLTO
(10.48s cold, 10.55s warm) and produced no reusable incremental entries.

The native-object path is therefore not retained. Release builds remain
all-bitcode through FullLTO; the persistent WIRE, reachability, rendered-text,
and final-binary caches provide reuse without weakening runtime optimization.

## Standalone executable visibility

Ordinary Tungsten executables now publish only `main`. Tungsten functions and
classes were already emitted with internal linkage, but the link driver still
passed `-export_dynamic`/`-rdynamic`, which kept roughly 1,100 C runtime entry
points in the dynamic symbol table and made them externally observable LTO
roots. The compiler's `--jit`/`--hot` host is the intentional exception: JIT
snippets omit the runtime and resolve `w_int`, `w_add`, and related symbols from
the host process. The driver detects that host from its emitted call to
`w_jit_load_object`; custom embedding hosts can opt in with
`TUNGSTEN_DYNAMIC_EXPORTS=1`.

Six alternating `benchmarks/big_math/program_loops.w` builds with
`--release --native --fast --no-debug` measured 12.065963s with the old export
contract and 9.942978s with hidden standalone visibility, a 17.59% wall-time
reduction. The clang/FullLTO phase fell from 11.7285s to 9.6090s (-18.07%). A
representative binary shrank from 2,993,128 to 2,513,448 bytes (-16.03%), and
its export trie fell from roughly 1,099 runtime symbols to `main` only. The
input LLVM was byte-identical; this is solely a final-link contract change.

Longer matched runtime screens found no code-quality cost. Paired medians were
5.06% faster for bignum `wordchain4`, 0.35% slower for `addmul`, and 0.86%
faster for the five-byte String slice lane. The initially noisy empty-slice
lane was rerun as 24 drift-cancelling ABBA blocks (48 samples per binary, 50
million operations each) and was 1.33% faster. All checksums matched. Focused
contracts also verify that a no-LTO C-FFI program links with only `main`
exported, while an auto-detected JIT host still exports and resolves `w_add`.

## Release frame and inlining experiments (not retained)

Release emission already strips source call-site metadata, omits debug
`noinline`, and leaves LLVM free to inline and perform sibling-call
elimination. An explicit tail-position prototype marked 106 direct calls as
`tail` instead of 14. The normalized machine-code text was nevertheless
byte-identical: LLVM had already converted every profitable call/return pair
into the same frame-popping branch. The hinting code was removed.

Forced inlining also lost to LLVM's cost model. Marking the 663 internal
self-compiler helpers with at most four WIRE instructions `alwaysinline`
slowed twelve protected-bignum compiler pairs by 0.49% and six self-compile
pairs by 0.38% (paired medians). Expanding the threshold to eight instructions
marked 1,121 helpers, slowed four self-compile pairs by 0.63%, and grew the
compiler from 8,055,776 to 8,118,328 bytes (+0.78%). Outputs remained
byte-identical, but neither policy is retained.

Debug builds keep the opposite explicit contract: frame pointers, unwind
tables, `noinline`, and `"disable-tail-calls"="true"`. Thus release code gets
LLVM's existing frame elimination while `--debug` continues to preserve
physical Tungsten backtrace frames.

## Embedded LLVM and LLD trial (not retained)

The external driver boundary is not the dominant release cost. On this host a
warm Homebrew clang process starts in 15.6ms and ld64 in 11.1ms, together about
0.3% of an 8.9s FullLTO link. Embedding libLLVM while retaining the same linker
can remove that startup, but not the optimization and code-generation work.
Replacing the complete clang/FullLTO pipeline in-process would instead assume
responsibility for target initialization, runtime bitcode composition, SDK
selection, LTO policy, diagnostics, and every supported cross target.

The available ld64.lld path was tested as the less invasive LLVM-owned linker
experiment. Four alternating pairs on byte-identical bignum LLVM reduced wall
time from 8.891723s to 8.696582s (2.20%; 2.71% by paired median), but enlarged
the text segment by 0.88%, regressed `wordchain4` by 4.93%, and regressed
`addmulchain4` by 0.86%. It also warns that Tungsten's 128MB `-stack_size`
contract is unimplemented. LLD is therefore not enabled, and no embedded-LLVM
integration is retained.

## Internal fastcc experiment (not enabled by default)

The existing `TUNGSTEN_LLVM_FASTCC=1` planner rewrote 1,634 eligible internal
compiler functions and 13,695 matching direct calls in the self-hosted
compiler. Twenty protected bignum artifact pairs were flat (0.144s median
compiler phase both ways), while eight self-compile pairs improved only 0.56%
wall and 1.02% compiler phase. That is below a useful acceptance threshold on
this host, so `fastcc` remains an explicit experiment rather than a default ABI
choice.

## Reproducible compiler PGO profile

`bin/tungsten build --pgo` now uses the source-controlled
`compiler-pgo-v2` corpus instead of training only on one compiler rebuild. Four
individual `--emit-ll` runs cover self-compilation, protected numeric lowering,
String lowering, and debug/frame-pointer emission. A deterministic eight-file,
one-worker batch additionally covers persistent Core hits, parsed AST reuse,
rendered-function reuse, locked class sets, SCC returns, and no-raise lowering.
Avoiding target links makes this broader training phase cheaper than the old
single training build.

The retained profile was measured against the same non-PGO release compiler:

- Twenty-four alternating warm protected-bignum artifact pairs fell from
  0.316792s to 0.288104s wall (-9.06%); measured compiler time fell from
  0.1710s to 0.1485s (-13.16%).
- Eight alternating self-compiler artifact pairs fell from 4.047773s to
  3.194056s wall (-21.09%); measured compiler time fell from 3.4095s to
  2.6445s (-22.44%).
- Five alternating 150-file, eight-worker batch pairs fell from 3.661236s to
  3.196275s (-12.70%).

PGO changes the compiler executable only. Before/after self-compiler LLVM was
byte-identical (SHA-256 `5cd770f8...`), bignum LLVM was byte-identical
(`281e6c71...`), and all 150 batch artifacts matched byte for byte. The profile
remains an explicit build choice because producing the instrumented and
optimized compiler adds release-build time; installed target programs do not
inherit the compiler's profile.

## Content-addressed final-link artifacts

The existing incremental binary cache can skip the entire pipeline when one
source/output-path manifest is unchanged. A second cache now operates after
emission: it keys the final executable by the emitted LLVM bytes, compiler and
linker identities, target/profile flags, runtime mode, optional link flags,
and runtime source/artifact mtimes. A different `-o` path, an mtime-only edit,
or a batch entry with identical release IR can therefore reuse the exact
previous FullLTO result without creating an object or ThinLTO boundary.

Six alternating `benchmarks/big_math/program_loops.w` pairs used explicit LLVM
paths and distinct output paths so the earlier source/path cache could not
intervene. With `--release --native --fast --no-debug`, median wall time fell
from 8.860400s to 0.358592s (-95.95%; -95.98% by paired median). The measured
clang/link phase fell from 8.5725s to 0.0685s (-99.20%). Emitted LLVM was
byte-identical (SHA-256 `281e6c71...`), runtime checksums matched, and cached
outputs are copies of the previously linked executable.

Four alternating cold-miss pairs measured the cost of computing and publishing
the content identity: 8.827787s without the cache and 8.902434s with it
(+0.85%; clang phase +0.75%). On already-cheap no-LTO links that bookkeeping
cost 8.03% across twelve pairs, so the cache is enabled by default only for
LTO builds. `TUNGSTEN_LINK_CACHE=1` opts a non-LTO workflow in, and
`TUNGSTEN_LINK_CACHE=0` disables it for diagnosis.

The cache fails closed for `TUNGSTEN_C_INCLUDES` until arbitrary C header
graphs have depfile tracking. Focused contracts cover changed output paths,
mtime-only source changes, explicit disable, dynamic-export separation,
runtime-artifact invalidation, FFI bypass, and executable identity. The shared
cache GC ages these reproducible `linkbin-*` artifacts like the existing Core,
AST, runtime, and final-binary entries.
