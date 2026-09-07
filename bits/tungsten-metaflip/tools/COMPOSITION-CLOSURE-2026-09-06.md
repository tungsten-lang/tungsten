# Verified composition closure and stronger-baseline triage

This is an offline GF(2) upper-bound experiment, not a world-record claim.
Neither canonical record ledgers nor the live fleet archive were changed.

## Implementation

`bud_products.rb --recursive-products` optionally prices and materializes
recursive Kronecker products as well as axis-aligned block sums. The default
remains block sums for compatibility with the frozen parent-walk experiments.
Every input, permutation, product, sum and exported tensor is reconstructed
exactly. Product rank retains term multiplicities rather than silently
deduplicating identical summands. Both product factors are strictly smaller
than the requested shape, so recursive planning terminates.

`composition_closure.rb` compares candidate recipes with two libraries:
the supplied verified basis, and that basis augmented with the candidates.
It exports both complete witnesses plus their recipes and construction plans.
Plan axes refer to `canonical_shape`; the requested `shape` can have a
different dimension permutation. This finite family does not include every
uneven-block construction, projection, change of basis or published algorithm.

### Propagate new seeds through a complete bounded grid

`--basis-report` accepts a completed GF(2) grid report with hashed tensor
snapshots. Every snapshot is tensor-checked and treated as part of the new
run's baseline, even if a previous report labelled it `new`. Only the explicit
candidate recipes are credited as additions. This avoids counting an old
gain again when chaining studies.

```sh
ruby bits/tungsten-metaflip/tools/composition_closure.rb \
  --output /new/propagation \
  --basis-report /verified/previous/report.json \
  --grid 2:32 \
  --reference-index /pinned/catalog-index.json \
  /verified/new-winner.merge.json

PYTHONDONTWRITEBYTECODE=1 python3 \
  benchmarks/matmul/metaflip/verify_recursive_portfolio.py \
  --root /new/propagation --admitted /new/propagation/admitted --workers 2
```

The reference index is optional comparison metadata, never an admission
source. The runner materializes and replays every improved row, retains
baseline and added snapshots, and checks source hashes before marking the
run complete. The independent Python checker repeats the full DP using a
separate implementation and verifies every retained input/output tensor.
Grid bounds must lie within 1 through 32; the default is 2 through 32.

The repository's `catalog_gf2_import.py` now accepts the catalog's sparse
encoding as well as dense factors. It checks sparse index uniqueness, width,
row coverage, integral coefficients and dense/sparse agreement. It requires
explicit F2 validity, transposes the catalog W convention, and verifies the
whole tensor before writing a witness. A catalog `verified` flag alone never
admits a certificate.

## Exact experiment

The newest [shared-factor renewal pass](../../../benchmarks/matmul/metaflip/bud_renewal_audit_2026_09_06/README.md)
uses the improved direct witnesses as parents and constructs 45 further local
product improvements. This also reconstructs known catalog comparators that
are outside the axis-split/Kronecker DP. The enlarged reference check excludes
three additional apparent novelty candidates, illustrating why the DP is a
verified local baseline rather than a complete best-known-rank oracle.

Later, the [cofactor propagation audit](../../../benchmarks/matmul/metaflip/cofactor_propagation_audit_2026_09_06/README.md)
uses the reusable `--basis-report` mode on all 5,456 shapes in `--grid 2:32`.
Nine previously found direct seeds produce 95 local improvements (nine direct,
86 derived), all independently replayed. Four derived values are below both
available reference bounds; a fifth Lille-beating value is explicitly rejected
as a best-known candidate because the pinned catalog lists a stronger one.
This is a comparison against finite sources, not a worldwide novelty proof.

The frozen basis contained 150 local witnesses plus seven newly reconstructed
catalog comparators. Catalog commit:
`f3a7f0f61b1005666c2cb03f98f2a16727604ea0`.
Source Git blobs were checked against the pinned tree; Python and Ruby each
reconstructed all seven imported witnesses. One additional rank-1176
10x12x16 source was excluded because it explicitly does not support F2.

Across the existing 352 candidate shapes:

