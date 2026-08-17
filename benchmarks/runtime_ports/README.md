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
| Integer `to_i` | `run_integer_to_i_public.sh`, `int_to_i_port.md` | Retained in the relaxed revisit. The exact `self` body emits a bare `ret`, and the C IC is removed. Two independent 12-pair x 50M thread-CPU campaigns measured 0.968--0.997 source/C across varying and compiler-inferred Integer strata; combined 24-pair medians were 0.995 and 0.984. Exact signed-i48 identity, surplus arguments, trailing blocks, autoload/bootstrap, interpreter, and reindexed-IC checks pass. |
| Enumerable combinators | `run_enumerable.sh` | Migrated before this loop; retained benchmark |
| Date and packed network values | `run_date.sh`, `run_ipv4.sh`, `run_network.sh` | Migrated before this loop; retained benchmark |
| IPv4 `octets` | `run_ipv4_octets.sh` | Retained in the relaxed revisit. The direct packed-`$value` shifts and ordinary cap-8 Array literal replace the C IC. Two balanced unique-name campaigns measured 0.991 and 0.984 source/C; after removing the real public IC, two thread-CPU campaigns measured 0.994 and 0.995. Interpreter/WIRE, 4,104-address representation, independent-allocation, prefix, surplus-argument, and cleanup checks pass. |
| IPv4/IPv6/MAC `to_s` | `run_packed_network_format_revisit.sh`, `packed_network_format_revisit_audit.md` | Retained in the relaxed revisit. The existing direct `w_to_s` wrappers replace exactly three class-specific IC rows; native `inspect` aliases remain for opaque-return safety. Two rebuilt campaigns measured 0.985--1.008 across plain/CIDR IPv4, plain/CIDR IPv6, and MAC. Exact prefixes, storage identity, surplus arguments, blocks, autoload, interpreter, WIRE, and LLVM gates pass. |
| UUID `byte` | `run_uuid_stringbuffer_revisit.sh`, `uuid_byte_port.md` | Retained in the relaxed revisit. The optimized source keeps the exact `w_to_i64` boundary, replaces two bounds tests with one mask, and loads the declared 16-byte view directly. Two rebuilt public campaigns measured 0.979/0.969 for ordinary indices and 0.985/0.978 for BigInt/wrapping fallback cases. Compiled code no longer calls `w_uuid_byte`; the C helper remains only as a narrow interpreter/storage bridge. |
| Base64 methods | `run_base64.sh` | Migrated before this loop; retained benchmark |
| String `empty?` | `run_string.sh`, `run_string_public.sh` | Retained in the relaxed revisit. The optimized source is one `($value & 14) == 0` mask/compare and its C IC is removed. Two balanced unique-name campaigns measured 0.937 and 0.927. Two isolated public thread-CPU campaigns passed inline, slab, heap, rope, and Symbol strata at 0.853--0.956 source/C. Compiled and tree-walker representation checks pass; the interpreter now flattens ropes at the same String source-dispatch boundary and routes shared Symbol methods through String. |
| String/Symbol `to_s` | `string_to_s_ab.w` | Retained. The shared 0xF9 source body clears only the Symbol marker (`wvalue_from_bits($value & -2)`), compiling to one `and` plus `ret`. Exact 48-value representation checks, compiled/interpreted autoload, fixed-point self-hosting, and two independent public-dispatch campaigns passed; ratios ranged from 0.844 to 0.966 across inline/slab/heap/rope String and inline/slab Symbol strata. Full evidence: `string_to_s_port.md`. |
| String/Symbol `size`, `length` | `run_string_length_branchless_revisit.sh`, `string_length_branchless_revisit_audit.md` | Retained in the relaxed revisit. The checked source calls the canonical raw byte-length helper, tags the signed-i48 common arm directly, and preserves cold `w_int` fallback. Two independently rebuilt campaigns passed all 18 inline/slab/heap/rope/NUL strata: worst per-method source/C medians were 1.054 and 1.044. A branchless uint32-coupled variant also passed at 1.056/1.062 but was rejected because it offered no material win. Seventeen representation cases, twelve no-use/autoload seams, generated `map/select/reject/count(:size/:length)`, exact String/Symbol identity, WIRE/LLVM, and tree-walker gates pass. Both native IC rows are removed. |
| AST-body accessors | `run_ast_body.sh` | Migrated before this loop; retained benchmark |
| Array `size`, `cap`, `empty?`, `first`, `last` | `run_array_leaf.sh`, `run_array_leaf_public.sh` | Retained in the relaxed revisit. `size`/`cap` tag their u32 view fields directly, `empty?` compares raw size, and `first`/`last` retain ebits-aware indexed decoding behind one empty guard. Two independently rebuilt public thread-CPU campaigns passed all 12 ordinary, typed, shifted/view, and empty strata at median ratios 0.948--1.016. A dedicated 200M-call/leg audit put the noisy nonempty `empty?` stratum at 0.980. The five native IC rows are removed. |
| Array `join` | `run_array_join.sh` | Migrated from its C IC to source, then optimized through retained v6. V6 replaces first-pass StringBuffer copies with the narrow raw `w_stringy_c_length` validation bridge and allocates one recycled buffer for pass 2. Two isolated candidate campaigns and two real-public campaigns cleared every workload. The final version also autoloads Array for runtime-only receivers through a one-shot unresolved-name guard and repairs frozen-slab freshness in both compiled and interpreted execution. Benchmark-only v3, v4, v5, and two unguarded loader scans were rejected. Full evidence is below. |
| Array `uniq` | `run_array_uniq.sh` | Skipped after the complete interpreter/WIRE/compiled semantic gate. V1's literal quadratic source loop measured 0.984–1.772 and failed every workload. V2 safely hashes only String/rope/Symbol values and produced major text wins (0.940 repeated, 0.384 unique, 0.785 large), but empty/singleton/small, numeric, mixed, and typed strata measured 0.991–1.241. The C IC remains installed. The gate also exposed a compiler recycle-scope bug described below. |
| Array `compact`, `dup` | `run_array_compact_dup.sh`, `run_array_compact_dup_public.sh` | Retained in the relaxed revisit. V2 snapshots the raw receiver size and keeps the allocation/decode/push loop in Tungsten. Two fresh unique-name campaigns and two isolated real-public campaigns passed every workload under the 1.10 budget; the public source paths ranged from 0.920 to 1.034 versus the native ICs. Both C handlers/table entries are removed. Runtime-only receivers autoload Array through the one-shot source-method guard, with dedicated `argv()` regressions for each method. |
| StringBuffer `size` | `run_uuid_stringbuffer_revisit.sh`, `run_string_buffer_size.sh` | Retained in the relaxed revisit. The canonical `StringBuffer` view loads `$length`, performs a one-compare signed-i48 roundtrip test, tags the common Integer inline, and uses an exact cold `w_int` fallback. Two public campaigns measured 0.985/0.982 for realizable buffers and 0.998/1.001 for synthetic overflow headers. The native IC is removed. |
| Float `infinite?` | `run_float_leaf_public.sh` | Retained in the relaxed revisit. The unbiased-magnitude equality body replaces the C IC. Two rebuilt public thread-CPU campaigns measured 0.981 and 0.996 source/C; exact compiled/meta-interpreter IEEE classification checks and WIRE audits pass. |
| Float `nan?` | `run_float_leaf_public.sh` | Retained in the relaxed revisit. The unbiased magnitude is compared above infinity, covering every representable raw NaN payload rather than only the canonical word. Two rebuilt public campaigns measured 0.966 and 0.972 source/C. |
| Float `abs` | `run_float_leaf_public.sh` | Retained in the relaxed revisit. The biased-word body clears the IEEE sign and canonicalizes NaNs exactly like `w_box_double(fabs(...))`. Public campaign ratios were 0.991/0.982 finite, 0.977/0.973 edge, and 0.978/0.978 NaN. All 100 individual comparisons passed; worst was 1.053. |
| Float `to_f` | `run_identity_leaf_public.sh`, `identity_leaf_public.md` | Retained in the relaxed revisit. The source body is exact receiver identity and its native IC is removed. Two independently rebuilt public campaigns measured 0.982/0.998 for finite values and 1.007/0.979 for NaNs. Exact signed-zero, subnormal, finite-extreme, infinity, canonical/raw-positive-NaN, surplus-argument, block, autoload, bootstrap, and interpreter gates pass. |
| Float `floor`, `ceil`, `round`, `sqrt`, `sq` | `run_float_remaining_public.sh`, `float_remaining_revisit_audit.md` | Retained after optimization. The first rounding source form regressed 12.95--16.11%, so it was rejected; a narrow raw-Math lowering rule removed its box/callback/unbox chain. Two fresh campaigns then measured floor 1.000/0.997, ceil 0.992/1.006, round 0.998/0.979, sqrt 1.015/1.025, and sq 1.004/1.003. All 32-encoding, WIRE/LLVM, surplus-argument, block, literal/native-factory autoload, and interpreter gates pass. The Float IC table now retains only `to_i` and `to_s`. |
| Hash `size` | `run_hash_size.sh` | Retained in the relaxed revisit. The public source body is the direct `$count` view-field load and its C IC is removed. The public caller LLVM is identical; the source target is four ARM64 operations plus `ret`, while the C target first validates the Hash tag. Four balanced thread-CPU confirmations ranged from 0.959 to 0.992 source/C, so the old 1.105 result was host/harness noise rather than a generated-code loss. Compiled core checks and a focused interpreter regression pass; bare `$count` now uses the existing allowlisted native-field bridge instead of falling through to an unset global. |
| BigArray `size`, `cap`, `empty?` | `run_small_big_array_public.sh`, `run_big_array_cap_empty_revisit.sh` | Retained in the relaxed revisit. `size` and `cap` load signed view headers, construct canonical immediate Integers inline, and retain exact cold `w_int` BigInt fallbacks; `empty?` is one raw zero comparison. Two independently rebuilt campaigns measured exact parity on inline `cap` and every `empty?` stratum; positive/negative overflow `cap` ratios were 0.923--1.000. All three C IC rows are removed. |
| SmallArray `size`, `cap`, `empty?` | `run_small_big_array_public.sh` | Retained in the relaxed revisit. `size` and `cap` compile to the u8 field load plus immediate tag, while `empty?` compares the raw field directly. Two public campaigns measured 1.000 for all three leaves. The three C IC rows are removed. |
| Mmap `size` | `run_mmap_size_relaxed_audit.sh`, `mmap_size_relaxed_audit.md` | Retained in the relaxed revisit. The source view loads signed `$size`, tags the nonnegative i48 file-length domain directly, and keeps exact cold `w_int` fallback boxing. Two rebuilt campaigns measured 0.950/0.950 paired medians for ordinary mappings and 1.026/1.050 for overflow. The native size IC is removed. |
| Mmap `as_u8/u16/u32/u64`, `as_i8/i16/i32/i64`, `as_f32/f64` | `run_mmap_wrapper_revisit.sh`, `mmap_wrapper_revisit_audit.md` | Retained in the relaxed revisit. Each source leaf makes one exact raw-i64 call to the lower typed-view primitive; the primitive ABI is explicitly widened from C `int` to `int64_t`. Two rebuilt 10-sample campaigns measured ratio-of-medians 0.957--1.083 and paired medians 0.957--1.050. Exact view headers/storage, errors, surplus arguments, blocks, autoload, interpreter, WIRE, and LLVM checks pass. `byte_at`, `[]`, `close`, and `view_at` remain native for diagnostic, provenance, or decoding parity. |
| BigInt `to_i` | `run_identity_leaf_public.sh`, `identity_leaf_public.md` | Retained in the relaxed revisit. The source `self` body preserves exact heap identity and removes the native IC. Two rebuilt public campaigns measured 0.957/0.984 for one-limb values and 0.997/0.967 for multi-limb values. Twenty-six canonical/noncanonical layouts, surplus arguments, bounded real-syntax block parity, no-use autoload, old-bootstrap, and interpreter gates pass. |
| BigInt `zero?`, `even?`, `odd?`, `negative?`, `positive?` | `run_bigint_predicate_relaxed.sh`, `bigint_predicate_relaxed_audit.md` | Retained in the relaxed revisit. The five source bodies read signed `$length` and, for parity only, raw `$limb0`; their native ICs are removed. Two independently rebuilt 10x26 public campaigns passed every stratum. Worst per-method paired medians were 0.994/1.001, 0.992/0.997, 0.969/0.969, 0.990/0.980, and 0.989/0.994. Exact 32-layout, WIRE/LLVM, surplus-argument, block, no-import autoload, and interpreter gates pass. |
| BigInt `neg!`, `abs!` | `run_bigint_bang_ab.sh`, `run_bigint_bang_public.sh` | Retained. Writable scalar native-data fields let both methods update signed `$length` directly; their C handlers and IC rows are removed. Two independent 10x20M balanced direct campaigns measured source/C 0.993/0.988 for `neg!`, 1.001/1.017 for positive `abs!`, and 0.986/0.992 per operation for the branch-taking `neg!; abs!` pair. The true-public before/after campaign improved 6.1--15.5%. Exact receiver identity, 1--4 limbs, spare capacity, compiled/interpreted mutation, WIRE, and signed-i32 LLVM store checks pass. |
| BigInt `abs` | `run_bigint_abs_public.sh` | Retained under the 5% budget — a strict win. The source body mirrors the C IC exactly: identity for effective-positive receivers, `w_bigint_mark_shared_value` plus a tag-overlay flip through `wvalue_from_bits` for effective-negative ones; the IC row is retired. Two public campaigns measured 0.968/0.981 (positive), 0.969/0.962 (negative), and 0.947/0.941 (sign-alternating) against the native IC. The port exposed a tree-walker gap: `wvalue_from_bits` had no BigInt arm, so the interpreter died mid-spec on the first source-level overlay flip — while `bin/tungsten run` still exited 0, hiding the death from tail-line gates. The fix adds the checked `w_bigint_from_bits` bridge (rejects parked/dead headers), and the gate battery now diffs full compiled-vs-interpreter outputs (8 spec pairs byte-identical). Raw samples: `bigint_abs_public_{pre,post_v1,post_v2}_results.txt`. |
| BigInt comparison (`==`, `!=`, `<`, `>`, `<=`, `>=`, `<=>`) | `run_bigint_compare_full.sh`, `bigint_compare_full.w` | **Complete mathematical migration.** Every route requiring BigInt ordering or magnitude work now reaches one allocation-free source comparator covering inline i48 values, heap BigInts, both sign encodings, unequal widths, equality, and arbitrary equal-width limb scans; intentional identical-WValue and inline-Int-only fast paths can finish before it. The C body remains only the stage0 weak default and explicit differential oracle. The compiler unconditionally injects the small support module, rejects a missing, duplicate, or ABI-invalid reserved helper, and emits one strong stable seam, so opaque/runtime-created BigInts cannot silently fall back to C. The same-binary boxed gate runs 4,232 exact C differentials plus every public operator. Eight balanced pairs under `--release --native --fast` measured all 30 strata at median source/C 0.672--1.073; the worst median was 1.073 at three limbs (individual noisy maxima reached 1.154). Retained raw and JSON evidence: `bigint_compare_full_boxed_final_results.{txt,json}`. Host/build: ARM64 T6050 macOS 26.0 target, LLVM 22.1.8, emitted `target-cpu=apple-m4`. |
| BigInt `gcd` | `run_bigint_gcd_native.sh`, `bigint_gcd_public.w` | **RETAINED in the 10% migration revisit with a native Tungsten one-limb kernel.** A same-binary C/source baseline first measured every row at parity (0.997--1.020). The retained untyped source method uses one exact BigInt-tag guard, reads normalized one-limb magnitudes directly, and runs a raw binary-GCD loop (`llvm.cttz.i64`, unsigned subtract/compare, logical shifts) before one inline-or-heap boxing decision. Mixed inline-Int arguments and all multi-limb Lehmer/HGCD shapes still use the reentry-free `w_bigint_gcd` boundary. A typed-overload candidate was rejected because its dispatcher regressed the untouched inline-Int control to 1.423x. Two independent balanced 8-pair campaigns for the retained method measured one-limb BigInt pairs at 1.076/1.076 source/C; inline-Int controls at 1.006/0.954, near-equal four-limb controls at 1.019/1.010, 8-vs-4 skew at 0.973/1.010, and 32-limb shared-factor controls at 0.999/0.998. The harness runs 42 exact C differentials plus divisor/greatest identities, mixed signs, unsigned-high-bit magnitudes, and a heap one-limb result; `gcd_spec.w` passes interpreted and `--release --native --fast`. The source port exposed and fixed stage0's missing `**=`/`&=`/`\|=`/`^=`/`<<=`/`>>=` syntax and `w_u64` boxing support; the rebuilt stage1/stage2 LLVM modules are byte-identical. Raw samples: `bigint_gcd_one_limb_native_{pre,candidate1,candidate2,candidate2_repeat}_results.txt`. Host/build: Apple M5 Max, arm64 macOS 26.6.1, Homebrew LLVM 22.1.8, configured `-mcpu=apple-m5`, `--release --native --fast`. |
| BigInt `isqrt` | `run_bigint_isqrt_public.sh` | **Retained — the exact one- and two-limb C base cases are now native Tungsten.** The two-limb body ports `bn_sqrtrem1`, `bn_sqrtrem2`, and `bn_isqrt_u128` without changing the algorithm: even-bit normalization, hardware-double seed, one 64/64 quotient extension, bounded exact integer corrections, and the same shift-back. It also preserves C's representation/storage boundary: i48 roots are formed inline; larger roots take the hot one-limb BigInt slot and publish limb then size. Wider values and negative-receiver handling retain `bigint_isqrt_any`'s divide-and-conquer C boundary. A stable strong source seam removes dynamic dispatch from the production native benchmark while its weak C definition keeps stage-0/thin binaries linkable; a reopen spec proves ordinary open-world last-definition semantics. Correctness: 6,222 C differentials plus root-bracketing and explicit inline/heap representation checks across 1..64 limbs, including u128 extrema and perfect-square neighbors; `BitOps.leading_zeros_u32/u64` has 100,000-word native and 1,000-word interpreted differentials; compiler stage IR is byte-identical. Matched same-binary source/C ratios for the new two-limb strata are 0.916 (`two`), 0.925 (`two-low`), and 0.953 (`two-square`). Two production bignum 31x500ms promotions are also green at 1.011 and 1.008 C/native; 2/4/8-size C-fallback controls stayed within 1.6% in the preceding 9x110ms screen. Earlier shim-only campaigns remain in `bigint_isqrt_public_{pre,post_v1,post_v2}_results.txt`; reproduce the new rows with the expanded runner. |
### Complete BigInt bitwise acceptance gate

