# Compiler performance: next tranches

This branch evaluates ten compiler-throughput changes independently. Each
tranche must preserve generated LLVM for representative inputs, retain exact
self-hosting fixed point where it applies, pass focused checks, and earn its
place with matched `--release --native --fast --no-debug` measurements. A
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
