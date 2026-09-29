# blowup campaign log (agent K, 9/29 continuation of scratchpad/soccer4)

REPRO RECIPE (deterministic; versions: MuJoCo 3.6.0, MyoSuite 2.12.2, numpy 1.26.4, Python 3.12, .venv-myo)
  1. full rollout capture, 16 s wall, bit-identical on every run (checked twice):
       .venv-myo/bin/python scratchpad/blowup/capture.py --params params/myo_soccer_single_leg_310_shc.txt --controller bin/challengers/soccer6-p \
           --seed 91049 --seconds 19 --out out/blowup/r91049_a          # -> "Nan, Inf or huge value in QACC at DOF 6 ... Time = 16.5170"
     (other starts: --seed 89122 --seconds 20 = 15.811 s; 89134 --seconds 140 = 134.214 s; 89135 --seconds 150 = 130.209 s; 89130 --seconds 150 = 141.040 s)
  2. from a 7.5 KB saved MjData state, ~1 s, no controller / arena (playground/repros/):
       .venv-myo/bin/python playground/repros/myosuite_soccer_wrap_nan_state.py [mujoco_wrap_nan_states/r89122_t15.81.npz ...]
  3. pure MuJoCo, no MyoSuite:  .venv-myo/bin/python playground/repros/mujoco_wrap_nan_repro.py [sphere]
  4. the source-level harness:  clang -O2 -o /tmp/wrap_harness playground/repros/mujoco_wrap_nan_harness.c -lm && /tmp/wrap_harness
  5. analysis: replaylib.py (bit-exact replays), analyse_fail.py, hazard_replay.py, nan_band_scan.py, bisect_variants.py, precursor_scan.py, knee_map.py, ring_segments.py, margin_series.py.
  6. the guard and its trials: playground/tasks/myo_soccer_ng.py, scratchpad/blowup/{test_guard,guardscan,add_trials,arena_ng,run_arms,analyse_arms}.py|sh

Goal: the ROOT CAUSE of the "Nan, Inf or huge value in QACC at DOF 6" blow-ups inside motionless one-leg holds of the soccer body
(MyoSuite myoChallengeSoccerP2-v0, MuJoCo 3.6.0, MyoSuite 2.12.2, numpy 1.26.4, .venv-myo), then a fix/measurement, then arena trials.
All state lives in the repo: scratchpad/blowup/, out/blowup/. Nothing in /private/tmp. Rules: max 2 rollout workers, no broad pkill,
diagnostic variants are labelled and never the official environment.

- 08:45 9/29 start. Read O's LOG (soccer4/LOG.md), README round 8, tools. Machine load ~75-80 on 18 cores (other agents' jobs).
  Facts checked in the model (myoChallengeSoccerP2-v0, max_time 310): timestep 0.001, frame_skip 10 (control 100 Hz), solver Newton (2),
  iterations 100, tolerance 1e-8, ls_iterations 50, cone pyramidal (0), impratio 1, integrator Euler (0), jacobian auto (2);
  nq 60 nv 58 nu 290 na 290 ngeom 125 nbody 28 njnt 48 ntendon 290 npair 14 neq 29 nwrap 944.
  DOF numbering: dofs 0-5 = the SOCCER BALL's free joint, dofs 6-11 = the kicker's ROOT free joint (jnt 1, mjJNT_FREE). So "QACC at DOF 6"
  is the root's first translational DOF = the FIRST dof of the player's kinematic tree: mj_checkAcc scans dofs in order and reports the first
  bad one, so it says only "the player's qacc is NaN/huge", not where it started (O's "the root's first free-joint DOF" reading is right
  but it is the ROOT, not a swing-ankle DOF).
- 08:47 REPRO (seed 91049, params/myo_soccer_single_leg_310_shc.txt, controller bin/challengers/soccer6-p): scratchpad/blowup/capture.py runs the arena rollout
  (MyoSim + MyoSoccerTask, P2 env, MAX_TIME 310) with a MuJoCo user-warning callback + a ring of mj_getState(INTEGRATION) per control step; 16 s wall.
  Command: `.venv-myo/bin/python scratchpad/blowup/capture.py --params params/myo_soccer_single_leg_310_shc.txt --controller bin/challengers/soccer6-p --seed 91049 --seconds 19 --out out/blowup/r91049_a`
  -> "Nan, Inf or huge value in QACC at DOF 6 ... Time = 16.5170" (pid 90289 / 92891). The capture holds model.mjb + ring.npz (1651 states) + fail.npz.
