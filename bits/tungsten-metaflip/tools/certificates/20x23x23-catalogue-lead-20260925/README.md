# Exact GF(2) 20×23×23 catalogue lead

The checked-in 20×23×24/r6005 parent projects to 20×23×23/r5924. A bounded
50M-step directed walk reached r5885; a 100M-step continuation reached r5883.
Two stronger sibling projections are also retained. `python3 verify.py`
reconstructs every projection seed from its parent and independently checks
each full tensor in Python and Ruby. The finite walk metadata records
provenance, not deterministic replay of all moves.

| Shape | Best retained rank | Prior local price | Lille table, 2026-09-25 |
| --- | ---: | ---: | ---: |
| 20×23×23 | 5883 | 6095 | 5906 |
| 20×22×24 | 5851 | 5902 | 5764 |
| 19×23×24 | 5894 | 6032 | 5825 |

These inputs lower seven prices in the pinned 2..32 GF(2) rank-only
composition calculation by 721 summed rank units. Only the three final
tensor shapes are materialized. The 20×23×23 GF(2) rank is numerically 23
below the [Université de Lille catalogue](https://fmm.univ-lille.fr/) entry
checked on 2026-09-25. This is not a confirmed global world-record claim;
all three ranks are upper bounds, not optimality claims.
