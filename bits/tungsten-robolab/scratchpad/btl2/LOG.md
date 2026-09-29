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
- gs_left_a (gain-scheduled left return, 80 training starts): full-set J 2.18 -> 1.13 (good 22 -> 50/75), validation J 1.92 -> 0.22 (good 6 -> 12/19) by gen 300
  (sep-CMA 816 dims; a first attempt with the repo's SepCMA diverged because that class clips x0 to [0,1] and penalises negative gains: replaced by an unboxed copy).
  Closed loop on 32 unseen starts (901-932): gen 209: pass 2 complete 20/30, apex 0.58, streaks mean 1.53, >=2 on 20; gen 300: pass 2 17/30 (4 leg hits), streaks mean 1.44, >=2 on 17.
  Pass 3 stays 0/21 (the right hand's A4 reflex stroke). The replay's J does not include the right hand's ability to take the ball; the next stage does.
  Feature check: the oracle's predicted crossing (x, y) equals the skill's `receive_state` prediction to 2 mm on 4 starts.
- gs_right_a (started 10:25): stage 1, the right hand's return pass, gain-scheduled: `oracle_gs.py --seeds 801..880 --val 881..900 --params scratchpad/btl2/params/pgLgs_g300.txt --ctl bin/challengers/btl2-b8 --hand r --muscles right_arm --bounce-no 3 --require 2 --t-lo 2.3 --t-hi 2.75 --t-end 3.6 --init scratchpad/btl2/runs/oracle_809_right.npz --gens 600 --pop 48 --batch 12 --sigma 0.06 --gsigma 0.04 --workers 2 --cache scratchpad/btl2/runs/rec_s1 --out scratchpad/btl2/runs/gs_right_a.npz`
- Anchor fix (10:33): `oracle_gs.py` anchors a stage on the skill's own trigger rule (`oracle_multi.trigger_tick`: the first tick after the bounce with the ball off the floor whose
  PREDICTED rising crossing of z 0.62 is within 0.165 s), not on the actual crossing: with the right hand's A4 reflex intercepting the return before z 0.62 the actual crossing does not exist
  (52 of 100 starts were dropped from stage 1's set, biasing it). `--require N` now keeps starts whose first N passes crossed the gate without a leg hit (whoever failed to take the ball is not the question).
  gs_right_a restarted: 53 training / 10 validation starts; gen 119: J 0.79, good 32/53, validation J 1.35 good 4/10.
- First chain with both programs (stages 0+1, `pgLR_a.txt` = g300 left + gs_right_a g240; 32 unseen starts, 5 s): WORSE: pass 2 complete 9/30 (30%; 'body' 11, wrong hand 10),
  pass 3 2/20; streaks mean 1.19, >=2 on 9. Cause: `evaluate` counted leg/arm hits only AFTER the release; the right arm's program brushes the incoming ball with its forearm before
  the palm does (fails the previous pass). Fix: contacts of the ball with anything but the hands before the passer's first touch now count as a hit (J +3 +0.5 per tick). gs_right_b restarted from g240.
- FIRST HONEST STREAKS BEYOND 2 (closed loop, 32 unseen starts 901-932, 5 s, `chain.py bin/challengers/btl2-b8 scratchpad/btl2/params/pgLR_b.txt`): params = A4 + gs left return
  (gs_left_a gen 300) + gs right return (gs_right_b gen 100, trained on the left program's outputs with the corrected objective: forearm/body contacts on the incoming ball before the palm
  touch, sampled at every physics step): pass 1 29/32, pass 2 16/30, pass 3 5/19, pass 4 1/6; streaks [4,3,3,3,3,2 x11,1 x13,0 x3] mean 1.59 (A4: 1.28), max 4, >=3 on 5 starts.
  Residual analysis (`corr3.py`, stage 1 over the recorded starts): valid inputs (left return crossed the gate) have J <= 2.1 on ~80%; failures are returns arriving near the body midline
  (crossing |y| < 0.13: the right forearm hits it) or where the left's own return went wrong. The stages have to be fitted to each other: alternate.
- REPLAY vs CLOSED LOOP mismatch found (seed 902/905, stage 0): replay release (1.85,-1.96,-3.63) vs closed loop (1.58,-1.30,-3.66) with the same program. Two causes:
  (1) the trigger tick differed by one tick on some starts (the replay's `ball_floor` guard used contact forces recomputed by mj_forward, the sensor's are from the last step): now BOTH use the state:
  skill `pg_trigger` skips while ball z < 0.14 (b9), replay `trigger_tick` uses the ball's z before the tick; (2) the gain blocks of the gain-scheduled tables had grown large (CMA unbounded), so a 2 mm
  difference in the predicted crossing (the skill's u vs the replay's u, from the same one-tick offset) moved activations by up to 0.27. Fix: gains bounded to +-1 activation per sigma of the feature (`--gmax`, skill `pg_gmax`),
  feature jitter of 0.1 sigma in training (`--ujit`). gs_left_b restarted from gs_left_a_g300 with these.
- gs_left_b (started 11:5x): `oracle_gs.py --seeds 801..880 --val 881..900 --ctl bin/challengers/btl2-b1 --init scratchpad/btl2/runs/gs_left_a_g300.npz --gens 800 --pop 48 --batch 12 --sigma 0.04 --gsigma 0.04 --gmax 1.0 --ujit 0.10 --workers 2 --out scratchpad/btl2/runs/gs_left_b.npz`
- Two more replay/closed-loop mismatches found and fixed while building a two-stage replay (`oracle_pair.py`, self-test `pair_test.py`: replay of the recorded chain must reproduce the recorded ball path):
  (3) the skill formed T0 + u Tx + u Ty, interpolated, then clipped to [0,1]; the oracle clipped at the knots, then interpolated: the skill now forms and bounds the knot values first (b10) and the
  converter writes T0 unclipped for gain-scheduled tables; (4) THE SENSOR'S BALL POSITION IS ONE PHYSICS STEP STALE: the bridge reads `d.body("ball").xpos` as mj_step leaves it (before the last
  integration), the replay's mj_forward recomputes it: 3 mm at 3 m/s, which shifted the predicted crossing by 1.8 mm and, through large gain terms, the program by up to 0.27 activation. The replay's
  `pred_cross` now uses the recorded stale position. After both, the pair replay follows the recorded closed-loop ball to 0.4-2 mm for 65-120 ticks (was diverging at tick 37).
- gs_left_b stopped (12:02, features were still the biased ones).
- 11:3x coordinator: load is low; up to 4 rollout workers while the 5-minute load average is under 30 (2 above), still one search at a time.
- pair_a (started 11:28, restarted 11:38 with 4 workers): `oracle_pair_search.py` joint search of the left and right returns on the two-stage replay (`oracle_pair.py`), 78 training / 20 validation
  starts, records made closed loop with `scratchpad/btl2/params/pgLR_b.txt` (left gs_left_a g300 + right gs_right_b g100) and btl2-b10. Start: good(pair) 27/78, left good 67/78; the score is the left's release
  (gate, no leg hit, bounce, energy; not its arrival point) plus the right's stroke on the ball the left sends. Output pair_a_L.npz / pair_a_R.npz.
  Command: `oracle_pair_search.py --seeds 801..880 --val 881..900 --params scratchpad/btl2/params/pgLR_b.txt --ctl bin/challengers/btl2-b10 --initL scratchpad/btl2/runs/pair_a0_L.npz --initR scratchpad/btl2/runs/pair_a0_R.npz --gens 600 --pop 64 --batch 16 --sigma 0.03 --gmax 1000 --ujit 0.10 --workers 4 --out scratchpad/btl2/runs/pair_a`
- 12:33 (the harness watchdog stalled this session 11:36-12:33; nothing lost: the skill patch (pg_*) and all tools are in the tree, pair_a kept running):
  pair_a (joint left+right search on the two-stage replay) was stopped at gen 30 after 54 min: 108 s per generation under load (2x the trace, 1632 dims) and no real gain (mean-vector
  full-set J 6.86 -> 6.56, good(pair) 21 -> 19/78, validation 10 -> 8/20). Too slow for what it gives; back to per-stage fits, now with the consistent features (unbiased predicted crossing, state-based
  trigger guard, bounded gains, knot-level clipping), alternating left and right on re-recorded chains.
- Pipeline v2 (12:34): every stage is fitted to be CONTRACTIVE and consistent with the next: tight arrival dead zones (position 2 cm, velocity 0.12 m/s) around the state the next stage works best from,
  each stage fitted on chains recorded with the stages before it in the loop. Order: stage -1 (the launch pass, right hand, gain-scheduled: A4's arrival at the left hand spreads y 0.23-0.48, a program
  that cancels the launch's variation makes everything downstream easier), then 0 (left), 1 (right), then the periodic cycle. New CLI: `--pos-dz --vel-dz --target --vt --no-pre` in oracle_gs.py.
- gs_pass0 (started 12:34, 4 workers, load 21): `oracle_gs.py --seeds 801..880 --val 881..900 --params params/dribble_btl_a4.txt --ctl bin/challengers/btl2-b8 --hand r --muscles right_arm --bounce-no 1 --t-lo 1.35 --t-hi 1.75 --t-end 2.5 --init scratchpad/btl2/runs/om_pass0_g120.npz --gens 400 --pop 48 --batch 12 --sigma 0.04 --gsigma 0.03 --gmax 1.0 --ujit 0.10 --pos-dz 0.02 --vel-dz 0.12 --target -0.13,0.34 --vt -1.5,1.45 --no-pre --workers 4 --cache scratchpad/btl2/runs/rec_s_m1 --out scratchpad/btl2/runs/gs_pass0.npz`
- gs_pass0 (stage -1, the launch pass as a gain-scheduled program, tight targets): after 10 generations: replay full-set J 0.161, good 80/80, validation good 20/20 (feature: the launch ball's predicted crossing,
  nominal (0.52,-0.308), spread only (0.020, 0.021) m: the launch input is very consistent). Stopped at gen ~15 (load 38, 5-min 31: back to 2 workers). `pgP0.txt` = A4 + gs_pass0_g10 as pass 0 (pg_first 0):
  closed loop, downstream still A4's reflex left hand, 16 unseen starts: release 1 vz -3.61 +- 0.15, |vh| 2.82 +- 0.13 (A4 -3.34 +- 0.11, 2.64 +- 0.16); pass 1 complete 8/16 (the reflex left hand cannot take it).
- gs_left_c (started 12:45, 2 workers): stage 0 (left) fitted with stage -1 in the loop (`--params scratchpad/btl2/params/pgP0.txt --ctl bin/challengers/btl2-b11`, records in rec_s0v2), tight arrival
  targets (0.45,-0.25) / (1.5,-1.5) m/s with dead zones 3 cm / 0.15 m/s, init gs_left_b_stop, gmax 1, ujit 0.1: `oracle_gs.py --seeds 801..880 --val 881..900 --hand l --muscles left_arm --bounce-no 2 --t-lo 1.70 --t-hi 2.40 --t-end 3.0 --require 1 --init scratchpad/btl2/runs/gs_left_b_stop.npz --gens 500 --pop 48 --batch 12 --sigma 0.04 --gsigma 0.04 --gmax 1.0 --ujit 0.10 --pos-dz 0.03 --vel-dz 0.15 --target=0.45,-0.25 --vt=1.5,-1.5 --workers 2 --cache scratchpad/btl2/runs/rec_s0v2 --out scratchpad/btl2/runs/gs_left_c.npz`
- ARENA: new trial `dribble_btl_streak_fresh32` (32 fresh starts, seeds 1101-1132, never used in any tuning; added to trials.json, no existing entry changed) seeded with A4
  (controller bin/challengers/dribble_btl-a2, params/dribble_btl_a4.txt, --task dribble_btl_v3): btl_streak mean 1.2188 +- 0.27, btl_rate 0.122.
- 12:5x resume after the watchdog stall: the cosmetic skill edit (comments/header only) compiles to the same binary (`./build.sh dribble_btl` "(cache)", sha1 equal to
  bin/challengers/btl2-b11); A4 params replay bit-identically on b11 (seeds 601, 705, 716; `scratchpad/btl/identity.py dribble_btl_v3 params/dribble_btl_a4.txt
  bin/challengers/dribble_btl-a2 bin/challengers/btl2-b11 <seed> 8`).
- gs_left_c gen 19: mean-vector full-set J 2.29 good 27/60 (start 9.11, 0/60), validation J 2.02 good 9/19. Load 27-32: 2 workers.
- Arena, banked while stage 0 runs (2 more workers, load 5-min 28): pgLR_b (the first ORACLE chain, A4 + gs left g300 + gs right b g100) with btl2-b8 on `dribble_btl_streak_fresh32`
  (`arena.py eval dribble_btl_streak_fresh32 --params scratchpad/btl2/params/pgLR_b.txt --controller bin/challengers/btl2-b8 --task dribble_btl_v3 --workers 2 --note "ORACLE ..."`, log runs/arena_pgLR_b_fresh32.log).
- ARENA RESULT (12:52, not promoted yet): `dribble_btl_streak_fresh32`, pgLR_b (ORACLE, btl2-b8): btl_streak 1.5000 +- 0.278 (A4 champion 1.2188), paired diff +0.281, sign-flip p = 0.019 (a win by the arena's rule).
  Per start (chain.py 1101-1133, 15 s, log runs/chain_pgLR_b_fresh32.log): streaks [3,3, 2 x16, 1 x10, 0 x4] (mean 1.50, >=2 on 18, >=3 on 2); pass 1 28/32 ok, pass 2 18/29 (62%),
  pass 3 2/21 (10%: 19 x bounces_or_wrong_hand, rise apex 0.55), pass 4 0/2. The right hand's return stage (pass 3) is the weak link of pgLR_b: it was fitted to the wrong arrivals.
- gs_left_c gen 29: full-set J 1.81 good 26/60, validation J 1.24 good 11/19.
