# Checked width-six composition frontier

**51 improvements over retained local witness ranks; no new source-scoped
candidate or world-record claim.** This uses the verified width-six bank
from [the projection follow-up](CLEANED-PARENT-PROJECTIONS-2026-09-11.md).
It is a bounded offline experiment, not an installed-fleet behavior change.

## Declared family

The seven checked outer parents are `222:7`, `223:11`, `224:14`, `233:15`,
`234:20`, `244:26` and `333:23`. Enumerate all ordered block-width assignments
from `{4,5,6}`, requiring at least one width-six block. The leaf library is
the previously verified 20-shape GF(2) bank; every leaf has a full witness.

The complete census visits **114,453** allocation words and prices
**111,701** eligible contexts, covering **651** canonical target shapes.
For each target, materialize the two lowest formula-price contexts, or its
only context: **1,298 constructions** in total. Every selected construction
is expanded, exactly cleaned and fully verified.

This is a complete price census but only a bounded post-cleanup shortlist.
Raw/formula rank is not an admissible lower bound on the result after
cleanup. The run does not exhaust other leaf representations, outer bases,
unselected allocations or arbitrary tensor decompositions.

## Results

All 1,298 materializations finish in about 274 seconds, after a roughly
four-second price census, on one low-priority CPU worker with no GPU.
These timings describe this run, not a performance comparison.

There are **51** target improvements over the frozen retained witness map.
Seventeen match the minimum pinned public comparison bound; none beats it.
No fresh rank pages were fetched because no output passed that initial
comparison. References remain explicitly pinned inputs, not a claim of
current global best ranks or absence of newer publications.

| Target | Prior retained rank | Verified rank |
| --- | ---: | ---: |
| 10x23x23 | 3303 | 3228 |
| 12x17x17 | 2182 | 2114 |
| 11x17x17 | 2046 | 1982 |
| 8x23x23 | 2623 | 2617 |
| 12x23x23 | 3805 | 3803 |

Exact cleanup reduces rank in 85 of the selected contexts, by at most
18 terms. In particular, the last two table rows have formula prices
2625 and 3817: both fail to beat their retained ranks until cleanup.
This independently reinforces the need to assess a bounded exploratory
shortlist after cleanup, not prune it solely by formula price.

The winning parents for these 51 targets are `233` (21), `234` (8), and
`244` (22). Thus 29 local gains come from the optimal `233` and `234`
parents, supporting their use as composition sources. This is not evidence
of a rank reduction for those parents. No square-shape rank improves here.

## Independent checks and cumulative accounting

The independent Python checker derives all 114,453 allocations, the
111,701 support-sensitive prices, and the exact deterministic shortlist.
For each recipe it rebuilds the full tensor, independently refactors the
shared-factor matrices, verifies the complete tensor identity, and runs
the pinned native full verifier. Limited cleanup/verification is not a pass.

Both checkers reject a deliberately corrupted tensor for **each of the 51
improved targets**. The checker also verifies every retained-bound and
reference value against the pinned input map, recomputes the best/gain
lists, and checks complete-object identities against the prior receipt.

All 1,298 endpoints are distinct and new to the prior receipt. The cumulative
series is now **16,424 complete representations**, with **38 source-scoped
candidate shapes unchanged**. Neither allocation counts nor helper leaves
are counted as new candidate shapes. The 51 local improvements are not
silently added to the source-scoped candidate count.

## Evidence and scope

Working root:
`/private/tmp/metaflip-width-six-frontier-20260911`.
Standalone evidence root:
`/private/tmp/metaflip-width-six-frontier-evidence-20260911`.

The package preserves parents, leaves, recipes, raw and cleaned tensors,
input bounds, provenance, exact binaries, and transitive checker sources.
`python3 -B replay.py` performs the independent replay; Python with NumPy
and a host compatible with the pinned native binary are required.
`ruby replay-frontier.rb` reruns the reusable producer's entire census and
shortlist against the saved output. A sealed replay checks its manifest
and receipt without rewriting them.

Tensors remain outside Git. No seed is promoted into the installed fleet,
no user process or installed binary is replaced, and no public catalogue
is changed. The useful follow-up is to test new representations of the
productive outer parents or additional cleanup-aware contexts, not repeat
this identical fixed-library price census.

Durable archive: **11,780 payloads**, **202,479,068 bytes**.

```
~/.local/share/tungsten-metaflip/evidence/2026-09-11-width-six-frontier.tar.gz
SHA256 f73f7036061cd7a6236fc04857ad7c79d2d4effdb86426cafa78bb6fff9177cf
```

The archive has a complete hash manifest and content-deduplicated hardlinks;
archive readback verifies every payload. The focused width-frontier spec
passes all six tests and 97 assertions. The reusable Ruby producer also
reproduces all 111,701 prices and the exact shortlist from packaged sources.
The packaged README precedes only this archive-receipt section.
The complete independent replay also passes from a fresh extraction with
only the packaged sources and binaries; all 1,298 endpoints and 51 negative
mutations agree with the original receipt. Post-replay manifest verification
confirms that all 11,780 payloads remain unchanged, with no extra files.

The durable remote home is
[metaflip-archives](https://github.com/tungsten-lang/metaflip-archives/releases/tag/evidence-2026-09-11).
Tarballs are release assets, not Git blobs; the archive repository tracks
their sizes, SHA-256 digests and remote verification receipts. The private
scratch paths above are provenance locations and may be removed after
archiving. Download and verify the named asset to restore a replay bundle.

## Wrap-up and storage migration

The separate archive repository now hosts 47 checksum-verified release assets
(4,908,040,060 bytes); its Git history contains only metadata. This includes
three archival snapshots of 60 wholly untracked dated benchmark directories,
preserving 117,765 generated files and 6,519,156,733 uncompressed bytes. These
historical snapshots received byte/readback checks, not new mathematical
validation of all prior claims.

Only after publication, remote SHA-256/size verification, and comparison of
every current source file with its archive manifest were those 60 directories
removed. The benchmark folder is now about 81 MiB. Curated records, proof
fixtures, tracked sources, installed binaries and build caches remain.
Redundant local archive payloads and the explicitly verified temporary replay
copies were also removed; remote indexes and cleanup receipts remain.

After cleanup, the width-frontier, cleanup-aware leaf, leaf-portfolio and
outer-basis focused suites pass **37 tests and 1,032 assertions**. No full
repository test suite or new search is started as part of this wrap-up.
