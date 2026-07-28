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

## Result 1 — the motivating row did not move

`SCPC-500-19`, the instance whose 1,611-vs-69 propagations per conflict is the
entire reason this was built, **times out at 120s with the knob both off and
on**, twice each (`rc=124`, no `s` line). The rival solves it in 26s.

So the specific prediction failed. Trail reuse does not convert the row it was
aimed at, and the props/conflict gap there is not mainly restart
re-propagation — or is, but re-propagation is not what the remaining 4.6x is
made of. Whatever else this change is worth, it is not worth what this file
originally argued it would be worth.

## Result 2 — a real but two-sided effect elsewhere

Interleaved A/B, one binary, env columns, medians of 3, 32 rows:
**geomean 0.9551** — 10 rows faster >5%, 16 within 5%, 6 slower >5%.

| direction | rows |
|---|---|
| faster | `Break_triple_10_16` 0.31x, `2bitadd_10` 0.61x, `urqh2x5` 0.79x, `shuffling-1` 0.89x |
| slower | `ContextModel` 1.92x, `minand064` 1.32x, `qg3-09` 1.08x, `bmc-ibm-12` 1.07x |

`minand064`'s measured noise floor is 1.02x, so its 1.32x regression is real,
not churn. Two-sided with no static predictor is the exact shape `portfolio.w`
says makes something **a race axis rather than a default** — and `cfgs` slot 7
is free. That, not a global default, is the form this should take if it ships.

## Result 3 — global ON wins rows, but costs a solved row

Full reference suite, reuse forced on for every arm, against the same suite
with it off. 59 comparable rows, and the +2 clears the ±2 churn band only
because the four individual changes are legible:

| row | off | on | |
|---|---|---|---|
| `2bitadd_10` | TIE 5.48 | **WIN 2.44** | predicted by the A/B's 0.61x |
| `schooltt-5-7-12-2-4-1.4` | TIE 10.06 | **WIN 8.20** | |
| `ais8.mis-97` | LOSS 3.72 | TIE 2.61 | |
| `f1000` | LOSS 8.00 | **UNSOLVED@120s** | a solved row lost outright |

WIN 33 -> 35, LOSS 15 -> 13, UNSOLVED 8 -> 9. The parity gate also went from
`FAIL: 1` to `OK` — though `bmc-ibm-12` sits right on the 1.5x tolerance and
has flipped that gate before, so it is not evidence on its own.

**`f1000` is the finding.** Turning a row we solve in 8s into a timeout is a
worse outcome than the two wins are good, because unsolved rows are the
standing's binding constraint. It is also the precise failure a global default
cannot avoid and a race axis can: with the axis, arms 0 and 3 run without
reuse and should still solve `f1000`, while arms 1 and 2 deliver `2bitadd_10`
and `schooltt`. Whether that actually holds is the next measurement, and it is
the one that decides whether this ships at all.
