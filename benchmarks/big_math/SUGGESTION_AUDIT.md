# BigNum external-suggestion validation ledger

This ledger tracks the six 20-item suggestion sets supplied during the BigNum
performance campaign. Suggestions are hypotheses, not accepted designs.
Every one of the 120 source items receives its own disposition even when
several items share one experiment.
The audit is exhaustive: an item is measured even when it only intersects
cells Tungsten already wins.  Current GMP losses influence scheduling, not
whether a hypothesis is tested.

The acceptance rule for a performance candidate is:

1. record a same-build, same-host baseline;
2. change only the intended variable;
3. run the affected end-to-end boxed cells with the same timing policy;
4. run focused correctness/differential checks;
5. retain the change only when it wins its intended matrix without an
   unacceptable regression;
6. retain the raw JSON or command output and machine metadata.

"pending" means the item has not yet received a complete disposition.
"active" means a matched experiment is in progress. Final states are
"kept", "rejected", "premise rejected", or "deferred", each with evidence.
A final "deferred" disposition requires a concrete unavailable prerequisite
or an out-of-scope architecture/operation; low priority is not sufficient.

Source fingerprints:

- GLM-2.1: a739eccb157b5bd494b4dbc27ce00fe66dfa96bada8419622bf2b3ea61470474
- Kimi-K3: b9c5dddcfa9f308937171e1f806b3b4a9b3342eba41084f2fd7e5d61c8ce218a
- Gemma4: c005f8511b0b5dfbc9793ca425aa56398ea13e1058fad7719ff58c5116ec1786
- Qwen3.6: a0604bd38b36d6efc971d6679f984262a4c149e140141650a6728925cfdbee8a
- Grok: ad566440c9a72625f2cf2171ba2dc8580bdaffcf2d37713d60a71362732dc5ea
- DeepSeek-v4-pro: 29aa2664eb7700cb44f04ce0c9bdef68a29ca4c8e938c871e086f39d229dada8

## GLM-2.1

| ID | Hypothesis | Status | Evidence |
| --- | --- | --- | --- |
| GLM-01 | Destination-passing / mutate-if-unique ABI for every operation | pending | |
| GLM-02 | Direct hot-handoff slot for results up to 64 limbs | kept | disabling only BN_BIGINT_HOT_SLOT while retaining the thread-local size buckets made the current direct handoff win 26/28 boxed add1/sub1/mul1/div1 cells from 2 through 64 limbs and improve the geomean 12.6%; the only losses were div1 at 32/64 limbs by 0.01%/0.14%, with no >5% regression; hot-handoff-6f41042-m5max-20260804.json |
| GLM-03 | Hand-written AArch64 normalized div-by-word kernel | pending | audit related commits 3926cbb, 6aea99c |
| GLM-04 | Branch-free reciprocal correction for 32-bit divisors | premise rejected | the separate two-half-limb 32-bit reciprocal loop is disabled on AArch64; routing small divisors through the normalized 64-bit preinverse path cut the divchain lane from 1.95x GMP to 1.002x; divchain-m5max-20260803.tsv |
| GLM-05 | Subquadratic half-GCD above about 1024 limbs | kept | existing recursive HGCD retained; half-slice band added at 6144; gcdlcm-half-slice-7096978-m5max-20260804.json; GMP fuzz 1000x8192 + 10x65536; sanitizer fuzz 250x8192 |
| GLM-06 | Reuse one scratch remainder across Lehmer steps | pending | |
| GLM-07 | isqrt reciprocal-sqrt seed, scratch reuse, and fewer divisions | pending | audit related commits 4b823f3, df0c604 |
| GLM-08 | Retune Toom-3 / Toom-4 crossover | premise rejected | the proposed diagnosis said 448 limbs was already in Toom-4 and should move back to Toom-3, but BN_TOOM4_THRESHOLD=456 means 448 already selected Toom-3; the GMP-verified forced sweep found Toom-3 was the best available rung there and still lost, so a threshold-only change could not close the cell; NOTED_TRADEOFFS.md; the later ce81fcb/dfb94bc kernel/parallel work is accounted for separately |
| GLM-09 | Lower NTT threshold and reduce SSA workspace clearing | pending | |
| GLM-10 | Widen NEON hybrid add/sub dispatch | kept | lowering the boxed hybrid cutoff from 384 to 288 limbs improved the 272..384 add/sub matrix 2.0% geomean with no >5% regression; add304..368 improved 3.1-4.5%, sub336..368 improved 4.1-4.7%, and the apparent sub288..320 losses were smaller than their paired IQRs; addsub-neon-min288-f011cd7-m5max-20260804.json; GMP add/sub fuzz 100000x1024 passed |
| GLM-11 | General carry-select add/sub | kept | exact hot-shape carry-select paths improve add256 to 0.587x, sub128 to 0.766x, and sub256 to 0.630x their otherwise-identical serial fallbacks; the unchanged add128 control moved 2.0% with paired IQR larger than the effect, and no cell regressed over 5%; arbitrary longer lengths use the separately measured generate/propagate hybrid; addsub-carry-select-673ec76-m5max-20260804.json; GMP fuzz 500000x256 passed |
| GLM-12 | Recognize and fuse addmul_1 / submul_1 language shapes | pending | |
| GLM-13 | BigInt Montgomery reduction for powmod | kept | bigint_powmod_any uses register, CIOS, or SOS Montgomery for supported odd moduli and Barrett otherwise; matrix-7a96d5c-accurate-20260802.json has all 12 powmod cells faster than GMP (0.60-0.998x), with GMP and independent-naive differential checks in the harness |
| GLM-14 | LCM via exact quotient and one multiply | kept | w_ic_integer_lcm_generic computes gcd, exact r/g, then one multiply, with a unit-gcd shortcut; gcdlcm-par-apply-3ccd13b-m5max-20260804.json has all LCM cells through 16385 faster and the 65536 cell at 1.001x parity |
| GLM-15 | Multi-limb exact division | kept | mag_divexact is the Jebelean/Hensel multi-limb exact quotient used by LCM; matrix-7a96d5c-accurate-20260802.json and gcdlcm-par-apply-3ccd13b-m5max-20260804.json provide end-to-end LCM evidence and GMP differential checks |
| GLM-16 | Defer boxing and merge shared-check with pool return | kept | escaping values still require their immediate top-level BigInt tag, but the realizable hot path already inlines the shared-count check with the empty-hot-slot return; disabling only BN_BIGINT_RELEASE_INLINE_HANDOFF made the current path improve the 20-cell boxed word-operation geomean 1.5% with no >5% regression; inline-release-handoff-1ee775a-m5max-20260804.json |
| GLM-17 | Page-offset rehoming at 384–512 limbs | rejected | extending add/sub rehoming through 512 limbs produced 1.003x geomean, five wins/five losses, and a 6.1% sub256 regression; a separate safe fresh-capacity mul/sqr rehome produced an unresolved 0.978x geomean with paired spreads larger than the effect and regressed the named mul448 cell 1.1%; both candidates were removed; addsub-rehome512-996180d-m5max-20260804.json and mulsqr-large-rehome-996180d-m5max-20260804.json |
| GLM-18 | Hand-written add/sub basecases for 8–128 limbs | kept | the existing straight-line AArch64 8/16/24/32/40/48/64 kernels and sub128 carry-select path were isolated from the generic scalar fallback; across the broader 3..128 boxed matrix current paths won 18/20 cells and improved 9.7% geomean, with the only >5% median loss in add128 where neither variant changes the arithmetic path and the paired IQR was twice the apparent effect; addsub-fixed-basecases-f011cd7-m5max-20260804.json |
| GLM-19 | Toom-2 equal/difference specializations at 32–48 limbs | kept | the current fixed 32/40/48 difference paths were measured against one otherwise-identical build with BN_MUL_POWER2_FIXED, BN_MUL_SPLIT_40_BLOCKS, and BN_MUL_SPLIT_48 disabled; nine alternating 110 ms boxed rounds measured candidate/baseline 0.851x/0.852x/0.841x, with all current cells faster than GMP; mul-fixed-toom2-32-40-48-1f431bc-m5max-20260804.json; GMP fuzz 10000x64 passed |
| GLM-20 | Branch-free carry/correction tails in mul1 and div1 | rejected | current mul1 rolling-carry kernels already return carry without a correction branch, so that half of the proposed transformation has no matching branch to remove; replacing div1's rare second reciprocal-correction branch with AArch64 cmp/sub/csel/cinc lost all nine boxed cells from 2 through 1024 limbs and slowed the geometric mean 1.107x, so the candidate was removed; div1-branchless-second-fbf77a1-m5max-20260804.json |

