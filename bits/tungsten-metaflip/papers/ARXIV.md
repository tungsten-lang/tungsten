# arXiv submission metadata (drafts of 2026-09-29)

Paste-ready fields for the arXiv submission form (`python3 scripts/make_arxiv_md.py` regenerates this file from the abstracts in `main.tex`).
arXiv limits the abstract field to 1,920 characters. Everything marked TODO needs the author.

## results/

- **Title:** Upper Bounds on the GF(2) Rank of Matrix Multiplication Below Four Public Tables: 795 Formats up to 32x32x32 and a Prior-Art Check
- **Authors:** Erik Peterson (TODO: affiliation, contact e-mail, ORCID)
- **Abstract** (1512 characters; limit 1,920):

  We report exact decompositions of the matrix-multiplication tensor over GF(2) for 795 formats <n,m,p> with all sides at most 32 whose rank is below every rank that four public tables list on 2026-09-29, in any ring (733 formats) or among schemes known to be valid over F_2 (62 formats). They are upper bounds only. The tables omit public GF(2)-valid prior art, and a check against the literature shows it: 87 of the 795 are superseded by published constructions or claims (80 by schemes we rebuilt and verified, 7 by published rank claims that we did not reproduce) and 112 more equal the rank of a composition of published schemes; 596 remain. Most of the 795 have no walk and no projection in their recorded lineage (507: 379 compositions, and 128 certificates and fleet checkpoints of earlier stages, which include walks); the rank-47 scheme for <4,4,4> over F_2 is the most frequent ingredient, and 92% have a side above 16. For the 733 strongest the median saving over the listed rank is 29 terms (0.9%); the largest are 268 terms, for <20,23,32> (7,772 against 8,040), and 4.8%, for <15,16,17>, and both remain. Neither record with all sides at most 8 is new. The comparison is easy to overstate (458 of the 733 have no GF(2)-valid scheme listed at all, commutative algorithms must be excluded, and the tables move), so we describe it carefully. All tensors are exact over F_2 and were checked by two separately written implementations; 691 ship with their derivation. The methods are in a companion paper.

- **Comments:** 26 pages, 10 tables, 2 figures (plus appendices). Companion paper: "Directed Flip-Graph Walks, Projection Cascades and Composition Closure for GF(2) Matrix-Multiplication Schemes: Search Methods with Provenance-Preserving Verification". Draft of 2026-09-29.
- **Primary category:** cs.SC (Symbolic Computation); **cross-lists:** cs.CC (Computational Complexity), cs.DS (Data Structures and Algorithms)
- **MSC class:** 68Q25; 15A69; 68W30    **ACM class:** F.2.1; I.1.2
- **License:** TODO (author's choice; CC BY 4.0 is the usual one)
- **Source bundle:** `make arxiv` writes `dist/results-arxiv.tar.gz` (main.tex, sections, tables, data, `main.bbl`, `refs.bib`); it is rebuilt standalone before it is written.

## methods/

- **Title:** Directed Flip-Graph Walks, Projection Cascades and Composition Closure for GF(2) Matrix-Multiplication Schemes: Search Methods with Provenance-Preserving Verification
- **Authors:** Erik Peterson (TODO: affiliation, contact e-mail, ORCID)
- **Abstract** (1754 characters; limit 1,920):

  Upper bounds on the tensor rank of matrix multiplication over F_2 are found by random walks on flip graphs and by composing known schemes. We describe the pipeline behind a large 2026 campaign, whose outcome is reported in a companion paper: a single-threaded, allocation-free directed flip-graph walker with bit-packed multiword factors, whose walks replay byte for byte, on the same build, from a seed file, a step count and a nonce; a cross-shape derivation step that projects a scheme onto a smaller shape after a shared-factor basis rewrite; a rank-only composition closure over block sums and Kronecker products, materialized into witnesses; ingestion of public integer and ternary schemes modulo two, and replay of matmulcatalog derivations over F_2; a scoring discipline against four public rank tables; and lineage bundles whose tensors are checked by two separately written exactness verifiers and whose seed, projection and replay rows are re-derived from pinned upstream revisions. Over 4,816 walks (3.1x10^11 proposals) the stages differ by orders of magnitude in yield: 40M-move walks from projection children lowered the rank below their starting rank in 90% of cases (relative to unreduced seeds, so not a yield of records), against 0.95% for walks from public integer schemes. We report a reproducibility defect that only a verification from a clean extraction with empty caches exposed, and comparison pitfalls: a comparison with the four tables alone overstated novelty, since a later check found 87 of 795 results superseded by published constructions or rank claims (80 rebuilt and verified, 7 claims) and 112 more matched by compositions of published schemes or claims. Every claim is an upper bound; nothing here proves optimality.

- **Comments:** 28 pages, 7 tables, 2 figures (no appendices). Companion paper: "Upper Bounds on the GF(2) Rank of Matrix Multiplication Below Four Public Tables: 795 Formats up to 32x32x32 and a Prior-Art Check". Draft of 2026-09-29.
- **Primary category:** cs.SC (Symbolic Computation); **cross-lists:** cs.CC (Computational Complexity), cs.DS (Data Structures and Algorithms)
- **MSC class:** 68Q25; 15A69; 68W30    **ACM class:** F.2.1; I.1.2
- **License:** TODO (author's choice; CC BY 4.0 is the usual one)
- **Source bundle:** `make arxiv` writes `dist/methods-arxiv.tar.gz` (main.tex, sections, tables, data, `main.bbl`, `refs.bib`); it is rebuilt standalone before it is written.
