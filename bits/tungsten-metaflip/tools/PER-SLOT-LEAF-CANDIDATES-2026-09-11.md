# Eight stronger checked GF(2) candidates from per-slot leaves

Using each outer term's actual block extents to choose its leaf gives four
smaller improvements. Bounded leaf substitutions strengthen one of them;
checked products and a direct sum propagate four more. All eight beat both
the preceding retained bounds and the freshly fetched Lille comparisons.
These are **source-scoped candidates**, not confirmed world records,
general-field algorithms, rank-optimality proofs or redistribution clearance.

| Canonical shape | Previous retained | Checked GF(2) rank | Fresh Lille |
| --- | ---: | ---: | ---: |
| 7x11x12 | 620 | **613** | 618 |
| 8x11x11 | 640 | **631** | 641 |
| 8x11x12 | 673 | **669** | 676 |
| 8x11x16 | 895 | **891** | 904 |
| 8x11x23 | 1,325 | **1,300** | 1,305 |
| 16x22x22 | 4,477 | **4,417** | 4,487 |
| 16x22x24 | 4,711 | **4,683** | 4,732 |
| 16x22x32 | 6,265 | **6,237** | 6,306 |

The previous retained column includes the five improvements in the
[earlier composition/restriction study](COMPOSED-PROJECTION-CANDIDATES-2026-09-11.md).
It is not a claim about the historical public record. No main square such as
3x3, 4x4 or 5x5 improves in this follow-up.

## What changed

The successful change is **per-slot leaf selection**, using the existing
`outer_basis_products.rb` and `outer_leaf_portfolio.rb` tools. An outer term
that touches only a narrower block need not use the same full cube leaf as
every other term. Each leaf is independently checked, and its exact embedding
is checked in the complete target tensor.

For example, use the previously checked 2x3x3/r15 parent and distribute the
middle dimension as `[3,4,4]`. Four slots now use 4x3x4/r38 leaves and eleven
use 4x4x4/r47 leaves: `4*38 + 11*47 = 669`. This is stronger than forming the
uniform rank-705 product and then restricting/cleaning it to rank 673.

The constructions are:

- **8x11x12/r669:** the allocation above, with no further rank reduction.
- **8x11x11/r631:** allocations `[4,4]`, `[3,4,4]`, `[3,4,4]` initially use
  nine rank-47, four rank-38 and two rank-29 leaves, totaling 633. Independent
  per-slot representation choices make two mapped terms vanish, giving 631.
- **7x11x12/r613:** in orientation 7x12x11, allocations `[4,3]`, `[4,4,4]`,
  `[4,3,4]` use eight rank-47, four rank-38 and three rank-29 leaves. Nominal
  rank 615 loses two zero terms under the exact embedding.
- **8x11x16/r891:** the checked 2x3x4/r20 parent, with allocations `[4,4]`,
  `[3,4,4]`, `[4,4,4,4]`, gives nominal rank 904. Exact shared-factor matrix
  cleanup removes 13 terms.
- **16x22x22/r4417**, **16x22x24/r4683**, **16x22x32/r6237:** fully expanded
  products of the corresponding smaller candidates with the checked
  rank-7 Strassen leaf.
- **8x11x23/r1300:** the fully expanded block sum of ranks 631 and 669 along
  the last coordinate. No price-only construction is reported as a witness.

All use the checked mixed-leaf bank
`90a48facfb6c04cfd585d684fc4ec9a757805d7b12e454e0bddaeae608abf02b`
and the pinned live-parent snapshots from the preceding studies. The bank
contains actual GF(2) tensors; rational catalogue entries are not reduced
modulo two to supply missing leaves. Seed attribution/redistribution review
remains separate from tensor correctness.

## Search and negative evidence

First, a native rank-47 leaf walk with two terms of allowed rank expansion
performs 32 trials and 16,777,216 attempts. All saved winners and endpoints
return to the original leaf. This is finite evidence to stop that unchanged
walk, not a proof that no alternate rank-47 representation exists.

The productive campaign uses five checked parent families: 2x2x3, 2x3x3,
2x3x4, 2x4x4 and 3x3x3. It enumerates **165** allocations obtained by reducing
one block from four to three on either one or two axes. This covers **20
canonical target shapes**. Every allocation is constructed, cleaned and
checked, not just assigned a formula price.

Next, select one lowest cleaned construction per target, or two when the
target beats the retained bound. All **25** selected per-slot portfolio
searches finish: two single-slot rounds, then the existing bounded two-slot
search with shortlist width four. They evaluate **121,812 proposals**.
The portfolio uses checked coordinate permutations and elementary shears,
not manual edits of winning tensor terms. Only the 633-to-631 case improves
the preceding cleaned rank. Some raw-rank/density choices clean worse, so
the original constructions remain available; raw score is not the final gate.

The propagation screen covers **60 literal products and 17 direct sums**
within target dimensions 32. All **16** constructions priced below the prior
retained bound are expanded and verified. Only four also cross the frozen
reference table. For example, 14x22x24/r4291 improves retained 4299 but not
the stronger reference 4284, so it is not in the headline table. Likewise,
7x15x16/r1087 improves retained 1089 but not reference 1083.

Finally, all **1,068** single-coordinate restrictions of 35 competitive
presentations finish, including independent projection and cleanup checks.
They do not improve the eight minima. This is a complete finite cohort,
not exhaustion of other allocations, leaf orbits, projections or tensors.

