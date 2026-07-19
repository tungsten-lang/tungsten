# GF(2) matmul flip-graph campaign — consolidated findings

This is the durable record of the flip-graph rank-search campaign for GF(2)
(mod-2) matrix-multiplication tensors, consolidated from many sessions
(2026-06-18 through present). It exists so a future session doesn't re-run
experiments already settled here. Where a finding was later corrected, only
the corrected version is kept — see "corrections" at the end for what changed
and why.

## 2026-07-11 audit: rigorous bounds, FlipFleet successor, and aligned symmetry starts

The global GF(2) intervals for the four requested square formats are now:

| format | rigorous lower bound | best construction | next upper target |
|---|---:|---:|---:|
| ⟨3,3,3⟩ | **20** (Wang 2026) | 23 | 22 |
| ⟨4,4,4⟩ | 34 (Bläser 2003) | 47 | 46 |
| ⟨5,5,5⟩ | 53 (Bläser 2003) | 93 | 92 |
| ⟨6,6,6⟩ | 76 (Bläser 2003) | 153 | 152 |

Wang's current v9 paper and machine-checkable certificate raise the 3×3 bound
from 19 to 20.  The published certificate was independently verified on this
machine in about two seconds.  A new 100M-step-per-orbit pass also strengthened
one dimension-2 child bound from 17 to 18 (32,307,892 backtracking leaves), and
the resulting checkpoint verified, but the global bound remains 20.  Direct
root searches through 1B steps did **not** prove 21; reaching a search cap is not
a refutation.  Source and certificates:
[`wcgbg/tensor-rank-lower-bound`](https://github.com/wcgbg/tensor-rank-lower-bound),
paper [`arXiv:2603.07280`](https://arxiv.org/abs/2603.07280).

The 2026-07-13 provenance recheck used upstream revision `efd22070269157e65aaf8d61a21da253a4000c61`
and fetched the two official Git-LFS objects rather than a locally extended
checkpoint.  Their SHA-256 values exactly match the tracked pointers:
`25595a883ce877eecd802139ff4e07646e154b2797ad6fe7f9ec737ab0c6135d`
for `cert_matrix_q02_n333.pb.txt` and
`4e824eb13c235e69045881d173d8ababe622421055a238005afce413aabe3289`
for its `.btp` proof archive.  The official verifier returned `OK` and the
unconstrained bound 20 in 6.55 seconds (non-LTO build; Apple-Clang LTO objects
trigger an unrelated `ld64.lld` stack-probing failure on this host).

The proof engine's highest-leverage next change is stabilizer-orbit pruning of
candidate constraint forms.  At the 3×3 root it currently branches over 511
nonzero forms although the full matrix symmetry has only three rank orbits; at
4×4 the analogous counts are 65,535 versus four.  Cache equivalences recover
values but do not shrink the certificate's exhaustive AND branch.  The paper
estimates more than 1.6e11 constraint-subspace orbits for 4×4, so on-demand
stabilizer orbits are likely prerequisite to moving that square lower bound.

A sound stabilizer prototype was subsequently tested.  Merely replacing the
511 root forms by three representatives is **not** sound in the legacy
numeric-prefix DFS; instead the prototype enumerates multisets of possible
A-forms modulo the base-subspace stabilizer and independently replays that
frontier.  It reproduced the published 2×2 and 3×3 proofs, reducing the 3×3
19→20 root layer from 511 cases to three.  For 20→21 its active frontiers were
`1, 3, 27, 760, 43,300, 1,917,713` through depth five.  All but 179,954
depth-five states closed, and those survivors were exactly one point short;
raising constrained orbits 492 (19→20), 493 (19→20), and 482 (18→19) would
close all of them.  Focused legacy searches still found no new proof: orbit
478 failed at 1B steps, orbit 480 failed at 1B, and orbit 492 failed at 250M.
The direct stabilizer traversal on orbit 478 reached 582,909 active depth-five
states and left 395,553 unresolved, so it also did not prove 19; its 3.31 GB
leaf-only pass quantified the barrier without constructing depth six.  These
caps are not refutations.  The full soundness argument, hashes, upper
bound checks, dependency chain, and certificate-format requirements are in
[`proof_orbit/README.md`](proof_orbit/README.md).

The final, deliberately-last lower-bound pass checked that official upstream
was still the audited `efd2207` revision and re-verified Wang's certificate in
2.01 seconds.  It then tried the two untested root dependencies: orbit 493
19→20 for 1B legacy steps (300.1 s, 36.1 GB RSS) and orbit 482 18→19 for 100M
steps (19.7 s, 5.36 GB).  Neither produced a checkpoint, so the rigorous 3×3
lower bound remains 20.  The next sound experiment should profile a
stabilizer-quotiented orbit-493 frontier to extract its child hitting set,
not spend a larger blind DFS budget.

### FlipFleet audit and pure-Tungsten replacement

Early fleet prototypes exposed several correctness and campaign defects:
hard-coded dimensions, scalar-only best retention across cycle-outs,
probabilistic checks that did not gate adoption, failed GPU loads left active,
fleet-wide leader resets that collapsed diversity, stale same-rank density
snapshots, and a W-only structured plus transition.  Those observations are
historical inputs to the current design, not the current runtime architecture.

`flipfleet.w` is now the authoritative 3×3–7×7 entry and loads the pure
Tungsten `flipfleet_native.w` driver.  The coordinator,
runtime-generic CPU walker, exact escape banks, adaptive policy, candidate
adoption, durable status/best checkpoints, and TUI are pure Tungsten.  Its GPU
roles compile checked-in dimension-specialized Tungsten/Metal assets; Python
generators and coordinators are not invoked during a campaign.

Every CPU or GPU result is exhaustively reconstructed before it can alter a
bank or the rank-then-density leader.  GPU hosts gate before writing and the
coordinator gates again.  The in-memory archive is bounded and max-min
diversity-aware, while exact best+1/best+2 shoulders and C3-preserving escape
states remain separate from the monotonic leader.  A ten-second 3×3 audit that
motivated this policy retained 42 distinct exact rank-23 schemes; an eight-slot
max-min sample had minimum term-set distance 34.

CPU threads keep tensor-specific sticky doors—leader, frontier, best+1,
best+2, symmetry, mixed escape, and anchor—and one of four independent
work/wander zones.  A strict improvement therefore does not turn the whole
fleet into follow-the-leader.  The default GPU policy is adaptive and `--no-gpu`
is the explicit control.

The frozen-core control originally received the same move quota as ordinary
walkers.  At 5×5 it sustained 11.6M moves/s versus roughly 50M for ordinary
walkers, and the synchronous join made every TUI row appear to run at the slow
control rate.  Per-thread timing plus an adaptive time-balanced control quota
raised measured 12-island throughput from 139M to 532M moves/s without removing
the control experiment.

The GPU portfolio keeps rank, density, C3, generic split, archive novelty, and
cooperative SIMD continuously active.  Fixed-cube break, orbit split,
polarization, and two-identity composition are discrete restarts and now rotate
with the defect, MITM, XOR-join, lifted-identity, substitution, and XOR-SAT
kernels instead of holding permanent lane floors.  Scalable pool epochs receive
up to three eighths of the device; host-heavy joins use smaller saturation caps
and return unused lanes to the continuous roles.

```sh
TUNGSTEN_LL_PATH=/tmp/flipfleet-native.ll \
  bin/tungsten -o /tmp/flipfleet-native \
  benchmarks/matmul/metaflip/flipfleet.w \
  --release --native --fast --lto

/tmp/flipfleet-native --tensor 3x3 --secs 60
/tmp/flipfleet-native --tensor 6x6 --no-gpu --secs 3600
```

### Symmetry starts must be target-aligned

The Moosbauer--Poole symmetric search does **not** start from the naive scheme;
it starts from a diagonal partition.  `sym_start.py` now constructs and exactly
checks those starts.  The authors' reference solver removes its `f` invariant
diagonal cubes from the mutable orbit set and freezes them, so that solver can
only visit ranks `r ≡ f (mod 3)` under C3.  Its published 5×5 three-cube run
therefore reaches 93 but would have to jump next to 90.  Frozen-cube starts
aligned with the one-rank-lower targets are:

| target | invariant cubes | example diagonal partition |
|---:|---:|---|
| 3×3 → 22 | 1 | `{1,2,3}` |
| 4×4 → 46 | 1 | `{1,2,3,4}` |
| 5×5 → 92 | 2 | `{1,2,4,5}, {3}` |
| 6×6 → 152 | 2 | `{1,2,5,6}, {3,4}` |

Using the authors' reference symmetric solver as a cross-check, the published
5×5 three-cube seed reproduced rank 93 on attempt 11 (45 seconds total for 12
attempts).  Target-aligned probes found no new record: 3×3 did 200 attempts /
600,282,006 flips and always stopped at 25; 4×4 did 100 attempts / 200,188,455
flips and reached 49 in 96 runs (usually then zero-neighbor); 5×5 did 100
from-start attempts / 15,987,958,677 flips and reached 95 three times but not
92.  Continuation did not unlock the smaller cases: 500 rank-25 continuations
spent 48,850,273,812 flips and all remained at 25; 500 rank-49 continuations
spent 50,000,001,000 flips and all remained at 49.  The stock reference solver
crashed when a saved rank-49 local minimum had an empty ordinary-move list, so
the latter batch used a separately compiled guard that enters the solver's
existing plus-transition path when headroom is configured (the patched path
passed an ASan/UBSan smoke test).  All twenty 3×3/4×4 waypoint files were
independently expanded and were exact, C3-closed, byte-distinct, and had the
intended one frozen cube.  Ten distinct rank-95 schemes were then
retained from a larger seed-making batch; 500 continuation attempts with plus
headroom through rank 101 spent 50,000,001,000 further flips and all 500
remained at 95.  These are component-search results, not tensor-rank lower
bounds.

For 6×6, 200 target-aligned starts spent 30,212,067,072 flips and reached rank
164 twice, but not 152.  One rank-164 waypoint was replayed and independently
checked (164 distinct nonzero terms, exact tensor identity, two frozen cubes,
and 27 mutable six-element symmetry orbits).  A further 500 continuations from
it spent 50,000,001,000 flips; every attempt remained at 164, so no rank-158
waypoint or rank-152 record was produced.

This residue rule is **not** automatic for every C3-closed walker.  In the local
`sym_gen2*` prototypes, orbit insertion can toggle a singleton cube and an
any-axis plus can split it into generic orbits; ordinary flips can also touch
one-hot singleton cubes.  These moves change both the fixed-orbit count and
rank residue while remaining exact and C3-closed.  A campaign must
either deliberately freeze those singleton terms or log their count; the
partition alone does not constrain the local prototype forever.

### Exact escape moves bridge the 3×3 frozen component

In local storage let `rho(u,v,w)=(v,w^T,u^T)`,
`O(t)={t,rho(t),rho^2(t)}`, and `C(x)=(x,x,x^T)`.  `sym_escape.py` now exposes
three fixed-cube toggles plus a generic split of any term.  A fixed-cube
one-axis split is an exact nominal +1 move into the full, non-C3 flip graph.
The C3-preserving identity

```text
C(x) = O(y,x,x^T) + O(x+y,x,x^T)
```

normally replaces one fixed term by six generic terms (+5 rank).  Cubic
polarization preserves C3 while deliberately changing fixed count and rank
residue; its collision-free delta is +7, while existing cubes made the record
campaign examples +5.  Exhaustive Python checks covered all **781,830**
one-axis 3×3 fixed splits, all 260,610 nontrivial 3×3 orbit splits, and all
130,305 unordered 3×3 polarizations; every identity expanded to the zero
tensor.  Random applications and every CLI output were checked against the
exact matrix-multiplication tensor.  Because these are parity toggles, actual
rank deltas can differ when terms already exist and cancel.

On the deterministic frozen waypoints above, the +1 split changed 3×3
rank 25 / 15 ordinary shared-factor pairs into rank 26 / 20 pairs, and changed
the zero-neighbor 4×4 rank-49 state into rank 50 with four pairs.  Twelve
asymmetric continuations reached the known 3×3 rank 23 in about one second,
then found no rank 22 over at least 23.2B reported moves.  The 4×4 version
returned to rank 49 and found neither 47 nor 46 over at least 72.1B reported
moves.

The +5 C3 split changed the same waypoints to ranks 30 and 54, with 42 and 24
ordinary pairs respectively.  Twelve 500M-move 3×3 continuations all reached
rank 23 (first observed between 1M and 194M moves); all twelve final schemes
were independently exact, C3-closed, and had two fixed terms.  Twelve analogous
4×4 runs all returned to exact C3 rank 49 with one fixed term and found no rank
46 over 6B moves.  These runs demonstrate a real component bridge—especially
rank 25 to rank 23—not a new upper bound or a tensor-rank lower bound.

### Escape moves are integrated into FlipFleet

`flipfleet_escape.w` implements generic split, fixed-cube break, orbit split,
polarization, and two-split composition directly over the native fleet's
parallel i64 factor buffers.  The coordinator builds mixed, best+1, best+2,
and C3-preserving banks without a separate preparation process.  Fixed/C3
families retain their eligibility checks, while generic split covers the
fixed-free 3×3 and 4×4 frontiers.

Escaped higher-rank states remain bank seeds; they do not replace the
rank-then-density leader merely because they were constructed.  Every seed
passes factor bounds and exhaustive reconstruction, C3-bank entries also pass
closure, and every returned candidate is gated again before adoption.  A
subsequent ordinary CPU walk may leave C3; only the dedicated C3 Metal engine
preserves complete cyclic orbits at every step.

A compiled 3×3 cycle-out smoke used `cycles=1`, a 1K-move record band, and
`split@cycleout/every1`.  The initial native launch loaded rank 23.  Four
genuine cycle-outs selected exact rank-24 escape seeds; three completed native
launches logged `seed rank=24 verify=1`, descended back to exact rank 23, and
two improved the same-rank density leader.  The fourth was launched at the time
box and then quiesced.  Final coordinator state remained rank 23 with four
escape applications, zero skips, zero invalid candidates, and no escaped seed
admitted as a higher-rank frontier.  This checks the actual argv/runtime-seed
path as well as the Python transformation.

A compiled 5×5 `orbit-split@startup/every1` smoke loaded the density-1191 C3
record as an exact rank-98/fixed-count-two seed (`seed rank=98 verify=1`).  The
ordinary native walker descended 98→95→94→93 in 351 moves with no invalid
candidate and produced an intermediate density-1189 leader, while the
coordinator's frontier stayed rank 93 throughout.

A final bounded portfolio ran 18 escaped startup walkers for 30 seconds.  All
18 native processes loaded `seed rank=98 verify=1`; none found rank 92, but six
successive exact-gated tie leaders reduced density to **1168** / 1,050 no-CSE
operations.  The run retained 210 exact rank-93 frontier schemes, reported zero
invalid candidates, and ended cleanly at rank 93.

### Escaping the isolated AlphaTensor 4×4 record

The exact AlphaTensor rank-47 seed has density 450 and no repeated U, V, or W
factor, so it has zero ordinary flip partners.  For a term `(a,b,c)`, replacing
its U factor by the exact GF(2) split
`(x,b,c) + (a+x,b,c)` gives a rank-48 escape (and analogously on V or W).
Restricting `x` so that both `x` and `a+x` already occur on that axis elsewhere
in the seed produced **165 distinct exact rank-48 starts**.  Each initial escape
has two external one-axis flip edges and a four-term connected component.  By
comparison, the random structured-plus move always draws one existing factor,
but its complementary factor is also present in only 330 of 6,486 ordered
proposals (about 5.1%), so its usual initial component has only three terms.

The complete ordinary-flip closure of all 165 starts, while forbidding rank
above 48, contains just **3,210** states: 3,209 at rank 48 and the original
isolated rank-47 scheme.  The closure has maximum ordinary distance 11 from an
escape start; its richest states have seven one-axis edges and a connected
component of size eight.  Every state was independently reconstructed as the
4×4 multiplication tensor.  There is no rank-46 state in this closure, so at
least a second plus identity or a rank-49-or-higher excursion is necessary for
this route.

Three bounded native campaigns then tested those exits:

| policy | aggregate moves | observed result |
|---|---:|---|
| random-axis plus/2000, band 3 | 12 × 500M = 6B | exact rank 47 in all 12 |
| complement-present plus/50, retained rank-48 anchor, band 4 | 12 × 500M = 6B | live ranks 47--51; no 46 |
| complement-present plus/20, retained rank-48 anchor, band 12 | 12 × 500M = 6B | live ranks 47--59; no 46 |

All final retained schemes were independently exact (12/12 in each policy),
and no rank-46 artifact was emitted.  The last policy genuinely maintained
multiple simultaneous split identities rather than merely collapsing each
escape back to rank 47, but it still did not descend.  The 3,210-state result
is an exhaustive statement only about the rank-at-most-48 ordinary component;
the 18B-move continuation results are search negatives.  Neither is a global
tensor-rank lower bound.

A separate exact rank-neutral macro probe asked whether a selected `k`-term
partial tensor has a distinct `k`-term decomposition, blocking the planted
solution and exact-checking every splice.  Compressing each mode to the span of
the selected factors made the 3×3 `k=3` scan exhaustive over all 1,771 chunks:
it found 18 distinct rank-23 rewrites, 12 equal to one ordinary flip and the
other six at ordinary-flip distance exactly two.  Thus it exposed no new
component.  On the isolated 4×4 rank-47 seed, span-dimension-prioritized samples
found no alternative model or timeout among 200 `k=3`, 2,000 `k=4`, and 500
`k=5` chunks; a further 400 `k=3` chunks checked with unrestricted 16-bit
factors also had no alternative or timeout.  Only the 3×3 factor-span scan was
exhaustive; the 4×4 samples are scoped search negatives, not a tensor-rank
lower bound.

### Escaping the tracked 5×5 and 6×6 record components

The tracked MP seeds are exact C3 schemes of ranks 93 and 153, each with three
fixed terms.  Deterministic orbit splits produced exact C3 rank-98 and rank-158
seeds with two fixed terms.  An unconstrained local C3 campaign used three
policies (any-axis plus/200 with band 15, any-axis plus/50 with band 24, and
W-only plus/200 with band 18), four walkers per policy.  Every walker undid the
bridge and returned to the known record within the first million moves:

| format | aggregate moves | final best-rank distribution | target |
|---|---:|---:|---:|
| 5×5 | 12 × 500M = 6B | `{93: 12}` | no 92 |
| 6×6 | 12 × 500M = 6B | `{153: 12}` | no 152 |

All 24 final dumps were independently reconstructed as exact, well-formed, and
C3-closed with three fixed terms.  The MP 6×6 seed is also invariant
under reversal, whereas the deterministic split is not; only one of the twelve
final rank-153 dumps recovered reversal symmetry.  Thus the extra Z2 symmetry
is not required for exactness or descent back to 153.  Dropping it enlarges the
search space (a potential quotient-performance cost), but is what opens states
outside the published C3×Z2 component.

Polarization gave a better target-aligned bridge.  From the records it first
made exact fixed-count-two ranks 98 and 158; a deterministic ordinary C3 flip
then reached ranks 95 and 155, one three-term orbit above the targets.  A hard
fixed-count-two guard inverse-toggled transitions that left that stratum.  An
instrumented build compared the logical term set before and after 1,000
rejected ordinary moves and 1,000 rejected plus moves, with zero mismatches.
Periodic compiled checks and independent final reconstruction also remained
exact.  The bounded hard-stratum results were:

| format | aggregate moves | final distribution | rejected transitions |
|---|---:|---:|---:|
| 5×5 | 12 × 500M = 6B | `{95: 12}` | 116,812,167 |
| 6×6 | 12 × 500M = 6B | `{155: 12}` | 73,426,310 |

All final schemes were byte-identical to their exact starting waypoint; neither
hard-stratum campaign found a lower saved frontier.  A final target-biased 5×5
heuristic therefore allowed temporary fixed counts 0, 1, 2, and 3, but only
accepted a lower saved best when `fixed_count == 2` and the compiled verifier
passed.  Across 12 × 250M = 3B moves it skipped 12,948,533 lower-rank visits in
other residues, yet all twelve saved frontiers remained independently exact
rank 95; no rank 92 was found.  This is a biased search negative, not an
exhaustive component result or a tensor-rank lower bound.

The unconstrained 5×5 batch did produce a same-rank cost improvement:
`matmul_5x5_rank93_d1191_gf2.txt` is exact C3 rank 93 with density 1191 and 21
ordinary shared-factor pairs, versus density 1224 and 12 pairs for the tracked
MP seed.  Its SHA-256 is
`ead9069627a7f15b238fbd95643b2d0b66545b76844b917be5edc651bf359f45`.
This is not a tensor-rank record, but it is both sparser and more connected and
is retained as the preferred C3 frontier seed.  The integrated orbit-split
smoke descended 98→95→94→93 in 351 moves, and the final 18-walker portfolio
improved the same-rank cost again:
`matmul_5x5_rank93_d1168_gf2.txt` is exact non-C3 rank 93, density 1168,
13 shared-factor pairs, and 1,050 no-CSE operations.  Its SHA-256 is
`10bacef79e1b43fdf1b494f2aebb6e6fa12afc5df00b5755c5915b7acfbbbb10` and it
was the default cost-oriented 5×5 frontier at that stage; the C3 campaign kept
the density-1191 scheme for orbit-split/polarization.  Rank and no-CSE base-case
operation count remain separate objectives, so density gating must not prune a
rank-record walk.  A final workspace scan parsed 214 rank-93 files and fully
verified 190; density 1168 was the minimum, with 1191 next.

## Verified record table (GF(2), n,m,p ≤ 7)

| format | naive | best known | source |
|---|---|---|---|
| ⟨3,3,3⟩ | 27 | **23** | Laderman 1976 |
| ⟨4,4,4⟩ | 64 | **47** | AlphaTensor (DeepMind, Nature 2022 — deep RL, not flip-graph-discovered) |
| ⟨5,5,5⟩ | 125 | **93** | Moosbauer–Poole symmetric flip-graph (arXiv:2502.04514) |
| ⟨6,6,6⟩ | 216 | **153** | Moosbauer–Poole symmetric flip-graph |
| ⟨7,7,7⟩ | 343 | **247** | weighted Strassen-outer isotropy plus support-aware 4/3 embedding; exact certificate in this repository |

**Corrected note:** Sedoglavic 2017 (arXiv:1712.07935) supplies the general-ring
seven-block identity. Its historical rank-250 specialization used the then
available square leaf, but substituting the exact GF(2) ranks 47, 29, and 38
gives 248 deterministically. Kauers--Wood's cited paper does not contain a
7×7 result and must not be credited with rank 249. Perminov independently
reports rank 248 from a direct GPU population search. The rank-247 construction
below improves that GF(2) upper bound; it does not claim a characteristic-zero
algorithm. The old ~1.5-trillion-move siege from a rank-250 seed only describes
that seed's local component and says nothing about reachability from either the
rank-248 or rank-247 frontier.

### 2026-07-14: exact rank-247 7×7 by weighted outer isotropy

`flipfleet_outer_isotropy_bench.w` exhausts all `6^3 = 216` images of the
rank-7 Strassen outer scheme under `GL(2,2)^3` and all eight placements of the
4/3 coordinate blocks. Every outer image is independently exact before it is
scored. The scan covers 1,728 recipes; 480 tie at nominal rank 248 and are all
materialized and fully reconstructed. Forty-eight of those recipes produce
rank **247**.

The winning recipe uses outer image codes `(I,A,B)` and allocation mask 3.
Its nominal rectangular-leaf sum is 248. Support-aware embedding truncates
exactly one leaf product to a zero factor; the other 247 products are distinct,
and duplicate-parity cancellation contributes zero. Thus the improvement is a
genuine weighted-support effect, not an accounting artifact. The checked-in
certificate is `matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt`, with SHA-256
`cb18a91b28e9e8b452dde46f69d876638a5af733c1d419ea77185da1c2487ea3`.
It has density 3554, 43 equal-factor pairs, and term-set distance 495 from the
former density-2952 rank-248 leader.

The formula-minimum audit took 20.73 seconds and about 71 MB RSS on the
development machine. A second harness, `flipfleet_outer_isotropy_full_bench.w`,
materialized all 1,728 recipes in 85.10 seconds to rule out a nominally more
expensive recipe compacting further. Its exact-rank histogram was
`247:48, 248:432, 250:480, 251:720, 253:48`; 576 recipes mapped one term to
zero, none mapped more than one, and none had duplicate-parity cancellation.
The certificate passed the Tungsten full tensor gate, serialize/
reparse/full-gate, an independent Python dense reconstruction, and an
independent sparse-parity reconstruction (`343` tensor ones and `4,668`
pair-XOR contributions). As of the 2026-07-14 public-catalogue comparison,
the discoverable GF(2) 7×7 frontier was rank 248, so rank 247 is a candidate
current world record pending the usual external catalogue/reviewer check.

The 48 winning recipes collapse to eight unique term sets. Three additional
rank-247 structural seeds are retained beside the reproducing artifact; each
has density 3554, 43 equal-factor pairs, and pairwise term-set distance 494.
They are low-cadence same-rank restart doors, not synthetic novelty scores.

Two alternate block families were closed as controls. The complete 46,656-row
two-block scan over every `6+1`, `5+2`, and `4+3` split and every
`GL(2,2)^3` outer image found formula minima 263, 256, and 248 respectively.
All 1,008 competitive recipes involving a `5+2` axis were materialized: every
one remained exact rank 256, with no mapped-zero or duplicate-parity
compaction. Separately, a rank-23 3×3 outer with `3+2+2` blocks produced exact
rank 273; steepest `GL(3,2)^3` walking improved some presentations by eight
formula terms but did not beat 273. The latter audit imports and independently
checks the GF(2) rank-11 `2x2x3` AlphaTensor leaf. These controls make the
weighted `4+3` Strassen orbit the uniquely productive audited block family,
without claiming an exhaustive theorem over all possible outer schemes.

### 2026-07-14: directed whole-scheme isotropy lowers search cost

An ambient matrix-multiplication isotropy applies an invertible basis change
to every term, with the corresponding contragredient actions on the other
factors. `flipfleet_global_isotropy.w` implements these actions using exact
swaps and transvections, replays their inverses, and full-gates every
materialized scheme. Random words were a negative result: on 4×4 they changed
every raw basin ID without changing the actual `GL` orbit or producing a
rank/density win, while on 5×5 they usually made the starting scheme denser.
Raw D3/reversal IDs therefore overcount basis relabelings as basin diversity.

Directed steepest descent over the same exact generators is strongly positive.
It reduced the catalog AlphaEvolve 5×5 rank-93 seed from density 1057 to 983;
two 24-island × 2M-move short-walk batches then reached density **968**.
Against the old density-1155 seed, a paired 24 × 2M benchmark gave density
wins in 24/24 trials versus 0/24 and minima 970 versus 1155. On 6×6, 1,024
isotropy restarts reduced rank-153 density 2502 to 1878; 80M productive short
walks reached **1860**, and another 64M audit moves were neutral. On the new
7×7 rank-247 certificate, 1,024 restarts reduced 3554 to 3137. A two-island
native continuation reached exact density **3098** after about 1.5B moves;
another 1,024-restart descent found it locally normalized. The square assets
at 5×5, 6×6, and 7×7 independently reconstruct exactly and have SHA-256:

- `matmul_5x5_rank93_d968_global_isotropy_gf2.txt`:
  `929262ed40c2978555a903377a62a76f9f68a92ae596cb82786dab1eb05fdc5b`;
- `matmul_6x6_rank153_d1860_global_isotropy_gf2.txt`:
  `f7e85eed357a54346ed5af061f0afbb5f9f66148a528b31c86f1d1678f1b86f7`;
- `matmul_7x7_rank247_d3098_global_isotropy_gf2.txt`:
  `ec097175450d3e67582ff5997051066e464cec3e7b16432253f3ded6b43fcc36`.

The rectangular generalization independently acts on the three domain sizes.
For ⟨2,3,4⟩, 256 directed restarts reduced the exact rank-20 catalog seed from
density 136 to **130**; the new default has SHA-256
`f9e858e97e84052d949e252a88885886146f3839275cbee615f03faf83658b72`.
These are cost/search-surface improvements at fixed rank, not new rank upper
bounds. Production FlipFleet now normalizes promising exact candidates before
admission, generates bounded directed-isotropy archive images at startup, and
adds a coarse `gi` orbit tag. That tag is telemetry: unequal values prove a
difference in the measured invariant, but equality is not a complete orbit
canonicalizer and never replaces full tensor reconstruction.

### 2026-07-13: deterministic rank-248 composition and rectangular subfleets

The pure-Tungsten `flipfleet_sedoglavic.w` composes exact schemes for
⟨4,4,4⟩, ⟨3,3,4⟩, and ⟨3,4,4⟩ through the characteristic-two Strassen-pad
identity. `ffsc_compose_files(path444, path334, path344, output, variant)`
rejects malformed or inexact leaves, cancels duplicate GF(2) terms, checks
every coefficient of the full 7×7 tensor, and writes only after that gate.
For the checked-in ranks 47/29/38 it returns rank 248.

The normalized rectangular leaves came from the addition-reduced ZT schemes
in dronperminov/FastMatrixMultiplication, reduced modulo two and independently
verified: `matmul_3x3x4_rank29_gf2.txt` has density 204 and
`matmul_3x4x4_rank38_gf2.txt` has density 282. Three reproducible 7×7
placements are retained:

- variant 0, density **2952**, the default and density leader;
- variant 1, density **2958**, the canonical sparse placement;
- variant 2, density **3015**, a distinct coordinate placement with 53
  shared-factor pairs across 78 terms, versus 44 pairs across 60 terms for
  the canonical placement.

All three rank-248 files were regenerated by the Tungsten composer, reloaded,
and exhaustively verified. A rectangular improvement has threefold leverage:
rank 28 for ⟨3,3,4⟩ or rank 37 for ⟨3,4,4⟩ would immediately recompose a
rank-245 7×7 scheme.

Two published thresholds exist per rectangular size on the 8/9 frontier —
see the campaign memory for the ⟨8,8,9⟩/⟨8,9,9⟩/⟨9,9,9⟩ soft-target map if
resuming that hunt; not reproduced here since it's speculative/unverified
territory, not a settled finding.

## What's been tried, exhaustively, and does NOT break any record

This is the single most valuable section — every one of these was tested to
real scale (billions to trillions of moves) and produced a clean, repeatable
negative. Don't re-attempt any of these without a genuinely new idea:

- **Plain random-walk flip-graph** (flip + natural reduction + restart-to-best):
  reaches 23/47/93/153 reliably, does not go below.
- **Greedy reducing-move** (always take a guaranteed ≥2-factor reduction):
  actively **regresses** — traps in local minima faster than pure random walk
  (3×3→24/25 instead of 23, 4×4→53/64). Reducing moves must be *accidental*,
  not scheduled; even 1/20 greedy frequency measurably hurts.
  Do not add greedy reduction "for speed" — it breaks quality.
- **Higher-order bucket reduction** (Gaussian-elim refactor of any term group
  sharing a factor, not just the trivial zero/dup case): fully implemented,
  verified correct, **conclusively neutral** — same walls (95/161 in the
  pre-correction record numbering) hold even with the complete reduction
  repertoire in the loop.
- **Zero-sum motif injection** (splice a naive⊗Strassen 15-term zero-sum patch
  into a random 2×2 subblock, for non-local escape structure): neutral.
- **Structured plus-moves + edge-constraint hierarchy** (Arai 2024 policy,
  full implementation): matches records reliably from naive, does not beat
  them from a record-seed.
- **Symmetric-quotient search** (C₃ rotation symmetry `(i,j,k)→(j,k,i)`, no
  transpose): reaches the same records via a much smaller (exhaustible) state
  space; the symmetric rank-23 component for 3×3 was **fully exhausted** — no
  path to 22 exists via symmetric moves from that component.
- **3×3 → 22 strong search negative (not a lower bound)**: ~1.5 trillion moves, full move-set stack
  (free walk + structured plus + bucket reduction + motif injection), 22
  appeared zero times while 23 appeared 300k+ times. Consistent with the
  symmetric exhaustion above. This is why Laderman-23 has held since 1976.
- **All-size 60-minute fleet sweep**: ~3 trillion moves total across 3×3/4×4/5×5,
  every wall held exactly at the recorded rank.
- **777-siege from a rank-250 seed**: ~1.5 trillion moves, zero descents —
  see the correction above for why this doesn't actually test the real
  248-frontier.
- **Meta flip-graph (Kauers–Wood cross-format edges)**: built and validated
  (extension/projection edges, round-tripped tensor-valid across format
  changes) — but **does not target the square records**. (5,5,5)=93 and
  (6,6,6)=153 are the symmetric flip-graph's own results, used as the
  meta-flip's *seeds*, not its target. The meta-flip improves the
  **rectangular vicinity** around the squares ((4,5,6)=90, (5,5,7)=127,
  (5,6,7)=150) — hunting a square-record improvement with it is mis-aimed.
- **Naive 1-thread-per-walker CUDA port** (RunPod B200, faithful port of the
  Mac fleet's kernel): only **1.7×** the 18-core Mac fleet's throughput
  (184M moves/s vs 108M/s) — each GPU thread is ~6500× slower than a CPU
  thread. GPU-hostile: ~3.8KB mutable state per walker in local memory (low
  occupancy) plus branchy, divergent O(rank) scans every move. **Throughput
  was never the lever** for this class of workload — see the next section
  for what actually moved the needle instead.

**Overall conclusion as of 2026-07-03**: the observed walls are structural
within the tested move families, not merely a tuning or throughput problem.
Every buildable lever on top of the *same*
move-family (flip + plus + reduction, in any combination or schedule) lands
on the same ranks. The one technique that ever changed the game was
**symmetry** (made 3×3 exhaustible) — cancellation patterns *are* symmetries,
which is presumably why human/RL-found algorithms (Strassen, Laderman,
AlphaTensor) look the way they do.

## GPU: what actually works

The naive CUDA-style port above is a dead end, but a **threadgroup-memory
redesign** on Metal is not:

### 2026-07-11: give breadth distinct exact basins

The previous relay assigned every lane the same CPU frontier.  That duplicated
the CPU fleet's basin and wasted the GPU's one genuine advantage: breadth.
`flipgraph_gpu_cal2zone.w` now builds exact split escapes in its Tungsten host
and lays them out as a seed portfolio; the kernel selects
`seedid = tid % nseeds`.  The native driver compiles the checked-in specialized
worker on demand, launches finite adaptive epochs, and independently exact-
gates its output.  Portfolio construction is outside the move loop, and the
kernel pays only a one-time seed offset at initialization/reset.

The audit also found that the 5×5 plus move used a 16-bit modulus (`65535`) for
25-bit factors.  The corrected kernel samples `1..2^25-1`; the specializer uses
the actual maximum factor width for every format.  This is a search-space fix,
not a micro-optimization.

The former i32 kernel necessarily corrupted 6×6's 36-bit masks.  Tungsten now
has `gpu.shared_i64` and 64-bit Metal buffer host accessors, and
`gpu_cal2zone_gen.py` emits native-i64 buffers, scratch, mask temporaries, and
full-width RNG for 6×6.  Its generated default uses four walkers per
threadgroup (rather than 16) so the three rank-cap arrays remain below 32 KiB.
Both 5×5 and 6×6 sources compile through the self-hosted emitter to the expected
MSL (`device int/long`, `threadgroup int/long`).  With unrestricted device
access, the i64 shared-memory smoke passed on an Apple M5 Max and both relay
formats completed real dispatches.

The first bounded 6×6 grind was immediately productive.  Starting from the
tracked exact rank-153 density-2574 scheme, an 8-lane × 1,000-move smoke found
density 2559.  Three successive 1,024-lane × 100,000-move rounds over 256 exact
split basins then found densities 2528, 2516, and **2512**; the fourth identical
round was neutral.  Each improving candidate passed both the relay verifier and
independent full tensor reconstruction.  A productive round took 5.90 seconds
including process startup/runtime Metal compilation.  The final scheme has
rank 153, 2,512 factor bits, and 2,323 no-CSE operations versus 2,574/2,385 for
the previous seed.  `matmul_6x6_rank153_d2512_gf2.txt` is now the tracked 6×6
cost leader.  This validates exact-basin diversity as a useful GPU role, but it
does not improve tensor rank.

The same bounded protocol improved 5×5 from the prior density-1168 cost leader
to 1160, 1157, and **1155** in three successive 102.4M-move rounds; the fourth
was neutral.  Productive rounds took 3.64–3.71 seconds on the M5 Max.  The final
scheme independently reconstructs the full tensor and has rank 93, 1,155
factor bits, and 1,037 no-CSE operations (13 fewer than density 1168).
`matmul_5x5_rank93_d1155_gf2.txt` is now the 5×5 cost leader.  It unexpectedly
returned to C3 closure with three fixed cubes, so it is also the new symmetry-
campaign default; density 1191 remains as a reproducible historical frontier.

### 2026-07-11: cooperative GPU, adaptive roles, and mined escapes

Ten follow-up ideas were implemented or bounded after the split-basin run.
The strongest throughput change assigns one whole decomposition to one Apple
SIMDgroup.  Partner, zero, duplicate, density, and copy scans are striped over
32 lanes and reduced with SIMD intrinsics.  A fair 512M-attempt A/B on the M5
Max measured:

| format | cooperative scan | shared hash chain | selected |
|---|---:|---:|---|
| 5×5 i32 | 351.4M steps/s | 234.3M steps/s | scan (+50%) |
| 6×6 i64 | 286.0M steps/s | 313.3M steps/s | hash (+9.5%) |

Both modes made identical partner selections and emitted byte-identical,
exhaustively tensor-verified results.  The 6×6 run improved the rank-153 cost
frontier from density 2512 to **2508**, or 2,319 no-CSE operations.  The exact
asset `matmul_6x6_rank153_d2508_gf2.txt` has SHA-256
`994ac8e19b5bf2104ef3294ee31c83606e65aaaff9b888b9bba3d9468a2f3209`.
It became the ordinary 6×6 default at that stage; the density-2574 C3 seed
remained separate for quotient walks.  This was not a tensor-rank improvement.

### 2026-07-12: native mixed CPU fleet reaches 6×6 density 2502

The pure-Tungsten mixed CPU fleet subsequently improved the same rank-153
frontier from density 2508 to **2502**, reducing the no-CSE base-case cost from
2,319 to **2,313 operations**.  The candidate was checked independently of the
search path: it has 153 distinct nonzero in-range terms and reconstructs all
46,656 coefficients of the 6×6 matrix-multiplication tensor over GF(2).  It is
also C3-closed with three fixed cubes.

The new default asset is `matmul_6x6_rank153_d2502_gf2.txt`, SHA-256
`df2750d583ce256321ad59a799171497d3b734fd5db7cc4190b852630c2a03d1`.
The d2508 file remains tracked with its original cooperative-SIMD attribution;
d2502 is its native mixed-CPU successor.  This is a cost improvement at the
known rank, not a rank-152 construction.

The discovery run was a bounded CPU-only native control (12 sticky islands,
1M moves per round); it surfaced d2502 in the first 12M aggregate moves and
remained the leader through 120M:

```sh
/tmp/flipfleet-native --tensor 6x6 --walkers 12 --steps 1000000 \
  --rounds 10 --no-gpu --no-tui --best /tmp/flipfleet-6-best.txt
```

At that stage FlipFleet also gained an opt-in adaptive GPU policy with four exact-gated
Tungsten/Metal shards: rank, density, escape, and novelty.  A bounded Pareto
archive over density, flip-pair connectivity, and term-set distance reseeds the
novelty role; exposure-normalized UCB allocation moves whole threadgroups while
retaining a one-group floor.  A short real 3×3 smoke reallocated live and had
zero invalid candidates, but tied the single-policy control.  The mechanism is
validated; no performance advantage is claimed yet.

The escape family is no longer limited to one split.  Two independently
verified 48-slot banks mix generic/fixed splits, C3 orbit splits,
polarizations, and normalized depth-two sequences.  A staged coordinator runs
a generated C3 Tungsten walker, applies an exact symmetry break, and hands off
to a generated ordinary Tungsten or Metal walker.  Real 5×5 and native-i64 6×6
smokes returned escaped ranks 98/158 to exact 93/153, but only to densities
1156/2540, so neither beat the tracked cost frontiers.

Tensor-signature joins found primitive five-term identities rather than only
composed binary splits.  Eight small candidate subsets produced 12, 7, and 115
non-factor-constant five-circuits for 4×4, 5×5, and 6×6; 3×3 instead supplied a
distance-five five-way split with only a +1 rank delta.  A 30-second,
four-walker Tungsten campaign from that 3×3 escape returned to rank 23 in one
second and reduced density 266 → **159** over 5.25B moves.  The independently
exact asset `matmul_3x3_rank23_d159_gf2.txt` has SHA-256
`ee07f94185603f5b39532b0188d1df7fd08d6b5a9272dc3912a4e4104d731086`
and 127 no-CSE operations.  No rank-22 scheme appeared.  The corresponding
4×4 five-circuit campaign returned to rank 47/d450 without finding rank 46;
a direct 4.096B-step cooperative-GPU pass on d450 was also neutral.
Three subsequent cooperative-GPU rounds spent 4.096B attempts each on the new
3×3 basin.  They reduced density 159 → 144 → **139**, then repeated 139; each
round took about 9.2 seconds at 441–445M steps/s.  The final rank-23 scheme has
107 no-CSE operations and SHA-256
`9d4c649998137bcbe779cfcc57c16c7b4c0f54497687c3cf10b601be428afc80`.
All outputs passed exhaustive tensor reconstruction, but none of the 12.288B
attempts found rank 22.  `matmul_3x3_rank23_d139_gf2.txt` is now the ordinary
3×3 default.  Remining that frontier produced 9,082 exact identities; fresh
rank-26/distance-five and rank-30/distance-nine bank slots each received
another 4.096B cooperative attempts.  Both returned to rank 23/d139 without a
rank-22 hit, bringing the cooperative total for this new basin family to
20.48B attempts.

A restricted meet-in-the-middle surgery scout joined full tensor signatures
for local 5→4 replacement.  It missed finite candidate families on all four
tracked records (3×3: 32 subsets/pool 700; 4×4: 16/pool 500; 5×5 and 6×6:
8/pool 500).  These are not local or global lower bounds.  Replacing full
6×6 pair-sum dictionary keys with a linear 128-bit projection plus exact
collision checks reduced the pool-700 control's peak RSS from about 955 MB to
91 MB.

### 2026-07-12: unified pure-Tungsten mixed/adaptive FlipFleet

`flipfleet.w` loads the native driver that makes the mixed CPU portfolio and
heterogeneous adaptive GPU policy the defaults; `--no-gpu` is the explicit
off switch.  The
`--tensor 3x3` through `--tensor 7x7` arguments select one pure-Tungsten
driver. Every size uses a tracked exact frontier seed and honest known-record
target. Size 7 now starts at rank 248 from the verified block composition;
the signed-i64 factor ABI rejects 8x8.

Eleven adaptive roles are active when eligible: rank, density, true
C3-preserving walking, generic split, fixed-cube break, orbit split,
polarization, depth-two composition, archive novelty, and cooperative
SIMD-group walking, plus a bounded rotating GPU kernel pool.  The pool reserves
one eighth of lanes and rotates projected R−1 defect search, exact
5→4/6→5/7→6 XOR surgery, lifted identities, verified contraction-bound
scouting, and XOR-SAT cube search.  They start from
tensor-specific fractions derived from the campaigns above, then exchange
whole 32-lane quanta under feedback normalized by measured worker wall time
(one exposure unit per occupied 32-lane/100ms quantum).  Exact role banks rotate
complete variable-rank schemes across restarts.  The generic-split role
remains a pure +1 control through the cal2zone host's internal wide split
portfolio.

The archive-novelty source is now a genuine bounded nondominated set at the
lowest returned frontier rank, trading off density, flip-pair connectivity,
and minimum term-set distance.  It is not an alias for the ordinary
rank/density archive.  C3 likewise keeps an
independent branch leader even when that exact+C3 state trails the global
leader; fixed-cube break can stage from it into the ordinary graph, while
orbit split and polarization retain separate exact+C3 banks.  Transient GPU
build, launch, or malformed-output failures use bounded exponential epoch
backoff and retry instead of permanently erasing a role from the portfolio.

C3 was not globally best.  The 5×5 and 6×6 campaigns show that it is a useful
structural branch, while recent milestones came from mixed CPU exploration and
cooperative SIMD.  The d2502 mixed-CPU successor happens to return to C3
closure, but that does not make the C3-only lane universally best.  Therefore
3×3/4×4 assign no default C3 lanes from their asymmetric record seeds, 5×5
assigns 12%, and 6×6 assigns 6%.  A new Metal C3 engine preserves closure at
every quotient flip and any-axis plus move.  A real 5×5 smoke ran 6,400 attempts at
about 188k steps/s and passed independent exact+C3 gates; a real raw-i64 7×7
smoke also passed.  The C3 branch keeps its own rank-then-density leader even
when the ordinary global leader is sparser.  C3 walking, orbit split, and
polarization now fail closed through distinct C3-base/orbit/polarization banks.
In the all-role 5×5 smoke their launch seeds were independently exact and
C3-closed at ranks 93, 98, and 100 respectively, rather than three aliases of
one generic leader.

The cooperative SIMD engine is a bounded relaunchable FlipFleet role using
scan lookup through 5x5 and hash lookup at 6x6/7x7.  The separate checked-in
pure-Tungsten MITM engine performs Metal pair enumeration and complement probes
for bounded 5→4 surgery, then exact-verifies the local identity and complete
spliced scheme.  Its planted 3×3 smoke produced an exact rank-27 output.  The
native coordinator retains 5→4 inside role 10's pool and adds exact planted
6→5 and 7→6 pair/triple joins.  Every fourth pool launch is forced rotation;
the others use contextual UCB by tensor and rank debt.  A 64-cell MAP-Elites
archive supplies structurally distinct pool seeds, and one CPU control freezes
a consensus core while walking only an n²-term fringe.  Build or launch
failure is reported as degraded coverage.

### 2026-07-12: CPU islands keep different doors

The follow-the-leader policy was too aggressive for the CPU fleet.  The old
native driver reset every explorer to one leader every 3M moves; by contrast,
the persistent-island audit retained 42 exact rank-23 schemes in ten seconds,
and an eight-slot max-min sample had minimum raw term-set distance 34.  That is
evidence for preserving basin diversity, not for sending every thread through
the same seed after each improvement.

CPU walkers now receive sticky, tensor-specific roles across rounds:
leader exploitation, separated-frontier replay, exact best+1 and best+2
shoulders, one-move C3 exploration where eligible, mixed algebraic escape, and
the original anchor.  A strict rank drop can migrate one leader/frontier lane;
it leaves the other doors alive.  Frontier doors use separated archive replay;
the separate anchor door already preserves the campaign start.  The 4x4 mix
deliberately gives more slots to +2
shoulders because exhaustive single-split closure at rank at most 48 only
returned to the isolated rank-47 component.  C3 is a minority branch for 5x5
and 6x6, not a universal CPU policy.

The default walker count is now hardware-derived. A July 12 sweep on the
18-core M5 Max measured the default mixed profile at 438M, 517M, 569M, and
567M CPU moves/s for J=10,12,14,16 respectively; J=14 (`active CPUs - 4`)
keeps the best aggregate rate while leaving room for Metal compilation, GPU
host command encoding, MITM hashing, the coordinator, and the OS. CPU-only
peaked at J=16, so `--no-gpu` uses `active CPUs - 2`. Explicit `-J` remains
authoritative. A strict drop migrates one leader/frontier island by default;
the rest keep knocking on their assigned doors.

### 2026-07-13: the 4×4 frontier has two inequivalent rank-47 orbits

The previous 4×4 fleet initialized every record-rank island from the sparse
AlphaTensor representative (`d450`).  The Kauers--Moosbauer scheme distributed
with `jakobmoosbauer/flips` at commit
`e31a0a0f0d2577cee5da047ca7dcae0c61992e40`
(`solutions/444-47-mod2.exp`) converts to an independently exact GF(2)
rank-47 scheme of density 677.  The conversion uses row-major bits for A and B
and transposed row-major bits for the output factor, matching FlipFleet's W
convention.  Both the native exhaustive gate and an independent sparse parity
reconstruction recover precisely the 64 matrix-multiplication coefficients.

This is not merely a dense relabeling of the existing seed.  The two schemes
share no complete terms (raw term-set distance 94), and their unordered triples
of factor-matrix ranks differ: the Flips scheme contains `(3,3,3)` and
`(1,3,4)` terms absent from the AlphaTensor scheme, while AlphaTensor contains
`(1,1,4)`.  Those triples are invariant under independent GL(4,2) sandwich
actions and axis permutation, proving that the seeds lie in different such
orbits.  Both are now exact-gated into the frontier archive, and the canonical
12-worker 4×4 profile assigns one CPU frontier island directly to the distant
orbit; MAP-Elites, parent differential, and GPU pool selection can draw from
both.

The two local closures are also quantitatively different.  The d450 record has
165 complement-present one-split starts and 3,210 states in the canonical
rank-at-most-48 ordinary-flip closure; d677 has 150 starts and 2,139 states.
Neither closure reaches rank 46.  Moreover, the tensor-signature matrix of the
94 terms in `d450 Δ d677` has rank 93, hence nullity one: its only zero
dependency is the complete 94-term difference.  No proper raw parent-difference
subcircuit exists at any size.  Differential surgery should therefore consume
evolved descendants from MAP/archive rather than repeatedly matching the two
untouched endpoints.

As of this audit the rigorous interval over GF(2) remains
**34 ≤ R(⟨4,4,4⟩) ≤ 47**.  The lower endpoint is
[Bläser's arbitrary-field](https://arxiv.org/abs/cs/0201001)
bound `2mn + 2n - m - 2`; no stronger published GF(2) certificate was found in
the audited literature.  Public AlphaTensor, Flips, matmulcatalog, and
FastMatrixMultiplication assets expose only these two rank-47 schemes, although
[Kauers--Moosbauer](https://arxiv.org/abs/2212.01175) report generating more
than 100,000 such schemes.  A global
rank-46 UNSAT attempt is not a credible short campaign—the existing encoder did
not solve even its known-SAT rank-47 control in 280 seconds.  Raising 34 needs a
certificate-producing substitution/stabilizer engine; the current GPU
contraction and XOR-SAT modes remain scouts and must not report a miss as a
proof.

### 2026-07-13: 988.5-billion-move two-basin 4×4 campaign

The first long hardened profile completed normally after 9,002 seconds and
988,501,306,802 fleet-reported moves (109.809M/s average).  It remained at the
exact rank-47/density-450 frontier, retained both exact rank-47 parents and full
32/32 rank+1/rank+2 banks, reported no degraded GPU epoch, and admitted no
inexact coordinator candidate.  It did not find rank 46; this is a search
negative, not a lower bound.

The terminal traces confirm genuine parent diversity.  Generic split launched
977 epochs from d450 and 976 from d677; archive novelty used d677 in 1,952 of
1,953 epochs; and the rank lane returned exact descendants of both parents from
26 shoulder densities.  Pool escapes returned 3,428 verified d450 and 614
verified d677 schemes.  The plateau therefore cannot be explained by every
lane following one leader.

Six generic pool walks did reach an internal *nominal* rank 46, but full tensor
verification failed, their worker `global_best` remained unset, and the
coordinator never saw or admitted them.  They are not records.  The old logs
did not retain enough seed/candidate/nonce state to replay those failures.  The
next-build instrumentation now freezes raw seed and candidate files, worker
round, physical-slot launch nonce, and a compact exact syndrome for every
nominal-at-target rejection before the slot is reused.  Such candidates remain
ineligible for admission and reward.  Dedicated density completed 1,953 epochs
without beating d450; the defect/substitution/XOR-SAT scout family also returned
no useful 4×4 candidate.  The 4×4 pool now keeps a 128-lane constraint floor in
a 1,536-lane epoch and water-fills the released capacity toward high-debt
generic escape and exact surgery, the only family that approached the target
even nominally.  Other tensor profiles retain their previous allocation.

Higher-rank waypoints are no longer discarded.  Exact best+1 and best+2
schemes from synthesized identities and native workers enter bounded near-rank
banks without changing the rank-then-density leader.  Admission limits each
label-independent factor-reuse signature, term-set distance keeps the retained
sample separated, and restarts prefer least-used slots.  A returned
improvement is attributed to its shoulder source for campaign telemetry.  When the best rank drops, the bank
rebases around it, carrying the old frontier forward when it becomes a useful
shoulder and reclassifying still-relevant seeds.  Distinct C3-base, orbit-split,
and polarization banks contain the exact C3 anchors and constructions; every
entry passes tensor and closure gates.  They are separate because those identities
normally cost more than two ranks.

Work-zone and wander-zone dwell times are independently tuned native profiles.
The earlier record override accidentally made a deep 10B cohort also spend 10B
in every high wander band.  Four sticky pairs per tensor now range from
`25m/6.25m` through `2.5b/250m` at 3x3, `50m/12.5m` through `5b/500m` at 4x4,
`100m/25m` through `10b/1b` at 5x5 and 6x6, and `200m/50m` through `20b/2b` at
7x7 (work/wander).  The shorter wander quota matches its twelve-band jumps and
allows faster basin turnover.

Rank alone was not enough to audit that turnover: every row could say `r93`
while holding either twelve distinct schemes or twelve copies of one scheme.
The native TUI now shows a live term-set digest and distance from the fleet
leader on every CPU row, plus active unique/minimum/mean distance statistics.
The 5×5 verification run held 12/12 distinct live term sets with minimum raw
distance 14–20 even though all personal-best ranks displayed 93.

Startup diversity is also concrete rather than synthesized only from one cost
leader. FlipFleet exact-loads all checked-in same-rank schemes (six at rank 93
for 5×5, including seeds at distance up to 186 from d1155), admits them to the
max-min frontier/MAP archives, and selects each door by least use then maximum
distance from active islands. Novel equal-frontier CPU returns now enter the
raw-distance archive just like GPU returns. Short and balanced doors receive a
separate one-work-plus-one-wander basin lease; high-band and marathon doors
retain their deep multi-wrap leases.

The native `cal2zone2` processes also stopped using phase shifts of one 31-bit
LCG sequence.  Its 2^31 period was shorter than a multi-billion-move work
dwell.  A process seed now chooses an odd-increment LCG modulo 2^63; with the
PCG multiplier congruent to one modulo four, each parameterized stream has
full 2^63 state period.  Selection still uses a 31-bit high word to keep the
existing overflow-safe multiply-high mapping.  Worker logs expose the stream,
and a sawtooth wrap changes to a new odd increment.  The change is confined to
the standalone `cal2zone2` process used by FlipFleet; other generator modes and
the embedded worker source remain byte-stable.

Why not GPU SAT now: the current 4×4 large-k surgery model failed to solve even
the known rank-47 SAT control in 280 seconds.  A GPU SAT/XOR solver would be a
new solver project, while exact-basin portfolios reuse the already measured
11.6× threadgroup-memory kernel and diversify it at essentially zero hot-loop
cost.

All of the preceding live scheduling, banking, escape construction, exact
gates, adaptive allocation, C3/SIMD/pool launches, retry policy, and TUI state
are implemented in Tungsten (with checked-in Metal kernels).  Python miners,
generators, and SAT experiments remain offline evidence/reproduction tools;
they are not subprocesses or control paths of `flipfleet.w`.

- **`flipgraph_gpu_tg.w`** (device-mem baseline is `flipgraph_gpu.w`):
  caching each walker's scheme in on-chip threadgroup shared memory
  (`gpu.shared_i32`, coalesced layout `sus[term*32+ltid]`) instead of device
  memory took a 4096-walker × 120K-step dispatch from 93s → 24s → 8s
  (~11.6×). The two levers: gate the O(rank²) duplicate-check to every 8th
  step (93→24s; zero-check must stay every step — it's the main reduction
  mechanism), then move to threadgroup memory (24→8s; thread-*private*
  arrays were slower — too big, register spill + occupancy loss).
- Sidecar `.metal` emission gotcha: it emits alongside whatever
  `TUNGSTEN_LL_PATH` points at (not `--ll`, which returns before emitting);
  the host reads it back via `read_file`.

### Latest addition: `cal2zone` schedule ported to GPU

Built `flipgraph_gpu_cal2zone.w` — same threadgroup-memory kernel design,
but with the actual `cal2zone` band-escalation schedule (see below) ported
to per-GPU-thread state, replacing an earlier margin/leash heuristic and a
separately-tried best-of-N candidate-scoring variant. Findings from that
detour, kept here so they aren't re-discovered the hard way:

- **Best-of-N candidate scoring (O(rank²) per step) was a dead end on GPU.**
  Scanning every candidate and scoring by pressure (the Phase-0-validated
  CPU technique) works on CPU because a single thread doing extra work per
  step is cheap; on GPU it cuts the achievable step count by ~64× for the
  same wall-clock budget, starving the schedule of the raw step volume it
  needs to ever escalate past the first couple of bands. Reverted to plain
  first-found selection (O(rank) per step) — the GPU's actual edge over a
  CPU fleet is parallel *breadth* (thousands of independent attempts), not
  smarter per-step choices.
- **Duplicate-check optimization hypothesis was empirically wrong.** Tried
  replacing the periodic O(rank²) all-pairs duplicate scan with an O(rank)
  check of just the 1-2 slots touched that step (a duplicate can only newly
  appear at a just-modified slot — sound reasoning) done every step instead
  of periodically. Measured: removing duplicate-checking *entirely* gave
  the *same* round timing as the original design; the new "optimization"
  was if anything marginally slower. Duplicate-checking was never the
  bottleneck at these rank sizes (O(rank) per step for the candidate scan
  and the zero-check dominate). Kept the new version anyway — it's more
  *correct* (catches duplicates the same step instead of letting `rank` sit
  wrong for up to 64 steps), just not a speed win. Worth revisiting a real
  hash-table (O(1) amortized, matching what the CPU side already does via
  hash chains) only if this becomes the actual bottleneck at larger sizes —
  it needs more shared memory, which is already the tight constraint here.
- **Re-seeding cadence vs. schedule persistence.** The relay design re-seeds
  every GPU thread from the CPU fleet's current-best file every round. If
  the schedule's own state (current band, self-calibrated threshold, cycle
  counter) also resets on every re-seed, it never gets far enough to
  escalate past band 1-2 in a short round. Fixed by separating "refresh the
  working scheme" (every round) from "reset the schedule state" (only ever
  via the schedule's own internal trigger) — a `firstinit` flag distinct
  from `doinit`, with schedule state persisting in the device `st` buffer
  across dispatches.
- **A verification-gating bug produced a phantom "better than the current record"
  reading twice** (GPU log briefly showed rank 22 for 3×3, below the current
  rank-23 record, and separately rank 46 for 4×4 below 47). Root cause: the
  displayed running-minimum (`globalbest`) was updated *before* the
  correctness check ran, not gated the same way the actual write/report
  path is. Confirmed harmless both times — nothing was ever written to the
  shared best-file or communicated to the CPU side, since `verify_buf`
  silently rejects the bad candidate (some GPU thread's rank counter
  occasionally reports a too-low value that doesn't correspond to an actual
  valid decomposition, at a low but nonzero rate — contained by
  verification every time observed, root cause not yet tracked down).
  Fixed the display gating; the underlying rare bad-counter case is worth
  root-causing if it recurs at a rate that matters.

## Performance engineering (CPU walker)

- **Bucketed hash-chain core** (`bucket_gen.py`): replaced every O(rank) or
  O(rank²) linear scan (partner-find, duplicate-check, pressure) with hash
  chains (three doubly-linked chains keyed by u-/v-/w-mask; free-list slot
  reuse; dense LIVE array for uniform random pick). This was the single
  biggest walker throughput lever: **3M → 47M moves/s** (~15×) at rank 250,
  further tuned to ~56M moves/s.
- Mixed raw-ABI calling convention (typed-array params + raw scalars) killed
  most remaining `w_int`/boxing churn at call boundaries.
- Explicit `-> f(...) (types...) ret_type` return-type declarations on
  generated functions avoid inferred-nil return types that would otherwise
  box every consuming operation.
- **OOM lesson**: compiled Tungsten binaries have no GC — `TUNGSTEN_FREE`
  only frees provably non-escaping values, so any per-move escaping
  allocation leaks linearly. A 17-walker fleet OOM'd a 128GB box in 26
  minutes this way (wide masks ≥2^47 boxed a heap bigint per flip, never
  freed). Before any long fleet run, measure one walker's RSS slope for 60s
  and make sure slope × walker-count × planned-hours stays well under RAM.

## The `cal2zone` CPU schedule

Erik's spec, implemented in `bucket_gen.py`'s `adaptive_esc="cal2zone"` mode:

- Every walker starts at **band 1**.
- **Work zone** (band ≤ `wthr`, starting at 7): escalate +1 band every 2B
  moves.
- **Wander zone** (band > `wthr`): escalate +12 bands every 500M moves.
- Past band 60: sawtooth back to band 1 (a "cycle"). Two full cycles with no
  descent → fresh RNG, and (if the run started from naive) a full reset of
  the working scheme back to naive.
- `wthr` self-calibrates **up-only**: any descent sets
  `wthr = max(wthr, descent_band + 1)`.
- Any descent resets that walker's band back to 1 immediately — successes
  reset to cheap/tight exploration; only being *stuck* earns a walker the
  right to wander into expensive high bands.

Run architecture: 18 CPU walkers (this schedule) + one GPU cal2zone kernel,
all re-seeding from a shared coordinator's current-best file each round
(`relay_coordinator.py`), sequenced 2 hours per format
(3×3×3 → 4×4×4 → 5×5×5 → 6×6×6) by `overnight_orchestrator.py`. Every
walker/GPU thread that matches or beats the known record for its size saves
its full decomposition to `benchmarks/matmul/metaflip/records/<format>/`
(never overwriting — multiple distinct record-rank decompositions accumulate
per format, since same-rank schemes can still differ structurally).

Early results this run: 3×3×3 confirmed 23 within a minute; 4×4×4 confirmed
47 within ~9 minutes; 5×5×5 in progress. GPU has not yet landed a genuine
verified win over the CPU fleet in this configuration (consistent with the
"throughput isn't the lever, and best-of-N isn't worth its per-step cost on
GPU" findings above) — it correctly rides along and re-attempts from
whatever the CPU fleet finds.

## Auxiliary datasets

- `sweep_shape/{r3,r5,r5best}.csv` + `slot{,5}.sh`: an earlier (2026-07-03)
  band-calibration sweep — bands 1-30 × 16 seeds each on 3×3 and 5×5,
  recording rank-found per (band, seed). Rescued from `~/.mmwork` (no
  previous durable home). Informed, but is not identical to, the later
  `cal2zone` band-zone design above.
- `matmul_5x5_rank93_gf2.txt`: a verified, independently-found rank-93
  decomposition of ⟨5,5,5⟩ over GF(2) (predates the record table correction
  above but the rank-93 finding itself was never in question).

## 2026-07-05 (evening): three new levers — two structural negatives + a tool gain

After the 7/5 rigidity pass (frontier schemes locally rigid; ⟨4,4,4⟩=47
flip-isolated, ⟨5,5,5⟩=93 flip-poor), three genuinely-new levers were built and
run in parallel. None broke a wall (both remain open world records), but two
produced *structural* negatives deeper than "the fleet plateaus," and one
improved the C3 tool. Live confirmation of the walls on the current files: the
47 has **0** flip-eligible pairs (47/47 terms mutually isolated, 0 reduction
pairs); the 93 has **14** flip pairs (74/93 isolated).

### Flip-richness-seeking search — FALSIFIED (the key result). DO NOT re-run.

Hypothesis: the search has only ever minimized (rank, then bits), never flip-
CONNECTIVITY, so it dies in flip-poor corners; an energy `E = rank + λ·(#flip-
isolated terms)` should steer to flip-rich 93s where a descent channel to 92
exists. Python prototype (`scratchpad/flipsearch.py` + `e*.py`), every scheme
exact-validated (`recon==T`):

- **0 reducible pairs (direct 93→92 channels) across ~1.71M rank-93 states**
  inspected, INCLUDING the maximally flip-rich ones. A 93→92 reduction requires
  a pair sharing 2 axes; one never appears. 160-dive aggregate min-rank
  distribution {93: 102, 94: 39, 95: 14, 96: 5} — none below 93.
- Enrichment is real but marginal (lateral flip-walk raises flip-pairs 14→19,
  lowers isolated 74→69) and lives ABOVE 93 (rank 95: ~29 pairs; rank 105: ~48).
  It does NOT survive the dive: enrich-then-dive from the richest rank-105 basins
  (48 pairs) still collapses to a channel-free 93 (~19 pairs). The reducer is
  proven working (105→93 in 12 consecutive valid reductions) — then stops dead.
- `E = rank + λ·isolated` never beats rank-only (both reach 93, neither 92, no
  winning λ ∈ {0.05, 0.1, 0.25}); iso-greedy steering ≈ uniform.
- **Meaning within the 1.71M sampled reachable 93s: none was one reduction from
  92.** This is why every
  from-93 push (incl. the earlier 54.6B-move seed-92 run) and every from-naive
  descent failed; the sampled rank-93 level set is channel-free, and
  flip-richness did not manufacture a channel. This is strong structural evidence
  against the tested flip + plus + reduction policies, not an exhaustive graph
  proof or a tensor-rank lower bound. (Scope: does
  not cover the cross-format extend/project edges — already "mis-aimed" for
  squares per the meta-flip README.)

### C3-symmetric FROM NAIVE — any-axis plus-transition: 102 → 97 (tool gain)

`sym_gen2.py`'s C3 quotient walker run from the naive rank-125 scheme on 5×5
(the from-naive symmetric descent had never been cleanly run before — prior C3
runs were seeded ON the flip-poor 93):

- W-only plus-transition (original) floors at **102**; generalizing the plus to
  a random U/V/W-axis split floors at **97** — a clean 5-rank gain, exactly
  validated (`recon==T`, C3-symmetric). New tool: **`sym_gen2_anyaxis.py`**
  (only `gen()`'s plus differs, 33 lines).
- **97 is a hard floor** (recorded 3395×, rank 96 never appeared once; robust
  across bands {2..120}, plusper {10k..200k}, marathons to ~600M moves/dive).
  naive→93 is a genuine MOVE-SET gap needing MP's exact algorithm, not tuning —
  consistent with the reduction-channel exhaustion above (even reaching 93 would
  not yield 92).
- **Band guidance is INVERTED for the C3 walker** vs the asymmetric one: tight
  bands 2–4 STALL at 122–125 (orbit-inserts move rank in steps of ~3, so a tight
  band resets before any plus-excursion can explore); **large bands 15–40 are
  optimal**. The sawtooth schedule stalls at 125 from naive (tiny start-band +
  huge escalation quanta never reach a productive band).

### Large-k SAT surgery for ⟨4,4,4⟩→46 — k=5 all-UNSAT (long-shot, live)

Extended the validated k≤4 `sat_surgery.py` to k=5–8 with guided subset
selection (smallest joint support + factor-adjacency): new tool
**`sat_surgery_hik.py`** (--selftest passes; k≤4 UNSAT reproduced; a planted k=5
merge is found). A k→(k−1) hit anywhere = rank 46. Also validated the *global*
rank-existence encoders (`sat_rank.py` / `sat_rank_cnf.py`, previously never
run): correct (z3 gives 2×2 rank-7 sat, rank-6 unsat) but **monolithic global
SAT is out at 4×4 scale** — cryptominisat5 could not find even the *known-SAT*
rank-47 in 280s (matches the literature: the analogous 3×3 rank-23 SAT cost
~35 CPU-years just to *find* solutions).

- **k=5 and k=6: all 3,628 guided subsets UNSAT** across the 3 sparsest 47s,
  zero timeouts (k=5 = 1,780: at_f2 687 + cpu16 532 + cpu10 561; k=6 = 1,848:
  676 + 559 + 613). Strengthens 4×4 local minimality from k≤4 to **k≤6** — no
  ≤6-term chunk of a known 47 re-decomposes with one fewer term.
- k=7–8 grinding as a deeper probe (beam 700–1000, perk 350–500, 45s/solve);
  coverage is beam-capped so these need not exhaust. The one live long-shot;
  a hit is the rank-46 record. *(Update with the k=7/8 verdict if/when it lands.)*

**Net:** ⟨5,5,5⟩→92 has substantially stronger negative evidence for the tested
flip-graph policies (the 0-channel sample supplies a structural reason); ⟨4,4,4⟩→46 remains a live
long-shot only via large-k surgery. New durable tools: `sat_surgery_hik.py`,
`sym_gen2_anyaxis.py`.

## Corrections (superseded claims, kept for context)

- "⟨7,7,7⟩ = 250 is the GF(2) record" — **wrong**. Sedoglavic's identity plus
  the GF(2) 47/29/38 leaves gives 248 exactly; see the record-table note.
- "5×5 record is 95" / "94 is the barrier" — an earlier session's
  literature check found 95/94 based on an incomplete record lookup; the
  verified, corrected record is 93 (Moosbauer-Poole), reflected in the table
  above. Anything referencing "95" or "94" for 5×5 elsewhere in old session
  logs is from before this correction.

## 2026-07-12: CPU and Metal profiling audit

A 12-walker 5×5 mixed-profile run sustains roughly 475–500 million CPU moves/s
while the GPU portfolio is active. A five-second process sample is dominated
by the intended inner operations (`ffw_try_flip_core`, `ffw_toggle`,
`ffw_pressure`, and algebraic-seed adoption); allocation, scheduling, and
coordinator work are negligible in the CPU workers.

An Instruments Metal System Trace covering all child workers recorded 6.06 s
of FlipFleet GPU work in a 10.64 s span (57% fleet occupancy; the whole system
GPU was active 69.5% of the interval). Most active time was at the maximum GPU
performance state and Metal reported no command-buffer errors. The trace did
identify two sources of avoidable latency rather than bad shader work:

- short-lived child processes compiled about 825 ms of MSL during the
  ten-second capture; persistent workers or checked-in metallibs are the next
  startup/rotation optimization;
- the 5→4 MITM Metal enumeration/probe passes are short, while its exact
  collision-preserving host table build costs about 0.34 s per 362-candidate
  subset. Long multi-subset epochs should therefore be treated as a rotating
  surgery probe, not a continuously saturated GPU lane.

The audit also caught a real host fault in the experimental 7→6 XOR join.
Its shared hash table was allocated as packed `u32` storage but an insertion
helper declared it as `i64[]`, so optimized host indexing used an eight-byte
stride and eventually crossed the mmap. The table is now one packed buffer,
the helper is explicitly `u32[]`, and the GPU receives the same packed layout.
Both planted 6→5 and 7→6 proofs pass, as do 20 sequential stress runs, eight
concurrent real 5×5 workers, a 30-second mixed 5×5 run, and GPU smokes for
3×3, 4×4, 6×6, and 7×7. No degraded status, process fault, command-buffer
failure, or exhaustive-verification reject appeared after the correction.

## 2026-07-13: live circuits, parent differentials, and staged large-k joins

The rotating pure-Tungsten pool now extends the small exact-surgery family in
three independent directions.  A Metal pair/triple or triple/triple join mines
five- and six-term zero signatures from the live factor closure.  A hit is not
trusted as a circuit merely because its 128-bit projection vanishes: the host
reconstructs the complete tensor and every nonempty proper subset, then
exhaustively verifies the scheme produced by toggling the primitive identity.

A separate bounded CPU child uses the symmetric difference of two distant
exact archive parents.  It hash-joins a primitive five-circuit and chooses the
orientation with the most terms already in parent A, producing an exact hybrid
when possible.  The scheduler caps this mode at one process/one logical
quantum; it is a diversity probe, not a new CPU fleet.  A planted distance-10
pair produced a third exact rank-27 3×3 scheme from two rank-32 parents.

Finally, the XOR worker now stages 8→7 as a triple/quad join and 9→8 as a
quad/quad join.  Regular count⁴ tuple enumeration runs on Metal while the
candidate family is capped at 16.  Full local and whole-scheme reconstruction
remain the admission gates, so these bounded searches do not imply local or
global lower bounds.  Planted 6→5, 7→6, 8→7, and 9→8 regressions all recover
the exact rank-27 parent from a rank-28 split seed before the new modes become
campaign-ready.

## 2026-07-13: persistent GPU path and bounded CPU search experiments

The startup cost identified by the July 12 Metal trace is now addressed in
the production path.  FlipFleet compiles emitted Metal to freshness-checked
`.metallib` files before an engine becomes ready.  Stable generic square and
rectangular roles additionally retain one worker process, Metal device,
library, pipeline, queue, and buffer set across default one-round epochs; a
generation-numbered mailbox supplies each new exact seed and bounded command.
C3, cooperative SIMD, and rotating-pool workers remain bounded processes but
load the cache.  Tiny 3×3 launch controls measured about 122 ms per
source-compiling child, 64 ms per cached child, and 15–19 ms per persistent
command (19 ms in the latest integration sample).  This closes most of the
rotation gap; it does not change shader move throughput.

The primitive miner has one live-frontier positive: from the exact 3×3
rank-23/density-139 scheme it emitted an exhaustively checked rank-29 alternate
escape.  The parent-differential and large-k positives remain planted
regressions: exact rank-32 parents at distance ten produced an exact rank-27
hybrid, and planted 8→7/9→8 joins recovered rank 27 from rank-28 split seeds.
Those controls establish that the implementations can find and splice their
intended identities.  They are not world-record improvements, local
minimality results, or tensor-rank lower bounds.

A separate equal-compute 6×6 comparison tested the stronger six-image
C3×Z2 constraint (historically named D3 in this tree).  Four trials per arm,
128 walkers × 5,000 steps each, left every C3 and C3×Z2 run at rank 153.  C3
took 4.671 s for the combined 2.56M configured transitions; C3×Z2 took
7.963 s, about 59% of C3 throughput, and did not improve density 2502.  The
worker is therefore retained as a standalone experiment, not a default role
or rotating-pool member.  Neither symmetry arm found rank 152.

Search diversity is now measured with a 62-bit canonical orbit digest across
the six tensor-axis automorphisms and simultaneous index reversal, augmented
by sorted factor-matrix-rank histograms as a cheap GL invariant.  Equivalent
images share a bank/MAP/lineage identity.  This digest is telemetry only;
exhaustive tensor reconstruction remains the admission gate.  A persistent
256-entry provenance registry carries direct-GPU, pool-mode, and rectangular
origins through bank copies and CPU continuations.  The first exact CPU
descendant can return delayed credit for rank reduction, same-rank density,
and canonical novelty to the originating role and context; return to the
origin basin is recorded as a separate hazard.

Two deliberately bounded CPU lanes test changes without perturbing the rest
of the sticky-door fleet.  One races eight work/wander, split-cadence,
pressure, and band-growth arms, cold-rotating every arm before using rank drop,
canonical novelty, and return hazard as integer utility.  A different island
observes accepted-state recurrence with a rolling Zobrist digest and a
512-entry direct-mapped recent filter.  On the 5×5 density-1155 seed, a 20M
move comparison measured 36,900,369 moves/s baseline versus 37,174,721 watched
(0% overhead at integer resolution). A final-audit rerun beside the live 7×7
campaign measured 29,940,119 versus 29,542,097 moves/s (1%). Both observed
871,604 unique fingerprints, 69,331 recent-filter hits, and 55,574 immediate
inverses. The apparent speed gain in the first sample is noise: the useful
result is 0–1% observed overhead while one lane quantifies reversible cycling.

The complete design and evidence classification are in
[`FLIPFLEET_SEARCH_EXPERIMENTS.md`](FLIPFLEET_SEARCH_EXPERIMENTS.md).  None of
these nine additions has yet changed a rank upper bound or rigorous lower
bound.

## 2026-07-14: complete nullspace tunnels and rank-changing map audits

The 7×7 rank-247 frontier has exact escape edges far beyond the old bounded
partial-automorphism enumerator. Complete elimination of each elementary
automorphism's `n^6` delta rows produced 155 genuine basis endpoints. Closing
projected directions through depth four produced 1,040 graph-unique exact
nodes, including two rank-247/density-3098 schemes with no terms in common
with the source (distance 494, the maximum possible). Both are checked-in
frontier seeds. A retained-workspace finder returned a genuine endpoint for
all 189 rotated starts in 39 ms mean / 58 ms p95, so FlipFleet now runs it as
a low-cadence coordinator escape rather than consuming a CPU or GPU lane.

Several plausible rank-changing generalizations were also closed cleanly.
Raw one-factor maps covered 7,056 complete kernels; paired raw maps retained
the bilinear cross term and covered 5,760 kernels over fifteen presentations.
Every real-frontier dependency was an individually fixed singleton, although
the paired planted control recovered Strassen rank 11→7. A zero-admitting
whole-window kernel-shear closure exhaustively tried up to 131,054 dependency
combinations, correctly recovered a planted Strassen 8→7 drop, but found no
drop on the 4×4–7×7 leaders or their tested alternate presentations. These
families stay offline; their negative results prevent wasting live pool width.

The corresponding production startup was also profiled rather than guessed.
Loading and full-gating the ten 7x7 profiles cost 314 ms, directed global
isotropy 357 ms, and the leader escape family 213 ms; eagerly expanding every
frontier escape cost 89,207 ms by itself. FlipFleet now freezes one exact
archive snapshot per rank generation and rotates one source/kind/nonce cell
per minute through a finite `source_count*5*6` schedule. Fifty calls averaged
24 ms (p90 41 ms, maximum 52 ms), and the default exact 7x7 startup smoke fell
to about 2.3 seconds. The TUI renderer was not changed.

A simultaneous coloured extension assigned each source term one of
`identity`, `g`, `h`, or `hg`, then solved the complete delta nullspace with an
explicit one-colour constraint. Across seven real frontiers, 28 generator
pairs, 112,638 kernel vectors, and 86,764 fully compared sparse MITM hits, it
full-gated 5,475 endpoints with zero failures. All 604 quotient survivors were
staged compositions of binary partial-automorphism edges; none was genuinely
cross-colour and none improved rank or density. A planted genuinely coupled
rank-12 to rank-8 control passes, so this is a clean negative on the current
frontiers. It remains offline; the binary beam's distance-494 doors are
strictly stronger for production diversity.

## 2026-07-14: a second constrained lower bound for `<3,2,4>`

After permuting the tensor to `<2,4,3>`, the one-dimensional constraint
generated by a rank-two `2x4` form now has a rigorous GF(2) lower bound 19, up
from the verified search-certificate value 18. An independent audit expanded
all 86 certificate orbits to all 417,199 subspaces of `F_2^8`, rebuilt 28,480
capacity inequalities, and divided the residual by a 576-element stabilizer
into 46 disjoint pseudo-Boolean shards. All 46 were proved UNSAT and replayed
by VeriPB 3.0.2 with no assumption rules, warnings, or unjustified diagnostics.

At that checkpoint this was only a constrained lemma, not a global 20 lower
bound. It proved that every factor on the `2x4` axis of any hypothetical
19-term `<3,2,4>` decomposition must be rank one. Combined with the earlier
A-mode lemma, the remaining global case had 19 distinct rank-one `3x2` factors
and 19 rank-one `2x4` factors. The quotient-rank result immediately below
supersedes that claim boundary.

## 2026-07-14: quotient-rank proofs close `<3,2,4>` at rank 20

The claim boundary above has now advanced: the remaining six rank-one-A /
rank-one-B symmetry cases are all proved UNSAT, so

```text
rank_GF(2)(<3,2,4>) = 20.
```

The key necessary condition comes from reordering
`(x tensor y) tensor (p tensor z)` as
`(x tensor z) tensor (y tensor p)`. The twelve target slices span
`Q tensor <I_2>`. A hypothetical minimal 19-term presentation has nineteen
independent `A tensor B` columns—any dependence absorbs one `C` factor and
deletes a term—so quotienting the four-dimensional `y tensor p` factor by
`<I_2>` must leave rank exactly `19 - 12 = 7`.

Each fixed-B necessary instance received an exact 36-by-19 rank-at-most-seven
factorization `V=UL`, with the seven rows of `L` in RREF to remove the
`GL(7,2)` gauge. The six 7,529-variable / 86,487-constraint OPBs use untouched
bases, not Benders cuts. RoundingSat proved all six UNSAT. Their filtered
deletion-free logs total 1,248,204,428 bytes and all replay under VeriPB 3.0.2
in forced checked-deletion mode with exactly one UNSAT conclusion and no
warning, error, failure, unjustified step, or assumption diagnostic.

An independent audit rebuilt all six OPBs byte-for-byte, checked the three
missing-A by two fixed-B orbit cover, and tested fixed matrices of ranks zero
through seven as SAT and rank eight as UNSAT under two column orders. Formula,
proof, solver, checker, and source hashes are pinned in
`proof_n324/n324_quotient_rank_manifest.json`. The earlier 300-model Benders
campaign remains useful search history, but it is not part of the final six
proofs. Rank-drop search for `<2,3,4>` is consequently retired; rank-20 density
search remains meaningful.

## 2026-07-14: genuine D3 doors and distance-494 campaign controls

The transpose-aware tensor D3 maps expose exact edges that coordinate-index
cycles miss. Across all 29 tracked 4x4--7x7 frontiers and eleven nonidentity
D3-times-reversal maps, complete coefficient nullspaces examined 127,755
combinations. They independently full-gated 13,794 endpoints with zero
failures; 11,331 were proper partial moves and 10,132 lay outside the source
D3 class. No endpoint improved rank or density. Five independently reloaded
representatives were added as restart doors: one 5x5 rank-93 seed at source
distance 32, two 6x6 rank-153 seeds at distances 8 and 16, and two 7x7
rank-247 seeds at distance 216. Dense combination sampling revisited the same
canonical classes at roughly three to four times the 7x7 admission cost, so
generation remains an offline audit and only the exact endpoints enter the
live frontier.

The two one-core campaigns started from the term-disjoint distance-494 7x7
partial-automorphism doors then completed 60.491B and 61.074B moves. Both
finished at exact rank 247/density 3098. This is useful basin-specific search
evidence, but it is neither a local-minimality proof nor a rank lower bound.
Their freed slots were moved to the two D3-distinct rank-247 doors.

## 2026-07-14: Metal lanes for the two smallest primitive rectangles

The exact `<2,3,4>` and `<2,4,5>` campaigns now have dimension-specialized
pure-Tungsten/Metal cal2zone workers instead of silently falling back to CPU.
Their capacities/shared-memory geometries are 64/12,288 bytes and
80/15,360 bytes, both with sixteen walkers per threadgroup. The generated
host relays accept both public `R u v w` rows and FlipFleet rank-header
checkpoints, retain the bounded persistent-process lease, and reconstruct any
adopted candidate coefficient-by-coefficient.

Production coordinator campaigns exercised 4.25984B `<2,3,4>` transitions
from rank 20/density 130 and 2.4576B `<2,4,5>` transitions from rank 33/density 246,
with zero exact rejects. Neither found rank 19 or rank 32. These are finite
negative searches, not rank lower bounds; the value is that both primitive
field-gap targets can now consume the adaptive GPU budget directly.

## 2026-07-14: exact rectangular 5 -> 4 MITM surgery

The two primitive rectangular campaigns now also run a distinct bounded
5 -> 4 surgery worker. Metal enumerates and probes complementary candidate
pairs; the Tungsten host performs the complete local identity check and then
the rectangular worker independently reconstructs every coefficient before
publishing. A checked-in exact rank-21 `2x3x4` shoulder plants a split in its
first five terms; the end-to-end GPU test recovers rank 20 and reloads it
through the full rectangular gate. The existing square rank-28 to rank-27
planted control still passes.

The audit exposed a shared performance defect rather than a tensor bug. The
old 128-bit fingerprint hash discarded low bits from three words and produced
long linear-probe clusters. A full-word rotate-and-avalanche hash reduced the
planted pool-256 host table from 126 ms to 6 ms and a 16-subset `2x4x5`
pool-256 table from roughly 3.1--3.8 seconds to 85--130 ms. Native Metal and
metallib compilation pass with the exact `xcrun --find` toolchain.

The finite frontier sweep covered 1,248 `2x3x4` windows / 108,128,448 pair
enumerations and 1,312 `2x4x5` windows / 94,291,520 pair enumerations over
pools 128--700, nearby depths 0/2/4/8, and the full bounded offset windows.
It sent 3,660 and 54 fingerprint collisions respectively through the exact
local gate, with no rank-19 or rank-32 result and no exact rejection. This is
search evidence, not a lower bound. Production therefore keeps the lane
sparse: pool 256 for `2x3x4`, pool 384 for `2x4x5`, sixteen windows per launch,
rotating nearby depth and offset, every eight rounds in a single-shape run and
once per four-round portfolio epoch. Its counters live in status telemetry;
the TUI layout is unchanged.

## 2026-07-14: support-guided overlapping block parity

The planted overlapping-block identity has been extended into a bounded
real-frontier audit in pure Tungsten. It builds index-mask banks from live term
supports, complements, and bounded AND/OR/XOR closure, substitutes the lowest
rank exact rectangular algorithm available in the checked-in 2--8 leaf pool,
and hash-compacts each four-block zero macro. Twenty-two missing sorted
minimum-dimension-two shapes through size 8 are generated by fully gated
disjoint tensor splits; among them, 2x7x7 has rank 81. The exact term-set XOR rank is
computed before endpoint allocation; every retained full-block best and every
rank-neutral/lower endpoint then receives a complete tensor reconstruction.
The planted test injects a nonempty exact zero macro above the rank-47 4x4
scheme and the same bounded sampler recovers the original rank-47 endpoint.

All coordinate-singleton four-cycles are algebraic no-ops after compaction:
432 at 4x4, 4,050 at 6x6, and 9,261 at 7x7. The fixed singleton axis excludes
every non-schoolbook rectangular leaf. The wider-mask run used 32 masks per
axis, 512 deterministic samples per orientation, and a 32-macro pair-XOR
frontier. Full-block replacement was complete modulo coordinate permutation
because every mask cardinality was represented. Best fully gated full-block
ranks were 54 from rank 47, 165 from rank 153, and 257 from both rank-247 7x7
presentations. The corresponding best single/pair estimates were 54/61,
160/164, and 262/267. Neither 7x7 presentation shared a term with its best
local support macro; the best 6x6 macro shared four terms but still landed at
rank 160. No rank-neutral or rank-lowering endpoint was found, so the strategy
is not integrated into the live pool. The implementation, planted controls,
and reproducible 4x4/6x6/7x7 comparison are in
`flipfleet_overlapping_block_frontier.w`, its `_test.w`, and `_bench.w`.

## 2026-07-14: signed cross-field projections

An independent parser/gate audited pinned exact `{−1,0,1}` schemes before
using them as GF(2) starts. It reconstructs the integer tensor, reduces signs
modulo two, parity-compacts duplicate terms, transposes the trace-dual output
factor into FlipFleet's `W` order, and then reconstructs every GF(2)
coefficient. The two signed 5x5 rank-93 files are exactly the existing
Kauers-A and Kauers-B term sets. Both distinct signed 6x6 rank-153 files reduce to the same existing
C3 rank-153/density-2574 term set. Their nearest nonidentical zero relations
are respectively two and twelve independent ordinary 2-to-2 flips, while
their XORs with the density leaders are global distance-186/distance-306
relations with no independently zero exact-factor component. They add neither
a basin nor a move family.

The public ZT JSONs produced one useful shoulder but no record. The 7x7
rank-250/density-2966 projection is term-for-term identical to the already retained
old-frontier certificate. The 4x4 projection is a new exact
rank-49/density-432 presentation at orbit distance 96 from rank-47/d450. Its
96-term leader XOR has no independently zero exact-factor component, so it is
not a local tunnel. Complete 36-generator isotropy descent plus 256 conjugate
restarts found no density below 432. The full-gated certificate is retained as a cold,
file-backed +2 restart seed: coordinator startup/frontier rebuilds admit it
through the ordinary novelty/signature policy, with no new CPU/GPU lane and no
TUI change. Full source commits, hashes, commands, and negative boundaries are
in `SIGNED_PROJECTION_AUDIT.md`.

## 2026-07-14: separate exact ternary fleet

`flipfleet_ternary.w` is now a separate pure-Tungsten CPU/GPU fleet over strict
`{−1,0,1}` factors. It accepts `--tensor 4x4` through `7x7`, repeatable signed
six-mask `--seed` files, wall/move bounds, `-J`, and durable best/status paths.
Every distinct import and every published/final best receives the exhaustive
integer `n^6` gate. Its own Metal breadth engine is on by default and can be
disabled with `--no-gpu`; it does not touch the GF(2) coordinator, GPU policy,
or TUI.

Pinned public rank-49 4x4 and rank-250 7x7 ZT JSONs, plus rank-93 5x5 and two
genuinely distinct rank-153 6x6 expression seeds, were parsed and expanded by
an independent Python verifier before the pure-Tungsten import gate. Complete
source commit/blob/file/certificate hashes are in
`ternary_catalogue_sources.tsv`. Bounded two-island controls covered 55.1M
moves apiece at 4x4/5x5/6x6 and 60.1M at 7x7 with zero rank drops and zero
exact rejection. They found useful exact density doors at 5x5 (r93,
1291→1249) and 6x6 (r153, 2574→2502), now checked in and included in default
seed rotation. The 4x4/r49 and 7x7/r250 objectives did not improve; a 10M 7x7
control returned an exact r250/d3069 door at term-set distance 64. That door is
checked in and default-pooled, and the CLI now gates/archives up to sixteen
novel equal-rank returns instead of discarding them at shutdown.

The original one-hour CPU-only controls later completed at substantially
larger bounds: 13,683,163,136 moves for 4x4, retaining r49/d432, and
1,868,406,784 moves for 7x7, retaining r250/d2966. Both had zero exact rejects
and no rank drop. This is an honest finite negative result for the implemented
move portfolio, not a proof that either basin is globally infertile.

A subsequent exact shared-factor GL(3) closure improved the 5x5 endpoint once
more, r93/d1249→r93/d1248, and then exhausted all five genuinely three-way
ternary matrix/inverse orbits, six source orders, and eight source gauges to a
fixed point. The saved endpoint changes three terms (symmetric-difference and
tested tensor-symmetry orbit distance six) and passes the complete integer
gate. This particular density step is reachable by two legal pair flips, so it
is a shortcut rather than a new 5x5 component. The move nevertheless has a
separate planted subtotal whose legal pair-flip component is a singleton and
whose nontrivial GL(3) endpoint is exact and ternary, establishing genuine
tunneling capability. It runs at one probe per 65,536 ordinary signed moves;
4x4/6x6 strict controls are empty and all 252 public-7x7 endpoints are denser
by 8--20, so they remain wander doors.

A larger direct shared-factor GL(4) lane was rejected before implementation:
the maximum projective-factor bucket sizes of the pinned 4x4, 5x5, 6x6, and
7x7 objective seeds are 1, 3, 2, and 3. A four-term probe would therefore be
inert. `flipfleet_ternary_gl4_audit_test.w` keeps this negative executable.

The broader `flipfleet_ternary_span_refactor.w` removes that shared-factor
precondition. It exhaustively enumerates the strict signed generator span of
a selected three- or four-term subtotal, hash-joins candidate rank-one terms,
and coefficient-gates every modular match over the complete ambient integer
subtotal. Planted tests recover exact 3-to-2, disjoint 3-to-3, 4-to-3, and
external-cancellation 4-to-2 identities; a split Strassen shoulder also
splices from rank eight back to a fully gated rank seven. On real leaders,
however, 512 deterministic windows on each of six pinned 4x4--7x7
presentations produced no 3-to-2; 96 three-term catalogues produced no
disjoint 3-to-3; the same 96 collision windows represented no opposite external term;
and six complete bounded 4-to-3 joins (156,426,570 candidate pairs) were all
negative. The executable benchmark therefore remains offline and receives no
fleet cadence until a real endpoint supplies positive evidence.

The productive replacement is an exact global matrix-index isotropy in
`flipfleet_ternary_index_shear.w`. For an elementary unimodular
`P = I + sE_ab`, it applies P to one side of a contracted physical matrix
index and `P^-T` to the other. All affected terms are preflighted before
commit; every intermediate accepted endpoint and final factor remains in
strict `{−1,0,1}`, and both Tungsten and independent Python reconstruct all
`n^6` integer coefficients. This is normalization inside a known tensor
isotropy orbit, not a new local tensor identity or a claim about disconnected
components.

Deterministic steepest normalization takes 5x5 r93/d1248 to r93/d997 in ten
shears and 6x6 r153/d2502 to r153/d1938 in eleven. The endpoints share no
canonical term with their inputs (term-set distances 186 and 306). Their
certificate hashes are respectively
`ab41aa831a566d86a46fcfb52e4d4eafaae6131cb229501704a825b564ab0298`
and `610eadf30fd46004e6898bcb5d01e4776b0062e358af3e3fc39a47fcd101dde7`.
The 4x4 and both 7x7 seeds are strict-descent fixed points.

GPU breadth then compounded the normalized doors to 5x5 r93/d967 and 6x6
r153/d1931 in 8,388,608 attempts each, with zero integer-gate rejects. Those
certificates
(`d63c756fef192ea7b0fe78bdc5378f2eb3af0f8cf63e6d3fb7b9f8110701c407`,
`f58820f4b3c4f71f4a7fd5b2303e30fda382c352d3b059fed74a678072186c37`)
are themselves fixed points of
the complete shear descent. CPU admission normalizes deterministically while
the raw d1245 and other seeds remain available to GPU lanes for structural
diversity; the closure repeats only every 8,388,608 ordinary CPU moves, and
production never publishes arbitrary isotropy-orbit novelty. It admits at
most one non-recursive shallow positive shear (density debt at most eight) per
normalized fingerprint to GPU seeds only, then closes every gated GPU return
before archive/publication. A 9M-move
one-island smoke at both sizes fired the rare closure and finished with d967
and d1931, zero failures. Full GPU architecture and compound measurements are
in `TERNARY_GPU_ENGINE.md`; exact move, audit, hashes, and reproduction details
are in `TERNARY_FLIPFLEET.md`.

Two additional 6x6 feedback paths preserve basin diversity without changing
the objective leader. The distinct public Kauers seeds normalize to distinct
d2208 doors; GPU breadth reaches two distinct d2148 endpoints; three more
index shears reach two distinct d1953 fixed points. Dedicated 134,217,728-
attempt GPU continuations from each d1953 gated 32 changed exact basins with
zero rejects but stayed at d1953, so d1931 remains best. The durable d1953
certificate hashes are
`f0f06c9812ecdec7ca79ebd07a65f296dc044a32a433e0f845f0d60837aa760c`
and `a38623255e9e7269b0d1ab681a2a0b39a48f91d94b4c741d1a3bdda6a6f7fcdd`.

That bounded shallow policy found a real symmetry tunnel. The original 6x6
d1931 fixed point takes a legal +6 global shear to d1937; 134,217,728 GPU
attempts reached d1935; one deterministic closing shear then reached a second
d1931 basin at term-set distance twelve from the original. The d1935 and new
d1931 hashes are `78df6b6f0b08c82d737b3f1940f6442f85ab48e2f0a8550435cd0fe4aa05ef82`
and `39d8782dffd33b988447982bb13632553734da4c5c70b36148670645eeda3801`.
Another 134,217,728 mixed plus 134,217,728 downhill attempts from the new
basin gated 39 changed exact returns with zero rejects but no density below
1931. The 5x5 d974 shallow-door control likewise stayed d974 over 134,217,728
attempts. `flipfleet_ternary_seed_variants.w` now automates exactly this capped
one-door route, deduplicates it, never recurses it, and normalizes GPU returns.

An independent support-sign CP-SAT filter at FastMatrixMultiplication commit
`e0ec7db4cb7d7ca41abbb2c6e3bd8c7de75c7c64` accepted the public 4x4/r49 ZT
shadow, but reported both saved GF(2) r47 supports and all saved 7x7 r248/r247
supports infeasible for strict ternary signs. This is an audited computational
filter, not a formal UNSAT proof. Reproduction commands, timings, scope, move
identities, and remaining optimization work are in `TERNARY_FLIPFLEET.md`.

Signed archive differences now have their own exact tunnel. A collision-free
six-mask union, dual-prime stacked weighted-Gram rank certificate, and full
integer basis gates found 6,228 proper exact splices across nine close 5x5,
6x6, and 7x7 lineage pairs. Complete disjoint relation cubes prove all of them
rank-neutral. Twelve representative children were distinct from both parents;
five improved their own density in matched one-million-move continuations, but
none beat the sparser parent and none dropped rank. The move therefore remains
an offline or low-frequency archive-cadence option rather than a default lane.
The proof-safe screen, 9.46-second audit, and replay commands are in
`TERNARY_PARENT_NULLSPACE.md`.

## 2026-07-14: external-cancellation completion of local refactors

Several local replacement paths had the same GF(2) admission bug: they
rejected a replacement term if it was already live outside the selected
window. Such a collision is useful, not invalid, because the two copies
cancel. A nominal local 3-to-4 replacement with one external collision is a
global rank-minus-one move; a local 3-to-3 replacement with one collision is
global rank-minus-two.

The span-3/span-4 Metal join now searches collision-containing presentations
before generic hits, parity-compacts the full symmetric difference, scores
the actual global rank, and reconstructs the complete tensor before reward or
publication. The same compact splice semantics now cover flattening-gauge,
absorbed low-rank shear, and SAT destroy/repair. Planted regressions recover
rank 23 from exact rank-27/28 3x3 shoulders through nominally neutral or
rank-minus-one local substitutions with external cancellations.

The real-frontier audit covered 7,334 independent tensor/cardinality/offset
jobs over current 4x4--7x7 leaders, every retained rank-optimal 4x4/5x5
presentation, and seven structurally distant 6x6/7x7 archives. It found zero
external-collision hits and zero exact failures. The corrected search remains
enabled at low priority because it closes a genuine completeness hole, but it
has not earned a larger live allocation on the present basins.

## 2026-07-14: reusable inner-dimension-two proof campaign

The quotient argument that closed `<3,2,4>` now has a tensor-generic proof
package for every GF(2) `<a,2,c>`. Regrouping the first two factor spaces gives
`Q tensor R` with `dim(Q)=a*c` and `dim(R)=4`; exactness forces the target
slice space `Q tensor <I_2>` into the term-column span. Therefore every
rank-`r` decomposition must satisfy

```text
rank(pi(S)) <= r - a*c
```

after quotienting `R` by `<I_2>`. This condition does not assume that the
displayed adjacent factors are rank one. Both native-XOR XNF and OPB encoders
enforce the complete tensor equations and an exact low-rank factorization of
the quotient matrix, with an RREF gauge to remove its `GL` symmetry.

For a hypothetical rank-32 `<5,2,4>` decomposition, cyclically equivalent to
`<2,4,5>`, the quotient is a 60-by-32 binary matrix of rank at most 12. The
complete fixed-first-term campaign has five coarse rank/pairing cases and 148
residual-factor stabilizer orbits; each case covers all 1,048,575 nonzero
third factors. Independent tests reproduce Strassen, distinguish both
rank-one pairing cases, and brute-force the full small stabilizer action.

Short CryptoMiniSat and RoundingSat probes on `<5,2,4>`, `<4,2,4>`, and
`<3,2,5>` were indeterminate. Consequently `proof_inner2/` is a sound
distributed proof campaign and not a new lower bound: all shards would need
checked UNSAT proofs before the corresponding rank claim changes.

## 2026-07-14: projective-line matrix-pencil tunnel

A maximal subtotal whose factors on one axis lie in `{a,b,a+b}` is a
two-slice matrix pencil. Writing its slices as `X=A+C`, `Y=B+C` makes the
complete within-plane CP refactor
`min_D rank(X+D)+rank(Y+D)+rank(D)`. The new pure-Tungsten operator exhausts
`D` in the combined complementary factor spans, minimally factors all three
matrices, parity-compacts the splice, and runs the full `n^6` gate.

This found six real rank-neutral 5x5/r93 tunnels beyond the span-4 and
single-pair neighborhoods: three from d1155 (maximum term-set distance eight)
and three from d968 (maximum distance ten). Two 4x4 archives had no five-term
line bucket. A complete 128 MiB rank-table audit covered all 30 five-by-five
coordinate pencils in two 6x6 archives plus the seven remaining d968 pencils,
about 1.25 billion `D` values, with no changed 6x6 optimum, rank drop, or exact
failure. None of the six selected maximum-distance 5x5 endpoints improved
density.

The structural result did not translate into fertility. A matched 900M-move
continuation (12 seeds, 25M moves each, source versus distance-eight pencil
versus one-pair restart) produced no rank drop and returned every pencil arm
to the same r93/d1155 best as the source. The pencil arm's 72 best updates
versus 12 for source merely record that unwind. The move remains an offline
audit with no CPU/GPU lane. Exact derivation, tables, controls, and replay
commands are in `MATRIX_PENCIL_TUNNEL.md`.

## 2026-07-14: projective-plane quadrilateral tunnel

The next projective generalization uses a full three-dimensional fixed-axis
span. Each complement of a Fano line is a four-point circuit, so the same
complementary matrix `D` can be toggled into all four factor buckets without
changing the tensor. The new pure-Tungsten operator minimizes the sum of the
four changed matrix ranks over all seven circuits. It completely exhausts
`D` through 16 coordinate cells and uses exact bucket/bucket-XOR/rank-one
candidates on larger planes; every result still receives local and full
coefficient gates.

The planted move makes a direct 5->4 drop while complete span-4 and line-pencil
audits find no direct reduction. It is not a new algebraic component,
however: a general flatten-gauge acts on the same factorization orbit, and the
shipped bounded gauge already reproduces a drop on the tiny plant. The new
coverage is structured rank-median optimization, not disconnection from
`GL(k,2)` gauge words.

Across 110,181 bounded planes on eight 4x4--7x7 frontiers, 5,439 qualifying
groups evaluated 81,227,377 exact candidates. The audit found one neutral
5x5/r93 endpoint at distance six and two neutral 7x7/r247 endpoints at
distance eight, with zero rank or density wins and zero gate failures. A
600M-move matched continuation produced more distinct descendants from the
projective starts, but the source beat the projective arm 6/16 on 5x5 and 8/8
on 7x7; all remaining 5x5 trials tied. The operator remains offline with no
CPU/GPU pool allocation. Derivation, exact bounds, tables, and replay commands
are in `PROJECTIVE_PLANE_TUNNEL.md`.

## 2026-07-14: five-bucket projective-circuit tunnel

A minimal dependency of five fixed-axis factors has rank four and XORs to
zero. Therefore the same complementary rank-one matrix can be toggled into all
five corresponding slice matrices without changing the tensor. The new
pure-Tungsten operator enumerates these five-circuits, tests all 25
selected-factor rank-one medians plus every nonzero matrix in the span of the
five old slices, minimally refactors the five slices, and parity-compacts each
endpoint before the caller's full tensor gate.

The planted control performs a direct 5-to-4 reduction and restores the exact
3x3 rank-23 scheme from a rank-32 circuit shoulder. Complete 4x4 audits found
no changed low-debt endpoint. Complete 5x5 audits found 1,036 endpoints from
d967 and 849 from d1155; their best shoulders were r94/d973 and r94/d1166.
The higher-rank matrix-span family added 92 and 69 endpoints over the
rank-one-only pass without improving debt or density.
Bounded 6x6/7x7 audits found only `+2` shoulders. There were no exact-gate
failures and no direct objective improvement.

A matched 12-pair, 240M-move continuation compared the best circuit `+1`
shoulder with an ordinary `+1` split. Both returned to rank 93 in every trial
and neither beat d967, but the circuit arm retained novel rank-93 descendants
in 12/12 trials versus 9/12 and averaged term-set distance 12 versus 9. It won
the paired final objective 7-to-5. Consequently one quarter of 5x5
`lifted-identity` launches now try a 256-circuit prefix and admit only exact
`+1` shoulders; all other sizes stay offline. The experiment reuses the
existing pool row and does not change the TUI. See
`PROJECTIVE_CIRCUIT5_TUNNEL.md`.

## 2026-07-14: checked `<2,3,5>` lower bound 23

The new `proof_n235/` package proves

```text
23 <= R_GF(2)(<2,3,5>) <= 25.
```

The lower endpoint combines a complete 31-orbit Wang certificate at root
bound 22, a multiplicity-aware capacity CNF for the rank-two first-factor
case, and an independent incidence contradiction for the all-rank-one case.
The 23,452-variable/46,455-clause CNF is accompanied by an XLRUP proof accepted
by the formally verified CakeML checker. The independent replay expands all
31 orbits to all 2,825 subspaces, regenerates the CNF byte for byte, and checks
the 21-row incidence count. The unchanged upstream Wang verifier at pinned
revision `efd22070269157e65aaf8d61a21da253a4000c61` accepts the base
certificate.

The upper endpoint is not a new rank record. FastMatrixMultiplication already
publishes rank 25 for this shape. Its AlphaTensor `{−1,0,1}` scheme was pinned
at checkout `e0ec7db4cb7d7ca41abbb2c6e3bd8c7de75c7c64`, reduced modulo two with
the output-order transpose made explicit, and independently exact-gated as
`matmul_2x3x5_rank25_d173_alphatensor_zt_mod2_gf2.txt`.

Separately, a 16-seed pure-Tungsten sweep of 10M moves per seed from the
elementary rank-26 block construction independently rediscovered rank 25 on
seeds 235107 and 235110. Their d210 and d278 certificates share zero terms
with each other or with the public d173 scheme. All three are retained as
exact provenance; a subsequent 62M-move continuation reduced the public basin
to d170 with one ordinary flip. A later five-island campaign reached d160 no
later than 39.73B recorded moves. A separate one-move load/walk/dump replay
accepted no move, reconstructed the complete tensor, and reproduced SHA-256
`48f567ce264b996cb6f1d9ce88296e1830b8a4261830ca3d03fc0a04b04e7be7`
byte for byte. D160 shares three terms with d170/d173 and none with d210/d278,
so d160/d170/d210/d278 are four distinct CPU restart doors and the profile
continues to target rank 24. The proof
does not claim exact rank, a lower bound above 23, or any result over the
rationals. Full hashes, proof logic, replay commands, and the claim boundary
are in `proof_n235/README.md`.

The same profile now has a first-class generated pure-Tungsten/Metal
cal2zone worker (`CAP=68`, `WPG=16`, 13,056 threadgroup bytes) beside its
pool-384 exact 5→4 MITM child. A 4,096-lane, four-round standalone profile
covered 1.6384B moves in 5.27 seconds (311M moves/s including setup under
concurrent GPU load). The integrated coordinator smoke covered 10.24M
cal2zone moves plus 1,176,576 MITM pairs from d160; both workers were ready,
the final checkpoint remained exact rank 25/d160, and GPU failures, host exact
rejects, and internal rejects were all zero. The earlier 64-batch MITM
admission sweep covered 75,300,864 pairs with no fingerprint hit. These are
bounded negative searches, not a rank-24 exclusion.

## 2026-07-14: small primitive exact ranks and the `<2,2,5>` one-term gap

Complete finite-geometry certificates, replayed with Wang's unchanged
verifier at pinned revision `efd22070269157e65aaf8d61a21da253a4000c61`,
close three primitive GF(2) ranks:

```text
R(<2,2,3>) = 11
R(<2,2,4>) = 14
R(<2,3,3>) = 15
```

For `<2,2,5>`, raising only the forced-product cap from `2^24` to `2^25`
finishes the previously skipped 33,554,432-case child and raises the checked
lower bound from 16 to 17. The exact block upper bound is 18, so the rigorous
interval is now `17 <= R(<2,2,5>) <= 18`. Certificate/archive digests,
11-orbit coverage, and one-command verifier replay are in
`proof_inner2/SMALL_PRIMITIVE_FRONTIER.md`.

`2x2x5` and `2x2x6` are now first-class CPU rectangular FlipFleet profiles,
targeting 17 and 20 from exact ranks 18 and 21. The first 68M-move 225 smoke
reduced density 95 to 88. A whole-scheme GL image supplied a zero-overlap
second door, and the ensuing two-door run reached exact d84 after 3.17B
moves. The retained d84/d88 schemes share no terms; their 36-column union has
rank 35/nullity one, so no proper differential splice exists. Both independent
tensor gates accept d84, whose SHA-256 is
`bdce32ca89b5598e470fade86855904c283149ee4ec47d46fe6275afbd80225e`.
The certified one-term 225 gap now has the highest static priority in the
default `--rect` portfolio; 226 remains available explicitly.

Independent block-local conjugation broadens that bank. A pure-Tungsten
4,096-member scan applies unrelated GL words to the rank-11 `<2,2,3>` and
rank-7 Strassen leaves before their `3+2` embedding. Every composition passed
the full gate. The selected r18/d92 door has 16 equal-factor pairs, shares no
term with d84 or d88, and has union nullity two with d84. Its proper 11↔11
dependency materializes a second exact d84 presentation. A matched 800M-move
screen of block door, splice, d84, and d88 found no rank or density gain, so
the endpoints are diversity doors rather than an objective claim.

The corrected rectangular GPU engine then demonstrated why nonleader seed
rotation and source-island feedback matter.  From block-d92 it returned through
d89/d86 to a fifth exact d84 scheme within the first 4.096 billion moves.  The
host tensor gate accepted it, and its saved SHA-256 is
`86b73a254dcafe6e39c1411d183a07cad43083bf5b6818a3f574996d103618a1`.
Its distances from d84/d88/block/splice are `28/36/10/14`.  Expanding the
complete block-parent audit to all five doors covered 20,479 nonidentical
unions and all 52,575 dependencies, yielding 32,096 proper exact rank-18
relations but no rank-17 projection.  All five now rotate across 225 islands;
the complementary-hybrid closure is evaluated separately as a new tunnel move.

That closure retained both children discarded by the old single-best selector,
but saturated at seven rank-18 schemes and produced no rank 17. Eight matched
20M-move continuations from each of the seven endpoints (1.12B moves total)
made no objective progress, so the move remains an offline exact audit rather
than a default lane. A stronger multi-parent affine solver then allowed a
solution to mix terms from any three or more supplied schemes. It exhausted
the five doors plus every single block parent, and all pairs and triples from a
32-parent maximin archive: 11,942,176 affine masks and 232,978 independently
gated rank-18 occurrences, with no rank-17 subset or gate failure. See
`ARCHIVE_NULLSPACE_CLOSURE_225.md` and `MULTI_PARENT_NULLSPACE_225.md`.

The next fixed-dictionary attack no longer caps the affine nullity. The
pure-Tungsten builder deduplicates the five doors plus block-local parents,
emits exact native tensor XORs with an unconditional `weight <= 17` sequential
counter, and replay-gates every SAT model. The five-door, maximin-32, and full
4,096-parent dictionaries contain respectively `55/625/3,321` terms, with
column ranks `51/212/212`; their serialized-order SHA-256 values are pinned in
`UNION_SUBSET_SAT_225.md`. An independent implementation reproduced every
column, rank, XOR row, and cardinality clause. The five-door limit-18 control
returned exact r18 and limit 17 was solver-reported UNSAT. Maximin-32 and full
bank searches remained indeterminate after 300 seconds; Z3 `PbLe(17)` and the
checked-lower-bound-gated `PbEq(17)` comparison also timed out. These are
bounded search negatives, not a stronger lower bound.

The associated all-parent affine audit exposed a scheduling obstruction more
important than its negative search count. The 4,101 inputs reduce to 3,750
distinct exact rank-18 schemes and affine-code dimension 1,625. Any odd XOR
of even-cardinality parents still has even cardinality, so it cannot land at
rank 17. A complete odd-triple audit made that boundary executable: for three
18-sets, a result at most 17 must be at most 16 and must contain a parent pair
overlapping in at least seven terms. Of 7,029,375 pairs, 218,571 passed that
complete filter. The 819,204,108 completing-pair probes took 36.334 seconds
in the original run and 13.088 seconds in the final release/native replay;
triples with multiple qualifying pairs can be visited more than once. Minimum
rank stayed 18. Five anchor scans covered another 35,128,130 generator pairs.
The already checked lower bound 17 independently
rules out the only possible even improvement, rank 16. Rank-18-only affine
parents are therefore retired for this one-rank gap; the SAT dictionary stays
offline pending a stronger nearest-code/cardinality solver or genuinely new
terms outside the block-local family.

The same independent-leaf construction was closed completely for the
three-Strassen `<2,2,6>` upper scheme. All 4,096 parents were exact rank 21;
4,026 were at the maximum distance 42 from the baseline. Crossing every
parent with the baseline and all 496 pairs in a 32-parent diverse archive
gave 4,522 nonempty unions, each with column rank 39/nullity three. All 31,654
relations were enumerated and all 27,132 proper projections independently
materialized as exact rank 21, with no rank-20 result or gate failure. Parent
7 is retained because it is a zero-overlap r21/d108 door with the same 21
equal-factor pairs as the baseline; its SHA-256 is
`6c74b5bb150e2e9d6529c00edcd319baaed3d8b53792024c7d0f7d71198b5405`.
Matched 100M-move baseline and door arms both stayed exact r21/d108, while
only the door arm reached a distinct equal-density best.
The finite nullspace family is retired, while the endpoint rotates as the
second 226 CPU door. Full replay is in `BLOCK_GL_NULLSPACE_226.md`.

The correlated follow-up is stronger than that pairwise count. Complete
multi-parent hulls over both doors plus every single parent, every pair in the
32-parent archive, and 4,956 of its 4,960 triples visited 52.67M additional
affine masks and gated 728,999 exact rank-21 occurrences without finding rank
20. The remaining four triple hulls had nullity 30, but a structural audit
closes them and every larger union at once: all 86,016 generated term
occurrences live in exactly one of three disjoint `<2,2,2>` output blocks.
Since the checked rank of each block is seven, any exact subset of the entire
dictionary needs at least `7+7+7=21` terms. This retires the whole block-local
dictionary, not just the enumerated low-nullity slices.

## 2026-07-14: a third independent `4x4x5` frontier

Sparse two- and three-generator whole-scheme GL words plus complete
parent-difference elimination found a proper 57-versus-57 splice. Ordinary
continuation reduced its exact endpoint to rank 60/d662. It is distance 106
from d628 and 120 from d919; each union has nullity one, so the new endpoint
is independent of both prior doors and offers no further proper splice.

The completed bounded audit covered 40,960 exact GL images, 81,920 complete
pair eliminations, and 1,285 proper splices without finding rank 59. The saved
certificate `matmul_4x4x5_rank60_d662_short_orbit_splice_gf2.txt` has SHA-256
`2fc026e447cb503662f4d214c65ff862c75b45a615024e09c6231dc457781ee8`.
It is now the third rotating CPU door; d628 remains the monotonic density
leader. Deterministic replay, full coefficient gates, and matched controls
are documented in `RECTANGULAR_CAMPAIGNS.md`.

## 2026-07-14: exact residual closure and GPU parity-compaction repair

The certified `2x2x5` gap received two complete correlated residual audits.
The residual worm archived 633 collision-safe unit-floor states (556 distinct
ordered term lists). Exhausting all 86,088 two-term repairs found no carrier
of tensor rank at most two. Exhausting all 378,080 old-term triples then
tested 35,213,136 `GL(3,2)` bases and 32,463 completing matrices, with no
rank-at-most-three carrier and therefore no rank-17 child. An independent
unit-to-unit scan covered 34,349,112 correlated carriers; its 14,439 exact
rank-two decompositions formed only two isolated four-cell components and
opened neither a bridge nor a new residual cell. These are complete negatives
for the archived corpus, not sampling failures. Replay is in
`RESIDUAL_WORM_225.md` and `THREE_TERM_REPAIR_225.md`.

The first full-width 225 Metal launch exposed a separate implementation bug
before its output could be trusted. When two equal GF(2) terms appeared, the
kernel copied the tail into one duplicate, decremented rank, and then removed
the other slot using the already-shortened tail. That could leave one duplicate
while deleting an unrelated term, producing nominal low-rank candidates that
the exhaustive host gate rejected. The corrected compactor orders the two
indices, removes the higher slot first, then performs an independent lower-slot
tail deletion. The source template and all fourteen checked-in square and
rectangular workers were regenerated. A full-width 4,096-lane replay completed
100 rounds of 20,000 moves—8,192,000,000 device moves—with zero internal
rejects and zero false improvements. Generator tests assert the two-deletion
shape in both Tungsten and emitted Metal for every asset.

## 2026-07-14: affine four-cube tunnel audit

The move lab now includes the exact sixteen-corner affine Segre identity over
`GF(2)^4`. Five affinely independent live terms determine a candidate
four-flat; toggling all sixteen corners preserves the tensor because a product
of three affine coordinate functions has degree at most three. A planted
rank-39 3×3 shoulder returns to the exact rank-23 scheme, so the operator and
full reconstruction boundary are live.

The real geometry supplied no tunnel. Complete enumeration on both 4×4
rank-47 doors (1,533,939 bases each) and two 5×5 rank-93 doors (51,971,283
bases each) found maximum circuit overlap exactly five: no generated four-flat
contained even a sixth live term. Five-million-basis samples on the normalized
6×6 and 7×7 leaders gave the same result. Every best endpoint therefore had
rank debt +6; there were no neutral or lowering candidates. The implementation
remains an offline regression and earns no fleet-pool share.

## 2026-07-14: `2x4x5` fleet density 222

The live pure-Tungsten `2x4x5` CPU fleet continued from the far-GL d241 door
and first reached an exact rank-33/d222 presentation by 199.6 billion worker
moves. A fresh one-move rectangular-worker replay reconstructed the complete
tensor, reported rank 33/d222 with zero accepted move, and wrote a byte-for-byte
identical file. The retained certificate is
`matmul_2x4x5_rank33_d222_fleet_gf2.txt`, SHA-256
`fb6d6d0a9ce859695cb8096c0e36fcdbe958190b29d3741d0bdb0c9c90d249a5`.

The d222 leader shares seven terms with the prior d241 frontier (term-set
distance 52) and no terms with the catalog presentation (distance 66). It is
now the default, while d241 and the catalog seed remain separate restart
doors. This is a cost and basin improvement at known rank 33, not a rank
record; the GF(2) campaign still targets rank 32.

## 2026-07-14: six-bucket projective-circuit closure

The rank-five six-factor dependency was implemented with canonical triple-XOR
hash matching, avoiding an `O(r^5)` scan. Planted 6-to-5 and full 3x3
rank-34-to-23 controls pass. Complete all-axis audits on the sparse and
alternate 4x4--7x7 doors covered 148,982 minimal circuits and 5,363,352 exact
endpoint occurrences, with zero neutral endpoints and zero rank drops. Best
debt was `+4` for 4x4 and `+2` for 5x5--7x7.

The best 5x5 `+2` shoulder was continued against two ordinary splits for 12
paired five-million-move trials. Both arms returned to rank 93 every time,
neither improved density, and the circuit arm lost the paired objective 5-to-6
with one tie despite averaging greater source distance (16 versus 13). The
operator remains an offline scout with no CPU/GPU pool allocation. Full
coverage, memory, timing, and replay are in `PROJECTIVE_CIRCUIT6.md`.

## 2026-07-14: strict-ternary unit-dependency median

The five-factor dependency median now has a separate integer implementation.
It admits only coefficientwise-verified relations
`sum s_i f_i = 0`, `s_i in {-1,+1}`, then applies
`M_i -> M_i + delta*s_i*(y tensor z)`. A planted strict 5-to-4 subtotal and a
full Laderman rank-32-to-23 shoulder pass integer reconstruction, while a real
GF(2) five-circuit with no signed unit relation is rejected.

Complete pair-versus-triple enumeration on the current 4x4--7x7 ternary
frontiers found 515--5,995 unit relations per seed. The 5x5 and 7x7 archives
contain exact `+1` shoulders, and 5x5/6x6 leaders contain `+2` shoulders, but
the complete audited default/archive set has no neutral endpoint and no rank
drop. The best selected endpoints are full-gated and lie at term-set distance
six or seven from their parents.

Matched continuation covered 168 million moves. The d432, d967, both d1931,
and d2966 comparisons tied their ordinary split controls; d997 split the
trials 6-to-6; the d3069 median lost 4-to-8. Neither 7x7 arm beat the d2966
leader. This is a sound, fast source of changed signed shoulders but not a
measured improvement, so it remains offline with no pool allocation. Details
and replay are in `TERNARY_DEPENDENCY_MEDIAN.md`.

## 2026-07-14: whole-bucket and polynomial GF(2) dependency medians

The five-factor circuit now has a genuinely whole-bucket implementation. It
captures every term under each circuit factor, enumerates all 31 nonempty
bucket-matrix subset toggles, and factors physical matrices without a packed
size limit. A planted five-bucket collection drops 10→9 although exhaustive
representative-term search bottoms out at ten; a mapped zero relation also
returns an exact 3x3 r42 shoulder to r23 under the full gate.

The real-door result was negative. Complete 4x4/5x5 and bounded 2,048-circuit
6x6/7x7 passes covered 11,758 circuits and 364,498 toggles. Minimum debt was
+3 on 4x4, +2 on both 5x5/6x6 doors and the sparse 7x7 door, and +1 exactly
once on the alternate 7x7 door. That r248/d3562 shoulder used one term per
bucket. In a 240M-move continuation it lost slightly to an ordinary split
(3 wins, 4 losses, 5 ties; best d3510 versus d3508), so it remains offline.

A second operator removes fixed circuit size for rank-one `D`. For each
fixed-factor bucket it computes `rank(M xor D)-rank(M)`, solves arbitrary-size
zero-sum dependencies by coordinate-recovering GF(2) elimination over the
other nonpositive buckets, then permits one or two positive buckets for
neutral/+1 debt. A minimal eight-factor plant drops 8→7 and a full r38
shoulder returns to r23. Complete sparse/alternate 4x4--7x7 scans tested 3,240
axis-local D values and full-gated 2,485 endpoints with no direct drop or gate
failure. An all-D scan rejecting canonical witnesses shorter than six found
nothing longer on all eight doors; alternate nullspace representations were
not enumerated. Every recovered hit therefore belongs to known 3--5-bucket
geometry. The strongest new shoulder was 6x6 r154/d1840, but in a 240M-move
matched continuation it failed to return to rank 153 in 12/12 trials while
every ordinary split returned; the paired result was 0--12. This broader
tunnel also remains offline. Exact counts and replay are in
`WHOLE_BUCKET_DEPENDENCY_MEDIANS.md`.

## 2026-07-14: rank-two arbitrary-dependency median

The arbitrary dependency operator now also constructs every unique physical
`D=A xor B` from two distinct live rank-one complementary matrices. Exact
hash deduplication and minimal physical factorization retain rank-one controls
while allowing an audit to isolate rank-two values. An adversarial
eight-bucket plant separates the families: every live rank-one `D` bottoms at
16 terms, while a rank-two pair XOR gives an exact 16→13 refactor and restores
a full exact 3x3 r39 shoulder to r23.

Complete all-axis scans of both 4x4--7x7 doors evaluated 283,890 unique
rank-two matrices. The 4x4, 6x6, and 7x7 doors had no admitted dependency.
The two 5x5 doors produced 7 and 6 exact endpoints respectively, all
three-bucket 5→6 replacements and all rank `+1`; there were no neutral
endpoints, drops, or gate failures. Complete six-bucket-minimum passes on both
5x5 doors found nothing. The best shoulder was r94/d975 from r93/d967.

In a 240M-move matched continuation, both the rank-two and ordinary-split arms
returned to rank 93 in all twelve trials. The rank-two arm lost the paired
objective 1-to-11, found no density win, and reached best d973 versus d967 for
the split arm. The implementation therefore remains an offline exact
regression with no pool allocation. Details and replay are in
`LOWRANK_DEPENDENCY_MEDIAN.md`.

## 2026-07-14: complete two-wide composition seam and 40 exact promotions

The production block leaf bank now covers all 28 sorted `<2,a,b>` shapes for
`2 <= a <= b <= 8` in addition to all 56 sorted 3--8 shapes. Eighteen newly
imported catalog leaves and the complete 84-shape pool passed independent
dimension, factor-bound, duplicate, and coefficient reconstruction gates.
The balanced rank-47 outer scan then closed all 1,154 sorted targets with one
dimension 8--11 and the other two at most 32.

Against explicit or integer-reducible GF(2) comparators, 129 formulas win,
two tie, 382 lose, and 641 have no pinned comparator. A universal signed
rank-49 outer control produces zero wins. Twenty-two conservative wins were
materialized, led by 11x28x28 rank 4937 (gain 183) and 11x20x32 rank 4014
(gain 146). Two direct `<2,3,5>` propagations give 8x11x20 rank 1119 and
8x12x20 rank 1175. Two more exact upper bounds, 11x16x31 rank 3195 and
11x16x32 rank 3255, beat the best pinned numerical values but remain labelled
uncovered rather than records.

Exact materialization then exposed mapped-zero removals that formula scoring
cannot see. Exhausting all 14,362 formula-minimizing balanced allocation/S3
ties improves 158 targets below formula rank and 53 beyond the deterministic
first recipe; duplicate parity contributes nothing. The nominal 10x22x23
rank-3073 formula falls to exact rank 3071, beating the pinned GF(2) rank 3072,
and six other strict results improve by 1--12 terms. Seven further zero-pruned
upper bounds beat every pinned numerical value but remain uncovered for lack
of an explicit or reducible GF(2) comparator. The d677 alternate rank-47 outer
has zero formula wins, 217 ties, and 937 losses against d450, and zero wins
after selected-recipe exact materialization.

The exact-equivalent bounded scorer precomputes pairwise outer support extents
and a dense oriented leaf-rank table. It reduced the 129-winner ordered
allocation closure from an unfinished two-hour run to 195.92 seconds, finding
10x16x16 exact rank 1558. Eight shards then closed all 1,154 rows in two
124--141-second waves: 38 formulas improve by 345 aggregate terms, and
10x16x17 exact rank 1694 newly beats universal/GF(2) rank 1696 by two. Exact
materialization of all 38 improved layouts found only two additional harmless
cancellations and no hidden comparator win.

The remaining unbalanced-tie loophole is now closed through a 12-term pinned
GF(2) deficit. A pure-Tungsten pass rescored every ordered 2--8 allocation and
unique S3 source ordering for 56 near-comparator targets, then
parity-materialized all 648 recipes tied at the global bounded minimum. Only
10x14x16 and 10x22x23 lose terms (two mapped-zero terms each); the former
remains six behind, while the latter merely reproduces the already-published
rank-3071 win through a different minimizing recipe. No recipe receives a
duplicate-parity reduction, so this complete near-bound tie closure adds no
new numerical record.

The manifest now has 186 exact certificates: 176 strict apparent GF(2)
records, one co-record, and nine uncovered upper bounds.

The pure-Tungsten manifest gate reloaded all 186 certificates. A separate
sparse Python verifier reconstructed 683,804 rank-one terms and 113,590,185
`(U,V)` support pairs; Apple Python 3.9 and Homebrew Python emitted the same
186-row audit, SHA-256
`796f5f3cf7b1cd65551cb19d6aca85d3c6028710e6776a6de879a0626b050b2c`.

Re-running downstream leaf sensitivity over all 186 materialized and 889
strict audited formulas keeps 4x4x5 rank 60→59 as the highest-leverage saved
target: 1,411 occurrences across 113 formulas, with 109 guaranteed
improvements. The newly exposed two-wide leader is 2x5x6 rank 47→46: it would
improve ten saved certificates by 82 guaranteed aggregate terms and 49 further strict
audited formulas by 652 terms, with three more comparable shadows crossing to
wins. FlipFleet now exposes this as a first-class rank-47→46 profile with an
exact catalog seed, independent pure-Tungsten admission gate, sticky CPU
islands, a capacity-92 cal2zone Metal worker, and low-cadence exact 5→4 MITM.

A zero-debt rectangular orbit-door scan then fixed the profile's remaining
single-presentation weakness. Among 512 exact sparse-GL/descent endpoints, 405
returned to density at most 438; sample 3 produced a second exact rank-47/d438
scheme at the maximum term-set distance 94 from the catalog leader, hence the
two doors share no rank-one term. The independently reparsed certificate is
`matmul_2x5x6_rank47_d438_orbit_door_gf2.txt`, SHA-256
`9db0a90aa042a75dece6ea15a082c34de3f942ce3c90014bf50d25b9e0ec7704`.
Implicit 2x5x6 starts now alternate the two sticky doors, and half the Metal
epochs rotate the nonleader door; explicit `--seed` runs remain single-source
controls.

## 2026-07-14: two-hour `2x2x5` GPU plateau

The specialized exact `2x2x5` campaign completed its planned 7,200 seconds at
rank 18/density 84. Five CPU islands made 59.105 billion moves, 4,096 Metal
lanes made 1.93675264 trillion moves, and the exact 5→4 MITM lane tested
3,477,958,656 complementary pairs. Four GPU doors were adopted; device and
host exact-reject counters remained zero. No rank-17 scheme appeared. This is
a large negative search sample, not a lower-bound proof.

## 2026-07-14: cubic three-factor raw-map tunnel

The raw-map nullspace hierarchy now includes a genuinely cubic move. For
independent linear maps on all three factor spaces, each live term contributes
the complete old-XOR-product-image delta. A coefficient-kernel support can be
replaced atomically, including zero-image omission and duplicate parity
cancellation. The `a tensor b tensor c` cross term in the product expansion
is absent from the existing one- and two-factor workers.

The pure-Tungsten control supplies a proper-submap-resistant five-position
5↔5 relation: the same selected support fails all three one-factor and all
three two-factor maps. Adding its two disjoint sides to Strassen gives an
exact rank-17 shoulder; applying the cubic move creates five duplicate pairs
and returns to independently gated rank seven.

The real-door audit is a clean negative. All 64 operation-family triples and
eight support-guided coordinate variants were run on two presentations at
each of 3×3, 4×4, 5×5, 6×6, and 7×7. Across 5,120 complete kernels, 576,512
term rows, and 335,761 nullspace basis vectors, every dependency selected a
set already invariant under the product map. There were zero changed
endpoints, algebraic failures, or gate failures. Since invariant supports are
closed under symmetric difference, no combination of those bases can produce
a hidden endpoint for a tested plan.

The 3×3--6×6 sweep took 0.93 wall seconds and at most 14.0 MB; two 7×7 doors
took 1.66 seconds and at most 18.6 MB. The move stays as an offline regression
for structurally new archives and receives no CPU/GPU pool allocation. The
escape recipe and exact replay are in `THREE_FACTOR_MAP_NULLSPACE.md`; the TUI
is unchanged.

## 2026-07-15: persistent rectangular doors, faster gates, and negative audits

Rectangular best checkpoints now have a persistent, bounded archive of up to
four nonleader side doors. Save and load both pass through the full rectangular
exact gate; writes use temporary-file rename, retained ranks are limited to the
leader through leader plus two, and exact duplicates are excluded. Portfolio
restarts keep lane zero on the leader and rotate the remaining lanes through
the archive. One malformed slot cannot poison the others, and `--naive`
physically clears every stale side door before publishing the schoolbook reset.

The support-major exact verifier accepted all 106 packaged GF(2) seeds and
rejected all 424 controlled corruptions, including the bit-63/last-word
boundary. Against the former coefficient-major reconstruction it took
15.3--15.5 ms instead of 0.85--0.87 s over the complete seed set, a 55--56x
aggregate gain with the same first-mismatch result. The independent sparse
oracle agreed, and the scheme hot-path test passed 30K square plus 30K
rectangular flips and 200 square plus 200 rectangular splits with periodic
exact/density checks and external rectangular adoption.

Two exact same-rank density records are now the packaged rectangular defaults:
`3x4x4` r38/d280
(`a08fc5382ac7da3e0fd09b3c1e389138feada0f91a6be5a0e06e75aa07668855`)
and `4x5x6` r90/d906
(`ba4a024752247b156b92bebe0a5bdfb644e44f3702323896bcb3a785625abdaa`).
The prior exact presentations remain in each frontier. A targeted campaign over
`2x5x6`, `3x4x6`, `4x4x5`, and `4x5x7` then consumed about 19.3 billion
aggregate moves with zero exact rejects and no rank or density gain. This is a
search plateau, not a lower bound.

The deliberate split-braid-merge “Rubik” macro split one labelled term, braided
exact pair flips at r+1, and merged a different pair back at r. It returned 209
full-gated endpoints beyond ordinary one-flip/span-4 coverage with zero gate
failures and no rank win. Density improved only on the superseded 5x5 d983
source, to d980 in five-term windows and d979 in six-term windows; the current
5x5 d967 and rectangular leaders did not improve. It remains an offline deterministic replay,
not a production lane.

The nonflip rectangular decision audit tested triangle shear, low-rank shear,
span refactor, and flatten gauge on `2x5x6`, `3x4x6`, `4x4x5`, and `4x5x7`.
It found 280 changed exact endpoints, zero gate failures, and no rank or density
win. Another 416M paired continuation moves found no rank drop, including
8x10M moves per arm for each of the two neutral `4x5x7` doors. These operators
also remain offline; the negative is bounded search evidence only.

Generated generic and rectangular GPU workers now map a failed equal-factor
partner scan to the rank sentinel before duplicate compaction, eliminating the
possible slot-`-1` access. The packaged fleet defaults to adaptive GPU scheduling
with 8,192 walkers and 40,000 steps per epoch, while retaining CLI overrides.
Rectangular portfolio epochs now use 16 base rounds (range 1--64), with
one-round straggler fill for shapes that can finish more work before the slowest
base quota. Package-layout coverage checks the guard in every generated worker
and pins both promoted density defaults.

The four rectangular side slots are now selected after gathering every exact
unique endpoint, rather than truncating in discovery order. Present `R`,
`R+1`, and `R+2` bands are reserved, and deterministic max-min term-set
distance fills the remaining slots. Exact term lists confirm any fingerprint
match. An adversarial order-invariance test retained a distance-37 prior door
over four distance-3 near copies while covering all three rank bands; 22-way
selection took 15 microseconds at island exit.

The low-cadence 5-to-4 MITM lane now snapshots the round-start best and runs
concurrently with CPU and cal2zone work, then joins and passes the full exact
gate at the existing barrier. A matched `<2,5,6>` epoch with 4,096 GPU lanes
and a 16-by-384 MITM table dropped from 1.43 s sequential median to 0.99 s
concurrent median (30.8%), with rank 47/density 438 unchanged, 1,176,576 pairs
tested, and zero failures or rejects. Bounded joins kill and reap a timed-out
child, and portfolio status now accounts failed-segment work monotonically in
both per-shape and total move fields. A 120-second four-target control completed
28 healthy epochs without a rank or density change.

Blind Rubik-style commutators do not transfer cleanly because an ordinary
tensor flip is a state-dependent partial involution. `ABA`/`ABAB` controls
returned 284 exact 5x5 endpoints and 444 exact 4x4x5 endpoints, all within
span-4 coverage. Setup-trigger-inverse ribbons tested 202,368 and 842,112
trigger positions without restoring the requested close. They remain offline;
the useful formulation is a labelled shoulder search toward a specified pair
of factor equalities, with exact visited-state deduplication and replay.

The resulting goal-directed beam searched depth 5--8 connected flip words on
the labelled `R+1` shoulder. Full gates accepted ten beyond-span-4 endpoints
on 5x5 and ten on 4x4x5, with no failures; 2x5x6 returned no endpoint. There
were no rank or density wins. The best 5x5 door was r93/d975 against d967 and
lost all eight matched 2M-move continuations. The best 4x4x5 door was r60/d641
against d628; after continuation both arms tied at d628 in all eight trials.
The full scan took about 0.56 s and roughly 305 MB peak RSS. Goal-directed
words therefore do reach exact states outside the current span-4 envelope,
but this generation stays offline because its new basins showed no objective
or continuation value.

A chosen-core variant dynamically selected the merge partner and axis at each
partial state, required the close to absorb the selected label, and confirmed
that its original triple vanished. Novelty mode found six beyond-span-4 5x5
doors and four 4x4x5 doors with zero target or exact-gate failures. Best density
was d975 versus d967 and d640 versus d628; the first lost all eight matched 2M
continuations and the second tied all eight. Objective mode produced only
span-4-covered endpoints, and 2x5x6 had no close. It remains offline.

Portfolio-child live status is now capped at 200 ms while first, retry-after-
failure, standalone, and final writes retain their prior guarantees. A matched
128M-move 4x5x7 control improved wall median 4.55 s to 4.36 s (4.2%) and CPU
median 2.95 s to 2.68 s (9.2%); system time fell 0.37 s to 0.11 s. Parent status
now exposes cumulative CPU/GPU moves and MITM attempts/pairs/ms both per shape
and in total. Live/unjoined projection, terminal commit, failed work, and naive
reset have focused regressions; the TUI layout is unchanged.

A subsequent 300-second campaign made 30,507,167,270 CPU moves and
96,247,680,000 GPU moves plus 105,891,840 MITM pairs in 90 launches. All four
leaders and 16 side doors passed independent gates, with zero failures/rejects
and no objective change: 2x5x6 r47/d438, 4x4x5 r60/d628, 3x4x6 r54/d488, and
4x5x7 r104/d1089.

The 2x2x6 r21 profile now has a specialized pure-Tungsten/Metal cal2zone
worker (4/12/12-bit factors, 64-term capacity, 12,288 bytes shared memory) and
rectangular 5-to-4 MITM support. Packaged build/dispatch passed. A 100-round
8192-lane control made 32.768B moves in 45.32 s with no rank/density gain; one
MITM pass tested 1,176,576 pairs in 0.52 s without a hit. It joins the default
rectangular portfolio as a distinct underexplored frontier, not because this
short control supplied positive evidence.

Three high-leverage default shapes that had still been CPU-only now have the
same generated, full-gated Metal coverage. `<3,4,6>` uses CAP104/WPG16 and
19,968 threadgroup bytes for 12/24/18-bit factors; 327.68M moves took 1.09 s,
about 301M/s. `<3,4,7>` uses CAP116 and 22,272 bytes for 12/28/21-bit factors;
the same work took 1.30 s, about 252M/s. `<3,5,6>` uses CAP122 and 23,424 bytes
for 15/30/18-bit factors; it took 1.43 s, about 229M/s. The last seed genuinely
sets bit 29, and the worst 30-bit normalization sum remains two below signed
`INT_MAX`. Packaged 16-lane smokes and full-width replays passed every internal
and host exact gate. None of the three short bring-ups changed rank or density;
they expand productive GPU breadth rather than claim a search result. Larger
default shapes remain CPU-only pending an occupancy/throughput case.

Parent telemetry now carries MITM failures separately from cal2zone failures.
An injected real MITM child failure made parent health degraded and retained
the failed attempt/pair count without disabling its healthy cal2zone relay; a
later clean accelerator epoch recovered health while cumulative failure history
remained visible. A real straggler-fill control also committed exactly 25M
moves from 10M base plus 15M base/fill work, closing the terminal-status replay
double-count boundary.

The endpoint-first version of the Rubik analogy is now a concrete offline
rectangular solver. Instead of guessing a word in state-dependent flips, it
chooses six or seven local terms, enumerates candidate factors, and hash-joins
an exact five- or six-term replacement on Metal. Unequal factor widths enter
the fingerprint, local tensor equality is exhaustive, and a complete
rectangular certificate gate precedes every output. Constructed controls split
one term of the exact `<2,5,6>` r47 scheme into an r48 shoulder; both 6-to-5
and 7-to-6 joins returned exactly one fingerprint/local/full candidate and
recovered an independently reloaded r47 certificate.

The real-frontier decision is still negative. At pool 256, 128 unique 6-to-5
subsets on each of `<2,5,6>`, `<3,4,6>`, and `<4,4,5>` covered 1.061 billion
canonical queries with zero fingerprint hit, hence zero local or certificate
gate. Search wall was 3.4--6.3 seconds per frontier and reusable scratch held
peak RSS near 45 MB. The 7-to-6 triple/triple join remained host-table-bound.
Both stay offline: 6-to-5 is now a fast valid local rewrite compiler, but it
has no frontier-value evidence, and neither engine yet synthesizes an ordinary-
move path to its endpoint.

The final relocation audit found one compiler-level deployment bug rather than
a Metaflip path heuristic: native `__DIR__` preserved a relative entry path.
A binary compiled from `bin/metaflip.w` could therefore lose both its packaged
runtime and its compiler fallback after being moved or launched from another
directory. Native lowering now resolves `__DIR__` to the source directory's
canonical absolute path at compile time while leaving diagnostic `__FILE__`
spelling unchanged. The regression compiled through the canonical driver from
a relative source path, moved the executable to `/tmp`, removed every Metaflip
and Tungsten override plus `tungsten` from `PATH`, and launched from an unrelated
directory. A cold 32-lane worker/Metal-library rebuild completed with exact
verification and `gpu_degraded=0`; the relocated package-layout and CPU
self-tests also passed.

## 2026-07-15: 2-wide rectangular fronts, unbiased GPU doors, and resolved macros

This pass added explicit exact GF(2) checkpoints for `<2,2,7>` at r25/d132
and `<2,2,8>` at r28/d160.  They are normalized reductions of the
FastMatrixMultiplication `2x2x7_tensor.mpl` and `2x2x8_tensor.mpl` files at
revision `e0ec7db4cb7d7ca41abbb2c6e3bd8c7de75c7c64`, with normalized SHA-256
digests `d81e851f6d642be561e18072e890d9fab955621dcac066781e3a18b58cfbd939`
and `a3d33adb4c20429ebaa2d1883f702d0c5b90e13de3112017e6b0bcf4b159d823`.
Because the catalogue does not identify an unambiguous original discoverer,
the import is conservatively attributed to the matmulcatalog contributors.
Erik Peterson's 2026 exact factor splits supply controlled restart shoulders
at r26/d135 and r27/d137 for `<2,2,7>`, and r29/d165 and r30/d169 for
`<2,2,8>`.  These are certified `R+1`/`R+2` presentations, not rank or density
records.  Their text-certificate hashes, in that order, are
`1b695890ecc86cee9ce7186da735a462b348f7a03b800069a9d2f8d5cb8085c9`,
`679ccfca924921b5b9c8ed514a69cc40bac643a60c99cd45e4a23670698bc52b`,
`4421ed9c520fc5e745a74db749498df93bd5113e2fa8f30df6449c8c849f4818`,
and `c0e2f152a1f0c1fc2678cd0cca0903ed0883b4b7818d29a3d9a5a3ade94d75ec`.

The curated public results tree now gives `<2,2,9>` the same three-band
corpus: Perminov's imported r32/d156 certificate, two exact simultaneous
coordinate permutations at the same rank and density, and an exact split
shoulder from each presentation at r33 and r34.  Thus the public corpus has
three `R`, three `R+1`, and three `R+2` doors, each with explicit parent and
move provenance.  The r33 densities are 159/162/162 and the r34 densities are
162/165/165.  Only the r32 algorithm is a best-rank checkpoint; the coordinate
permutations are alternate presentations and the higher ranks are synthetic
diversity seeds.

All 18 generated rectangular Metal workers now permute the full-period LCG
state through unsigned PCG RXS-M-XS before masking a factor.  They reject zero
and redraw instead of remapping zero to one, so every nonzero power-of-two-width
mask has the same conditional probability.  A deterministic 300K accepted
four-bit audit needed 19,754 retries, had a maximum-minus-minimum bin count of
528, and the 8,192-lane check covered all 225 adjacent nonzero pairs.  The old
folded sampler's measured correlation reached about +/-0.565; the PCG path
stayed within about +/-0.014.  An aggregate timing control was neutral
(26.97 seconds versus 27.05 seconds), and the specialized 229 worker's profile
capacity was corrected from 80 to the actual 64 terms.

The host-generated `+1` split doors had a second diversity defect: both target
and donor were affine functions of the same lane id, so 8,192 nominal 227
shoulders collapsed to at most about `3R` presentations (75 on the r25 source).
The replacement divides doors between donor-factor splits and systematic
enumeration of every other nonzero factor mask, with the epoch rotating the
enumeration.  Consecutive 8,192-lane epochs produced 5,201 and 5,441 distinct
227 doors, and 5,507 and 5,776 distinct 228 doors.  Thirty-two reconstructed
shoulders passed exact gates, and a source-consistency guard covered all 18
worker copies; generation throughput did not regress.

The default `--rect` portfolio now contains 13 fronts:
`225,226,227,228,229,457,346,456,446,445,256,347,356`.  With the measured
12-worker CPU default it visits 12 distinct shapes per epoch and rotates the
omitted shape, instead of duplicating a front.  The rectangular CPU query path
now batches the two widest unequal factor spaces.  On 229 this raised median
throughput from 27.128 to 29.367 M moves/s (8.25%); the balanced 5x5 control was
neutral and RSS remained flat.  The coordinator also no longer sleeps after
its final portfolio child has exited.  A three-shape, three-worker, 10M-move
control fell from a 0.47-second to a 0.42-second median (10.6%).

The resulting search evidence was negative:

| Shape | Exact checkpoint | GPU moves | CPU moves | Result |
|---|---:|---:|---:|---|
| `<2,2,5>` | r18/d84 | 32.768B | -- | no rank or density change |
| `<2,2,7>` | r25/d132 | at least 68.8B | 4.070B | no rank or density change |
| `<2,2,8>` | r28/d160 | 36.0448B | 3.950B | no rank or density change |
| `<2,2,9>` | r32/d156 | 32.768B | 4.030B | no rank or density change |

The CPU runs deliberately rotated through the exact `R`, `R+1`, and `R+2`
bands where available.  The GPU totals are stated conservatively and do not
count every sampler or smoke run.  These are bounded failed campaigns, not
lower-bound certificates.

The endpoint-first k-XOR engine was then made collision-complete and its subset
selector was fixed: the old retry cap returned only 163 of 256 requested 227
subsets, while the new bounded cap returned all 256 in 329 attempts.  Every
real screen below selected 256 unique subsets.  Each 6-to-5 screen used a
384-factor pool, eight nearby factors, and 2,397,077,504 canonical query
triples; each 7-to-6 screen used a 192-factor pool, eight nearby factors, and
297,287,680 queries.

| Door | 6-to-5 fingerprint/local checks; wall | 7-to-6 checks; wall |
|---|---:|---:|
| 227 r25 | 1,300; 34.211 s | 680; 20.867 s |
| 228 r28 | 10; 3.541 s | 0; 2.147 s |
| 229 r32 base | 380; 26.667 s | 320; 12.578 s |
| 229 r32 cycle | 5,210; 54.900 s | 23,300; 57.991 s |
| 229 r32 reverse | 70; 35.002 s | 540; 12.965 s |

Collision-rich doors required additional ordinal probe dispatches, so physical
GPU thread counts exceeded the 13.4718B canonical queries.  No checked
fingerprint candidate satisfied local tensor equality, no candidate reached
the full certificate gate, and every output file was empty.  Planted rank-drop
and collision-ordinal controls still passed.  Sparse table compaction reduced
the otherwise identical 227 6-to-5 wall time from 45.328 to 34.211 seconds
(24.5%).  The engine remains an offline prescribed-rewrite tool rather than a
fleet lane.

The Rubik analogy also produced two replayable, state-dependent words.  The
literal form is `A C D B D C A` with an optional trailing `B`; the resolved
form is `A C D B X Y Z`, where `X/Y/Z` are chosen against the post-trigger
state instead of pretending that fixed flips are global group generators.
Replayed move prefixes preserve the exact tensor, and successful endpoints
return to the source rank; the planted construction temporarily carried at
most three extra local terms and produced a distance-10 endpoint with density
seven lower after 957,432 cleanup candidates.  On the real 5x5 r93 source,
all 16 selected resolved endpoints passed the full gate, 11 lay beyond complete
four-term-span coverage, and maximum term-set distance was 10.  On 229 r32, a
focused literal run returned 40/40 full-gated beyond-span-4 endpoints, ten
unique, again at distance at most 10.

Novel endpoints were not fertile.  Eight matched 20M-move continuations per
arm from the selected 5x5 d971 door gave the macro arm zero wins, the ordinary
arm two, and six ties; final basin diversity was two versus three.  The 229
d171 control gave zero macro wins, one ordinary win, seven ties, and diversity
one versus two.  Neither shape dropped rank.  Peak RSS for the focused bench
was reduced from 4.01 GB to 296 MB, but the strategy remains offline because
the matched continuation supplied negative value evidence.

Finally, the native profiler path no longer calls Ruby's nonexistent-in-
Tungsten `String#rstrip`: `tungsten symbolicate` now uses `String#rtrim`, and
both stdin backtrace and direct-token symbolication pass.  This loop found no
new exact rank record, no same-rank density record, and no provable lower bound;
its durable gains are better certified seed diversity, less biased and more
varied GPU work, faster rectangular execution, and two tested ways to request
a specific local change without mistaking search failure for impossibility.

## 2026-07-15: balanced doors, direct rank-drop goals, and final rectangular screens

The rectangular CPU scheduler now assigns its seven basin roles with an
independent staggered round-robin ticket instead of deriving both the role and
restart randomness from the same nonce.  In the first 28 assignments, the old
role counts were `3/0/3/7/4/5/6` for 227, `6/2/9/2/2/2/5` for 228, and
`3/5/3/5/3/4/5` for 229.  Every new count is `4/4/4/4/4/4/4`, and every
complete sliding window is balanced.  The side archive now treats all exact
checked-in frontier doors as fixed max-min anchors, rejects their duplicates,
and reuses the already gated states when cloning lanes.  An adversarial archive
test retained a distance-37 prior door over distance-3 near copies regardless
of input order.  A real 229 run retained ranks `[32,33,34,32]`; direct worker
telemetry showed the rank-33 and rank-34 shoulders actually scheduled as `+1`
and `+2`, rather than merely present on disk.

Multiworker windows now advance by their side-worker width instead of one
door.  On 229 with one leader, four side workers, four saved doors, and four
built-in side roles, two epochs expose all eight roles exactly once; the old
stride revisited three saved doors and exposed only five roles.  Four-epoch
counts are exactly two each, while one-worker and two-worker schedules retain
their prior behavior.  Four more ambitious productive-rebase adaptations were
neutral or worse on adoption-rich controls and were reverted.

The runnable bit was missing those 229 shoulders even though the curated public
corpus already contained them.  It now packages the exact r33/d159 and r34/d165
splits descended from the r32/d156 base.  Thus all of 227, 228, and 229 really
offer `R`, `R+1`, and `R+2` restart strata.  The added text certificates have
SHA-256 digests
`c0aebc2a46306692704943203d01a0e3f7e44826701e0e5dc839f699e9793676`
and
`888941431ee4f7a99999991eb18bda10ca015fe127e7cb1b4cb01bc659b03e6e`.

Three small changes accelerated all 18 generated rectangular Metal workers
without changing their trajectories.  The cyclic match scan uses one add and
conditional subtraction instead of variable remainder; paired endpoints were
byte-identical and 225/227/229 improved 3.5--4.8%.  An unmatched proposal now
skips zero and touched-slot duplicate scans while preserving the 4,096-step
audit, scheduled density capture, RNG, escape cadence, and step accounting.
The step-63-improvement/step-64-capture regression passes, paired logs remain
byte-identical, and this second stage improved the already optimized workers a
further 5.25%, 6.17%, and 4.68% on 225, 227, and 229 respectively.  Finally,
six signed random-coordinate mappings use one remainder plus a conditional
addition instead of two remainders.  Exhaustive equivalence holds for every
positive modulus through 122; warmed paired runs remained byte-identical and
improved the three workers another 1.34%, 1.16%, and 1.07%.  Early scan exit
and a split zero-scan shortcut were rejected because they were slower or not
repeatable.

A tempting CPU change was deliberately rejected.  Trying other factor axes
when the selected axis had no partner cut 227's miss rate from 66.47% to 1.19%
and raised accepted exact transitions from 10.10M/s to 12.69M/s, but total
attempt throughput fell from 30.82M/s to 13.15M/s.  Equal-wall continuation
showed no fertility advantage: a 1.5-second `+1/+2` comparison lost 5--3 and
produced 149 useful updates versus 230, with the same 12 rank drops.  The 229
comparisons all tied.  The fallback was reverted; more legal motion was not
more useful motion.

A 120-second three-shape campaign then executed 82,840,721,134 moves with zero
CPU, GPU, MITM, internal, or full-gate failure.  The totals and final exact
states were:

| Shape | CPU moves | GPU moves | Final state |
|---|---:|---:|---:|
| 227 | 657,488,542 | 30,146,560,000 | r25/d132 |
| 228 | 633,779,904 | 27,197,440,000 | r28/d160 |
| 229 | 612,492,688 | 23,592,960,000 | r32/d156 |

No rank, density, or lower-bound objective changed.

The newly optimized wider workers also received equal standalone search
budgets: 4,096 lanes times 500,000 steps times two continuous rounds, or
4.096B configured GPU lane-moves per shape.  The exact-gated 346 r54/d488,
347 r64/d519, and 356 r68/d634 fronts stayed unchanged after about 11.061,
19.347, and 22.775 seconds.  No improvement file or internal reject was produced.

The Rubik-style experiment was extended from finding a novel word to compiling
a requested rank drop.  Starting from an exact `R+1` split, a bounded connected
beam searches for two labelled terms that become equal on all three factors;
cancelling that duplicate pair would finish at at most `R-1`.  A planted
rank-3-to-rank-2 construction succeeded at depth two after 1,192 visited states
and 1,352 revisits, with every replay prefix exact.  Real depth-2-through-8
searches were negative: 227 checked 78 windows and 7,011,522 codes, 229 checked
81 and 7,509,348, and 3x3 checked 88 and 5,407,416.  None reached the
three-factor equality goal, so this remains an offline exact macro.

When an endpoint is known, the middle word can now be compiled rather than
guessed.  A new offline wrapper lifts a supplied `k->k-1` replacement back to
`k` terms by splitting its intended cleanup term, runs the exact bidirectional
endpoint BFS, and appends the resolved merge.  It automatically proposes final
merge pairs before bounded factor-mask fallbacks.  On the retained real 227
control it found the shortest two-move word after exploring 22 states from
each side:

1. flip the shared-U pair
   `(2,128,129),(2,512,516)` into
   `(2,512,645),(2,640,129)`;
2. merge `(4,2,768),(4,256,768)` along V into `(4,258,768)`.

The intermediate rank-26 local tensor, resolved undo word, and every prefix
are exact.  Grafting the replay into the packaged r26 shoulder independently
reconstructs and verifies the complete r25 matrix-multiplication certificate.
This closes the endpoint-to-algorithm loop for a real k-XOR result, although
that endpoint remains an ordinary neighbor rather than a new basin.

The endpoint-first k-XOR engine now also asks the direct-record questions
`7->5`, `6->4`, and `5->3`.  The first uses a collision-complete pair/triple
join; the latter two use pair and single tables against canonical pair probes.
Every fingerprint hit must pass
exhaustive local equality and complete rectangular verification.  Known-parent
endpoints and every endpoint within symmetric term distance four are filtered,
covering all immediate ordinary two-for-two flips while continuing later hash
collision ordinals.  Planted double-split r49-to-r47 controls recovered the
original exact 2x5x6 term set for both objectives; adversarial all-collision
controls preserved 20 triple, 15 pair, and six single-table ordinals.

The first apparent 227 same-rank result, hash
`836f9f44512600de8b095f1e3785df6438f46dbf1a370268f1653e482286f8fa`,
was correctly demoted to a control.  Its complete difference from the parent
was the single ordinary U-pivot flip
`(2,128,129),(2,512,516) -> (2,512,645),(2,640,129)`.  The certificate and
replay provenance are retained under `~/.tungsten/metaflip/controls/`, but it
is neither a new record nor a new basin.

Full direct-record screens were clean negative evidence.  The 6-to-4 engine
tested 256 unique pool-384 subsets for each shape, with 18,825,216 canonical
table and query pairs per shape.  It produced 36 local checks on 227 and none
on 228/229, but zero full candidate; wall times were 1.200, 0.418, and 1.421
seconds.  A deep 227 7-to-5 pass processed 98,304 candidates, 18,825,216 table
pairs, 2,397,077,504 canonical triple queries, and 2,434,531,840 dispatched
threads in 14.978 seconds.  All 70 fingerprint hits failed before the full
gate.  These engines are exact, collision-complete, and practical for bounded
offline screens, but the production GPU pool and TUI remain unchanged because
there is no frontier-value evidence.  The cheaper 5-to-3 objective also tested
256 unique pool-384 subsets per shape: each issued 18,825,216 canonical pair
queries.  The 227 run made nine local checks, 228/229 made none, and all full
gates remained empty in 246, 256, and 284 ms.  A direct 4-to-2 kernel was not
added because the same relation is represented by 5-to-3 plus one protected
spectator, and the broader screen had zero yield.

This pass found no new exact rank record, same-rank density record, or provable
lower bound.  Its retained gains are balanced independent basins, genuinely
anchored archives, real 229 rank-debt strata, faster byte-equivalent Metal
walkers, an endpoint-to-exact-word compiler, and stronger ways to formulate a
deliberate rank-drop goal.

The automatic cleanup scaffolds were also audited as restart doors rather than
credited from their raw count.  Its 64-candidate 227 control produced 11 exact
compiles, but canonical sorting of each complete r26 term set collapsed them to
only five distinct shoulders; six hits were duplicate presentations of the
same split.  All five are exact split preimages of one exact r25 endpoint (that
endpoint is not term-set-identical to the packaged catalogue presentation).
Each was paired with a distinct ordinary r25 split at exactly the same initial
density; controls used the same parent and axis where possible and otherwise a
deterministic exact-density split elsewhere in the same scheme.  Every
door/trial pair had a unique seed, the two arms shared that seed, and both ran
the production 10% focused / 70% adaptive / 20% wander phase mix.

At 32 trials per door and 2M moves per arm (160 pairs, 640M total moves), the
structured shoulders lost 42--96 with 22 ties.  Neither arm reached r24;
structured shoulders returned to r25 in 156/160 trials versus 159/160 controls,
with mean final densities 153 versus 147.  Their best endpoints were r25/d134
versus r25/d132, and exact canonical endpoint diversity was 142 versus 141
(15 shared), so novelty did not translate into fertility.  An 8-trial-per-door
10M continuation likewise lost 12--20 with eight ties, no r24, and mean density
150 versus 145.  These preimages therefore remain out of the production restart
inventory.  The decision runs were compiled with
`tungsten compile --release --native --lto --fast` and invoked as
`rank_debt_preimage_probe 32 2000000` and
`rank_debt_preimage_probe 8 10000000`; the temporary probe was removed after
the audit rather than shipped in the bit.

## 2026-07-15: complete default GPU coverage and coupled cleanup goals

The last three CPU-only fronts in the default rectangular mix now have
specialized pure-Tungsten Metal workers.  `<4,4,6>` uses CAP128, 16 threads per
group, and 24,576 threadgroup bytes; `<4,5,6>` uses CAP152, 16 threads, and
29,184 bytes; the full-width `<4,5,7>` worker uses shared `i64` masks, CAP168,
eight threads, and 32,256 bytes.  Measured search rates were approximately
161.4M, 129.9M, and 80.3M moves/s respectively.  A 2.048B-move decision run on
each left the exact r73/d690, r90/d906, and r104/d1089 leaders unchanged.  The
default 13-shape portfolio is consequently fully GPU-backed, but this coverage
gain is not a record.

The worker cache also no longer equates a missing offline `metal`/`metallib`
toolchain with a missing GPU.  Generic, C3, SIMD-group, rectangular, MITM, and
pool bundles can dispatch the compiler-emitted sibling MSL through runtime
Metal.  An injected `xcrun` failure completed a real 446 dispatch through that
path; an empty sibling source still failed hard.  Absence of the optional
offline cache tier therefore no longer marks the GPU DEGRADED, while real
build, source, or dispatch failures still do.

The direct-rank-two k-XOR screen was widened from the three 2-wide controls to
the full rectangular seed set.  Across 48,128 bounded subset evaluations
(46,330 distinct selected index sets), the GPU enumerated 1,156,497,408 table
tuples and 11,478,204,416 query tuples.  `5->3` covered all 21 supported
fronts; `6->4` and `7->5` covered the 13 primitive or high-composition-leverage
fronts for which those objectives were meaningful.  Six 128-bit fingerprint
matches appeared, all in the 227 `6->4` screen, and all six failed exact local
tensor equality.  No full certificate check or accepted rank drop followed.
This is a broad sampled miss, not a lower-bound proof.

Two more literal Rubik-style cleanup compilers tested whether temporary rank
debt can expose a prescribed two-rank close.  The four-line catalyst adds the
cancelling pair `C+C`, walks the exact fixed-rank flip graph, then removes four
terms sharing two factors whose remaining factors XOR to zero.  Positive
controls verify exact `3->1`, `5->3`, `6->4`, and `7->5` envelopes; the
nontrivial `3->1` plant closes after three flips at catalyst ordinal 5 and BFS
node 89.  On real seeds, depth-three searches over `q=5,6,7` across all 21
fronts visited 20,323,645 orbit states and tested 717,708,537 flip codes.  A
depth-four census on 227/228/229 added 48,379,342 states and 1,690,981,920
codes.  None of the combined 68,702,987 states exposed a four-term zero line.

The coupled double-annihilation macro instead splits two distinct source terms
(`R -> R+2`), resolves a state-dependent ordinary-flip word, and asks for two
different duplicate pairs whose cancellation would finish at `R-2`.  Its
explicit rank-4-to-rank-2 fixture uses setup splits on source labels 0 and 1,
then the exact forward codes `36,40,35` and independently resolved undo codes
`35,40,36`; all prefixes verify, and BFS finds the endpoint after 911 states
and 2,198 legal edges.  The real depth-one-through-six census used 3,072 setup
searches on 225, 227, 229, 256, 346, 445, 456, and 457.  It visited 11,721,598
states, tested 370,312,434 codes, admitted 46,936,086 legal edges, and found no
two-doublet goal.  Reusing one BFS workspace reduced the earlier prototype's
peak RSS from about 2.927 GB to 24.56 MB; the current eight-front run completed
in about 7.7 seconds.  Both cleanup compilers remain exact offline scouts, not
production lanes.

Two coordinator lifetime costs were removed without changing search
trajectories.  Rectangular CPU islands now keep one OS thread for the campaign
lifetime and synchronize through a round barrier; each parked worker reloads
its state slot, so fleet-best rebases still take effect.  Exact output and
counters matched the prior implementation on 225 and on 100-round
229/256/446/456/457 controls.  Ordinary throughput stayed within about 3%, RSS
fell 5--9%, and a 10,000-tiny-round stress fell from 107 to 95.3 MB and from
30.6B to 22.9B retired instructions.  Separately, one byte-level pass now
parses all child-status fields.  Fifty thousand full parses fell from 1,231 ms
and 948.4 MB of allocation to 33 ms and 2.36 MB with identical values and
fallback semantics.

The new strategy sources also exposed two compiler/bootstrap ambiguities.
`moves/10` was lexed as one arity-bearing identifier instead of identifier,
slash, and integer, while the bang in `value!=1` could be swallowed into the
identifier. Numeric `/N` arity is now recognized only after a method name, and
bang suffixes stop before `!=` and `!~`. The C bootstrap gained the matching
positional-argument, nested-type-hint, packed-numeric, and hash-delete support.
A remaining stage-identity failure was traced to the generic `size` fast path
returning zero for `StringBuffer`, which made stage 1 empty `%w[...]` literals;
the correct buffer length plus an explicit dependency on the shared VM call
body restored a verified byte-identical stage-1/stage-2 LLVM fixed point.

No experiment in this section found a new exact rank record, same-rank density
record, or provable lower bound.  The retained result is infrastructural:
complete GPU coverage, a reliable runtime-MSL fallback, cheaper long-lived CPU
coordination, and two exact formulations of the desired coupled rank drop whose
bounded real-frontier searches were negative.

The next clean experiment should therefore be endpoint-first: retain the
lowest-weight syndromes from near-miss k-XOR joins, let a small CPU SAT or
set-cover repair vary one or two spectator terms, and only then feed an exact
replacement to the rank-two word compiler. This attacks the observed scarcity
of cleanup endpoints directly instead of spending default lanes on forward
walks toward a very thin two-doublet or four-line target set.

## 2026-07-16: twelve-move intake wave and the in-process CDCL

Twelve new move lanes from the ranked ideation campaign landed as
pure-Tungsten move-lab intakes, every one with planted regressions and a
bounded real-frontier smoke (all `flipfleet_<lane>_test.w` passing; the
full table with measured numbers is FLIPFLEET_MOVE_LAB.md "Twelve-move
intake").  Shared infrastructure: `flipfleet_sat_cdcl.w`, an in-process
incremental CDCL solver with assumption cores and conflict budgets, so
SAT lanes stop paying process + DIMACS costs per query and can narrow
incrementally.

New exact artifacts and certified closures banked by the intake tests:

- **A gated rank-7 2x2 scheme invariant under the cyclic index rotation
  (i,j,k) -> (i+1,j+1,k+1)** (7 = 2*3 + 1), found by the cyclic-sandwich
  ansatz cell (3,1) in 3.8k conflicts.
- **The <2,5,2> rank-17 psi-symmetric cell (8 pairs + 1 fixed) is
  certified UNSAT** -- the first exact closure inside the certified
  <2,2,5> gap (17 <= R <= 18).  The remaining (c, f) partitions of the
  psi class are enumerable cells; the pinned naive-witness control
  validates the encoding at target scale.  Strassen itself is
  psi-symmetric (2 pairs + 3 fixed) and every psi-symmetric rank-7 2x2
  scheme needs at least three fixed terms.
- Equivariant surgery speaks the frontier's language: d1155's C3 census
  (30 free orbits + 3 fixed cubes) confirmed; planted orbit and cube
  re-derivations SAT instantly; the excise-2-orbits -> (1 orbit + 2
  cubes) net-minus-one cell is certified UNSAT on naive 3x3 AND within a
  3k-conflict budget on the live d1155 frontier; the 5x5-scale
  equivariant instance (62.5k vars / 281k clauses) solves its planted
  probe in 26 ms, so frontier orbit-drop cells are genuinely runnable.
- Ball-SAT certifies slot-aligned rigidity radii (naive 2x2: radius 4)
  and descends the planted split-above-Strassen anchor at radius 1.
- Negative knowledge, measured where the ideation predicted risk: the
  rank-93 presentations carry zero cyclic sandwich symmetry; Strassen
  stays flip-isolated even over GF(4); pair-lift children unwind to
  their parents through the block projection at mixing depth 4; the
  incremental-surgery core-lift factor is 1x on tiny pools.

Scheduling: `flipfleet_move_intake.w` rotates the twelve lanes as
bounded occasional options with the pool's dwell discipline, persistent
accounting, a strict yield-versus-closure split, and a promotion print
that points at the GPU_KERNEL_POOL.md registration recipe once a lane
earns pool width with verified wins.  None starts with live width -- the
standing rule that negative experiments stay reproducible benchmarks.

## 2026-07-16 (evening): psi rank-17 class 5/9 closed, two pair-lift doors

The <2,5,2> (rotated <2,2,5>) rank-17 psi-symmetric class now has FIVE of
its nine (pairs, fixed) partition cells certified UNSAT: (8,1), (2,13),
(1,15), (0,17) by the in-process CDCL (flipfleet_psi252_campaign, lex
SBPs, budget-scaled arenas), and (3,11) by cryptominisat5 in 68 seconds
on the exact DIMACS export (ffcdcl_dump_dimacs) -- the first
independent-solver confirmation lane.  The four open cells (7,3), (6,5),
(5,7), (4,9) resisted 600-818k in-process conflicts AND 30-minute
cryptominisat slots each; the hardness concentrates where the pair and
fixed counts balance.  Next levers: XNF export with native x-lines so
Gaussian elimination sees the row structure, and hour-scale timeouts.
A full 9/9 would prove no psi-symmetric <2,2,5> rank-17 scheme exists;
any SAT is an outright record.

The pair-lift crossover is now a working door factory: two new exact
<2,2,5> rank-18 doors checked in (d87 at distance 4 from d84; d91 at
distance 4 from d88; mutually far), both regenerated deterministically
and re-gated from file bytes.  The twelve-lane intake runner promoted
pair-lift on its first verified yield; suture sweeps over the new door
pairs are logged clean negatives with informative defect-rank profiles.

## 2026-07-17: psi-symmetric rank-18 witness and its local rigidity

cryptominisat found the (6 pairs, 6 fixed) rank-18 cell SATISFIABLE on
the exact export; the decoded, gated witness is checked in as
`matmul_2x5x2_rank18_psi_symmetric_gf2.txt` (density 110) -- the first
psi-symmetric <2,5,2> rank-18 scheme.  The psi class is therefore
INHABITED at 18, so the five certified rank-17 cell closures speak
about rank, not vacuous symmetry.  The four open rank-17 cells
((7,3), (6,5), (5,7), (4,9)) also survived hour-long cryptominisat
runs on native-XOR (XNF) exports with Gaussian elimination -- parked as
deeply hard.

psi-equivariant descent surgery (flipfleet_psi252_descent, the
equivariant-surgery pattern transplanted to the transpose involution)
then swept every (<= 2 pairs, <= 2 fixed) excision of the witness
against every one-fewer-term psi-invariant replacement profile: all
156 residual instances CERTIFIED UNSAT with zero indeterminates, in
seconds each.  The witness is psi-locally rigid at excision depth
(2,2) -- the psi-analog of k-local minimality, and a genuinely new
certificate class for the campaign.

### 2026-07-17 loop postscript: steady state

The rank-18 witness hunt closed out: (8,2), (7,4), (5,8) all
indeterminate at hour-scale cryptominisat, so the psi rank-18 class
stands at one checked-in witness, (9,0) certified empty, three cells
open.  psi-descent now runs in the thirteen-lane intake rotation
(depth (2,2) per occasional pull, ~170 certified residuals each);
deeper progress on the rank-17 gap needs day-scale solver budgets on
the four balanced cells or a new structural idea (psi x C2 combined
quotients, descent from non-rigid witnesses yet to be found).
Reproduce: /tmp-built drivers flipfleet_psi252_{campaign,export,
export_xnf,decode,descent} and flipfleet_move_intake_run, all
checked in.

## 2026-07-17: cloud density campaign and support-component peeling

A six-phase NUMA-sharded 7x7 CPU campaign on one `m8i.96xlarge` executed
11,493,501,799,890 supervised moves.  One n4 shard, started from the exact
rank-247/density-3096 dynamic-syzygy door, first reported an exact d3095
checkpoint at 735,308,184,180 cumulative shard moves.  The preceding
checkpoint was d3096 at 732,405,155,878 moves, so the winning reporting
interval was at most 2,903,028,302 moves.  No shard reached rank 246, and the
final two d3094-seeded phases added 3,724,378,944,384 moves without improving
rank 247/density 3094.  Every supervisor stopped by an explicit signal or
deadline; final OOM and stale-worker counters were zero.

The important result was hidden inside the live endpoint.  Reconstructing the
four legal flips from d3096 to d3095 showed that the first three already reach
an exact rank-247/density-3094 scheme, while the fourth is disjoint and worsens
density by one.  The retained endpoint shares 244 of 247 terms with d3096,
has symmetric support distance six, and has axis densities `1020/1022/1052`.
Its certificate SHA-256 is
`56277df5a94ebfa161e25d34d82c0479f2a8ad07e51a224cdb772fcba7a935b5`.
Independent host and pure-Tungsten reconstructions agree on all `7^6`
coefficients; a deterministic pure-Tungsten replay gates every intermediate.
The affected three-term component has only eight ordinary-flip states, and
d3094 is density-minimal within it.  This is a same-rank density improvement,
not a new rank bound.

That audit yielded a reusable move.  For two exact parents `A` and `B`, their
symmetric difference is a zero tensor.  Connect two delta terms only when
their Cartesian supports intersect on all three axes.  Disconnected graph
components occupy disjoint tensor cells, so every component is independently
a zero relation and may be toggled without taking the full parent difference.
The d3096/d3095 delta has ten terms and splits `6+4`; peeling the six-term
component deterministically produces d3094.  The implementation independently
gates both parents, every component relation, all materialized children, and
the winner.  One hundred fully gated 7x7 calls averaged about 1.5--1.7 ms.
It now runs only on cold same-rank-density intake and in the single
differential child before general nullspace elimination; the differential
threshold is six while ordinary archive novelty policy is unchanged.  CPU,
GPU, and late-GPU adoptions record the component and origin in durable best
provenance.  Ordinary worker loops pay no additional cost.

The A40 companion campaign exercised five independent 7x7 roots through
leader, original, and descendant roles.  Across five production phases it
executed 1,195,540,480,000 CUDA attempts and 93,616,304,225 compatible-partner
checks in 5,974.468 kernel-seconds.  It emitted 592 exact candidate events
with zero exact rejects, maintained a 32-door archive, and finished at
rank 247/density 3094; it did not find rank 246 or a denser rank-247 endpoint.
ECC counters remained zero through shutdown.

The rectangular half of the CPU campaign found an exact `<2,2,7>` rank-25
density-128 presentation, improving the packaged d132 density leader.  The
first reporting barrier with d128 was at 25.469 billion cumulative shape-local
moves, and the previous d130 barrier was at 25.357 billion; the full discovery
cost is therefore at most 25.469 billion moves and the final reporting interval
at most 112 million.  The certificate hash is
`bf071351b20e442a1d3b532bff5bf534a1b22b00ac75f657c3da4c2265d5515c`,
and its support distance from d132 is 42.  Metaflip now starts 227 from d128
but retains d132 and the rank-26/rank-27 controlled-debt shoulders.  Matched
wide-front controls also justified increasing rectangular side-door capacity
from four to eight: 467 and 466 filled all eight with no material throughput
loss, while 346 correctly retained only four eligible doors.  The final
4,200-second structural portfolio executed 10,784,929,500,000 moves with
zero failures and found no additional rank or density improvement.

Operationally, square bests now have additive machine-readable provenance in
the status heartbeat and an atomically replaced `<best>.provenance` sidecar.
The record covers seed/recovery, CPU island, dedicated and pooled GPU, live and
late rectangular composition, late GPU drain, reset, and global-isotropy
postprocessing.  Telemetry failures remain nonfatal, and neither square nor
rectangular TUI rendering changed.

## 2026-07-18: cyclic braid-collision closure audit

The pure-Tungsten offline audit exhaustively tested the three corrected cyclic
braid paths for every eligible ordered source/donor pair in 108 exact
record-rank frontier seeds: 53 square seeds across six shapes and 55
rectangular seeds across 28 shapes.  Six packaged rank-debt shoulders were
excluded.  The scan covered 1,636,532 ordered pairs, 1,632,542 pairs whose
factors differ on every axis, and 4,897,626 U/V/W paths.  All paths had zero
generated outputs already live (`c=0`): there were no direct-edge collisions,
middle-output neutral-then-merge collisions, or `c=2/3` closures.

Three planted `3x3` rank-24 shoulders, one per cyclic orientation, each
recovered the exact rank-23 source through a middle-only `c=1` collision and
passed the complete coefficient gate.  The release audit took 0.40 seconds
wall time (about 29.3 million paths/second).  Keep this closure as a cheap
offline intake audit for newly banked schemes; the present corpus does not
justify a production CPU or GPU lane.

## 2026-07-18: rectangular braided re-arm is reversible churn

A paired pure-Tungsten benchmark compared the current init/rebase-only braided
debt policy with conditional `+1/+2` re-arming whenever a `3x4x6` island reached
`current == best` with zero partnerable incidences.  Across both checked-in
rank-54 doors, 32 trials x 32 production-shaped rounds x 500,000 moves gave
1.024 billion matched moves per arm.  All 1,984 re-arms were exact, but both
arms had zero rank wins, zero density wins, one endpoint per door, and zero
term-set distance from their source.  Re-arming increased accepted moves by
19% and 55%, but only as reversible churn; guard plus setup cost 0.61% and
1.35% of phase time.  Five-million-move rounds and a higher-frequency
128-round stress test likewise produced no distinct endpoint or useful win.

A separate 1,024-nonce lifetime audit found that more than 93% of both `+1`
and `+2` shoulders collapsed back to the exact zero-partner wall within 1,000
focused moves; every GL-frontier shoulder closed by 109,755 moves.  Keep
braided debt at initialization and explicit rebase only.  If revisited, place
a structurally deeper escape after the focused-work bookend rather than at a
round boundary where focused work immediately unwinds it.

## 2026-07-18: post-focus braided debt also collapses

The suggested post-focus alternative was screened in pure Tungsten with
independently re-keyed focused, adaptive, and wander phases.  Across both
checked-in `3x4x6` rank-54 zero-partner doors, eight trials of all seven
control/init/post-focus/re-arm schedules at 100 million moves executed 11.2
billion matched, exact-gated moves.  Every schedule had zero rank wins, zero
density wins, one final current endpoint, one best endpoint, and zero exact
failures.  All 63 eligible post-focus/re-arm injections collapsed to the
identical rank-54 wall.  A preceding 10-million-move screen observed another
253 successful injections with the same null result.

The six live leaf targets are not eligible: their 11 checked-in
presentations have 8--38 partnerable incidences, and focused work reached an
exact zero-partner best/current wall in zero of 88 matched trials (including
`3x3x4` and both `3x4x4` doors).  Reject post-focus braided injection for
production; retain init/rebase-only braid on genuinely zero-edge starts.  The
reproducible decision benchmark is
`spec/rect_post_focus_braid_bench.w`; no production or TUI path changed.
