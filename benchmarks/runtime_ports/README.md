# Runtime-to-core migration benchmarks

This directory is the performance and correctness gate for moving method
implementations from `runtime/runtime.c` into Tungsten classes under `core/`.
Every retained migration must be at least as correct as its C implementation
and remain within the current performance budget in every important input
stratum. Prefer and continue tuning source implementations that are faster,
but a small source-dispatch cost is acceptable when it removes a C builtin.

Historical campaigns through 2026-07-13 used a deliberately strict 3%-win
gate (`W/C <= 0.97`). The relaxed migration revisit beginning 2026-07-14 uses
the user-selected 10%-regression budget (`W/C <= 1.10`). Older ledger entries
retain their original wording and ratios so their decisions remain auditable.

## Benchmark protocol

1. Copy the old C handler into a benchmark-only `*_ref.c` file without changing
   its behavior.
2. Expose that copy through a `__c_*` method using `ccall`; keep candidate and
   optimized Tungsten bodies separately addressable as `__w_v1_*` and
   `__w_v2_*` while tuning.
3. Compile C and Tungsten paths into the same release binary with
   `TUNGSTEN_C_INCLUDES`. Compilation and corpus construction are excluded from
   the timed region.
4. Check exact results, boundary behavior, errors, and representation-sensitive
   cases before timing.
5. Prefer C/W/W/C and W/C/C/W pairs within each process, summing the two
   measurements per implementation to cancel first-order clock and thermal
   drift. Every loop must consume a checksum, and each path should run for at
   least 0.2 seconds per measurement.
6. Use an even 8–12 paired samples so ABBA and BAAB orientations are balanced,
   report medians, and use a long enough untimed warmup to stabilize frequency.
   Repeat independently after a compiler rebuild when a result is close.
   On a busy host, prefer thread or process CPU time to wall time and keep the
   C/source legs in the same process; record sustained competing workloads
   rather than treating scheduler noise as a candidate regression.
7. Inspect emitted LLVM IR when necessary to confirm the public method reaches
   the source body rather than an intrinsic or stale IC entry.
8. After a unique source body passes, remove only its matching IC entry in an
   isolated production-shaped trial and time the real public method. Restore
   the IC unless this second measurement also clears the retention gate.

Runtime IC lookup currently precedes type-class lookup. Before calling an
existing public name the source leg must therefore either use a unique
`__w_*` candidate name or remove the matching IC entry in an isolated trial;
adding a core body alone can silently benchmark the old C handler twice.

## Retention gate (2026-07-14 relaxed revisit)

- Ratios are candidate Tungsten time divided by C time: below `1.00` is a
  speedup and above `1.00` is a slowdown.
- Median paired `W/C <= 1.10` in every important input stratum.
- An independent repeat must also remain at or below `1.10`; close or noisy
  results require longer thread/process-CPU samples, not a wall-clock waiver.
- No correctness, allocation, overflow, error, or representation regression.
- If any important case regresses, keep the C builtin and record the result as
  skipped. Do not hide a loss by averaging it with unrelated faster cases.

After a migration passes, optimize the Tungsten body again and preserve enough
benchmark structure to compare C, first-source, and optimized-source versions.

## Migration ledger

