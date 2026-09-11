# Literal and sheared projection follow-up

**No new retained rank or world-record claim.** This finishes the outstanding
finite literal-projection study and tests non-coordinate restrictions, including
their usefulness as composition parents. It does not change the default fleet
schedule, launch an indefinite search, or promote a canonical seed.

The native seeded-basis operator and its focused gates were committed separately
as `da2084dc`. It remains an explicit experimental API, not a default queue lane.

## Completed literal restrictions

The [seeded-basis study](SEEDED-BASIS-SEARCH-2026-09-10.md) had checked 1,341 of
2,210 planned one-coordinate deletions from 78 selected parents. This continuation
checks the remaining 869: 839 in a 150-second batch, then the final 30 in a
separate 18-second batch. Exact context-prefix assertions prevent repeating the
already recorded cases or silently skipping a coordinate.

The complete finite family has **2,204 distinct outputs across 86 target
shapes**. All 2,210 contexts pass native full-tensor verification, independent
coordinate contraction, independent shared-matrix cleanup and full integer
tensor reconstruction. None beats the saved retained bound; 60 contexts match
it. This closes only these selected parents and literal deletions, not all
representations, bases or multi-coordinate restrictions.

## Non-coordinate restrictions

An invertible coordinate change preserves the parent matrix-multiplication
tensor. Applying it before deletion changes the restricted subspace. The
proposal uses primal coordinate matrices on U, inverse-dual rows on V, and
inverse-dual row/column matrices on W, matching the existing
`MetaflipOuterBasisProducts.transvection_word_terms` convention.

Two independent implementations are compared: dense GF(2) coordinate matrices
with Gaussian inversion in Python, and the existing successive bitwise
transvections in Ruby. Forty control cases check complete tensors and inverse
words, including rectangular and multiword factors. The existing Ruby tests
for involutions and basis words also pass (two tests, 193 assertions).

From the 166 original inputs and 530 seeded endpoints, select up to two
minimum-rank representations per canonical shape. This supplies 98 parents
across all 51 source shapes. Proposal order interleaves single shears touching
the deleted coordinate with seeded multi-shear words. Selection and ordering
are heuristics, not dominance rules.

The recorded run completes **1,372 contexts**:

- 1,370 admitted, with 1,324 distinct outputs across the admitted set;
- two native-verification work-limit deferrals, neither admitted nor counted
  as a verified rank;
- 98 target shapes encountered, with no retained-rank improvement.

Every admitted output passes native projection and cleanup, independent
projection/cleanup replay, native full-tensor verification and independent
full integer reconstruction. Limits remain 20M algebra/verification work units.

The initial pilot stopped at a verification limit on a 19x27x27/r8109 output
(`d8ad45aa49e05b54e63ee5ad0ee18791457949a6fc0f83cfe6040b35a793924b`),
not an invalid tensor. Its last recorded checkpoint contains 375 verified
contexts. The repaired driver resumes those exact keys, records deferrals
explicitly, and completes 997 further contexts in a bounded 181-second run.
Uncheckpointed pilot work may have been replayed; it is not double-counted.
The family includes 71,396 possible single-shear cases before the additional
word proposals, so this run is emphatically **not exhaustive**.

For 532 contexts with an already checked literal deletion of the same parent
and coordinate, shearing gives a lower rank in 32, the same rank in 105 and a
higher rank in 395. The largest reduction is eight terms (2x20x25: 879 to 871,
still above the retained 773). Thus the action genuinely changes restrictions,
but this is not evidence of a record or a broadly profitable default lane.
These matched contexts are not independent statistical trials.

## Composition follow-up

Rank ties are not discarded. All 289 distinct admitted descendants within two
of the saved bound, fitting the current <=63-bit/512-term parent interface,
receive the 63 scale triples in `{1,2,3,4}^3` except `(1,1,1)`.

All **18,207 native composition plans** are independently checked. They cover
644 target shapes; fifteen have no saved reference. There are no known-bound
crossings. Formula prices are not full tensor witnesses and cannot rule out
post-expansion reductions.

A separate round-robin shortlist fully materializes 16 constructions from
16 parent-shape families, covering 15 targets. Native expansion matches
independent leaf substitution; every complete tensor and cleanup passes.
None reduces rank in cleanup or improves the retained bound. The remaining
price-only contexts are not claimed fully expanded or ruled out.

## Deduplication and decision

The sheared sample contributes 1,309 representations not present among the
complete literal-projection outputs. Across the mixed-direction, seeded-basis,
literal-projection and sheared-projection studies, full tensor identity gives
**4,590 distinct non-input representations**, or 4,756 including the 166 shared
inputs. This rollup excludes unrelated historical campaigns and the composition
outputs. These are representations, not 4,590 improved shapes.

There is no evidence here to enable an extra default basis/projection lane.
Two concrete next directions remain: test multi-coordinate restrictions toward
the main square shapes, and close the existing checked-wide-output feedback gap
so useful eligible descendants can reach live search and incremental composition.
Neither is claimed implemented by this follow-up. A resource-limited candidate
must remain deferred rather than turning into a negative result or admission.

## Reproduction and scope

The comparison uses the pinned 5,984-shape retained table from the seeded study,
not a refreshed world-record table. Since nothing beats that retained baseline,
there is no public novelty claim to promote. All work is local, bounded and
low-priority CPU work; no GPU or full-machine throughput claim is involved.

Working evidence:

```
/private/tmp/metaflip-seeded-projection-tail-20260910
/private/tmp/metaflip-seeded-projection-final-20260910
/private/tmp/metaflip-sheared-projection-search-v2-20260910
/private/tmp/metaflip-subspace-compositions-20260911
```

The incremental evidence package contains the 869 new literal contexts, all
1,372 sheared contexts including deferrals, source tensors, original drivers,
the interrupted pilot, portable independent replay, the native verifier, all
pricing plans and the 16 full constructions. The preceding 1,341 literal
contexts were separately cold-replayed in the sealed seeded-basis archive.

Cold replay passes all 869 new literal contexts, all 1,372 sheared contexts
(2,239 admitted full-tensor checks and two correctly deferred cases), and all
16 full compositions/cleanups. The price-only corpus retains its initial
independent plan checks; cold replay does not rerun every price-only plan.
`paired_compare.py` reproduces the 532-context comparison above.

The sealed archive is outside the repository:

```
~/.local/share/tungsten-metaflip/evidence/2026-09-11-subspace-projections.tar.gz
```

It has 5,871 manifest payloads, 113,800,789 bytes, and SHA-256
`0d70f8fe033aa21649fa5644ce8876a8315017c84776c0dcbcf753b58c9f953a`.
Every archived payload was read back and matched against the manifest. From
an extracted copy on the original macOS/arm64 platform, replay with
`python3 -B cold_replay.py /a/new/report.json`; no fleet is started.

No full local `rake`, push or publication is performed. The six unrelated dirty
files remain byte-for-byte unchanged relative to their previous combined diff
SHA-256 `2f741028f621d98408d438dd598a8738b499710070aae691675a893a9bc8cf42`.