## Exact replay and identities

The independent Python replay reconstructs each slot from individual
coordinate images, checks source hashes, reconstructs products/sums, and
recomputes exact matrix cleanup. Its complete GF(2) expansion and the native
full verifier check all **1,274 distinct retained endpoint tensors**. Every
native check completes within the 20-million-work allowance; a limited
response is not accepted. One-bit, validly encoded corruptions of all eight
headline candidates are rejected by both full-tensor checkers.

Focused existing tests also pass: `outer_basis_products_test.rb` (10 tests,
350 assertions) and `outer_leaf_portfolio_test.rb` (14 tests, 508 assertions),
with no failures, errors or skips. No full test suite was run.

The study-series rollup is **9,142 representations**, including 166 original
inputs (**8,976 non-inputs**). This round adds 1,274 beyond 7,868. These are
deduplicated complete-object identities, not record counts or isomorphism
classes. Recipe-only prices and transient proposal states are not additions.

| Shape | Full MFW1 SHA-256 |
| --- | --- |
| 7x11x12 | `8977e56cfc18bbb506d6c422e4c9dd51ec0b39896741c8f3d80026984a39909c` |
| 8x11x11 | `ad2e0055a9b983aa7a5fe508758376e753f1c54df1b7b19da77166c3002cc647` |
| 8x11x12 | `04d934281a39fe080c8851d4cbfa78119f7a63a0634ab8e3202a363a8ffc5dfe` |
| 8x11x16 | `6f33a6dca357e3f8752e1fe678cb35b2cd25e40f84e18ae28c2fddb6d526f501` |
| 8x11x23 | `90f334a791caa14218c3bc3dd932119ade930b5a7020985b466469cd0d49c1af` |
| 16x22x22 | `06fb228c0d26d6f758ce842ffade04f4f630c1f6763e9247cde9ece62eb167ba` |
| 16x22x24 | `b4557db59ca8867cef17208fdcd3d283e4bf8d87348d337b6461c96a43c92546` |
| 16x22x32 | `c6db66b69769b8c17e37cfe33de20ac3731a40828d1028e44c5aadcc218048d9` |

## Comparison and retention scope

Fresh HTTP responses saved September 11, 2026 support the comparisons for
[7x11x12](https://fmm.univ-lille.fr/7x11x12.html),
[8x11x11](https://fmm.univ-lille.fr/8x11x11.html),
[8x11x12](https://fmm.univ-lille.fr/8x11x12.html),
[8x11x16](https://fmm.univ-lille.fr/8x11x16.html),
[8x11x23](https://fmm.univ-lille.fr/8x11x23.html),
[16x22x22](https://fmm.univ-lille.fr/16x22x22.html),
[16x22x24](https://fmm.univ-lille.fr/16x22x24.html), and
[16x22x32](https://fmm.univ-lille.fr/16x22x32.html).
The web-search cache's rank 691 for 8x11x12 is stale; the fresh response says
676. Replay checks the ranks in all eight saved responses.

The catalogue HEADs still match the preceding pinned comparison:
`solven-eu/matmulcatalog` at `f3a7f0f61b1005666c2cb03f98f2a16727604ea0`,
and `dronperminov/FastMatrixMultiplication` at
`db560ca5811bc38d5a6d5c0a3ec4315937ceabce`. These checks do not establish
global literature absence, isomorphism novelty or public acceptance.

The private replay bundle retains recipes, checked leaf/source snapshots,
endpoint tensors, native binaries, source pins and reference responses.
Neighbor intermediates are reconstructed rather than duplicated. The first
scratch attempts caught a decimal-MFR/hex-MFW import mix-up and an unsorted
recipe comparison; both failed closed and their failure logs are retained.
Corrected end-to-end replay passes.

```
~/.local/share/tungsten-metaflip/evidence/2026-09-11-slot-leaf-candidates.tar.gz
23,067,143 bytes; 2,863 payloads
SHA256 8180e5a51dae3f6611e761b867b5a9961fd246ff3392352334766a76b95c2913
```

After extraction, run `python3 -B replay.py audit` with the checker
dependencies installed. This machine uses Homebrew Python 3.14 with NumPy;
the explicit executable is `/opt/homebrew/opt/python@3.14/bin/python3.14`.
Replay needs neither the original scratch directories nor the checkout.
The bundled native binaries target this local platform. Every archived
payload was read back and checked against its SHA-256 manifest.
The complete replay also passes from a fresh extraction outside the checkout,
including all eight corruption rejections, with identical ranks and counts.

This was an automated offline campaign using existing MetaFlip tools, not a
new default `bin/metaflip` lane. No runtime code/defaults, canonical seeds,
public catalogue, GPU search, profiling, push or publication changed. Each
search/replay used one low-priority CPU worker. Unrelated edits were preserved.

Next useful tests include allocations clipped on all three axes, additional
checked leaf variants, and preserving this recipe lineage when scheduling
automatic per-slot refinement. More attempts in the unchanged rank-47 walk
would not address the failure observed here.

The [triple-clipped and outer-basis follow-up](TRIPLE-SLOT-BASIS-AUDIT-2026-09-11.md)
now checks that first family: 2,378 additional representations, no retained
bound gain. The eight candidates above remain unchanged.
