**Sprinters on v4** (trials `sprint_top_speed_v4`, `_v4_p95`, `_v4_elite2`; the old trials and champions are untouched). Practice task
`sprint_touch_v4` (objective 2 or the flying-start pace objective 3), controllers `RunRISkill` and, for the final entries, `RunGearSkill`
(`lib/robolab/skills/run_gear.w`). Ceilings are the pitch-free ideal-control ceilings above (8.2 / 10.45 / 9.28 m/s). P95 and elite2 are the
literature profiles (`profiles/p95.json`, `elite2.json`); no result of the unverified `elite.json` profile is reported here. The run-by-run log is
`scratchpad/sprint_knot/LOG.md`.

**Arena** (12 perturbed standing starts, 30 s, a fall scores -1e9; validation = 40 further unseen starts, seeds 141-180, and 40 more, 181-220, never trained on):

| trial | champion (params, controller) | peak 1 s speed | starts surviving | share of the ceiling | unseen seeds: falls in 40 + 40 |
| --- | --- | --- | --- | --- | --- |
| `sprint_top_speed_v4` (8.2) | `params/run_gear_v4_avg_c.txt`, RunGear, 3 gears | **6.170 +- 0.003** | 12/12 | 75.2 % | 0 + 5 (4 of them at 5-7 s) |
| `sprint_top_speed_v4_p95` (10.45) | `params/run_gear_v4_p95_e.txt`, RunGear, 3 gears | **7.862 +- 0.010** | 12/12 | 75.2 % | 1 + 1 |
| `sprint_top_speed_v4_elite2` (9.28) | `params/run_gear_v4_elite2_c.txt`, RunGear, 3 gears | **6.78** | 11/12 (seed 231 falls) | 73.1 % | 1 + 2 |

Every entry (ten promotions, one loss; `playground/arena/history.jsonl`; all paired tests p <= 0.001 except the loss):

| stage (share of the ceiling) | average body | P95 body | elite2 body |
| --- | --- | --- | --- |
| the v3 champions' params on v4 | fall (0/12) | fall (0/12) | fall (0/12) |
| first v4 search (RunRI from the v3 params) | v4s1 3.92 (48 %), v4s2 4.68 (57 %), **v4r1 4.65 (56.7 %, entered, 11/12)** | p1: 6.60 at 1500 rollouts (63 %), 7.05 at 2400 (67.5 %; 17/24 seeds survive) | e1 (from the average-body gait) 6.42 (69 %; 7/24 falls) |
| + start plan v0 2.0, foot clearance | a2 (from the P95 gait) **5.875 (71.6 %, entered, 11/12)**; a2v 12/12 at 5.873, loses the paired test (p 0.30) | **p2b 7.00 (67 %, entered, 10/12)** | **e1v 6.44 (69 %, entered, 10/12)** |
| two gears | **6.045 (73.7 %, entered, 12/12)** | **7.449 (71.3 %, entered, 12/12)** | **6.61 (71.3 %, entered, 11/12)** |
| three gears | **6.170 (75.2 %, entered, 12/12)** | **7.862 (75.2 %, entered, 12/12)** | **6.78 (73.1 %, entered, 11/12)** |
| four gears | - | 7.94 (76 %) on 6/6 practice starts, 7.938 on 40 unseen with 4 falls: not entered | - |

**What the searches found.**

- *The v3 params fall on v4, and the first v4 gait is a dead end.* Started from the v3 average-body params, sep-CMA (v4s1, v4s2, v4r1: 6600 rollouts) ends in a straight-leg
  pogo (touchdown knee 0.14, peak 0.14 rad; 60 % of the vertical impulse arrives in the first 35 ms as a 10.6 BW collision, foot vz -2.3 m/s): 4.65 m/s, an isolated basin (almost any
  change falls; objective 5 with the v4 ideal stance moved its score 350.1 -> 351.4 in 7 generations; `knots 1` seeded from the ideal falls). The same search started from the *P95* v4 gait
  (a smooth bent-knee stance, peak vGRF 3.8 BW, found from the v3 P95 champion in 1500 rollouts) reached 5.875 m/s on the average body in 600 rollouts. The lesson is the basin, not the
  budget: try the other bodies' gaits as starts. (The P95 gait is a crouched, ~4 steps/s bounce, knee 0.8-0.9 rad at touchdown, torso upright: not the ideal stance.)