| Area | Harness | Status |
|---|---|---|
| Integer leaf methods | `run_integer.sh` | Migrated before this loop; retained benchmark |
| Integer `to_i` | `int_to_i_port.md` | Skipped. An exact `self` body and removal of the real public native IC passed all signed-i48 bit identities, one/many surplus arguments, autoload, and trailing-block passthrough. A 15-pair 50M-call thread-CPU campaign measured source/C medians of 0.989 for varying Array receivers and 0.981 for compiler-inferred Integers (aggregate 0.994/0.986). An earlier wall-clock campaign was parity but scheduler-noisy. Neither important stratum cleared 0.97, so production remains unchanged. |
| Enumerable combinators | `run_enumerable.sh` | Migrated before this loop; retained benchmark |
| Date and packed network values | `run_date.sh`, `run_ipv4.sh`, `run_network.sh` | Migrated before this loop; retained benchmark |
| IPv4 `octets` | `run_ipv4_octets.sh` | Skipped. The direct packed-`$value` shifts with an ordinary cap-8 Array literal passed interpreter/WIRE and 4,096-address representation checks, but the balanced 10x5M unique-source median was 0.981 and did not clear the 0.97 gate. |
| UUID `byte` | `uuid_byte_port.md` | Skipped after two independent 15-pair thread-CPU campaigns. The optimized source reduces bounds checking to one mask and direct u8 load; exact compiled/interpreted autoload, all 16 bytes, bounds, BigInt/low-i64 wrapping, surplus arguments, invalid Float parity, and receiver stability passed. Hot medians were 0.977 and 0.978, narrowly missing 0.97; BigInt fallback improved to 0.967/0.960. Production is untouched. |
| Base64 methods | `run_base64.sh` | Migrated before this loop; retained benchmark |
| String `empty?` | `run_string.sh` | Skipped. Exact source body measured 0.973 and the optimized bitmask body 0.985 in quiet 9x50M runs; neither cleared the 0.97 gate |
| String/Symbol `to_s` | `string_to_s_ab.w` | Retained. The shared 0xF9 source body clears only the Symbol marker (`wvalue_from_bits($value & -2)`), compiling to one `and` plus `ret`. Exact 48-value representation checks, compiled/interpreted autoload, fixed-point self-hosting, and two independent public-dispatch campaigns passed; ratios ranged from 0.844 to 0.966 across inline/slab/heap/rope String and inline/slab Symbol strata. Full evidence: `string_to_s_port.md`. |
| AST-body accessors | `run_ast_body.sh` | Migrated before this loop; retained benchmark |
| Array `size`, `cap`, `empty?`, `first`, `last` | `run_array_leaf.sh` | Skipped. After raw-field lowering, quiet 9x50M confirmations were `size` 0.985, `cap` 1.022, `first` 0.986; `empty?` and `last` also failed both earlier gates |
| Array `join` | `run_array_join.sh` | Migrated from its C IC to source, then optimized through retained v6. V6 replaces first-pass StringBuffer copies with the narrow raw `w_stringy_c_length` validation bridge and allocates one recycled buffer for pass 2. Two isolated candidate campaigns and two real-public campaigns cleared every workload. The final version also autoloads Array for runtime-only receivers through a one-shot unresolved-name guard and repairs frozen-slab freshness in both compiled and interpreted execution. Benchmark-only v3, v4, v5, and two unguarded loader scans were rejected. Full evidence is below. |
| Array `uniq` | `run_array_uniq.sh` | Skipped after the complete interpreter/WIRE/compiled semantic gate. V1's literal quadratic source loop measured 0.984–1.772 and failed every workload. V2 safely hashes only String/rope/Symbol values and produced major text wins (0.940 repeated, 0.384 unique, 0.785 large), but empty/singleton/small, numeric, mixed, and typed strata measured 0.991–1.241. The C IC remains installed. The gate also exposed a compiler recycle-scope bug described below. |
| Array `compact`, `dup` | `run_array_compact_dup.sh` | Both are skipped after passing the complete interpreter/WIRE/compiled corpus. `compact` missed the gate in all eleven strata (0.976–1.010). `dup` passed only medium arrays (0.937); empty, singleton, small, large, typed, and shifted measured 0.981–1.025 or narrowly above the exact 0.97 cutoff. Both production ICs remain installed. |
| StringBuffer `size` | `run_string_buffer_size.sh` | Skipped: quiet 9x50M median W/C 1.023 |
| Float `infinite?` | `run_float_infinite.sh` | Skipped after public-dispatch trial. The unique source body passed twice (0.959, 0.921), but after removing the C IC the public method measured 0.983, so the production migration was reverted |
| Float `nan?` | `run_float_nan.sh` | Skipped after public-dispatch trial. The one-compare body passed an isolated balanced ABBA run at 0.958, but the real public method measured 1.057 with 10 balanced orientations and a long warmup |
| Float `abs` | `run_float_abs.sh` | Skipped. The biased-word source body passed 88 exact-bit checks, including signed zero and raw noncanonical NaN payloads. In the first quiet balanced 10x50M unique-source campaign, finite/edge/NaN C/W medians in ns were 10.118/10.178, 10.110/10.112, and 10.227/10.237; paired-ratio medians were 0.988, 0.991, and 1.002. The independent rebuild measured 10.931/10.565 (0.982), 10.133/10.155 (0.996), and 10.357/10.401 (0.985). No stratum cleared the 0.97 gate, so production is untouched: the C IC remains and no public-dispatch trial was warranted. |
| Float `to_f` | `/tmp/tungsten-float-to-f-{baseline,candidate}/benchmarks/runtime_ports/float_to_f_ab.w` | Skipped before a public-method trial. The exact identity body lowers to a bare `ret i64 %__self` and passed 66 exact-bit checks across signed zero, subnormals, finite extrema, infinities, canonical NaNs, and raw positive NaN payloads. Ten balanced 100M-call samples produced a median source/C ratio of about 0.987, which is faster but misses the strict 0.97 migration gate. The C IC remains installed and the experimental harness stays isolated in `/tmp`. |
| Hash `size` | `run_hash_size.sh` | Retained in the relaxed revisit. The public source body is the direct `$count` view-field load and its C IC is removed. The public caller LLVM is identical; the source target is four ARM64 operations plus `ret`, while the C target first validates the Hash tag. Four balanced thread-CPU confirmations ranged from 0.959 to 0.992 source/C, so the old 1.105 result was host/harness noise rather than a generated-code loss. Compiled core checks and a focused interpreter regression pass; bare `$count` now uses the existing allowlisted native-field bridge instead of falling through to an unset global. |
| BigArray `size` | `run_big_array_size.sh` | Skipped. The literal signed-header load plus `w_int` measured 0.972 for i48 values and 1.048 for overflow. V2 inlined exact signed-i48 tag construction with canonical `w_int` fallback, but measured 1.005/0.979. Both passed exact signed-i64, Int/BigInt representation, WIRE, arity/block, and receiver-stability checks; neither cleared both strata. Production is untouched. |
| SmallArray `size`, `cap`, `empty?` | `/tmp/tungsten-small-array-leaf` | Skipped after exact checks over header sizes 0..255. `size` and `cap` lower to a byte load plus inline Int tag; the optimized `empty?` keeps the field raw through a single compare instead of calling generic equality. Balanced medians were about 0.999, 0.985, and 0.987 respectively. None cleared the 0.97 gate, so all three native IC entries remain installed. |
| Mmap `size` | `mmap_size_validation.md` | Skipped after six source variants. The best real-domain body used a signed-i48 range test and measured about 0.947 for inline sizes, but its exact `w_int` overflow fallback measured about 0.990 in the longer four-leg campaign. All 16 signed-i64 boundary cases, representation, extra-argument, block, close, and ABI-layout checks passed. No variant cleared both strata; the C IC remains installed. The audit also found that removing it would require a new Mmap autoload/interpreter bridge, since Mmap is not currently registered by `core/tungsten.w`. |
| BigInt leaf methods | `run_bigint_leaf.sh` | Skipped. Generic `to_i`, `prev`/`succ`/`next`, and five predicates failed or were unstable; raw `even?` failed its repeat (0.961 then 1.085). Corrected ABBA timing put raw `negative?` at 0.954 and three source-dispatch trials at 0.968, 0.977, and 0.992, but only one cleared the 0.97 gate. A fidelity audit also found that the real C IC uses the native arity `-1` cache branch while the in-process C reference uses ordinary arity 0, so the production migration was restored to C pending a true IC-vs-source harness. |

