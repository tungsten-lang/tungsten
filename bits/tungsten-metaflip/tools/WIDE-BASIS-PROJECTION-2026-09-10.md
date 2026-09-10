# Native wide basis and coordinate-projection proposals

The native operator set now includes rank-neutral shared-factor basis changes
and coordinate restrictions for packed tensors up to 1,024-bit factors and
16,384 terms. A bounded real-tensor sweep finds **19x27x28/r8109**, improving
the retained r8129 witness by 20 terms. Independent algebra replay and the
full tensor check pass. The saved external comparison is still **r7983**:
this is a local improvement, **not a world record or a fresh public audit**.

## What is integrated, and what is not

Normal narrow candidates already enter native background matrix compression,
basis proposals, coordinate projections and incremental composition, including
rank ties. The [previous wide integration](NATIVE-WIDE-REFINEMENT-2026-09-10.md)
also applies bounded strict matrix cleanup to verified composition outputs.

This change adds the remaining *wide operator primitives*, not their recursive
queue policy. The ordinary wide composition queue still runs strict cleanup;
it does not automatically run the campaign below. This study's bounded Python
driver invokes native Tungsten operators and the native full verifier. Python
is orchestration and an independent test oracle, not a new runtime dependency
of `bin/metaflip`. No live flip/GPU worker, canonical seed or archive is changed.

`ffwm_refactor` in `composition/matrix_cleanup.w` makes one bounded one-axis
basis proposal, selecting independent columns in ascending or descending order.
Unlike strict reduction, it finishes the coefficient calculation even when
matrix rank equals the number of summands, and permits replacement on a rank
tie. That representation can enable a later axis or projection to reduce rank.
The original `ffwm_reduce` behavior and work counters remain unchanged.

The primitive validates dimensions, slab/scratch lengths, axis/direction and
budget before mutation. At its algebra limit, only completed group operations
are kept and unfinished groups remain intact. Statistics count strictly reduced
groups separately from neutral changes; an exhausted budget is not a fixed point.

`ffwp_project` in `composition/projection.w` restricts one coordinate on the
U/V/W factor grids, repacks the smaller limb stride, removes zero terms and
XOR-cancels duplicate triples. Source and output must be separate slabs; the
source is not changed. Invalid inputs are rejected before destination writes.
Its work is bounded by the existing rank/width limits, not a new time guarantee.
Neither primitive admits an artifact by itself: a full tensor gate is required.

## Finite search and independent replay

The input set is the sixteen recovered wide constructions from the previous
backtracking/cleanup audit. Their previously checked prices are baseline,
not new discoveries in this run. The 300-second, one-worker/no-GPU pilot uses
20-million-unit algebra and full-verification limits for each native call.

For each input it tries six single-axis modes and twelve two-pass modes
(six axis permutations, each with ascending/descending column order), followed
by strict matrix cleanup. All **288 configurations** complete. Full-tensor
identities, not only rank, distinguish retained endpoints. Projection parents
include the source and up to three minimum-rank alternatives chosen by full
term-set distance. Equal-rank variants therefore remain eligible.

The pilot completes **1,815 projections** before the time limit; its projection
family is explicitly **not exhausted**. The unchanged 74-view r8129 control was
already tested in the prior audit and is not repeated or recredited. There is
no raw-rank prefilter before projection cleanup/full verification.

Across all phases there are 4,553 distinct native operations, 4,091 distinct
tensor objects and 1,999 full-native-verified endpoints. No endpoint hits the
full-verification limit. Independent replay checks every operation:

- 752 basis operations against a separate row-equation factorization;
- 1,986 strict cleanup operations against the independent matrix oracle;
- 1,815 projections against direct coordinate-grid restriction;
- exact tensor preservation and all identity/shape/rank bindings throughout;
- 59 distinct input/best complete tensors independently expanded and checked.