## Kimi-K3

| ID | Hypothesis | Status | Evidence |
| --- | --- | --- | --- |
| KIMI-01 | AArch64 normalized divrem_1-class kernel | pending | audit related commits 3926cbb, 6aea99c |
| KIMI-02 | Route 32-bit divisors through normalized preinverse division | kept | BN_DIV_SINGLE_32BIT_RECIP=0 on AArch64 routes non-power-of-two small words through the normalized preinverse path; divchain-m5max-20260803.tsv records 1.95x -> 1.002x versus GMP with matched checksums |
| KIMI-03 | Hoist N×1 routing in the multiply entry | kept | bigint_mul_any tests the positive N×1 shape before the general pair dispatcher; mul1-13689fa-accurate-m5max-20260803.json -> mul1-lifecycle-a64-accurate-m5max-20260803.json reduced boxed 2-8-limb time 39-45% |
| KIMI-04 | Straight-line mul1 rungs and close fixed-kernel gaps | kept | inline 2-4 and fixed 8/16/24/32/40/48/64 boxed rungs plus rolling-carry kernels; lifecycle artifact cuts 2-8-limb boxed time 39-45%, and 1ba1be6 kernel probes moved 64/256/1024 limbs to 1.01/1.02/1.01x GMP |
| KIMI-05 | Extend page-hazard guard to division and large results | rejected | a direct div1 quotient-allocation guard at 128..8192 limbs was neutral (0.995 candidate/base geomean, four wins/three losses); div1-page-rehome-a47a1f6-m5max-20260804.json; forcing a settled alternate placement at 1024..8192 improved the repeated-fixed-operand geomean 2.6%, but the search performs up to 16 fresh allocations before timing and keys the settled result to exact operand addresses, so a workload with many different numbers would repay that cost; div1-page-rehome-forced-a47a1f6-m5max-20260804.json; the multi-limb Knuth/BZ/reciprocal paths write arithmetic into normalized or TLS workspace and only copy the final q/r into the boxed result, so they do not have the proposal's direct quotient-write/original-dividend-read stream; boxed GMP checks passed in every measured cell and the production candidate was removed |
| KIMI-06 | Mutate-if-unique entries for word add/sub/mul/div | kept | compiler/runtime ship guarded w_bigint_{add,sub,mul,div}_mut entries; program-loops-6e7c006-m5max-20260804.tsv measures release/native/fast end-to-end loops (0.346x accumulate, 0.989x mulchain, 1.007x divchain in the final interleaved batch); --fuzz-mut covers all four entries and alias refusal |
| KIMI-07 | Extend compiler mut-accumulator recognition | kept | fail-closed accumulator and rotation-shape analyses route dead locals to mut/destination entries while preserving value aliases; program-loops-6e7c006-m5max-20260804.tsv records 0.738x GMP addchain and focused bigint_mutate_unique_spec covers aliases and disqualification |
| KIMI-08 | Add mulchain1/divchain1 whole-language-loop lanes | kept | run_program_loops.sh builds Tungsten release/native/fast and matched GMP loops, alternates lanes, checks checksums, and now reports median/IQR; program-loops-6e7c006-m5max-20260804.tsv records a noisy loaded-host run without using it for a performance disposition |
| KIMI-09 | Skip redundant write-before-read workspace clearing | pending | |
| KIMI-10 | Fixed-size multiply study at 32/40/48 limbs | kept | isolated compile-time A/B of the current fixed shapes versus the generic fallbacks measured 1.175x/1.174x/1.189x speedups at 32/40/48 limbs; paired IQRs 0.034-0.056; all three boxed current paths beat GMP; mul-fixed-toom2-32-40-48-1f431bc-m5max-20260804.json; GMP fuzz 10000x64 passed |
| KIMI-11 | Optimize Toom-3 evaluation/interpolation at 400–500 limbs | kept | dfb94bc parallelizes the independent Toom-3 point products while leaving interpolation serial; against the ce81fcb accurate baseline, boxed mul improved 20.5% at 384, 1.7% at 448, and 10.2% at 512 limbs, held at 1024, and remained faster than GMP in all five measured cells; mulsqr-a64-par-cutoffs-df0c604-m5max-20260804.json -> mul-a64-par-toom3-ce81fcb-m5max-20260804.json; current GMP fuzz 2000x2048 passed |
| KIMI-12 | Rebalance large isqrt division | pending | audit related commits 4b823f3, df0c604 |
| KIMI-13 | Audit HGCD inner routing and tune its band | kept | counters found 100% block acceptance and row-apply dominance; propagated half slices win 4–7% at 8192–16384; gcdlcm-half-slice-7096978-m5max-20260804.json |
| KIMI-14 | Probe NEON add crossover at 96–256 limbs | kept | the requested low-band probe rejected 96 as too aggressive in the smoke screen and an acceptance-grade 224 cutoff split 10 wins/10 losses with a 5.9% add240 regression; narrowing upward found 288 as the first safe mixed-operation cutoff, improving the 16-cell boxed matrix 2.0% geomean with no >5% regression; addsub-neon-min224-f011cd7-m5max-20260804.json and addsub-neon-min288-f011cd7-m5max-20260804.json |
| KIMI-15 | Add mid-band fixed squaring rungs | pending | |
| KIMI-16 | Mark generic entries and error paths cold | rejected | the bundled cold+preserve-most generic-entry candidate was measured on 24 boxed add/sub/mul/div/mod/gcd cells at 2..512 limbs and regressed 1.0% by geomean with 11 losses, including a 46.0% mul64 regression; generic-entry-cold-5748032-m5max-20260804.json; these functions are the ordinary hot implementation for many boxed BigInt shapes, not exceptional fallbacks; an isolated cold+noreturn annotation on die/dief also regressed 0.8% by geomean across 15 cells with two >5% losses, so it failed the keep-only-winning gate even after separating it from the generic entries; error-path-cold-5748032-m5max-20260804.json; the established preserve-most/cold contract remains limited to compiler-proven guarded-i48 mutate fallbacks where declaration, definition, and call convention already match; both production candidates were removed |
| KIMI-17 | Re-open the live-depth capacity-policy default | rejected | 48 hybrid capacity points x live depths 1/4/8 x 1024/4096-limb traces produced zero candidates meeting the fixed RSS/churn criteria; power-of-two remains default; b4-base-*.tsv, b4-grid-*.tsv, NOTED_TRADEOFFS.md |
| KIMI-18 | Retune parallel cutoffs under quiet/load-monitored conditions | pending | audit related commits ce81fcb, dfb94bc |
| KIMI-19 | Add instructions-retired measurement | rejected | the installed public Xcode 26.4.1 `xctrace` CPU Counters template successfully captured a 50M-iteration boxed add64 run, but CLI-default Guided/CPU-Bottlenecks mode exposes 1 kHz bottleneck samples plus an opaque cumulative PMC array with no exported event-name mapping, not a documented retired-instruction total; it also combines startup, Tungsten, and GMP phases without explicit signposts; `powermetrics` refused unprivileged execution, while direct private-kperf plumbing would be undocumented and macOS-only; instructions-retired-probe-033ea10-m5max-20260804.json; retain xctrace as an auxiliary profiler rather than a benchmark acceptance metric, and continue using alternating 110 ms x9 wall-time samples with IQR/load metadata |
| KIMI-20 | Use per-operation adaptive timing targets | rejected | two matched 2 ms x3 screens and one 110 ms x9 reference covered 28 boxed cells spanning add/mul plus powmod/lcm/isqrt/tostr/fromstr at 1,4,16,64 limbs; all three classified the same 27 wins and one loss, with no win/loss flips, while screen/reference ratio disagreement was 3.4-3.8% by geometric mean and at worst 9.3%/18.2%; silently promoting composite families would make the fast default much longer without reproducing the claimed phantom-loss benefit; the explicit `--accurate` and `--full` modes already provide at least nine 110 ms repetitions, and the harness publishes IQR at every width, so the fast default remains uniform and conclusions still require the explicit accurate modes; adaptive-timing-screen-a-c125ea0-m5max-20260804.json, adaptive-timing-screen-b-c125ea0-m5max-20260804.json, adaptive-timing-accurate-c125ea0-m5max-20260804.json |