`run_bigint_bitwise_full.sh` compiles `bigint_bitwise_full.w` and
`bigint_bitwise_full_ref.c` into one `--release --native --fast` binary. The
timed lanes cross symmetric noinline wrappers around the public retained-C
oracles and stable strong source seams. The default matrix covers the
documented width points from 1 through 8192 limbs, 4095/4096/4097 boundaries,
odd/remainder
widths, severe skew in both orders, inline mixes, representative sign/width
pairs, both negative encodings, identities, distinct-equal storage, and
normalization/cancellation shapes. It also gates consumed `&=`, `|=`, and
`^=` source seams against the retained C mutation entries at every 1--256-limb
width supported by the established compound matrix. The one-limb correctness
fixtures separately force nonzero i48 AND/XOR results and require exact inline
canonicalization; the timed one-limb fixtures remain heap-valued so they keep
measuring the consumed kernel across the full adaptive lane.

Every row is adaptively calibrated until both lanes run for at least 110ms,
then receives eight balanced C/W/W/C and W/C/C/W pairs. A median source/C
ratio above 1.10 fails. The runner retains raw samples and a JSON summary with
calibration, checksums, quartiles, build/source/IR/binary hashes, target
CPU/triple, host/load/power metadata, and dirty state. Correctness runs the
shape matrix plus 12,288 deterministic exact source/C differentials, public
syntax, explicit sends, reversed operands, canonicality, and
lifecycle-sensitive identity results.

Short diagnostic screens may set `TARGET_NS` and a lower `SAMPLE_MIN_NS`:
calibration still targets `TARGET_NS`, while the separate floor prevents a
single noisy large-width leg from discarding the screen. Full acceptance does
not set that override, so its sample floor remains exactly 110ms.

The default `MODE=accept` is fail closed: it requires one strong completion
marker, one strong seam per operation, and a reachable-LLVM audit proving that
immutable source seams call no retained C/public bitwise fallback. Consumed
seams must likewise avoid retained C math, but their direct raw helpers retain
one explicitly reported matching `w_bit_*` policy edge for non-integer
coercion and error handling; focused Float and invalid-String differentials
exercise that edge. `MODE=baseline` allows an older partial build to be
recorded, explicitly labels its partial source and C/C inline-control rows,
omits compound rows whose old binaries have no strong consumed seams, and is
not a full acceptance result.

The initial full diagnostic is retained as
`tungsten-bigint-bitwise-full-screen-p2-target20ms-floor10ms.{txt,json}`.
Correctness, source-link, and IR gates passed, but 76 of 186 two-pair screening
medians exceeded the 1.10 source/C limit, so this records an implementation
checkpoint rather than a completed performance migration. The independently
measured four-limb AND specialization improved from 1.270200x to 1.075932x in
eight 110ms pairs; its retained evidence is
`tungsten-bigint-bitwise-and-width4-{pre-specialization,candidate-specialized}.{txt,json}`.
No cross-target or GMP claim follows from these host-specific source/C runs.

### Source-path boundary constant — measured, and direct lowering extended (2026-08-08)

Follow-up to the shift skip's "~12ns boundary constant" attribution: on a
quiet host the actual src-vs-C gap for the cheap in-arm ops is ~2ns
(`and-four` src 27.4ns vs C 25.4ns) — the seam gate's two view loads, the
weak-wrapper hop, and the worker re-deriving the shapes the gate already
proved. The alloc/seal boundaries are NOT a recoverable component: they
LTO-inline, and swapping the `&` body's pool alloc for the hot-slot
allocator measured a wash (1.078/1.098 vs the landed 1.076/1.055),
consistent with the add/sub configuration sweep. The shift family's loss
therefore stands on C's kernel superiority at tiny op costs, not on a
removable dispatch tax. What WAS worth extending: the statically-typed
direct route (`lower_binary_op`'s exact-tag-guarded branch straight to
the seam symbol, previously `+`/`-`/`*` only) now also covers `&`, `\|`,
`^`, `/`, `%` — typed sites skip the fast wrapper, runtime entry, and
seam gate entirely, with the guard's slow arm keeping the full
polymorphic chains (rational division through a `## big`-typed site
verified engine-identical). Thin modules bind the seam declarations to
the runtime's weak C defaults exactly as before.

### Division (`/`, `%`) — dispatch plus native one-limb pairs (2026-08-09)

RE-ASSESSMENT (Erik: "I can't think of any reason that the c should be
faster — it likely was assessed on the old dispatch chain"): CONFIRMED
empirically. With the weak-arm seam in `w_div`/`w_mod` routing every
both-heap-BigInt pair through source plumbing bodies
(`BigInt#/(BigInt) -> ccall w_bigint_div`, likewise `%`), two interleaved
ABBA campaigns (`run_bigint_opdivmod_public.sh`, 12 rows) measured worst
rows 1.086 then 1.046 — the one-limb ~11ns row's toll — with every
at-width row 0.97-1.03 (fourtwo, near-equal, and the 11µs Burnikel-Ziegler
band at parity). The dispatch chain is toll-free within the budget, so
`/` and `%` are RETAINED as source-routed operators. What stays in C is
the division KERNEL tier, per the original analysis below — those
paragraphs still describe why a source division kernel is a from-scratch
build, now decoupled from the (solved) dispatch question. Raw samples:
`bigint_opdivmod_public_camp{1,2}_results.txt`; semantics pinned by
`spec/numeric/bigint_divmod_spec.w` (truncated division, both engines).

NATIVE ONE-LIMB FOLLOW-UP: the both-heap one-limb pair now completes in
Tungsten with raw `u64` division/remainder. A heap BigInt divisor is greater
than the signed-i48 maximum, so the quotient is bounded below 2^17 and can be
tagged inline without allocation; modulo tags an inline remainder or uses the
ordinary `w_u64` allocation boundary, then composes the dividend sign. The
expanded harness covers heap/inline remainder, dividend bit 63, |a|<|b|, and
all four sign combinations for both operators, while retaining int-argument,
4/2-limb, near-equal, Burnikel-Ziegler, and signed wider controls. The shim
baseline ranged 0.963--1.097 source/C. A first branchy source body was REJECTED
because generated boxed boolean plumbing put division as high as 1.156.
Replacing that plumbing with raw sign bits and one combined limb-count compare
is RETAINED: two independent balanced 8-pair campaigns measured one-limb
division at 0.987--1.052 then 0.967--1.031, one-limb modulo at 0.744--0.930
then 0.734--0.919, and every wider/control row at or below 1.087. The harness
passes 192 exact C differentials plus q*y+r round-trips; the focused spec passes
interpreted and `--release --native --fast`, including unsigned-high-bit,
inline/heap remainder, zero-quotient, and sign seams. LLVM contains `udiv i64`
and `urem i64` in the source workers. Raw samples:
`bigint_divmod_one_limb_native_{pre,camp1,camp2,camp3}_results.txt`.
Host/build: Apple M5 Max, arm64 macOS 26.6.1, Homebrew LLVM 22.1.8,
configured `-mcpu=apple-m5`, `--release --native --fast`.

EXACT 4-BY-2-LIMB FOLLOW-UP: the positive fixed-width `mag_divmod_42_core`
leaf is now mechanically ported to native Tungsten on macOS ARM64 before any
Tungsten-specific tuning.  The embedded assembly preserves the Clang 22.1.8
`-O3 -mcpu=apple-m5` schedule for the existing C arithmetic leaf: the
same 256-entry Moller--Granlund reciprocal table, normalization, three 3-by-2
quotient-digit steps, correction rules, quotient/remainder capacities, and
`bigint_finish_mag_sub` normalization.  Signed 4/2 pairs and every other width
remain on the C specialization tree.  The public harness now checks 192
ordinary corpus differentials plus 512 adversarial 4/2 C differentials with
independently constructed exact quotients, remainders, and round trips.  A
12-pair same-binary baseline measured native/C at 0.964 for division and 0.982
for modulo; one-limb and signed fallback controls remained within 4.5%.
Retained raw evidence: `bigint_divmod_42_exact_results.txt` and
`bigint_divmod_42_exact_controls_results.txt`.  Those figures describe the
exact port baseline, not a redesigned native algorithm.

EXACT 6-BY-3-LIMB MODULO CHECKPOINT: the positive `mag_mod_63` arm is ported
with the corrected C algorithm and its Clang 22.1.8 `-O3 -mcpu=apple-m5`
schedule before native-only tuning.  The source body preserves the 96-byte
scratch frame, reciprocal table, four quotient-digit steps, capacity-3 hot
allocation, and `bigint_finish_mag_sub` policy; division and signed 6/3 pairs
remain in C.  Its algebraic corpus first exposed and fixed a C carry-loss bug
when the leading low-limb borrow overflowed the two-limb prefix.  The focused
check now covers 208 ordinary corpus differentials, 512 adversarial 4/2
differentials, and 512 independently constructed 6/3 differentials.  The
first 12-pair exact-port baseline is deliberately retained even though it is
not yet a win: native/C was 1.068 (36.763 ns versus 34.384 ns median).  Raw
evidence: `bigint_mod_63_exact_results.txt`.  This checkpoint is the exact
port requested before changing the native schedule.

NATIVE 6-BY-3 STORAGE FOLLOW-UP: after the exact checkpoint, the source leaf
was allowed to optimize only its result handoff.  It now accepts the boxed
operands directly, computes the same limbs before allocating, and tail-calls
one shape-specific runtime boundary that performs the capacity-3 hot
allocation, publishes all three limbs, and applies the unchanged
`bigint_finish_mag_sub` policy.  The reciprocal arithmetic and every quotient
correction arm remain byte-for-byte the exact port above.  A 31-pair matched
run improved native/C from the checkpoint's 1.065 to 1.024 (34.725 ns versus
34.138 ns median), recovering about 3.9% of total time while remaining an
honest 2.4% C win.  The untouched 4/2 control remained green at 0.969; signed
6/3 stays on C.  Raw evidence:
`bigint_mod_63_native_finish_results.txt`.

