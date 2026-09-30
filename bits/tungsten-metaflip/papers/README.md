# Papers on the 2026-09 GF(2) matrix-multiplication record hunt

Two arXiv drafts about the search campaign of 2026-09-26..29 (and the two earlier stages it pools):

| directory | paper | what it says |
|---|---|---|
| `methods/` | *Directed Flip-Graph Walks, Projection Cascades and Composition Closure for GF(2) Matrix-Multiplication Schemes: Search Methods with Provenance-Preserving Verification* | the walker, the cross-shape derivation (projection, basis rewrite, cascade), composition closure, public-seed ingestion, scoring, lineage bundles and the verification protocol, with the yields and the defects we found |
| `results/` | *Upper Bounds on the GF(2) Rank of Matrix Multiplication Below Four Public Tables: 795 Formats up to 32x32x32 and a Prior-Art Check* | the 795 formats below four public tables, how they arose, how they compare with the tables, and what survives a prior-art check (87 superseded, 112 matched by published constructions, 596 remain) |

Both are **drafts**. `\todo{...}` marks everything that needs the author or a decision (they print in red).

## Build

```
make                # methods/main.pdf and results/main.pdf   (needs tectonic; no other TeX install)
make arxiv          # dist/{methods,results}-arxiv.tar.gz, each verified by a standalone rebuild
make final          # the same, but refuses while any \todo remains
```

Only tectonic (XeTeX) was available when the drafts were written. The sources are ASCII and use standard packages, so arXiv's pdfLaTeX
should accept them, but that was not tested. `ARXIV.md` has the paste-ready metadata (abstracts are under arXiv's 1,920-character limit).

`scripts/mkbib.py PAPER` writes `PAPER/refs.bib` from `refs-all.bib` (the 50 entries checked against the sources when the bibliography
was assembled) and `extra.bib` (this project's own entries and Drevet-Islam-Schost, whose data come from the AlphaTensor docstring and
were not otherwise checked), keeping only the cited keys and dropping our verification memos from the printed `note` fields.

## Data and checks behind the papers

`results/data/*` and `results/tables/*` are generated:

```
python3 scripts/prior_art_flags.py RECORDS_TSV CONSOLIDATED_MD PAPER_DATA_DIR/prior_art_flags.tsv
python3 scripts/gen_results_data.py RECORDS_TSV PAPER_DATA_DIR results
```

`RECORDS_TSV` is `records.tsv` of the `gf2-campaign-records` asset of release `evidence-2026-09-29` of `tungsten-lang/metaflip-archives`;
`PAPER_DATA_DIR` holds the figure TSVs that the campaign's statistics script wrote (`paper_stats.py`, still only in the campaign work directory)
and `prior_art_flags.tsv`; `CONSOLIDATED_MD` is section C of the prior-art audit (`paper-notes/08-rescore-and-prior-art.md`, produced by
`08-consolidate.py` in the work directory). `gen_results_data.py` also applies the two lineage corrections described in the results paper
(9x9x9 is a walk from a public scheme, 13x13x13 is a July certificate; the archived index says "live fleet checkpoint").

`verification/` holds two logs made for the papers, with the scripts that produced them:
`ruby_all_20260929.log` (`scripts/ruby_verify_all.py`: the Ruby exactness check over the 985 distinct bundle tensors, the 102 committed
certificates and the two fleet checkpoints, 1,089 tensors, all exact) and `rebuild_closure_20260929.log` (`scripts/rebuild_closure.py`:
259 of 267 closure rows rebuild byte for byte; 8 rows depend on three unrecovered leaves). Both need the campaign's `release-0929/` directory.

## Before submitting (author's list)

1. Affiliation, contact, funding and conflict-of-interest statements (placeholders in `results/main.tex` and `methods/main.tex`).
2. Push and merge branch `metaflip-public-ternary-gf2`; deposit the tensors publicly (the archive repository is private) and cite the DOI.
3. Re-score against the tables at submission time: all four sources changed during the campaign, and `results/sections/persistence.tex`
   records the state of the last check (2026-09-29, 21:33 UTC).
4. Prior art: the check in `persistence.tex` was limited (48 papers, four constructions, one evening). It superseded 87 of the 795 records and matched 112;
   a complete audit has not been done and the claim policy label stays "apparent". Update the counts if the check is repeated.
5. Licensing: the matmulcatalog repository has no licence file; the project owner decided to redistribute with attribution, but the authors of that catalogue have not been asked.
6. The AI-assistance disclosure in the acknowledgements is deliberate; keep or edit it as you see fit.
7. Corrections to earlier project documents that the papers state are listed in `ERRATA.md`; apply them to the archive and the notes.
8. Suggested arXiv categories: cs.SC (primary), cross-lists cs.CC and cs.DS.