## Gemma4

| ID | Hypothesis | Status | Evidence |
| --- | --- | --- | --- |
| GEMMA-01 | Add a wide-compute IR type for BigInt intermediates | pending | |
| GEMMA-02 | Add a carry-chain IR node | pending | |
| GEMMA-03 | Add first-class FFT/NTT IR operations | pending | |
| GEMMA-04 | Add vector constant-load IR operations | pending | |
| GEMMA-05 | Runtime trace detection and JIT for repeated arithmetic | pending | |
| GEMMA-06 | Compiler-directed prime-candidate prefiltering | pending | |
| GEMMA-07 | Explicit SIMD lowering for bitwise operations | premise rejected | the measured AArch64 boxed path does not need a new WIRE vector node or hand-written intrinsic to obtain the proposed lowering: Clang already emits an eight-limb unrolled NEON loop with four q-register AND/OR/XOR operations from the operation-selected C loop; disabling loop and SLP vectorization made the current 16..512-limb path 2.39x slower by geomean, while the auto-vectorized build won every measured GMP cell; bitwise-auto-simd-684afd9-m5max-20260804.json; emitted bench-lane assembly inspected with otool; GMP bitwise/shift fuzz 100000x1024 passed |
| GEMMA-08 | Algebraic-normal-form modular lowering | pending | |
| GEMMA-09 | Scratchpad allocation for temporary BigInts | pending | |
| GEMMA-10 | Arithmetic-loop vectorization directives | pending | |
| GEMMA-11 | Fixed-point/scaled-integer IR representation | pending | |
| GEMMA-12 | Secondary arithmetic-context graph in the AST | pending | |
| GEMMA-13 | Implicit identity-element propagation | pending | |
| GEMMA-14 | Compile-time modular-context detection | pending | |
| GEMMA-15 | Cross-platform native-intrinsic abstraction | pending | |
| GEMMA-16 | Specialized dynamic type-promotion paths | pending | |
| GEMMA-17 | Atomic operations for shared BigInt structures | pending | |
| GEMMA-18 | Algebraic theory tags such as p-adics | pending | |
| GEMMA-19 | Cost-weighted symbol-value lookup caching | pending | |
| GEMMA-20 | Whole-program interprocedural constant folding | pending | |