There are 554 changed, equal-rank basis operations; this is an operation count,
not 554 new shapes. Only one retained shape bound decreases. No main-cube rank
or fresh saved-reference crossing appears. This cohort is separate from the
historical 4,286-parent / 215,226-context flip study; do not add its intermediates
to that rollup as independent discoveries.

The retained r8109 witness has canonical MFW1 SHA-256:

```
0e21d6d3303805d170c31922bd72db2887dfce83191e980f93762906bde8c8ec
```

It is obtained from r8129 by two ascending-column passes in axis order 2,0,1,
then strict matrix cleanup. All six ascending axis orders reach r8109 on this
input; single-axis proposals only reach r8119 or r8123. No individual winning
equation was manually edited. This is a useful regression for future bounded
wide-queue integration, not evidence that this basis family is exhaustive.

## Descendants and composition follow-up

A separate 180-second-bounded follow-up finishes all 74 single-coordinate
deletions of the new r8109 parent in about 135 seconds. Each native projection,
cleanup and full-verifier result is independently reconstructed and checked.
None beats the retained target table:

| Shape | Best checked descendant | Retained bound |
|---|---:|---:|
| 18x27x28 | 7903 | 7443 |
| 19x26x28 | 7847 | 7805 |
| 19x27x27 | 8002 | 7847 |

The baseline and augmented 5,984-shape price tables through dimension 32 are
closed under coordinate restriction, block sums and Kronecker products. A
separate enumeration checks every final recurrence and replays price changes.
Both tables are already fixed points: the only added numerical gain remains
19x27x28/8109. No further derived price needs materialization, and no new
reference crossing appears. These negatives concern the stated finite family,
not all possible projections, changes of basis or tensor compositions.

## Focused checks

The new independent test runs 864 basis cases over 31..1,024-bit widths, including
428 budget-limited cases and forced neutral changes, plus 219 projection cases
with 105 full projected tensor checks. It exercises stride changes and malformed
axis/direction, undersized slabs/scratch/status, nonmutation, verification limits
and false-tensor rejection.

The existing 416-case cleanup regression passes with all sixteen corpus output
identities and bounded work counters unchanged. Automatic wide admission still
passes its 66->65 test, immutable-original/cached-replay checks and forged/missing
output rejection. Packed composition adds 63 independent full tensor replays.
These are focused correctness gates, not a matched throughput benchmark.

Example focused commands from the repository root:

```
bin/tungsten compile bits/tungsten-metaflip/spec/wide_matrix_cleanup_test.w --out /tmp/wide-basis --release --native
bin/tungsten compile bits/tungsten-metaflip/spec/wide_projection_test.w --out /tmp/wide-projection --release --native
python3 -B bits/tungsten-metaflip/spec/wide_basis_projection_parity_test.py /tmp/wide-basis /tmp/wide-projection
```

The next runtime integration must schedule these wide proposals as bounded,
restartable work, preserve useful rank ties, and keep full admission gates.
Do not insert an unbounded recursive projection scan into candidate intake.

## Evidence retention

Bulk artifacts stay outside the checkout. The evidence package retains every
pilot object, both independent audit reports (algebra and metadata/coverage),
the descendant family, finite composition closure, native binaries, source
pins and replay tools. Its focused portable replay checks all input/best
tensors, repeats primitive parity, and reconstructs the r8109 recipe natively
and independently; the focused replay passes. It is not a second full timed
campaign. The sealed archive is
`~/.local/share/tungsten-metaflip/evidence/2026-09-10-wide-basis-projection.tar.gz`:
100,164,072 bytes, SHA-256
`6bbfb15da6276c0f74074441c84e9b44180094f603289899fc98e334dc5c56b9`.
All 4,288 payloads plus the manifest were rehashed from the sealed archive.

The binaries use `--release --native` against the local compiler/runtime,
not an independent clean compiler build. The six unrelated dirty files remain
unchanged; their combined diff SHA-256 is
`2f741028f621d98408d438dd598a8738b499710070aae691675a893a9bc8cf42`.
No GPU run, canonical seed promotion, publication or record claim is included.
