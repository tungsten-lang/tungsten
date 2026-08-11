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

A layout-only follow-up kept the original predicate order but moved the N×1
path onto the fall-through edge.  Its first 9×110 ms run suggested a 1.4%
add-only win, but a 15×200 ms replication reversed to a 0.7% loss.  Both the
combined and add-only candidates were removed.  Artifacts:
`baselines/addsub-word-fallthrough-48dffb5-m5max-20260804.json` and
`baselines/add-word-fallthrough-replication-48dffb5-m5max-20260804.json`.

Three follow-ups tested whether constant-sign specialization could retain the
tiny-word gain.  They were screened at 7×80 ms because each failed before the
acceptance-length gate.  Combining early positive-word dispatch with explicit
sign cases measured 0.9969 geomean over 44 add/sub/add1/sub1 cells but had six
regressions over 5%.  Keeping the original order and splitting every add1 sign
case measured 1.0106 over 22 add/add1 cells with five such regressions; limiting
the split to positive 2--8-limb add1 measured 1.0033 with six.  All production
code was removed.  Artifacts:
`baselines/addsub1-positive-word-early-screen-6667a9d-m5max-20260804.json`,
`baselines/add1-sign-split-screen-6667a9d-m5max-20260804.json`, and
`baselines/add1-positive-small-screen-6667a9d-m5max-20260804.json`.

The post-sub1 accurate residual refresh selected all 49 cells that were red in
the last complete fast screen and remeasured them at 9×110 ms.  Seventeen
remained above GMP: add1@2/3; sub1@2/3/4; mul1@4/24/128/256/448/1024/2048/
4096/8192; add@128; isqrt@384; and div1@48.  Several are within timing spread,
so this is a prioritization snapshot rather than the final full-matrix claim.
Artifact: `baselines/matrix-6667a9d-residual-accurate-m5max-20260804.json`.

After restoring every rejected mul1 experiment, a new 485-cell default screen
measured 442 wins.  The accurate follow-up deliberately promoted all 86 cells
at or above 0.95× GMP, including fast-screen wins; 59 remained wins and 27
were at or above parity.  The clearest repeatable gaps were add1@2/3/4
(1.245/1.344/1.303) and sub1@2/3/4 (1.156/1.134/1.213).  Several nonlinear
and wide residuals have relative IQR above 10%, so they remain replication
targets rather than cutoff evidence.  Artifacts:
`baselines/matrix-a5e79a3-screen-m5max-20260804.json` and
`baselines/matrix-a5e79a3-residual095-accurate-m5max-20260804.json`.

After retaining deferred final stores in the wide AArch64 add/sub hybrid, the
next complete 485-cell screen measured 446 wins at 0.625 T/GMP geomean.  Its
acceptance rerun promoted all 71 cells at or above 0.95× GMP rather than only
screen losses: 49 measured wins and 22 measured at or above parity.  The clear
small-word gaps remain add1@2/3/4 (1.319/1.265/1.315), sub1@2/3/4
(1.197/1.136/1.219), and mul1@4/8/24 (1.113/1.062/1.035).  Of ordinary
add/sub, only sub@40 combined a loss with low spread (1.012, relative IQR
0.031); add@128's 1.016 result had 0.180 relative IQR.  Other nonlinear and
wide losses also remain replication targets where their timing spread exceeds
the observed deficit.  Artifacts:
`baselines/matrix-8305ff1-screen-m5max-20260804.json` and
`baselines/matrix-8305ff1-residual095-accurate-m5max-20260804.json`.

After the unsigned-word entries and retained one-limb addition leaf, a fresh
485-cell default screen measured 457 wins, 27 losses, and one tie at a 0.628
Tungsten/GMP geomean.  The acceptance follow-up promoted all 69 cells at or
above 0.95x GMP, including screen wins, and measured 57 wins with twelve
remaining losses: add@128 (1.008), div@4 (1.027), mod@448 (1.003), gcd@2
(1.004), and mul1@24/32/128/256/384/2048/4096/8192
(1.003--1.086).  Add1, sub1, and div1 were all green in the promoted set.
Only add@128 combined a loss with very low relative IQR (0.006); several of
the other rows remain replication targets under the recorded 3.9--4.7 host
load.  Artifacts:
`baselines/matrix-d0ecda6-screen-m5max-20260804.json` and
`baselines/matrix-d0ecda6-residual095-accurate-m5max-20260804.json`.

## 128-limb addition carry-select — RETAINED (2026-08-04)

The low-noise `add@128` residual selected a dedicated eight-way carry-select
leaf.  It computes eight independent 16-limb chains with carry-in zero, then
applies each preceding chunk's carry to the next chunk's first limb.  If that
increment wraps, the rare path replays the exact serial 128-limb kernel;
otherwise the independently computed chunk carry remains valid.

The first 7 x 80 ms screen over add/sub at 13 target and adjacent widths was
slightly noisy: 12/26 wins, 0.995 geomean, and one inactive add64 control over
5%.  The acceptance-grade 9 x 110 ms replication won 19/26 cells at 0.972
geomean with no regression over 5%; add128 improved to 0.659x its serial
fallback and 0.668x GMP.  Every timed sample used the full boxed immutable
operation and public-GMP oracle.  Optimized differential fuzz passed 500000
random cases through 256 limbs plus three deterministic carry/borrow boundary
cases, including the add128 wrap replay; ASAN/UBSAN passed 20000 cases plus
the same boundaries.  Artifacts:
`baselines/add128-carry-select-screen-69086b0-m5max-20260804.json` and
`baselines/add128-carry-select-acceptance-69086b0-m5max-20260804.json`.

## 40-limb subtraction follow-ups — NOT taken (2026-08-04)

The accurate `sub@40` result was only 1.2% behind GMP but had the lowest
relative spread among the remaining ordinary add/sub cells.  A five-second
boxed profile kept 99.6% of sampled events inside the compiler-deduplicated
add/sub lane, so it could not distinguish the inlined allocator/dispatch from
the fixed kernel.  Disassembly confirmed that the selected leaf is the
existing straight-line 40-limb `SBCS` chain.  Artifact:
`baselines/sub-boxed-40-cc14371-m5max-20260804.svg`.

Two causal candidates failed.  Disabling the existing page-offset guard in a
byte-identical binary lost 13/20 add/sub affected and adjacent-control cells,
measured 1.010 geomean, and had three regressions above 5%; `sub@40` itself
became 4.2% slower.  A 16+16+8-limb carry-select prototype then lost every
screen cell, measured 1.077 geomean, and made `sub@40` 10.9% slower.  Both
production candidates were removed.  Artifacts:
`baselines/sub40-page-hazard-causal-cc14371-m5max-20260804.json` and
`baselines/sub40-csel-screen-cc14371-m5max-20260804.json`.

A profile of boxed add1@3 put 56% of sampled branch events in the inlined
Tungsten lane, but symbol deduplication prevented a reliable sub-function
split.  Disassembly exposed one remaining general smallest-fitting capacity
test in the fixed 2--8-limb word route.  Replacing it with an exact
power-of-two hot-class take failed a 16-cell affected/control screen: 12
losses, 1.0232 geomean, and six regressions over 5%.  The extra class selector
cost more than the removed range proof, so the candidate was removed.
Artifacts: `baselines/add1-boxed-3-a5e79a3-m5max-20260804.svg` and
`baselines/addsub1-exact-hot-screen-a5e79a3-m5max-20260804.json`.

## Tiny add/sub destination passing — NOT taken (2026-08-04)

