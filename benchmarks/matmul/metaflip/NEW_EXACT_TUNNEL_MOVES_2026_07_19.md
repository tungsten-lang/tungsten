# New exact tunnel moves: measured intake

This note records the move search performed after the rectangular AWS campaign
was stopped on 2026-07-19.  The goal was not to add more names to the GPU pool;
it was to find exact operators that cross barriers the current atomic moves do
not cross, build pure-Tungsten controls, and reject weak proposal distributions
before they reach production.

Every retained endpoint below is checked by an exact local tensor gate.  Real
matrix-multiplication endpoints are rebuilt and independently checked against
all tensor coefficients.  None of these prototypes is scheduled by Metaflip
yet, and no TUI code was changed.

## Decision summary

| Move | Strongest evidence | Decision |
|---|---|---|
| fixed-rank flip-pocket closure | 102 distinct real C013 relations of size 3--8; all close in 2--5 flips, and 30 improving orientations require leaving the default density-slack envelope | best CPU-resident candidate; run a matched campaign before promotion |
| coupled multi-codeword bucket kernel | planted 9→7 where either constituent stays at 9; two independently full-gated rank-93 5x5 doors at support distance 10 and 14 | best algebraic GPU candidate; add a sparse experimental sampler only after continuation scoring |
| kernel-line fiber completion | exact rank-6 endpoint at distance 12 outside an exhaustively enumerated three-state ordinary-flip component; every proper lift subset pays +1/+2 rank | genuine component bridge; keep in the lab until a rank-metric real-frontier search replaces random masks |
| paired nonzero-defect cancellation | exact planted 6→4 and a fast dual-hash join; 99.2M naive real proposals produce no hash hit | identity is useful, current proposal generator is not; keep offline |
| mixed-span primitive 9-circuit | exact 5→4 circuit with factor-span signature `(3,2,2)`, absent from the fixed `(2,2,2)` cardinality-nine template | valid missing circuit type, but current real fits are only +3; keep offline |

## 1. Fixed-rank flip-pocket closure

`flipfleet_fixed_rank_pocket.w` searches the complete bounded ordinary-flip
graph of a selected 5--8-term pocket and applies the resulting word atomically.
The endpoint is exact at every edge, but the fleet does not have to admit the
intermediate density-debt states as island leaders.

The strongest evidence is data-driven.  Comparing 759 exact rank-247 C013
archive candidates with the C013 seed yielded 102 distinct nontrivial local
relations of size 3↔3 through 8↔8.  Every relation has a shortest ordinary-flip
word of depth 2--5, and the bidirectional searches met after at most 87 local
states.  Ninety-eight relations have a lower-density orientation.  Thirty of
those 98 cannot be traversed with the production `DSLACK=4` edge gate even at
depth ten; weighted by archive occurrence, that is 43 productive pockets the
normal work zone suppresses.

The representative 7x7 C013 5↔5 word has local densities

```text
105 -> 101 -> 111 -> 102 -> 93
```

so a net density win of 12 requires one `+10` edge.  The 6↔6 word leading from
d3554 toward d3492 similarly needs five flips and a `+10` intermediate edge.

The checked-in generic regression uses the smaller real rectangular closure:

```text
2x2x5 d92 -> d84
depth:       0   1   2   3   4   5
density:    92  89  90  88  86  84
```

The bounded BFS finds the target first at depth five in 14 retained states.
Depth four and monotone-density search both miss.  This fixture is not blocked
by `DSLACK=4`—its one uphill edge is only `+1`—so the regression makes only the
true depth/monotonicity claim.  It freezes the other thirteen terms, rebuilds
the full rank-18 scheme, and passes the complete rectangular tensor gate.

The prototype is an oracle-window closure: two known exact endpoints define
the pocket, after which the BFS rediscovers the word without seeing its path.
Production still needs the proposed support-overlap pocket selector and a
ticket-to-hit benchmark; the corpus result proves the closure is useful, not
that autonomous selection is already solved.

Recommended first production experiment: one low-cadence coordinator CPU
resident, rotating `k={5,6,8}`, depth at most five, and node caps 128/128/256.
Admit density wins and rank drops; archive neutral endpoints sparsely.  Target
less than one percent aggregate CPU displacement.

## 2. Coupled multi-codeword bucket-kernel descent

Fix one factor axis and group the subtotal as

```text
sum_i f_i tensor M_i.
```

For codewords `z_j` in the kernel of the factor matrix and arbitrary
complementary matrices `D_j`, the simultaneous repaint

```text
M'_i = M_i xor sum_j z_j[i] D_j
```

is exact.  Minimal refactorization is nonlinear: two overlapping corrections
can help jointly even when neither helps alone.  This strictly extends the
one-codeword/common-`D` dependency medians.

The planted control uses all seven nonzero factors in `F_2^3`, overlapping
triangle codewords `{1,2,3}` and `{1,4,5}`, and distinct rank-one matrices
`D1=0x1`, `D2=0x2`.  The source bucket-rank sum is nine.  Applying either
correction alone leaves it at nine; applying both gives an exact rank-seven
subtotal.

