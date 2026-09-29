**The trunk, which round 1 named the blocker.** Measured, it is not what stopped the extended stance, and no trunk mechanism was needed (all opt-in in `RunGearXSkill`,
`lib/robolab/skills/run_gearx.w`, `bin/robolab_run_gearx`; every tunable defaults to 0 and the P95 champion's 12 arena starts replay to the digit):

- *Where the trunk goes.* The crouched champion's trunk rocks +0.016 rad over a stance. p1_snap1's extended stride rocks +0.36, and a pre-activated one (vasti drive `drv_pre` 0.7 on the alpha 0.5 gear, which
  produces the ideal's stance in the first strides: contact 0.097 s, flight 0.160, step 2.04 m, touchdown knee 0.47, mean / peak force 2.6 / 4.0 BW) pitches +0.11..+0.30 rad per stance and a further +0.3
  in flight, cumulatively, and falls forward in 1.3-1.6 s (drv_pre 0.4 / 0.7 / 1.0: 4/8, 5/8, 7/8 falls). The searched extended gear rocks +0.09 (0.28 -> 0.37): the ideal's 0.1 rad.
- *What a perfect trunk is worth.* `sprint_touch_v4x` opt-in env `ROBOLAB_TRUNK_STAB=kp,kd,limit` applies a DIAGNOSTIC ideal external torque to the torso body (not an actuator the body has). On the crouched
  gear it is worth +0.10 m/s (300 N m, pitch held to its own slow mean) to +0.17 (100 N m, lean held at 0.3 rad; 200 N m 8.08; 400 N m all 4 fall); on the alpha 0.5 extended gear +0.08 (rock +0.15 -> +0.014),
  and the pre-activated extended gear still falls with the trunk held (it runs ~10 strides at the ideal's stance and then its touchdown thigh wanders 0.44..0.90 rad and the knee collapses to 1.3-1.8).
  On the searched extended gear the torque makes it fall 8/8 at 300, 150 and 80 N m: that orbit uses its 0.11 rad rocking.
- *Real mechanisms* (4 flying seeds, 12 s, on the alpha 0.5 gear): arm counter-rotation `k_arm_p` 8 cuts the stance rock from +0.15 to +0.08..+0.12 (30-50 %) and moves the speed by nothing (1/4 falls);
  `k_arm_d` 0.3 to +0.11..0.14; swing-hip synergy `k_swh` 0.5 falls 2/4 and 1.5 changes nothing; a lean that grows with speed (`lean_v` 0.05-0.1) falls 3/4. Put in the search as tunables (f4) the search kept
  `k_arm_p` 0.66 and `lean_v` 0.018 and they are not the source of the 0.5 m/s (ablation above). The spine servo of round 1 stays off (`k_sp` 0.03).

**What limits the stride now** (muscle level, `mtab.py`, crouched gear 4 at 7.9 m/s; force fraction = force / peak isometric at the stance's peak-load quarter, activation 1.0 in all):
vasti 0.72, soleus 0.83, gastrocnemius 0.80, toe plantarflexors 0.9-1.1 (saturated), hip extensors 0.2-0.3 (they shorten at 3-4 range/s: power-limited). A stronger muscle does not help an untuned gait
(single group x1.25 on the P95 body, 4 flying seeds, peak from 7.931: gastrocnemius 8.124 with no fall, soleus 7.990 (2/4 fall), toe plantarflexors 7.945, hip extensors 7.935, hamstrings 7.834 (3/4 fall),
vasti 4/4 fall: the controller is tuned to its vasti), so the ceiling table's ranking (plantarflexors and vasti strength first) is the right one, and hip extension is limited by shortening speed, not strength.
The one-parameter line search along the search's own direction (alpha 0.5 -> `f3c`) shows the ridge is narrow: 1.5 x the step falls 5/8, 2 x 6/8, with no speed gain in the survivors.

**Refinement, and the fall hazard.** The landing ankle's box floor (-0.3) was still the lever. Single edits of the promoted gear 5, in the standing-start chain (arena starts; falls on unseen standing starts
141-220 and 251-330; survivors' peak):

| variant | arena starts | unseen falls, 80 + 80 | survivors' peak (unseen) |
| --- | --- | --- | --- |
| `x5a` (entered) | 8.276, 12/12 | 4/80 + 3/80 | 8.30 |
| `a_reach` -0.33 (`scratchpad/sprint2/x5a_ar-0.33_stand.txt`) | 8.373, 12/12 (min 8.341) | 6/80 + 6/80 | 8.36-8.37 |
| `a_reach` -0.35 | 8.394, 10/12 (223, 224 fall at 20-21 s) | 7/80 | 8.40 |
| `a_reach` -0.40 and 1400 more ES rollouts (`f7_snap1`, `f7s1_stand.txt`) | 8.48, 11/12 (224 falls) | 11/80 (flying: 9/40) | 8.47-8.48 |
| `d_push` back to the previous stage's -0.1285 (`x5b_stand.txt`) | 8.337, 12/12 | 8/80 | 8.35 |

Each is +0.06..+0.2 m/s and each has more late falls (all at 19-28 s, 8-15 s after gear 5 is entered): the hazard rises with speed along this ridge, and the searches' 16-24 s flying horizons do not reach
it. `x5a` (7/160 = 4.4 %) is what round 1 would have entered by its own rule (3/80 for the four-gear champion); `x5c` (12/160 = 7.5 %, Fisher p 0.24 against `x5a`) is left out for +0.10 m/s. A search on 30 s
standing-start chain rollouts (or 30 s flying ones) is the next step for those variants.

**Not done / not entered.** A sixth gear (`f6`, `f6b`: 2400 rollouts on snapshots of `x5a`, `sprint_touch_run_v4_p95m.npz` / `_p95n.npz`) does not beat gear 5: a restarted copy of gear 5 falls on 7/19
flying starts at 8.3 m/s, the search repaired survival (16/19) and not speed (steady 8.21 against 8.26). The recipe was not run on the average and elite2 bodies; the entry speed of gear 5 (7.8 m/s) was not
searched (the champion's gear 4 is entered at 7.7). What would move the numbers next: the landing ankle towards the ideal's -0.44 with a search that sees 30 s, a longer flight at the same contact (0.150 ->
0.161 s, 9 % more mean force), and a step length that the lift-off geometry allows only at higher speed.

Recipe (the round-1 recipe with the two changes that mattered: a start inside the extended family, and `--agg mean`): snapshots of the champion's steady running (`scratchpad/sprint2/snap.py PARAMS CONTROLLER OUT.npz
--seeds 31-50 --t0 20 --t1 29`), a practice file (`mkgear.py PARAMS OUT --gears K --fly`, plus the start's twins), then `RUN_NATURAL_START=flying ROBOLAB_SNAP=<snapshot set>
hsearch.py sprint_touch_v4x --method es --agg mean --lam 16 --seconds 16 --seeds <8 seeds> --attrs objective=6,fly_touch=2,fall_pen=300,st_ktd=0.55,st_td=0.5,st_lo=-0.55,st_kmax=0.75
--init <practice file> --only "gK_*" ...` (`scratchpad/sprint2/es.sh`; the ES needs `RUN_NATURAL_START=flying` exported or its rollouts are standing starts, and a start value outside its box is clipped:
both cost round 2 an hour). Check the search's `start` line is a survivor's score (> 0) before trusting the run. The standing-start entry: `mkgear.py PARAMS OUT --gears K --von <0.1 m/s below the snapshots>`.

Files: `lib/robolab/skills/run_gearx.w`, `lib/entry/run_gearx.w` (RunGearX); `playground/tasks/sprint_touch_v4x.py` (objective 6, the diagnostic torque); `playground/hsearch.py` (`--agg mean`, opt-in);
`params/run_gearx_v4_p95_x5a.txt` (the champion; frozen binary `bin/challengers/run_gearx-a`, copy in `bin/champions/`); snapshot sets `playground/cache/sprint_touch_run_v4_p95{j,k,m,n}.npz`; every tool,
practice file, search log and the run-by-run log in `scratchpad/sprint2/`.