Two byte-identical decomposition runs separated dispatch from result lifetime.
Bypassing the dynamic add1/sub1 dispatcher while retaining immutable pool
handoff improved the ten affected 2--16-limb cells 17.8% by geomean.  Passing
the known-dead previous result directly into the already-decoded word kernels
improved all twelve affected 2--32-limb cells 18.1%; its two inactive one-limb
controls moved -0.6%/+1.0%.  This validates both costs independently rather
than inferring them from the GMP comparison.  Artifacts:
`baselines/addsub1-dispatch-decompose-same-binary-f9ae488-m5max-20260804.json`
and `baselines/addsub1-destination-decompose-f9ae488-m5max-20260804.json`.

The result is an upper bound, not a shippable ABI.  A fail-closed generic
replace wrapper, still selected by a byte-identical runtime toggle, improved
the affected band 12.3% but its guarded binary remained materially slower in
absolute terms and its one-limb fallbacks regressed.  A compact outlined entry
then brought the targeted 2--4-limb GMP ratios down to roughly 1.04--1.07, but
lost overall and regressed inactive/wide controls.  Inlining it won add1 at
three and four limbs, but duplicated the shape test and caused large
one/16/32-limb regressions.  All production prototypes were removed.
Artifacts: `baselines/addsub1-word-replace-screen-f9ae488-m5max-20260804.json`,
`baselines/addsub1-word-dest-outline-screen-f9ae488-m5max-20260804.json`, and
`baselines/addsub1-word-dest-inline-screen-f9ae488-m5max-20260804.json`.

A later production-shaped sub1 prototype rotated two caller-owned result
buffers, preserving the immediately previous immutable result exactly as the
GMP lane's `result[2]` does.  Its fail-closed destination entry consumed a dead
buffer on every path and never mutated the live operand.  The complete
9x110 ms 1..8192-limb band rejected it: seven wins, thirteen losses, 1.0371
candidate/baseline geomean, and seven regressions above 5%.  Forcing the entry
inline to model full-LTO call elimination still screened at 1.0375 geomean
with eleven losses and six regressions above 5%.  The one-limb cell improved
in the acceptance run, but only to 1.004x GMP, so neither prototype remained.
Artifacts: `baselines/sub1-dest-rotation-66e409f-m5max-20260804.json` and
`baselines/sub1-dest-rotation-inline-screen-66e409f-m5max-20260804.json`.

**Condition to take it:** make the existing add/sub dispatcher accept an
optional dead destination after its single shape decode, or prove/hoist the
shape in compiler IR.  A second guard tree in the hot loop spends the measured
reuse win before arithmetic starts.

The condition was met on 2026-08-10 by moving the proof into the compiler
(E4 stage 3).  Lowering's mut-candidate walker gained a word-overwrite arm:
`r = a + w` / `r = a - w` / `r = a * w` over a dominating literal seed keeps
r's candidacy, and the assignment lowers to `w_bigint_{add,sub,mul}_word_dest`
with r's dying OLD value as the destination.  All guards sit inside the new
entries after the shape decode — the generic entries carry no new branch, so
the ordinary boxed lanes are untouched (the post-change 485-cell screen
measured 458 wins at 0.636 geomean, unchanged).  Compiled word loops
(`run_program_loops.sh` wordadd/wordsub/wordmul/wordchain at 2/4/32 limbs)
improved 5-6x against the byte-identical TUNGSTEN_BIGINT_DEST_OPS=0 control
— the previous emission leaked the dying result outright — and the 32-limb
add/sub/chain lanes now beat the retained-destination GMP twin (0.61-0.67).
The remaining 1.6-1.8x at 2-4 limbs is fixed loop machinery around a ~2.5 ns
op, not the entry.  Page-offset hazards reuse bigint_mul_n1's >= 32-limb
rehome-and-settle policy: a plain refusal is NOT self-healing for this shape,
because the released destination becomes the hot slot and returns as the very
next allocation (measured: wordadd2 stuck at 7.0 ns in permanent fallback
versus 2.5 ns rehomed).

## Native unsigned-word entries — RETAINED (2026-08-04)

The documented `add1`, `sub1`, `mul1`, and `div1` rows were asymmetric at the
API boundary: GMP hoisted the one-limb operand and called `mpz_*_ui`, while
Tungsten passed the same value as a boxed BigInt through its generic
boxed/boxed dispatcher.  Tungsten now has matching decoded unsigned-word
entries.  Their positive boxed leaves retain the existing fixed arithmetic
kernels and recycler; signed/overlay and inline inputs take a complete
semantics-preserving fallback inside the same entry.

Across the complete 1..8192-limb word matrix, the final candidate won 68/80
cells at 0.9381 candidate/baseline geomean with no regression above 5%.
Add1/sub1 each won 18/20 cells, while mul1/div1 each won 16/20.  The former
add1@2/3/4 losses became 0.840/0.837/0.907× GMP and sub1@2/3/4 became
0.908/0.946/0.980×.  A focused 15×250 ms follow-up found that the initial
mul1@1 regression came from missing its direct positive 1×1 leaf; adding that
leaf made the cell 18.6% faster than the generic Tungsten path and 34.0%
faster than GMP, with all four controls improved.

This is not a claim that the residual matrix is complete.  In the final run,
add1@1 and sub1@1 were 1.002/1.042× GMP, and mul1 retained losses at
32/128/256/384/448/512/1024/2048/4096/8192 limbs (1.004--1.063×).
Artifacts:
`baselines/tungsten-word-api-final-52e11bf-m5max-20260804.json` and
`baselines/tungsten-word-api-regression-check-52e11bf-m5max-20260804.json`
and
`baselines/tungsten-word-api-mul11-direct-52e11bf-m5max-20260804.json`.

The result required full boxed evidence rather than assuming that less
dispatch must win.  An unchecked known-owned result release was neutral
overall and caused four >5% regressions.  Moving the word test ahead of the
equal-width dispatcher improved the target but regressed equal add/sub by up
to 33%.  Inlining the eight-limb multiply kernel closed its target but caused
eight >5% control regressions; publishing carry/size inside the leaf and
outlining the wide sub1 copy also lost overall.  All of those candidate source
paths were removed.  Artifacts:
`baselines/owned-result-release-52e11bf-m5max-20260804.json`,
`baselines/addsub1-word-early-52e11bf-m5max-20260804.json`,
`baselines/mul1-f8-boxed-inline-52e11bf-m5max-20260804.json`,
`baselines/mul1-f8-publish-size-52e11bf-m5max-20260804.json`, and
`baselines/word-ui-wide-outline-52e11bf-m5max-20260804.json`.

Optimized public-GMP differential fuzz passed 100,000 signed/overlay cases
through 1024 limbs, including 0/1, i48, high-bit, and `UINT64_MAX` words for
all four operations.  ASAN/UBSAN passed 10,000 cases through 128 limbs.

A later byte-identical 15×250 ms replication confirmed that the remaining
one-limb add/sub results were real, though small: add1@1 was 1.013× GMP and
sub1@1 was 1.035×.  Four attempts to put a positive one-limb leaf before the
wide add/sub return were rejected: two inline predicate layouts, a cold
inline block, and an outlined helper either produced three to ten >5% control
regressions or made the target slower.  Reusing the already-decoded receiver
on the fallback edge was neutral overall and produced eight >5% regressions.
Artifacts:
`baselines/addsub1-one-limb-current-replication-4dbb251-m5max-20260804.json`,
`baselines/addsub1-positive11-screen-4dbb251-m5max-20260804.json`,
`baselines/addsub1-positive11-onecmp-screen-4dbb251-m5max-20260804.json`,
`baselines/addsub1-positive11-cold-screen-4dbb251-m5max-20260804.json`,
`baselines/addsub1-positive11-outline-screen-4dbb251-m5max-20260804.json`, and
`baselines/addsub1-reuse-decode-screen-4dbb251-m5max-20260804.json`.