A bounded triangle/rank-one scan over representative 3x3--7x7 records found no
rank drop.  It did find genuine nonlinear synergy throughout the corpus and
two rank-neutral 5x5 doors:

| Source | Individual ranks | Coupled rank | Support distance | Density delta | Full gate |
|---|---:|---:|---:|---:|---:|
| rank-93 d1155 | 93 / 94 | 93 | 10 | +8 | pass |
| rank-93 d983 | 93 / 94 | 93 | 14 | +4 | pass |

The d1155 door is a checked-in deterministic regression.  The d983 replay was
independently compiled and full-gated during intake.  These are archive doors,
not objective wins.  Their value must be measured by descendant yield before
scheduling.  The search maps well to a GPU: enumerate low-weight factor-kernel
codewords and rank-one `D` values, evaluate bucket rank deltas, and beam/join
over overlapping corrections.

## 3. Kernel-line fiber completion

For one factor axis and nonzero line generator `q`, project factors modulo
`<q>`.  Every choice of quotient-term lifts leaves a residual of the form

```text
q tensor M.
```

The existing exact GF(2) matrix factorizer gives the minimum completion rank of
`M`.  This turns a speculative projection/completion holonomy into a concrete
operator with no smaller matrix-multiplication catalog dependency.

The planted rank-six fixture projects to four quotient terms.  Toggling all
four lifts returns another exact rank-six scheme at term-set distance 12.  All
14 nonempty proper lift subsets have completion rank three or four—ten pay
rank `+1`, four pay rank `+2`.  The ordinary fixed-rank flip component of the
source has exactly three states and does not contain the endpoint.  Stored
relation replay is involutive, and corrupt or partial recipes fail closed.

This is distinct from whole-format projection replacement, from symmetry-orbit
quotients, and from the current two-term absorbed shear.  A naive random
real-frontier mask screen did not find a useful neutral endpoint.  The next
honest test is a rank-metric MITM/beam over lift masks, not a fleet lane fed by
random subsets.

## 4. Paired nonzero-defect cancellation

A local proposal need not be exact by itself.  Define

```text
delta(A -> A') = tensor(A) xor tensor(A').
```

If two disjoint proposals have the same nonzero defect, applying both is exact.
The prototype enumerates 3→2 proposals for two windows, joins two independent
linear defect hashes, compares the complete defect bitsets, and independently
checks the returned relation.  Its planted fixture recovers an exact 6→4 move
with defect `0x08`; 1,000 repeated joins take about one millisecond in the
release build.

The first real decision screen sampled 100,000 disjoint-window tickets from the
packaged 2x2x5 rank-18 seed.  With a 32-term span pool per side it generated
49.6M proposals on each side—99.2M total—and found zero dual-hash hits, exact
defect matches, or rank hits in 15.021 seconds.  The move remains promising for
GPU hash joining, but only after proposals are generated from structured
low-rank residuals rather than arbitrary factor-span pairs.

## 5. Missing mixed-span primitive circuit

The identity in `flipfleet_coupled_dependency_repaint.w` is a primitive
nine-term zero circuit with factor-span signature `(3,2,2)`.  One side has five
terms and the other four.  The existing cardinality-nine template has signature
`(2,2,2)`, so no injective image of that template covers this circuit.

The exact 5→4, reverse 4→5, and all axis-permutation controls pass.  Complete
side recognition finds no occurrence on representative 2x2--7x7 records.
Exhaustive mixed-span fitting on the second rank-23 3x3 door scores 164 exact
images in 2,585,016 fits, all with only the three fitted overlaps: the best
endpoint is rank `+3`, with no `+1`, neutral, or drop.  Ten-million-fit prefixes
on representative 4x4--7x7 doors find no consistent image.  This is a valid
new circuit orbit, but not evidence for a resident.

## Additional exact families not yet implemented

Three follow-ons remain mathematically clean:

1. **Circuit 2-sum / hinge elimination.** Join two fitted zero circuits on a
   shared nonlive rank-one hinge and cancel it, producing a higher-span dynamic
   relation.  Cache circuits by hinge and score their symmetric differences.
2. **Cross-automorphism defect matching.** Join nonzero subset defects from
   two different tensor automorphisms.  This is a structured proposal source
   for paired-defect cancellation and strictly extends one-generator partial
   automorphism nullspaces.
3. **Balanced block barter.** Given two local decompositions `P,Q` of the same
   tensor and a disjoint isomorphic block `g`, exchange
   `P + g(Q) <-> Q + g(P)`.  This transports rank debt between composition
   seams without exposing global debt.

The promotion order supported by current evidence is: flip-pocket first,
coupled bucket-kernel second, kernel-line fiber after a better mask engine,
paired defects only after a better proposal generator, and the mixed-span
circuit last.