EXACT 6-BY-3-LIMB QUOTIENT CHECKPOINT: the positive
`mag_div_q_63_certified` arm is now mechanically ported before native-only
tuning.  Its generated AArch64 body is the Clang 22.1.8
`-O3 -mcpu=apple-m5` schedule for the existing C arithmetic: identical
normalization, reciprocal table, four fixed quotient digits, saturated and
add-back paths, triangular certificate, capacity-four allocation, failure
release, and fallback into the unchanged C division tree.  The arithmetic
leaf has a 48-byte frame and no calls.  The same 1,232-case public q/r corpus
is green.  As required for an exact-first migration, the initial loss is
retained rather than hidden: a 12-pair matched run measured native/C at 1.165
(105.002 ns versus 90.226 ns median); 4/2 and signed controls remained green.
Raw evidence: `bigint_div_63_exact_results.txt`.

NATIVE 6-BY-3 QUOTIENT FOLLOW-UP: counters showed that an inconclusive native
certificate re-entered `bigint_div_any`, which executed the same fixed 6/3
certificate in both the boxed arm and `mag_divmod` before reaching the
reciprocal/triangular/Knuth continuation.  The source failure edge now releases
its speculative capacity-four result and resumes at that exact continuation;
the certificate arithmetic and every later selection threshold are unchanged.
The redundant C certificate disappeared from the counter profile.  A promoted
31-pair run reduced native from the exact checkpoint's 105.002 ns to
70.998 ns; native/C is 0.782 versus the checkpoint's 1.165.  The 4/2 and
signed controls remained green at 0.966 and 0.957.  Raw evidence:
`bigint_div_63_resume_results.txt`.

EXACT 8-BY-4-LIMB QUOTIENT CHECKPOINT: the positive 8/4 specialization of
`mag_div_q_triangular_certified` is now mechanically ported before changing
the native routing or algorithm.  The embedded AArch64 body preserves the C
algorithm's normalization, reciprocal table, five register-carried quotient
digits, lazy-low rows, saturated `bn_submul_1` and add-back paths, sufficient
certificate, capacity-five allocation, and `bigint_finish_mag_sub` policy.
On the retained public benchmark corpus the certificate is inconclusive on
all 64 operands, so the exact source failure seam resumes at `mag_divmod` and
preserves C's second certificate attempt before Knuth fallback.  The
1,760-case public differential corpus, focused 39-check division spec, LLVM
verification, and runtime object build are green.  A 31-pair promotion with
roughly 500 ms legs measured native/C at 0.97964 (88.782 ns versus 90.609 ns),
with 31/31 native wins and 0.00710 paired-ratio IQR.  This records the exact
checkpoint; skipping the known-redundant second certificate is reserved for a
separate native-only follow-up.  Raw evidence:
`bigint_div_84_exact_results.txt` and
`bigint_div_84_exact_promotion_results.txt`.

NATIVE 8-BY-4 QUOTIENT FOLLOW-UP: the retained public corpus proves the first
triangular certificate inconclusive on every operand.  At four divisor limbs
the reciprocal path's minimum is 256 limbs and the B-Z gates are 24/64, so the
exact checkpoint's resumed `mag_divmod` can only repeat the same certificate
and then select Knuth.  The native failure seam now resumes directly at that
proven Knuth destination; the ported quotient digits, certificate, allocation,
Knuth kernel, and finalization are unchanged.  A promoted 31-pair run measured
native/C at 0.70920 (64.358 ns versus 90.832 ns), with 31/31 native wins and
0.00612 paired-ratio IQR.  This is a routing improvement after the separately
committed exact checkpoint, not a replacement division algorithm.  Raw
evidence: `bigint_div_84_resume_results.txt` and
`bigint_div_84_resume_promotion_results.txt`.

8-BY-4 MODULO PORT PREPARATION: the new exact 8/4 stratum and 512-case
algebraic edge matrix exposed a pre-existing `mag_mod_84` saturated-digit
handoff bug.  Its corrected five-limb window must advance `(w3,w2)` as the
next register remainder pair; the old `(w4,w3)` mapping shifted the recurrence
by one limb.  The generic Knuth path independently confirmed the oracle, and
`(B^4-1)^2+r` now has a focused spec regression.  Before any native 8/4
arithmetic was added, a 12-pair source/C baseline measured 1.028 (37.878 ns
versus 36.859 ns); both lanes still execute the corrected C leaf.  Raw
evidence: `bigint_mod_84_preport_results.txt`.

EXACT 8-BY-4-LIMB MODULO CHECKPOINT: the corrected positive `mag_mod_84`
arm is now ported before any native-Tungsten redesign.  The embedded AArch64
body is the Clang 22.1.8 `-O3 -mcpu=apple-m5` schedule for the C leaf:
identical normalization, shared two-entry TLS preinverse cache, five
Moller--Granlund 3-by-2 quotient digits, saturated `bn_submul_1` and add-back
paths, and corrected consecutive-saturated-digit handoff.  Arithmetic finishes
before the unchanged capacity-four hot allocation and
`bigint_finish_mag_sub` policy.  The 1,760-case public corpus and focused
division spec are green.  A promoted 31-pair same-binary run measured native/C
at 0.993 (36.326 ns versus 36.555 ns); the 4/2 control was 0.983 and the
already-native 6/3 control 1.029.  This is the exact-port checkpoint, not a
native-only algorithm change.  Raw evidence: `bigint_mod_84_exact_results.txt`.

NATIVE 8-BY-4 CACHE FOLLOW-UP: counters attributed 1.5% of total cycles to
Mach-O TLS resolution because the exact C layout stores each preinverse field
behind a separate descriptor.  Native Tungsten now stores the same two
`(d1,d0,value)` entries and incrementing round-robin selector in one private
TLS object, reducing a hit from three descriptor resolutions to one.  The
reciprocal, five quotient digits, correction paths, allocation, and
normalization are unchanged.  In a direct exact-vs-native 31-pair promotion
with 500 ms legs, the combined cache won 30/31 pairs: candidate/exact was
0.98899 with 0.00829 paired IQR (35.934 ns versus 36.312 ns medians);
C-normalized candidate/exact was 0.98768.  Raw evidence:
`bigint_mod_84_native_tls_results.txt`.

EXACT POSITIVE ADD1@3 CHECKPOINT: the positive three-limb receiver plus
positive one-limb BigInt arm now has a literal native Tungsten port of C's
`BN_WORD_FIXED_CASE(3)` schedule on macOS ARM64: the same `ldp`/`ldr` loads,
`adds`/`adcs` chain, `stp`/`str` publication, and carry result.  The source
wrapper also retains `bigint_add_ui_any`'s storage policy rather than hiding
the hard part behind a larger allocation: it asks the hot allocator for
exactly three limbs and only the full-carry edge grows to a non-hot cap-four
buffer, copying/zeroing/releasing exactly like `bigint_add_word_into`.
Compiled and interpreted focused specs cover no carry, one-limb carry death,
full three-limb carry, exact header size, round trips, neighboring widths, and
sign fallbacks; emitted LLVM verifies and the final leaf is the intended nine
instruction arithmetic/storage body plus `ret`.  The exact checkpoint is not
yet performance-accepted: a 9x110 ms public `add1@3` run measured native
source at 6.095 ns versus C at 1.821 ns and GMP at 1.839 ns.  A hardware-
counter profile attributes 10.2% of cycles to the native leaf and contains no
`bn_add_word_a64_fixed`, proving this is the admitted source route rather than
a stale C measurement.  That retained
gap is the starting point for a separately committed native-only routing and
boundary optimization, not permission to alter the C algorithm during the
port.  Evidence: `bigint_add1_3_exact_results.txt`.

NATIVE ADD1@3 FOLLOW-UP: after the literal C port was checkpointed, a separate
native-only pass removed two surrounding costs without changing the leaf's
arithmetic, storage, growth, or normalization.  Exact `(BigInt BigInt)` `+`
facts now select the ordinary guarded source seam, and the positive boxed
add/add1 harness returns dead results through the same typed BigInt recycler
contract used by the C lane instead of the general heap-kind dispatcher.  An
11-pair matched release-boundary A/B won 11/11 (3.679 ns to 2.507 ns,
candidate/baseline 0.67986), and a 31-run public promotion measured native at
2.497 ns versus C at 1.779 ns and GMP at 1.721 ns.  Thus native is 59.0%
faster than the exact checkpoint's 6.095 ns, while the remaining 40.4% gap to
C is retained honestly.  Broader 2..64-limb controls all improved; attempted
private pre-entry and header-store shortcuts were rejected because they
regressed controls.  Evidence: `bigint_add1_3_native_results.txt`.

EXACT POSITIVE ADD1@4 CHECKPOINT: the adjacent positive four-limb receiver
plus positive one-limb BigInt arm now has the same exact-first treatment.
Native source contains C's literal two-`ldp`, `adds`/three-`adcs`, two-`stp`,
`cset` schedule; it requests the same hot cap-four result and preserves the
rare grow-to-five epilogue byte-for-byte.  Compiled and interpreted focused
checks cover no carry, carry death at two depths, full four-limb propagation,
the 4→5 growth, exact header sizes, round trips, signs, and neighboring
widths.  In an 11-pair matched test the source port won every pair, reducing
the native lane from 4.150 ns to 2.527 ns (candidate/baseline 0.60958).  The
public row remained slower than C/GMP at 2.528 ns versus 1.805/2.089 ns, so
the exact schedule is checkpointed without claiming native parity.  Counter
profiles move the row from `w_bigint_add`/`bn_add_word_a64_fixed` to the
leaf-only `__bigint_add1_4_exact`.  Evidence:
`bigint_add1_4_exact_results.txt`.

EXACT POSITIVE ADD1@2 CHECKPOINT: the two-limb arm is now the literal
`BN_WORD_FIXED_TWO_FN` schedule in native source (`ldp`, `adds`, `adcs`,
`stp`, `cset`), with the same hot cap-two allocation and rare grow-to-three
result construction.  The matched target row won 11/11 pairs, 3.601 ns to
2.506 ns (candidate/baseline 0.69495), and counters moved from
`w_bigint_add` to the leaf-only `__bigint_add1_2_exact`.  As an exact-first
checkpoint it also records rather than conceals code-layout fallout: before
the separate dispatch follow-up, @1 and @4 controls regressed about 3% while
@3 improved and @5 was neutral.  Compiled/interpreted checks cover no carry,
carry death, full 2→3 growth, exact header sizes, round trips, signs, and
neighbors.  Evidence: `bigint_add1_2_exact_results.txt`.