## Qwen3.6

| ID | Hypothesis | Status | Evidence |
| --- | --- | --- | --- |
| QWEN-01 | Recalibrate the Karatsuba threshold and basecase | pending | |
| QWEN-02 | Fold coefficients in squaring kernels | premise rejected | the proposal's premise that squaring uses the ordinary multiply ladder is false: pointer-identical x*x routes through bigint_sqr_dispatch_cap, whose dedicated school/Karatsuba/Toom square kernels fold diagonal and doubled cross terms; a36ac29's forced square-kernel crossover plus the boxed sqr artifacts measure that dedicated ladder, and current GMP fuzz 2000x2048 passed |
| QWEN-03 | Redundant/Montgomery representation for multiply chains | pending | |
| QWEN-04 | Johnson-style fast GCD at large widths | pending | compare against current HGCD work model |
| QWEN-05 | Strip common trailing zeros before GCD | rejected | an always-on top-level strip/right-shift/result-restore candidate was measured end-to-end at 2..8192 limbs with exact common trailing-zero counts 0, 1, 13, and 63; the candidate/base geomeans were 0.983, 1.008, 0.994, and 0.937 respectively, so only the contrived 63-bit geometry won consistently while the 0/1-bit cases that dominate independent random integers were neutral or slower; gcd-common-tz0-03039a2-m5max-20260804.json, gcd-common-tz1-03039a2-m5max-20260804.json, gcd-common-tz13-03039a2-m5max-20260804.json, gcd-common-tz63-03039a2-m5max-20260804.json; 20000-case GMP differential fuzz including exact shared shifts 1..63 passed; the production candidate was removed while the operand control and stronger fuzz coverage were retained |
| QWEN-06 | Increase Lehmer window and tighten simulation | pending | current HGCD counter audit is prerequisite evidence only |
| QWEN-07 | Batched Newton–Raphson reciprocal digits for division | pending | |
| QWEN-08 | Barrett precomputation for repeated reductions | kept | WPrimeModCtx precomputes the modulus reciprocal and reuses it across the full powmod ladder and decimal D&C levels; matrix-7a96d5c-accurate-20260802.json has all powmod cells faster than GMP, including even-modulus/large-width Barrett coverage in focused fuzz |
| QWEN-09 | Parallel-prefix carry add/sub | kept | the general-length AArch64 hybrid computes vector generate/propagate masks, resolves exact per-limb carry masks with a word-level prefix formula, and applies them in a second SIMD pass; lowering its boxed cutoff to 288 improved the 272..384 add/sub matrix 2.0% geomean with no >5% regression; addsub-neon-min288-f011cd7-m5max-20260804.json; GMP fuzz 100000x1024 passed |
| QWEN-10 | Skip zero spans in sparse add/sub | rejected | an isolated boxed candidate scanned the smaller/right operand's zero low-limb prefix, copied the unaffected destination prefix, and began the carry/borrow kernel at the first nonzero limb; even with exactly half the magnitude zero it lost every acceptance-grade cell: 2.206x/2.005x candidate/baseline at add/sub256, 1.425x/1.396x at 1024, and 1.313x/1.299x at 4096; addsub-zero-prefix-half256-55b6b39-m5max-20260804.json, addsub-zero-prefix-half1024-55b6b39-m5max-20260804.json, and addsub-zero-prefix-half4096-55b6b39-m5max-20260804.json; all paired runs passed the public-GMP result check; the candidate was removed while the benchmark-only sparse geometry was retained |
| QWEN-11 | Per-thread allocation slot cache | kept | production has one direct TLS handoff plus two buffers per logarithmic class; hot-handoff-6f41042-m5max-20260804.json isolates the handoff from those buckets and measures a 12.6% geomean win across 28 small boxed cells, while result-pool-132f1c7-m5max-20260804.tsv measures the complete pool at 1.00-1.56x for 1024-limb operations and 5.2-8.5x for four-limb word operations versus malloc/free |
| QWEN-12 | Stack-passed scratch results up to eight limbs | pending | |
| QWEN-13 | SIMD bitwise operations | kept | current positive equal-width AND/OR/XOR loops auto-vectorize to four 128-bit NEON operations per eight-limb iteration; against an otherwise-identical `-fno-vectorize -fno-slp-vectorize` build, the 18 boxed cells from 16 through 512 limbs improved 58.1% by geomean (0.339x-0.606x), and every current cell measured 0.659x-0.843x GMP; 4/8-limb fixed rungs remain scalar because the A/B found no SIMD benefit there; bitwise-auto-simd-684afd9-m5max-20260804.json; GMP bitwise/shift fuzz 100000x1024 passed |
| QWEN-14 | Cache/decompose shift offsets | premise rejected | the proposed per-call division/modulo bottleneck is absent: bignum_shl_generic and bignum_shr_generic each decompose a dynamic count once with `k >> 6` and `k & 63`, the aligned branch already copies with memcpy, and the always-inlined boxed shift-by-13 lane constant-folds both values before entering its fixed positive kernels; the current default screen has all 40 shl/shr cells faster than GMP at 0.245x-0.872x; matrix-dd523e6-screen-m5max-20260804.json; source and emitted lane assembly inspected |
| QWEN-15 | SIMD/early-exit magnitude comparison | rejected | an AArch64 candidate preserved the scalar most-significant pair early exit, then tested each eight-limb equal prefix with four 128-bit XORs and an OR reduction; on low-limb-difference full scans it lost all five 64..8192-limb boxed cells, regressed 9.7% by geomean, and every loss exceeded 5%; high-limb-difference and equal shapes were neutral at 0.988x and 1.004x, so the candidate was removed; cmp-neon-prefix-low-4bb7a7d-m5max-20260804.json, cmp-neon-prefix-high-4bb7a7d-m5max-20260804.json, cmp-neon-prefix-equal-4bb7a7d-m5max-20260804.json; each sweep checked its shaped operands against GMP; the retained BENCH_CMP_SHAPE control also exposed current high-difference compares at 1.36x-1.53x GMP |
| QWEN-16 | Cache reciprocals for recurring divisors/moduli | kept | the two-entry one-limb preinverse cache won all ten boxed div1 cells from 2 through 1024 limbs and improved 13.5% by geomean; the admitted exact-divisor multi-limb cache improved the 12-cell repeated div/mod geomean 21.8%, including 1.94x div1024 and 2.37x mod4096 speedups; its lone mod64 regression led to a measured exact-width admission hole that improved mod64 19.9% and the eight-cell control geomean 3.7% with no >5% regression; div1-preinv-cache-b2ca7c0-m5max-20260804.json, divmod-recip-cache-b2ca7c0-m5max-20260804.json, mod-barrett-skip64-b2ca7c0-m5max-20260804.json; GMP fuzz passed 100000 single-limb, 10000 mixed div/mod, 5000x64, and 2000x256 reciprocal cases |
| QWEN-17 | Divide-and-conquer decimal conversion | kept | current base-10 writer and parser switch from repeated 10^19 division/Horner to cached-power divide-and-conquer; forcing the quadratic bases through 1024 limbs made current tostr/fromstr 0.065x/0.331x at 1024 and improved the 16-cell geomean 53.5%, while every current cell remained faster than GMP; decimal-dc-6b91db9-m5max-20260804.json; each boxed cell round-tripped against the public GMP writer/parser oracle; later-parser-threshold smokes at 768/960 digits were neutral overall or regressed adjacent cells, so production stayed unchanged |
| QWEN-18 | Preserve O(1) sign-overlay paths in all lowering modes | kept | a forced-copy boxed baseline isolated the current tag-sign path at 1, 64, and 8192 limbs: neg/abs won all six cells, improving 92.8% by geomean and holding 1.41-1.54 ns at every width versus 739-765 ns copies at 8192 limbs; all 40 current neg/abs matrix cells are faster than GMP; tag-sign-overlay-4666161-m5max-20260804.json; bigint_tag_sign_spec passed interpreted and release/native/fast across 1..48-limb arithmetic, predicates, formatting, hashing, and linked-view bang semantics |
| QWEN-19 | Function attributes and vectorization controls for limb loops | premise rejected | the bundled mechanism is not sound as a general optimization: Clang `annotate("no_splat")` is not a backend vectorization control, AArch64 dot-product instructions do not accelerate 64x64 limb carry arithmetic, and `assume_aligned(..., 1)` adds no information; production already uses BN_HOT_SECTION/alignment on hot kernels, explicit carry-chain assembly, and targeted unroll/vector pragmas; globally disabling loop/SLP vectorization made the measured 16..512-limb bitwise loop band 2.39x slower, so controls must remain kernel-specific; bitwise-auto-simd-684afd9-m5max-20260804.json; emitted AArch64 assembly inspected |
| QWEN-20 | Return one-limb multiply results without a general ladder | kept | bigint_mul_positive_11 and early boxed N×1 entries allocate/publish directly without the general ladder; mul1 lifecycle artifact cuts 2-8-limb boxed time 39-45% and current 1-limb mul1 is faster than GMP |

