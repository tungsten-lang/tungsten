### Sprinters on v4, round 2 (29 Sep): the extended stance held, and what it took

Round 1 ended at 7.907 m/s on P95 (75.7 % of the 10.45 pitch-free ideal-control ceiling) with four crouched gears, and named one untried thing: a gear whose stride is the
ideal's extended stance, searched from flying starts. **It works.** A fifth gear searched that way lifts the standing-start P95 champion to **8.276 +- 0.049 m/s (79.2 % of the
ceiling)**, +0.369 m/s on all 12 arena starts (paired p < 0.001, 12/12 survive; `params/run_gearx_v4_p95_x5a.txt`, controller `bin/challengers/run_gearx-a` = RunGearX, promoted in
`sprint_top_speed_v4_p95`). It is 79 % of a ceiling that is an upper bound built from separate capacity tests under idealised stabilisers, not a demonstrated gait: no muscle-only
stride at 10 m/s is known to exist, and this one is **not** 10 m/s (2.2 m/s short of the ceiling). Gears 1-4 are round 1's untouched; the entry says "five gears, v4 P95, standing
start". Log of every run with its command line: `scratchpad/sprint2/LOG.md`.

| per-start peak (m/s), seeds 221-232 | 221 | 222 | 223 | 224 | 225 | 226 | 227 | 228 | 229 | 230 | 231 | 232 | mean |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| four gears (previous champion) | 7.924 | 7.920 | 7.900 | 7.930 | 7.812 | 7.916 | 7.931 | 7.914 | 7.887 | 7.921 | 7.905 | 7.929 | 7.907 |
| five gears, extended-stance gear 5 (`x5a`) | 8.272 | 8.291 | 8.280 | 8.278 | 8.010 | 8.285 | 8.336 | 8.319 | 8.324 | 8.284 | 8.301 | 8.334 | 8.276 |

Falls (30 s, standing start, never trained on): seeds 141-180 **3/40** (153, 161, 175 at 19.6-25.2 s; survivors' peak 8.302, min 8.163), seeds 181-220 **1/40** (193 at 19.8 s; peak
8.303, min 8.240); the four-gear champion has 2 + 1 (its 153 and 175 are among the falls here). Flying starts (24 s, the champion's own steady-running snapshots at 7.6-8.0 m/s;
`playground/cache/sprint_touch_run_v4_p95j.npz` for training, `_p95k.npz`, 42 snapshots of 42 other runs, for validation): the extended gear survives 18/19 training starts and 36/40
unseen ones (peak 8.330, steady 8.253), the champion's own gear 4 restarted the same way 33/40 (peak 7.939, steady 7.891): the flying-entry transient (falls at 0.8-2.6 s) is
a property of the protocol, and the extended gear is not worse at it.

**The stride (mean over the steady stances, right foot).** The search did not reach the ideal; it reached its touchdown and its peak force:

| | crouched gear 4 (flying, 40 unseen) | extended, first search (f3c) | extended gear 5 (`x5a`, standing start seed 221) | ideal at 10.0 m/s (P95 v4) |
| --- | --- | --- | --- | --- |
| steady speed (m/s) | 7.891 | 7.756 | 8.234 | 10.0 |
| contact / flight (s) | 0.101 / 0.138 | 0.106 / 0.153 | 0.108 / 0.150 | 0.100 / 0.161 |
| step length (m) / step rate (1/s) | 1.91 / 4.13 | 2.02 / 3.86 | 2.14 / 3.85 | 2.61 / 3.83 |
| thigh at touchdown / lift-off (rad, + ahead) | +0.57 / -0.41 | +0.49 / -0.37 | +0.57 / -0.37 | +0.44 / -0.70 |
| knee at touchdown / stance maximum (rad) | 0.66 / 0.71 | 0.48 / 0.76 | 0.55 / 0.79 | 0.52 / 0.6 |
| ankle at touchdown (rad, - dorsiflexed) | 0.00 | | -0.21 | -0.44 |
| mean / peak vertical force (BW) | 2.37 / 4.12 | 2.42 / 4.37 | 2.38 / 4.84 (5.04 flying) | 2.61 / 5.06 |
| trunk pitch touchdown -> lift-off (rad) | 0.15 -> 0.17 (rock +0.016) | 0.24 -> 0.35 (+0.11) | 0.28 -> 0.37 (+0.09) | rock < 0.1 (penalised) |

