# Trail reuse on restart — hypothesis and decision rule

Written **before** the measurement, deliberately. Three conclusions in this
campaign had to be retracted because the criterion was chosen after seeing the
numbers; this file fixes the criterion first.

## The lever

A restart throws the whole trail away, and the heuristic then rebuilds most of
it: every decision still more active than the best unassigned variable gets
re-made and re-propagated. Van der Tak, Ramos and Heule (JSAT 2011) keep that
prefix instead.

The reason to try it here is measured, not general. On the rows we lose,
propagations per conflict are wildly out of line with the rival at identical
per-operation speed:

| row | wassat props/conflict | CaDiCaL |
|---|---:|---:|
| `SCPC-500-19` | 1,611 | 69 |

That 23x is the same order as the unexplained part of the conflicts/second gap
on dense formulas (`DivS_568_11`: 171 c/s against 9,397). Re-propagating a
discarded trail is the mechanism that produces exactly this signature —
propagation work that buys no conflicts. `wassat_propagate` itself is already
tuned (split binary lists, lit-index blockers, contiguous backward-scanned
watch blocks), so a 55x throughput gap is not plausibly a constant factor
inside it.

## What was built

- `wassat_heap_peek_act` / `wassat_vmtf_peek_stamp` — the value the
  corresponding `pick` would return, without consuming it. Both perform only
  the skip-assigned work `pick` already does, so peeking cannot change which
  variable `pick` then returns.
- `reuse_trail_target` asks **whichever heuristic is live** — EVSIDS activity
  in stable mode or when VMTF is off, VMTF stamps otherwise. Comparing trail
  decisions against activity while VMTF is driving would rank them by a key
  that is not deciding anything, which would have made the whole change a
  no-op-with-overhead on the focused arms where most restarts happen.
- A due rephase still takes a full restart: it rewrites every saved phase and
  wants the clean slate.
- `WASSAT_REUSE_TRAIL=1`, default **off** until this file has numbers.

## Decision rule, fixed in advance

Judged on the reference suite by **row win/loss status**, not geomean — a
geomean can move a lot on long rows whose status never changes, and the noise
floors say so:

- **Land** if rows-won increases by **more than 2**, or holds while several
  rows move the same way. Trail reuse should help many rows a little, not one
  row hugely.
- **Bank as a negative** if rows-won drops by more than 2. Record the
  mechanism, do not re-litigate on geomean.

The ±2 band is measured, not guessed. The SLS-memory-ceiling suite flipped two
rows against its baseline — `2bitadd_10` WIN→TIE and `ibm-2004-03-k70`
WIN→LOSS — on rows whose SLS arenas are 0.2 MB and 32.1 MB, i.e. far below the
256 MB ceiling, so the code path for both was byte-identical across the two
runs. **An inert change produced two status flips across 37 rows.** Any
rows-won difference of 1 or 2 is therefore churn, and reading one as a result
is the same error that has already cost this campaign three retractions.
- Ignore any single-row result on `Carry_Bits_Fast_12` (22.24x noise floor),
  `em_7_3_6_fbc` (7.48x) or `bench_1614` (2.40x). A change that looks decided
  by one of those alone is not decided.
- If off and on produce *identical* timings the mechanism never fired — treat
  that as a bug in the wiring, not a null result, and check the heuristic
  selection first.

Correctness is not a judgement call: `ab.py` checks every `s` line against the
published expectation and across columns, and a disagreement is fatal
regardless of speed.
