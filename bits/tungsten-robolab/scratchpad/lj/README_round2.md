### Long jump, round 2 (28-29 Sep): the ideal take-off, a landing that stops rolling over, and what a fresh start does

The tables above are round 1; the arena board is authoritative. Round 2 replaced the chunk take-off with the
**ideal-control take-off** of each body's own approach state, added a learned **landing program**, and then spent a
night finding out why the robust means stayed far below the one-start jumps.

**The method** (`playground/long_jump_limits.py`; the runner's own approach state in, jump out):

1. `capture` a real rollout at the start of the plant flight (`--from pen`: at the penultimate touchdown): position,
   velocities, muscle activations and tendon fibre states, exactly.
2. `optimise`: all 32 muscles follow open-loop excitations from that state to the take-off; sep-CMA maximises the ballistic
   distance from the board. That is the **ideal-control ceiling** of the body from that approach: 4.93 m for the 7.02 m/s
   p95 runner (vx 6.27, vz 2.89 m/s, contact 0.112 s), 4.25 m for the 6.56 m/s elite2 runner.
3. `distil` the ideal into quintic contraction knots plus drive knots every 30 ms, latched on the plant touchdown (`j_ik`, `ik_*`;
   `ik_from 1` starts the program at the penultimate touchdown) and re-optimise it over captured perturbed approaches
   (`robust`).
4. `handover` the program on many approaches, then `landing`: a landing program (`j_il`, `il_*`: excitation knots on their own clock,
   latched on the first sand contact) learned by sep-CMA on the hand-over states. **ORACLE-class**: the landing table is an
   open-loop excitation program, and so is the p95 take-off (reflex gain 0.03); the residuals added this round are sensed,
   bounded and zero-initialised.

**Arena** (all promotions paired; `long_jump_p95_robust32`, `_robust96` and `long_jump_elite2_robust32` are new trials on starts
that no search or practice ever used, seeded with the champion they replaced):

| trial | body | before | champion now | verdict |
| --- | --- | --- | --- | --- |
| `long_jump_p95` (1 start) | p95 | 4.895 m | **5.100 m** (feet mark, 0.35 m beyond the ballistic 4.75) | promoted twice (4.958, 5.100): a landing program learned for this start; overfit to it by construction |
| `long_jump_p95_robust` (16) | p95 | 3.924 m | **4.631 m**, 16/16 legal (4.30-4.79) | +0.706, p < 0.001 |
| `long_jump_p95_robust32` (new, 32 fresh) | p95 | 3.445 m | **4.546 m**, 31/32 legal | +1.10, p < 0.001 |
| `long_jump_p95_robust96` (new, 96 fresh) | p95 | 4.084 m (the 16-start champion, pn1) | **4.317 m**, 89/96 legal (median of the legal 4.68) | +0.234, p = 0.003 (pn2: swing-foot lag feedback) |
| `long_jump_elite2_robust32` (new, 32 fresh) | elite2 | 3.011 m | **3.592 m**, 31/32 legal | +0.58, p = 0.001 (run-up steering 0.3, check mark +0.04 m) |
| `long_jump_elite2_robust` (16) | elite2 | 3.936 m | 3.936 m (kept) | the steered variant scores 3.68 there and does not beat it |

`long_jump_p95_robust` and `_robust32` hold pn1 (`params/long_jump_p95_pn1.txt`), `_robust96` holds pn2
(`params/long_jump_p95_pn2.txt`; on the arena's 16 starts pn2 scores 4.38 with one somersault, so pn1 keeps that trial).
Controller: `bin/challengers/long_jump_run-b20p` / `-b20q` (frozen copies of the skill build b20). One-start jump:
`params/long_jump_p95_ik10.txt`, `-b20s`.

**A champion's 16 fixed starts hide the failure rate.** The arena scores a champion on the same 16 perturbed starts forever, and
16 of 16 can be legal by luck: the p95 champion of 28 Sep scored 3.92 m there but 3.27 m on 96 fresh starts (90 legal: 2 stumbled in
the run-up, 2 somersaulted, 1 fouled, 1 touched the runway after landing) and 3.44 m on 32 others; the elite2 champion scored 3.94
there and 3.01 on 32 fresh (on 80 starts, 64 fresh and the 16, 5 landed short and 6 fouled). Judge a controller on fresh starts.

**Why the robust means were far below the one-start jumps** (112 fresh starts with the p95 penultimate-touchdown program; the
harness `handover` reproduces every class on the captured states):

- **The landing rolls over: a timing problem, not a rotation-control problem.** The landing program's knots run on a clock started at
  the hand-over; the sand only re-syncs it. A flight 0.09 m lower or 0.2 m/s slower than the ones it was learned on lands 30-50 ms
  earlier than the program expects. The legs are still hanging when the toes touch the sand, the COM 1.0 m up and 0.1-0.2 m behind the toes,
  and the body vaults over its feet (Ly 0 to 75-110 kg m2/s in 0.1 s, torso pitch through pi). The fix is a **ballistic-time clock**
  (`il_tg`, `il_zl`): before the sand the program time is tg minus the COM's ballistic time to fall to zl (a flight is ballistic whatever the limbs
  do), so the legs' tuck and reach are locked to the predicted landing. On the 32 hand-overs of the landing search the 3 roll-overs went to 0
  for tg 0.58-0.66 (`playground/long_jump_diag.py --tgs`). The program was learned on those 32 hand-overs only and overfits the clock:
  tg 0.70 makes 48 of 112 fresh starts somersault. On the average body's hand-overs the clock changes nothing (4 of 23 roll over
  for another reason).
