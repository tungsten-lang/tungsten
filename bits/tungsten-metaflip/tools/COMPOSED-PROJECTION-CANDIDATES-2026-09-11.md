# Five checked GF(2) reference-crossing candidates

Composition followed by coordinate restriction and exact matrix cleanup
produces three smaller candidates; Strassen products propagate two of them.
Every listed tensor has been fully materialized and checked independently.
These are **source-scoped best-known candidates**, not confirmed world records,
general-field algorithms, optimal-rank proofs, or redistribution clearance.

| Canonical shape | Checked GF(2) rank | Frozen retained bound | Fresh Lille rank |
| --- | ---: | ---: | ---: |
| 8x11x11 | **640** | 646 | 641 |
| 8x11x12 | **673** | 684 | 676 |
| 8x11x16 | **895** | 914 | 904 |
| 16x22x24 | **4,711** | 4,754 | 4,732 |
| 16x22x32 | **6,265** | 6,284 | 6,306 |

The three smaller ranks also beat the pinned matmulcatalog F2-labelled
metadata, respectively 646, 690 and 914. References over Q or Z are numerical
comparators, not automatically valid imported GF(2) leaves. Nothing here
infers that a rational scheme can be reduced modulo two.

## Construction and attribution

All coordinates below are zero-based. Factors use Metaflip's output-row-major
convention, and every object is identified by its entire canonical MFW1 bytes.

- **8x11x12/r673:** the checked 2x3x3/r15 live-parent representation composed
  with a checked 4x4x4/r47 leaf gives 8x12x12/r705. Delete coordinate 8 on
  axis 1: raw r685, exact shared-factor matrix cleanup r673.
- **8x11x16/r895:** a checked 2x3x4/r20 live parent with the same rank-47 leaf
  gives 8x12x16/r940. Delete coordinate 2 on axis 1: raw r914, cleaned r895.
- **8x11x11/r640:** use a different rank-673 presentation. From the r705
  parent, delete coordinate 1 on axis 2 and clean r697 to r673, in orientation
  8x12x11. Then delete coordinate 6 on axis 1 and clean r653 to r640.
- **16x22x24/r4711** and **16x22x32/r6265:** fully expanded products with the
  checked 2x2x2/r7 Strassen leaf. Both exact term sets match an independent
  Kronecker constructor; they are not merely multiplied rank labels.

These winners come from the original composed inputs, **not** the subsequent
seeded basis walk. Their small live-parent snapshots and the mixed-composition
bank are pinned. The two parent plans are singleton-group products; no
unwitnessed catalogue price enters their construction. Parent snapshots are
in the preceding private live-parent evidence bundle, also copied into this
bundle where needed for replay. Underlying seed attribution and asset-level
redistribution review remain separate from verifying the resulting tensor.

| Shape | MFW1 SHA-256 |
| --- | --- |
| 8x11x11 | `50184798b76445cac5220516464b9d06f69c23e8f0ea2109d784ae2c2299c198` |
| 8x11x12 | `1594c62e08adb9c708bf031eae3fd665fb6a2cc8909fd0fe731c44175f20d3e7` |
| 8x11x16 | `bbd4919dc2895a8f60805591eb2dd30ad39627fbd63435815ea13f0e063dff98` |
| 16x22x24 | `2924de587c69f9dab276bb9c1e2d6c35e4c781fda652b1cde23a709e10317d2a` |
| 16x22x32 | `6cdbecae2edf96b396279eaa88398ef4110c31dbae914b5700c4930327e7fc2c` |

## Search change and bounded evidence

The previous post-composition basis walk was rank-neutral. This follow-up
instead screens all **5,000** one-coordinate projections from 191 distinct
parents across 20 canonical shapes. Per target, it selects four lowest
distinct raw projections and one seeded exploratory alternative, then adds
matched original-ancestor controls. All **270 selected cases** complete.
Raw rank is only a scheduling heuristic: this is not a sound impossibility
test for unselected projections, which might clean much further.

The matched basis-descendant/ancestor comparison is 14 better, 69 tied and one
worse. It does not explain the reference crossings: the original parent
presentations produced those. The useful lesson is to assess a parent's
verified descendants, not only its own rank or composition price.

The three smaller winning shapes receive an exact leaf-product screen within
target dimensions 32: **45** literal product contexts, plus **14** direct sums
among the winners. Only the two listed products beat both comparison bounds.
In particular, 8x11x11/r640 times Strassen gives r4480, which does **not** beat
the retained 16x22x22/r4477. No improvement is claimed for that propagation.
These price screens do not exclude gains from later algebraic refinement.
The first screen accidentally included 36 extra dimension-33 contexts; fixing
the bound to 32 leaves exactly the same two qualifying products and no changes
to any admitted tensor.

