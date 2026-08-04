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
| GLM-02 | Direct hot-handoff slot for results up to 64 limbs | pending | |
| GLM-03 | Hand-written AArch64 normalized div-by-word kernel | pending | audit related commits 3926cbb, 6aea99c |
| GLM-04 | Branch-free reciprocal correction for 32-bit divisors | pending | audit related commit 3926cbb |
| GLM-05 | Subquadratic half-GCD above about 1024 limbs | kept | existing recursive HGCD retained; half-slice band added at 6144; gcdlcm-half-slice-7096978-m5max-20260804.json; GMP fuzz 1000x8192 + 10x65536; sanitizer fuzz 250x8192 |
| GLM-06 | Reuse one scratch remainder across Lehmer steps | pending | |
| GLM-07 | isqrt reciprocal-sqrt seed, scratch reuse, and fewer divisions | pending | audit related commits 4b823f3, df0c604 |
| GLM-08 | Retune Toom-3 / Toom-4 crossover | pending | audit related commits ce81fcb, dfb94bc |
| GLM-09 | Lower NTT threshold and reduce SSA workspace clearing | pending | |
| GLM-10 | Widen NEON hybrid add/sub dispatch | pending | |
| GLM-11 | General carry-select add/sub | pending | |
| GLM-12 | Recognize and fuse addmul_1 / submul_1 language shapes | pending | |
| GLM-13 | BigInt Montgomery reduction for powmod | pending | |
| GLM-14 | LCM via exact quotient and one multiply | pending | |
| GLM-15 | Multi-limb exact division | pending | |
| GLM-16 | Defer boxing and merge shared-check with pool return | pending | |
| GLM-17 | Page-offset rehoming at 384–512 limbs | pending | |
| GLM-18 | Hand-written add/sub basecases for 8–128 limbs | pending | |
| GLM-19 | Toom-2 equal/difference specializations at 32–48 limbs | pending | |
| GLM-20 | Branch-free carry/correction tails in mul1 and div1 | pending | |

## Kimi-K3

| ID | Hypothesis | Status | Evidence |
| --- | --- | --- | --- |
| KIMI-01 | AArch64 normalized divrem_1-class kernel | pending | audit related commits 3926cbb, 6aea99c |
| KIMI-02 | Route 32-bit divisors through normalized preinverse division | pending | |
| KIMI-03 | Hoist N×1 routing in the multiply entry | pending | |
| KIMI-04 | Straight-line mul1 rungs and close fixed-kernel gaps | pending | audit related commits 1ba1be6, 5cb55ac |
| KIMI-05 | Extend page-hazard guard to division and large results | pending | |
| KIMI-06 | Mutate-if-unique entries for word add/sub/mul/div | pending | audit related commit d1715f9 |
| KIMI-07 | Extend compiler mut-accumulator recognition | pending | |
| KIMI-08 | Add mulchain1/divchain1 whole-language-loop lanes | kept | run_program_loops.sh builds Tungsten release/native/fast and matched GMP loops, alternates lanes, checks checksums, and now reports median/IQR; program-loops-6e7c006-m5max-20260804.tsv records a noisy loaded-host run without using it for a performance disposition |
| KIMI-09 | Skip redundant write-before-read workspace clearing | pending | |
| KIMI-10 | Fixed-size multiply study at 32/40/48 limbs | pending | |
| KIMI-11 | Optimize Toom-3 evaluation/interpolation at 400–500 limbs | pending | audit related commit dfb94bc |
| KIMI-12 | Rebalance large isqrt division | pending | audit related commits 4b823f3, df0c604 |
| KIMI-13 | Audit HGCD inner routing and tune its band | kept | counters found 100% block acceptance and row-apply dominance; propagated half slices win 4–7% at 8192–16384; gcdlcm-half-slice-7096978-m5max-20260804.json |
| KIMI-14 | Probe NEON add crossover at 96–256 limbs | pending | |
| KIMI-15 | Add mid-band fixed squaring rungs | pending | |
| KIMI-16 | Mark generic entries and error paths cold | pending | |
| KIMI-17 | Re-open the live-depth capacity-policy default | pending | |
| KIMI-18 | Retune parallel cutoffs under quiet/load-monitored conditions | pending | audit related commits ce81fcb, dfb94bc |
| KIMI-19 | Add instructions-retired measurement | pending | |
| KIMI-20 | Use per-operation adaptive timing targets | pending | audit related commit 1aa9e10 |

