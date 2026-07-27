# Root-satisfied clause detach: measured, not landed (third time)

**Measured:** 2026-07-26. **Outcome:** net loss on breadth. Not in the tree.

This records the numbers so the technique does not have to be re-derived a
fourth time. It has now been implemented and reverted three times; twice
before this, the second of those explicitly flagged at the time as optimising
the scoreboard rather than the solver.

## What was implemented

A clause containing a literal true at decision level zero can never propagate
and never conflict, but it still costs a watch-list slot, a blocker load, and
on a blocker miss a walk of its body, on every visit to either watched
literal. The implementation was:

- `Wassat#detach_root_satisfied` — one pass over the clause database marking
  root-satisfied clauses `alive = 0`, which drops them from the watch rebuild
  and, in `PROOF_NONE`, compacts them out of the arena entirely.
- `wassat_detach_root_sat` — the scan itself, native, inlining the
  variable-indexed value lookup.
- Called from the top of `reduce_db`, which always runs from a level-zero
  trail, before the LBD histogram and the compaction.
- Gated on `@raw_flat && @proof_mode == WASSAT_PROOF_NONE`, the same gate
  `simplify_raw_mode` uses: in proof mode a detached clause can still be cited
  by a hint. Gated additionally on the root trail having *grown* since the last
  sweep, since a clause can only become root-satisfied when a literal is newly
  fixed at level zero.
- Root unit clauses skipped: they pin the root trail.

Nothing about that is wrong, and the verdicts were correct everywhere.

## Why it does not pay, and why single rows cannot tell you

**The effect is dominated by trajectory reroll, not by the propagation
saving.** Removing clauses changes watch-list order, which changes which
conflict propagation finds first, which reshapes the entire search. Measured
deterministically (`WASSAT_ARMS=1 WASSAT_PRE_ARMS=0`, so there is no race
nondeterminism at all):

| instance | conflicts without | with | wall without | with |
|---|---|---|---|---|
| bmc-ibm-10 | 1,733 | 1,733 | 0.14s | 0.14s |
| bmc-ibm-12 | 7,162 | 7,733 | 0.56s | 0.58s |
| smulo016 | 715,215 | 1,118,076 | 33.79s | 65.74s |

smulo016 doubling is not the technique being bad at bitvector kernels — it is
one unlucky reroll of a trajectory the campaign has repeatedly measured as
swinging 2–15x on configuration alone. A reading like that, in either
direction, carries almost no information about the technique. This is exactly
how the `bmc-ibm-10` row justified landing it twice before.

## The honest cross-tier number

Interleaved A/B against the identical binary without the change, over
reference.py's own parity and survey rows, three reps, min-of-3, verdicts
checked against the published expectations on every run and cross-checked
between binaries:

```
detach vs no-detach:  geomean 1.0215 over 29 rows
                      4 faster >5%, 4 slower >5%, 21 within 5%
    worst: 3bitadd_31 1.63x, ContextModel 1.51x, qwh.35.405 1.18x
    best : bmc-ibm-12 0.82x, ibm-2004-03-k70 0.89x, mrpp_6x6#14_10 0.90x
```

Four rows better, four rows worse, everything else inside the noise band, and
the geomean 2% on the wrong side. That is a null with a slightly negative
tilt — not a trade worth stating, just an absence.

Nine rows exceeded the 25s budget for every binary and are excluded rather
than counted as ties: 2bitadd_10, f1000, urqh2x5, SAT_dat.k10, mp1-ps_5000,
gensys-icl003, fla-350-6, Urquhart-s3-b3, urquhart3_25bis.

## If anyone picks this up a fourth time

The propagation saving is real but small, and it is being swamped. To measure
the *saving* rather than the reroll you would have to hold the trajectory
fixed — count watch visits and propagations per conflict rather than wall
time, and only then decide whether the saving is large enough to be worth a
randomised trajectory. Do not measure it on one row, and do not measure it on
`bmc-ibm-10`.
