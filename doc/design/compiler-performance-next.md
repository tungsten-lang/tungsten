# Compiler performance: next tranches

This branch evaluates ten requested compiler-throughput opportunities plus one
retained WIRE-builder tranche discovered while pursuing them. Each tranche
must preserve generated LLVM for representative inputs, retain exact
self-hosting fixed point where it applies, pass focused checks, and earn its
place with matched `--release --native --fast` measurements. Release already
selects the non-debug profile; `--no-debug` is not required. A
negative or noise-flat experiment is documented and reverted rather than
silently accumulated.

## Target probe cache

Target layout, function attributes, and native Arm CPU flags previously
started three short-lived compiler subprocesses for every independent compile.
They now use one exact-key process cache followed by a checksummed, atomic disk
record in the compiler cache directory. Disk entries expire on the next local
civil day. `TUNGSTEN_TARGET_CACHE=0` disables both levels;
`TUNGSTEN_TARGET_DISK_CACHE=0` retains only process memoization.

The key includes the selected C compiler, cross target, resolved architecture
arguments, and the corresponding target environment. A configuration change
therefore misses immediately; the one-day lifetime bounds changes to an
auto-selected compiler without adding a compiler-version subprocess on every
lookup. Malformed or incomplete records fail closed.

Eight alternating full self-compile pairs were noise-flat end to end: median
wall time was 3.9172 s disabled and 3.9148 s warm (-0.06%), while the target
detection stage itself fell from a 46 ms median to 0 ms. On the intended
many-process workload, ten alternating blocks of fifteen tiny native compiles
(150 per mode) took 26.0202 s disabled versus 15.5718 s warm, a 40.15%
reduction (173.5 ms to 103.8 ms per compile).

## Persistent packed AST cache

Compiled compiler processes now persist pristine per-file ASTs rather than
limiting parse reuse to one `compile-batch` worker. A small manifest contains
the exact compiler executable identity, AST schema hash, path, stat tuple, and
content fingerprint. An unchanged file therefore needs one small metadata
read and one source read before its packed graph is restored into the current
process's AST store. The source rebuilds the lexer's compact process-local
line/column table; deserialization rebases matching `FileOffset` locations
from the producing process's file ID to the new one. A metadata-only touch
fingerprints the source, then reuses the same payload. Corruption, a compiler
rebuild, a schema change, or a content change is an ordinary parse miss.

The checksummed graph format reconstructs node and body handles rather than
copying arena offsets. It preserves shared nodes, Arrays/Hashes and cycles,
sparse and typed sidecars, inline and singleton leaves, byte-addressed
interned leaves, and canonical decimal BigInts. Payload and manifest writes
are atomic, with the manifest published last.

Disk snapshots default to files of at least 16 KiB; smaller files are faster
to parse and still use the existing process cache. The threshold can be
changed with `TUNGSTEN_FRONTEND_DISK_CACHE_MIN_BYTES`, while
`TUNGSTEN_FRONTEND_DISK_CACHE=0` disables persistence. The 16 KiB cutoff made
the already process-cached, eight-worker 150-program batch neutral (2.2840 s
disabled versus 2.2855 s warm, -0.07%); caching every file had regressed it by
1.43% through tiny payload reads.

Eight alternating full self-compile pairs with the 16 KiB cutoff reduced
median load+parse from 0.497 s to 0.241 s (-51.51%) and external wall time
from 3.71 s to 3.42 s (-7.82%). The post-load compiler stages were noise-flat
in that sample (3.133 s to 3.104 s). Every paired LLVM file was byte-identical,
as were cache-disabled/cold/warm full compiler outputs. Exact self-host fixed
point also held at SHA-256 `21ae636cfd41d86668a2b8d699231a1598fa9bfec64e89b008a7b2a81aec6692`.

## One-pass program index

Lowering previously performed independent recursive AST walks to discover
nested-scope references that require a top-level global mirror and uses of
ARGV/builtin runtime classes. It also rescanned the top-level stream to find
runtime classes and parameter-inference candidates, then rebuilt the same
locked-world function/method definition map for return-class and no-raise
summaries.

The retained `ProgramIndex` uses the generated AST child schema to collect the
deep facts in one traversal, including nested pair structures such as
interpolation parts and `elsif` arms. Its top-level subsets feed class ordering
and parameter candidate discovery, and the two locked-world analyses share one
definition index. `TUNGSTEN_PROGRAM_INDEX=0` retains the former independent
walks for comparison and diagnosis.

