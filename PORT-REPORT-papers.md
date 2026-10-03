# PORT-REPORT-papers: paper build scripts in Tungsten

Branch `port/papers` (worktree `/Users/erik/tungsten-mf-port-papers`), created from `metaflip-tungsten-port` at `ec0a1d069`.
Scope: `tungsten-lang/papers/scripts/{mkbib,pack_arxiv,make_arxiv_md,gen_results_data,prior_art_flags}.py`
ported to `.w` next to the originals (the originals stay as oracles); `tungsten-lang/papers/Makefile` switched to the Tungsten scripts.
`ruby_verify_all.py` and `rebuild_closure.py` are not in this task.

Status: in progress (this file is updated after every script).

## Oracle runs

Oracle = the Python originals (Python 3.14.7) run on a `git archive` copy of the papers directory in a scratch directory.
`export BIT_HOME=<worktree>/bits GIT_NO_LAZY_FETCH=1`; Tungsten by absolute path `/Users/erik/tungsten/bin/tungsten`.

## Files

| file | original | port |
|---|---|---|
| (filled in as the ports land) | | |

## Parity evidence

(filled in as the ports land)

## Timing

(filled in as the ports land)

## Tests

(filled in as the ports land)

## Deviations

(filled in as the ports land)

## Blockers and workarounds

(filled in as the ports land)