## Grok

| ID | Hypothesis | Status | Evidence |
| --- | --- | --- | --- |
| GROK-01 | Close residual mul1 kernel throughput gaps | kept | rolling-carry AArch64 bn_mul_1 keeps flags live across the loop and settles carry once; 1ba1be6 probes moved 64/256/1024-limb kernels to 1.01/1.02/1.01x GMP and mulchain to 0.98x; remaining boxed mul1 overhead is recorded separately |
| GROK-02 | Mutate/recycle the destination for N×1 multiply | kept | w_bigint_mul_mut writes the one-word product into a proven-dead unique receiver and falls back on alias/capacity guards; program-loops-6e7c006-m5max-20260804.tsv measures mulchain at 0.989x GMP with matched checksum |
| GROK-03 | Fixed-length add1/sub1 kernels at 2–8 limbs | pending | a C straight-line 2/3/4-limb candidate was rejected after losing 9/10 boxed cells, regressing 3.5% geomean with five >5% regressions; production stayed unchanged; addsub1-straight234-dd523e6-m5max-20260804.json; genuinely hand-scheduled AArch64 rungs through 8 remain distinct and untested |
| GROK-04 | Optimize Toom-3 evaluation/pointwise/interpolation at 400–500 | kept | dfb94bc optimized the pointwise phase by running independent Toom-3 products through the persistent worker pool; boxed mul improved 20.5%/1.7%/10.2% at 384/448/512 versus the matched ce81fcb baseline, held at 1024, and won all five measured GMP cells; mulsqr-a64-par-cutoffs-df0c604-m5max-20260804.json -> mul-a64-par-toom3-ce81fcb-m5max-20260804.json; current GMP fuzz 2000x2048 passed |
| GROK-05 | Re-fit the 48-limb multiply ladder | kept | disabling BN_MUL_SPLIT_48 while holding the source/build constant made boxed mul48 1.189x slower; the current path is 0.841x its generic fallback and 0.848x GMP over nine alternating 110 ms rounds; mul-fixed-toom2-32-40-48-1f431bc-m5max-20260804.json; GMP fuzz 10000x64 passed |
| GROK-06 | Fill the 384–512 squaring-ladder gap | kept | ce81fcb lowered the AArch64 Karatsuba-square parallel cutoff to 384; boxed sqr improved 49.6% at 384 and 68.3% at 448, flipping both to clear GMP wins; sqr512 regressed 8.6% but stayed at 0.720x GMP, and the five-cell 256..1024 sqr geomean was 0.712x GMP; mulsqr-df0c604-accurate-m5max-20260804.json -> mulsqr-a64-par-cutoffs-df0c604-m5max-20260804.json; current GMP fuzz 2000x2048 passed |
| GROK-07 | Polish mid-size equal-length add/sub kernels | kept | the fixed 3..64/sub128 ladder improves its generic fallback 9.7% geomean across 20 boxed cells, and the 288-limb SIMD cutoff improves the adjacent 272..384 matrix another 2.0% geomean without a >5% regression; addsub-fixed-basecases-f011cd7-m5max-20260804.json and addsub-neon-min288-f011cd7-m5max-20260804.json; GMP fuzz 100000x1024 passed |
| GROK-08 | Reduce large HGCD application and matrix-product cost | kept | half slices amortize row application at 6144+; accurate boxed artifact gcdlcm-half-slice-7096978-m5max-20260804.json; remaining GMP losses recorded |
| GROK-09 | Reduce large-isqrt iteration/fallback cost | pending | audit related commits 4b823f3, df0c604 |
| GROK-10 | Extend compiler mutate-if-unique coverage | kept | compiler covers +,-,*,/ dead accumulators plus Fibonacci rotation destinations with fail-closed alias analysis; bigint_mutate_unique_spec and program-loops-6e7c006-m5max-20260804.tsv provide correctness and end-to-end evidence |
| GROK-11 | Pool TLS scratch for Toom/isqrt/NTT | pending | |
| GROK-12 | Fit threshold crossovers instead of choosing first-best | pending | |
| GROK-13 | Improve rectangular/lopsided multiplication | pending | |
| GROK-14 | Fill useful fixed schoolbook leaf sizes | pending | the proposed 6x6/10x10 candidates have been measured and rejected (see DEEP-19); other recurrence-derived leaf sizes still require their own isolated A/B |
| GROK-15 | Re-evaluate live-depth-aware capacity policy | rejected | live-depth-corrected 48-point capacity grid found no hybrid policy meeting >=20% peak-RSS improvement with churn <=+10%; best peak win was 2.8%; b4-base-*.tsv, b4-grid-*.tsv, NOTED_TRADEOFFS.md |
| GROK-16 | Tune parallel workers only in winning large bands | pending | audit related commits 803a5c4, dfb94bc |
| GROK-17 | Improve div1/multi-limb preinverse cache locality | pending | |
| GROK-18 | Reduce identity/shared-mark tax | pending | keeping the hot-slot header live instead of clear/revive was neutral/slower overall (1.002x geomean, 9 wins/11 losses, one >5% regression) in hot-live-header-1ee775a-m5max-20260804.json; the requested identity-mix and escape/shared experiment remains to run |
| GROK-19 | Make page-hazard rehoming cheaper/more selective | pending | broadening current rehoming to 384-512 limbs was measured and rejected (GLM-17); the distinct selective/cheaper-policy hypothesis remains to test |
| GROK-20 | Add end-to-end language loops to acceptance evidence | kept | accumulate, mulchain, addchain, and divchain are release/native/fast whole-language loops with matched GMP checksums and median/IQR timing; program-loops-6e7c006-m5max-20260804.tsv |

