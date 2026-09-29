AGENT K REPORT (soccer hold blow-ups, 9/29). Root cause found and reproduced; it is a MuJoCo tendon-wrap NaN, not the stance. Guarded arena trials now certify balance gains.

1. REPRO (deterministic; MuJoCo 3.6.0, MyoSuite 2.12.2, numpy 1.26.4, Python 3.12, .venv-myo)
   .venv-myo/bin/python scratchpad/blowup/capture.py --params params/myo_soccer_single_leg_310_shc.txt --controller bin/challengers/soccer6-p --seed 91049 --seconds 19 --out out/blowup/r91049_a
   -> "Nan, Inf or huge value in QACC at DOF 6 ... Time = 16.5170" in 16 s wall. Two captures are bit-identical (1651 states x 1019 values); a bit-exact open-loop replay of all 16 500 substeps
   from the recorded controls matches every control step. Also 89122 (15.811 s), 89134 (134.214), 89135 (130.209), 89130 (141.040); the guarded reruns hit 89103 (255.550) and 89106 (222.068)
   at the same instants. A 7.5 KB saved MjData state reproduces it in ~1 s with no controller: .venv-myo/bin/python playground/repros/myosuite_soccer_wrap_nan_state.py [mujoco_wrap_nan_states/r89122_t15.81.npz ...]

2. ROOT CAUSE (playground/repros/mujoco_wrap_nan.md, self-contained; NOT filed upstream: Erik decides)
   - DOF 6 = the kicker's ROOT free joint's first dof (dofs 0-5 are the ball's free joint): mj_checkAcc reports the first bad dof, so it only says "the kicker's qacc is NaN".
   - At the failing substep exactly ONE tendon length is NaN (239 recfem_r_tendon; the wrap points of its cylinder KnExt_at_fem_r_wrap are NaN) and mj_fwdPosition (kinematics + tendons: no solver, contact
     or actuator) already returns it. No precursor in any indicator (contact/constraint counts, solver iterations (1 throughout), largest constraint force, the 215 N leg contact, limits, muscle forces).
   - Source: MuJoCo engine_util_misc.c length_circle: angle = acos(dot(p0n, p1n)) of the two normalised tangent points of a cylinder/sphere wrap. When the tendon line only grazes the geom (relative margin
     (r^2-d^2)/r^2 < ~6e-8, i.e. within ~1 nm of the tangent) the points are ~2e-8 rad apart, the dot rounds above 1.0 (about 1 case in 10; 30 % at the tangent), acos = NaN, and mju_wrap's `wlen < 0`
     test does not see the NaN: tendon length, moment arms, muscle force, qacc = NaN, mj_checkAcc resets the data, the kicker falls 0.2-0.4 s later. Old and current: the pure-MuJoCo repro gives the same
     859 NaN of 8001 (cylinder) / 651 (sphere) on mujoco 3.2.7, 3.3.0, 3.6.0 and 3.14.0 (newest PyPI release); upstream main's wrap functions are byte-identical.
   - Evidence: real-library sweep (40 001 mj_fwdPosition calls through the failing state, one hip angle 2e-6 rad in 1e-10 steps): 272 NaN, all with the wrap active and margin <= 5.5e-8, NaN fraction following
     the exact 60-digit 1-dot (29 % < 1e-17, 6 % near 1e-16, 0 above 2.5e-16; same curve in two other failing states); standalone C harness of the 3.6.0 wrap code: 6834 NaN in 40 001 points, all with
     dot > 1.0, 0 with the dot clamped (the ONE-LINE FIX: mju_acos(mju_clip(dot, -1, 1)) in length_circle).
   - Why it looked rare and chaotic: the sliver is ~1 nm wide but the swing leg's right rectus femoris HOVERS at its wrap tangent (91049: the margin settles to 0 +- 2e-4 and crosses it hundreds of times; the
     swing ankle chatters 4e-3 rad step to step); each visit to the sliver is NaN with probability ~0.1. Bit-exact replay of 91049: exactly 2 substeps in the sliver, one survived (11.236 s), one NaN (16.517 s).
   - Also a SECOND VICTIM: the guarded runs caught IL_L1_r_tendon (a TRUNK muscle on back_cylinder_s) at 2.12 s of start 96029: the official environment would have scored that start a balance failure.
   - BISECT (bisect_variants.py; column B = one change applied to the bit-exact failing substep only): timestep/2, CG, PGS, 500 iterations, cone, impratio, noslip, islands, implicitfast, Jacobian, warmstart, contacts off,
     the tibia_r-femur_l pair removed or softened, muscle activation dynamics x2, sidesite removed, swing-ankle damping: the NaN stays; only wrap-geometry changes (radius x(1+1e-6), x(1-1e-3), 0) remove it.
     From 300 steps earlier every change that alters the trajectory re-rolls the rounding (O's "0.002 rad cures it 4 of 4"). EXCLUDED as causes: the leg contact, the solver, the timestep, the chatter (a
     trigger of the crossings at most).
   - MyoSuite gotcha: env.unwrapped.mj_data (MyoSim.d) is a sensor-synced MIRROR (ctrl 0, no warm start); the stepped data is env.unwrapped.robot.mj_data. O's contact/qacc/efc dumps were the mirror's. A sliver state at a
     control-step boundary reaches the controller through the mirror first (89103, 89130): NaN muscle length -> NaN ctrl -> MuJoCo zeroes ALL controls.

