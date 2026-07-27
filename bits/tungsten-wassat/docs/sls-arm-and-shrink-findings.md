# SLS as a race arm, and the chrono/shrink question — 2026-07-27

Follow-up to `why-we-lose.md`. **Landed** (`97ed3d1`). It was developed on a
branch in a detached worktree because another agent held an in-flight refactor
of `lib/{policy,portfolio,solver,wassat}.w` at the time; that refactor has since
landed as `383594b`, and this was rebased onto it, re-gated and re-measured
against the new baseline. Every measurement used a hash-pinned compiler.

**Headline against current main: geomean 0.7636** over the parity + survey rows
(11 faster >5%, 7 slower >5%, 13 within 5%; total 44.9s -> 40.2s). The 0.69
below was against the pre-refactor baseline and is kept because the per-row
detail is still the clearest picture of where the arm pays.

## 1. SLS as a race arm — landed on the branch, geomean 0.69

The defect from `why-we-lose.md`: the SLS burst was gated on
`art["clauses"].size` in 2000..50000, on a raw path whose artifact returns
`"clauses": []`. Structurally unreachable.

**Two arms, not one.**

- One races the **scout**, bounded by *the scout's lifetime* rather than by a
  flip budget. That is what makes it free: it walks for exactly as long as the
  scout was going to run anyway, so a miss costs a core on a stage already
  running and never a millisecond of wall clock. On dense formulas the scout's
  2,000-conflict cap is expensive (748ms on `n320p5q2_n`), which is precisely
  the budget local search needs there.
- One races the **raw arms** behind it, for rows needing a longer walk
  (`ntil-90d-33` needs 1.2M flips).

`wassat_sls_run` gained a stop cell polled in the flip loop, so an arm dies
within one flip of any other arm answering. `wassat_scout_arm_body` now
publishes its verdict to that cell.

**The load-bearing detail.** The scout's *usual* outcome is status 0
(undecided, hand off to the raw race), which signals nothing. An arm waiting on
a signal that never comes walks out its entire budget with the join blocked
behind it. Measured when it did: `bmc-ibm-12` 0.7s → 25s timeout,
`uuf200-013` 0.16s → 25s, `mrpp_6x6#14_10` 0.14s → 25s. The fix is to raise the
cell unconditionally after the scout and lucky arms join.

### Result

Over reference.py's parity + survey rows, 3 reps, min-of-3, verdicts checked
against the published answers and across binaries:

```
geomean 0.6906 vs HEAD   (9 rows faster >5%, 10 slower >5%, 9 within 5%)
    best : 3bitadd_31 0.02x, uf225-015 0.04x, uf250-0100 0.04x,
           g125.18 0.19x, g250.15 0.30x
    worst: dspam_dump_vc972 1.97x, bmc-ibm-6 1.86x, mrpp_6x6#14_10 1.70x,
           qwh.35.405 1.49x, shuffling-1 1.27x
```

On competition rows wassat does not solve today:

| row | HEAD | SLS arm | CaDiCaL | vs HEAD | vs CaDiCaL |
|---|---:|---:|---:|---:|---:|
| `n320p5q2_n` | 13.05 | **0.05** | 0.43 | 283x | **9.3x faster** |
| `n384p5q2_vh` | 66.99 | **0.47** | 1.71 | 143x | **3.7x faster** |
| `DivS_568_11` | DNF | **2.65** | 2.34 | 45x | 0.88x |
| `DivS_862_11` | DNF | **4.31** | 3.55 | 28x | 0.82x |
| `ntil-90d-33` | 56.94 | **17.76** | 12.74 | 3.2x | 0.72x |

**The regressions are real and should be stated with the win.** They are on
fast rows where an extra thread is not amortised — all under 0.12s absolute,
against wins of 25-280x on rows taking 13-120s. Total wall over the scored rows
32.6s → 31.2s, and the censored (>25s) rows improve far more than that without
being counted.

Gate: solver 38/38, cli 28/28, preprocess 21/21, incremental 12/12, sls 5/5,
trim 7/7, explain 5/5, portfolio 8/8; differential 200 cases in both default and
`WASSAT_RAW_AT=0`; php87 `--proof` VERIFIED by a freshly built `wrat`.

## 2. The dense-formula throughput gap — diagnosed, one concrete lever

`n320p5q2_n` is 320 variables / 30,726 clauses; `DivS_568_11` is 568 / 553,495
— about 975 clauses per variable. wassat runs 171-809 conflicts/second on these
against CaDiCaL's 9k-76k.

The SLS arm *sidesteps* this wherever the instance is satisfiable, which is
most of where it currently bites. It does not fix it, and the exposure that
remains is a dense UNSAT formula, where local search cannot help at all.

**One concrete lever, measured.** The bounded CDCL scout is deliberately
*not* wall-clock bounded on the raw path — "a raw kernel's scout is already
bounded by its conflict cap, so it runs on conflicts alone and is
reproducible". On dense formulas that cap is not a small budget: 2,000
conflicts cost **748ms** on `n320p5q2_n` (`c prof cli.scout_race 748ms` against
`c prof cli.raw_race 83ms` for the entire race behind it). A wall-clock bound on
the raw path would cut that, at the cost of the reproducibility the current
choice buys. That trade deserves its own measurement; it is not made here.

The deeper cost is watch-list scanning on formulas where every variable occurs
in ~1000 clauses, and that is a data-structure question (watch layout, blocking
literal effectiveness), not a policy one.

## 3. Chrono + shrinking — no winning formula, and a suspected defect

Shrinking was gated `@use_shrink && !@use_chrono` because the pass walks a
level's trail segment `[tlim[bl-1], tlim[bl])` and **aborts** on a foreign-level
entry, which chronological backtracking interleaves.

The guard was relaxed from abort to skip. This is sound in the strong sense: it
either finds every marked literal of the level and derives exactly what the
plain case derives, or runs past `flr` and aborts as before. The worst case is a
fruitless walk, never a wrong clause.

**The guard was not the binding constraint.** With shrinking now permitted on
chrono arms, measured at the shipped width (arms 0,1 chrono-off; arms 2,3
chrono-on):

| row | shrink off | on | ratio | conflicts off → on |
|---|---:|---:|---:|---|
| `php109` (cardinality) | 1.30 | 12.95 | **9.98x** | 11,841 → **407,421** |
| `hole9` (cardinality) | 1.29 | 12.82 | 9.92x | 11,990 → 401,862 |
| `minand064` (bitvector) | 3.95 | **2.13** | **0.54x** | 94,504 → **36,832** |
| `bmc-ibm-12` | 0.69 | 1.04 | 1.50x | 5,832 → 6,903 |
| `uuf250-01` (random) | 1.41 | 1.91 | 1.35x | 128,059 → 158,619 |

There is one genuine winning cell — `minand064` at 0.54x with 2.6x fewer
conflicts — so the technique is not worthless here. But **on the cardinality
shapes, which are exactly where the literature says All-UIP shrinking should
pay, it is 10x worse and needs 34x the conflicts.** A pass that costs 34x the
conflicts on pigeonhole is not merely unhelpful; that is the signature of a
defect in the implementation, not a policy question. It matches the earlier
observation that php87 regressed 3.7x with 29% of literals removed.

**Recommendation: do not enable it, and do not treat this as a tuning question.**
The next step is to find out why the shrunken clause is so much weaker on
counting encodings — most likely the shrink target level or the asserting
property — rather than to search for a shape gate that dodges the symptom.
Shrinking stays off; the relaxation and the `WASSAT_SHRINK` hook are retained so
that investigation does not have to start by rebuilding this scaffolding.