NATIVE FIXED ADD-WORD DISPATCH FOLLOW-UP: after the exact 2/3/4-limb leaves
were separately checkpointed, their repeated shape tests were replaced by one
`bn == 1` gate and a compact `case an` selector.  Arms 2, 3, and 4 still call
the byte-for-byte exact ports; arm 1 and the default tail return directly to
the unchanged C boundary.  Final AArch64 lowering is a comparison tree, not a
jump table, and no arithmetic, allocation, growth, or normalization policy is
changed.  Across matched 11-pair runs every tested width from 1 through 64 won
all 11 pairs.  Candidate/baseline medians were 0.647 at @2, 0.966 at @3,
0.959 at @4, and 0.925--0.959 at the unported 5..64 controls.  The public
native lane remains slower than C through @8, while beating GMP from @16;
those remaining gaps are inputs to later native-only work, not reasons to
change the exact ports.  Evidence: `bigint_add1_fixed_dispatch_results.txt`.

EXACT POSITIVE ADD1@5 CHECKPOINT: the five-limb arm extends the literal port
with C's two `ldp` plus one `ldr`, `adds` plus four `adcs`, two `stp` plus one
`str`, and final `cset`.  It requests the same cap-five hot result and keeps
the full-carry grow-to-six construction unchanged.  The target won all eleven
matched pairs, falling from 3.881 ns on the retained C tail to 2.618 ns native
(0.67608).  The @4 control was neutral at 0.98991; the still-unported @6 row
moved to 1.02981 from code layout and is retained honestly for the next exact
arm.  The public row measured 1.743/2.628/2.147 ns for C/native/GMP.  Counters
attribute 58.4% of cycles to the exact source leaf and no samples to the C
fixed kernel.  Evidence: `bigint_add1_5_exact_results.txt`.

EXACT POSITIVE ADD1@6 CHECKPOINT: the six-limb arm is likewise C's literal
three-`ldp`, `adds`/five-`adcs`, three-`stp`, `cset` schedule with the same
cap-six hot allocation and full-carry grow-to-seven path.  It won all eleven
target pairs, 3.958 ns to 2.679 ns (0.67691).  The @5 control improved 3.8%;
the unported @7 control was unresolved at 1.01156 with a wider 0.02253 IQR.
The public row was 1.751/2.673/2.352 ns for C/native/GMP.  Counters show only
the source leaf, source operator, and TLS allocator on the hot path, with no C
word kernel.  Evidence: `bigint_add1_6_exact_results.txt`.

EXACT POSITIVE ADD1@7 CHECKPOINT: native source now contains C's exact
three-`ldp`/one-`ldr`, `adds`/six-`adcs`, three-`stp`/one-`str`, `cset`
seven-limb schedule, plus the unchanged cap-seven and rare 7-to-8 growth
policy.  The target won 11/11 pairs, 3.996 ns to 2.737 ns (0.68522).  The @6
control improved 5.2%, while the still-C @8 control was neutral at 0.99248.
The public row measured C/native/GMP at 1.887/2.731/2.585 ns.  Counter samples
attribute 74.8% of cycles to the exact leaf, which has no callees, and none to
the C word kernel.  Evidence: `bigint_add1_7_exact_results.txt`.

EXACT POSITIVE ADD1@8 CHECKPOINT: this port follows the current optimized C
arm, including its four upfront `ldp` loads, two-limb common carry chain,
unlikely branch to the six-`adcs` ripple, duplicated four-`stp` publication,
and zero/carry return paths.  The cap-eight hot allocation and rare grow-to-
nine construction are unchanged.  The target won 11/11 pairs, 4.222 ns to
2.774 ns (0.65751).  Unported @9/@16 controls were unresolved near 1.015;
the already-native @7 row regressed 7.3% from layout and is preserved as an
explicit exact-checkpoint cost for the following dispatch optimization.  The
public @8 row was 1.886/2.781/3.024 ns for C/native/GMP.  Evidence:
`bigint_add1_8_exact_results.txt`.

NATIVE ADD1@7 CARRY-DEATH FOLLOW-UP: with every fixed arm checkpointed, the
seven-limb native leaf now branches after limb one.  The common path publishes
the five unchanged high limbs directly; the vanishingly rare surviving-carry
path executes the former full chain.  A 31-pair 500 ms promotion won 31/31 at
0.93297 (2.705 ns versus 2.912 ns).  Eleven-pair controls at 1..6, 8, 9, 16,
32, and 64 limbs stayed within 0.8% except noisy @16, which remained within
its 3.7% IQR.  The public @7 row became 2.559 ns, just faster than GMP at
2.597 ns but still behind C at 2.010 ns.  Shared-wrapper consolidation and an
@7 precheck were rejected because they regressed other fixed arms.  Evidence:
`bigint_add1_7_carry_death_results.txt`.

### Original kernel assessment (2026-08-08, governing remaining wider kernels)

Add, subtract, and multiply each migrated by standing on an existing
hand-written asm kernel (`asm_add_no`, `asm_sub_no`, `asm_mulbase`), which
let every source body reduce to shape tests plus a single kernel call with
no limb loop. Division has no comparable kernel, and none of its primitives
exist as WIRE ops:

- a preinverse 2-by-1 divide (AArch64 has no 128/64 divide instruction, so C
  builds a multiply-based reciprocal and caches it in `BnDivPreinvCache`),
- Burnikel-Ziegler recursive division for the large band,
- Jebelean exact division (`mag_divexact`) for the exact-quotient case,
- width-specialized `mag_div_q_63_certified`, `mag_div_triangular_certified`,
  and `mag_mod_{84,63,42}`.

The exact 4-by-2 leaf above is the first deliberate exception to this earlier
disposition: it ports one already-tuned C specialization rather than inventing
a replacement kernel.  The recursive, exact-division, and remaining certified
width bands stay in C until each can be ported and oracle-validated with the
same discipline.  The protocol, harnesses, weak-linkage seams, and shape-gate
machinery are in place for that arm-by-arm migration.

Shift profiling note (2026-08-09): the public BigInt benchmark sink now
releases fresh results through `w_value_free`, matching production's recycler
instead of bypassing it with libc `free`. On `shr-sf13`, the corrected sink
changed the absolute medians from roughly 39--40 ns/op to 17.971 ns C and
18.991 ns source-shim (paired source/C 1.059). The corrected tungsten-flame
profile makes `w_bigint_shr` the dominant cost at 48.3% self; allocation,
release, and value-free account for 19.3% combined. Raw evidence:
`bigint_shr_sf13_recycler_sink_results.txt`,
`bigint_shr_sf13_recycler_profile.sample.txt`, and
`bigint_shr_sf13_recycler_profile.folded`. Host/build: Apple M5 Max, arm64
macOS 26.6.1, Apple clang 21.0.0, `--release --native --fast`, base `9c68b1d`.

Mid-width right-shift funnel (2026-08-09): positive sub-limb `>>` now has a
native Tungsten kernel for 33..96 limbs. It allocates through the hot-slot
handoff, runs one portable raw-limb funnel, and publishes the normalized i32
size with a direct explicit-receiver view-field store. The compiler work this
required is general: parser, stage-0 interpreter, and lowering now support
`receiver$field = value` and compound assignment; the same source bootstraps
without a C metadata-publisher bridge. Import paths are normalized before
loader identity checks, fixing `core/...` versus `./core/...` duplicate loads.
The initial sweep correctly rejected broad admission: source/C reached 1.126
at 192 limbs, 1.230 at 256, and 2.285 at 4096. After narrowing the runtime and
source gates, a 12-pair same-binary campaign measured 1.074/1.075 at the
33-limb normal/trim boundary, 1.064 at 40, 1.068 at 64, 1.065 at 65, 1.033 at
80, and 1.039 at 96. C-retained controls were 1.002 at 32, 1.006 at 97, and
0.975--1.000 at 128 through 4097 limbs. The harness now covers 39 correctness
strata; interpreted and native shift specs pass all 674 checks; stage 1 and
stage 2 emit byte-identical LLVM; the final IR has strong shift seams, a raw
`w_bigint_alloc_hot(i64)` call, and a direct `store i32` with no publisher
helper. Raw evidence: `bigint_shr_funnel_direct_store_smoke_results.txt`,
`bigint_shr_funnel_threshold_sweep_results.txt`, and
`bigint_shr_funnel_direct_store_final_results.txt`. Host/build: Apple M5 Max,
arm64 macOS 26.6.1, 128 GB, Homebrew LLVM 22.1.8, GMP 6.3.0,
`--release --native --fast`; user config `build.cpu = apple-m5` (this LLVM
build stamps the emitted module with `target-cpu=apple-m4`).

