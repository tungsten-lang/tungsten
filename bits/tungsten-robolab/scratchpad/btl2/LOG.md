# Dribble through the legs, round 2 (agent D, 29 Sep 2026 onward)

Goal (Erik): several through-the-legs passes IN A ROW, measured on held-out starts. State at the start:
champion A4 (`params/dribble_btl_a4.txt`, frozen controller `bin/challengers/dribble_btl-a2`; the current
`bin/robolab_dribble_btl` replays it bit-identically, checked with `scratchpad/btl/identity.py` on seeds 601 and 705):
`dribble_btl_25` 0.104, `dribble_btl_streak_25` mean longest streak 1.28.

All commands run from `bits/tungsten-robolab`. Tools in this directory: `common.py` (load/write params, one rollout),
`chain.py` (per-start pass chains + failure reasons), `scan.py` (grid of overrides), `palm.py` (palm/ball trace),
`reach2.py` (arm IK reach with a flexed/twisted trunk).

## Baseline replication (nothing changed)

`chain.py bin/challengers/dribble_btl-a2 params/dribble_btl_a4.txt 701 726 15` (the arena's streak seeds, 2 workers, 96 s):
streaks [2 x11, 1 x10, 0 x4], mean 1.28, max 2, >=1 on 21, >=2 on 11, >=3 on 0. Identical to the arena's 1.28.
By pass index: pass 1 complete on 21 of 25 (84%; lost_after 2, body 2), pass 2 complete 11 of 25 (44%; wrong hand or
two bounces 13, body 1), pass 3 complete 0 of 12 (all "bounces_or_wrong_hand"). Mean rise apex after each pass's bounce:
0.63, 0.43, 0.40 m (centre); horizontal speed at the receiving touch 2.15, 1.22, 1.07 m/s. So the wall is an energy decay
across passes, not only the return: pass 1 leaves the right palm at 3.3 m/s down (a strike from a cock 11 cm above the
ball with the palm already at 3.1 m/s), pass 2 leaves the left palm at only 1.7 m/s down (the left palm is cocked 6 cm
above the contact, strikes at 1.5 m/s down and sweeps 3.2 m/s sideways; ball leaves at 1.67 x, -1.4 y, -1.73 z), so it
rises to 0.43 and the right hand meets it at 0.45 m.

Trace of seed 601 (`palm.py`): pass 1 released 1.815 s ball (-1.75, 1.8, -3.35); bounce 1.941 at (0.21, -0.02); left
palm touches the rising ball at 2.165 at z 0.63 (rise +1.5 m/s, horizontal 2.1 m/s); leaves at 2.27 with (1.67, -1.4, -1.73);
bounce 2.442 at (0.25, -0.01); the right hand meets it at 0.45 m at 2.645 and sends it (-0.67, 1.36, -2.2): it bounces
at (0.47, -0.07) (not between the legs) and hits the left shin.
Contact physics (dribble.py): hand-ball contact is critically damped (solref 0.004 1, mu 1.0), so the ball leaves with
the palm's velocity ALONG THE PALM NORMAL (no restitution); the ball-floor COR is 0.77 (K_ROLL 0.17 of slip).
For the return the outgoing ball needs about 4 m/s along the palm normal; the left palm delivered 2.8.

## Reach (reach2.py)
With the lunge's trunk twist (spine_rot +0.55, lead-side shoulder back) the left palm reaches (-0.15..0.35, 0.35, 0.85..1.05)
with 0-6 cm error at spine flexion 0.55, and with <2 cm at flexion 0.2-0.35 (without twist x<0.05 is out of reach).
So a higher cock for the lead hand is statically reachable; A4's low cock (bl_dzc 0.054) is a dynamics/timing optimum.

## Diagnosis 1 (29 Sep, 06:00-07:10): where the chain breaks, and why (`ret.py`, `joints.py`, `comfort*.py`)
`ret.py bin/challengers/btl2-base params/dribble_btl_a4.txt 701 717 3.4` (release state of every pass, 16 seeds):
- release 1 (the right hand's launch pass): z 0.60, vz -3.36 (sd 0.12), |vh| 2.62 (sd 0.13): very repeatable.
- release 2 (the left hand's return): vz -1.53 (sd 0.81), |vh| 1.47 (sd 0.38): weak and scattered; complete on 4 of 16.
- release 3 (the right hand's strike of the low return, ball at z 0.39-0.50): weak, scattered (0.4-2.4 m/s), 0 of 5 complete.
So pass 3 is a separate failure from pass 2: the right hand strikes a ball at 0.4-0.5 m with its cock LOWERED by the meeting
correction (hand.dz), so it has no run-up.
Joint traces (`joints.py`, seed 716): the LEFT arm at its return is at its joint limits (shoulder_rot -1.34 of -1.40, elbow 0.3 -> 0
of limit 0, wrist_flex +1.0 of 1.2, shoulder_abd -0.1 of -0.3), the stroke is a wrist flick (-15 rad/s) and the shoulder swing, muscles
saturated (shoulder adductors 1.0, elbow extensors 1.0 from 2.10 to 2.20 s), contact at 1.5 m/s palm speed (peak 3.9 m/s only after the ball
has gone). The RIGHT arm's launch stroke is elbow extension 2.3 -> 1.4 rad at -10 rad/s (comfortable, margins 0.1-0.25 rad).
`comfort.py` (IK of a straight downward-across stroke, joint-limit margins): right hand at (0.45,-0.30) reachable with 0 error and margins
0.07-0.25 rad for palm tilts 25-60 deg; the left hand at the back-left spot cannot reach the ideal stroke for any trunk lean 0-0.55 or twist
0-0.8 (errors 4-13 cm, shoulder_rot at its limit at every point). The earlier planner (`scratchpad/btl/plan7*.py`) already showed the leg
clearance and gate rules force the back-left spot (x -0.2..0.0) for every feasible layout; so the left hand is kinematically weak by geometry.
A4 is brittle: changing spine 0.55 -> 0.5 loses pass 1 outright (its arrival point moves 0.4 m).
Single-parameter probes (16 seeds, 3.4 s, `scan.py`): bl_drv 1-2.5 no gain; bt_rotl (trunk turn into the left catch) any nonzero value hurts
(ok1 12 -> 6, ok2 4 -> 0: the arm IK uses the commanded, not the measured, twist); left spot moved inward by=0.32/0.29: ok1 15, ok2 5-6
(within noise); bt_plan=1,bt_pside=1 (planned strike for the left hand only, defaults) worse (release vz -1.4, vh 1.0).

## Plan
The right hand is the strong one (comfortable geometry): let it restore the ball's energy from the low return (long stroke: cock high,
strike low; `bt_ychain 1` gives the right hand's passes after a catch their own stroke `br_*`, bit-identical to A4 while `br_*` keep their
defaults, checked on seeds 702, 716, 704), and make the left hand's return a reliable soft redirect. Rig: seeds whose passes 1 and 2 are
received (`pool.py`), so pass 3 depends only on `br_*`.

## Code change (opt-in, A4 replays bit-identically: checked seeds 601, 705, 716)
`lib/robolab/skills/dribble_btl.w`: `bt_pside` (0 both, 1 lead leg's hand only, 2 the other only) restricts the planned contact `bt_plan`
to one hand (`planned?(hand)`). Frozen builds: `bin/challengers/btl2-base` (= repo state before), `bin/challengers/btl2-b1` (with bt_pside).

## Runs
- pool of seeds with passes 1 and 2 received under A4 (`pool.py bin/challengers/btl2-b1 params/dribble_btl_a4.txt 801 901 3.0 2 bt_ychain=1`):
  39 of 100: 801,809,813,816,817,819,820,821,822,823,828,829,834,835,836,846,850,852,854,855,856,857,861,864,865,866,867,868,874,875,877,883,884,885,887,889,890,892,895
- manual probe (br_zh 0.79/0.65/0.55 x br_dzc 0.2/0.35, 16 pool seeds, 4 s): pass 3 complete 0 of 16 in every cell (apex 0.32-0.42).
- p3a (started 07:10, pid 33145): `tune.py --ctl bin/challengers/btl2-b1 --init params/dribble_btl_a4.txt --fixed bt_ychain=1 --only br_angc,br_angl,br_zh,br_dzc,br_dzl,br_sweep,br_kv,br_t,br_tmax,br_steer,br_lead,br_ax,br_ay,br_drv --seeds 801,809,813,816,817,819,820,821,822,823,828,829 --secs 3.6 --objective p3 --gens 30 --pop 12 --workers 2 --sigma 0.2 --out scratchpad/btl2/params/p3a.txt --log scratchpad/btl2/runs/p3a.log`
- p3a (pid 33145) stopped at gen 4 (07:25) to free the machine for the oracle study: score 0.237 -> 0.671, pass 3 still 0 of 12 (ok1-4 [12,12,0,0]); params so far in scratchpad/btl2/params/p3a.txt

## Oracle study (muscle-level ceiling), 29 Sep 07:20 onward  (`oracle_lib.py`, `oracle_search.py`, `oracle_multi.py`, `oracle_view.py`)
Method: run the A4 controller once (`record`: activations of every tick, MuJoCo snapshots, ball state), then REPLAY the recorded
activations from a snapshot (bit-exact: max ball position difference 0.0 over 180 ticks, 0.04 s per replay) with the 16 left-arm
muscles (shoulder x6, elbow x2, wrist x4, fingers x4) replaced by a piecewise-linear program (knots every 25 ms, 0..1) searched by CMA-ES.
Objective (`oracle_search.evaluate`): the left hand must touch the ball; the ball must cross the leg gate (the task's rule replayed on
the trace), touch no leg, bounce near the ankle-to-ankle segment, rise to a free apex >= 0.68 m and arrive near the right hand's strike
zone (0.50,-0.26) at z ~0.6 (horizontal speed <= 2.2 m/s).
Result 1 (single start, seed 716, snapshot 2.0 s, 16 muscles, 272 knots, pop 100 then 60): score 0.008 after 30 generations (2.5 min CPU):
release (2.07,-1.98,-3.27) m/s at z 0.54 (|vh| 2.87), i.e. the mirror image of pass 1's release (-1.85,+1.9,-3.3); apex 0.68; gate crossed;
arrival (0.49,-0.21) z 0.54. A4 releases (1.25,-1.48,-2.08) on the same start. => THE ARM CAN DELIVER A FULL-ENERGY RETURN;
the wall is the controller's stroke (reflex servo + pose chunks), not the muscles or the geometry.
Mechanism (oracle_view.py, seed 716): cock at palm z 0.89, a small lift to 0.95 (wrist flexion to +1.26, the limit) from 2.05 s,
then the downswing starts 0.15 s before contact: palm 3.3 m/s at contact (A4: 1.9), a 95 ms carry that keeps accelerating the ball
(wrist flexion +1.26 -> -0.58, elbow 0.68 -> -0.07, shoulder abduction 0.46 -> 0.08, shoulder flexion -0.03 -> 0.36), release at 2.295 s.
Next: robust program across starts (oracle_multi.py; om_left_a: 12 training starts, 8 validation starts, program starts 32 ticks before
the ball's predicted rising crossing of z 0.62), then the right hand's next stroke on the states it produces, then playback in the skill.
- om_left_a (started 07:42): `oracle_multi.py --seeds 801,809,813,816,817,819,820,821,822,823,828,829 --val 834,835,836,846,850,852,854,855 --window 0.40 --lead 32 --gens 200 --pop 60 --workers 2 --sigma 0.10 --init scratchpad/btl2/runs/oracle_716_arm.npz --out scratchpad/btl2/runs/om_left_a.npz`

## Program playback in the skill (opt-in `pg_on`, A4 replays bit-identically: btl2-b2 vs the A4 binary on seeds 601, 705, 716)
`lib/robolab/skills/dribble_btl.w`: params `pg_on`, `pg_first` (pass number of the first programmed pass, 1 = the left hand's return),
`pg_n`, `pg_nk` (17 knots), `pg_dk` (0.025 s), `pg_lead` (0.165 s), `pg_gain` (0 = reflexes off during the program), tables
`pg<p>_<m>_<k>` (m: shoulder flex/abd/rot, elbow, wrist flex/dev, finger mcp/pip, each pos then neg). The stroke of pass number
`pg_first + p` starts when the ball's predicted rising crossing of bt_rh (0.62) is `pg_lead` away (`receive_state`, exact ballistic;
guarded against the floor-contact transient with ball_floor: the sensor's prediction jumps for ~10 ms at the bounce), jumps the hand's
track into chunk `g_run` (gain pg_gain, move announced, follow-through to `idle`), adds the table as drive each tick, and the hand's
touch/release hands the ball over (`handoff_prog`). Frozen builds: btl2-b2 (playback), b3 (pg_dbg), b4 (floor guard), b5 (trigger before step).
`oracle_to_params.py` turns an oracle npz into params (checked: the seed-716 program in the closed-loop skill releases pass 2 at
(z 0.51, vz -3.09, |vh| 2.50), pass 2 complete, vs the replay's (-3.27, 2.87); seeds 704/702, not in that program's training, do not work).
Measured alignment: the program starts exactly 32 ticks before the ball's rising crossing of z 0.62 on every start (716, 704, 702, 801, 809, 813, 816),
the same as `oracle_multi.py --lead 32`.
- om_left_a at gen 24: validation (8 starts not in training) mean J 0.32, good 3 of 8 (training mean J 0.34): the robust program generalises.
- om_left_a stopped at gen ~50 (07:52; saved best = gen 45: train J 0.155 good 7/12, validation J 0.445 good 4/8: some overfit to the 12 starts).
  Closed loop (btl2-b6 + `pgL_g45.txt` = A4 + that table as pass 2, `chain.py ... 901 933 4.0`, 32 UNSEEN starts):
  pass 1 complete 28/32, pass 2 complete 15/30 (50%; A4 44%) with the rise apex 0.60 (A4 0.43) and horizontal speed at the receiving touch 2.14 (A4 1.22);
  pass 3 (A4's reflex stroke of the right hand) 0/19 (apex 0.56). streaks: mean 1.34, max 2, >=2 on 15. So the left hand now sends a full-energy
  return, the right hand's reflex stroke cannot take it: next is the right hand's stage (pass 3).
- oracle_809_right (single start, right hand, pass 3, recorded with `pgL_g45.txt` in the loop, snapshot 2.415 s): J 0.000 after ~100 gens: release
  (-1.73,+1.35,-3.33) apex 0.70, bounce (0.19,0.06), arrival (-0.13,0.32) z 0.60 (the right arm can send the return back with full energy too).
- om_right_a (started 08:07): `oracle_multi.py --seeds 801..860 --val 861..884 --params scratchpad/btl2/params/pgL_g45.txt --ctl bin/challengers/btl2-b6 --hand r --muscles right_arm --bounce-no 3 --require 2 --t-lo 2.3 --t-hi 2.75 --t-end 3.6 --window 0.40 --gens 200 --pop 60 --workers 2 --sigma 0.10 --init scratchpad/btl2/runs/oracle_809_right.npz --out scratchpad/btl2/runs/om_right_a.npz`
  (kept 22 training / 6 validation starts whose passes 1 and 2 were received).
- om_right_a stopped at gen ~40 (mean-vector J 3.07): the return ball's arrival at the right hand under the stage-0 program of gen 45 is broad
  (crossing x 0.505 +- 0.094, y -0.238 +- 0.113, vx 1.45 +- 0.87, vy -1.14 +- 0.96 over 33 received returns), because the closed-loop left program is only
  moderately consistent on unseen starts: release 2 over 24 unseen starts vz -3.13 +- 0.54 (A4 -1.53 +- 0.81), |vh| 2.51 +- 0.68 (A4 1.47 +- 0.38),
  pass 2 complete 11 of 22; some releases bounce 0.3-0.4 m too far out (0.02,0.4) and hit the lead leg, one start misses. The 12-start training set overfits
  (validation J 0.445 vs training 0.155). Stage 0 gets a much bigger training set before stage 1 is redone.
- om_left_b (started 08:50): `oracle_multi.py --seeds 801..880 --val 881..900 --window 0.40 --lead 32 --gens 400 --pop 60 --batch 12 --full 10 --workers 2 --sigma 0.08 --init scratchpad/btl2/runs/om_left_a_g45.npz --out scratchpad/btl2/runs/om_left_b.npz` (records 100 more starts first).
- om_left_b (80 training / 20 validation starts, objective with arrival-velocity terms) stopped at gen ~15 to do the launch pass first: the previous
  program (fit to 12 starts) scores J 3.7 on the 75 recorded starts (good 17/75), gen 9 of the new run 2.39; saved as om_left_b0.npz.
  Reason for reordering: the sequential greedy chain is cleaner if pass 1's release is consistent before the left return is fitted to it
  (A4's pass 1 arrival at the left hand is crossing x -0.21..-0.06, y 0.25..0.37, vx -1.17..-1.55: a few slow outliers).
  Skill change: `pg_first 0` programs the launch pass itself (the trigger allows @pass_no 0 once the ball is released); btl2-b8.
- om_pass0 (started 09:0x): stage "-1": the right hand's launch pass as a program: `oracle_multi.py --seeds 801..880 --val 881..900 --params params/dribble_btl_a4.txt --ctl bin/challengers/btl2-b8 --hand r --muscles right_arm --bounce-no 1 --t-lo 1.35 --t-hi 1.75 --t-end 2.5 --window 0.40 --lead 32 --gens 500 --pop 48 --batch 10 --workers 2 --sigma 0.10 --cache scratchpad/btl2/runs/rec_s_m1 --out scratchpad/btl2/runs/om_pass0.npz`
- om_pass0 (launch pass as a program) reached mean J 0.131, good 80/80 training and 19/20 validation in the replay by gen 120, but CLOSED LOOP it is worse than A4's
  stroke: pass 1 complete 9/24 on unseen starts (A4 21/24) although the release is as consistent (vz -3.48 +- 0.17, |vh| 2.78 +- 0.15; A4 -3.34 +- 0.11, 2.64 +- 0.16):
  the ball arrives 5-10 cm off the state the left hand's REFLEX stroke is tuned for (bounce (0.25,0.10) instead of (0.20,0.00)). Not a bug: a stage's output has to be
  matched by the next stage. And no consistency gain (A4's pass 1 is already the most repeatable stroke). => keep A4's launch pass; stages start at the return.
- om_left_b restarted (09:5x) on the 80/20 sets with pop 48, batch 10, early-stopped replays, init om_left_b0.npz.
- om_left_b (T0 only, 80 training starts) plateaued at mean J ~2.2 (good 22-28 of 75; validation J 1.9, good 6/19). Per-start J vs the predicted rising crossing position of the arriving ball
  (`corr2.py`): J is small (0.0-0.5) for y 0.33-0.41 and large for y < 0.29 (release too weak: vz -1.6..-2.8, apex 0.47-0.6) and y > 0.41 (leg hits or a miss; y 0.47 no touch): correlation of J with y 0.47.
  A4's pass 1 arrives with y from 0.23 to 0.48 at z 0.62 (its own reflex left hand adapts to that), so a single open-loop table cannot cover it: gain scheduling on the predicted
  arrival (T0 + ux Tx + uy Ty, `oracle_gs.py`, skill `pg_gs`; features: predicted crossing (x, y) from the skill's own sensor prediction) is the next step.
- gs_left_a (started 10:5x): `oracle_gs.py --seeds 801..880 --val 881..900 --ctl bin/challengers/btl2-b1 --init scratchpad/btl2/runs/om_left_b_g100.npz --gens 800 --pop 48 --batch 12 --sigma 0.05 --gsigma 0.05 --workers 2 --out scratchpad/btl2/runs/gs_left_a.npz`