## DeepSeek-v4-pro

| ID | Hypothesis | Status | Evidence |
| --- | --- | --- | --- |
| DEEP-01 | Inline tiny add1/sub1 at 1–8 limbs | kept | always-inlining the word add/sub kernels improved accurate 4/8-limb add1 by 14/19% and sub1 by 2/11%; addsub1-dfb94bc-accurate-m5max-20260804.json -> addsub1-inline-dfb94bc-m5max-20260804.json; residual 2-4-limb losses remain explicit |
| DEEP-02 | Register-only mul1 paths at 1–4 limbs | kept | bigint_mul_positive_11 and bigint_mul_n1_small keep 1-4-limb products in inline scalar carry chains and publish directly; mul1 lifecycle artifact reduced 2/3/4-limb boxed time 45/44/42% |
| DEEP-03 | Fixed mul1 kernels at 5–7 limbs | kept | extending the boxed straight-line carry chain from 4 through 7 limbs improved mul1 at 5/6/7 limbs by 39.2%/36.6%/35.2%; the 2..16-limb boxed screen improved 19.4% geomean with no >5% regression (the only median loss was +0.8% at 4 with paired IQR 0.205); mul1-small-max7-10ffc4b-m5max-20260804.json; GMP fuzz 100000/100000 passed across both orders, signs, and 2..128 limbs; residual 3..8-limb GMP losses remain |
| DEEP-04 | Software-pipeline mul1 at 8–48 limbs | kept | rolling-carry asm interleaves next-half loads with the adcs chain and fixed rungs cover 8/16/24/32/40/48; 1ba1be6 kernel and boxed measurements show broad improvement with differential/ASan coverage |
| DEEP-05 | Tune Karatsuba/Toom transitions at 32–48 limbs | kept | the forced family sweep selected difference-form Toom-2 in this band; the boxed disable-A/B confirms the fixed 32/40/48 routes improve 17.5%/17.4%/18.9% with no measured cell regression and all three cells faster than GMP; mul-fixed-toom2-32-40-48-1f431bc-m5max-20260804.json |
| DEEP-06 | Add/fix a fixed-shape 32-limb Toom-2 difference path | kept | BN_MUL_POWER2_FIXED selects bn_toom2_diff32 with fixed 16-limb children; disabling that fixed family made boxed mul32 1.175x slower, while the current path measured 0.767x GMP; mul-fixed-toom2-32-40-48-1f431bc-m5max-20260804.json; GMP fuzz 10000x64 passed |
| DEEP-07 | Optimize the 384–448 multiply/square transition | kept | ce81fcb rerouted 448-limb multiply to its measured fixed difference split and opened square parallelism at 384; dfb94bc then parallelized Toom-3 point products; boxed mul384/448 moved from 1.032x/1.197x GMP to 0.828x/0.802x and boxed sqr384/448 moved from 1.028x/1.102x to 0.691x/0.649x; matched accurate artifacts mulsqr-df0c604-accurate-m5max-20260804.json, mulsqr-a64-par-cutoffs-df0c604-m5max-20260804.json, and mul-a64-par-toom3-ce81fcb-m5max-20260804.json; current GMP fuzz 2000x2048 passed |
| DEEP-08 | Parallelize large GCD matrix work | kept | four independent row products use the persistent worker pool at 2048+; baseline gcdlcm-half-slice-7096978-m5max-20260804.json; result gcdlcm-par-apply-3ccd13b-m5max-20260804.json; 20/22 through 65536 and every cell through 16385 wins; GMP fuzz 1000x8192 + 20x65536; sanitizer fuzz 500x8192; interpreted and release/native/fast GCD/LCM specs |
| DEEP-09 | Adapt NEON add/sub to GCD pair replay | pending | current GCD flame/profile evidence is prerequisite evidence only |
| DEEP-10 | Seed large isqrt more accurately | pending | audit related commits 4b823f3, df0c604 |
| DEEP-11 | Add a fixed eight-limb modulo path | pending | |
| DEEP-12 | Optimize the 128-limb division choice | pending | |
| DEEP-13 | Cache division reciprocals on first use where profitable | pending | |
| DEEP-14 | Inline/specialize boxed 2×2 GCD | pending | |
| DEEP-15 | Add tiny per-size allocation slots | pending | |
| DEEP-16 | Fuse allocation with result computation | pending | existing word add/sub already hoists allocation into the always-inlined operation wrapper; replacing its range-checked hot take with exact 2/4-limb capacity selection lost 8/10 boxed cells, regressed 4.6% geomean, and had five >5% regressions, so the candidate was removed; addsub1-exact-small-c05ae06-m5max-20260804.json; other operation families remain to audit |
| DEEP-17 | Add a dedicated 3×3 multiply kernel | kept | the existing bn_mul_eq3_inline was isolated with BN_MUL_EQ3_INLINE=0 as the baseline; nine alternating 110 ms boxed rounds measured candidate/baseline 0.607x (paired IQR 0.038), moving mul3 from 1.162x GMP to 0.731x; mul-eq3-inline-e465fd4-m5max-20260804.json; GMP multiply/square fuzz 10000x64 passed |
| DEEP-18 | Reschedule AArch64 addmul_1 | pending | |
| DEEP-19 | Add dedicated 6×6 and 10×10 multiply kernels | rejected | nine alternating 110 ms boxed rounds found the C 10x10 candidate 1.562x slower than the generic path; 6x6 alone improved its target to 0.806-0.881x, but two placement-controlled adjacent screens produced unacceptable 7-11% regressions at mul10/mul12, so both candidates were removed and production stayed unchanged; mul-eq6-eq10-candidates-6ad6737-m5max-20260804.json, mul-eq6-adjacent-screen-6ad6737-m5max-20260804.json, mul-eq6-adjacent-layout-6ad6737-m5max-20260804.json |
| DEEP-20 | Profile-guided threshold tuning for Apple M5 Max | pending | audit related commits ce81fcb, dfb94bc |

