
**Arena** (`sprint_top_speed_v4_beyond`, a new trial: the rules of `sprint_top_speed_v4_p95`, 12 perturbed standing starts 221-232, 30 s, `peak_speed_1s`, guard no fall, `ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=beyond ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation`,
task `run_v4`; no existing trial was edited). Seeded with round 3's sprinter chain replayed on this body (-1e9 on 12/12); challenged with chain C (`arena.py eval ... --promote`): **wins, mean paired difference +7.5e8, p = 0.002, promoted** (frozen
`bin/champions/sprint_top_speed_v4_beyond-20260929-233725`, controller `bin/challengers/run_gearx-s4a` = RunGearX, params `params/run_gearx_v4_beyond_c.txt`). BEYOND-HUMAN: not comparable with any other trial.

| per-start peak (m/s) | 221 | 222 | 223 | 224 | 225 | 226 | 227 | 228 | 229 | 230 | 231 | 232 | survivors' mean |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| chain C (promoted) | 10.159 | 10.105 | 10.185 | 10.178 | fall | 10.152 | fall | 10.153 | 10.146 | 10.170 | fall | 10.103 | **10.150 (9/12)** |
| chain D (`..._d.txt`, not promoted: p = 0.267 against C) | 10.164 | fall 23.9 s | 10.195 | 10.173 | 10.174 | 10.176 | fall 13.0 s | 10.174 | 10.127 | 10.171 | fall 6.6 s | 10.178 | 10.170 (9/12) |

**Result: above 10 m/s on every survivor (10.10-10.20 m/s), but NOT fall-free**: 9 of 12 arena starts survive 30 s, and 20/80 (C) and 14/80 (D) of the unseen standing starts fall, against the target of at most 10 % on each set. Chain D is chain C with two numbers of gear 3 changed
(`g3_k_swh` 1.87 -> 3.0, the swing-hip trunk synergy, and `g3_lean` -0.151 -> -0.10; selected on the 141-180 set, which is why it looks better there).

Falls on unseen standing starts (30 s, never trained on; type: START = gear 1 before 8 s, HANDOVER = the gear-1 -> gear-2 switch at 7.6 m/s, TOP = gear 2/3 above 9.4 m/s):

| chain | seeds 141-180 | seeds 181-220 |
| --- | --- | --- |
| C (entered) | **9/40**: 155 (6.1 s, START), 171 (11.8), 173 (11.1) HANDOVER, 142 (28.8), 160 (23.6), 163 (26.8), 175 (23.9), 176 (24.7), 180 (26.6) TOP; survivors' peak 10.134 (min 9.944, max 10.227) | **11/40**: 216 (6.1 START), 182 (10.1), 196 (12.6), 218 (12.5) HANDOVER, 181 (24.8), 185 (22.6), 194 (23.5), 198 (24.5), 202 (24.1), 212 (26.5), 217 (29.2) TOP; survivors' peak 10.136 (min 9.877, max 10.197) |
| D | **4/40**: 155 (START), 171, 173 (HANDOVER), 149 (27.1 TOP); survivors' peak 10.172 (10.107-10.223) | **10/40**: 216 (START), 182, 196, 218 (HANDOVER), 191 (21.8), 201 (24.9), 202 (28.4), 203 (18.9), 206 (29.4), 212 (26.9) TOP; survivors' peak 10.171 (10.127-10.234) |

By type over the 80 starts: C 2 start + 5 handover + 13 top; D 2 + 5 + 7. Every fall is one of three chaotic hazards, each 3-16 % per run; the top falls come 10-15 s after the gait reached ~10 m/s (a slow trunk drift: pitch at touchdown 0.13-0.16 in the tail of the
falling runs against 0.05 in the survivors).

