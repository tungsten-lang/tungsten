# Exact block-47 materializations, 2026-09-23

These are complete GF(2) matrix-multiplication tensors, not just block-formula
rank estimates. `manifest.json` pins the historical cross-audit and source
revision lists. The parent formulas use the rank-47 4x4 outer tensor and the
audited 3--8 leaf pool. The compressed MFW1 files carry the final witnesses;
the checker expands every coefficient using both the Python and independent
Ruby full-tensor verifiers.

| Shape | Audited formula | Exact composition | Retained rank | Lille listed rank |
|---|---:|---:|---:|---:|
| 13x15x27 | 3131 | 3129 | 3126 | 3191 |
| 13x16x26 | 3148 | 3148 | 3148 | 3226 |
| 13x16x27 | 3256 | 3256 | 3256 | 3346 |

The 13x15x27 composition has two cancellations omitted by the formula scan.
A 100-million-move directed walk from that exact rank-3129 parent (nonce
21907) saves three more terms. The parent is retained so the walk can be
replayed. A second nonce (21901) reached the same rank, and a continuation
from that result (21905) tied. Bounded postbasis scans did not lower any of
these three ranks; a 100-million-move walk from each of the other two tied.

From the repository root, run:

```sh
python3 bits/tungsten-metaflip/tools/check_block47_exact_20260923.py
```

Optionally compile `bits/tungsten-metaflip/tools/wide_rect_walk.w` and pass its
binary as `--replay-walk BINARY` to reproduce the retained directed walk byte
for byte. `--replay-compose BINARY --leaf-root DIR` also re-materializes all
three block formulas with `flipfleet_block_compose.w` and verifies their exact
canonical hashes. The tensors beat the numeric ranks in the Lille table as checked on
2026-09-23. This finite comparison is not a worldwide-record or optimality
claim. Against the existing cross-audit formula bounds, replacing 3131 with
3126 improves only 13x15x27 itself under the current direct-sum/product closure
over sorted dimensions 2--32; no further composition gain is claimed.
