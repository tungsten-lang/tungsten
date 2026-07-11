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

### FlipFleet audit and replacement path

The native `flipfleet.w` retained several correctness and campaign defects:

- it was hard-coded to 5×5;
- a cycle-out retained only best rank/density scalars and discarded the actual
  best decomposition;
- CPU candidates were adopted before its randomized verifier ran, and validity
  did not gate best bookkeeping;
- a failed GPU load remained installed in the fleet;
- every explorer was reset to one leader every 3M moves, collapsing diversity;
- the claimed same-rank density archive read a snapshot updated only on strict
  rank drops;
- the structured plus transition was W-only.

`flipfleet.py` is now the sound campaign driver for 3×3 through 6×6.  It builds
the fast Tungsten hash-chain walker for the requested format, exact-verifies
every candidate before adoption, atomically archives every distinct frontier
snapshot surfaced to the coordinator, retains the full best scheme across restarts, defaults to persistent
islands with partial migration, can start from the tracked record schemes, and
uses random-axis plus transitions by default.  Same-rank density snapshots now
flow through an exact-gated spool into that archive (rather than being silently
ignored), and stale or repeatedly invalid worker dumps cannot steer migration.
A ten-second, two-walker 3×3 run seeded at the record retained **42 distinct,
exact-valid rank-23 schemes**, with zero invalid candidates; the old native
status snapshot was still at rank 106 after 720 seconds on 5×5.

The restart sample is now bounded and diversity-aware: all exact snapshots seen
by the coordinator remain durable, while memory maintains an online max-min sample under
term-set symmetric-difference distance and restarts from least-used entries.
On a live rank-23 stream, an eight-slot archive made 9 replacements and retained
minimum pairwise distance 34 (out of a maximum 46), rather than filling with
near-duplicate ties.  Durable archives are exact-gated and rehydrated on a
resumed run.
The displayed/checkpointed leader is ordered by rank and then density, so an
equal-rank improvement now updates `best.txt`, status cost, and the performance
curve without collapsing the separated restart sample.

Record scheduling also had a hidden trigger bug: its special dwell budget
tested the transient live rank, normally 24--25 during an excursion, instead of
the saved best rank 23.  That silently bypassed the requested record budget.
The generated walker now tests `best_rank`, reads the budget at runtime, and
the fleet assigns a mixed 250M/1B/10B portfolio so short-horizon islands recycle
through term-set-separated seeds while other islands retain the original deep search.
A forced short-budget smoke test produced four clean cycle-outs and three real
frontier reseeds while remaining exact.

Examples:

```sh
# From naive, persistent independent islands.
python3 benchmarks/matmul/metaflip/flipfleet.py \
  --size 3 --walkers 12 --strategy independent --secs 60

# Push from the exact tracked frontier; stop only on a verified record.
python3 benchmarks/matmul/metaflip/flipfleet.py \
  --size 5 --seed record --walkers 12 --strategy islands --stop-on-record
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

`flipfleet.py --escape-kind {split,break,orbit-split,polarize}` now injects the
same exact identities without a separate seed-preparation step.  `split`
selects any term and therefore covers the fixed-free tracked 3×3 and 4×4
records; the other three retain their fixed-cube/C3 eligibility rules.
`--escape-at` chooses startup, genuine cycle-out, or both, while
`--escape-every N` deterministically interleaves escaped and base launches.

The escape is strictly a one-launch excursion.  It is always derived from the
unmodified frontier selected by the coordinator, never recursively from an
escaped seed.  Escaped higher-rank seeds do not replace `initial`, `best.txt`,
the density leader, the restart archive, or the configured world record.
Migration, quarantine, and ordinary exits do not receive escapes.  Every
generated seed passes factor bounds and full exact reconstruction before the
native process can launch; C3-preserving kinds receive an additional closure
check.  Dynamic ineligibility is an explicit logged fallback, while an
ineligible startup fails before compilation.  Event provenance includes kind,
trigger, base/output rank, fixed count, C3 state, selected factor/cube, part,
axis, and canonical base digest; `status.json` reports
considered/applied/bypassed/skipped counters.
The compiled walker itself remains non-quotient, so it may leave C3 after a
C3-preserving injection.  If identity collisions make an escape tie or beat
the frontier, its published worker dump is still exact-gated and adopted as a
normal candidate.  Recovery preserves the requested eligibility profile, so a
C3 seed is not replaced by a non-C3 density tie before an orbit escape starts.

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
C3-closed with three fixed terms.  The tracked 6×6 record is also invariant
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
is now the default cost-oriented 5×5 frontier; `--seed c3-record` selects the
density-1191 C3 scheme for orbit-split/polarization.  Rank and no-CSE base-case
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
| ⟨7,7,7⟩ | 343 | 249 → **248** | Kauers–Wood meta flip-graph (arXiv:2510.19787) pushed 249→248 via Perminov's ternary meta flip-graph (arXiv:2511.20317, GPU population search, N=16384, 24-72 GPU-hours/run) |

**Corrected note:** an earlier session mis-attributed "777=250" as a
Perminov/GF(2)-flip-graph result — it is actually Sedoglavic 2017
(arXiv:1712.07935), a general-ring algebraic construction unrelated to
flip-graph search and not GF(2)-specific. It sits 2 ranks above the real
frontier (249→248); an entire day's siege from a seed AT 250 (~1.5 trillion
moves, zero descents) only shows Sedoglavic's construction is a local optimum
for our move set — it says nothing about flip-graph reachability of 249/248.

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
`seedid = tid % nseeds`.  `flipfleet.py --gpu` generates, compiles, launches,
and exact-gates this relay.  The default is 256 basins; one restores the old
single-seed experiment.  Portfolio construction is outside the move loop, and
the kernel pays only a one-time seed offset at initialization/reset.

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
MSL (`device int/long`, `threadgroup int/long`).  This Codex sandbox exposes no
default Metal device and lacks the offline Metal toolchain, so on-device timing
and execution remain a required pre-campaign gate; no speedup is claimed yet.

Why not GPU SAT now: the current 4×4 large-k surgery model failed to solve even
the known rank-47 SAT control in 280 seconds.  A GPU SAT/XOR solver would be a
new solver project, while exact-basin portfolios reuse the already measured
11.6× threadgroup-memory kernel and diversify it at essentially zero hot-loop
cost.  Grinding a single fleet best remains available with `--gpu-escapes 1`
as the control arm.

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

- "⟨7,7,7⟩ = 250 is the GF(2) record" — **wrong**, see the record table note
  above (Sedoglavic 2017, not flip-graph, not GF(2)-specific).
- "5×5 record is 95" / "94 is the barrier" — an earlier session's
  literature check found 95/94 based on an incomplete record lookup; the
  verified, corrected record is 93 (Moosbauer-Poole), reflected in the table
  above. Anything referencing "95" or "94" for 5×5 elsewhere in old session
  logs is from before this correction.
