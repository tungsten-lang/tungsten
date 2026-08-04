# Noted, not taken

Wins in one area that cost another get recorded here instead of shipped:
the measured win, the measured loss, and the condition that would make the
trade worth it. (Bignum campaign ground rule, 2026-08-02.)

## Toom-6 enablement (B3a) — NOT taken (2026-08-02)

Forced-kernel sweep (`run_kernel_crossover.sh mul`, GMP-verified operands):
`bn_toom6` is 12-63% SLOWER than `bn_toom4` at every size 384..4096 — the
entire band below BN_SSA_THRESHOLD. There is no crossover to set a
threshold at; both BN_TOOM6_THRESHOLD and BN_SQR_TOOM6_THRESHOLD stay
INT32_MAX. The kernel is written but not competitive on this uarch.
**Condition to take it:** profile evaluation, pointwise multiplication, and
interpolation separately to identify the dominant gap, then re-run the
crossover. Threshold flipping alone cannot help.

## Forced-kernel threshold inference — REJECTED (updated 2026-08-04)

`tune_bigint_thresholds.sh` (first-best-per-family heuristic, REPS=3)
proposed KARA=15 / TOOM3=176 / TOOM4=2816 — contradicted by the forced
crossover data (toom4 dominates from ~600, toom2 wins to ~360). The
heuristic picks the first size a family wins a noisy 3-rep row, which is
not a crossover. Its generated header is also invisible to
`harness_is_stale` (fixed: `runtime/generated/*.h` is now watched), so
past tuner validations may have measured stale binaries.

A best-of-9 smooth log-log fit was tested as the replacement rule. It predicted
a 13-limb schoolbook/Toom-2 crossover from the same raw sweep. The exact boxed
13-versus-24 affected-cell A/B lost 10/11 cells and regressed 6.5% by geomean;
several green cells became slower than GMP. Recursive leaf choices and
fixed-shape kernels make these curves discontinuous, so fitting is not a valid
product-threshold oracle either. The tuner now records a best-of-9 forced sweep
but does not generate an active header. Each candidate cutoff must be validated
over every boxed cell whose dispatch changes.

Parallel and family cutoffs have since been calibrated with alternating boxed
A/Bs on the M5 Max; see the suggestion ledger and retained JSON artifacts.

## NEW red cells: mul@384 (1.03) and mul@448 (1.20) — kernel gap, not tuning

Neither size is in DEFAULT_SIZES (the 368..512 blind spot strikes again).
Forced-kernel data says dispatch already picks our best kernel at both
sizes; at 448 the BEST forced kernel (toom3, 17.4 us) loses to GMP's
whole mpz op (14.7 us), so no threshold can fix it. At 384 the end-to-end
cell still loses 1.03 despite selecting the best local kernel, so the
remaining deficit includes entry/dispatch overhead. Phase-4 material:
toom3 eval/interp shape at 400-500 limbs, and the mul entry path at the
toom2/toom3 boundary.

The "empty Toom-3 squaring window" [392, 616) is CORRECT as configured:
forced `bn_toom3_sq` loses to `bn_kara_sq` throughout it (392: 10.9 vs
10.4 us; 512: 16.5 vs 8.0). What the crossover actually found was the
opposite mis-tune — kara's ceiling was far too LOW; see commit a36ac29
(BN_SQR_TOOM4_THRESHOLD 616 -> 2560, sqr@704 1.07 -> 0.73).

The fixed-leaf gaps (8-11, 13-14, 18-19, 22-23, 25-32) were initially left
unfilled because the P0.1 matrix had zero red cells there and the projected
gains sat under the +-5% wall-clock floor.  That scheduling decision was
superseded by the exhaustive external-suggestion audit: winning cells do not
exempt a proposal from measurement.  The later controlled A/Bs retained the
measured 12/17/24 and 32/40/48 shapes and rejected the remaining proposed
leaves when their target cells or adjacent controls did not reproduce; see
GROK-14, DEEP-05/06/17/19, and their artifacts in `SUGGESTION_AUDIT.md`.

## Boxed add/sub word-first dispatch — NOT taken (2026-08-04)

Moving the boxed N x 1 test ahead of equal-width add/sub dispatch improved the
intended 2-8-limb add1/sub1 cells by roughly 4-9%.  The complete alternating
9 x 110 ms affected/control matrix did not support retaining it: 23 wins and
21 losses across 44 cells, 1.0023 candidate/baseline geomean, and 11 ordinary
add/sub regressions over 5%.  Production keeps equal-width dispatch first.
Artifact: `baselines/addsub-word-first-3aab316-m5max-20260804.json`.

## BN_BIGINT_HYBRID_CAP default flip — NOT taken (2026-08-02)

**Claimed win (prior session, real workloads):** hybrid (p2<=32 + q32)
measured -32% real RSS on live sets and ~1% faster whole-program.

**Measured loss (this session, 21-op accurate matrix, 110ms/9-run
discipline):** geomean 0.774 -> 0.777, zero losses >= 1.05, but **27
cells regress > 5%** against the power-of-two baseline — including
mul@64 0.827 -> 0.995 (the historical red cell), div@256 +20%,
shl@1024 +23% — vs 21 cells improving > 5%. The flip's acceptance
criteria (no cell regressing > 5%, zero win->loss flips) fail. The
mixed-size capacity trace agrees directionally: power-of-two takes
8.8 ns/request vs hybrid 10.7 (the hybrid pool take pays a first-bucket
size check per hit).

*Caveats:* the hybrid matrix ran under spec-suite load (ratios are
load-robust by design, but the regression tail may be inflated), and the
capacity trace's hit% is pinned at 99.99+ (live_depth defect), so its
allocator-pressure signal is weak. Baselines:
`baselines/matrix-7a96d5c-accurate-20260802.json` (pow2) vs
`baselines/matrix-hybrid3232-accurate-20260802.json`.