So the extended gear lands with the ideal's knee, dorsiflexes the ankle half way to the ideal's, delivers the ideal's peak force in a 0.108 s contact and keeps the trunk inside the
ideal's 0.1 rad rock. What it still lacks against the ideal: 7 % of the flight, 17 % of the step length (the lift-off thigh is set by geometry, contact time x speed, so it follows
speed), 9 % of the mean force,.

**What the searches were and what worked.**

- *Lab first* (all in `scratchpad/sprint2/`: `lab.py` per-stance table from flying starts, `snap.py` snapshot sets, `mkgear.py` gear-K params files, `scan.py` one-at-a-time moves, `morph.py`
  / `line.py` interpolation and line search, `mtab.py` muscle-level view, `val.sh` / `standval.sh` validation). Round 1's extended-mode gait (`p1_snap1`, the ideal-like 6.6 m/s gear) run as gear 5 from the 7.9 m/s
  snapshots falls in 1.2-1.4 s on 8/8: its trunk pitches +0.28..+0.39 rad per stance (torso_kp at its 0.3 floor) and the chain of pitching and a mistimed landing ends in a forward fall.
  Interpolating only its leg-geometry tunables from the champion's gear 4 (`morph.py`, no re-tuning) lowers the speed monotonically: peak 7.93 / 7.83 / 7.75 / 7.69 / 7.65 / 7.50 / 7.49
  m/s for alpha 0 / .1 / .2 / .3 / .5 / .75 / 1 while the touchdown knee goes 0.65 -> 0.56, the contact 0.100 -> 0.122 s and the trunk rock +0.02 -> +0.21 rad, at a peak force that stays 4.0-4.2 BW.
  The alpha 0.5 point survives 18/19 training starts (steady 7.47) and is the start of the search.
- *The search that failed, and the one that worked.* round 1's `hsearch` scores a candidate by its WORST of 12-19 seeds and prunes on it. From a gait that survives every seed, that statistic
  moves by luck with every small mutation (the worst of 18 seeds), so sparse mutations of a good stride almost never pass: 5 generations, 0/24 offspring, on the alpha 0.5 start
  (`f2`, scratchpad log). **`hsearch.py --agg mean`** (new, opt-in; the default is unchanged) scores a candidate by the MEAN of its seeds' scores and stops it at its first fall (fall_pen 300),
  so small mutations move the score smoothly while robustness stays a hard rule. With it, 8 flying-start seeds x 16 s, (1+16)-ES on the 73 gear-5 twins, from the alpha 0.5 start and the
  ideal-stance objective 6 (`sprint_touch_v4x.py`: pace less 40 points per rad the touchdown knee misses 0.55, the touchdown thigh 0.5, the lift-off thigh stays ahead of -0.55, the stance knee
  passes 0.75): 7.47 -> 7.77 steady in ~3900 rollouts (`f3`, `f3b`, `f3c`; validated 37/40 unseen, more robust than the crouched gear's 33/40 but 0.13 m/s slower), then, with the same
  search continued for 2300 rollouts on RunGearX (`f4`), **8.26 steady**. The moves that carried it (single changes reverted in the lab, 8 seeds x 16 s, peak from 8.32): the landing ankle
  target `a_reach` -0.13 <- -0.30 (its box floor) costs **0.48 m/s** (3/8 fall), `k_land` 0.209 <- 0.136 costs 0.15 (3/8 fall), `psi_reach` 0.060 <- 0.016 costs 0.14, `toe_land` 0.07; the arm reflex
  (`k_arm_p` 0.66) and `lean_v` (0.018) found by the same search are NOT the cause: with either or both at 0 the gait runs 8.29-8.31 (1-2 falls in 8 instead of 0). The touchdown posture is the mechanism:
  a dorsiflexed ankle and a knee near 0.54 at contact, which is the ideal's touchdown.
