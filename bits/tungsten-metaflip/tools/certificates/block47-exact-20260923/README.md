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

The four additional 13x rows came from materializing 20 unarchived audited
formulas with `screen_block47_cancellations.py`. Four had strict exact
cancellations; the other 16 did not. A second sweep of eight 14x16 formulas found
one more cancellation at 14x16x26. A first 100-million-move directed walk
lowered each of the five further. A second 100-million-move walk tied each
rank with lower density, so the lower-density tensors are retained. Their
exact-composition parents and both walk nonces are pinned in the manifest.
The earlier 13x15x27 composition and walk are retained unchanged. Bounded
postbasis scans of 13x15x23 and 13x15x26 tied their current ranks.

From the repository root, run:

```sh
python3 bits/tungsten-metaflip/tools/check_block47_exact_20260923.py
```

Optionally compile `bits/tungsten-metaflip/tools/wide_rect_walk.w` and pass its
binary as `--replay-walk BINARY` to reproduce the retained directed walk byte
for byte. `--replay-compose BINARY --leaf-root DIR` also re-materializes all
eight block formulas with `flipfleet_block_compose.w` and verifies their exact
canonical hashes. The tensors beat the numeric ranks in the Lille table as
checked on 2026-09-23. This finite comparison is not a worldwide-record or
optimality claim. Against the existing cross-audit formula bounds, the five
new materializations improved their target shapes but produced no additional
downstream gain in the current direct-sum/product closure over sorted
dimensions 2--32; no universal composition claim is made.