## Campaign evidence already available for audit

These artifacts and commits are candidates for item-level evidence, but their
existence does not automatically disposition an item:

- 1ba1be6, 5cb55ac: one-limb multiplication kernel/boxed fast path.
- 3926cbb, 6aea99c: reciprocal and small one-word division.
- 74f497c, ec92b25: boxed word add/sub allocation and inlining.
- 4b823f3, df0c604: isqrt quotient dispatch and division-width tuning.
- ce81fcb, dfb94bc: AArch64 multiply/square cutoffs and parallel Toom-3 points.
- e465fd4 follow-up artifact: isolated boxed 3x3 inline-multiply A/B.
- 1f431bc follow-up artifact: isolated boxed fixed-Toom-2 A/B at 32/40/48.
- 6ad6737 follow-up artifacts: rejected 6x6/10x10 fixed-leaf candidates and adjacent-size screens.
- 10ffc4b follow-up artifact: boxed 5-7-limb mul1 straight-line A/B.
- 996180d follow-up artifacts: rejected 128-512 add/sub and 256-1024 mul/sqr rehome extensions.
- fbf77a1 follow-up artifact: rejected branch-free div1 second reciprocal correction across 2-1024 limbs.
- f011cd7 follow-up artifacts: fixed add/sub basecase disable A/B and 224/288-limb NEON crossover probes.
- 673ec76 follow-up artifact: exact 128/256-limb add/sub carry-select disable A/B.
- 6f41042 follow-up artifact: direct hot handoff versus thread-local size buckets across 28 small boxed cells.
- 1ee775a follow-up artifacts: inline release handoff A/B and neutral hot-slot live-header A/B.
- dd523e6 screen: current 485-cell default matrix, plus accurate 1..16-limb add1/sub1 confirmation and rejected C straight-line 2/3/4-limb candidate.
- c05ae06 follow-up artifact: rejected exact-capacity hot allocation for 2-4-limb word add/sub results.
- 684afd9 follow-up artifact: isolated the existing auto-vectorized boxed AND/OR/XOR loops from a scalarized build across 4-512 limbs.
- 4bb7a7d follow-up artifacts: rejected a SIMD equal-prefix compare candidate across low-difference, high-difference, and equal operands; retained the compile-time benchmark shape control.
- 4666161 follow-up artifact: isolated O(1) boxed tag-sign neg/abs against forced limb copies; added Tungsten-only variant timing while retaining GMP correctness checks.
- 6b91db9 follow-up artifact: isolated divide-and-conquer decimal writing/parsing from their quadratic base algorithms through 1024 limbs.
- b2ca7c0 follow-up artifacts: isolated one-limb and multi-limb reciprocal caches, then admitted an exact mod64 ordinary-division exception.
- 1aa9e10: timing stability metadata.
- 66227a5: documented --full large/FFT-band preset.
- JSON and flamegraph artifacts under benchmarks/big_math/baselines/.