- **A scuffing swing foot** (4 of 96 fresh starts). The plant-side toe clears the runway by 12 mm in a healthy start (site height 0.032 m; the ground
  contact is at 0.019 m) and drags for 0.1-0.15 s in a bad one. The plant-touchdown latch (force above 0.05 body weights) fires on the scuff at
  0.10 s, 0.14 s before the ideal touchdown; the program clock jumps ahead and runs the stance in the air. `ik_fmin 1.5` (the latch needs 1.5
  body weights; a real plant reads 4 on its first tick, scuffs 0.2-0.94) removes the class.
- **Weak take-offs** (vz 1.6-2.4 m/s, typical 2.7-3.0): a late stride phase, the swing foot 0.5-0.7 m behind the COM and the trunk 0.15-0.2 rad
  forward at the penultimate touchdown (0.08 +- 0.03 typical; vz = 3.05 - 4.0 x pitch in the harness), about 10% of starts. The flight is short
  (0.4-0.6 s) and lands with the legs hanging. A one-sided torso-pitch feedback on the free leg's hamstrings lifts vz (vz < 2.4: 10 to 1 of
  161 mined starts) but turns those starts into forward-rotating take-offs (L +2 to +23 kg m2/s instead of -5.8 +- 2) that no landing recovers:
  every somersault of the 112 has L above 1.7 or a take-off pitch of 0.24 rad or more. What helped is a **swing-foot lag feedback** (`ik_fx*`,
  `ik_kf_*`, found by greedy forward selection on 119 mined approaches under penalties L <= -1.5, pitch <= 0.25, vz >= 2.55): 87 legal of 96 to
  92 on 7001-7096, 84 to 89 on 9033-9128.
- **Fouls** (3 of 112, 5-49 mm): the take-off foot's front lands 0.06 +- 0.05 m behind the line. A check mark 0.05 m longer (task
  `long_jump_p95g`; `j_board_shift` and `ik_gap0` move with the board, so the run-up is identical) removes them for 0.05 m.
- **The runner's own stumbles** (2-3%): a fall in the acceleration phase (steps of 0.9, 0.9, 0.7 m at 3.5 s); not the jump's.
- **Elite2 has a different problem**: its run-up cannot be steered (`j_st_w 1.5` makes it fall), so the take-off foot lands 0.2-0.5 m behind
  the line or well over it. A gentle steering (`j_st_w 0.3`; 0.6 falls) plus a check mark 0.04 m longer (`long_jump_elite2b`) lifts the fresh-start
  mean by 0.3-0.6 m; 0.08 and 0.12 m of check mark were worse.

Roll-over rates on fresh starts (somersaults per start): the 28 Sep champion 2/96, pn1 6/96 + 9/96 + 1/48, pn2 2/96 + 5/96 + 2/48. The pn family
jumps 4.3-4.6 m and rolls over on 4-7% of fresh starts; the old chunk landing of the 28 Sep champion jumped 3.3-3.4 m and rolled over on 2%. A
short-flight landing that survives the weak take-offs is still open: a hand-set time-to-strike reflex (`il_ctau`, `il_kc_*`) rescued 2 of
5 weak hand-overs, a learned one 13 to 8 of the 56 hardest hand-overs (5 to 4 of 75 held out).

**Against humans** (men; sources and levels as in round 1; D marks a value derived here):

