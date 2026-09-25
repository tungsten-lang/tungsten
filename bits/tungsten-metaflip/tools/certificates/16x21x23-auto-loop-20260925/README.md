# Exact 16×21×23 GF(2) feedback-loop witness

The bounded loop started from the checked-in 16×23×22/r4618 tensor.
An exact projection reached 16×23×21/r4517, one 50-million-move directed
walk reached r4501, and a rank-tied basis change followed by another walk
reached **r4497**. This lowers the prior local price of 4542 by 45.
The five-state lineage is retained in `manifest.json`. Run
`python3 verify.py` to check the source, basis/projection edges, and every
complete GF(2) tensor independently in Python and Ruby.

The [Lille catalogue](https://fmm.univ-lille.fr/) listed rank 4469 for this
shape on 2026-09-25. The result is therefore a local improvement, still 28
above that comparison. The six-walk campaign is finite and establishes no
optimality or global novelty claim.
