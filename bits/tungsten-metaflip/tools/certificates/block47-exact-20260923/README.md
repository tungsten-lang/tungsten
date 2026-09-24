# Exact block-47 materializations, 2026-09-23

These are complete GF(2) matrix-multiplication tensors, not just block-formula
rank estimates. `manifest.json` pins the historical cross-audit and source
revision lists. The parent formulas use the rank-47 4x4 outer tensor and the
audited 3--8 leaf pool. The compressed MFW1 files carry the final witnesses;
the checker expands every coefficient using both the Python and independent
Ruby full-tensor verifiers.

| Shape | Audited formula | Exact composition | Retained rank | Lille listed rank |
|---|---:|---:|---:|---:|
| 13x15x23 | 2664 | 2662 | 2659 | 2724 |
| 13x15x26 | 3013 | 3012 | 3010 | 3074 |
| 13x15x27 | 3131 | 3129 | 3126 | 3191 |
| 13x16x26 | 3148 | 3148 | 3148 | 3226 |
| 13x16x27 | 3256 | 3256 | 3256 | 3346 |
| 13x19x26 | 3764 | 3762 | 3761 | 3838 |
| 13x19x27 | 3898 | 3894 | 3893 | 3989 |
| 14x16x26 | 3413 | 3412 | 3407 | 3472 |
| 15x19x29 | 4768 | 4766 | 4766 | 4835 |
| 15x19x31 | 5089 | 5083 | 5083 | 5131 |
| 15x22x25 | 4732 | 4731 | 4731 | 4787 |
| 15x22x26 | 4938 | 4936 | 4936 | 4974 |
| 15x22x27 | 5124 | 5120 | 5115 | 5148 |
| 15x23x25 | 4915 | 4913 | 4913 | 4968 |
| 15x23x26 | 5137 | 5133 | 5129 | 5167 |
| 16x20x26 | 4636 | 4636 | 4634 | 4802 |
| 16x21x25 | 4710 | 4710 | 4710 | 4836 |
| 16x21x26 | 4908 | 4908 | 4908 | 5041 |
| 16x22x24 | 4665 | 4665 | 4665 | 4732 |
| 16x22x25 | 4921 | 4921 | 4921 | 5028 |
| 16x22x26 | 5139 | 5138 | 5136 | 5250 |

The four additional 13x rows came from materializing 20 unarchived audited
formulas with `screen_block47_cancellations.py`. Four had strict exact
cancellations; the other 16 did not. A second sweep of eight 14x16 formulas found
one more cancellation at 14x16x26. A first 100-million-move directed walk
lowered each of the five further. A second 100-million-move walk tied each
rank with lower density, so the lower-density tensors are retained. Their
exact-composition parents and both walk nonces are pinned in the manifest.
The earlier 13x15x27 composition and walk are retained unchanged. Bounded
postbasis scans of 13x15x23 and 13x15x26 tied their current ranks.
An 18-shape 14x/15x sweep found three more exact cancellations at 15x19x29,
15x22x25, and 15x23x25. Their 100-million-move walks returned the exact
composition parents unchanged, so no walk outcome is needed to replay them.
An adjacent 11-shape sweep found four further cancellations. The walks on
15x19x31 and 15x22x26 returned their composition parents unchanged; the
retained walks on 15x22x27 and 15x23x26 lower them to 5115 and 5129.
A further six-shape 15x/16x allocation-boundary sweep found one cancellation,
at 16x22x26. Its first 100-million-move directed walk reduced rank 5138 to
5136; the next two tied rank while lowering density. All three nonces and the
exact-composition parent are pinned in the manifest.
Its coordinate projections gave five independently exact tensors below the
Lille-listed ranks, but each was numerically dominated by an already audited
block-47 formula. The projections were not retained in this package. We
materialized and independently verified those five stronger formulas instead.
One 100-million-move walk improved 16x20x26 by two terms; matched walks on the
other four tied their formula ranks.

From the repository root, run:

```sh
python3 bits/tungsten-metaflip/tools/check_block47_exact_20260923.py
```

Optionally compile `bits/tungsten-metaflip/tools/wide_rect_walk.w` and pass its
binary as `--replay-walk BINARY` to reproduce the retained directed walk byte
for byte. `--replay-compose BINARY --leaf-root DIR` also re-materializes all
twenty-one block formulas with `flipfleet_block_compose.w` and verifies their exact
canonical hashes. The tensors beat the numeric ranks in the Lille table as
checked on 2026-09-24. This finite comparison is not a worldwide-record or
optimality claim. With the historical formula bounds included, the first five
new materializations improve only their target shapes in the direct-sum/product
closure over sorted dimensions 2--32. The three later shapes also reduce the
numeric closure at 23x25x31 from 10002 to 10000, but that remains worse than
Lille's listed 9585. No additional record candidate or universal composition
claim follows from that finite scan. The four adjacent-sweep tensors improve
only their own shapes against the same formula-bounded closure. The new
16x22x26 tensor also lowers the finite numeric closure at 18x22x26 from 6041
to 6038, still worse than Lille's listed 5771. Among the six new retained
rows, only 16x20x26 and 16x22x26 lower the already audited block-formula
numeric closure over sorted dimensions 2--32; the four other rows turn prior
formula estimates into full exact tensor witnesses.
