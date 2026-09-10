# Mixed-direction refinement and composition audit

This finite follow-up finds **no new retained rank**, either primitive or
among the fully materialized compositions. It does validate broader search
coverage and completes the prior automatic-wide corpus audit. It makes no
world-record claim and does not refresh the public comparison table.

Ordinary MetaFlip already runs native background matrix cleanup, bounded basis
changes, projections and incremental composition for narrow candidates. The
new automatic wide lane also transforms verified composition results and
preserves rank ties; see [its integration report](AUTOMATIC-WIDE-TRANSFORMS-2026-09-10.md).
That lane remains a finite generation: wide projection outputs are archived,
not yet recursively recomposed or converted into live u64 walker seeds.

## Finite family and deduplicated counts

The sweep starts with 166 distinct pinned GF(2) tensors across 51 canonical
shapes: 148 seed-manifest entries, sixteen retained wide parents and two
rank-85 compact parents. It includes the main 3x3, 4x4, 5x5, 6x6 and 7x7
families. Existing input ranks augment the saved 5,984-shape comparison grid,
so rediscovering an imported seed cannot count as an improvement.

Each parent receives all 36 mixed-direction contexts: six axis permutations
times six nonuniform per-axis ascending/descending column masks. Each context
uses at most two cycles, stops early on a repeated endpoint, then performs
strict matrix cleanup. Uniform directions were covered by the earlier family.
Native calls keep the 20M algebra/full-verification limits. Full tensor
identity, not rank or pair count, keys the operation cache and endpoints.

The initial 180-second pilot completes 2,444 contexts. A continuation reuses
its exact cached operations and finishes the remaining contexts in about
61 seconds. The **cumulative**, not additive, totals are:

- 5,976 unique contexts, exactly 36 per input;
- 6,612 distinct native operations: 5,946 basis and 666 cleanup;
- 2,132 distinct intermediate objects;
- 777 full-native-verified endpoints, including 611 new identities;
- zero algebra-limited steps or verification-limited endpoints;
- zero retained primitive rank improvements, including the main cubes.

Independent replay reconstructs every operation using the integer
row-equation matrix oracle. It separately expands 188 distinct input/best
full tensors, checks every context chain and unique configuration, recomputes
all 611 new endpoint metadata rows and the retained-rank comparison. It does
not independently expand every intermediate tensor: the exact algebra replay
proves preservation along each step instead. The report SHA-256 is
`3811bf9a89dff5d3fe31b1777195412d221dcead310f15a32b8492e785c85f32`.

## Composition checks

475 new endpoint representations fit the small-parent mask/rank limits.
The native mixed group/grid planner tests each at all 63 scale triples in
`{1,2,3,4}^3` other than `(1,1,1)`: **29,925 contexts**. Its leaf bank contains
22 pinned complete witnesses plus independently checked literal unit leaves.
All returned disjoint group/grid plans and costs are checked independently.
The faster component counter also agrees with the original graph oracle on
100 randomized cases and periodically checks complete production plans.

There are 737 canonical target shapes. Ten are outside the saved comparison
grid and are explicitly marked unknown, never assigned a fabricated bound.
No constructive plan price crosses a known retained bound. This is not an
optimality certificate: bounded planner fallbacks and post-expansion XOR
cancellation can change the picture.

To test that remaining possibility, a shape-diverse round-robin selects
96 constructions from 26 parent-shape families, covering 93 target shapes.
Selection prioritizes price ratio and target volume within each family; this
is heuristic ordering, **not sound dominance pruning**. Every selected plan
is materialized natively and independently from its leaf substitutions.
All 96 complete tensor identities pass. Bounded native matrix cleanup then
agrees term-for-term with the independent oracle; no cleanup is limited,
none reduces rank, and none beats the retained bound. The other pricing
contexts are not claimed to have been materialized or ruled out.

The composition driver initially compared the oracle's insertion order with
canonical term order. The stopped first case was diagnosed by exact full
tensor checks and equal term sets; the corrected comparison sorts the oracle
result. The complete 96-case run uses that correction. No native algebra or
admission gate was relaxed.

## What changed and what stays experimental

The 36 extra modes stay out of the default candidate queue: this study did
not establish a payoff for their extra automatic work. No candidate is
promoted, no seed is changed, and no CPU/GPU flip campaign runs here.

The committed code improvement is in the independent projection checker:
row-block contraction replaces full-grid scanning while retaining the grid
oracle as a comparison test. It passes 461 deterministic dense/sparse,
duplicate, edge and multiword cases; the native 169-context queue and public
four-context batching regressions pass. The full prior automatic study now
passes 5,215 context replays and 4,975 distinct full tensor checks, with no new
retained gain. Its automatic recovery of the earlier r8109 wide witness is
not counted again.

All search/audit jobs are bounded low-priority CPU jobs. No full local `rake`
suite, clean compiler bootstrap, canonical archive mutation, publication or
push is included. The unrelated compiler/runtime/spec diff remains unchanged.

## Evidence

Working reports are under `/private/tmp/metaflip-mixed-directions-complete-20260910`
and `/private/tmp/metaflip-wide-auto-study-20260910`. Bulk tensors remain
outside the checkout. A local sealed package also preserves the exact inputs,
intermediates, plans, native binaries, source pins, independent auditors and
focused portable replay:

```
~/.local/share/tungsten-metaflip/evidence/2026-09-10-automatic-wide-mixed-directions.tar.gz
277603026 bytes
SHA-256 f8c6ddec1c63d0b7f9d410d219dbdf3431b3dcaed19ca3b8aaa0527fcb550106
```

All 13,356 payloads plus the manifest were rehashed from the sealed archive.
Before sealing, the portable replay passed the native 169-context queue and
public batching tests, all 6,612 mixed algebra/metadata steps, 61 distinct
automatic input/best full tensors, and all 96 full composition/cleanup replays.
This focused cold replay does not repeat the entire automatic corpus audit;
that first completed audit is retained separately. From an extracted package,
`python3 -B cold_replay.py /a/new/output/directory --full-automatic` also
repeats the complete automatic corpus check. No GPU worker is started.

The native binaries are local release/native builds at base commit
`4f3123088d32574d3d082ac1d44ae4778de6ec1e`, not a clean compiler bootstrap.
The unchanged unrelated diff SHA-256 is
`2f741028f621d98408d438dd598a8738b499710070aae691675a893a9bc8cf42`.