- *Falls are the score, and the falls were three different things* (traced with `scratchpad/sprint_knot/stridetab.py`, `pitchmax.py`, `alt_growth.py`):
  (1) the searched **start plan speed `v0` sits at ~0.25 m/s** (the drives scale with v_des / v_top from the first push, so the start has almost no drive): every searched gait falls in 4-9 s on
  10-25 % of starts, and `v0 = 2.0` (the tunable's box is [0, 2.5]) removes these falls with the stride untouched (average a2: 4/40 -> 0/40; P95 hard seeds 7/8 -> 1/8; elite2 8/8 -> 1/8);
  (2) **swing-foot trips** in the crouched gaits (4 scuffs / s): `clear_h 0.16, k_clear 2, heel_tuck 0.6` at no speed cost; (3) a residual **late fall** (13-30 s) of the ~4 steps/s bounce, a sudden bad step
  after an intermittent period-2 burst of the aerial gaps (15-25 ms against 2-4 ms), not a drift: max torso pitch after 5 s is 0.23-0.38 rad on every surviving seed and crosses 0.6 rad only ~0.05 s before the fall,
  and stride, stance or pitch variability do not predict it. A single-parameter tweak "fixes" a failing seed by chance (any perturbation reshuffles a chaotic outcome): only fresh seeds tell.
- *Search on few seeds overfits.* Hardening a stride on 8-10 mined hard seeds produced gaits that survive those seeds and fall MORE on fresh ones (average 8/30 against 4/40, P95 9/42 against 15/64,
  extended-mode P95 10/40 early falls): at a 20 % hazard, passing 8 seeds is luck 17 % of the time. What works is a long cascade: a candidate stops at its first bad rollout, only low-hazard ones run
  all 12-19 seeds. Gear 2 of the P95 champion trained on 4 seeds fell on 8/40 unseen seeds, on 16 seeds on 2/40.
- *`playground/hsearch.py`* (new, opt-in): scores a candidate by its worst rollout and runs the seeds as a cascade inside one worker (stop at the first score below the incumbent's; a short "gate" horizon per seed,
  `84g10`); a (1+lambda)-ES with sparse mutations, a success-rate step size, one combination of the improving offspring and one extrapolation step per generation (or sep-CMA with restarts around the incumbent).
  sep-CMA stalled on the fragile optima (sigma 0.04 in 94 dimensions is a 0.4 step against ~4 % of a box that breaks ~40 of the parameters); the ES moved 3-5 x faster per rollout. `search.py --box name=lo:hi`
  widens a search box (a skill does not clamp a params-file value; the searched gaits sit on the bounds of t_push_max, k_land, t_land, z_ref, hip_lead, g_kl, a_push, k_late).
- *One parameter set cannot both start and cruise; gears.* A flying start (`RunKnotSkill` `fly_entry 2`: enter the right stance chunk from a snapshot of the champion's own steady running,
  `playground/cache/sprint_touch_run_v4_*.npz`; 8-24 s rollouts, 3-5 x cheaper than a standing start) lets a search tune the cruising gait alone: on P95 it gained 0.5 m/s in 20 minutes
  (6.95 -> 7.46 steady) and that gait falls from a standing start (6/6 at 4 s). **`RunGearSkill`** (opt-in `gears N`; without it RunKnotSkill exactly, checked to the digit): every tunable X has gear twins
  g2_X .. gN_X (default: the previous gear's value) and the first flight after the filtered speed reaches `g<k>_v_on` rebuilds the whole stride (chunks, poses, corrections, reflex gains, reciprocal inhibition)
  from gear k's values; `Track#set_movement` (controller.w, a new method with an SDK spec) swaps the movement under the running track. Gear 1 is the start and the acceleration; each later gear is searched by
  flying-start ES from snapshots of the gear before it (`gear0 K` starts a practice run in gear K). Gear 2 trained on 4 seeds x 8 s exploited its horizon (fell at ~19 s on 6/6); on 16 seeds x 24 s (`fall_pen 300`) it holds.
  The gain per gear on P95 is +0.45, +0.41, +0.08 m/s: the crouched family saturates near 8 m/s.
- *The requested experiments, all opt-in and reported as run.* Objective 5 (above): no gain from the pogo basin. Knots: seeded from the ideal (v4 P95 at 9 m/s, average at 8 m/s) the stance falls (the touchdown knee
  comes out 0.81 for a commanded 0.54); seeded from the gait's own distilled stance (`knot_seeds.py`; the world thigh has to be shifted by the pelvis pitch, -0.25 rad) it runs (6.29 m/s against 6.45, contact 0.176 s
  against 0.124), a start for a knot search that was not run because the gears gained more per hour. Spine trunk servo (`k_sp`, `k_spd` in RunRISkill; the lumbar spine has 200-250 N m, as strong as a hip): small gains change
  nothing measurable, gains from 0.5 break the gait. Residual TCN and ILC were not run: the v3 result was negative, the failure here is a stride-timing instability rather than a tracking error, and there is no
  kinematic target the saturated stance can follow.

**Why not 10 m/s.** The best controller is at 7.86 m/s on P95 (75 % of the 10.45 ceiling; 7.94 with a fourth gear at a 10 % fall rate), 6.17 on the average body (75 %) and 6.78 on elite2 (73 %). Three independent routes saturate at 72-76 % of
their ceilings (standing-start CMA and ES; flying-start ES per gear; knots). The ideal at the P95 ceiling is contact 0.100 s, flight 0.161 s, 3.83 steps/s, 2.61 m steps, mean / peak force 2.61 / 5.06 BW, touchdown knee 0.54, lift-off thigh -0.66;
the four-gear runner at 7.9 m/s has contact 0.102 s, flight 0.139 s, ~4.15 steps/s, ~1.9 m steps, 2.35 / 4.5 BW, knee 0.67, thigh -0.41: force and contact are within 10 %, but it flies 14 % less and steps 27 % shorter, so 10 m/s at its cadence would
need 2.4 m steps. Every search preferred the crouched bounce because the ideal's extended stance (touchdown knee 0.5, lift-off thigh -0.66, a trunk that rocks less than 0.1 rad) cannot be started (60 % of standing starts of the extended gait fall in
acceleration) and no controller here holds the trunk against the stance hip's hip-extension torque (the trunk pitches 0.36 rad per stance in the extended gait, against the ideal's 0.1). What would still move the numbers: a robust fourth gear
(the P95 hazard at 7.7+ m/s is the limit), a third-gear-style search for the extended stance from flying starts on top of a crouched acceleration, and a trunk actuator in the stance (the spine servo was too weak alone).

Files: `lib/robolab/skills/run_gear.w` + `lib/entry/run_gear.w` (RunGearSkill); `run_knot.w` (`fly_entry`), `run_ri.w` (`k_sp`, `k_spd`); `controller.w` (`Track#set_movement`); `playground/hsearch.py`, `search.py --box`, `tasks/sprint_touch_v4.py`
(`start_noise`, `ROBOLAB_SNAP`); champions' params `params/run_ri_v4_*.txt`, `params/run_gear_v4_*.txt`, frozen binaries `bin/challengers/run_ri-v4base`, `run_knot-v4*`, `run_gear-v4*`; diagnostics and every search's params and logs in `scratchpad/sprint_knot/`.