**Condition to take it:** the B4 capacity grid (with the live_depth fix)
finds a hybrid point that keeps the op matrix clean, or the campaign's
headline metric moves from the op matrix to whole-program benchmarks (E3)
where hybrid's RSS win is the thing being measured. Both measurements are
one runtime -D flag apart; nothing needs rebuilding to revisit.

## Raw-slot promotion keeps i64 silent-wrap semantics for `+ - *` (pre-existing)

**What:** Untyped block/loop locals whose defining chain is "int-shaped"
(`analysis.w` `int_shaped_node?`) are promoted to raw i64 stack slots for
speed, with explicitly documented silent-wrap semantics. Compiled code then
diverges from the interpreter when such a local overflows i64:

```
(1..1).each -> (k)
  x = 1000000000000 * k
  y = x * x            # compiled: 2003764205206896640 (wrapped)
                       # interpreted: 10^24 (promoted to BigInt)
```

**Win being protected:** raw slots avoid boxing in untyped numeric loops
(the boxing penalty is ~18x; the promotion machinery exists because of it).

**Loss:** engine-parity break for untyped arithmetic that overflows i64
inside inlined iterator blocks / while loops. Silent wrong values, the worst
failure class. `<<` was removed from this machinery on 2026-08-02 (see
below); `+ - *` remain because their wrap point (2^63) is far rarer in
practice than a shift's, and no raw representation exists for a promoted
BigInt in a raw slot.

**Condition to take the fix:** either (a) guarded raw ops with a deopt path
that re-boxes the loop state on first overflow, or (b) accepting the boxing
cost for untyped loops and reserving raw slots for `## i64`-hinted locals
only, with a benchmark showing the regression is confined to code that
should be hinted anyway.

**Related fix that WAS taken (2026-08-02):** shift-left. `1 << 200`
compiled to 0, and `a << 13` inside a block dropped its top limb — a shift
overflows i64 with tiny operands, and `1 << bits` is how BigInts are born,
so `<<` now (1) is not int-shaped (`analysis.w`), (2) folds literal bases
that provably fit i48 and otherwise routes literal-based shifts through the
checked `__w_shl_fast` (`ops.w`), and (3) infers nil (boxed) for a bare
literal base instead of `:i64` (`lowering.w`), mirroring the `**` rule.
Declared `## i64`/`## u64` bases keep the raw machine `shl` and its wrap
contract.

## NEW red rows: the asymmetric (big op small) cells — 2026-08-02

The equal-size matrix never measured the dominant real-loop shape. New
add1/mul1/div1 rows (second operand ONE limb; GMP lane uses its strongest
mpz_*_ui idiom) immediately found:

- **mul1: 3.0-4.8x LOSS at every size >= 16 limbs** — no dedicated N x 1
  scalar-multiply entry (GMP does one addmul_1-shaped pass into a retained
  dest). bn_addmul_1 machinery exists; mul_any needs an N x 1 fast path.
- **div1: 1.29-2.29x LOSS** — same shape vs mpz_tdiv_q_ui's single-pass
  divrem-by-word. bn division-by-limb kernels exist for to_s; div_any
  needs the wiring.
- add1: wins 0.27-0.60 at >= 64 limbs; add1@16 = 1.22 (alloc overhead vs
  in-place add_ui at the size where the copy is cheap but the alloc is
  not).

Together with E3, this decomposes mulchain's 7.8x whole-loop gap: ~4x is
per-op kernel, the remainder allocation-per-pass (E4's half). These rows
are the acceptance meter for the N x 1 kernel work.

**RESOLVED 2026-08-02 same session** (42cfad2, ee6131b, 0858cc4): mul1
1.23-1.27x (bn_mul_1 arm; residual = alloc churn + kernel throughput),
div1 0.42-1.09x (by-limb reciprocal arm + preinv branch fix), add1/sub1
0.80 @16 and 0.27-0.44 above (single-pass N±word kernel). And E4 stage 1
landed: qualifying accumulator loops mutate in place — E3 accumulate
124 -> 11.8 ns/it, whole-loop gap 104x -> 9.8x. Remaining meters: mul1's
~1.24x (kernel work), addchain (needs swap-shape analysis, stage 2).

## B4 capacity grid — RUN AND CLOSED: no hybrid point passes (2026-08-02)

With the live_depth fix giving the recycler real misses (hit% 96-99 at
depths 4/8 instead of the pinned 99.99), the full 48-point (p2, q) grid
x depths {1,4,8} x traces {max=1024, max=4096} against the acceptance
criteria fixed in the plan (>= 20% peak-RSS win, churn within +10%):
**zero points pass.** Best peak win anywhere: 2.8% (p2<=256+q32 @4096
depth 8); at depth 4 most hybrid points have WORSE peak than
power-of-two (the churn working set is dominated by the pool's retained
classes, and pow2's fewer classes retain less). Artifacts:
baselines/b4-grid-{1024,4096}.tsv + b4-base-*.tsv.

Reconciliation with the earlier -32% RSS claim: that was measured on
LIVE-SET workloads (all values held simultaneously — arrays/matrices of
bignums), where per-allocation slack fully exposes and hybrid genuinely
wins. On churn-with-recycler traffic the recycler's retained classes,
not per-value slack, set the peak. Different workload class, both
measurements stand.

**Condition to reopen:** a whole-program benchmark family (E3-style)
weighted toward large live sets of bignums, measured against the same
acceptance discipline. Until then BN_BIGINT_HYBRID_CAP stays opt-in for
liveset-heavy programs, default off.