- 78 candidates beat the frozen basis's recursive closure.
- Adding all candidates improves that closure at 102 targets.
- 31 resulting constructions beat **both** their previous local candidate
  and the frozen basis closure. These are further local improvements, not
  31 novel algorithms.
- All 704 exported comparison/result witnesses passed the older independent
  Python verifier: 316,880 terms and 9,960,857 support-pair XORs.

An example is 8x8x15: the previous local rank 647 becomes 631 by combining
the existing 8x8x7 rank-302 candidate and 8x8x8 rank-329 construction.
This is ordinary block reuse, not a new primitive flip-search record.
The [retained research fixture](../../../benchmarks/matmul/metaflip/composition_closure_2026_09_06/README.md)
includes both origin recipes and an independent three-recipe audit.

The six previously retained follow-up products separate as follows:

| Shape | Retained local rank | Frozen verified recursive comparison | Disposition |
|---|---:|---:|---|
| 5x12x12 | 522 | 498 | Existing catalog witness is better |
| 5x12x16 | 696 | 657 | Existing catalog witness is better |
| 5x16x16 | 924 | 868 | Existing catalog witness is better |
| 10x12x12 | 894 | 900 | Keep for wider novelty audit |
| 10x12x16 | 1188 | 1190 | Keep for wider novelty audit |
| 10x16x16 | 1530 | 1560 | Keep for wider novelty audit |

These are finite-library comparisons, not authoritative best-known ranks.
For example, an older local uneven-block ledger reported 1558 for 10x16x16;
that witness was absent during this initial pass. The subsequent
[coverage audit](SEARCH-COVERAGE-AUDIT-2026-09-06.md) reconstructs it exactly
and finds stronger uneven-block comparators at several other targets.

## Wider metadata screen: not proof

The pinned catalog index covers 680 relevant canonical shapes after merging
its explicitly F2 metadata with the verified basis. A separate rank-only
block/product envelope leaves 16 candidates below that metadata envelope:

```
10x15x15 1388    10x12x12 894     10x12x16 1188    12x14x16 1634
12x15x16 1712    10x16x16 1530    15x16x16 2260    8x12x15 896
8x8x12 500      8x15x16 1188     8x8x15 631       7x8x8 302
8x8x9 381       9x12x14 954      9x14x16 1268     9x9x10 536
```

This screen merely prioritizes further checking. Its other metadata sources
were not all independently reconstructed. It omits field-unclear external
rank claims and construction families not represented by its recurrence.
The catalog and cached Lille pages also disagree on some external values;
neither a filename nor this shortlist is a novelty certificate.

The subsequent exact uneven-block audit dominates the listed 12x14x16,
15x16x16 and 8x15x16 candidates with ranks 1624, 2137 and 1174. It also
reconstructs the 7x8x8 rank-302 known-template instance. Preserve the list
above as the historical metadata screen, not a current discovery list.

## Replay and evidence

From the bit directory, with explicit local witness libraries:

```sh
ruby tools/composition_closure.rb --output NEW_DIRECTORY \
  --library VERIFIED_LIBRARY --extra-library VERIFIED_COMPARATORS \
  CANDIDATE.recipe.json
python3 tools/verify_bud_products.py \
  --verifier ../../benchmarks/matmul/metaflip/verify_block_composition_records.py \
  NEW_DIRECTORY/*/{known,augmented}/*.recipe.json
```

Current-run evidence:

- `/private/tmp/metaflip-composition-closure-20260906-corpus/report.json`
- `/private/tmp/metaflip-composition-closure-20260906-corpus/independent-audit.json`
- `/private/tmp/metaflip-catalog-comparators-20260906/audit.json`
- `/private/tmp/metaflip-catalog-comparators-20260906/metadata-envelope.json`

Focused checks passed: bud products (14 tests/130 assertions), disjoint packing
(6/136), closure (2/19), independent Ruby verification (5/43), and catalog
import (4 tests, including malformed sparse and false-tensor cases).

Imported coefficients remain outside the distributable bit. Their source
terms and the GPL-derived parent lineage still require preservation and
license review before redistribution. No publication, commit, submission or
canonical-record promotion was performed.