| BigInt `&` | `run_bigint_opand_public.sh` | **RETAINED — the first bigint BITWISE operator migrated to source.** The arm is both-heap-BigInt, both effective-positive, 2..4096 limbs, `a != b` (`bigint_bitwise_src_shape`); C keeps one-limb pairs (fused u64 arm), every negative operand (the fused on-the-fly two's-complement pass), and the aliased-receiver identity. The source body has no limb loop in Tungsten: shape tests, one pool allocation, one class-scoped embedded-`ll` kernel call (`__bigint_bw_and`), seal. The kernel is HAND-VECTORIZED `<2 x i64>` IR — bitwise ops have no carry chains, so no per-arch asm is needed, and explicit vector IR sidesteps the vectorizer's runtime alias checks (the fresh result buffer cannot be proven noalias from inside a kernel). The FIRST kernel (2 limbs/iteration) was REJECTED: `and-sixtyfour` measured 1.149/1.136 in two interleaved campaigns. The retained kernel processes 4 limbs/iteration (two `<2 x i64>` ops) with pair+scalar remainder blocks; per-width control flow is branch-resolved, not loop-carried. Two interleaved ABBA campaigns (8 pairs/stratum, thread-CPU clocks, loaded host — pairing is the drift-cancelling instrument): worst rows 1.076 then 1.055 (`and-four`); `and-fortyeight` 0.879/0.881 and `and-skew` 0.917/0.909 — source FASTER than C, including at the 48-limb page-rehome hazard width; controls (`one` 1.013/1.023, `int-arg` 0.990/0.994, `neg` 1.021/1.026) at parity, proving the gate selects the intended shapes. Correctness: 247-case matrix (15 widths to 4097 limbs, all four sign combos, structured cancellation/demotion/sparse cases) byte-identical to C AND to the Python oracle; reopened-`&` sentinel proves infix routing through the seam with `TUNGSTEN_BIGINT_SRC_OPS=0` pinning C; `spec/numeric/bigint_bitwise_spec.w` pins semantics byte-identically on both engines. New surface this port needed: `&`/`|`/`^` operator METHOD NAMES in both parsers (the lexer fuses `&(` into one BLOCK_CALL token — both `parse_method_def`s and the tight-dot call site treat it as name `&` with the paren pre-consumed), walker delegation of BigInt `&`/`|`/`^` sends to `w_bit_and`/`w_bit_or`/`w_bit_xor`, and receiver-gated loader spellings (a receiverless call named `&` is block invocation — gating on it autoloaded Integer/BigInt into every block-using program including the compiler itself, which broke stage identity until the `call_receiver != nil` test). Raw samples: `bigint_opand_public_camp{1,2}_results.txt`. |
| BigInt `\|` | `run_bigint_opor_public.sh` | **RETAINED.** Same arm and body shape as `&`; the kernel (`__bigint_bw_or_uneq`) is two-phase — quad `<2 x i64>` OR over the shorter operand's limbs, then a quad copy of the longer operand's remainder — so the result is exactly max-width and its top limb is the longer operand's (seal's trim exits immediately). Campaigns (interleaved ABBA, thread-CPU): a first run on a load-12 host read `or-sixtyfour` 1.144, which did NOT reproduce on a quiet host — 1.034 (10 pairs) and 1.021 (full 8-pair campaign); worst passing row `or-four` 1.090, with `or-fortyeight` 0.887/0.936 and `or-skew` 0.939/0.946 FASTER than C (the 48-limb win is C paying its own page-rehome hazard guard, which fires at exactly n=48). Controls at parity (one 1.001, int-arg 1.009, neg 1.049). Correctness: fresh 247-case OR matrix byte-identical to C and Python; reopened-`\|` sentinel proves seam routing; OR rows added to `spec/numeric/bigint_bitwise_spec.w` (both engines byte-identical). Raw samples: `bigint_opor_public_camp{1,2}_results.txt`. |
| BigInt `^` | `run_bigint_opxor_public.sh` | **RETAINED — completes the bitwise family.** Same arm and two-phase kernel shape as `\|` (`__bigint_bw_xor_uneq`: quad `<2 x i64>` XOR over the shorter operand + quad tail copy), plus a straight-line equal-4 fast path at kernel entry: the first kernel measured `xor-four` 1.115-1.121 against C's fully-unrolled `BN_BITWISE_SMALL` n≤4 arm, and the fast path (one compare, two vector ops, ret) brought it to 1.055/1.087. Two clean campaigns: worst rows 1.055 then 1.087; `xor-fortyeight` 0.774/0.771 and `xor-skew` 0.968/0.969 FASTER than C; controls at parity. Equal-length XOR can cancel every shared top limb — seal's trim restores canonical form, pinned by the matrix's cancellation rows and `spec` `xor_eq_cancel` (result demotes to inline 67). Correctness: fresh 247-case XOR matrix (including near-identical values and full-top-cancellation pairs) byte-identical to C and Python; reopened-`^` sentinel proves seam routing; XOR rows in `spec/numeric/bigint_bitwise_spec.w` byte-identical across engines. Raw samples: `bigint_opxor_public_camp{1,2}_results.txt`. THE WHOLE `&`/`\|`/`^` FAMILY IS NOW SOURCE-ROUTED on the both-effective-positive multi-limb arm, with C retaining one-limb, negatives, and identity — the same boundary the arithmetic operators landed on. |
| BigInt `<<`, `>>` | `run_bigint_opshift_public.sh`, `bigint_opshift_public.w` | **RETAINED in the 10% migration revisit with native Tungsten mid-width sub-limb funnels, signed one-limb and multi-limb demotion, zero-shift identity, right-overshift, and negative-count left-overshift arms; rejected allocation-producing shapes route directly to C.** The earlier full source kernel remains useful rejected evidence: rebuilding through separate source alloc/kernel/seal boundaries lost 1.21-1.45x (2.66x on one-limb `>>`). Typed `BigInt#<<(Int)`/`>>(Int)` methods own the source fast paths; measured native funnels construct mid-width positive sub-limb results in source, while reentry-free `w_bigint_shl`/`w_bigint_shr` boundaries preserve tuned C kernels for remaining source-admitted shapes. Weak/strong seams make infix syntax source-routed, while `TUNGSTEN_BIGINT_SRC_OPS=0` pins the same binary to C. Two balanced 8-pair campaigns covered 4/64/256-limb, aligned/funnel, large-count, and negative strata; worst source/C was 1.034 then 1.014. The follow-on native one-limb arm admits only positive right shifts whose limb result provably fits signed i48: the source body performs one raw `lshr` and directly forms the NaN-boxed Integer, allocating and calling no C shift kernel. Two 12-pair campaigns measured this arm at 0.922 and 0.945 source/C; a one-limb heap-result control stayed on C at 0.996/0.981 and the four-limb source-shim control stayed 1.009/1.003. The matching negative one-limb arm rounds arithmetically as `-ceil(magnitude / 2^k)` and admits only results through the exact `-2^47` boundary; two post-change 12-pair campaigns measured 0.828/0.835 source/C, while a negative heap-result control remained in C at 1.004/1.002 and the existing positive native arm stayed 0.950/0.947. Positive multi-limb shifts that discard all but the top limb now load and shift that limb directly when the result fits i48: the C-backed source-shim baseline was 1.068/1.079 for unaligned/aligned four-limb cases; two native 12-pair campaigns measured 0.635/0.569 and 0.659/0.573, while ordinary four/64-limb fallbacks stayed 1.015/1.043 and 1.002/1.020. Negative 2–4-limb demotion unrolls the discarded-limb sticky test and rounds as `-(q+1)` whenever any bit is lost: its shim baseline was 1.089/1.101 for unaligned/aligned cases; two native 12-pair campaigns measured 0.588/0.545 and 0.586/0.546, with an ordinary negative four-limb fallback at 1.048/1.054. For wider negatives, source demotion is deliberately proof-gated to cases where the top residual or limb zero proves sticky without a scan; at 64 limbs its shim baseline was 1.094/1.101, two native campaigns measured 0.577/0.540 and 0.581/0.543, and the ordinary fallback stayed 1.003/1.040. Sparse unknown-sticky shapes remain in C. The native overshift arm uses only effective sign and limb count, returns inline 0/-1 without reading limbs or calling C, and applies at every width (including above the 4096-limb shim band). Its pre-change source shim measured 1.029/1.060 source/C for positive/negative; two post-change 12-pair campaigns measured 0.888/0.881 and 0.871/0.859, while the ordinary four-limb control stayed 1.006/1.001. The semantic mirror, `x << -k`, now takes the same metadata-only completion when `k` covers the magnitude: its source/C shim baseline was 1.005/1.009 for positive/negative receivers, while two native 12-pair campaigns measured 0.899/0.886 and 0.897/0.913; the ordinary positive-count left-shift control stayed 0.994/1.010. Zero-shift identity now source-routes both directions and signs through the immutable alias-handoff primitive, then returns `self`: two 12-pair campaigns measured 1.044/1.088 and 1.044/1.025 for positive/negative `<< 0`, plus 1.013/1.024 and 1.019/1.002 for `>> 0`; allocation-producing one-limb cases remain in C. The positive right-shift funnel is retained at 33..96 limbs: its final 12-pair ratios were 1.033--1.075 across admitted cells, while 32/97/128/192/256/4096/4097 controls measured 0.975--1.006. The positive left-shift funnel is retained at 65..224 limbs: its final 12-pair ratios were 0.927--1.081 across admitted cells; 64/225/256/4096/4097 controls bypassed source at 0.995--1.010. A broad left-shift sweep rejected 256 and 4096 limbs at 1.199 and 1.868. Correctness: the public harness passes forty-one strata; `bigint_shift_source_spec.w` checks 1,010 width/sign/count/i48-boundary cases against a division oracle on both engines including negative counts, overshifts, the 64/65 and 224/225 funnel seams, and the 4096/4097-limb boundary; the 1..64-limb sweep and identity specs pass compiled/interpreted; LLVM shows the positive one-limb arm as a raw limb load, `lshr i64`, bound test, and tag OR; the negative arm adds only a remainder test and conditional rounding increment; the positive multi-limb arm performs one dynamic top-limb load and residual shift; the negative 2–4-limb arm adds raw unrolled sticky loads and one rounding increment; the wide-negative arm uses only top/low-limb sticky proofs and contains no scan; the overshift arms use raw sign/size/count tests followed by direct tag formation; zero shifts call only `w_bigint_mark_shared_value` before returning. Raw samples: `bigint_opshift_public_source_camp{1,2}_results.txt`, `bigint_shr1_native_camp{1,2}_results.txt`, `bigint_shr1_negative_native_{pre,camp1,camp2}_results.txt`, `bigint_shr_toplimb_native_{pre,camp1,camp2}_results.txt`, `bigint_shr_toplimb_negative_native_{pre,camp1,camp2}_results.txt`, `bigint_shr_toplimb_wide_negative_native_{pre,camp1,camp2}_results.txt`, `bigint_shr_overshift_native_{pre,camp1,camp2}_results.txt`, and `bigint_shl_negative_overshift_native_{pre,camp1,camp2}_results.txt`, `bigint_shift_zero_source_{pre,camp1,camp2}_results.txt`, `bigint_shr_funnel_{direct_store_smoke,threshold_sweep,direct_store_final}_results.txt`, and `bigint_shl_funnel_{pre,threshold_sweep,final}_results.txt`. Host/build: Apple M5 Max, arm64 macOS 26.6.1, Homebrew LLVM 22.1.8, GMP 6.3.0, configured `-mcpu=apple-m5`, `--release --native --fast`, bases `7722ba8`/`906b6ee`/`41e2738`/`c064848`/`8d76ffb`/`7ca1f73`/`ec531d5`/`5d2478b`/`f01623f`/`e60ff98`. The remaining C shift kernels are later arithmetic-kernel migration work. |
| BigInt `*` (schoolbook band) | `run_bigint_opmul_public.sh` | **RETAINED.** `asm_mulbase` writes the whole na+nb product in one asm block, so `BigInt#*` has no limb loop: shape tests, one allocation, one kernel call, seal (which trims the possible high zero limb); sign is the XOR of the operands' effective signs. The arm is both operands 2..24 limbs, excluding equal-length same-raw-sign pairs (C's `bigint_mul_positive_equal`) and self-multiplication (C's squaring path); every Karatsuba/Toom/NTT crossover and the n-by-1 specializations stay in C. Measured: `mul-mixed` 0.933 and `mul-skew` 0.936 — both FASTER than C — with the C-retained rows at 1.000-1.060. The harness carries deliberate control rows: one-limb and inline-int below the band, and 64x64 above it, all of which must sit at ~1.00 because C still handles them; they did (1.032, 1.023, 1.000), which is what proves the gate selects the intended shapes rather than reporting a vacuous pass. Correctness: 600-product matrix (nine widths, four sign combinations, plus `/` and `%` round-trips) byte-identical to the C oracle on the first attempt — a direct dividend of the add/sub debugging (plain if/else for raw limb addresses, polymorphic `w_mul` fallback, no source limb loop). **The same boundary emerged independently for all three operators: C wins equal-length same-sign pairs and one-limb operands; source wins everything else in range.** |
| BigInt `+` and `-`, unequal-length arm | `run_bigint_opadd_public.sh`, `run_bigint_opsub_public.sh` | **RETAINED — the first bigint OPERATORS migrated to Tungsten source.** The arm is every multi-limb pair (2..4096 limbs) EXCEPT equal-length pairs whose RAW operand signs match; C keeps those (its `bigint_add_equal_fast`/`bigint_sub_equal_fast` arms) plus one-limb operands (fused u64). The exclusion must key on RAW signs, not the effective signs after `-` flips its argument: `a - b` with both operands positive is precisely `sub_equal_fast`'s domain, and testing post-flip inverted the condition and mis-routed it into source at 1.21-1.24. The tell was two harness rows that compute the same thing (equal-length magnitude subtract) disagreeing — `add-mixed` 1.036 versus `sub-four` 1.236 — which is only explicable if the specialization keys per-operator on raw signs. On the migrated arm the source path is FASTER than C: `add-skew` 0.954 then 1.004, `sub-skew` 0.955 then 0.961 across two independent 16/20-run campaigns (64-limb + 4-limb, same-binary A/B). C-handled rows stayed at parity (0.99-1.06). Getting there took four measured corrections, each named by the previous measurement: (1) a source tail loop over the longer operand's remaining limbs ran on the strided view-field path — 2.49/2.01; replaced by fused `asm_add_uneq`/`asm_sub_uneq` kernels that combine over the shorter operand and propagate across the remainder in ONE pass → 1.247/1.220; (2) the propagate ran to completion even though a carry dies almost immediately (it survives only an all-ones limb) — added a carry-death branch into a copy loop; (3) that copy moved 8 bytes per iteration against C's NEON `memcpy` — widened to 4-limb `ldp`/`stp` quads with a scalar remainder, which is what closed `+` (1.240 → 0.954). The copy path is only reachable once the carry is provably dead, so it exits with an explicit zero carry and the `cmp` inside it may clobber flags safely. The source bodies now contain NO limb loop on the fast path: shape tests, one allocation, one fused kernel call, one optional carry-limb store, seal. Correctness: 3072-case matrix (ten widths, four sign combinations per operator, cancellation, round-trips) byte-identical to the C oracle; Python-oracle probe on unequal-length pairs; `wn_limb` asm cross-check; 15-spec battery on both engines including `rational`/`complex` (mixed-type coverage the bigint matrix cannot provide); stage-1/stage-2 identity. Levers: `TUNGSTEN_BIGINT_SRC_OPS=0` pins C at the runtime arm, `TUNGSTEN_BIGINT_DIRECT_OPS=1` opts typed call sites into direct lowering. |
| Bigint operators, earlier 5%/10% attempts (superseded) | `run_bigint_opadd_public.sh` | Historical: nine kernel bodies rejected before the fused-kernel design above. With the gate relaxed from 5% to 10%, the campaign asked which *shapes* source could win and gated the runtime arm accordingly. Measured, all same-binary A/B: one-limb 1.40-1.50 (C's fused u64 arm) — fixed by handing one-limb back to C via `bigint_src_shape`, which then measured 0.99-1.06; equal-length pairs 1.13-1.19 against `bigint_{add,sub}_equal_fast`; and — the decisive one — **unequal-length pairs 2.49 (add) / 2.01 (sub)**, because the source tail loop over the wider operand's remaining limbs runs on the strided view-field path where C does a tight propagate. That last number only appeared once a `skew` stratum (8-limb + 3-limb) was added: the pre-existing five strata are all equal-length or one-limb, so after gating they would have reported ~1.00 across the board while measuring nothing source actually executed. **Lesson: when a gate narrows what a migrated path handles, the harness must gain a stratum for exactly that path, or the pass is vacuous.** Configuration sweep (all measured, none sufficient): pool allocator + `seal` beat both the hot-slot allocator and the "fast" epilogues — `finish_add`/`finish_sub` cost 1.74-1.87 on subtract rows despite skipping normalize's trailing-zero scan. Retained state: `bigint_src_shape` returns 0 (predicate and rationale kept in place so a future ported specialization can re-open exactly the shape it wins), direct lowering is opt-in via `TUNGSTEN_BIGINT_DIRECT_OPS=1`, and the source `+`/`-` bodies remain as thin boundaries because they fix a real bug — explicit `x.+(y)` on a BigInt previously resolved Int's bodyless `+` and returned nil. |
| Bigint operator arm (`+` → source) | `run_bigint_opadd_public.sh` | The operator-to-source dispatch architecture is PROVEN VIABLE under the 5% budget. `w_add`'s bigint arm resolves `BigInt#__big_add` once from the type-class table (dispatch key 0x02) and calls it through a cached direct pointer; registration re-arms a cached miss, `TUNGSTEN_BIGINT_SRC_OPS=0` pins the C path (the same-binary A/B lever and production kill switch). A sentinel-override probe proves routing. With the worst-case plumbing body (source → `ccall` → C kernel), two same-binary 12-run A/B pairs measured on/off ratios of 1.018/1.033 (one-limb), 1.010/1.028 (inline arg), 1.034/0.990 (four-limb), 0.991/1.016 (mixed-sign), 1.047/0.980 (64-limb) — every row inside the budget, toll at the noise floor. Cross-build comparisons showed ±3-5% layout noise; the same-binary lever is the decisive instrument for operator work. Prerequisite feature landed: `- data` inline array element loads/stores (`$limbs[i]`, u8-u64, `T[N]` and flexible `T[]` tails) via `:view_load_inline_elem`/`:view_store_inline_elem`, spec'd on both engines by `spec/numeric/bigint_limb_index_spec.w`. A first REAL source kernel (same-sign heap pairs ≤ 16 limbs, plain carry loop over `$limbs` into an alloc/seal-bounded fresh result) was then measured and REJECTED: 1.173/1.179 at one limb and 1.363/1.362 at four limbs against the C kernel's fused small-size specializations, with fallback shapes paying 1.06-1.10 for the extra shape tests. It also taught two hard lessons now encoded in the arm/body comments: the arm fires for `int + bigint` shapes so the body must shape-test SELF before any `$field` read (an unguarded `$size` load segfaulted on the masked immediate payload), and a branchy per-limb loop across three call boundaries cannot beat fused C. The wn_limb-discipline retry (v2: addcarry chains, split common/tail loops, single-branch tail, threshold 64) narrowed four-limb from 1.363 to 1.159 and one-limb to 1.114 — still over budget — and measured 2.352 at 64 limbs: the strided view-field loop runs ~1.3 ns/limb where C's unrolled ADC chain runs ~0.5, so the remaining gap is view-field loop CODEGEN (address-recurrence strength reduction and real unrolling for `:view_load/store_inline_elem` loops), not body style. v2 raw samples: `bigint_opadd_public_v2kern_{on,off}_results.txt`. A THIRD kernel attempt used the new class-scoped embedded-`ll` form (hand LLVM IR over raw limb addresses, i128-widened carry loop, spliced verbatim): correctness fully green including stage identity, but the same-binary A/B measured 1.120 (one), 1.072 (int-arg), 1.208 (four), 1.100 (mixed), 1.666 (sixtyfour). This is decisive: even verbatim portable IR cannot reach C's flag-threaded adc chains, because LLVM does not form them from loop-carried carries (LLVM #74493 — the documented reason the emitter's `asm_*` intrinsics exist; `doc/embedded-ll-asm.md` measures portable ll at ~1.5 c/l best-case vs asm ~1.0 matching C). Closing the gap needs an embedded-`asm` kernel, which is per-architecture — putting one in `core/` is a portability policy decision, so it was not taken unilaterally. The operator selector also moved from the experimental `__big_add` to the public `+` (typed-dispatch surface): the arm resolves `WN_plus` from BigInt's OWN method table (no superclass walk — Int's bodyless `+` registers a callable empty artifact that a chain walk would silently select), `TUNGSTEN_BIGINT_SRC_OPS=trace` prints resolution proof, and the rename fixed a live bug — explicit `x.+(y)` on a BigInt previously dispatched to Int's bodyless `+` and returned nil on the compiled engine. The walker delegates `+`-on-BigInt to `w_bigint_add` (mirror of the compiled arm). Loader autoload gained `abs`/`prime?`/`+` in the OUTER spelling gate (the inner BigInt gate was nested inside it, so inner-only entries never fired — a latent gap for the abs/prime? ports, now fixed). A FOURTH kernel body rode the now target-selecting `asm_add_no` WIRE op (per Erik's arch-gating approval: the emitter emits the flag-threaded adcs template on arm64 and a portable i128-carry IR loop elsewhere, so `core/` stays architecture-neutral; the op's pointer operands also now accept raw `## i64` addresses alongside typed arrays). Real adcs chains still measured 1.152/1.037/1.101/1.093/1.220 — and that fourth data point isolates the ACTUAL constant: the runtime arm reaches the source body through a runtime-resolved pointer, which whole-program LTO cannot inline, while the C path's direct `bigint_add_any` call inlines fully into `w_add`. Every source body with real work pays a ~3-4ns opaque-boundary tax (consistent across all four attempts' one-limb rows); kernel style was never the binding constraint. The weak-linkage arm was then BUILT AND PROVEN (Erik-approved): `__w_bigint_plus_src` has a weak C-kernel default in the runtime, and the emitter injects a strong wrapper around the (content-hash-renamed) compiled `BigInt#+` whenever a program compiles it — strong-over-weak link resolution routes `+` through source, a reopened `+` observably takes over INFIX addition (the definitive sentinel probe), thin programs link the weak default, and the boundary-body A/B sits at parity. That exonerated the call boundary and re-convicted the loop: `asm_add_no`'s 1x template ran ~5 insns/limb vs the C kernel's unrolled ladder, so the template was rewritten as a 4x-unrolled ldp/adcs/stp quad loop with a 1x remainder (flag-safe bookkeeping; wn_limb's asm cross-check green) — a permanent upgrade for every `asm_add_no` user. With weak arm + u4 template the kernel body measured 1.161 (one), 0.986 (int-arg), 1.094 (four), 1.104 (mixed), 1.088 (sixtyfour): converging, still over budget, with two NAMED residuals — the per-call constant (alloc + seal ccall boundaries and template preamble, dominant at one limb) and the fallback tax (the body's shape/sign tests run before bailing on mixed signs and the C kernel redoes them). Both endgame items were then BUILT and measured, and together they close the question. (1) Sub-magnitude: `asm_sub_no` got the same u4-unrolled `sbcs` treatment plus a portable i128-borrow arm, a weak arm was added to `w_sub`, and both operators were written inline in source with magnitude compare + subtract so mixed signs stay in Tungsten — this also constitutes the `-` operator port. (2) Fused finish: `w_bigint_alloc_hot` (hot-slot handoff, the allocator the C kernels actually use) and `w_bigint_finish_add`/`_sub` (the specialized epilogues — add skips normalize's trailing-zero scan, which its postcondition makes unnecessary) replaced the general alloc/seal pair. Correctness is beyond doubt: a 3072-case matrix (ten widths 2^47..2^254 plus limb boundaries, all four sign combinations of both operators, cancellation and round-trip identities) is byte-identical to the C oracle, kernels fuzz clean against wn_limb, all specs pass on both engines. The performance verdict is nonetheless negative and now well-explained: `+` 1.07-1.10, `-` up to 1.86, and mixed-sign `+` REGRESSED from 19.3ns (bail to C) to 32.1ns once the source subtract branch handled it. `bigint_add_any`/`sub_any` are not carry loops but dispatch trees of specializations — identity, one-limb, equal-length, word-shape, mutate-in-place, hot-slot reuse — each fully inlined into `w_add`. A source body pays 2-4ns of shape tests out of a ~20ns operation just to choose a path, then runs a generic kernel where C ran a specialized one. **Conclusion: migrating bigint operators means porting the specialization tree arm by arm, each with its own gate — not writing a better kernel.** Seven bodies now stand measured and rejected; the C boundary is retained, with all the infrastructure (weak arms, u4 carry ops, hot alloc/fast epilogues, raw-address operands) landed and ready for that arm-by-arm work. The retained production state is the boundary body (`ccall w_bigint_add`): four same-binary pairs measured worst-row 1.034/0.990/1.051/0.938 (four-limb aggregate clearly inside budget). Raw samples: `bigint_opadd_public_{llkern,asmkern}_{on,off}_results.txt`. Raw samples: `bigint_opadd_public_{pre_arm,src_on,src_off,src_on2,src_off2,kern_on,kern_off,kern_on2,kern_off2,plumb_on,plumb_off,plumb_on2,plumb_off2}_results.txt`. |
| BigInt `to_f` | `run_bigint_tof_native.sh`, `bigint_tof_public.w` | **RETAINED — native Tungsten limb walk.** The old source shim over `w_bigint_to_f` was measured first in the same binary as its benchmark-only C oracle: all ten positive/negative 1/4/16/17/64-limb rows were at parity (0.983--1.036), proving the lane plumbing was balanced. The retained body loads the signed header once, walks the `u64[]` magnitude from high limb to low with a raw `f64` accumulator (`uitofp`, multiply by exact 2^64, add), composes the tag-sign overlay, and boxes only the final Float. Two independent balanced 8-pair thread-CPU campaigns measured 0.849/0.873 (one limb), 0.677/0.653 (four), 0.455/0.465 (sixteen), 0.459/0.445 (seventeen), and 0.363/0.355 (64) for positive receivers; every negative row also won (0.353--0.885). The harness runs 100 exact WValue-bit differentials against the public C boundary, covering unsigned-high-limb conversion, mantissa rounding, signs, corpus widths, and finite/infinity seams. `spec/numeric/bigint_to_f_spec.w` pins the same semantics on interpreted and `--release --native --fast` builds. Emitted LLVM contains one `uitofp`, raw `fmul`/`fadd`, and no runtime call in the loop. Raw samples: `bigint_tof_native_c_shim_pre_results.txt` and `bigint_tof_native_source_candidate1{,_repeat}_results.txt`. Host/build: Apple M5 Max, arm64 macOS 26.6.1, Homebrew LLVM 22.1.8, configured `-mcpu=apple-m5`, `--release --native --fast`. |
| BigInt `to_s` | `bigint_tos_public.w` | **RETAINED.** Source shim over the new exported `w_bigint_to_s` boundary (base validation matching `w_to_s_base_arg`; the D&C decimal writer and base-N chunk loop stay in C); IC row 0 retired. Statically `:int`-typed call sites keep the compiler's `w_int_to_s` intercept and print/interpolation paths use `w_to_s` directly — the source body serves dynamic dispatch, and `spec/numeric/bigint_to_s_spec.w` pins all three routes agreeing (plus bases 2/16/36 and the D&C round-trip through the string parser). Campaigns: tos-one 1.031/1.038, tos-four 0.956/0.940 (the retired IC hop is a real win at 60ns), tos-sixtyfour 1.000/1.000 (the 1.46µs D&C writer — kernel-bound). |
| BigInt `prime?` | `run_bigint_prime_public.sh` | **Native one-limb checkpoint; not performance-accepted.** Positive normalized one-limb BigInts now run a deterministic seven-base u64 Miller-Rabin implementation in source using raw Montgomery multiplication; negative one-limb values reject directly. Wider Mersenne Lucas-Lehmer, Proth, and generic BPSW shapes retain `w_bigint_prime_q`. The same-binary harness compares the public source method with an explicit C oracle and checks 4,140 fixed/random full-word differentials. The final two-pair screen measured median source/C 1.224 for the prime row and 1.226 for the composite row, above the 1.10 migration limit; the source path is committed as an auditable implementation checkpoint, not a speed claim. Raw sample: `bigint_prime_one_limb_native_checkpoint_results.txt`. The earlier all-C source-shim campaigns remain in `bigint_prime_public_{pre,post_v1,post_v2}_results.txt`. |
| BigInt `lcm` | `run_bigint_lcm_public.sh` | **RETAINED within the 10% migration gate.** The rejected source composition remains useful evidence: chaining public `gcd`, `/`, and `*` lost 1.28-1.68x on small and near-equal strata. The public method now completes BigInt/BigInt one-limb pairs in native Tungsten as raw-u64 GCD, exact division, raw-u128 multiplication, and one final box; mixed and multi-limb pairs retain the fused `w_bigint_lcm`/`mag_divexact` fallback. A same-binary boxed public-W/C-oracle campaign measured W/C 1.062 (two-limb result), 1.081 (shared-factor one-limb result), 1.013 (inline-Int fallback), 0.992 (four-limb coprime), 0.999 (8-limb shared factor), and 0.979 (32-limb shared factor). A 16-pair targeted repeat confirmed the native cells at 1.053/1.078. Correctness covers 2,096 C differentials, full-word randomized magnitudes, mixed signs, divisibility/product identities, and edge semantics. Emitted LLVM has raw limb loads, raw GCD/division, one `mul i128`, and exactly one `w_u128(i128)` call; the work also fixes generic/raw/nobox ccall forwarding of raw i128/u128 arguments. Raw samples: `bigint_lcm_one_limb_native_{pre,candidate2,candidate2_repeat,final,final_repeat}_results.txt`. Host: Apple M5 Max, arm64 macOS 26.6.1, Apple clang 21.0.0; build: `--release --native --fast`, base `34fe928`. |
| BigInt `prev`, `succ`, `next` | `run_bigint_leaf.sh`, `run_bigint_leaf_public.sh` | Retained under a user-selected 5% budget (`W/C <= 1.05`, stricter than the 1.10 relaxed gate). The three IC rows are retired (names unregistered in `w_init_ic_tables`); Int's source bodies serve BigInt receivers through type-class dispatch, and the loader's BigInt call-name gate gains the three spellings. Two balanced A/B campaigns measured 1.000/1.009 (`prev`), 1.003/1.007 (`succ`), 1.014/1.009 (`next`). The first true-public campaign rejected the port of `next`: its delegating `succ` body cost a second dynamic dispatch, regressing 1.061--1.080 in all four strata, so `Int#next` now carries a direct `self + 1` body. Two subsequent public campaigns passed all 12 method-stratum rows at 0.980--1.026 and 0.980--1.013 against the pre-port baseline. `spec/numeric/bigint_succ_prev_spec.w` pins semantics on both engines, including the i48 demotion crossover and an argv-promoted receiver with no bigint literal. Stage-1/stage-2 identity re-verified after both edits. |

