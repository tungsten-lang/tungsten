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

| Shape | Retained rank | Prior local price | Lille table, 2026-09-25 |
| --- | ---: | ---: | ---: |
| 20×22×23 | 5702 | 5940 | 5722 |
| 19×22×23 | 5551 | 5748 | not established here |
| 20×21×23 | 5463 | 5654 | not established here |

These tensor witnesses lower six rank-only prices in the pinned 2..32 GF(2)
composition calculation, by 862 summed rank units. The other three prices
are 19×22×29: 7187→7143, 21×21×23: 6027→5946, and 21×22×23: 6310→6199.
Those prices are not materialized tensors. The 20×22×23 rank is numerically 20 below the
[Université de Lille catalogue](https://fmm.univ-lille.fr/20x22x23.html)
entry checked on 2026-09-25. It is not a confirmed global world-record claim
and none of these ranks is an optimality claim.