## Gemma4

| ID | Hypothesis | Status | Evidence |
| --- | --- | --- | --- |
| GEMMA-01 | Add a wide-compute IR type for BigInt intermediates | pending | |
| GEMMA-02 | Add a carry-chain IR node | pending | |
| GEMMA-03 | Add first-class FFT/NTT IR operations | pending | |
| GEMMA-04 | Add vector constant-load IR operations | pending | |
| GEMMA-05 | Runtime trace detection and JIT for repeated arithmetic | pending | |
| GEMMA-06 | Compiler-directed prime-candidate prefiltering | pending | |
| GEMMA-07 | Explicit SIMD lowering for bitwise operations | pending | |
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
| QWEN-02 | Fold coefficients in squaring kernels | pending | audit related commit ce81fcb |
| QWEN-03 | Redundant/Montgomery representation for multiply chains | pending | |
| QWEN-04 | Johnson-style fast GCD at large widths | pending | compare against current HGCD work model |
| QWEN-05 | Strip common trailing zeros before GCD | pending | |
| QWEN-06 | Increase Lehmer window and tighten simulation | pending | current HGCD counter audit is prerequisite evidence only |
| QWEN-07 | Batched Newton–Raphson reciprocal digits for division | pending | |
| QWEN-08 | Barrett precomputation for repeated reductions | pending | |
| QWEN-09 | Parallel-prefix carry add/sub | pending | |
| QWEN-10 | Skip zero spans in sparse add/sub | pending | |
| QWEN-11 | Per-thread allocation slot cache | pending | |
| QWEN-12 | Stack-passed scratch results up to eight limbs | pending | |
| QWEN-13 | SIMD bitwise operations | pending | |
| QWEN-14 | Cache/decompose shift offsets | pending | |
| QWEN-15 | SIMD/early-exit magnitude comparison | pending | |
| QWEN-16 | Cache reciprocals for recurring divisors/moduli | pending | |
| QWEN-17 | Divide-and-conquer decimal conversion | pending | |
| QWEN-18 | Preserve O(1) sign-overlay paths in all lowering modes | pending | |
| QWEN-19 | Function attributes and vectorization controls for limb loops | pending | |
| QWEN-20 | Return one-limb multiply results without a general ladder | pending | audit related commit 5cb55ac |

## Grok

| ID | Hypothesis | Status | Evidence |
| --- | --- | --- | --- |
| GROK-01 | Close residual mul1 kernel throughput gaps | pending | audit related commits 1ba1be6, 5cb55ac |
| GROK-02 | Mutate/recycle the destination for N×1 multiply | pending | |
| GROK-03 | Fixed-length add1/sub1 kernels at 2–8 limbs | pending | audit related commits 74f497c, ec92b25 |
| GROK-04 | Optimize Toom-3 evaluation/pointwise/interpolation at 400–500 | pending | audit related commit dfb94bc |
| GROK-05 | Re-fit the 48-limb multiply ladder | pending | |
| GROK-06 | Fill the 384–512 squaring-ladder gap | pending | audit related commit ce81fcb |
| GROK-07 | Polish mid-size equal-length add/sub kernels | pending | |
| GROK-08 | Reduce large HGCD application and matrix-product cost | kept | half slices amortize row application at 6144+; accurate boxed artifact gcdlcm-half-slice-7096978-m5max-20260804.json; remaining GMP losses recorded |
| GROK-09 | Reduce large-isqrt iteration/fallback cost | pending | audit related commits 4b823f3, df0c604 |
| GROK-10 | Extend compiler mutate-if-unique coverage | pending | |
| GROK-11 | Pool TLS scratch for Toom/isqrt/NTT | pending | |
| GROK-12 | Fit threshold crossovers instead of choosing first-best | pending | |
| GROK-13 | Improve rectangular/lopsided multiplication | pending | |
| GROK-14 | Fill useful fixed schoolbook leaf sizes | pending | |
| GROK-15 | Re-evaluate live-depth-aware capacity policy | pending | |
| GROK-16 | Tune parallel workers only in winning large bands | pending | audit related commits 803a5c4, dfb94bc |
| GROK-17 | Improve div1/multi-limb preinverse cache locality | pending | |
| GROK-18 | Reduce identity/shared-mark tax | pending | |
| GROK-19 | Make page-hazard rehoming cheaper/more selective | pending | |
| GROK-20 | Add end-to-end language loops to acceptance evidence | kept | accumulate, mulchain, addchain, and divchain are release/native/fast whole-language loops with matched GMP checksums and median/IQR timing; program-loops-6e7c006-m5max-20260804.tsv |