### Array `join` follow-up trials

The retained public source migration passed two quiet balanced campaigns in
every stratum. The paired public/C ratios were respectively: empty
0.641/0.622, singleton 0.770/0.782, pair 0.701/0.739, four 0.745/0.763, eight
0.828/0.830, medium 0.527/0.516, large 0.210/0.209, huge 0.070/0.069, UTF-8
0.508/0.523, and typed 0.771/0.780. Exact-arity interpreter lookup and the
allowlisted StringBuffer/slab bridges preserve its two live-size/to_s passes,
NUL behavior, error order, mutation behavior, and overload surface.

All later ratios below compare one candidate directly with retained v1 in the
same binary/process. Workload order is empty, singleton, pair, four, eight,
medium, large, huge, UTF-8, and typed.

- v3 reset the first validation buffer after every item. Its ratios were
  0.987, 0.997, 1.001, 1.003, 0.996, 1.006, 1.055, 1.007, 1.012, and 0.999.
- v4 merged separator validation into the first-pass buffer. Its ratios were
  0.797, 0.891, 0.925, 0.943, 0.984, 0.999, 0.995, 1.001, 1.028, and 0.997.
- v5 reused one buffer across validation and output, resetting it once. Its
  ratios were 0.649, 0.788, 0.836, 0.892, 0.944, 1.015, 1.009, 1.005, 1.002,
  and 0.998.