### Remaining Float leaf relaxed revisit

The hidden source bodies for `floor`, `ceil`, and `round` originally returned
Float, unlike their public native handlers, which returned Integer. The
retained forms state the old boundary explicitly: a Math libm operation,
signed-i64 conversion, then checked `w_int` boxing. `sqrt` remains the direct
Math primitive and `sq` is the exact universal product.

The first complete source campaign exposed an avoidable compiler cost:
rounding medians were 1.130, 1.157, and 1.161 versus C. Those versions were
not retained. Lowering now recognizes only the exact
`w_numeric_to_i64(Math.floor/ceil/round(x))` composition and emits raw libm
plus LLVM `fptosi`; arbitrary numeric conversions keep their dynamic checks.
After that optimization, two independently rebuilt 10-observation campaigns
put every method within 2.6% of native. The gate also compares the historical
C expressions across 32 IEEE encodings, including signed zeros, subnormals,
i48/int64 boundaries, infinities, and multiple NaN forms. Full hashes and the
excluded pre-optimization campaign are preserved in
`float_remaining_revisit_audit.md`.

### Float/BigInt identity relaxed revisit

Both retained bodies are the logical optimization endpoint: one source-level
`self`, lowering to `ret_i64 %__self` in both WIRE and LLVM. The public harness
uses matched roots and fresh compilers, proves the exact native-table delta,
and checks 22 Float encodings plus 26 signed BigInt layouts before timing. Its
40M-call legs use direct per-thread CPU clocks and consume the public result's
WValue bits, so neither optimizer dead-code elimination nor host-wide load can
decide the result.