Putting the leaf after the existing `n >= 2` return finally preserved the
wide add1 path.  Its isolated 9×110 ms acceptance won 11/20 cells at 0.9781
geomean with no >5% regression; add1@1 improved 19.4% and became 0.840× GMP,
leaving every add1 width green.  The same placement was not safe for sub1:
the combined acceptance regressed sub1@384/448 by 9.1%/8.4%, and an isolated
sub1 screen lost 11/20 cells at 1.0100 geomean with three >5% regressions.
Only the add leaf remains in production.  Artifacts:
`baselines/addsub1-positive11-after-screen-4dbb251-m5max-20260804.json`,
`baselines/addsub1-positive11-after-acceptance-4dbb251-m5max-20260804.json`,
`baselines/add1-positive11-after-acceptance-4dbb251-m5max-20260804.json`, and
`baselines/sub1-positive11-after-isolated-screen-4dbb251-m5max-20260804.json`.

A five-second `tungsten flame` run at boxed `sub1@1` found that Clang had
inlined the entire arithmetic path into `bench_lane_sub1`; there was no
remaining helper frame to tune independently.  A compact positive 1x1 leaf
improved that cell to 0.936x GMP, but lost 13/20 sub1 widths at 1.0048
geomean with six regressions above 5%.  Outlining the uncommon signed/overlay
fallback while retaining the direct leaf initially looked better across an
80-cell sub1/add1/sub/add screen, but binary inspection showed that unrelated
lane addresses moved by 640 bytes and the nominally inactive controls supplied
most of the 3.5% aggregate win.  Moving the helper to the compiler's cold
region kept `sub1@1` at 0.894x its baseline and 0.924x GMP, but the complete
screen became neutral at 0.9998 geomean, split 43 wins/37 losses, and had ten
regressions above 5%; sub1 itself lost 11/20 cells at 1.0147 geomean.  All
source candidates were removed.  Artifacts:
`baselines/sub1-boxed-1-dc4e7fc-m5max-20260804.svg`,
`baselines/sub1-positive11-compact-screen-66e409f-m5max-20260804.json`,
`baselines/sub1-outline-fallback-screen-dc4e7fc-m5max-20260804.json`, and
`baselines/sub1-cold-fallback-screen-dc4e7fc-m5max-20260804.json`.

## One-word and terminal GCD schedules — NOT taken (2026-08-04)

A five-second boxed `lcm@1` flame profile put 59% of sampled branch events in
the Tungsten LCM lane.  Disassembly localized its arithmetic work to the
inlined one-word binary-GCD loop before result allocation.  Artifact:
`baselines/lcm-boxed-1-eaafe25-m5max-20260804.svg`.

Replacing that loop with straight Euclid lost 7.6% by geomean across ten
`gcd`/`lcm` cells at 1--16 limbs and produced three regressions above 5%.
Changing only the multi-limb terminal-word GCD to Euclid lost 2.5% across
twelve cells at 128--4096 limbs, with ten losses and an 11.3% regression at
`gcd@4096`.  A branchy Stein loop was effectively neutral at 1.005x overall,
but made the targeted `gcd@1` cell 2.8% slower and `lcm@2` 5.6% slower.

Two hybrid binary/Euclid schedules used a magnitude-ratio gate before paying
for hardware division.  Shift gates of two and three lost 21.9% and 21.2% by
geomean respectively; both made `gcd@1` about 42--45% slower and `lcm@1`
about 53--57% slower.  These short screens are rejection evidence, not
acceptance-length measurements.  All candidates were removed.  Artifacts:
`baselines/gcd-u64-euclid-screen-eaafe25-m5max-20260804.json`,
`baselines/gcd-terminal-euclid-screen-eaafe25-m5max-20260804.json`,
`baselines/gcd-u64-branchy-screen-eaafe25-m5max-20260804.json`,
`baselines/gcd-u64-hybrid2-screen-eaafe25-m5max-20260804.json`, and
`baselines/gcd-u64-hybrid3-screen-eaafe25-m5max-20260804.json`.

## Wide NEON add/sub cadence — NOT taken (2026-08-04)

A five-second boxed `sub@8192` profile put 50.1% of sampled branch events in
`bn_hyb_sub_pass1` and 49.5% in `bn_hyb_round`; cache/TLB event views had the
same split.  The ordinary boxed residual is therefore the two-pass hybrid
itself, not allocator or generic dispatch overhead.  Artifact:
`baselines/sub-boxed-8192-28be5b6-m5max-20260804.svg`.

Nine short screens swept the scalar A phase through 32/40/48/56/64 limbs and
the middle scalar C share through 25/40/50/60/75 percent at 2048--16384 limbs,
covering add and subtract together.  A=40/C=25 looked best in the screen: all
eight cells won at a 0.905 candidate/baseline geomean.  That result did not
survive the required affected-band run.  At 9x110 ms over 26 cells from 288
through 65536 limbs, it lost 16 cells, regressed three above 5%, and measured
1.014 overall; add/sub at 4096 regressed 11.0%/8.8%.  A selector limiting
A=40 to 6144--12288 limbs then lost 7/10 boundary cells at 1.025 geomean.
All cadence candidates were removed.

A byte-identical runtime-toggle control also extended the existing 4 KiB
destination rehoming predicate through 16384 limbs.  It was neutral overall
(0.997 geomean), split 6/4, and made the target `sub@8192` cell 6.7% slower;
wide rehoming was rejected independently of cadence.  Artifact:
`baselines/addsub-wide-page-rehome-screen-28be5b6-m5max-20260804.json`.

Artifacts: `baselines/addsub-hyb-a32-c50-screen-28be5b6-m5max-20260804.json`,
`baselines/addsub-hyb-a40-c50-screen-28be5b6-m5max-20260804.json`,
`baselines/addsub-hyb-a56-c50-screen-28be5b6-m5max-20260804.json`,
`baselines/addsub-hyb-a64-c50-screen-28be5b6-m5max-20260804.json`,
`baselines/addsub-hyb-a48-c25-screen-28be5b6-m5max-20260804.json`,
`baselines/addsub-hyb-a48-c75-screen-28be5b6-m5max-20260804.json`,
`baselines/addsub-hyb-a40-c25-screen-28be5b6-m5max-20260804.json`,
`baselines/addsub-hyb-a40-c40-screen-28be5b6-m5max-20260804.json`,
`baselines/addsub-hyb-a40-c60-screen-28be5b6-m5max-20260804.json`,
`baselines/addsub-hyb-a40-c25-acceptance-28be5b6-m5max-20260804.json`, and
`baselines/addsub-hyb-mid-a40-screen-28be5b6-m5max-20260804.json`.

**Condition to revisit:** change pass-1 mask construction or eliminate a
result reread in pass 2.  Repartitioning the existing scalar/NEON phases only
moves the same bandwidth and carry-resolution work between width-specific
local optima.

The result-reread condition was subsequently met without changing the cadence.
Pass 1 now computes only generate/propagate masks; pass 2 rereads the two input
streams, reconstructs the provisional sum/difference, applies the resolved
carry mask, and writes the destination once.  The 9x110 ms boxed acceptance
run improved 19/24 add/sub cells from 288 through 65536 limbs, measured 0.957
candidate/baseline geomean, and had no regression above 5%.  The five slower
cells were 0.5--4.6% regressions.  Public-GMP differential fuzz passed 2000
random signed cases through 65536 limbs plus carry/borrow boundaries; an
ASAN/UBSAN build passed 500 cases through 8192 limbs.  Artifacts:
`baselines/addsub-hyb-deferred-store-screen-083526d-m5max-20260804.json` and
`baselines/addsub-hyb-deferred-store-acceptance-083526d-m5max-20260804.json`.

## Mul1 wide dispatch and page rehoming — NOT taken (2026-08-04)

Routing widths above 64 ahead of the fixed-width ladder initially measured a
2.6% full-band win, then reversed to a 1.2% loss with three >5% regressions in
the 15×200 ms replication.  The candidate was removed.  Artifacts:
`baselines/mul1-wide-early-48dffb5-m5max-20260804.json` and
`baselines/mul1-wide-early-replication-48dffb5-m5max-20260804.json`.

