# Exact GF(2) impact-parent projection children

These ten complete MFW1 tensor witnesses come from exact coordinate
projections of the six checked-in impact parents, optional same-rank basis
changes, and bounded directed walks. `python3 verify.py` reconstructs each
projected seed from its parent, checks the seed rank and hash, then checks the
retained witness by independent Python and Ruby full-tensor verifiers. The
walk metadata records finite provenance; the verifier checks the final tensor
identity, not deterministic replay of every move.

| Shape | Final rank | Pinned local price before this batch | Lille table, 2026-09-25 |
| --- | ---: | ---: | ---: |
| 12×13×23 | 2142 | 2203 | 2136 |
| 16×17×22 | 3475 | 3509 | 3509 |
| 16×23×23 | 4743 | 4893 | 4785 |
| 15×23×24 | 4699 | 4827 | 4712 |
| 19×23×25 | 6122 | 6400 | 6154 |
| 20×22×25 | 6076 | 6329 | 6075 |
| 20×23×24 | 6005 | 6222 | 6084 |
| 19×24×29 | 7236 | 7691 | 7272 |
| 19×25×27 | 7144 | 7493 | 7198 |
| 20×25×26 | 7130 | 7204 | 7171 |

Eight final GF(2) ranks are numerically below the
[Université de Lille catalogue](https://fmm.univ-lille.fr/) entries checked
on 2026-09-25. That catalogue includes algorithms over other fields, so this
is not a verified global or field-specific world-record claim. All ten are
exact GF(2) upper bounds, not optimality claims.

Against the pinned 2..32 GF(2) price closure *after* the six parent witnesses,
these ten rank inputs lower 51 shape prices by 4,995 total rank units. Those
are composition prices, not 51 additional materialized tensor certificates.
The certificates add less than a few megabytes to the repo; the raw search
archives remain outside it.