Eight alternating release/native/fast self-compile pairs reduced median
lowering from 1.4690 s to 1.4295 s (-2.69%), measured compiler time from
3.1775 s to 3.1335 s (-1.38%), and external wall time from 3.775 s to
3.715 s (-1.59%). Every paired LLVM file was byte-identical. Focused parity
also covers ordinary, capture, `elsif`, generic-specialization, protected-Core,
and locked return-class programs; debug parity retains physical frame
attributes. Exact self-host fixed point held at SHA-256
`b31e5f316b10f1ba6600f9c0fc9a74710b3f8f6ff069d3341a1fcd409d2d27b9`.

## Fixed-slot lowering values

Every lowered expression previously returned a two-key Hash carrying its
machine representation and LLVM operand. These transient `{type, value}`
objects now use append-only WIRE kind 268 with the canonical ordinal layout
`:type, :value`. The constructor reserves exactly two fields, so it avoids a
heap Hash/table allocation while preserving the existing field API. This is a
deliberately narrow first use of fixed-slot lowering state; long-lived context
maps remain ordinary Hashes because their optional fields and child-context
copy semantics need a separate schema.

Six alternating release/native/fast self-compile pairs reduced median
lowering from 1.3925 s to 1.3855 s (-0.50%), measured compiler time from
3.0575 s to 3.0500 s (-0.25%), and external wall time from 3.6400 s to
3.6300 s (-0.27%). Retired instructions fell about 0.15%, while median peak
RSS fell about 39 MiB (2.56%). Every paired LLVM file was byte-identical.
Exact self-host fixed point held at SHA-256
`039f2a1b8deff342b4c992868e238f9d2048bf6bb88f6bbd9af61a35648c2d9a`.

A denser special-case representation that omitted the two field-symbol words
reduced another roughly 5 MiB, but the extra runtime access branches erased
the instruction benefit on the full self-compile. That variant was reverted;
the ordinary fixed-layout WIRE record is the retained balance.

## Early Core reachability

On a persistent Core WIRE hit, the cached cohort is already immutable and has
completed CFG, ownership, and free-insertion work. Closed-world reachability
now runs immediately after lowering for programs with both Core protection and
locked method tables. Escape analysis, content-hash graph construction,
release cleanup, and emission then see only the program plus reachable Core
closure. A cold miss deliberately retains the complete pipeline so the newly
published artifact is reusable by a different program.

Registration filtering remains after content hashing, preserving the existing
hash contract. The complete cached-Core function metadata is also retained as
a lightweight provenance input so the symbol sidemap remains byte-identical;
dead bodies do not re-enter call-graph or canonical-content work.
`TUNGSTEN_EARLY_CORE_REACHABILITY=0` retains the former late-only path.

Eight alternating warm artifact pairs for
`benchmarks/big_math/program_loops.w`, under release/native/fast with the
frontend and link artifact caches disabled, reduced median measured compiler
time from 102.0 ms to 93.5 ms (-8.33%). Escape analysis fell from 7 ms to
2 ms and content hashing/postprocessing from 10 ms to 6 ms as the work set
shrank from 949 to 181 functions. External artifact wall time was 210 ms to
200 ms at the timer's 10 ms resolution. LLVM and the complete symbol sidemap
were byte-identical.

The intended end-to-end claim is narrower: four final-candidate FullLTO build
pairs were flat at 9.195 s versus 9.230 s (+0.38%, noise), consistent with the
earlier six-pair 9.240 s versus 9.250 s result. Six bignum workload checksum
screens matched. Focused release and debug parity also proves that physical
debug backtrace attributes survive the early slice.
Exact self-host fixed point held at SHA-256
`347cc471eb65e8cec230d681be4d647ba966afebc4b6f568443c93c0268e9c6a`.

## Fixed WIRE function and block builders

Instructions were packed, but each function and basic block still began as a
temporary Hash passed through `wire_record`. Their append-only WIRE kinds now
have explicit source-level field schemas. One runtime bulk constructor fills
the canonical symbol/value pairs, creates the standard empty child
collections, and primes field-cache entries without allocating or walking a
temporary Hash. Module construction remains on the generic path: it happens
once per compile, while this tranche targets 4,000-plus functions and their
blocks.

Eight alternating release/native/fast self-compile pairs were wall-time
noise-flat. The median within-pair compiler delta favored fixed builders by
about 0.4%, and wall time by about 0.5%, but the between-run spread was larger.
The hardware counters were consistent: retired instructions fell about 0.27%
and peak RSS fell roughly 22 MiB (1.5%). Generated LLVM was byte-identical.
The retained claim is therefore reduced allocation and memory pressure, not a
material standalone compile-time speedup.