The first same-binary mul1 page-hazard experiment was not causal: its runtime
toggle did not reach the add/sub-style predicate used by generic N×1
multiplication.  The corrected toggle now covers both predicate families.
Corrected runs still showed 2.4-4.8% movement in inactive fixed-width controls,
so no sub-2% toggle effect was accepted.  A compile-time removal then made the
actually affected 128..8192 band 0.8% slower and regressed 2048 limbs 6.1%; it
was removed.  Artifacts: `baselines/mul1-page-hazard-causal-48dffb5-m5max-20260804.json`,
`baselines/mul1-page-hazard-causal-replication-48dffb5-m5max-20260804.json`,
and `baselines/mul1-no-page-rehome-48dffb5-m5max-20260804.json`.

## Mul1 carry scheduling and wrapper inlining — NOT taken (2026-08-04)

A five-second `tungsten flame` run at boxed mul1@256 attributed 64% of sampled
branch events to `bn_mul_1`, 3.2% to `bigint_mul_n1`, and 2.0% to TLS address
resolution.  Raw `bn_mul_1` measurements were approximately at public
`mpn_mul_1` parity, while the full boxed lane retained the larger gap.
Artifact: `baselines/mul1-boxed-256-3001650-m5max-20260804.svg`.

Four complete 20-width kernel experiments did not create a safe margin.  A
globally earlier carry schedule measured 0.9991 geomean but had three >5%
regressions; selecting it only around 128--512 limbs measured 1.0082.  A
compact four-limb streaming loop measured 1.0040, and a pair-pipelined
four-limb loop measured 1.0071 with one >5% regression.  Artifacts:
`baselines/mul1-a64-early-carry-3001650-m5max-20260804.json`,
`baselines/mul1-a64-early-carry-band-3001650-m5max-20260804.json`,
`baselines/mul1-a64-stream4-3001650-m5max-20260804.json`, and
`baselines/mul1-a64-pair-pipeline-3001650-m5max-20260804.json`.

Inlining the dynamic boxed wrapper improved every affected width in its short
screen, but the required 15×200 ms full-band replication reversed to 1.0104
geomean with two >5% small-control regressions.  It was removed along with all
kernel candidates.  Artifacts:
`baselines/mul1-inline-wrapper-screen-3001650-m5max-20260804.json` and
`baselines/mul1-inline-wrapper-replication-3001650-m5max-20260804.json`.

After the decoded unsigned-word entry removed most dispatcher overhead, a new
five-second boxed `mul1@128` profile assigned 87.4% of sampled branch events to
`bn_mul_1`, 6.8% to the lane, 4.4% to its wrapper, and 0.8% to TLS resolution.
Raw checks put the kernel itself at 0.98--1.05× public `mpn_mul_1` from 32
through 8192 limbs, with the clearest loss at 4096.  Explicit 256-byte source
and destination prefetches were then tested over all 20 boxed widths.  Every
actually affected width from 128 through 8192 lost, including 2.1% at 4096;
the apparent 1.0% all-cell geomean win came entirely from inactive small-width
layout movement.  The prefetch source was removed.  Artifacts:
`baselines/mul1-boxed-128-6767146-m5max-20260804.svg` and
`baselines/mul1-a64-prefetch256-screen-6767146-m5max-20260804.json`.

Doubling the proven eight-limb rolling-carry body without changing its inner
schedule saved one loop-control pair per 16 limbs.  A 7×80 ms complete-width
screen suggested 17/20 wins at 0.9927 geomean with no >5% regression, but the
required 9×110 ms replication reversed to 7/20 wins at 1.0121 geomean and
regressed 64/128 limbs by more than 5%.  The 16-limb outer unroll was removed.
Artifacts:
`baselines/mul1-a64-unroll16-screen-4dbb251-m5max-20260804.json` and
`baselines/mul1-a64-unroll16-acceptance-4dbb251-m5max-20260804.json`.

A later loaded-host audit first ran the byte-identical current binary through
both A/B lanes for 15x200 ms.  The nominal B/A result was still 1.0220
geomean with four false regressions above 5% while unrelated CPU jobs raised
load average from 4.69 to 6.56.  That artifact is retained as a noise bound,
not a performance baseline:
`baselines/mul1-current-replication-78e0403-m5max-20260804.json`.

Two causal screens remained useful under the same load.  Replacing only the
generic 128+ limb Tungsten kernel with public `mpn_mul_1`, while retaining
Tungsten allocation, boxing, and publication, improved seven of nine affected
widths at a 0.9796 affected-band geomean.  Nevertheless every resulting boxed
128..8192-limb cell measured at or above the complete GMP operation
(1.0004x--1.0611x), so a kernel port alone cannot close this lane.  A native
fixed 128-limb entry then bypassed the generic wrapper, inactive fixed-width
comparisons, and dynamic rehome decision.  It improved the target only 0.6%,
lost 15/20 complete-band controls, and measured 1.0118 geomean.  Both controls
were removed.  Artifacts:
`baselines/mul1-public-kernel-upper-bound-screen-78e0403-m5max-20260804.json`
and `baselines/mul1-fixed128-entry-screen-78e0403-m5max-20260804.json`.

A direct-destination upper bound then rotated two already-proven-dead result
buffers for 128+ limbs, preserving the immediately previous immutable result
while removing recycler return/take and generic publication work.  The first
screen incorrectly selected the destination path inside the timed lane and
therefore charged inactive 1..64-limb controls an extra width branch; it is
retained only as diagnosis:
`baselines/mul1-dest-upper-screen-b81d43a-m5max-20260804.json`.

The corrected harness kept the ordinary small lane byte-identical and selected
the separately aligned destination lane once outside timing.  Its acceptance
run improved six of nine affected 128..8192 widths at a 0.9845 geomean, but
left six boxed cells above GMP and regressed 8192 limbs 5.8%; this is real
lifecycle headroom, not a shippable win.  Combining the same direct buffers
with public `mpn_mul_1` was neutral at 0.9984 over the affected band and still
left eight of nine cells above the complete GMP operation.  The loaded-host
screens do not support another kernel clone or a benchmark-only destination
path; production remains unchanged.  Artifacts:
`baselines/mul1-dest-upper-acceptance-b81d43a-m5max-20260804.json` and
`baselines/mul1-dest-public-upper-screen-b81d43a-m5max-20260804.json`.

Replacing the four-entry TLS settled-placement table with an unordered
low-page operand key stored in the existing BigInt header padding was also
rejected.  The experiment covered every consumer of the shared placement
predicate, including already-green controls: add, sub, mul1, and/or/xor at
fourteen widths from 24 through 8192 limbs.  The 7x80 ms screen split 35 wins
and 49 losses at a 1.0096 candidate/baseline geomean with fourteen regressions
above 5%.  Mul1 itself lost 9/14 cells at 1.0027 geomean, while the already
green sub, and, and xor families regressed 3.6%, 2.0%, and 3.1% by geomean.
The source candidate was removed without escalating it to an acceptance run.
Artifact:
`baselines/inline-placement-key-screen-bb153db-m5max-20260804.json`.

## Mul1 128-limb carry-select blocks — RETAINED (2026-08-04)

The retained AArch64 path processes exact multiples of 128 limbs as eight
independent seeded 16-limb multiplication chains per block.  Each chain
returns its final product high word and the one-bit addition carry.  Once all
eight chains finish, the caller adds each preceding carry bit to the next
chunk's first result limb.  A correction wrap is the only case that can alter
the rest of that chunk, so it replays the exact seeded serial 128-limb block.

