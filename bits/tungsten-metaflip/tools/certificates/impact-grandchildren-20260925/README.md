# Exact GF(2) projection-grandchildren

This package retains five complete tensor witnesses from a bounded two-round
projection → directed-walk → composition-feedback campaign rooted at the
checked-in 19×25×27/r7144 parent, plus one 100-million-move continuation.
`python3 verify.py` reconstructs each
projection from its parent, checks the projection seed rank and hash, and
independently checks the retained full tensor in Python and Ruby. Walk
metadata records finite provenance; exactness does not depend on replaying
the random moves.

| Shape | Rank | Prior local price |
| --- | ---: | ---: |
| 19×24×27 | 6827 (via 6841) | 7128 |
| 19×24×26 | 6683 | 6878 |
| 19×23×27 | 6747 | 6789 |
| 19×25×26 | 7023 | 7183 |

Against the pinned 2..32 GF(2) price closure before these inputs, their
rank-only composition effect lowers eight shape prices by 921 summed rank
units. Only the five retained tensors are materialized and independently
checked. The best 19×24×27 rank is three below the [Université de Lille
catalogue](https://fmm.univ-lille.fr/)'s 6830 entry as checked on
2026-09-25, but it is a GF(2) construction and not a confirmed global
world-record claim. All listed ranks are upper bounds, not optimality claims.