The first/repeat source-to-C medians were 0.982/0.998 (finite Float),
1.007/0.979 (Float NaN), 0.957/0.984 (one-limb BigInt), and 0.997/0.967
(multi-limb BigInt). All 80 paired observations produced exactly 40,000,000
identity hits. The gate includes signed zero, subnormal and finite extrema,
infinities, canonical and dispatch-safe raw-positive NaNs, heap zero, both
BigInt signs, sparse/spare-capacity layouts, i48 through 256-bit boundaries,
surplus arguments, block behavior, no-use autoload, old-bootstrap, and the
tree walker.

This audit exposed two pre-existing lowering bugs rather than hiding them in
the benchmark: assigning a heap-BigInt `to_i` result can inherit an Integer
fact and nan-unbox its pointer, and implicit numeric result-`each` can use the
same pointer-derived loop count. Direct WValue identity remains correct in
both native and source roots; the real-syntax block parity probe breaks on its
first entry so the known bug cannot run billions of iterations. These compiler
issues are recorded for a separate fix and are not part of the identity port.

### BigInt predicate relaxed revisit

The retained source methods mirror `WBigint` directly. Signed `length` at
offset 4 is zero/sign-tested by all five methods; `even?` and `odd?` first
short-circuit heap zero, then load the low 64-bit limb at offset 16 and test
one bit. The source declaration names that flexible-tail word `limb0`, avoiding
an Array facade or generic numeric dispatch. LLVM checks require an `i32` load
plus sign extension for length and a raw `i64` limb load.

The exact gate covers 32 canonical and deliberately noncanonical heap layouts:
zero with and without storage, spare capacity and garbage spare limbs, both
signs and parities, leading-zero headers, and one through four limbs. It also
checks exact Bool bits, receiver stability, surplus arguments, compiled block
error parity, no-import autoload across literal/promotion/native boundaries,
and tree-walker field access. Every one of 26 independently gated timing
strata passed in both fresh 10-observation ABBA/BAAB campaigns. The complete
52-row table and compiler hashes are preserved in
`bigint_predicate_relaxed_audit.md`; isolated maximum-pair spikes are retained
there as noise diagnostics but never used to average away a failing median.

### BigInt prev/succ/next port (5% gate)

The 2026-08-06 campaign ran under a user-selected 5% regression budget. The
port itself is deletion: retiring IC slots 5-7 lets dispatch fall through to
`Int#prev`/`succ`/`next` (`core/numeric/int.w`), whose bodies are the same
`self - 1` / `self + 1` the C trampolines computed via `w_sub`/`w_add`. The
loader's BigInt call-name gate gains the three spellings so an argv- or
native-boundary BigInt with no literal evidence still autoloads the class.
This also unifies the engines: the tree walker had always dispatched these to
source; only compiled binaries ran the IC.

Reviving the dormant strict-gate harness surfaced three drift repairs, all
benchmark-side: the case factory now boxes with the v4 top-level BigInt tag
instead of `w_box_ptr(..., W_SUBTAG_GENERIC)`; the benchmark-local `- data`
mirror declares the leading `u8 _type` byte explicitly (without it every
offset shifted down and `$limb0` parity landed on a pad byte — sign/zero
checks passed by accident, parity could not); and the WIRE assertions accept
the `__w_add_fast`/`__w_sub_fast` wrappers current lowering emits.

Direct A/B medians (10 balanced ABBA/BAAB pairs x 5M consumed calls, mixed
1-4-limb signed corpus): `prev` 1.000/1.009, `succ` 1.003/1.007, `next`
1.014/1.009 across two campaigns.

The first public campaign exposed a real structural loss the A/B could not
see: `Int#next`'s body was a bare `succ` call, so the retired one-hop IC row
became two dynamic dispatches — 1.061--1.080 across all four strata. That
version was rejected; `Int#next` now has the direct `self + 1` body (an
improvement inline-Int receivers inherit too, since their table never
registered these names). With it, the two independent public campaigns
measured post/pre paired medians of 0.980--1.026 and 0.980--1.013 over all
12 rows (prev/succ/next x one/two/four-limb and i48-crossover strata, mixed
signs, thread-CPU clocks, fresh results consumed and freed). An isolated
prev-four 1.058 in the rejected first campaign did not reproduce in either
retained run (0.984/0.986).

Raw samples: `bigint_leaf_public_{pre,post_v1_rejected,post_v2,post_v3}_results.txt`.
Correctness: `spec/numeric/bigint_succ_prev_spec.w` (both engines), the
858-check A/B gate, argv-promotion probe, and re-verified stage identity.

### Array leaf relaxed revisit

The retained bodies operate on the declared `WArray` view instead of calling
header helpers. `size` and `cap` load one u32 and OR it with the canonical
immediate-Integer tag; `empty?` is one raw zero comparison. `first` and `last`
guard the empty receiver and then use the compiler's ebits-aware Array index
path, preserving ordinary WValues, packed signed and unsigned integers, u1,
floats, shifted starts, and borrowed views.

The production-shaped harness builds matched native-IC and source-method roots
with one compiler, inspects all five public call sites and method bodies, and
checks exact results across 16 fixtures plus surplus arguments and trailing
blocks. It separately proves autoload from literals, typed constructors, exact
C factories, `argv()`, and `ARGV`, then runs the same surface in the tree
walker. The first 10-observation campaign's paired medians were 0.963--1.014;
an independently rebuilt 12-observation repeat measured 0.948--1.016 across
all 12 strata. Since one nonempty `empty?` pair was a wide host-noise outlier,
a separate 12-pair campaign extended each leg to 200M calls and measured a
0.980 median. Decisions use total `CLOCK_THREAD_CPUTIME_ID` nanoseconds rather
than quantized whole nanoseconds per call or wall time.

### String `empty?` relaxed revisit

The old source candidate already encoded the storage-mode invariant correctly,
but its shift-then-mask form missed the historical 0.97 gate. The retained
version tests the three mode bits in place, so WIRE contains one `and_i64`, one
comparison, and no shift, `w_str_data`, or native-handler fallback.

The unique-name harness was strengthened from alternating two-leg timings to
balanced C/W/W/C and W/C/C/W samples with a 5M-call warmup. Two fresh 8x50M
campaigns measured 0.937 and 0.927 source/C. The production harness then used
matched isolated roots and a benchmark-only thread CPU clock. It checked 80
public calls per build across inline, slab, heap, flattened-rope, and Symbol
representations plus surplus arguments. The first public campaign measured
0.948, 0.930, 0.939, 0.920, and 0.853 by stratum; the independent rebuild
measured 0.939, 0.942, 0.929, 0.956, and 0.855. The source method and removal
of `w_ic_string_empty` are therefore retained.

Compiled dispatch had always flattened a rope before invoking a String source
method, while the tree walker initially exposed the rope object's pointer bits
as `$value`. A focused interpreter regression caught the resulting false
`empty?`. Primitive source dispatch now flattens only after it has found a
String source method, so unrelated calls gain no new type check. Because String
and Symbol share runtime key `0xF9`, the interpreter also routes both `to_s`
and `empty?` through the shared String source class; the focused inline/slab/
heap/rope/Symbol and surplus-argument matrix passes with the C IC absent.

### IPv4 `octets` relaxed revisit

The production source body reads the packed IPv4 word once and constructs an
ordinary Array from four independent shifts and masks. The retained form keeps
the C implementation's w64 element representation, size four, default capacity
eight, and fresh allocation on every call; CIDR prefix bits do not enter any
octet. Its emitted WIRE has four shifts, masks, pushes, and no call to
`w_ipv4_octets` or generic method dispatch.

Two balanced 8x5M unique-name campaigns measured 0.991 and 0.984 source/C.
For the production-shaped trial, `w_ic_ipv4_octets` and its sole table row were
removed in an isolated root while a byte-equivalent C reference stayed in the
same release binary. The harness uses thread CPU time so concurrent search jobs
cannot charge descheduling to either leg. Two corrected public campaigns
measured 47.040/47.115 ns (0.994) and 47.149/47.089 ns (0.995), comfortably
inside the 1.10 budget. The source implementation and C-IC removal are retained.

The permanent gate covers eight fixed and 4,096 generated addresses, including
all prefix forms, exact Array layout/capacity, result independence, mutation,
and bounded cleanup. Focused compiled and tree-walker specs also cover ignored
surplus arguments and run against an isolated compiler built with the old IC
physically absent.

### Float leaf relaxed revisit

`abs`, `nan?`, and `infinite?` now operate directly on Float's biased WValue.
Each body subtracts the 2^48 bias and masks the IEEE sign bit once. Classification
then compares the magnitude with the infinity word; `abs` adds the bias back,
with one cold branch that returns the same canonical positive qNaN produced by
`w_box_double`. The earlier experimental `nan?` equality was semantically
incomplete because a valid raw qNaN or sNaN need not equal the canonical word.

The production-shaped harness compiles the same public calls against isolated
native-IC and source-method roots and times with thread CPU time. Campaign one
ratios were 0.991 (abs finite), 0.977 (abs edge), 0.978 (abs NaN), 0.966
(`nan?`), and 0.981 (`infinite?`). After rebuilding both roots, the independent
ratios were 0.982, 0.973, 0.978, 0.972, and 0.996. Every one of the 100 balanced
four-leg comparisons passed the 1.10 gate; the worst individual ratio was
1.053.

Sixty exact public checks per build cover signed zeros, subnormals, finite
extrema, infinities, canonical NaNs, and raw noncanonical positive qNaN/sNaN
words. Emitted WIRE contains only integer unbias/mask/compare operations plus
the `abs` add/canonicalization branch, with no C or generic-dispatch fallback.
A compiled meta-interpreter runs the same 60 checks with all three ICs absent;
its narrow `wvalue_from_bits` bridge decodes only the nonnegative Float-word
range that source `abs` can return. All three source bodies and C-IC removals
are retained.

### SmallArray / BigArray leaf relaxed revisit

The retained SmallArray bodies operate on the declared `WSmallArray` view:
`size` and `cap` read the u8 header once and OR it into the canonical immediate
Integer tag, and `empty?` keeps that field raw through one zero comparison.
BigArray's signed-i64 header cannot always fit the immediate payload, so its
source body inlines the signed-i48 range/tag arm and calls `w_int` only for the
exact positive/negative overflow cases that must allocate a BigInt.