Immediately before this change, the add128-retaining tree's complete screen
measured 457/485 wins and its 9 x 110 ms promotion left thirteen losses, ten
of them mul1 widths.  Artifacts:
`baselines/matrix-42ffc87-screen-m5max-20260804.json` and
`baselines/matrix-42ffc87-residual095-accurate-m5max-20260804.json`.

An initial 7 x 80 ms complete-width screen included 128 limbs and suggested a
7.5% mul1-band win.  The first 9 x 110 ms replication confirmed the aggregate
gain but made 128 itself 2.1% slower with spread larger than the effect, so the
production selector begins at 256 limbs.  A byte-identical runtime-selector
acceptance then won every changed 256/384/512/1024/2048/4096/8192 cell by
13--20%, measured 0.933 geomean over all twenty mul1 controls, and had no
regression over 5%.  The final compile-time production A/B again won every
changed width by 5--24%, measured 0.933 full-band geomean, and had no >5%
regression.  All changed complete boxed cells measured faster than GMP.

The post-change 485-cell fast matrix measured 458 wins at 0.617 geomean.  Its
9 x 110 ms follow-up promoted all seventy cells at or above 0.95x GMP,
including screen wins, and measured 64 wins with six remaining losses:
div@4, gcd@2048, isqrt@384, sub1@1, mul1@128, and mul1@448.  At that point the
selector deliberately left the last two shapes on the prior rolling kernel.

A narrow follow-up composed three retained 128-limb blocks with a four-chain
64-limb tail for the exact 448-limb shape.  The 7 x 80 ms screen improved the
target 21.7% to 0.792x GMP with no >5% control regression.  Its 9 x 110 ms
acceptance replication improved the target 19.6% to 0.823x GMP; the complete
twenty-width mul1 band measured 0.992 candidate/baseline geomean and again had
no >5% regression.  This closes the measured 448-limb loss while leaving the
lower-overhead rolling kernel selected at 128 limbs.  Artifacts:
`baselines/mul1-csel448-screen-2779b76-m5max-20260804.json` and
`baselines/mul1-csel448-acceptance-2779b76-m5max-20260804.json`.

The remaining exact-128 loss needed less setup, not shorter carry chains.  A
four-by-32-limb carry-select leaf improved the target 14.0% to 0.918x GMP in
its 7 x 80 ms screen.  The production-shaped 9 x 110 ms A/B retained a 13.0%
target win but moved one unchanged 448-limb control 5.3%, so it was not used
alone for acceptance.  A byte-identical runtime-selector replication removed
that placement ambiguity: exact 128 improved 13.5% to 0.913x GMP, 17/20 mul1
controls won at 0.971 geomean, and none regressed over 5%.  Every documented
mul1 cell in that final artifact is faster than GMP.  Artifacts:
`baselines/mul1-csel128x32-screen-0ceddc3-m5max-20260804.json`,
`baselines/mul1-csel128x32-acceptance-0ceddc3-m5max-20260804.json`, and
`baselines/mul1-csel128x32-same-binary-0ceddc3-m5max-20260804.json`.

Every timed sample checked the full boxed result against public GMP.  The
expanded randomized checker passed 100000 optimized cases and 20000
ASAN/UBSAN cases through 1024 limbs across both operand orders and sign
encodings.  Constructed v=2^64-1 cases force the boundary correction to wrap
in the exact-128 32-limb chain, a complete 16-limb-chain block, and the
448-limb tail, exercising every serial replay.  Artifacts:
`baselines/mul1-csel128-screen-42ffc87-m5max-20260804.json`,
`baselines/mul1-csel128-acceptance-42ffc87-m5max-20260804.json`,
`baselines/mul1-csel128-same-binary-42ffc87-m5max-20260804.json`,
`baselines/mul1-csel128-production-42ffc87-m5max-20260804.json`,
`baselines/matrix-mul1csel-screen-42ffc87-m5max-20260804.json`, and
`baselines/matrix-mul1csel-residual095-accurate-42ffc87-m5max-20260804.json`.

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

## Residual isqrt384 and gcd2048 follow-ups — NOT taken (2026-08-04)

Acceptance-grade residual measurements left isqrt384 roughly 2.3% and
gcd2048 roughly 4.0% behind public GMP, with materially wider IQRs than the
small linear lanes. Full boxed profiles ruled out result allocation as the
dominant isqrt cost and ruled out worker creation as the GCD cost: isqrt was
concentrated in B-Z base-division addmul/submul arithmetic, while three GCD
workers slept for about 97% of their samples and the caller retained the
HGCD/Lehmer work. Residual artifacts:
`baselines/residual-four-bf00da8-accurate-m5max-20260804.json` and
`baselines/residual-two-bf00da8-15x200-m5max-20260804.json`.

Raising the approximate-quotient admission from 193 to 194 first made the
target 1.7% slower. The approximate-divisor alignment was then swept at fixed
2/4/16 limbs against the retained dynamic 8-limb policy across 256..1024.
None passed: 2 and 4 lost their matrices, while 16 was neutral overall but
made the target 8.4% slower. A fixed 23-limb submul leaf then improved
isqrt384 in a short screen but reversed to a 2.2% loss in the 9 x 110 ms
acceptance band. The candidate was removed. Artifacts:
`baselines/isqrt-divappr-min194-screen-bf00da8-m5max-20260804.json`,
`baselines/isqrt-pad2-screen-bf00da8-m5max-20260804.json`,
`baselines/isqrt-pad4-screen-bf00da8-m5max-20260804.json`,
`baselines/isqrt-pad16-screen-bf00da8-m5max-20260804.json`, and
`baselines/isqrt-submul23-acceptance-bf00da8-m5max-20260804.json`.

A temporary recurrence trace then replaced the single-row guess with the
actual `384 -> 192 -> 96 -> 48 -> 24 -> 12 -> 6 -> 3` root chain.  Each root
iteration reaches seven 50-by-25 and five 48-by-24 Knuth leaves.  Deferring
the leaf's initial quotient/remainder zeroing until an unwritten tail needed
it was tested across boxed isqrt/div/mod at 24..512 limbs, including the
already-green shared users.  It split 17 wins and 16 losses at 1.0028x
candidate/baseline geomean and caused two regressions above 5%, so the change
was removed.  Artifact:
`baselines/bz-defer-output-zero-screen-d3f83b9-m5max-20260804.json`.

For GCD, moving parallel row application above 2048 made the target 5.9%
slower. The current four-step row-serial linear-combination kernel also beat
both the existing interleaved schedule (10/12 losses, 1.028 geomean) and a
smaller two-step serial loop (9/12 losses, 1.007 geomean). Scalar HGCD retry
geometry was then filled in rather than inferred: denominators 4, 5, 6, and 7
all failed against current 8. A capacity-gated denominator-5 screen looked
strong, but its acceptance replication reversed to 1.005 geomean, three
regressions over 5%, and a 2.1% target loss. All selectors were removed.
Artifacts:
`baselines/gcd-par-min2049-screen-bf00da8-m5max-20260804.json`,
`baselines/gcd-den8-min2049-screen-bf00da8-m5max-20260804.json`,
`baselines/gcd-row-interleaved-screen-bf00da8-m5max-20260804.json`,
`baselines/gcd-row-serial-unroll2-screen-bf00da8-m5max-20260804.json`,
`baselines/gcd-exact2048-den5-screen-bf00da8-m5max-20260804.json`,
`baselines/gcd-exact2048-den6-screen-bf00da8-m5max-20260804.json`,
`baselines/gcd-exact2048-den7-screen-bf00da8-m5max-20260804.json`, and
`baselines/gcd-cap2048-den5-acceptance-bf00da8-m5max-20260804.json`.

## Exact 480-limb serial Toom-2 recursion — REMOVED (2026-08-04)

