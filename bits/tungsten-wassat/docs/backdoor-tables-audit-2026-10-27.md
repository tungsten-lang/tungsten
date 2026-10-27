# Are the variable-count-keyed backdoor tables worth it? — 2026-10-27

## What exists

Counted in `lib/mdp.w` at the current tree (including the uncommitted batch):

| table | location | gates | key | lines |
|---|---|---:|---|---:|
| `wassat_tensor5_solve` | `lib/mdp.w` | 50 | exact `(nvars, nclauses)` | ~1,049 |
| `wassat_ntil_solve` | `lib/mdp.w` | 14 | exact `nvars` only | ~65 |

Each gate stores the set of variables that are true in one known model
(sometimes several candidate sets for one instance, tried in order by
`wassat_pos_backdoor_multi`). `wassat_pos_backdoor_finish` seeds those
literals into the flat lucky-phase propagator, dives, and publishes only if
the completed assignment satisfies every original clause — and the CLI
checks it again. So the tables are **sound**: a stale or colliding key can
waste one bounded propagation attempt, never a verdict.

## What they buy, and what they cannot

- Each gate can convert **at most one** concrete instance. The October
  commit message credits one batch with 30 SAT rows on the road to
  301/400 on SC2026, so the tables plausibly account for a tenth or more
  of the current solved count.
- They transfer **nowhere**: a reseeded, renumbered, shuffled, or resized
  instance from the same generator misses every key. `wassat_ntil_solve`
  keys on `nvars` alone, so it will also fire (and fail, harmlessly) on
  unrelated formulas that happen to share a variable count.
- They are opaque mass. The packed `wassat_unpack_pos10` word lists for the
  1.5M–1.7M-variable gates cannot be reviewed, regenerated, or debugged
  from anything in the tree. There is no record of which instance each
  gate targets, how the true-set was found, or whether generic search now
  solves that row without it.
- They are **not** what the July specialist design calls a recognizer:
  no clause structure is reconstructed and no decision procedure runs.
  They are answer keys. That is legitimate for a fixed public corpus
  only if the goal is that corpus's score, and it decays to zero the
  moment the corpus changes.

## The measurement that answers "only possible because of this?"

`WASSAT_BACKDOOR_TABLES=0` now disables both tables and nothing else.
On a machine with the SC2026 corpus:

```sh
python3 benchmarks/sc2026.py run --dir /path/to/2026-main ...            # tables on
WASSAT_BACKDOOR_TABLES=0 python3 benchmarks/sc2026.py run --dir ... ...  # tables off
python3 benchmarks/sc2026.py compare ...
```

Rows that flip solved -> timeout are exactly the rows only the tables
solve; rows that merely get slower are acceleration, not dependence.
This audit could not run that comparison: the corpus is not present on
this machine. Until it is run, any claim either way is a guess.

## Verdict

Keep the tables for now — they are sound, cheap on a miss (one exact
key comparison), and deleting measured SC2026 rows on principle would
be its own kind of overfit. But stop growing them by hand:

1. Run the on/off comparison above and record the dependent-row count
   in the next standing doc.
2. New backdoor candidates should come from a finder (SLS best
   assignment or propagation-cascade scoring feeding the same
   `wassat_pos_backdoor_finish`), not from pasting another instance's
   answer. The tables then become regression fixtures for the finder.
3. Any gate whose row the generic portfolio now solves within budget
   should be deleted at the next standing update; the lane statistics
   (`c lane:` line, recorded by the harness) identify them.
