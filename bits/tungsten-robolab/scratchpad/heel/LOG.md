# Why the trail leg's heel stays low: measurements of 29 Sep 2026 (night)

Erik's question: "in all the runners, why is their trail-leg's foot staying so close to the ground? in the usain bolt model he
contracts at the knee to a very acute angle, his heel is near his glute. why is this not so in our runners? is that a human mistake,
or are our models missing something? have we modeled momentum in the body? body weight in addition to the muscles, maybe it's
momentum that keeps the calf carrying up to the glute".

Scripts (all in this directory; run from bits/tungsten-robolab; v4 body env = ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95
ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation):

- `probe.py TASK PARAMS CONTROLLER SEED SECONDS OUT.npz` logs knees, hips, heel positions and leg muscle activations every control step
  (env RF_SCALE / HIP_SCALE / KN_SCALE / KP_SCALE / HAM_SCALE scale a muscle group's peak force on the built model: an anatomy what-if);
  `analyze.py OUT.npz T0 T1` prints the per-swing peak knee flexion, heel height and heel-to-hip distance.
- `whip.py MODE T0 WIN SEED SECONDS OUT.npy [PARAMS CONTROLLER]` (modes base, r_knee_off, r_ext_off, r_tau<N m>): passive-whip tests on the
  right leg after each toe-off (contact > 0.05 body weights is stance), same env scale variables as above.
- `decomp.py SEED T_FROM T_TO OUT.npz` decomposes the right knee's equation of motion (muscles by group, series-tendon springs, gravity and
  Coriolis, inertial coupling from the other joints' accelerations) and logs the fibre joints and the series-elastic tendon forces.
- `inspect_model.py` prints damping / stiffness / armature / tendon and actuator parameters of the right leg.

## Numbers (v4 body, 95th percentile, five-gear champion `params/run_gearx_v4_p95_x5a.txt` + `bin/challengers/run_gearx-a`, arena start 221)

| what | our runner (7.8 m/s) | reference |
| --- | --- | --- |
| peak swing knee flexion | 98 deg mean (87-105), both legs, 40 swings each | Bolt ~140 deg (README, sprint_blocks form table) |
| when | 0.29 s after toe-off, i.e. at the END of the swing | sprinters fold within ~0.1-0.15 s |
| flexion gained in the first 0.1 s after toe-off | 18 deg | ~70-90 deg |
| heel peak height (pelvis 0.89 m) | 0.35 m | heel near the glute |
| heel-to-hip distance at the fold | 0.58 m | ~0.31 m for a 140 deg fold |
| swing-leg moment of inertia about the hip (Winter masses, 0.43 m thigh/shank) | ~1.35 kg m^2 at 98 deg | ~0.81 at 140 deg (straight leg 2.35) |
| step frequency | 3.8 /s (sprinter body 4.2, blocks runner 3.3) | Bolt 4.5 |

The Bolt-keyframed runner (`sprint_bolt_form` champion, formB_p.txt, v3 p95 body, 5.6 m/s; its search minimises the joint-angle error to Bolt's
max-velocity cycle) also folds only to 104-105 deg (peak hip flexion 100 deg): the model cannot follow Bolt's knee even when it is told to.

## What the controller asks for

RunSkill (six-chunk stride, `gait` key absent): the swing leg's mid-swing pose is `tuck(k_mid)` = min(k_mid + heel_tuck, 2.45) = 2.45 rad (140 deg),
late swing `k_late` 2.05-2.2 rad, the trailing leg's follow-through `tuck(k_fo)` = 1.24 + 0.6 = 1.84 rad (105 deg); chunk easing times are tiny
(t_land 0.002, t_push 0.05, t_flight 0.13 s) and the swing reflex stiffness is ~0, so the knee flexor drive is at 1.0 for the whole swing
(activation log). The command is not the limit; the achieved fold is (~1.8 rad).

## Where the torque goes (`decomp.py`, right knee, first 0.15 s of swing)

- Muscles at the knee (flexion positive): ham 83 -> 32, knee_pos 20-50 N m, total about +100 N m early.
- Inertial coupling from the hip's acceleration (the "whip"): +285 to +443 N m in the first 30 ms, so momentum IS modelled and is large.
- Series-elastic tendons (chains of the extensors, which show up in qfrc_passive at the knee, not in qfrc_actuator): the rectus femoris chain
  110-209 N m and the vasti chain 45-92 N m at toe-off; the net qfrc_passive at the knee is -63 ... -219 N m (extension). The rectus femoris is
  driven as a HIP flexor by the pose servo (the hip mask includes rf) and by drv_rf 0.74-0.8; each N m of hip flexion from it costs 0.8 N m of
  knee extension. Fibre joints are nowhere near their range limits; passive-only muscle torque (activation 0) is 0 at these lengths.
- Net: the knee reverses to +8 rad/s by 36 ms, then stalls (2.5 rad/s at 72 ms) when the coupling fades and the rectus femoris pulls.

## Experiments

- knee extensors (vasti + rectus femoris) off for 0.12 s after each right toe-off: flexion gained in the first 0.1 s rises from 18 to 48 deg
  (control leg 30); peak flexion unchanged (the window is short and the run degrades: 7.2 m/s).
- all right knee muscles off: falls at 13 s. Knee muscles off + an applied 60 N m knee-flexion torque for 0.12 s after toe-off: right knee gains
  60 deg in 0.1 s and peaks at 132 deg (max 148); 120 and 200 N m fall sooner (the gait is not retuned). So the model CAN fold to Bolt's
  angle with momentum plus about the mono knee flexor's torque (53 N m at p95) once nothing pulls the knee straight.
- drv_rf 0.8 -> 0 or 0.3, drv_swk 0.8 (gear 5 twins): no change in the fold (102-104 deg), peak speed 7.83-7.89 (the pose servo still recruits rf).
- ANATOMY WHAT-IF: rectus femoris peak force x1/3 and mono hip flexor x2 (total hip-flexion torque unchanged), champion gait NOT retuned:
  fold 98 -> 121 deg, but peak speed 5.4 m/s (the gait is tuned to the old proportions; falls at 11 s if the vasti are also x1.35). The Bolt-form
  runner with the same patch, not retuned: fold 105 -> 112 deg, step frequency 3.2 -> 3.6 /s at the same 5.6 m/s.

## Diagnosis

Momentum and body mass are in the model (MuJoCo rigid bodies with Winter's segment masses and inertias) and the whip is large. What cancels it
is the anatomy's split of the hip-flexion / knee-extension capacity: playground/body.py V2_MONO_PEAKS = hip_flex (100, 120), knee (40, 230) and
V2_BIARTICULAR rf 150 (hip 1.0, knee 0.8), ham 200, gas 180 "keep each joint's total peak torque at human scale" but make the rectus femoris
60 % of hip flexion (150 of 250 N m; real: iliopsoas ~55-60 %, rectus femoris ~20-25 %, sartorius / tensor fasciae latae / pectineus / adductors
the rest) and 26 % of knee extension (real ~10-15 %). Hard hip flexion in this body therefore pulls the knee straight through the rectus femoris
chain, which is exactly the swing's job (thigh forward AND heel up), and there is no sartorius / gracilis (hip flexor + knee flexor). The searched
runners settle on a compromise with a long, slow recovery leg (about 1.7x Bolt's swing inertia, lower cadence). A human mistake in the anatomy
calibration (round-number peaks), not missing physics. Untested: whether a Bolt-like fold raises speed once the gait is retuned.
