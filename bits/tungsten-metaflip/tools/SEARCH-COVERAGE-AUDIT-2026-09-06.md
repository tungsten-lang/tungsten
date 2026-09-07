# Parent coverage, observation cadence, and stronger comparisons

No world record is confirmed. This pass expands exact research coverage,
rejects an expensive observation-only policy change, and reconstructs stronger
comparisons that were missing from the previous finite library. The live
CPU/GPU search and canonical record ledgers were not modified by these tools.

## Parent representation coverage

The catalog importer now expands integral shared-intermediate circuits as
well as dense and canonical sparse factors. Fresh input references are
expanded chronologically; W intermediates combine products and its output
rows use the catalog's column-major convention. Booleans, floating-point or
fractional coefficients, forward/self references, malformed row counts and
mixed encodings are rejected. The complete GF(2) tensor is reconstructed
before a file is written. Six focused tests include nested input/output
intermediates and 35 malformed sparse/circuit mutations.

The layout was checked against the pinned catalog's
[SchemeIO implementation](https://github.com/solven-eu/matmulcatalog/blob/f3a7f0f61b1005666c2cb03f98f2a16727604ea0/src/main/java/eu/solven/matmul/catalog/SchemeIO.java).
Both rank-40 2x3x8 parent variants passed independent Python and Ruby
reconstruction. Their exact repeated-U structures are eight pairs plus eight
triples, and twelve pairs plus four quadruples. The former uses the existing
dense decoder; the latter needed the new circuit decoder.

With the unchanged 150-leaf verified library, 32 packing trials, maximum
dimension 16 and maximum scale 8, the two parents produce 158 scored
constructions over 72 already-covered targets. Twelve local ranks improve:

| Shape | Previous local recursive result | New parent product |
|---|---:|---:|
| 4x8x9 | 210 | 208 |
| 4x8x15 | 346 | 344 |
| 4x15x16 | 658 | 640 |
| 6x10x16 | 647 | 640 |
| 6x12x16 | 744 | 736 |
| 6x15x16 | 936 | 920 |
| 8x9x10 | 492 | 488 |
| 8x9x14 | 677 | 676 |
| 8x9x16 | 752 | 736 |
| 8x14x15 | 1090 | 1088 |
| 9x10x16 | 934 | 920 |
| 14x15x16 | 2056 | 2032 |

These are known-parent/library-coverage gains, not primitive flip discoveries.
Most match or lose to other catalog entries. Rank 208 for 4x8x9 is below the
pinned GF(2) catalog comparator 209, whose coefficients were downloaded,
Git-blob checked and independently reconstructed. Its formula is
`8*11 + 8*15`, using the dense parent; the new circuit decoder alone did not
cause that improvement. The other apparent catalog improvement, rank 2032,
is dominated by the exact uneven-block comparison below.

## Uneven-block comparisons

The existing `flipfleet_block_composer.w` was reused, not reimplemented.
The new offline `uneven_block_audit.w` wrapper reads explicit manifests,
checks all inputs and outputs, refuses output overwrite, and records exact
allocation/orientation data. Balanced allocations and minimum-formula ties
are searched, not every possible allocation or tensor decomposition.

Across 16 historical shortlist targets and two new targets, 20 comparison
outputs plus two calibration outputs passed the independent Python verifier:
23,877 terms and 967,116 support-pair XORs. Important outcomes:

| Shape | Candidate/local rank | Exact uneven-block rank |
|---|---:|---:|
| 12x14x16 | 1634 | 1624 |
| 15x16x16 | 2260 | 2137 |
| 8x15x16 | 1188 | 1174 |
| 14x15x16 | 2032 | 1975 |
| 10x16x16 | 1530 | 1558, using the older unbalanced calibration |
| 4x8x9 | 208 | 210 (Strassen outer), 220 (rank-47 outer) |

The 7x8x8 calibration reproduces rank 302 with `4*47 + 3*38`, the same
uneven-block pattern as the [Lille construction](https://fmm.univ-lille.fr/7x8x8.html)
with stronger GF(2) leaves. Its parent-walk recovery is not a new construction
mechanism. The old 10x16x16 rank-1558 comparison is now backed by a freshly
reconstructed tensor instead of only a stale ledger entry.

Field distinctions remain essential: the live Lille 8x8x15 page describes a
rank-628 construction using a rank-32 2x4x5 leaf that the pinned catalog
explicitly excludes from F2. Using verified GF(2) ranks 60 and 33 in that
parent pattern gives 636, so the rank-628 claim does not disprove the local
rank-631 GF(2) witness. Cached web versions of that page were stale.

## Verification and retained evidence

The independent audit of 576 observation-study outputs, 144 preceding
targeted-study outputs, and 72 catalog-parent products passed all 792 cases:
762,304 terms and 42,184,837 support-pair XORs. Three preceding long-chunk
studies did not improve the existing ranks 1634/536/500. The observation-only
test preserved walk/greedy endpoints and found no lower rank at cadence 1;
details are in [BUD-PARENT-WALKS](BUD-PARENT-WALKS-2026-09-06.md).

The [retained comparison fixture](../../../benchmarks/matmul/metaflip/comparison_audit_2026_09_06/README.md)
contains the rank-208 construction and rank-209 comparator, plus four stronger
block outputs and five sufficient leaves. All four block outputs replay
byte-for-byte with that smaller leaf set. Its independent nine-tensor audit
covers 7,393 terms and 369,402 support-pair XORs.

Private full-run evidence:

- `/private/tmp/metaflip-observation-study-20260906/audit.json`
- `/private/tmp/metaflip-observation-study-20260906/independent-audit.json`
- `/private/tmp/metaflip-bud-catalog238-20260906/report.json`
- `/private/tmp/metaflip-catalog-comparators-20260906/circuit-audit.json`
- `/private/tmp/metaflip-uneven-audit-20260906/independent-audit.json`

Imported data and derived witnesses remain outside the distributable bit.
Preserve all existing source/seed terms and resolve licensing before any
redistribution. No commit, publication, submission, or canonical promotion
was performed.
