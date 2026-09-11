# Triple-clipped leaves and bounded outer-basis audit

This follow-up adds **2,378 distinct, fully checked GF(2) representations**,
but no retained-bound improvement. The eight source-scoped candidates in the
[per-slot study](PER-SLOT-LEAF-CANDIDATES-2026-09-11.md) remain unchanged.
There is no new world-record claim or main-square improvement.

| Canonical target | Best in this batch | Prior retained bound |
| --- | ---: | ---: |
| 7x7x11 | 394 | 377 |
| 7x11x11 | 579 | 576 |
| 7x11x15 | 787 | 778 |
| 7x15x15 | 1,042 | 1,032 |
| 11x11x11 | 895 | 873 |

These comparisons use the pinned retained-bound snapshots, not a new public
catalogue survey. For example, improving this experiment's 7x15x15 from
1,063 to 1,042 does not beat the already retained 1,032.

## Finite scope

The five checked parents are 2x2x3/r11, 2x3x3/r15, 2x3x4/r20,
2x4x4/r26 and 3x3x3/r23. Each allocation narrows exactly one block from
width four to three on **each** of its three axes. Every term receives a
checked leaf sized to its actual block extents, from the same pinned
22-tensor bank used by the preceding study.

- All **113** such allocations are materialized, matrix-cleaned and verified.
- Five selected per-slot portfolio refinements and ten kernel-basis walks
  finish without improving the five minima. Raw-rank/density winners can
  clean worse; original candidates are preserved.
- All elementary single outer transvections yield **88** distinct parents
  and **2,170** parent/allocation contexts. The first 40 price-selected
  contexts are followed by **all 2,130 remaining contexts**. Thus the
  single-transvection result does not depend on the formula shortlist.
- All **1,696 ordered two-transvection words** are screened. After removing
  original/single-word identities and duplicates, they yield **962** new
  parent representations and **25,384** contexts. Only **80** are
  materialized: eight cheapest contexts per target, plus eight using
  distinct additional parents. This remains a heuristic shortlist, not
  exhaustive post-cleanup minimization at word length two.

The full single-word follow-up finishes in about 240 seconds with one
low-priority CPU worker. Exact cleanup can save up to 17 terms in this
cohort, but the formerly omitted contexts do not improve the table.
These timings describe this run, not a matched performance benchmark.

## Independent checks

The Python replay independently performs both sides of each basis change,
enumerates the finite words and allocations, and recomputes all **27,554**
single-/double-word construction prices from coordinate supports and checked
leaf ranks. It verifies that the 2,170 single-word contexts are covered
exactly once by the two materialization passes.

For every materialized recipe it checks source hashes, reconstructs the
individual coordinate images, applies GF(2) parity, recomputes matrix
cleanup, and expands the complete tensor identity. The native full verifier
also accepts every endpoint within its 20-million-work allowance; limited
checks are not treated as successes. The replay checks 2,587 distinct source
snapshot tensors and rejects validly encoded one-bit corruptions of all
five batch minima in both independent and native verifiers.

The deduplicated study-series total is now **11,520 complete-object
identities**, including 166 original inputs (**11,354 non-inputs**).
All 2,378 endpoints are new relative to the preceding 9,142. These are
representation counts, not records, isomorphism classes, transient proposals
or unmaterialized formula prices.

## Evidence and next experiment

The private bundle contains recipes, source/leaf snapshots, endpoint
tensors, pinned checker sources and native binaries, complete census files,
logs and a SHA-256 manifest. Repeated payloads use hardlinks in the package;
no tensor collection is added to the repository.

```
~/.local/share/tungsten-metaflip/evidence/2026-09-11-triple-slot-basis-study.tar.gz
128,317,509 bytes; 29,521 payloads
SHA256 e768a15b48a0e1a151c8d74eba5c37e07df6dac85061435239af6151b2e65ce0
```

Run `python3 -B replay.py` after extraction. The standalone package replay
passes and matches the scratch replay byte-for-byte. This host uses
Homebrew Python 3.14 with NumPy; bundled native binaries are platform-specific.
Archive payload readback is checked against the manifest.
A fresh extraction also passes the complete payload-manifest check, including
hardlink targets; it contains no unmanifested payloads.

This closes only the stated cohort, not other block allocations, leaf
representations, larger basis words or tensors. The next construction test
allows **multiple narrowed blocks on an axis**, changing the allocation
family instead of spending more attempts in the same basis shortlist.
No default runtime behavior, canonical seed, GPU campaign, profiling,
public catalogue, push or publication changed in this study. The user's
separately running MetaFlip cycle was not interrupted.