3. THE FIX AS A LABELLED VARIANT (playground/tasks/myo_soccer_ng.py; nothing else edited: not the .w skill, bridge, SDK or arena code)
   Stepped data advances through a guard (snapshot, mj_step exactly as MyoSuite, and only on a MuJoCo reset with a NaN tendon at the snapshot: redo the substep after a <= 1e-10 rad nudge), plus a mirror check per control
   step; other instabilities are replayed as MuJoCo does (nan_other = 0 everywhere). Bit-identical to the official environment until a NaN: identical in every base metric on 119 / 119 event-free hold20 starts
   (official task run on all 120), 35 / 35 full 310 s brake runs, and every re-run; the 7 known events reproduce at the official instants and are all survived:
   89106 (lift) 222.068 s, 89122 15.811, 89130 141.040, 89134 134.214, 89135 130.209, 89103 255.550, 91049 16.517: each holds to the end of its run (310 s: bal1 307.6-308.6; 91049 was run to 30 s, bal1 28.3).

4. TRIALS (new keys through the arena lock; per-start tables scratchpad/blowup/RESULTS.md; run with scratchpad/blowup/arena_ng.py = arena.py + a resumable rollout cache)
   | trial | entry | official (unguarded) | guarded result | vs champion |
   | --- | --- | --- | --- | --- |
   | soccer_single_leg_310_40_ng (89100-89139, 310 s, bal1_300) | round-5 lift | 34 / 40 | 35 / 40 (seeded champion) | |
   | | round-6 set ramp | 38 / 40 | 39 / 40 | +0.100, p = 0.066: not promoted (fixed 4) |
   | | ramp + shift brake | 35 / 40 | 40 / 40 | +0.125, p = 0.034: PROMOTED (fixed 5: 89110 89115 89117 89130 89133, broke 0) |
   | soccer_hold20_120_ng (96000-96119 fresh, 20 s, hold20 = standing since the start and on one leg for the last 15 s) | lift | - | 102 / 120 (seeded) | |
   | | ramp | - | 113 / 120 | +0.092, p = 0.006: PROMOTED (fixed 14, broke 3) |
   | | brake | - | 118 / 120 | vs ramp +0.042, p = 0.067 (fixed 6, broke 1): not promoted; vs lift +0.133, p < 1e-4 (fixed 16, broke 0) |
   The guard reverses the official ranking (lift 34, brake 35, ramp 38 -> lift 35, ramp 39, brake 40): the brake lost 5 holds to the bug. The 5 lift falls (89110 89115 89117 89130 89133) and the ramp's 89133 are REAL
   balance falls (rows identical to the official ones, no NaN). The 310_40_ng trial is now saturated (40 / 40); early-fall gains are certified on hold20 (the ramp's gain is p = 0.066 on 40 starts, p = 0.006 on 120).
   Per-start hold20 failures: lift (18) 96023 96033 96039 96043 96045 96052 96055 96064 96067 96070 96081 96086 96095 96096 96098 96100 96105 96116; ramp (7) 96011 96055 96059 96095 96098 96103 96116; brake (2) 96023 (falls at 11.1 s),
   96116 (2.3 s). Full per-start tables: scratchpad/blowup/RESULTS.md.
   BLOW-UP RATE (counts): official runs, each first event ends the hold: lift 1 in 10 783 start-seconds, ramp 1 in 11 799, brake 5 in 11 529 (0.09 / 0.08 / 0.43 per 1000 start-seconds; 7 in 34 111 pooled = 1 per 4.9 ks,
   6 % of 310 s holds). Guarded, all events counted (passing starts identical and event-free): 310 s x 40 starts: lift 2 events / 10 876 start-seconds, ramp 2 / 12 095, brake 6 / 12 400 (0.18 / 0.17 / 0.48 per 1000);
   20 s x 120 starts: lift 1 (the trunk tendon) / 2 112 s, ramp 0 / 2 304, brake 1 / 2 375. All 10 distinct events were survived (nan_other 0); 4 of 10 were control-step-boundary (mirror) events.
   MECHANISM CLOSURE (brake, 40 starts x 310 s all real, 12.28 M substeps of recfem_r watched): 60 states in the NaN sliver, 54 survived + 6 NaN; the exact-1-dot table (measured on the real library) predicts 6.27 events,
   observed 6 (P(NaN | sliver state) = 0.10, 95 % 0.05-0.20). HAZARD EXPOSURE per entry (120 fresh starts x 20 s, all real): substeps within 1e-4 of the tangent lift 0.48 % / ramp 1.21 % / brake 1.41 % (paired p = 1e-4 for
   ramp and brake vs lift, 0.31 brake vs ramp); starts spending > 1 % of the hold there: 5 / 25 / 25 of ~120: the ramp family parks the swing rectus femoris at the tangent ~3x more; O's "the brake raises the hazard" was that
   plus a 5-vs-1 draw (exposure-proportional expectation of the official counts: 0.9 / 2.8 / 3.3).

5. FILES: new playground/tasks/myo_soccer_ng.py; playground/repros/{mujoco_wrap_nan.md, mujoco_wrap_nan_repro.py, mujoco_wrap_nan_harness.c, myosuite_soccer_wrap_nan_state.py, mujoco_wrap_nan_states/ (5 saved states)};
   scratchpad/blowup/ (LOG.md with the repro recipe and run index, RESULTS.md per-start tables, the tools, evals/, evalcache/). Modified: playground/arena/{trials.json (new keys soccer_single_leg_310_40_ng, soccer_hold20_120_ng),
   champions.json, history.jsonl, params/ (the arena's frozen champions), README.md (note on the _ng trials)}, bin/champions/ (frozen binaries), README.md (new "Soccer round 9" section + supersession notes in Round 8).
   NOT touched: lib/robolab/skills/myo_soccer_v4.w, the bridge, the SDK, the arena code. No git commits.
6. CAVEATS / NEXT: FIVE MINUTES ON FRESH STARTS (supplementary scan, not an arena trial: the 120-start 310 s trial was started, stopped at 69 starts because the machine load rose above 30, and withdrawn unseeded; resume with
   scratchpad/blowup/prefill_310_120.py + add_trial_310_120.py + arena_ng.py seed): the brake at 310 s, guarded, on 69 fresh starts (96000-96038, 96060-96089): 68 / 69 hold 300 s (the one fall, 96023 at 11.1 s, is the
   hold20 failure; no late failure), 15 NaN events in 6 starts (all recfem_r, all survived; each would have ended that hold officially at 14.3 / 25.1 / 31.4 / 50.2 / 191.1 / 282.7 s: 62 / 69 official). Pooled with
   the 40-start trial: 108 / 109 guarded vs 97 / 109 official-equivalent. Second closure sample: 224 sliver states (15 NaN) vs 15.8 predicted; both sets 284 states, 21 NaN vs 22.1 predicted. The 310_40_ng entries' passing rows were copied from the identical official runs (cache entries say primed_from; all 35 of the brake's were re-run for real and matched). The official
   soccer_single_leg_310_40 board is unchanged (lift 34 / 40). Balance work should use the _ng trials (searches still use the unguarded task: a NaN costs about one candidate-start in 5000 s). The upstream report is
   ready in playground/repros/ (self-contained, versions 3.2.7-3.14.0, one-line fix); Erik decides. No other task is known to be affected (the shared MUJOCO_LOG.TXT has late warnings only from the soccer body).