The native arena test validates all 25 function ordinals, boxed counters,
recycle-scope initialization, and block instruction storage. Compiler fixed
point held exactly at SHA-256
`7ba84ea636dd7a033b945d0a65ca59ff32f79fe585003e5e2d259538cc47de80`;
serial release/debug parity checks also passed with physical debug-frame
attributes intact.

## Dense content-hash temp table

Canonical function hashing previously assigned stable temporary ordinals
through a general String-keyed Hash. Lowering already mints ordinary WIRE
temporaries densely as `%t0`, `%t1`, and so on, so the native compiler runtime
now indexes those numeric suffixes directly in a per-function Array. Named
parameters, malformed names, and legacy producers retain a small Hash fallback;
first-seen canonical numbering and the unusual parameter/temp spelling
collision remain identical to the old representation.

Eight alternating release/native/fast self-compile pairs reduced median
content hashing from 299.5 ms to 285.0 ms (-4.84%). The complete measured
compiler moved only from 3.1925 s to 3.1830 s (-0.30%), and external wall time
was effectively flat at 3.805 s versus 3.800 s. Retired instructions fell
0.28% and median peak RSS fell about 3.5 MiB. Generated LLVM was byte-identical
in every pair. This is retained as a small composable mid-end improvement, not
claimed as a material standalone end-to-end speedup. Exact self-host fixed
point held at SHA-256
`df783b613f8d8d6cade3b968b3f426434f549a6de01baf615b1ddfed3adc76b2`;
the lazy-content-hash and linear postprocessing parity checks also passed.

## Persistent rendered Core functions

The existing release-only function emitter cache reused immutable Core bodies
inside one `compile-batch` worker. It now also persists one checksummed bucket
per exact compiler executable, lowered-Core key, target layout/triple,
attribute/frame policy, static-slab mode, architecture, and floating-point
mode. A fresh compiler process restores that bucket once, then uses the same
per-function hit path as the in-process cache. Atomic graph writes make races
safe; malformed, corrupt, or mismatched buckets are ordinary misses and are
repaired after rerendering. Debug modules still bypass rendered-text reuse, so
physical source-backtrace frames remain direct emitter output.

Five alternating pairs of 150 fresh release/native/fast compiler processes,
with lowered Core and target probes prewarmed outside both modes, reduced
median wall time from 36.944990 s to 28.318626 s. That saves 8.626364 s
(-23.35%, 1.305x throughput). The final LLVM and symbol sidecar matched
byte-for-byte in every pair.

On the protected bignum `program_loops.w` artifact path, eight alternating
pairs reused 161 Core functions. Median emitter time fell from 22.5 ms to
13.0 ms (-42.22%), measured compiler time from 92.5 ms to 83.5 ms (-9.73%),
and external wall time from 200 ms to 190 ms (-5.00%). Retired instructions
fell 7.34% and peak RSS about 2.8 MiB; LLVM and sidemaps were exact.

The unprotected full self-compile cannot use this cache and remained neutral:
eight pairs measured 3.0785 s versus 3.0825 s compiler time (+0.13%) and
3.665 s wall time in both modes, with unchanged retired instructions and RSS.
Exact self-host fixed point held at SHA-256
`477f77c032d06da8e364f022799f33e87d7fb349d1690b6c437e3a1e4b3c0fdf`.
Focused tests cover process and disk hits, corruption repair, exact LLVM and
sidemaps, debug-frame bypass, and interaction with early Core reachability.

## Direct-buffer instruction emission

The emitter previously built a fresh String for every WIRE instruction, then
immediately appended it to the function StringBuffer. Common fixed-shape
opcodes now append their pieces directly: loads/stores, pointer and GEP
plumbing, integer arithmetic/comparisons, ordinary direct calls, branches,
returns, and scope markers. AST intrinsics, inline caches, loop metadata, and
other complex renderers retain the established String-returning path. The
`TUNGSTEN_DIRECT_BUFFER_EMIT=0` switch restores that path for exact A/B checks.

Eight same-compiler alternating release/native/fast self-compile pairs reduced
median emitter time from 883.5 ms to 649.0 ms (-26.54%), measured compiler time
from 3.028 s to 2.774 s (-8.39%), and external wall time from 3.60 s to 3.35 s
(-6.94%). Retired instructions fell 6.22% and median peak RSS fell about
55.7 MiB. Every full-compiler LLVM file was byte-identical.