All **462** one-coordinate neighbors of the ten initial reference-crossing
presentations and two propagated tensors are then projected, cleaned and
checked. This completes its finite cohort in about 67 seconds on one
low-priority CPU worker. It discovers the r640 candidate. The projection
studies span **59 canonical target shapes**; the two products add two more.
These wall times describe this run, not a benchmark or profiling result.

Three further retained-table crossings are deliberately not promoted:

| Shape | Checked rank | Retained | Stronger reference |
| --- | ---: | ---: | ---: |
| 8x9x17 | 786 | 807 | 782 |
| 16x22x23 | 4,633 | 4,724 | 4,627 |
| 16x22x31 | 6,187 | 6,189 | 6,160 |

## Verification and reference scope

Cold replay independently checks all **732 projection/cleanup steps**, two
parent compositions and two propagated products. It checks **824 unique
endpoints** with complete integer-based GF(2) expansion and the native packed
verifier, rather than random evaluations. The producer's matrix cleanup and
coordinate mappings agree with independent Python implementations; product
generation uses the existing Ruby constructor and a separate Python replay.
All native admission checks finish within the fixed 20-million-work budget;
no work-limited response is accepted. One-bit, validly encoded corruptions of
each smaller candidate are rejected by both full-tensor checkers.

The deduplicated study-series rollup is **7,687 representations**, including
166 original inputs: **7,521 non-input representations**. This batch adds
730 beyond 6,957. Those are representation counts, not record counts; useful
rank ties and different orientations remain distinct. The r640 chain is a
concrete reason to retain multiple equal-rank parents.

Live responses were saved September 11, 2026 for
[8x11x11](https://fmm.univ-lille.fr/8x11x11.html),
[8x11x12](https://fmm.univ-lille.fr/8x11x12.html),
[8x11x16](https://fmm.univ-lille.fr/8x11x16.html),
[16x22x24](https://fmm.univ-lille.fr/16x22x24.html), and
[16x22x32](https://fmm.univ-lille.fr/16x22x32.html).
The web-search cache returned an obsolete r691 for 8x11x12; the fresh HTTP
response says r676 and is the comparison used here.

The complete, non-truncated tree of
[Perminov's catalogue](https://github.com/dronperminov/FastMatrixMultiplication)
is pinned at `db560ca5811bc38d5a6d5c0a3ec4315937ceabce`. Its current table
agrees on r641/r676/r904 for the smaller shapes. The
[matmulcatalog](https://github.com/solven-eu/matmulcatalog) snapshot is pinned
at `f3a7f0f61b1005666c2cb03f98f2a16727604ea0`. These finite source checks do
not establish global literature absence, isomorphism novelty or public
acceptance. No public catalogue, seed archive or submission was changed.

## Retention

Bulk witnesses, exact plans, checked leaf bank, native binaries, reference
responses, producer scripts and a standalone `replay.py` remain in a private
compressed bundle outside the checkout. The repository retains this concise
audit only. See `summary.json`, `references/summary.json`, `mutations.py` and
the SHA-256 manifest inside the bundle. The replay has no dependency on the
original scratch directories; the native binary targets this local platform.

```
~/.local/share/tungsten-metaflip/evidence/2026-09-11-composed-projection-candidates-v2.tar.gz
35,953,334 bytes; 1,654 payloads
SHA256 d25cb7babfe2ce72c64c778c4f76551015854a35c7f54a1807d65cd01ce78b70
```

Use Python with the checker dependencies installed (this run used Homebrew
Python 3.14 and NumPy 2.4.4). The first extracted replay selected Apple's bare
Python 3.9 and stopped at the NumPy import, before checking any tensors; that
is not a tensor-test result. For this machine, the explicit replay commands are:

```
/opt/homebrew/opt/python@3.14/bin/python3.14 -B replay.py
/opt/homebrew/opt/python@3.14/bin/python3.14 -B mutations.py
```

The isolated replay and mutation results match the original run. The corrected
32-bound replay also passes, with unchanged witness results. Every payload in
the final archive was read back and checked against its SHA-256 manifest.

All study processes are terminal. No profiling, GPU run, background fleet,
canonical seed promotion, runtime default change, push or publication was
performed in this follow-up. This is evidence for prioritizing the existing
composition -> restriction -> cleanup loop, not a new production scheduler.

The next useful expansion is checked mixed/group composition of these wide
parents, beyond the two pure products tested here. The existing narrow
planner's input format must not be used for their multiword factors. Preserve
the equal-rank presentations and exact full-word identity when adding that
path; a rank-only archive would lose the presentation that led to r640.
