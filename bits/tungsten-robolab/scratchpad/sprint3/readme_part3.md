
**Arena** (`sprint_top_speed_v4_sprinter`, a new trial: the rules of `sprint_top_speed_v4_p95`, 12 perturbed standing starts 221-232, 30 s, `peak_speed_1s`, guard no fall,
`ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=sprinter ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation`, task `run_v4`; no existing trial was edited). Seeded with the P95 five-gear champion
replayed on this body (-1e9 on 12/12); challenged with the chain above (`arena.py eval ... --promote`): **wins, mean paired difference +6.7e8, p = 0.004, promoted**
(frozen `bin/champions/sprint_top_speed_v4_sprinter-20260929-210109`, controller `bin/challengers/run_gearx-s3a` = RunGearX). Not comparable with the P95 trials.

| per-start peak (m/s) | 221 | 222 | 223 | 224 | 225 | 226 | 227 | 228 | 229 | 230 | 231 | 232 | mean of survivors |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `run_gearx_v4_sprinter_g5a` | fall 13.0 s | 8.504 | 8.432 | 8.326 | 8.486 | fall 3.5 s | 8.361 | 8.334 | fall 11.5 s | fall 3.8 s | 8.349 | 8.461 | **8.407** (8/12) |

Falls on unseen standing starts (30 s, never trained on): seeds 141-180 **10/40** (five start falls at 3.5-3.9 s: 141, 148, 150, 164, 176; 155 at 22.9 s, 156 at 15.6, 157 at 11.5,
161 at 16.8, 162 at 12.1; survivors' peak 8.385, min 8.306, max 8.533); seeds 181-220 **9/40** (182 at 6.2 s, 184 at 27.1, 193 at 9.7, 196 at 4.7, 202 at 13.3, 209 at 28.8, 211 at 10.3, 214 at
10.8, 215 at 5.6; survivors' peak 8.423, min 8.300, max 8.569). 19 of 80 (24 %) fall, against 4 of 80 for round 2's P95 champion.

**The stride against the ideal** (entered chain at its steady state, seed 222, 26 stances of the last 12 s, `stridetab.py`; the ideal is the best stance budget of the sprinter's ceiling chains):

| | entered chain, 8.44 m/s | ideal at 8.5 m/s | ideal at 12.0 m/s (the ceiling) |
| --- | --- | --- | --- |
| contact / flight (s) | 0.093 / 0.133 | 0.116 / 0.256 | 0.066 / 0.154 |
| step (m) / rate (1/s) | 1.92 / 4.4 | 3.16 / 2.69 | 2.64 / 4.54 |
| thigh at touchdown / lift-off (rad, + ahead) | +0.56 / -0.42 | +0.46 / -0.52 | +0.38 / -0.73 |
| knee at touchdown (rad) | 0.69 (max 0.72) | 0.56 | 0.60 |
| ankle at touchdown (rad, - dorsiflexed) | 0.00 | -0.50 (the box floor) | -0.37 |
| mean / peak vertical force (BW) | 2.38 / 4.15 | 3.21 / 4.98 | 3.34 / 4.72 |
| trunk pitch touchdown -> lift-off (rad) | 0.086 -> 0.097 (rock +0.011) | excursion 0.11 (penalised above 0.1) | 0.05 |

It is P95's crouched high-cadence bounce at a higher speed: at 8.44 m/s the ideal stance has a 0.26 s flight and a 3.2 m step (the budget optimiser buys swing time with flight at low speed),
the runner flies half as long and steps 40 % shorter; it uses 4.15 of the ~5 BW peak force the ideal uses and 2.4 of its 3.2 BW mean, so the body's strength is largely unused. The trunk, the
problem of this body, rocks only 0.011 rad per stance in the steady gait.

**Long jump (reported, not started).** The runner does not exceed 10 m/s, so no jump work; its runway profile from a standing start (seed 222, `scratchpad/sprint3/runway.py`): 10 m at 5.1 s
(4.1 m/s), 20 m at 7.1 s (5.8), 30 m at 8.7 s (6.5), 40 m at 10.2 s (7.3), **44 m mark at 10.7 s: 7.50 m/s, mean 7.27 m/s over the last 5 m** (P95's runner: 6.6-6.9 m/s at 44 m). The
acceleration between 3 and 7 m/s is still the slow part (44 m to reach 7.5).

**What worked / what did not.** Worked: fixing the body before anything ran; the ceiling (12.36); the lean lever (0/12 -> 6/12 standing survivors with one number); a mean-aggregate ES from a
surviving crouched start (15/17 on its training snapshots). Did not: replaying either P95 champion (0/12 each); the extended gear on this body; drive, servo-gain and speed-plan changes; lowering
the lean in gears 2-4; earlier gear switches (they trade one fall for another); the start search (too slow under the machine load). **What would be needed for 10 m/s:** the start and gears 1-4
re-searched on this body from flying starts as round 1 did (they carry the start hazard and the 13 s falls), a trunk mechanism that scales with the stronger hips, an extended-stance gear searched
from the crouched 8.4 m/s gait (round 2's recipe; the extended gear of round 2 does not transfer), and the ~1.6 m/s between 8.4 and 10, which on P95 took two rounds for +0.4: the runner uses
68 % of the ceiling, and P95's best was 79 %.

Files: `playground/profiles/sprinter.json`; `playground/arena/trials.json` (+ `champions.json`, `history.jsonl` by `arena.py`); `params/run_gearx_v4_sprinter_{v1,g5a,g5a5}.txt` (the entered chain is `g5a`);
frozen binary `bin/challengers/run_gearx-s3a` (RunGearX, the same build as `run_gearx-a`); snapshot sets `playground/cache/sprint_touch_run_v4_sprj.npz` / `_sprk.npz` (git-ignored); ceiling data
`out/sprint_limits/probe_v4b_sprinter_*`; every tool (`snap3.py`, `val3.sh`, `rep.sh`, `qv.sh`, `scan3.sh`, `es3.sh`, `st.sh`, `stab.py`, `runway.py`), search log and run-by-run log in `scratchpad/sprint3/`,
outputs in `out/sprint3/`.