With rendered-function caching disabled so the emitter remained in the work
set, eight protected bignum artifact pairs reduced emitter time from 22 ms to
16 ms (-27.27%), compiler time from 90 ms to 85 ms (-5.56%), external wall
time from 190 ms to 180 ms (-5.26%), retired instructions by 4.47%, and peak
RSS by about 1.1 MiB. LLVM and symbol sidemaps were exact. Focused release and
debug parity additionally covers ordinary, protected-Core, locked class-set,
and bignum fixtures while retaining physical debug-frame attributes. Exact
self-host fixed point held at SHA-256
`9f51c3d27d50a208b575e1c748ebaa469198b9e26c20482865b711fb41302a4e`;
the process/persistent rendered-function cache test also passed on the direct
path.

## Deterministic parallel function emission

Once global lowering, inference, function ordering, and metadata discovery are
complete, ordinary WIRE functions are independent LLVM rendering jobs. The
emitter now assigns loop and alias-scope metadata serially, freezes the final
per-function flags, and hands functions to a bounded native worker team through
an atomic cursor. Each worker owns its StringBuffer and referenced-string set;
the parent concatenates results and merges sets in original function order.
LLVM and sidemaps therefore remain deterministic even though job completion
order is not.

Automatic mode requires at least 64 functions, uses the detected CPU count,
and caps itself at eight workers. `TUNGSTEN_EMITTER_JOBS` can select a value up
to 32, while `TUNGSTEN_PARALLEL_FUNCTION_EMIT=0` restores serial emission. A
rendered-Core cache bucket remains on its faster serial/cache-hit path. Debug
modules also stay serial so physical backtrace frames are produced directly,
and process-parallel `compile-batch` children suppress nested emitter teams.
The WIRE field lookup accelerator is thread-local; the arena itself is frozen
before worker creation.

This is a single-emission worker pool rather than a permanently parked runtime
pool. An ordinary compiler process has one large render phase, while repeated
program compilation already uses rendered-Core reuse and/or the deterministic
process pool. The measured thread-start cost was below the saved work even on
the 181-function bignum artifact, so a persistent pool would add lifecycle and
shutdown machinery without a demonstrated second use in the common path.

Eight alternating final-candidate self-compile pairs, using plain
release/native/fast and eight workers, reduced median LLVM emission from
685.5 ms to 344.5 ms (-49.74%), measured compiler time from 2.9475 s to
2.5985 s (-11.84%), and external wall time from 3.54 s to 3.19 s (-9.89%).
Peak RSS rose 0.58% and retired instructions 0.28%, reflecting the bounded
worker stacks and synchronization. All paired LLVM files and sidemaps were
byte-identical.

With rendered-function caching disabled, twelve protected bignum artifact
pairs reduced emission from 16 ms to 11 ms (-31.25%) and compiler time from
86.5 ms to 81.0 ms (-6.36%); wall time was flat at the timer's 190 ms
resolution. Focused checks cover 1/2/4/8-worker parity, release-without-
`--no-debug`, serial debug frames, direct-buffer emission, rendered-Core cache
interaction, and process-parallel batch compilation. Exact self-host fixed
point held at SHA-256
`5580cc198e96a292252078380d882eb2afa49236ca55b19966e8f64883b68c41`.

## Persistent non-Core library WIRE

Protected, locked programs can now reuse raw pre-mid-end WIRE for a contiguous
cohort of unchanged imported non-Core files. The cache begins at the exact
warmed-Core string/counter boundary, restores the cohort's functions, then
re-lowers its top-level startup while skipping definition bodies. Entry-file
definitions and statements lower normally. Restored functions still traverse
CFG/SSA, ownership, free insertion, content hashing, and emission, so this
removes source lowering without imposing an optimization or codegen boundary.

Eligibility is deliberately conservative. `PROTECT_THE_CORE!` and
`LOCK_THE_DOORS!` must both hold, the exact Core WIRE artifact must already be
warm, imported expressions must form a prefix, and startup must not create
functions outside definitions. Library generic specialization and ambiguous
cross-boundary fusion bypass reuse. The all-or-nothing cohort key includes the
compiler identity, stable Core ABI hash, AST schema, every library path/stat
tuple/content digest, callable signatures, class layouts, globals, return and
class-set facts, no-raise facts, raw-call ABIs, and the locked method/type
universe. Consequently an entry body-only edit may reuse the cohort, while any
library or relevant ABI/dependency change lowers it again.