Each of v3-v5 lost at least one important stratum, so all three are strict
skips and none received an independent repeat.

V6 is retained. Its narrow production bridge, `w_stringy_c_length`, returns
the unboxed `strlen(as_str(value))`. This validates String/Symbol/rope storage
and reproduces the embedded-NUL boundary without a first-pass copy or reset.
The Tungsten method validates the separator before any element conversion,
validates every first-pass `w_to_s` result, then creates one recycled
default-growth output buffer for pass 2.

Two direct v6/v1 campaigns cleared the 0.97 gate in all ten strata. Their
ratios were 0.559/0.539, 0.644/0.658, 0.703/0.709, 0.757/0.738, 0.792/0.769,
0.836/0.843, 0.833/0.874, 0.834/0.846, 0.818/0.803, and 0.884/0.879.
The actual public method then cleared its first campaign at 0.566, 0.693,
0.737, 0.795, 0.806, 0.869, 0.865, 0.870, 0.866, and 0.901. An independently
rebuilt compiler repeated below 1.00 everywhere at 0.590, 0.696, 0.749, 0.791,
0.819, 0.886, 0.893, 0.875, 0.852, and 0.902.

That fresh compiler passed the tree-walk public/v6 semantic matrix and the
narrow interpreter bridge, including every typed decoder, overloads,
embedded NUL, live-size shrink, exact two-pass call order, and fatal errors.
Compiled checks additionally pin exact C bytes/representation, frozen-slab
freshness, mutation behavior, extra arguments, cleanup, and WIRE shape.

A post-migration audit found two cases hidden by the benchmark's explicit
`use array`: an Array supplied only by `argv()` had no literal/class reference
to autoload the now-source-only method, and the tree walker implemented String
variable `<<` through `+`, which could reuse an interned mode-6 slab value after
freeze. `spec/compiler/array_join_autoload_spec.w` now pins the argv-only case.
The interpreter uses the same `w_str_append` boundary as compiled lowering,
and the join matrix freezes a pre-existing six-byte result and requires two
fresh, distinct mode-7 results afterward.

A naive method-name autoload trigger was measurably too expensive. The first
standalone walker branch moved median load/parse from about 5.305s to 6.200s.
Consolidating the call branches was still a rejection: in five alternating
self-host pairs it moved load/parse 5.728s to 6.176s and wall 8.69s to 8.92s.
The retained form compares against `join` only while Array is unresolved and
turns the guard off after the first match; later autoload iterations skip the
comparison entirely. Against the original pre-trigger compiler, five balanced
pairs produced byte-identical LLVM in all ten runs while median load/parse fell
from 6.468s to 5.637s (0.872), wall from 8.98s to 8.33s (0.928), and user CPU
from 8.29s to 7.70s (0.929).

### Array `uniq` static design

The retained C handler is deliberately still the public implementation. V1 is
its direct source control flow: decoded indexed reads, a first-occurrence
output Array, and a quadratic `w_eq` scan. V2 only enters its Hash branch when
the input has more than 16 elements and item zero is text; otherwise it takes
the exact v1 path. In the Hash branch the already-proven first item seeds the
Hash and output directly, avoiding a redundant classifier and guaranteed-miss
lookup. Later String/rope/Symbol values use Hash membership, with canonical
`W_FALSE == 1` tested through `wvalue_bits`; every non-text value still scans
the complete output with `w_eq`.

The classifier encodes the current `runtime/wvalue.h` contract in Tungsten:
tag `0xFFF9` is inline/slab/heap String or Symbol; only a non-sentinel generic
object (tag zero, low subtag zero) may be inspected at byte zero, and type 9 is
a rope. WIRE must show shifts/masks plus one guarded `load_u8_ptr` and no C or
dynamic call inside this helper. The tree-walker already exposes `wvalue_bits`
and guarded raw byte loads, while the two Hash storage calls have narrow
arity/type-checked bridges. `array_uniq_interpreter.w` exercises all admitted
representations, the guard families, both valid bridges, their four failure
modes, and representative fallback equality cases without linking benchmark C.