**The stride against the ideal** (chain D at its steady state, seed 224, 15 stances of the last 30 % of a 24 s run, `scratchpad/sprint_knot/stridetab.py`; the ideal is the best stance budget of the beyond body's ceiling chain, `probe_v4b_beyondc2`):

| | chain D, 10.05 m/s | ideal at 10 m/s | ideal at 16 m/s (the ceiling) |
| --- | --- | --- | --- |
| contact / flight (s) | 0.080 / 0.149 | 0.092 / 0.262 | 0.061 / 0.157 |
| step (m) / rate (1/s) | 2.31 / 4.36 | 3.54 / 2.83 | 3.49 / 4.59 |
| mean / peak vertical force (BW) | 2.79 / 4.81 | 3.84 / 5.18 | 3.57 / 5.0 |
| thigh at touchdown / lift-off (rad) | +0.66 / -0.46 | +0.65 / -0.55 | +0.93 / -0.28 |
| trunk pitch at touchdown (rad) | 0.055 (rock over the stance -0.01) | free (excursion 0.07) | free (excursion 0.11) |

It is the crouched high-cadence bounce of the P95 and sprinter runners (4.2-4.4 steps/s) run at a higher speed: its cadence and flight time are the ideal's at 16 m/s, and the speed comes from the step growing from 1.9 m (8.4 m/s) to 2.3 m; the peak force
(4.8 BW) is the ideal's, so the strength of this body is not what limits it.

**Runway profile of chain D from a standing start** (`scratchpad/sprint4/runway.py`, seed 224; seed 222 in brackets): 10 m at 4.08 s (4.97 m/s), 20 m at 5.84 s (6.32), 30 m at 7.33 s (7.14), 40 m at 8.69 s (7.63), **44 m mark at 9.21 s: 7.74 m/s, mean 7.62 m/s over the last 5 m** (seed 222: 7.19 / 7.40),
50 m at 9.98 s (8.25), 60 m at 11.18 s (8.61), 80 m at 13.46 s (9.14), 100 m at 15.62 s (9.51), 120 m at 17.69 s (9.83): 10 m/s only after about 140 m (about 19 s). Round 3's sprinter chain: 7.50 / 7.27 at 10.7 s; round 2's P95 runner 6.6-6.9. A long jump from a 44 m run-up would still take off at about 7.4-7.7 m/s, 2.5 m/s below this chain's top speed: the
3-7 m/s acceleration (30 m to reach 7.1 m/s) is the slow part, so a faster start gear is the next thing the jump needs. Its gear 1 has a ~6 % start hazard (gear-1 falls at 5-7 s), and the searches on 12-14 seeds did not reduce it on unseen seeds, so the acceleration gear has to be searched on 40+ seeds
first. **The long jump was not started.**

**What worked / what did not.** Worked: choosing the body by a written rule and two measured ceilings (13.51, 16.32) before any runner ran; **re-searching the runner from the start on the new body, gear by gear from flying (and edge-of-instability) snapshots with the mean-of-seeds search**: one searched gear 1 reaches 8.4 m/s
(the round-3 chain's speed) in 10 minutes, gear 2 9.87 m/s in 16, and the three-gear chain passes 10 m/s on every survivor; finding that the speed-plan caps (`v_cap`, `v_top`) bound the top gear at 10.0 m/s; `lean_acc` 0 halving the start hazard (13 % -> 6 %, 136 seeds); the gear-3
trunk synergy `k_swh` 3.0 with `lean` -0.10 on the set it was selected on (141-180, 30 s: 9/40 -> 4/40 falls at 10.17 m/s; on 181-220 it only moved 11/40 -> 10/40, so most of that gain did not transfer). Did not: replaying round 3's sprinter chain (0/12); any single lever on the start (12/12 fall); a start / handover search on 12-14 seeds (fixes those seeds, not the hazard: 9/56 unseen starts still fall);
a 40-seed `mean` search (stopped before its first generation ended: 16 candidates x 40 seeds is ~5 min per generation); lowering the handover speed (5.0-6.5 m/s: gear 2 does not take over below ~7 m/s) or moving it in 7.2-8.0 (the handover hazard stays 6-8 %); trading speed for stability with `lean` (-0.25: 8/40 falls at 9.64 m/s) or `torso_kp` / `torso_kd` / `hip_lead` (worse). **What would be needed for a
fall-free 10 m/s:** the three hazards below 3 % each: a start / acceleration gear searched on 40+ seeds, a handover trained on the chain's own switch (standing-start rollouts), and a top gear searched with 25-30 s horizons on many seeds (or a speed-dependent trunk set point: `lean_v` < 0, which `RunGearX` ignores today).
About 2 h 40 min of wall clock, of which ~50 min were lost to machine stalls (a 26 min hole at 21:23-21:49, 20 min at 23:12-23:33 and several 5 min ones; load 20-28 from other agents).

Files: `playground/profiles/beyond.json` (rule, ladder, decision, ceilings); `playground/arena/trials.json` (+ `champions.json`, `history.jsonl` by `arena.py`); `playground/hsearch.py` (opt-in `--agg meanall`, `HSEARCH_UB`); `params/run_gearx_v4_beyond_{a,b,c,d}.txt` (the entered chain is `c`; `d` is the better one on the unseen sets);
frozen binaries `bin/challengers/run_gearx-s4a` / `-s4b` (RunGearX, the same build as `run_gearx-a`: `lib/robolab/skills/run_gearx.w` was NOT edited, so the P95 champion still replays 8.272 8.291 8.28 8.278 8.01 8.285 8.336 8.319 8.324 8.284 8.301 8.334 and round 3's sprinter chain 8/12 at 8.407 with it: both re-checked);
snapshot sets `playground/cache/sprint_touch_run_v4_{bj,bk,bh,bm,ct,cv,cm}.npz` (git-ignored); ceiling data `out/sprint_limits/probe_v4b_beyondc{1,2}_s1_*`; every tool (`freeze_twins.py`, `mkchain3.py`, `nextgear.sh`, `stb.sh`, `stc.sh`, `esk.sh`, `rep.sh`, `qv.sh`, `qbatch.sh`, `val.sh`, `valchains.sh`, `runway.py`, `stab.py`, `snap3.py`), every search
log (`sa`, `ga`, `gb`, `gc`, `gd`, `ge`, `sb`, `sb2`, `sc`) and the run-by-run log in `scratchpad/sprint4/`, outputs in `out/sprint4/`.