| level | distance | our body |
| --- | --- | --- |
| untrained woman | 3.57 +- 0.54 m | elite2: 3.59 m fresh mean, best start 4.1 |
| untrained man | 4.95 +- 0.55 m | p95: **5.10 m** best (103%), 4.63 m robust on the arena's 16 starts, 4.32-4.55 m on fresh starts (87-92%; the 13th-28th percentile of untrained men) |
| speed-matched elite jumper (an 8.30 m jumper from 6.1-6.6 m/s run-ups; Bridgett & Linthorne 2006) | 4.33-4.77 m | p95 at 6.7 m/s: 4.6 m robust, 5.1 m best: at or above |
| high-school state qualifying | 6.07-6.65 m from 8.9 m/s | not reached |
| NCAA D1 finals median, world record | 7.56-7.75 m, 8.95 m | not reached |

The p95 body's take-off (vz 3.0 m/s, contact 0.13 s) equals that of Willwacher et al.'s 7.27 m jumpers (vz 3.01 m/s); what it lacks is speed: 6.7 m/s at
the board (the runner tops out at 6.9 m/s at 37-45 m and 7.0 m/s at 55 m: a longer run-up adds 0.06 m/s). The fit to the best jump,
D = 0.88 v t_air(vz) + 0.52 m, with v the run-up speed at the board (a projection, not a measurement), needs for vz 3.0 (the model's own
take-off) / 3.3 m/s (Bridgett & Linthorne's speed-matched jumper): 4.95 m at 6.5 / 6.1 m/s, 5.5 m at 7.3 / 6.9 m/s, 6.07 m at 8.2 / 7.7 m/s,
6.65 m at 9.0 / 8.4 m/s, 7.56 m at 10.3 / 9.7 m/s, 8.95 m at 12.4 / 11.6 m/s. So the next level (robustly above the untrained man's mean, 5.5 m) needs a 7.3 m/s run-up at the
board, high-school state level 8.2-9.0 m/s. The sprint work's v4 P95 body has a 10.45 m/s ideal-control ceiling; no v4 P95 or elite2 runner is
promoted yet, so the v4 long-jump family (`ROBOLAB_CALIB=v4`) is not built.

**Practice and the harness.** `long_jump_diag.py` (a landing tick by tick; `--tgs` scans the clock), `long_jump_mine.py` (approach
features against outcomes over captured starts) and `long_jump_eval.py` (full rollouts, one line per start, for starts that are not the arena's).
The harness is not exact: take-off vx and vz differ from the full rollout by 0.2-0.4 m/s on some starts for the base program too, and a
feedback selected in it screens candidates that full rollouts must decide. A pitfall found on the way: the take-off tables are by muscle role
(T_ = the plant leg's side), and 4 of 161 mined starts take off with the left foot; a search that reads the tables with the first capture's side
mirrors them wrongly for those starts (they appeared as failed take-offs). `greedyfb` builds tables and gains per capture side.

```sh
.venv/bin/python playground/long_jump_limits.py capture long_jump_p95e --params out/long_jump_run/p95pn_approach.txt \
  --controller bin/challengers/long_jump_run-b20 --seeds 8001,8002 --name p95mn --from pen
.venv/bin/python playground/long_jump_limits.py handover out/long_jump_run/p95pn_latch.txt --captures p95mn_s8001,p95mn_s8002 --name h
.venv/bin/python playground/long_jump_mine.py p95mn h out/long_jump_limits/land_p95pn3.txt --tg 0.61
.venv/bin/python playground/long_jump_limits.py greedyfb out/long_jump_run/p95pn_ik.txt --prefix p95mn --channels kp,kf \
  --lmax=-1.5 --lw 0.3 --pmax 0.25 --pw 3 --fmin-on --delta 0.05 --out out/long_jump_run/fb.txt
.venv/bin/python playground/long_jump_eval.py long_jump_p95_robust96 --params params/long_jump_p95_pn2.txt \
  --controller bin/challengers/long_jump_run-b20q --task long_jump_p95g
.venv/bin/python playground/long_jump_run_render.py long_jump_p95e --params params/long_jump_p95_ik10.txt \
  --controller bin/challengers/long_jump_run-b20s --out out/long_jump_v5_p95_5100
```

Videos: `out/long_jump_v5_p95_5100.mp4` (the 5.10 m jump: take-off, flight and landing at 1/4 speed; the jumper tumbles in the pit but no
rule is broken; feet mark), `out/long_jump_v5_p95_4958.*` (the intermediate 4.958 m) and `out/long_jump_v5_p95.*` (the 4.895 m of round 2's first
champion); each has a `_sheet.png` and `_metrics.json`. The run's log is `out/long_jump_run/LOG.md`.