The complete tree-walk/fatal, WIRE, release, representation/capacity, typed,
shifted, equality, and bounded-cleanup gate passed. V1's balanced ratios were
empty 0.984, singleton 1.017, small text 1.263, small mixed 1.219, repeated
text 1.672, unique text 1.400, large text 1.772, numeric 1.210, mixed 1.335,
and typed 1.195. V2's text-only Hash accelerator improved repeated/unique/large
text to 0.940/0.384/0.785, but the other seven workloads measured 1.006,
0.991, 1.241, 1.184, 1.194, 1.068, and 1.194. Both are strict skips with no
repeat or public-method trial; production remains unchanged.

During the gate, a `## recycle` Hash declared in a branch after an earlier
branch containing `break` emitted unwind `cleanup_push_hash` but no normal-path
recycle. The benchmark was made independent of the bug by emitting the Hash
branch first and avoiding `break` only in its rare non-text fallback. The
underlying compiler defect is now fixed: terminated branches restore their
compile-time recycle-scope depth, explicit return/break/next transfers emit
path-local LIFO cleanup, and each early return snapshots only the dominating
function-scope allocations. The exact historical fallthrough now emits one
Hash push/pop/recycle; focused WIRE and compiled checks cover return, break,
next, sibling restoration, exceptions, and double-recycle detection.

### Array `compact` / `dup` static design

The two leaf collection ports are deliberately independent. Their benchmark
reference functions mirror the installed C loops: allocate an ordinary
polymorphic Array at default capacity, decode each element in the receiver's
live window, and push either every value (`dup`) or every raw value other than
the `W_NIL` sentinel (`compact`). V1 preserves the live `$size` loop condition;
v2 snapshots the raw size because neither decoded access nor output push can
mutate the separate receiver. The compiler should lower each candidate to one
`w_array_new_empty`, one static decoded-index site, one static push site, and a
raw size load; compact's nil test must be an `icmp`, never `w_eq`/`w_neq`.

The compiled correctness corpus retains all results so pool history cannot
hide capacity drift. It pins cap transitions across 7/8/9, 15/16/17, and
32/33 outputs; exact WValue bits and shallow object identity; result ownership,
start, and ebits; receiver header/content stability; fresh non-aliasing outputs;
independent mutation; shifted and borrowed views; nil versus false; ignored
extra arguments and the language's implicit result iteration for trailing
blocks on no-block methods; and bool/u1/u4/i4/u8/i8/u16/i16/u32/i32/
u64/i64/f32/f64/bf16/w64 decoding. Timed outputs escape into bounded batches
and are freed outside the measured intervals. Each same-process sample is
C/W/W/C or W/C/C/W, with 10 balanced orientations by default.

The complete interpreter, WIRE, and 42-family compiled correctness gate passed.
`compact` v2 then failed its first ten-run campaign in every stratum: empty
1.010, all-nil 0.993, singleton 0.990, small dense 0.984, small sparse 0.976,
medium dense 0.990, medium sparse 0.988, large dense 0.982, large sparse 1.001,
typed 1.007, and shifted 1.003. It is therefore a strict skip with no repeat or
public-method trial. `dup` v2 likewise failed its separate ten-run campaign:
empty 0.988, singleton 1.002, small just above the exact 0.970 cutoff, medium
0.937, large 0.981, typed 1.010, and shifted 1.025. Since six of seven strata
failed, it is also a strict skip with no repeat or public-method trial. The
benchmark-only `run_array_compact_dup_public.sh` is the final scaffold: it
requires isolated baseline/candidate roots, audits native-IC versus public
source shapes and WIRE, and repeats the full workload matrix through the real
public name. It never patches either root itself. Shared `core/array.w` and the
runtime IC table remain untouched until all three gates pass.

## Compiler work retained during this loop

- Recycle-scope lowering now restores lexical bookkeeping after terminated
  branches and emits balanced LIFO cleanup on return, break, and next without
  duplicating exception unwinds. Early returns record the prefix of live
  function-scope allocations, preventing later sibling temps from being
  retroactively inserted where they do not dominate. Fresh compilers reached
  a stage-2/stage-3 LLVM fixed point; focused debug, release, and ASan runs each
  passed 100 repetitions. Eight same-input full-emission pairs produced
  byte-identical LLVM with wall/user ratios of 0.9987/0.9971 and instruction/
  cycle ratios of 1.00013/0.99964. A separate load+parse slice fluctuated by
  about +0.65% on an oversubscribed host while retired instructions were
  unchanged, so the full non-regressing compiler measurement is the retention
  result.
