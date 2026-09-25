# Exact GF(2) 20×22×23 projection/walk feedback

The checked-in 20×23×23/r5883 tensor projects through basis mode 10 to
20×22×23/r5740. One bounded 50M-move native walk reached r5702; a separate
50M-move continuation stayed at r5702. The bounded automatic loop then found
19×22×23/r5583 by projection and r5551 by a 50M-move walk, plus a direct
20×21×23/r5502 projection. That second projected child was not given a walk
slot by the old scheduler, so a separate 50M-move walk tested the revised
two-child priority and reached r5463. The original loop completed two walks
and admitted eight exact states; only the minimal useful provenance chain is
retained here.

`python3 verify.py` reconstructs each projected seed from its checked-in
parent and independently checks every full tensor in Python and Ruby. Walk
counts and nonces record provenance, not deterministic replay of every move.

| Shape | Retained rank | Prior local price | Pinned external best |
| --- | ---: | ---: | ---: |
| 20×22×23 | 5702 | 5940 | 5596 |
| 19×22×23 | 5551 | 5748 | not established here |
| 20×21×23 | 5463 | 5654 | not established here |

These tensor witnesses lower six rank-only prices in the pinned 2..32 GF(2)
composition calculation, by 862 summed rank units. The other three prices
are 19×22×29: 7187→7143, 21×21×23: 6027→5946, and 21×22×23: 6310→6199.
Those prices are not materialized tensors. The search-indexed
[Université de Lille detail page](https://fmm.univ-lille.fr/20x22x23.html)
displays 5722, but the pinned 2026-09-22 catalogue snapshot (SHA-256
`1a43aedc346bae47458dafe053fcff6ec78934ffc7124b8c046960b9891a2719`)
records a Lille best of 5596 for the same shape. Until that discrepancy is
resolved, r5702 must **not** be described as beating Lille or as a world
record. None of these ranks is an optimality claim.