The boxed `mod@448` profile made the fixed 15-limb addmul leaf look like a
candidate bottleneck, but replacing the 15- or 21-limb fixed rows with the
generic row lost 25/40 and 27/40 cells. A cross-block 15-limb schedule lost
22/40, and routing the fixed 12-limb row through the generic block kernel lost
32/45. These screens covered their complete `mod`/`div`/`mul`/`sqr`/
`fromstr`/`isqrt` bands, including green controls, so none of those leaf
changes was retained. Artifacts:
`baselines/addmul-f15-fixed-row-screen-11eb818-m5max-20260804.json`,
`baselines/addmul-f21-fixed-row-screen-11eb818-m5max-20260804.json`,
`baselines/addmul-f15-cross-screen-11eb818-m5max-20260804.json`, and
`baselines/addmul-f12-generic-screen-11eb818-m5max-20260804.json`.

The higher-level exact-480 dispatch was different: its fixed recursion ran
the three 240-limb products serially, while the generic difference-form path
qualified for the existing parallel product scheduler. A byte-identical
runtime-knob replication over the six reached cells plus six inactive controls
measured generic/fixed at 0.961 geomean, with no regression above 5%; boxed
`mul@480` improved to 0.601x its fixed baseline. The production 15 x 200 ms
matrix then put all 12 `mod`/`div`/`mul`/`fromstr` cells at 480/960/1024 limbs
ahead of public GMP, at 0.708 geomean. The fixed 480 selector is therefore off
by default; its benchmark knob remains for causal replication. Artifacts:
`baselines/toom480-runtime-knob-replication-11eb818-m5max-20260804.json` and
`baselines/toom480-production-15x200-11eb818-m5max-20260804.json`.

Optimized GMP differential fuzz passed 10,000 exact 480-limb products and
5,000 random products through 1024 limbs. ASAN/UBSAN passed 1,000 exact and
1,000 random products. The benchmark exposes `--fuzz-mul-exact` so future
fixed-width cutoff changes can be validated directly.

## Cached-remainder 28-limb child selection — TAKEN (2026-08-04)

The `mod@448` flamegraph's fixed 15-limb row was not reached through one of
the named fixed Toom trees. A recursion-width trace instead found repeated
`bn_toom2_sum(28)` calls under 448/449, 224/225, 112/113, 56/57, and 28/29
difference-form parents. The width-28 sum form creates a 15-limb third child.
Globally removing the measured width-28 difference-form exclusion improved
the target but was neutral over 30 affected/control cells (1.00008 geomean),
so that broad candidate was rejected:
`baselines/toom2-diff28-screen-7fdd96e-m5max-20260804.json`.

The retained change supplies the difference-form hint only while cached
remainder division computes its two Barrett products; direct 28-limb products
keep their faster sum form. A byte-identical 15 x 200 ms replication over six
mod widths and twelve div/mul controls won 14/18 cells at 0.995 geomean with
no regression above 5%; the six mod cells improved 0.9% by geomean. The final
production pass put `mod@448` at 0.99x GMP, and the focused residual
replication measured it at 0.97x. Artifacts:
`baselines/div-recip-diff28-context-screen-7fdd96e-m5max-20260804.json`,
`baselines/div-recip-diff28-context-replication-7fdd96e-m5max-20260804.json`,
`baselines/div-recip-diff28-production-15x200-7fdd96e-m5max-20260804.json`,
and `baselines/residual-three-diff28-15x200-7fdd96e-m5max-20260804.json`.

Cached-reciprocal GMP differential fuzz passed 25,000 optimized cases at
112/224/448/512 divisor limbs, including 10,000 at the target width.
ASAN/UBSAN passed another 3,000 cases at 112/448/512. The same residual pass
measured `sub1@1` at 0.98x GMP; `isqrt@384` remained the sole red cell in that
nine-cell replication at 1.02x.

## Tiny word-subtraction outlining -- NOT taken (2026-08-04)

The one-limb `sub1` residual was tested as part of a complete 80-cell
`add1`/`sub1`/`add`/`sub` screen over all twenty default widths, rather than
only at the losing cell.  Outlining `bigint_sub_ui_any` lost 42/80 cells at a
1.017 candidate/baseline geomean and produced twelve regressions above 5%.
At `sub1@1` it was 1.256x the current inline implementation and still 1.235x
public GMP.  The outline was removed.  Artifact:
`baselines/sub-ui-noinline-screen-a0d3984-m5max-20260804.json`.

## Fixed 8-by-4-limb remainder -- TAKEN (2026-08-04)

The `mod@4` boxed fixture is an 8-limb dividend modulo a 4-limb divisor.  Its
cached Barrett path performs two products after the cache lookup; a fixed
remainder leaf instead keeps the normalized high remainder pair in registers,
uses five 3-by-2 reciprocal quotient estimates, and subtracts only the lower
two divisor limbs around each estimate.  The fixed leaf without a reciprocal
cache was only a 3.1% target win in its byte-identical 15 x 200 ms replication
and remained 1.019x GMP, so that incomplete form was not enabled.

The starting 15 x 200 ms refresh measured every one of the 68 cells selected
at 0.95x GMP or slower from the current default screen: 63 won and five lost.
A 21 x 300 ms replication of those five left `mod@4`, `isqrt@384`, and
`sub1@1` red, while `mod@448` and `gcd@2048` moved just below parity.
Artifacts: `baselines/matrix-a0d3984-residual095-15x200-m5max-20260804.json`
and `baselines/residual-five-a0d3984-21x300-m5max-20260804.json`.

Caching the normalized two-limb preinverse changed the result.  A
byte-identical runtime-knob replication over `mod`/`div` at
3/4/5/8/16/24 limbs measured `mod@4` at 0.747x the prior path and 0.816x GMP;
the twelve-cell geomean was 0.982 with no regression above 5%.  Two cache
entries were also measured directly instead of assuming one repeated divisor:
they were neutral-to-positive for a stable divisor (0.994x one entry) and
0.784x one entry when the normalized divisor pair alternated every operation.
The alternating experiment used the same binary for both cache policies.
Artifacts:
`baselines/mod84-direct-screen-a0d3984-m5max-20260804.json`,
`baselines/mod84-runtime-knob-replication-a0d3984-m5max-20260804.json`,
`baselines/mod84-preinv-runtime-knob-a0d3984-m5max-20260804.json`,
`baselines/mod84-preinv-cache-entries-stable-a0d3984-m5max-20260804.json`,
`baselines/mod84-preinv-cache-entries-alternating-a0d3984-m5max-20260804.json`,
and `baselines/mod84-two-entry-runtime-knob-a0d3984-m5max-20260804.json`.

Optimized public-GMP differential checks passed 200,000 mixed multi-limb
div/mod cases through sixteen divisor limbs and 200,000 repeated/replaced
four-limb reciprocal cases.  ASAN/UBSAN passed another 100,000 cases in each
family.  The final 21 x 300 ms boxed residual refresh measured `mod@4` at
0.808x GMP, down from 1.025x, while also rechecking all four neighboring
frontier cells.  `mod@448` measured 0.999x; `gcd@2048`, `isqrt@384`, and
`sub1@1` measured 1.003x, 1.020x, and 1.017x respectively, but all three had
relative IQR above 10%.  Artifact:
`baselines/residual-five-mod84-production-21x300-m5max-20260804.json`.

## Caller-provided triangular isqrt quotient -- NOT taken (2026-08-04)

The exact top-level square-root quotient at 8..256 result limbs was tested
with a caller-provided destination, removing its temporary BigInt allocation,
copy, and recycle.  This deliberately covered already-green cells: the
`isqrt@384` residual uses the approximate B-Z branch and is not affected.
A byte-identical 9 x 110 ms screen won all nine affected isqrt cells at a
0.985 geomean, and a 15 x 200 ms replication again won all nine at 0.980.
However, the final current-source 9 x 110 ms replication reversed to only
4/9 affected wins at a 1.002 geomean; `isqrt@16` regressed 6.8%.  Across the
thirteen affected/control cells it lost 7/13.  The destination ABI and its
runtime knob were removed.  Artifacts:
`baselines/sqrt-triangular-destination-screen-6ab814b-m5max-20260804.json`,
`baselines/sqrt-triangular-destination-replication-6ab814b-m5max-20260804.json`,
and `baselines/sqrt-triangular-destination-final-6ab814b-m5max-20260804.json`.

