# Prior-art audit of 2026-09-29 (evening)

Evidence behind `results/sections/persistence.tex`. These are the audit's own files, copied unchanged from the campaign work directory
(`~/.tungsten/metaflip/experiments/record-hunt-20260926/work/paper-notes/`). They were run from that directory, with the fresh clones
of the four tables under `work/upstream-latest/`, the fetched papers under `work/upstream-latest/arxiv/<id>/` and the release under
`work/release-0929/`; the paths are absolute and they will not run elsewhere without edits. They are records, not tools.

| file | what it is |
|---|---|
| `report.md` | the audit note (was `08-rescore-and-prior-art.md`): re-score, literature check, the per-record flags of section C, recommended wording |
| `08-rescore-latest.py` | Part A: re-scores the 795 records against the latest heads with the release's own `public_tables()` |
| `08-fetch-literature.py`, `08-literature-check.py` | fetch the papers; parse Perminov's three rank papers, decode and verify Medley et al.'s rank-245 scheme, re-check the transcribed rows |
| `08-literature-data.py.gz` | the 878 transcribed rows with line, page and verbatim quote (gzip; `import` needs it un-gzipped as `08-literature-data.py`) |
| `08-composition-closure.py`, `08-composition-verify.py` | rank-only closure by sums, Kronecker products and Strassen; explicit compositions of published scheme files built and verified (146 schemes) |
| `08-serendipitous-check.py` | rebuilds the matmulcatalog's serendipitous-product claims over GF(2) from the named FMM base schemes and verifies them |
| `08-crosscheck-release-verifier.py` | nine of the superseding schemes through the release verifier, plus a negative control |
| `08-consolidate.py` | one flag per record (S1 S2 M1 M2 Q none); its output is `../results/data/prior_art_flags.tsv` (see `../scripts/prior_art_flags.py`) |
| `10-fullpool-closure.py`, `.log` | rank-only closure over ALL formats from the union of public GF(2)-valid ranks and our own witnesses (276 / 461 / 984 formats below the four tables) |

Not shipped: the fetched paper texts and PDFs, the 185 schemes rebuilt by the audit and by the round-2 fact-check, and `10-fullpool-closure.json`
(536 KB). They belong with the data release.