The matched-root runner uses independently built compilers and root-local
release/LTO runtime links, avoiding the shared development runtime archive.
Two ten-observation thread-CPU campaigns measured source/native at 1.000 in
both runs for SmallArray `size`, `cap`, and `empty?` and for BigArray inline
`size`; BigArray overflow measured 0.962 and 0.961. Static gates require the
old handlers/table names to be absent and pin the intended WIRE field/tag/
comparison shapes with only the BigArray cold `w_int` fallback.

Correctness covers every SmallArray size byte (0..255), all signed-i64 BigArray
view headers including both signed-i48 edges and both i64 endpoints, exact
Int/BigInt/Bool representation, surplus arguments, trailing-block behavior,
views and receiver stability. Runtime-created receivers now autoload their
source classes through an exact factory-result map for `ccall` and
`ccall_rawargs`; the runtime and tree walker also report BigArray/SmallArray
class identity explicitly. The no-`use` compiled gate and interpreter gate
both run with all migrated IC rows physically absent.

The follow-up `cap`/`empty?` campaign independently exercises ordinary and
synthetic inline capacities, both overflow directions, and zero, positive,
and negative raw sizes. In its first/repeat runs, all inline and Boolean
strata were exact 1.000 parity; positive overflow measured 0.963/0.962 and
negative overflow 0.923/1.000. Exact representation checks include both i48
edges, the first values beyond them, both i64 endpoints, independently varied
size/cap headers, view flags, surplus arguments, block behavior, four no-use
factory paths, and the tree walker. Full protocol and raw summaries are in
`big_array_cap_empty_revisit_audit.md`.

### Mmap `size` relaxed revisit

The retained facade moves Mmap into its own `core/mmap.w`, declares the exact
`WMmap` view, and implements only `size`; its other methods remain explicit
bodyless native declarations. Real mapping lengths are nonnegative, so one
arithmetic shift recognizes the entire inline-i48 domain. Synthetic negative
or enormous headers take the canonical `w_int` fallback, preserving exact
BigInt sign and limb representation.

Both independent ten-pair thread-CPU campaigns passed. Ordinary source/native
paired medians were 0.9503 and 0.9501; positive overflow measured 1.0263 and
1.0504. Correctness covers sixteen signed-i64 headers, both i48 and i64 edges,
exact bits/limbs, surplus arguments, blocks, mapping close state, ABI offsets,
separate File/native autoload paths, and retained primitives in the tree
walker. Compiler dispatch key `0x91`, a narrow native field bridge, and Mmap
type discovery make the source path independent of the removed IC. Production
also uses a one-shot `size` name gate so an Mmap crossing an unknown parameter
or native boundary cannot depend on a constructor being visible in the same
AST. The full
protocol, hashes, and allocator-noise diagnostics are in
`mmap_size_relaxed_audit.md`.

### UUID / StringBuffer relaxed revisit

`UUID#byte` now declares the runtime allocation as a fixed `u8[16]` view. It
keeps the former `w_to_i64` Int/BigInt conversion—including low-i64 wrapping
for oversized BigInts—but recognizes 0..15 with one `(index & -16)` test and
returns the inline byte load. The compiled public WIRE contains the conversion,
mask, and view load with no `w_uuid_byte` or dynamic-call fallback. The old C
function remains only for the tree walker's fixed-array storage bridge.

Correctness covers all sixteen bytes, both adjacent bounds, positive and
negative BigInt bounds, 2^64 wrapping to 0/15 and rejection at 16, surplus
arguments, version/variant/type stability, and the exact invalid-Float error
payload. UUID literals and the exact parse/factory calls now autoload the
source class. Two ten-pair public thread-CPU campaigns measured 0.979/0.969 for
hot indices and 0.985/0.978 for the fallback corpus; worst individual ratios
were 1.074 and 1.052, both below the 1.10 budget.

StringBuffer's core declaration now uses the runtime class name
`StringBuffer`, allowing dispatch key 0x0B to register its source method. Its
optimized `size` keeps `$length` raw, masks and sign-extends the low 48 bits,
and compares that roundtrip with the original once. Matching values are ORed
with the immediate Integer tag; only a synthetic out-of-range header calls
`w_int`. This improves on the first source version, whose WIRE was merely a
field load followed by `w_int`.

The same matched-root runner checks empty, ASCII, and UTF-8 live byte lengths,
surplus arguments, receiver/content stability, signed-i64 boundary headers,
autoload/bootstrap, interpreter field access, exact WIRE, and IC removal.
Normal buffers measured 0.985/0.982 source/native; the allocation-heavy corrupt
header fallback measured 0.998/1.001. Individual overflow samples reached
1.137 under allocator noise, but the independent median gates are neutral and
the ordinary realizable path's worst sample was 1.008. The self-host imports
the class explicitly so older stage-0 loaders can build the first source-size
compiler after the IC disappears.

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
Under the historical 0.97 gate, `compact` v2 measured 0.976--1.010 and `dup`
v2 measured 0.937--1.025, so both were correctly skipped at the time.

The 1.10 revisit rebuilt and reran both candidates rather than reclassifying
the old numbers. The two balanced same-process campaigns measured
`compact` at 0.970--1.014 and 0.976--1.005, and `dup` at 0.978--1.012 and
0.960--1.007. The production-shaped isolated-root campaigns then compiled the
same public-name benchmark against either the native IC or the source method.
Their `compact` ratios were 0.920--1.024 and 0.933--1.034; `dup` was
0.921--1.014 and 0.937--1.002. Every selected workload passed twice, so both
methods and their optimized size snapshot are retained and the two C handlers
and IC rows are removed.

The public harness continues to require isolated baseline/candidate roots and
audits the native-IC/source shapes, emitted WIRE, exact result layout, typed and
view decoding, extras, trailing blocks, and bounded cleanup. Two additional
compiled specs prove that `argv().compact` and `argv().dup` load Array without
an Array literal or explicit `use`. Their shared one-shot loader guard was
measured with matched compilers over eight alternating immutable self-host
pairs: all 16 LLVM outputs were byte-identical, while candidate/baseline
medians were 0.981 for load+parse, 1.015 for total compiler phases, and 0.994
for both wall and user CPU.

### Packed-network `to_s`

IPv4, IPv6, and MAC already had direct source wrappers around the canonical
`w_to_s` formatter, so this port removes only their three class-specific
`to_s` IC rows. Their native `inspect` aliases remain: an arbitrary untyped
native return can still receive `inspect` without giving the loader a class
fact, while universal `to_s` has a sound runtime fallback. Exact output,
receiver-bit/field stability, every IPv4 and IPv6 prefix, surplus arguments,
trailing blocks, no-import autoload, interpreter behavior, WIRE, and LLVM all
passed.

Two independently rebuilt 10-observation campaigns measured source/native
medians of 0.990/0.986 for plain IPv4, 0.989/0.999 for CIDR IPv4,
0.987/0.989 for plain IPv6, 0.990/0.985 for CIDR IPv6, and 0.991/1.008 for
MAC. All three methods clear the 1.10 gate and are retained. The initial
check-only run also caught an ambiguity in the benchmark support ABI: raw
`-1` aliases a reserved packed WValue, so no-prefix inputs now cross the mixed
boundary as boxed `nil` and are converted outside the timed method.

### Atomic / Channel / Thread wrapper revisit

Four bounded synchronization leaves now live in the core facades:
`Atomic#increment`, `Atomic#decrement`, `Channel#recv`, and `Thread#alive?`.
They call the unchanged lower C primitives directly; storage, atomic ordering,
channel scheduling, thread lifecycle, and all constructors remain native.
`Atomic#cas/get/set/add`, `Channel#send/close`, and `Thread#join/kill` also keep
their native IC rows because their names are too broad for a sound source-only
autoload boundary or because their hard-fatal/mixed-ABI behavior is not exactly
expressible by the facade.

Two independently rebuilt 10-observation campaigns produced source/native
ratios of 1.00461/0.996906 for Atomic increment, 1.00227/1.00141 for Atomic
decrement, 0.974415/0.976986 for Channel recv, and 0.920427/0.918999 for Thread
alive?. The worst fresh-cache load ratio was 1.0122 and compiler binary size was
1.00006, all below the 1.10 gate. Narrow selector gates and exact native-factory
provenance register the facades without changing public identity: all three
opaque handle kinds still report `Unknown`. Full raw observations and parity
coverage are in `sync_wrapper_revisit_audit.md` and its adjacent artifacts.

## Compiler work retained during this loop

- ARGV discovery now rides the existing exhaustive builtin-runtime-class AST
  walk instead of recursively traversing the complete compiler AST a second
  time. The final v2 also inlines the two `ARGV`/`argv()` predicates, deleting
  the old 175-line walker and its per-node helper calls while preserving the
  Spinel stage-0 normalizer's intentional suppression. Common-bootstrap,
  rebuilt, and self-host compilers emitted identical 13,580,943-byte LLVM
  (`f874bfa3...e8e4bb`); nested `ARGV`, nested `argv()`, and no-ARGV fixtures
  retained their exact entrypoint signatures and behavior. Two independent
  eight-pair campaigns measured lowering at 0.988/0.989 and total compiler
  time at 0.992/0.990; wall was 1.009/1.006 and user CPU 1.011/1.002. The
  pooled 16-pair ratio-of-medians was 0.991 for lowering, 0.994 total, and
  1.006 for both wall/user, with every warmup and measured LLVM pair
  byte-identical.
- Class lowering now caches the trait-expanded, accessor-synthesized, and
  typed-overload-expanded body produced by its registration prepass and reuses
  it in `lower_class_def`; isolated callers retain the old transformation
  fallback. A self-host and a focused trait/accessor/overload/reopen fixture
  emitted byte-identical LLVM, and six relevant specs passed. Across two
  independent eight-pair campaigns, the combined paired medians were 0.993 for
  lowering, 0.993 for total compiler phases, 1.001 for user CPU, and 1.004 for
  wall time; aggregate ratios were 0.998, 0.996, 1.005, and 1.005. Every
  individual metric pair remained within 1.10.
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
  direct field candidates expressible, fixed BigInt's `length` layout/load
  checks, and now underpins the retained BigInt predicate source methods.
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

## Integrated verification snapshot (2026-07-15)

- The combined compiler containing the retained runtime ports and fused ARGV
  scan rebuilt successfully from the checked-in bootstrap. Two subsequent
  self-host generations emitted byte-identical 13,656,142-byte LLVM modules
  (`419fd5c23673452a8325a6c7d769eea6a0deb554630deb935bf80e478f9192a6`).
- The full Spinel stage-0 bundle generated with `SPINEL_STAGE0_FULL=1` and
  passed Ruby syntax validation. The SmallArray/BigArray benchmark's complete
  `CHECK_ONLY` gate passed against the integrated compiler, as did the new
  UUID, StringBuffer, and nested-ARGV compiled and interpreter specifications.
- The complete spec run passed every migration and compiler-regression check.
  Its only failures were the five pre-existing generic numeric specs
  (`complex_spec`, `hypercomplex_mul_spec`, `matrix_spec`,
  `operator_overload_spec`, and `vector_spec`). Each produced the identical
  missing `new`, `basis`, or `identity` failure when independently compiled
  and run from an untouched detached worktree at baseline commit `f62869b`;
  none is attributable to this migration series.
- After the String/Symbol `size`/`length` and public-identity merge, two newer
  self-host generations again reached a byte-identical LLVM fixed point:
  13,772,879 bytes with SHA-256 `54ea5a49d01a499f50d2357c64203c7eb445c46c86e77ef1e48c455934c17f29`.
  The expanded suite again left only those same five baseline numeric failures;
  all String representations, twelve no-use/generated-name gates, and compiled
  plus interpreted identity checks passed.
- After the synchronization-wrapper merge, the next two self-host generations
  emitted byte-identical 13,819,933-byte LLVM modules with SHA-256
  `613490a639145b20ecb377763353a568611bcc9223d982814d2d3b7f0c7293de`.
  Focused source/native, WIRE/LLVM, factory-autoload, interpreter, fatal-parity,
  and public-identity checks all passed. The full suite again left only the same
  five detached-baseline numeric failures.

## Pending compiler trials

No compiler trial in this section has yet cleared its first performance gate.

## Rejected compiler trials

- Range iteration tried replacing unconditional canonical `w_int` boxing with
  an inline signed-i48 membership test, direct NaN boxing on the hot arm, and
  a cold BigInt call. Against the simpler unconditional call, 11 balanced
  samples measured 0.999 for a long hot loop, 0.975 for four-item ranges,
  1.009 for cold BigInt values, but 1.398 for one-item setup-heavy ranges.
  The branch/merge overhead dominates precisely where loop setup is most
  visible, so the checked boxer and its branch metadata were removed. Range
  representation correctness is being retained separately and continues to
  use unconditional `w_int` where a counter must become a boxed Integer.

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