## DeepSeek-v4-pro

| ID | Hypothesis | Status | Evidence |
| --- | --- | --- | --- |
| DEEP-01 | Inline tiny add1/sub1 at 1–8 limbs | pending | audit related commits 74f497c, ec92b25 |
| DEEP-02 | Register-only mul1 paths at 1–4 limbs | pending | audit related commit 5cb55ac |
| DEEP-03 | Fixed mul1 kernels at 5–7 limbs | pending | |
| DEEP-04 | Software-pipeline mul1 at 8–48 limbs | pending | audit related commit 1ba1be6 |
| DEEP-05 | Tune Karatsuba/Toom transitions at 32–48 limbs | pending | |
| DEEP-06 | Add/fix a fixed-shape 32-limb Toom-2 difference path | pending | |
| DEEP-07 | Optimize the 384–448 multiply/square transition | pending | audit related commits ce81fcb, dfb94bc |
| DEEP-08 | Parallelize large GCD matrix work | kept | four independent row products use the persistent worker pool at 2048+; baseline gcdlcm-half-slice-7096978-m5max-20260804.json; result gcdlcm-par-apply-3ccd13b-m5max-20260804.json; 20/22 through 65536 and every cell through 16385 wins; GMP fuzz 1000x8192 + 20x65536; sanitizer fuzz 500x8192; interpreted and release/native/fast GCD/LCM specs |
| DEEP-09 | Adapt NEON add/sub to GCD pair replay | pending | current GCD flame/profile evidence is prerequisite evidence only |
| DEEP-10 | Seed large isqrt more accurately | pending | audit related commits 4b823f3, df0c604 |
| DEEP-11 | Add a fixed eight-limb modulo path | pending | |
| DEEP-12 | Optimize the 128-limb division choice | pending | |
| DEEP-13 | Cache division reciprocals on first use where profitable | pending | |
| DEEP-14 | Inline/specialize boxed 2×2 GCD | pending | |
| DEEP-15 | Add tiny per-size allocation slots | pending | |
| DEEP-16 | Fuse allocation with result computation | pending | |
| DEEP-17 | Add a dedicated 3×3 multiply kernel | pending | |
| DEEP-18 | Reschedule AArch64 addmul_1 | pending | |
| DEEP-19 | Add dedicated 6×6 and 10×10 multiply kernels | pending | |
| DEEP-20 | Profile-guided threshold tuning for Apple M5 Max | pending | audit related commits ce81fcb, dfb94bc |

## Campaign evidence already available for audit

These artifacts and commits are candidates for item-level evidence, but their
existence does not automatically disposition an item:

- 1ba1be6, 5cb55ac: one-limb multiplication kernel/boxed fast path.
- 3926cbb, 6aea99c: reciprocal and small one-word division.
- 74f497c, ec92b25: boxed word add/sub allocation and inlining.
- 4b823f3, df0c604: isqrt quotient dispatch and division-width tuning.
- ce81fcb, dfb94bc: AArch64 multiply/square cutoffs and parallel Toom-3 points.
- 1aa9e10: timing stability metadata.
- 66227a5: documented --full large/FFT-band preset.
- JSON and flamegraph artifacts under benchmarks/big_math/baselines/.