The trial exposed a validation gap even though it was not retained.  The
isqrt differential fuzzer now includes explicit 1..513-limb edges and a
separate random 1..4096-limb mode, so small exact-quotient paths can be mixed
with large roots in one process.  With the production algorithm restored,
public-GMP checks passed 100,000 random roots through 512 limbs and 100 mixed
large/edge cases through 65,536 limbs.  The rejected candidate separately
passed 100,000 small and 100 mixed optimized cases plus 20,000 small and 48
mixed ASAN/UBSAN cases before the performance gate removed it.

## Fixed 22-limb division submul row -- NOT taken (2026-08-04)

The recurring 48-by-24 Knuth leaf under `isqrt@384` multiply-subtracts the
22 divisor limbs below its 3-by-2 estimate.  A fully unrolled fixed-22 row was
therefore measured across 39 `isqrt`/`div`/`mod` cells at thirteen widths,
including every nearby green control.  It lost 23/39 cells at a 1.015
candidate/baseline geomean, caused seven regressions above 5%, and made the
target `isqrt@384` 9.7% slower.  The candidate and benchmark knob were removed
without an acceptance replication.  Artifact:
`baselines/submul-f22-screen-26a4a17-m5max-20260804.json`.

## Current default matrix residuals -- 483/485 composed wins (2026-08-05)

The current M5 Max/public-GMP-6.3.0 default screen measured 472/485 boxed
cells ahead of GMP at a 0.618 Tungsten/GMP geomean.  The short screen was
used only to select the 51 cells at 0.95x GMP or slower.  A 15 x 200 ms
promotion cleared 44 of those; a 31 x 500 ms promotion cleared five of the
remaining seven.  Repeating the last two on AC power left two stable losses:
`isqrt@384` at 1.016x GMP (13,518.816 ns versus 13,304.902 ns, 1.35%
relative IQR) and `sub1@1` at 1.032x GMP (1.920 ns versus 1.861 ns, 1.81%
relative IQR).  The resulting 483/485 count is composed from the screen and
promotions, not a claim that one long 485-cell pass was run.  Artifacts:
`baselines/matrix-bfda652-current-screen-m5max-20260804.json`,
`baselines/matrix-bfda652-current-residual095-15x200-m5max-20260804.json`,
`baselines/matrix-bfda652-current-residual-red-31x500-m5max-20260804.json`,
and
`baselines/matrix-bfda652-current-residual-two-ac-31x500-m5max-20260805.json`.

## One-limb subtraction dispatch and reserve selection -- NOT taken (2026-08-05)

A direct positive one-by-one subtraction leaf closed the target cell at
0.964x GMP, but its production-shaped 15 x 200 ms family run won only 4/20
cells, regressed the family by 1.34% geomean, and made `sub1@64` 7.9% slower.
The broader same-binary trial likewise lost 36/60 cells and had thirteen
regressions above 5%.  Moving the sign split after word decoding was nearly
neutral across the family (0.996 geomean, no >5% regression) but made
`sub1@1` 0.6% slower and left it 1.064x GMP.  Selecting an exact one-limb hot
reserve instead of the smallest fitting reserve was also neutral overall
(0.9997 geomean across 50 cells), while making the target 1.5% slower and
1.052x GMP.  All candidates were removed.  Artifacts:
`baselines/sub1-positive11-same-binary-bfda652-m5max-20260804.json`,
`baselines/sub1-positive11-production-bfda652-m5max-20260805.json`,
`baselines/sub1-signsplit-word-screen-bfda652-m5max-20260805.json`, and
`baselines/one-limb-exact-hot-screen-bfda652-m5max-20260805.json`.

## B-Z correction-shape and isqrt384 follow-ups -- NOT taken (2026-08-05)

The B-Z trace now records full as well as shortened correction products.  The
384-limb isqrt fixture reaches seventeen full correction products: four at
`k=24`, seven at `k=25`, two at `k=48`, three at `k=50`, and one at `k=100`.
Lowering the B-Z base threshold from 24 to 20 lost the target and introduced
a >5% regression.  Routing the 24-limb top product to schoolbook arithmetic,
forcing a fixed 100-limb split, moving the product into the high remainder,
and placing submul in a hot section all failed their complete affected/control
screens.  A 32-limb approximate-divisor pad lost 8/9 cells.

Forcing the exact quotient only at 384 initially looked favorable in a
separate-binary screen, but the same-binary target was 1.9% slower and still
1.069x GMP.  Sum/difference selectors at the traced parent widths did not
replicate: the best parent-200/sum-100 screen became 1.0008 geomean with a
>5% regression in its 10-cell acceptance run.  The final 31 x 500 ms
three-cell check was directionally positive overall but still lost the
target, so no selector was retained.  Representative artifacts:
`baselines/bz-threshold20-screen-bfda652-m5max-20260804.json`,
`baselines/isqrt-bz-school24-context-screen-bfda652-m5max-20260804.json`,
`baselines/isqrt-pad32-screen-bfda652-m5max-20260804.json`,
`baselines/isqrt-exact384-same-binary-screen-bfda652-m5max-20260804.json`,
`baselines/isqrt-bz-parent200-sum100-acceptance-bfda652-m5max-20260804.json`,
`baselines/isqrt-bz-parent200-sum100-31x500-bfda652-m5max-20260804.json`,
`baselines/mul-split100-fixed-screen-bfda652-m5max-20260804.json`,
`baselines/bz-product-in-rh-screen-bfda652-m5max-20260804.json`, and
`baselines/submul-hot-section-screen-bfda652-m5max-20260804.json`.

## Split-carry-chain mul_1 kernels (16-64 limbs) — built, gated OFF (2026-08-10)

GMP's small marginal cost per limb between mul1 sizes (~0.6-0.8 ns-cycles/limb)
suggested `mpn_mul_1` overlaps carry chains within a call while our fixed
kernels run one serial `adcs` chain.  The mechanism was built (`BN_M1F_CUT`/
`BN_M1F_FIX` boundary correction with rare in-kernel ripple; shapes 8+8 through
16x4 inside `bn_mul_1_f16..f64` behind per-width `BN_MUL1_SPLIT_F*` knobs) and
validated by a 95,000,712-case fuzz against both the serial reference and
`mpn_mul_1`.

In latency mode (next multiplier derived from the previous carry — the chain
fully exposed) splits win 0.77-0.93 vs GMP exactly as designed.  In the boxed
lane they lose 0.8-2.6% at every width: back-to-back boxed calls already
overlap in the out-of-order window (each call's chain opens with a
flag-independent `adds`), so BOTH sides run at the shared multiplier-pipe
floor (~0.75-0.78 c/l marginal, measured for our serial kernels and for
`mpn_mul_1` alike) and the boundary corrections are pure overhead.  The
`mul1@24/@32` residual (~1.00-1.03) lives in the boxed wrapper (alloc/release
round-trip vs `mpz_mul_ui`'s retained destination — `sample` shows our lane at
~1.45-1.5x GMP's wrapper cost at every width, kernels out-sampling
`__gmpn_mul_1`), which prior wrapper campaigns above already measured as not
closable without regressing controls.

All `BN_MUL1_SPLIT_F*` default 0; the knobs-off binary compiles kernels
identical to the serial baseline (disassembly-verified, no `cset` in `f24`).
**Condition to enable:** a workload or silicon where the boxed lane is
latency-exposed (e.g. dependent single-op chains), per width, via the knobs.
## Hot-slot shave split halves — NOT taken individually (2026-08-11)