Snapshots use the existing checksummed graph format and atomic writer. A bad
or corrupt entry is an ordinary miss and is repaired. `TUNGSTEN_LIBRARY_WIRE_CACHE=0`
disables lookup for exact A/B tests; `TUNGSTEN_LIBRARY_WIRE_DISK_CACHE=0`
disables persistent configuration. This first implementation caches one
dependency cohort rather than independent per-file units: a change to any
member relowers the cohort, avoiding cross-file counter, string, and mutable
lowering-state ambiguity.

Eight alternating `--release --native --fast --emit-ll` pairs used an entry
that imports the real compiler lexer and its two non-Core dependencies (111
functions across three files), with Core and unrelated probes warmed outside
both modes. Median lowering fell from 120.5 ms to 87.0 ms (-27.80%), measured
compiler time from 212.5 ms to 181.0 ms (-14.82%), and external wall time from
310 ms to 280 ms (-9.68%). Retired instructions fell 12.67% and peak RSS
8.37%. Every paired LLVM module and symbol sidemap was byte-identical.

The dormant path was neutral: six alternating unprotected self-compile pairs
measured 2.6025 s before and 2.6030 s after (+0.02%) inside the compiler, with
3.205 s versus 3.210 s external wall (+0.16%) and effectively unchanged RSS
and retired instructions. Every self-compiler LLVM module was byte-identical.

Focused coverage proves cold/store/hit behavior, reuse across two different
entry bodies with the same ABI, metadata and content invalidation, corruption
repair, and a linked native cache-hit result. Release is tested without
`--no-debug`. Exact self-host LLVM fixed point held at SHA-256
`2562e51f40ebb55e1175b23b1448f2654cbd2ca99011305a143fad657ffe1346`.

## Imported-library reachability

Once both Core and the method universe are locked, imported non-Core functions
are just as closed as cached Core functions. The early reachability closure now
classifies the unchanged library cohort as prunable, follows direct calls,
closures, registrations, and dynamic method roots through the combined graph,
then filters dead registrations at the established post-hash point.
`TUNGSTEN_LIBRARY_REACHABILITY=0` restores the Core-only closure.

The benefit is proportional to unused imported code. Eight alternating plain
`--release --native --fast --emit-ll` pairs for an entry that imports Lexer but
does not call it retained 6 of 111 library functions. Median compiler time fell
from 179.0 ms to 111.5 ms (-37.71%), external wall time from 270 ms to 210 ms
(-22.22%), and LLVM size from 1,879,992 to 411,198 bytes (-78.13%). A real
`Lexer#tokenize` entry retained 92 of 111 functions and was noise-flat at
181.5 ms versus 183.0 ms; its LLVM was 1.27% smaller. The focused contract
therefore compares native behavior, not LLVM bytes: removing dead definitions
is the intended artifact change.

## Persistent rendered library functions

Eligible imported functions now have a second release-only rendered-text
bucket beside Core. Its key includes the library WIRE identity, target and
frame policy, and the compacted Core-plus-library string prefix. Entry-file
strings are excluded, so two programs with the same library ABI and live
library closure can share the bucket without allowing release string
compaction to renumber a cached reference. Corruption and mismatches remain
ordinary misses through the checksummed graph reader.

Eight alternating real-Lexer pairs, with the 92-function live library closure
and Core rendering warm in both modes, reduced median emitter time from 49.0
ms to 27.5 ms (-43.88%), compiler time from 196.5 ms to 173.5 ms (-11.70%),
wall time from 290 ms to 270 ms (-6.90%), and peak RSS from 133,775,360 to
128,368,640 bytes (-4.04%). Every paired LLVM file and sidemap was
byte-identical. When reachability leaves only six library functions, this
additional cache is intentionally near-neutral; it targets programs that use
substantial imported implementations.

## Parallel read-only mid-end work

CFG construction/promotability discovery and ownership analysis are
independent per function. A bounded worker team now computes those summaries
concurrently. SSA conversion, block pruning, and every packed-WIRE mutation
remain on the parent thread in canonical function order; the global arena is
never allocated from concurrently. Programs below 512 functions, all
compile-batch worker children, and non-compiled runtimes remain serial.
`TUNGSTEN_PARALLEL_MIDEND=0` disables both stages, while
`TUNGSTEN_MIDEND_JOBS` selects up to 32 workers (automatic mode caps at eight).