- 08:50 !!! MyoSuite GOTCHA (affects every earlier diagnostic, O's blowwarn/contactlog/legforce/chatter included): env.unwrapped.mj_data (= MyoSim.d) is NOT the stepped
  data. MyoSuite's Robot creates its OWN MjData (robot.mj_data, sharing the MjModel) and steps THAT; env.mj_data is a sensor-synced mirror (time/qpos/qvel/act copied, then mj_forward)
  with ctrl = 0 and no solver warmstart. The stepped data is sim.u.robot.mj_data. (The mirror's forward is what the controller sees, hence "CTRL NaN at actuator 239" after the blow-up.)
- 08:52 DETERMINISTIC MINIMAL REPLAY (replaylib.py): model.mjb + ring state 1650 (t = 16.51 s) + the recorded ctrl -> 7 mj_step substeps reproduce the state of the callback
  BIT FOR BIT (qpos/qvel/act/warmstart diff 0.0) and substep 8 (t = 16.517) raises the warning. No controller, no MyoSuite needed.
- 08:53 ROOT CAUSE, LOCALISED: at the failing substep exactly ONE tendon has NaN length: tendon 239 recfem_r_tendon (right rectus femoris = the SWING leg's hip/knee flexor;
  ten_length NaN, ten_velocity NaN, actuator_force NaN at 239; qfrc_actuator NaN on 17 dofs, qacc_smooth NaN on all 52 player dofs -> mj_checkAcc: first bad dof is 6 = the root).
  Its computed wrap points 733/734 (the two tangent points of the cylinder wrap KnExt_at_fem_r_wrap, geom 67, r = 0.025, sidesite 746) are NaN.
  MuJoCo 3.6.0 src/engine/engine_util_misc.c (downloaded to scratchpad/blowup/ref/): wrap_circle -> length_circle: angle = mju_acos(dot(p0n, p1n)) (mju_acos = plain acos, no clamp);
  for a graze (tendon line within ~5e-8 of tangent) the two tangent points are ~1e-8 rad apart, so dot = 1 - 1e-16 rounds to > 1.0 -> acos = NaN; mju_wrap tests `wlen < 0`
  (false for NaN) so the NaN length goes on to L, the moment arms and the actuator force.
  Evidence (scratchpad/blowup/wrapdiag.py, float64 port + 60-digit Decimal of the formulas at the failing state): |tmp|^2 = 0.000624999977699 vs r^2 = 0.000625 (margin +3.6e-8 relative),
  exact 1-dot = 8.8e-17 (< the 1.1e-16 rounding of the dot), the port's dot = 0.9999999999999999 (real MuJoCo's contraction/order gives > 1 -> NaN).
- 08:55 margin_series.py (91049, every 0.5 s): from ~4.5 s on the swing leg's rectus femoris line sits ON the cylinder's tangent boundary: margin (r^2-|tmp|^2)/r^2 alternates
  between +5e-5 (wrapping, arc angle ~1e-5 rad) and -2e-4 (no wrap) from one control step to the next (the swing-ankle limit cycle, period 2 control steps, jitters the leg across it):
  every crossing has a small chance (~5e-8 / 3e-5) to land in the NaN sliver 0 < margin < ~5e-8. So the "chaos, no precursor, rare" of O's blow-ups is the sampling of a
  measure-1e-8 numerical sliver by a leg that chatters over a wrap tangency.
- 08:57 BIT-FOR-BIT: capture of 91049 twice (r91049_a, r91049_b, pids 92891/2701): ring.npz (1651 states x 1019 doubles), ctrl_fail and fail.npz identical; blow-up at 16.5170 both.
  hazard_replay.py: open-loop replay of the whole 1650 control steps (16500 substeps) from ring state 0 with the recorded ctrl matches the ring bit for bit at every step (0 mismatches).
- 09:00 NaN SLIVER MEASURED ON THE REAL LIBRARY (nan_band_scan.py: the failing state, hip_flexion_r swept +-2e-6 rad in 1e-10 steps = 40001 mj_fwdPosition calls, NaN flag of ten_length[239]):
  272 NaN points, all with the wrap active and margin between +4.6e-11 and +5.5e-8; NaN probability by exact (60-digit) 1-dot of the tangent points: <1e-17 30 %, 1-3e-17 20 %, 3-6e-17 14 %,
  6-8e-17 7 %, 8e-17-1.2e-16 5 %, 1.2-1.5e-16 2 %, 1.5-2.5e-16 0.4 %, >2.5e-16 0 % (rounding of the dot product decides; the sliver is 2e-7 rad wide in hip flexion).
- 09:02 hazard_replay.py on 91049 (substep resolution): the swing leg STRADDLES the wrap tangent: 8103 wrapping-active and 8397 no-wrap substeps of 16500; margin < 1e-6: 21 substeps,
  inside the NaN sliver (< 6e-8): 1 survived substep (t = 11.236 s, margin +2.7e-8, 1-dot 4.9e-17, p_nan 0.135) and the fatal one (t = 16.517 s, +3.6e-8, 8.8e-17). Expected events ~0.27 in 16.5 s vs 1 observed.
- 09:06 captures (shc params, soccer6-p) reproduce O's other blow-ups at O's times: 89122 at 15.811 s (11 s wall), 89134 at 134.214 s (86 s wall; pids 8149, 8151); analyse_fail.py: in ALL THREE
  cases (91049, 89122, 89134) the only NaN tendon is 239 recfem_r_tendon, wrap of KnExt_at_fem_r_wrap ACTIVE with margin +3.6e-8 / +9.1e-9 / +2.6e-9 (exact 1-dot 8.8e-17 / 5.8e-18 / 4.6e-19).
  Wall time is ~0.65x real time now (load ~50): 134 s of sim in 86 s.
- 09:09 captures of 89130 (141.040 s; the FIRST warning there is CTRL NaN at actuator 239: the sliver was hit on the state the mirror evaluates at the control-step boundary, so the
  controller read a NaN muscle length; the stepped data hits the same NaN in its first substep) and 89135 (130.209 s): tendon 239 NaN again, margin +2.7e-8 / +1.1e-8. Five of five known
  blow-ups analysed (91049, 89122, 89134, 89130, 89135) = tendon 239, wrap active at margin 2e-9..4e-8. (89103 @255.6 s and the lift entry's 89106 @222 s still to capture.)
- 09:10 scratchpad/blowup/repro_min.py = PURE MuJoCo 3.6.0 MINIMAL REPRO (no MyoSuite/controller): static cylinder + 3 sites + a spatial tendon with a sidesite, geometry of recfem_r/KnExt_at_fem_r_wrap,
  p1.x swept across the tangent in 1e-13 m steps: 859 NaN of 8001 points (all at cut depth >= 0), 0 on the non-wrapping side; the sphere wrap (same wrap_circle) 651 NaN of 8001.
- 09:11 GUARD (playground/tasks/myo_soccer_ng.py, task variant, default-on nudge; env MYO_SOCCER_NANGUARD=0 = count only): scratchpad/blowup/test_guard.py.
  Identity, seed 89101, 25 s, shc params: official / ng0 / ng1 final MjData state BIT-IDENTICAL (hash d2fc375412b33f6b), metrics identical, 0 events.
  Seed 91049, 30 s: official = blow-up at 16.517 s, falls (stand 16.86 s, bal1_raw 14.9); ng0 (count only) = bit-identical to official (hash b98c295b06918615), nan_events 1 at 16.517 (recfem_r_tendon);
  ng1 = ONE nudge (<= 1e-10 rad of the joint angles) and the kicker keeps standing on one leg to 30 s (bal1_raw 28.34): the fall was the NaN event, nothing else.
- 09:16 GUARD v1 (stepped-data nudge only) on the known cases (guardscan.py, jobs_known.json, pid 36231): 89106-lift: official event 222.068 reproduced (nan_first_t 222.068), nudged OK, then a 2nd NaN at 227.740 s
  (5.7 s later: a CONTROL-STEP-BOUNDARY event, MUJOCO_LOG.TXT shows CTRL NaN at actuator 239 first) and a fall at 228.75 s; 89103-shc: event 255.550 reproduced (CTRL NaN first, then QACC) and a fall at 256.57 s.
  LESSON: when the sliver state is the one at a control-step boundary, the observation MIRROR (env.mj_data, what MyoSim reads muscle lengths from) evaluates it first, the controller gets NaN, returns
  NaN for actuator 239 and MuJoCo zeroes ALL controls for the step: nudging the stepped data alone is not enough (~1 event in 10 is of this kind). Guard v2 (myo_soccer_ng.py): on_step checks the mirror's
  ten_length after every control step and nudges stepped data + mirror the same way before the controller reads them, and refreshes obs_dict. Killed the v1 run (own pids), re-running with v2.
- 09:14 bisect_variants.py (91049; out/blowup/bisect_91049.txt): column B (bit-exact state at the failing substep, ONE variant applied to that substep only): every solver / timestep / cone / impratio /
  noslip / islands / implicitfast / dense-Jacobian / warmstart / contacts-off / tibia_r-femur_l-pair-removed / swing-ankle-damping variant still has NaN tendon 239 in mj_fwdPosition (position stage: no solver,
  contact or actuator involved) and the step still resets; only the wrap-radius variants (x(1+1e-6), x(1-1e-3), 0) are finite. Column A (variant for the whole window from 13.5 s): only the unchanged model,
  Newton 500 it / tol 1e-12 and the dense Jacobian (trajectory bit-identical) reproduce the event at 16.517; every other change re-rolls the rounding (no warning), as the sliver mechanism predicts.
- 09:15 the pure C harness (scratchpad/blowup/ref/wrap_harness.c = MuJoCo 3.6.0 is_intersect/length_circle/wrap_circle verbatim, clang -O2 arm64) on the failing 2D inputs + 40001 last-bit sweeps:
  6834 NaN, every one with dot > 1.0 before acos; with dot clamped to [-1, 1]: 0 NaN. Upstream main (fetched 9/29, engine_util_misc.c): length_circle, wrap_circle, wrap_inside, mju_wrap byte-identical to 3.6.0.
  mj_checkAcc (engine_forward.c) resets the data after the warning (unless mjDSBL_AUTORESET) and mj_fwdActuation zeroes ALL ctrl when any is NaN (this is the CTRL-first case).
- 09:19 repro artifacts: playground/repros/mujoco_wrap_nan.md (report), mujoco_wrap_nan_repro.py (pure MuJoCo: 859 NaN of 8001 cylinder points, 651 of 8001 sphere), mujoco_wrap_nan_harness.c,
  myosuite_soccer_wrap_nan_state.py + mujoco_wrap_nan_states/*.npz (5 x 7.5 KB saved MjData states: 91049, 89122, 89134, 89135, 89130; each: warning at the expected substep, NaN tendon 239 at the position
  stage, no NaN after a 1e-10 rad nudge). Also scratchpad/blowup/repro/ (same files).
- 09:22 hazard_replay.py on the other four captures (bit-exact replays, 0 state mismatches): wrap active in 17 % / 21 % / 32 % / 11 % of the substeps (89122 / 89134 / 89135 / 89130); the event was the only sliver
  visit in each 16-20 s window; nearest survived approaches at margin 4.8e-7 / 6.9e-8 / 1.5e-7 / 2.2e-7.
- 09:24 GUARD v2 (stepped-data nudge + mirror repair; playground/tasks/myo_soccer_ng.py) on the six other known blow-up starts (guardscan.py, out/blowup/guard_known2.json, pid 52659): every start hits its
  official event at the official time (89103 255.550, 89106 222.068 + a 2nd at 227.74, 89122 15.811, 89130 141.040, 89134 134.214, 89135 130.209), each nudged (nan_nudged = nan_events), nan_other 0, and every one
  keeps standing to the end of its run (290 / 260 / 50 / 175 / 170 / 165 s). With v1 (no mirror repair) 89103 and 89106 fell within ~1 s of the event: all controls zeroed by MuJoCo's NaN-ctrl rule.
  Also added WrapWatch (per-control-step graze margin of recfem_r / recfem_l, checked against the ring: near3 0.7125 vs 0.7111) to the task's metrics (wrap_r_near3, wrap_r_flips ...).
- 09:24 arena trials added through the arena lock (add_trials.py): soccer_single_leg_310_40_ng (89100-89139, 310 s, bal1_300, task myo_soccer_ng) and soccer_hold20_120_ng (96000-96119, 20 s, hold20; seeds 96xxx
  grep-checked unused anywhere in the repo). Arena wrapper with cache key incl. the task/bridge source bytes: scratchpad/blowup/arena_ng.py.
- 09:25 run_arms.sh started (pid 82188, log out/blowup/arms.log, 2 workers): hold20 seed lift, eval ramp, eval shc; then 310_40_ng seed lift, eval ramp, eval shc. No --promote (decided afterwards from the cache).
- 09:31 STOPPED run_arms.sh (own pids 82188 82206 82210-82212 + controllers) after 45 of 120 hold20 lift rollouts: adding substep-level wrap telemetry to the task (P(NaN | sliver visit) measured live); the cache key includes the task source, so the old rollouts are void; restart follows.
- 09:32 task module v3 (substep-level WrapWatch telemetry: |margin| histograms, survived sliver states with exact 1-dot, expected P(NaN), nan_omd; still read-only): identity re-checked (89101, 25 s, official vs ng1: same MjData hash d2fc375412b33f6b, same wall 19 s); 91049 20 s: 1 event at 16.517 (exact 1-dot 8.8e-17), 2 survived sliver states (4.9e-17 at 11.24 s, 3.3e-16), expected 0.182. run_arms.sh restarted (pid 95639).