The shipped packed-word hot slot (pointer | cap<<48 in ONE u64) plus the
fused 16-byte release header read (type+shared+cap in one ldp) only wins as
a UNIT.  Screened separately against the same baseline (ABBA T-only medians,
two independent 3-pair screens pooled, 12 samples/side):

- Packed word alone: mul1@2 0.909 but neg@4 1.175, sub@8 1.059, mul1@4
  1.035.  The encode's orr must wait on the release path's late separate
  cap load, and the take-side pointer decode adds a cycle nothing else
  hides.
- Fused header read alone: exactly 1.000 on every mul1/add1 cell (no win to
  bank) with add@4 1.060 and neg@4 1.042.  The 16-byte header load spans
  the producer's just-stored `size` word (offset 4), so tiny-cell releases
  eat a store-forward partial-overlap penalty, and with the two-word slot
  still in place nothing consumes the early cap.
- Combined: mul1@2 0.875, mul1@4 0.932, neg@4 0.965, add1@1 0.983; every
  other word cell holds within 1% (mul1@32 re-probed at 1.004, 12
  samples/side).  The early fused cap feeds the packed encode directly and
  the halved slot traffic pays for the pointer decode.

**Condition to revisit the halves:** any future change that re-splits the
release header read from the slot encode (or re-widens the slot to two
words) must re-run the paired screen — each half's cost is only hidden by
the other's savings.

## mulhigh (Mulders short product) — validated, gated OFF on M5 (2026-08-11)

Built for the reciprocal-carrying isqrt recursion and intended to
generalize into the Barrett/powmod division spine.  The premise fails on
this uarch: best sequential config (beta=0.75, base=48) measures
mulhigh(n)/mul(n) = 0.87/0.78/0.92/0.92 at n = 512/1024/2048/4096 —
against a 0.75 gate — and in the sqrt path's parallel regime the short
product is outright SLOWER than a full multiply (1.04-1.16x), because
the worker pool gives one balanced product a ~2x speedup that a serially
composed short product cannot use.  The Newton reciprocal chain has a
second, structural failure: the residual 1 - high(D*X) cancels its
entire high half, so each precision doubling needs true products down to
the full doubled width (hp(v) + hp(v/2) per level, not 2*hp(v/2));
recomposed from measured parts the chain is +11% over the incumbent
bz_d2n1n_q, which itself measures 55% of isqrt@4096 exactly as profiled.
The primitive ships validated (200k-case contract fuzz, ASAN clean,
error bound ERR(n) <= 2*ERR(m)+1 proven in comments) but unused.
**Condition to take it:** single-core targets (no pool asymmetry), or a
cheap wraparound residual via mulmod B^m +/- 1 that dodges the
cancellation.  isqrt@4096/@8192 stand at 0.92/0.90 vs GMP without it.
## mulhigh wired: certified-reciprocal division (2026-08-11 addendum)

DRAFT addendum to the "mulhigh (Mulders short product)" entry — for
NOTED_TRADEOFFS.md when this lands (diff currently applied, uncommitted).

The 2026-08-11 "gated OFF" verdict was measured against the isqrt Newton
chain, where the competitor is ONE balanced pool-accelerated multiply.
Re-examined where the competitor is not that, three of five candidates
were negatives and two landed (plus one bug found by the route counters):

**Taken (wired, ABBA battery: bench_big_math boxed cells, medians of 4/side,
M5 Max, LLVM 22, -O3 -flto -mcpu=apple-m5):**

1. `mag_divmod_reciprocal_certified` quotient step (2n/n, vlen>=256).
   The incumbent full 2n x (n+2) U*R product measured 98-100% of the whole
   certified divide, and only its top n+3 limbs are consumed.  Dropping
   the low n-2 limbs of U up front (tail < 2*B^(2n-1)) leaves a balanced
   (n+2)^2 product; below the pool floor (BN_DIV_RECIP_MULHI_Q_MAX=382,
   or whenever bn_toom_parallel_depth is set) a Mulders short product
   beats even that.  The all-ones certificate probe becomes a headroom
   test rp[1] <= B-(vlen+9) proving the quotient exact outright
   (derivation in the code comment); failure ~vlen/B, fallback unchanged.
   Cells: div@256 0.57x, div@512 0.42x, div@1024 0.58x (controls
   div@24/64/128 = 1.00; the two-lane rect pool had only ever recovered
   the unbalance penalty, so the sequential short product still wins).

2. Barrett remainder-only arm, forced-sequential band
   (BN_DIV_RECIP_MULHI_R_MIN=8 .. BN_DIV_RECIP_PAR_MIN-1): first product
   (n+1)^2 full with only the top half consumed, pool already disabled —
   exact mulhigh shape.  The same one-extra-limb anchor keeps the
   existing <= 2 correction certificate (q_hat in [q-2, q], derivation in
   code; 30k-case fuzz measured zero corrections and zero cert failures).
   Cells: mod@128 0.96x, mod@256 0.92x, mod@512 0.91x.  Above the band
   the pool makes the full product cheaper (mulhigh 1.07-1.22x): incumbent
   stays.

3. `bn_mul_low` dropped-carry fix (found by the wiring's route counters):
   rows cut short by the operand rather than the result window discarded
   their addmul carry INSIDE the low-rn window, so the Barrett
   verification product was short at limb n whenever q3 trimmed to vlen
   limbs (~3 of 4 random operand pairs).  The certificate caught it —
   correctness always held — but every such mod in the 24..56 triangular
   band silently paid a full failed Barrett attempt plus the Knuth
   division it fell back to.  Random-operand probe: mod@24/32/48
   whole-call 0.37x/0.38x/0.39x once the certificate passes; the battery
   cell mod@24 (a lucky fixed operand pair that already certified) still
   shows 0.85x from the mulhigh product swap.

**Rejected (measured):**

- w_prime_modctx k>96 Barrett arm: q1*mu is only 29-38% of a ctx mulmod,
  so mulhigh predicts 0.89-0.97x mulmod at k=97..256 and ~1.0x at 384+
  (pool reaches the incumbent there).  Two premises of the plan were
  wrong: BPSW spawns no worker threads, and its band (k<=96, in the bench
  k<=17) is Montgomery — the Barrett arm only runs above 6144-bit moduli.
  Not worth widening the cached mu by two limbs.  Revisit if
  W_MONT_MAX_LIMBS drops.

- tostr P_j path (w_dec_divmod_pj): never rides the certified-reciprocal
  cache (P_j is not normalized; called out in its own comment block).
  Its per-level product1 has the same top-consumed shape, but summing the
  measured shares (top split 6-9%, balanced levels 30-56% of divisions
  that are themselves 25%/14%/8%.. of tostr) puts product1 at ~25-30% of
  tostr end-to-end; a 15% Mulders saving on that is ~3-4% — under the
  cell noise floor, against a delicate <=5-correction budget that the
  mulhigh deficit would eat into.  Battery: tostr@256 0.99x, tostr@1024
  0.98x (untouched, as routed).

- Fixed-kernel-riding recursion (candidate 3): the equal-shape dispatch
  already lands on the tuned bn_mul_eq ladder; direct calls measure
  0.993-0.999x at k=36..578 (0.98 at k=20).  Nothing to take, and the
  0.92@2048 sequential cell no longer exists in shipped paths — wired
  mulhigh runs at N <= ~770.

Gates: 120k-case wired fuzz vs Knuth (q and r bit-exact, 48.7k certified
hits, 0 cert failures), 30k more under ASAN+UBSAN clean, powmod/isqrt/
div-below-256 control cells 1.00x, stage identity + int_spec + bigint
specs (recorded in the landing report).