- The recycle follow-up now gives every inlined Array iterator a lexical
  cleanup scope and restores its bindings, parameter facts, unboxed-variable
  map, and lowering depth before sibling CFGs. Nonlocal block returns snapshot
  and unwind the runtime cleanup stack instead of making the shared catch edge
  reference conditionally dominating compiler temps. Exceptions deactivate
  abandoned block-return frames, and all stack exception frames—including
  HTTP/1, TLS, HTTP/2, and HTTP/3—use one initializer that records cleanup
  depth. Focused C and language tests passed under ASan and repeated execution;
  isolated exception-cycle cost was +0.52% noise with identical push machine
  code, HTTP crossover tests changed sign when ports were swapped, and the
  integrated compiler reached a byte-identical gen2/gen3 LLVM fixed point
  (`d8b0da5f...10851`).
- Native view-field lowering now preserves signed/unsigned machine types,
  sign-extends narrow signed loads, and avoids eager integer boxing. This made
  direct field candidates expressible and fixed BigInt's `length` layout/load
  checks, although no newly tested public runtime port survived its gate.
- CFG/SSA setup now skips overflow/promotability analysis for ineligible
  functions, reuses the promotable-variable map, omits an unused backedge
  analysis, and performs one conservative phi-pruning pass. Alternating
  self-host measurements showed median CFG time falling from 0.293s to 0.176s
  and total compiler-phase time from 3.471s to 2.682s.
- Function replacement now maintains a lazily synchronized name-to-index map
  instead of rescanning the entire function list for every class method. Three
  alternating equal-build self-host pairs produced a 0.900 median lowering
  ratio and a 0.892 total compiler-phase ratio. A reopen/intervening-function
  regression spec emits byte-identical WIRE before and after the change.
- Raw-integer promotion analysis now returns immediately for the common
  zero-candidate scope, reuses its declared/candidate key lists, and proves its
  shrinking-set fixed point by cardinality. Five balanced self-host pairs all
  favored the candidate: median lowering was 0.951, total compile 0.958, and
  wall time 0.975. All ten emitted LLVM files were byte-identical.
- Ownership analysis now marks phi results and incoming values in its first
  scan and omits a fixed-point pass that could not change valid WIRE. Five
  balanced self-host pairs favored the candidate in lowering and total compile
  every time: median lowering was 0.904, total compile 0.912, wall time 0.965,
  and user CPU 0.993. All ten emitted LLVM files were byte-identical.
- Parser packed-token access now converts an Array-materialized numeric token
  through `w_numeric_to_i64` once, then extracts type, offset, and length with
  raw shifts. This detail is necessary because high-bit `W_TAG_CHAR` patterns
  materialize as negative one-limb BigInts; shifting either the boxed number
  or its pointer was respectively allocating or incorrect. The strengthened
  compiled/interpreter spec covers both that representation and small Integer
  tokens. In five balanced old/new self-host pairs, median load+parse fell from
  6.293s to 5.869s, lowering from 2.035s to 1.641s, total compiler time from
  3.527s to 2.730s, wall from 9.560s to 9.040s, and user CPU from 8.840s to
  8.100s. Wall, user CPU, and load+parse won all five pairs; all twelve warm
  and measured LLVM outputs were byte-identical.
- Zero-argument dynamic calls now use a three-argument cached-dispatch entry
  point. It retains the generic dispatcher's cache precedence, native-wrapper
  ABI, nil padding, inheritance, and uncached slow path, while exact source
  arity-zero hits call their target directly. Ten balanced in-process 50M-call
  samples measured specialized/generic medians of 0.883 for source arity 0 and
  0.865 for native IC arity -1. An independent pair of release binaries, with
  75 zero-argument call sites changed and all 129 nonzero sites left generic,
  measured 0.905 and 0.903 respectively. The host was heavily loaded by
  unrelated long-running jobs, but both A/B methods cleared the gate by much
  more than the observed noise. The hot benchmark's `__text` shrank by 268
  bytes (the file grew 96 bytes from link metadata). A release compiler
  artifact grew 156 bytes of `__text` while its total file shrank 8 bytes;
  emitted compiler IR grew 1,292 bytes (0.010%). Both isolated roots reproduced
  the existing stage-2 signal-10 abort, so no stage-2 self-host time is
  attributed to this change.