Eight alternating plain release/native/fast self-compile pairs reduced median
CFG+SSA from 221.5 ms to 152.0 ms (-31.38%), ownership from 150.0 ms to 22.0
ms (-85.33%), compiler time from 2.5835 s to 2.3960 s (-7.26%), and external
wall time from 2.910 s to 2.725 s (-6.36%). Peak RSS was effectively flat.
The 1/2/4/8-worker fixtures produce byte-identical LLVM and sidemaps and the
same sorted SSA-conversion roster. Short-lived workers are deliberate: an
ordinary compiler process has one large mid-end, while compile-batch already
uses a persistent process pool. The measured startup cost is included in the
22 ms ownership phase, leaving no demonstrated second dispatch that would pay
for permanently parked compiler threads.

## mmap graph input

The checksummed graph reader now maps cache files privately and decodes from
that view, falling back to the previous `malloc` plus `fread` path when mmap is
disabled or unavailable. `TUNGSTEN_GRAPH_MMAP=0` selects the fallback. This is
not yet a zero-copy object graph: Strings, Arrays, Hashes, AST nodes, and WIRE
records are still reconstructed into their normal stores.

Twelve alternating warm Lexer pairs reported the same 7 ms Core and 4 ms
library load stages at millisecond resolution. Median compiler time moved from
176 ms to 173 ms (-1.70%), wall time stayed at 270 ms, and peak RSS fell from
135,553,024 to 128,393,216 bytes (-5.28%) because the two temporary file-sized
buffers disappeared. LLVM and sidemaps were exact. A truly directly mapped
graph can save at most the current 11 ms read-and-reconstruct stage on this
174 ms workload before format overhead; it requires relocatable packed
containers rather than pointers to reconstructed heap objects.

## Measured follow-up boundaries

The per-file library profile explains where a finer cache can help. The Lexer
cohort contains:

- `compiler/lib/lexer.w`: 85 functions, 3,560 blocks, 19,152 instructions;
- `languages/tungsten/lexers/regex_helpers.w`: 22 functions, 448 blocks,
  2,002 instructions;
- `languages/tungsten/lexers/known_units.w`: 4 functions, 45 blocks, 163
  instructions.

The existing cohort cache saves about 33 ms of lowering. Using instruction
share as an optimistic upper bound, a `lexer.w` edit could recover only 3.4
ms by reusing the other files, a `regex_helpers.w` edit about 29.9 ms, and a
`known_units.w` edit about 32.7 ms. Per-file persistence is therefore worth a
future relocatable-cache tranche for helper edits, but it first needs explicit
cross-file ABI edges and independent string/temp/block/call-site namespaces.

On the warm real-Lexer path, the stages after raw WIRE restoration are 13 ms
CFG+SSA, 9 ms ownership, 6 ms escape, 1 ms free insertion, and 18 ms content
hashing. Caching the entry-independent cut after ownership has a 22 ms (12.6%
of compiler time) ceiling. A snapshot after content hashing has a 47 ms
(27.0%) ceiling, but escape summaries, deduplication, and final symbol names
depend on entry callers. That later form must either key on an entry call/body
summary, reducing reuse after edits, or split composable function summaries
from the whole-program pass.

Two additional prototypes were removed after exact-output A/B gates:

- Packing the transient lowering context improved median lowering only 0.55%
  and left compiler/wall time flat (-0.06% and -0.17%). It did not justify a
  new 38-field WIRE kind.
- Adding nine more operations to direct-buffer rendering left median emitter
  time exactly 343.5 ms in eight self-compile pairs. The already-retained
  common direct path has moved the remaining fallbacks out of the bottleneck.

The long-argument audit likewise found no constant chain to collapse in the
hot loop. `render_instruction` has seven arguments, all register-passed on
AArch64. The 10- and 11-argument wrappers run once per function; their extra
values are target, frame, attribute, slab, and mutable reference state that
varies per compilation. Converting them to process globals would sacrifice
reentrancy for two occasional stack arguments, while a Hash context adds hot
lookups. Generated high-arity WIRE constructors carry actual record fields,
not repeated constants.

The combined retained branch reached exact self-host LLVM fixed point at
SHA-256 `5aa550415f8a0af1fff483ad6f6b076a757aae6c6b9f77b17b40aadacaa35f0c`;
the corresponding symbol sidemap also matched exactly at
`5a0d63130c64ad2542657468b75bed497bd2ebec8a37480a1c1febf2dfeb08c2`.
