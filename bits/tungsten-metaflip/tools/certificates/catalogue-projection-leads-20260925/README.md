# Exact GF(2) catalogue-projection leads

These five complete MFW1 witnesses come from two bounded offline campaigns:
19×24×29/r7236 → 19×24×28/r7005 → r6994 → r6990, and
16×23×23/r4743 → 16×22×23/r4625 → r4618. The other two retained children
are exact projections without a walk. `python3 verify.py` reconstructs every
projected seed from its parent, checks its rank and hash, then verifies each
retained full tensor independently in Python and Ruby. Walk metadata records
finite provenance, not a claim that the random moves were replayed.

| Shape | Best retained rank | Prior local price | Lille table, 2026-09-25 |
| --- | ---: | ---: | ---: |
| 19×24×28 | 6990 | 7253 | 7012 |
| 19×23×29 | 7113 | 7293 | 7075 |
| 16×22×23 | 4618 | 4716 | 4627 |
| 15×23×23 | 4635 | 4713 | 4585 |

The rank inputs lower eleven prices in the pinned 2..32 GF(2) composition
calculation by 1,025 summed rank units; only four distinct final tensor shapes
are materialized. The 19×24×28 and 16×22×23 GF(2) ranks are numerically below
the [Université de Lille catalogue](https://fmm.univ-lille.fr/) entries checked
on 2026-09-25. That cross-field comparison is not a confirmed global
world-record claim. These are upper bounds, not optimality claims.