- One-argument calls on a conservatively proven exact source-class ivar now use
  a scalar cached-dispatch ABI. The hot path computes the WObject class key
  directly and calls the source `/1` method without materializing an argument
  array; every miss, stale trusted hint, native receiver, and incompatible
  cache entry falls through to the canonical generic dispatcher. The proof is
  deliberately function-wide: every ivar write must construct or explicitly
  hint the same ordinary source class, while unknown/compound/multi writes,
  implicit `-> new(@field)` parameters, generated setters, reopens, native
  constructors, and both endpoints of every inheritance edge disable it.
  Twenty balanced 100M-call pairs measured 3.392 ns versus 4.109 ns (0.826,
  17.4% faster); stale/native code remained byte-identical and at timing
  parity. Self-host load+parse improved by 9.7--11.3%, full compile stayed at
  parity, exactly nine Interpreter Environment sites select the helper, and
  release/debug/ASan, repeat-100, full-suite, and stage-7/stage-8 fixed-point
  gates passed. The production rebuild reached a byte-identical gen2/gen3 LLVM
  fixed point (`cba3fec3...17be`).
- Development links now cache native runtime archives by a v4 content/config
  key instead of the single global `/tmp/tungsten-runtime-native.a`. The key
  covers the runtime root and dependencies, compile flags and ambient
  toolchain environment, generated thresholds, and the literal plus resolved
  identities of both compiler and archiver. Small wrapper executables are
  content-hashed, so same-size rewrites with restored nanosecond mtimes still
  invalidate. Builds use per-process object directories and atomically publish
  the final archive; same-key and different-key concurrency, quoted paths,
  spaces, stale legacy archives, release bypass, and fixed point all passed.
  Twenty warm pairs were non-regressing (wall median 0.550 s versus 0.585 s).

## Pending compiler trials

No compiler trial in this section has yet cleared its first performance gate.

## Rejected compiler trials

- The dedicated one-argument cached-dispatch ABI passed its dispatcher-only C
  microbenchmark strongly: source arity-one calls measured 0.858 and native
  wrapper calls 0.815 versus the generic dispatcher. Exact coverage included
  source arities zero through five, nil filling, slow fallbacks, inheritance,
  native cache replacement, and ropes. The production-shaped cross-build then
  verified the intended transformation—113 generic argc-one calls became 113
  helper calls, 113 first-argument stores disappeared, and scratch allocas fell
  from 73 to 15—but real varying-argument results split. Source calls improved
  to 0.960 while native Array calls regressed to 1.021, so the production ABI
  and emitter change were not retained. Forcing the helper to always-inline
  made the native result worse at 1.065. The likely boundary is the native
  wrapper ABI: it still requires a pointer to a one-element argument array, so
  the scalar helper merely moves that spill into the callee. A future version
  needs a true scalar native fast path, not another inlining hint. This rejects
  only the broad all-receiver selector: the conservative exact-source-ivar
  subset documented above was measured separately and is retained.

- Replacing each escape/content-hash call-edge list's linear duplicate check
  with a per-function hash looked attractive statically (60.7% of content-hash
  edges were duplicates), but five balanced self-host pairs were neutral to
  slower: median process user CPU was 1.014, total compile 1.125, and wall time
  1.084. All ten LLVM files were byte-identical; the code and its dedicated
  regression fixture were removed because performance did not clear the gate.

- Routing all 429 internal `Parser#at_type?` sites through a direct top-level
  helper passed its exact mechanical audit and matched compiled/interpreter
  semantics. Every measured self-host pair emitted byte-identical LLVM, but
  the balanced medians were flat for load/parse (0.998) and slower for total
  compiler time (1.091), wall time (1.035), and user CPU (1.021). The isolated
  candidate was rejected and production parser dispatch remains unchanged.

- Moving the lexer's closed 133-entry token-symbol mapping into direct
  top-level helpers also passed its exact audit and compiled/interpreter gate,
  with byte-identical LLVM from every measured pair. It regressed all balanced
  self-host medians: load/parse 1.030, total compiler 1.081, wall 1.025, and
  user CPU 1.011. Production keeps the virtual mapping chain.

The self-host build still reports a stage-1/stage-2 LLVM mismatch. Cached
pre-change builds reproduce the same mismatch class, so it is tracked as an
existing issue rather than attributed to these optimizations.
