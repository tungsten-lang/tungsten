# hazard campaign log (agent Z, 9/29 evening): an OFFICIAL, UNGUARDED 300 s one-leg hold that avoids the MuJoCo wrap tangent

Goal: `soccer_single_leg_310_40` (official: unmodified `myo_soccer`, .venv-myo) at 39 or 40 of 40 (and on fresh starts), by a controller whose
swing leg's right rectus femoris line stays off its wrap tangent (recfem_r_tendon, cylinder KnExt_at_fem_r_wrap, MuJoCo 3.6.0 `length_circle` NaN).
State lives in the repo: this log, `scratchpad/hazard/` (tools), `out/hazard/` (rows, jobs, series), `params/hazard/` (params). No /private/tmp, no commits.
Rules read: playground/arena/README.md; freeze a COPY of a binary to `bin/challengers/soccer7-<tag>`; workers <= 6 while the 5-min load < 12, 4 below 30, 2 above.

SEEDS LEDGER (soccer starts; table tennis's tt_p2 uses 97000-97099 on a different env, so I stay at 97100+; the arena trials use 89100-89139 and 96000-96119: scoring only)
  97100-97399  practice (margin maps, searches, fits)
  97400-97519  validation A (120 fresh hold20 starts; first use = the claim run of a candidate)
  97520-97639  validation B (120 fresh hold20 starts)
  97700-97819  official-environment 120-start 310 s scan (last)

TOOLS (mine): wscan.py (jobs -> rows: guarded task, count-only NaN mode by default, per-control-step margin + swing-leg joint telemetry, exposure e4/e3),
  mkjobs.py / mksweep.py (job files), summ.py (per-config summary). Rows are read-only telemetry: rollouts are bit-identical to the plain guarded task's.

- 18:20 start. Read README rounds 8-10, blowup/{FINAL_REPORT,LOG,RESULTS}.md, repro note, HANDOFF. Load 3.5 on 18 cores (quiet): a 20 s rollout takes 8.5 s wall with 6 workers, 8 s = 3.3 s.
- 18:27 REPRODUCTION of K's exposure (count-only mode, 20 s, 8 fresh practice starts 97100-97107, per entry; rows out/hazard/rows_expo0.jsonl):
    `.venv-myo/bin/python scratchpad/hazard/mkjobs.py out/hazard/jobs_expo0.json 20 97100:97108 lift=params/myo_soccer_single_leg_310_lift.txt:bin/challengers/soccer5-lift ramp=params/myo_soccer_single_leg_310_ramp.txt:bin/challengers/soccer6-i brake=params/myo_soccer_single_leg_310_shc.txt:bin/challengers/soccer6-p`
    `.venv-myo/bin/python scratchpad/hazard/wscan.py --jobs out/hazard/jobs_expo0.json --out out/hazard/rows_expo0.jsonl --workers 6`  (35 s wall for the 24 rollouts)
    exposure = fraction of the watched substeps (t >= 3 s) with |margin of recfem_r| < 1e-4: lift falls at 97104/97105 (real, as in K's lift), the other 6: 0.00-0.72 %; ramp 0.07-19.4 %; brake 0.03-19.4 % (97103: 19.4 % of the hold within 1e-4, 67 % within 1e-3: a strong hoverer, identical under ramp and brake).
- 18:40 FIRST FINDINGS from per-control-step series (30 s brake holds, seeds 97100/97101/97103, out/hazard/series/brake_<seed>.npy: t, margin_r, margin_l, hf_r, ha_r, hr_r, kn_r, an_r, sub_r, hf_l, ha_l, kn_l):
    the swing leg's mean posture is fixed (hip flexion -0.185, knee 1.675, ankle 0.22) but the margin of recfem_r swings between about -2.4e-2 and -2e-3 (sd 7e-3, step-to-step 2-6e-4):
    dmargin/dknee = +2.5 per rad at the tangent (knee_map.py on the 91049 capture: tangent at knee_angle_r 1.693, parked 1.678), so 3e-3 rad of knee chatter = 7e-3 of margin.
    Start-to-start the late mean margin differs from -1.4e-2 to +3e-3 because hip adduction (-0.056..-0.097) and rotation (-0.03..-0.12) of the parked swing hip differ per start; the knee (1.674-1.677) barely does.
    Working hypothesis: the swing shank rests on the stance thigh (contact), so the parked knee angle sits (by geometry) within ~0.02 rad of the RF tangent; the hold is a limit cycle across it.
- 18:50 !!! GEOMETRY (geom.py on the 91049 capture, `.venv-myo/bin/python scratchpad/hazard/geom.py out/blowup/r91049_a`): margin of recfem_r at the parked state -1.46e-4; sensitivities dmargin/dq:
    knee_angle_r (leader, followers moved along the model's joint equalities) +2.50 per rad; raw coordinates: knee_angle_r_beta_translation1 (the PATELLA's follower coordinate) -73.8 per METRE (0.074 per mm),
    hip_flexion_r -0.27, hip_rotation_r +0.11, hip_adduction_r +0.013, ankle / subtalar / left leg / trunk 0. With the followers reset to their polynomial values the margin would be -3.76e-2, so the parked state's
    patella coordinate is 0.5 mm off its rigid-coupling value (the joint equality is soft; the quadriceps force stretches it): the margin = polynomial(knee, hip) + 73.8 x (patella stretch).
    So the hover at the tangent is a force feedback through the soft patella equality (wrap -> longer tendon -> reflex force -> patella stretch -> line off the cylinder), a sliding-mode equilibrium at the kink of the wrap.
- 18:52 LOAD JUMPED to 45-48 (other agents; 5-min 17): the first 6-worker sweep stalled (a batch of 12 s rollouts took 1084 s wall); stopped my own tree (pids 75173 ...), resumed with 4 workers (pid 76720; wscan.py is resumable by tag).
- 18:53 sweep sw1 (one-at-a-time, brake base, 8 practice starts 97100-97107, 12 s): b_sw_knee 1.2 / 1.5 / 1.7 (base 1.8) give late mean margin -1.36 / -0.61 / -0.21 (base -5e-3), e4 = 0 in every start, all 8 starts stand 12 s: the swing knee COMMAND moves the parked knee (2.5 per rad) far off the tangent.
    `.venv-myo/bin/python scratchpad/hazard/mksweep.py out/hazard/jobs_sw1.json 12 97100:97108 params/myo_soccer_single_leg_310_shc.txt bin/challengers/soccer6-p b_sw_knee=1.2,1.5,1.7,1.9,2.0,2.1 b_sw_th=-0.1,0.0,0.1,0.25,0.35,0.5 b_sw_add=-0.1,0.0,0.03,0.1,0.15,0.2 b_sw_ankle=0.0,0.15,0.25,0.4 fy_splay=-0.2,-0.1,0.1,0.2 k_leg=22,26,34,40 sb_ksw=0.5,1.0,3.0 stiff_l=0.02,0.09`
    `.venv-myo/bin/python scratchpad/hazard/wscan.py --jobs out/hazard/jobs_sw1.json --out out/hazard/rows_sw1.jsonl --workers 4`  (rows out/hazard/rows_sw1.jsonl; summary: summ.py)
- 19:25 sweep sw1 partial (179 of 288 rows; 8 starts x 12 s, brake base; summ.py): late mean margin of recfem_r [max over steps in the last 5 s], falls of 8:
    base -4e-3 [-2e-4] 0 falls, e4 2.85 %;  b_sw_knee 1.2 -1.36 / 1.5 -0.61 / 1.7 -0.216 [-0.204] / 1.9 +0.190 [+0.205] (0 falls each), 2.0 +0.38 (1 fall), 2.1 +0.50 (2 falls): e4 = 0 in all of them (margin sd 7e-3).
    b_sw_th (swing thigh world angle; base 0.1735): 0.25 -0.0439 (sd 1.9e-4, 0 falls of 16), 0.1 +0.014 (e4 0.33 %), 0.0/-0.1 falls 2-3, 0.35 +0.06 (2 falls), 0.5 falls 6 of 10.
    b_sw_add -0.1 -0.012 (e4 0.25 %), 0.0 -0.020 (sd 1e-4).  The swing knee command is the lever (base 1.8 sits on the tangent: parked knee 1.6755 vs tangent ~1.69).
- 19:30 wscan.py gained an all-segment watch (AllSegs, vectorised margins of all 68 wrapped segments at control-step resolution; seg_top / seg_rf_near3/4 / seg_oth_near3/4): identical to K's WrapWatch on recfem_r (12 s brake 97103: near3 0.5316, near4 0.1876), no other segment within 1e-3 in that hold.
- 19:41 load 59 (1-min) / 37 (5-min): sweep restarted with 2 workers (pid in out/hazard/sw1c.pid; log out/hazard/sw1c.log), resumable by tag.
- 19:47 !!! MY MISTAKE (logged for the coordinator): my two "stop the sweep" commands (18:50, 19:24) did NOT stop anything: in zsh `kill $PIDS` / `for p in $PIDS` pass a multi-pid string as ONE word (no word splitting; use `${=PIDS}`),
    errors hidden by 2>/dev/null. So THREE sweeps ran concurrently from 18:30 (pids 75173: 6 workers, 76720: 4, 78717: 2 = 12 rollout workers, over the 6-worker cap) and drove the machine load to 72 (1-min) for ~1 h, which is why rollouts stalled
    (wall 900-1080 s for 12 s of sim) and why rows_sw1.jsonl has 395 rows / 247 unique tags (deterministic duplicates; summ.py keeps the last row per tag). All three trees were killed properly at 19:47 with `kill ${=ALL}` (verified: 0 wscan processes left).
    Rule for the rest of the campaign: only ever start one search / scan, verify with `pgrep -f`, kill with ${=PIDS} and check `kill -0` output.
- 19:46 SOURCE EDIT (myo_soccer_v4.w, opt-in, default off): `bhold 1` (+ bh_dknee, bh_dth, bh_dank, bh_dadd, declared only when on): the hold chunk (b_hold_<st>, add_catch_leg only) takes the lift posture plus shifts of the PARKED swing leg's knee / thigh /
    ankle / hip adduction, so the lift stays bit-identical and only where the leg parks moves (helper `hold_posture(st)`; when off the SAME posture object is passed as before). Built: `./build.sh myo_soccer_v4` (2 min; log out/hazard/build_bhold.log),
    frozen copy bin/challengers/soccer7-bh1 (5652232 bytes; the previous live binary == soccer6-p, 5652184 bytes). TODO: replay identity of the lift / ramp / brake params against soccer6-p (metrics of the same starts must be equal to the digit).
- 19:51 IDENTITY (default-off `bhold` build): lift / ramp / brake params on bin/challengers/soccer7-bh1, 8 starts 97100-97107 x 20 s (24 rollouts, `wscan.py --jobs out/hazard/jobs_id1.json --out out/hazard/rows_id1.jsonl --workers 3`, 3.4 min) vs the same rollouts on the old binaries
    (soccer5-lift / soccer6-i / soccer6-p, out/hazard/rows_expo0.jsonl): 0 of 24 differ in 15 exact-equality keys (stand_time, bal1_raw, fallen, t_fall, wrap_r_hist substep histogram, pr_* posture statistics, nan_events ...): replay is bit-identical.
- 19:52 SCREEN 1 (candidates on 60 practice starts 97100-97159, 20 s, guarded task count-only, new binary; one process, 4 workers; pid out/hazard/scr1.pid, rows out/hazard/rows_scr1.jsonl, log out/hazard/scr1.log):
    arms B0 = brake (shc params), K17 = b_sw_knee 1.7, H1 = bhold 1 + bh_dknee -0.1 (lift keeps 1.8, hold parks 1.7), K19 = b_sw_knee 1.9, T25 = b_sw_th 0.25.
    `mkarms.py out/hazard/jobs_scr1.json 20 97100:97160 B0@P@C K17@P@C@b_sw_knee=1.7 H1@P@C@bhold=1,bh_dknee=-0.1 K19@P@C@b_sw_knee=1.9 T25@P@C@b_sw_th=0.25` (P = params/myo_soccer_single_leg_310_shc.txt, C = bin/challengers/soccer7-bh1)
    summary: `armsum.py out/hazard/rows_scr1.jsonl --ref B0`
- SWEEP sw1 RESULT (8 starts x 12 s, brake base; late-5 s mean of the margin, its sd, and whole-run exposure e4 / e3 = substeps within 1e-4 / 1e-3 of the tangent; parked swing knee kn_r):
    knob (value)  -> margin: b_sw_knee 1.2 -1.36 | 1.5 -0.61 | 1.7 -0.216 (kn 1.592) | 1.8 base -4e-3 (kn 1.6755, e4 2.85 %, e3 11.2 %) | 1.9 +0.19 (kn 1.765) | 2.0 +0.38 (1 fall) | 2.1 +0.50 (2 falls)   slope +2.0 per rad of command;
    b_sw_th 0.25 -0.044 (sd 1.9e-4: NO chatter, 0 falls) | 0.1 +0.014 (e4 0.33 %) | 0.0 / -0.1 +0.03 (1 / 3 falls) | 0.35 +0.06 (hip rotation +0.40, 1 fall) | 0.5 +0.30 (4 falls of 8);
    b_sw_add 0.0 -0.020 (sd 1e-4) | 0.03 -0.009 | 0.1 +9e-4 (e4 0.5 %) | 0.15 +0.015 | 0.2 +0.036   slope +0.2 per rad;   b_sw_ankle 0.0 / 0.15 +2e-3 (e4 1 %) | 0.25 -0.012 | 0.4 -0.030;
    k_leg 22 -0.104 (kn 1.640) | 26 -0.067 | 34 +0.018 | 40 +0.073 (slope +8e-3 per unit);   fy_splay -0.2 0 (e3 30.6 %: the worst) ... +0.2 -0.011.
- 20:49 (resumed after a harness watchdog stop; coordinator rules: no foreground command over ~4 min, 4 workers only while the 5-min load < 15, 2 between 15 and 30, no new launch above 30, one search at a time, own pids only)
    State check: the sw1 sweep trees (75173, 76720, 78717) were dead since 19:47; the only wscan process was the screening scan 84044 (4 workers, 150 of 300 rows): stopped it at 20:49 (own tree, `kill ${=ALL}`, 0 wscan processes left; resumable by tag: rows out/hazard/rows_scr1.jsonl).
    SCREEN 1 PARTIAL (20 s, 60 starts 97100-97159 per arm, guarded count-only, new binary; `armsum.py out/hazard/rows_scr1.jsonl --ref B0`):
      B0 (brake) 59 / 60 (97136 falls at 3.6 s), e4 0.87 %, e3 11.1 %, e2 65 %, margin(recfem_r) late median -5.9e-3;
      K17 (b_sw_knee 1.7)   59 / 60 (the SAME start 97136 at 3.6 s: a shift/lift fall, unchanged), e4 = e3 = e2 = 0 for recfem_r (margin -0.213) ...
      !!! BUT with the all-segment watch the SAME cylinder's other muscles show up: in K17, vasmed_r_tendon (medial vastus, cylinder KnExt_at_fem_r_wrap) is within 1e-3 of its tangent in 9-13 % of the control steps
          in the worst starts (near4 up to 2.7 %, 24-37 tangent crossings per start; 20 of 60 starts list it as their top segment): the knee shift moved the hazard from recfem_r to vasmed_r.
          Each of the four KnExt muscles (recfem, vasint, vaslat, vasmed) has its own tangent knee angle; a safe swing knee must be clear of ALL of them (and of the swing leg's other wraps).
      H1 (bhold, lift 1.8 -> hold 1.7) 9 of 60 rows: vasmed_r near3 only in 2 of 9 starts (0.6 %, 0.1 %): the lift keeps the leg's approach different, to be measured on all 60.
    Next: per-segment statistics (mean, sd, near2) in wscan2.py, then a knee-command sweep with all 68 segments (which knee bands are free of every tangent), 2 workers.
- 20:52 OFFLINE MAP of every right-leg wrap segment vs the swing knee angle (kneeseg.py on the 91049 capture: `.venv-myo/bin/python scratchpad/hazard/kneeseg.py out/blowup/r91049_a`, hip posture of that state,
    followers moved along the joint equalities, second variant keeping the state's force-stretch deviation). Tangent knee angles in [0.9, 2.1] rad (stretch kept / pure polynomial; slope of the margin per rad):
      bfsh_r 1.283 / 1.284 (0.98) | vaslat_r 1.447 / 1.461 (2.12) | vasmed_r 1.602 / 1.621 (1.88) | vasint_r 1.646 / 1.664 (1.97) | recfem_r 1.678 / 1.693 (2.46);   all other right-leg wraps (adductors, gastrocnemii, hamstrings, gracilis, glmax3, iliacus): none in the range.
    The base parks the swing knee at 1.6755 = ON recfem_r's tangent (1.678). b_sw_knee 1.7 parks it at 1.592 = 0.010 rad from vasmed_r's tangent (the hover the all-segment watch found).
    Knee bands free of every tangent by >= 0.07 rad: below ~1.21, [1.36, 1.38] (between bfsh and vaslat, 0.08 each side), [1.52, 1.53] (between vaslat and vasmed, 0.078 each side), and above ~1.75 (all four margins positive, recfem +0.19 at 1.7646).
    Parked knee vs command (sw1): 1.2 -> 1.1675, 1.5 -> 1.449, 1.7 -> 1.5917, 1.8 -> 1.6755, 1.9 -> 1.7646, 2.0 -> 1.8607, 2.1 -> 1.9288: so b_sw_knee ~1.4 parks at ~1.355, ~1.6 at ~1.52, 1.9 at 1.765.
- 20:51 knee-command sweep with all 68 segments: `mkknee.py out/hazard/jobs_knee1.json 12 97100:97106 shc-params soccer7-bh1 7 b_sw_knee 1.2,1.3,1.4,1.5,1.55,1.6,1.65,1.7,1.75,1.8,1.85,1.9,1.95` (78 rollouts, segment stats from t >= 7 s via WSCAN_TFROM),
    `wscan2.py --jobs out/hazard/jobs_knee1.json --out out/hazard/rows_knee1.jsonl --workers 2` pid 96793 (log out/hazard/knee1.log). wscan2.py = wscan.py + segv_* per-segment stats + inter-leg contact force (pr_legf_*).
- 21:13 KNEE-COMMAND SWEEP WITH ALL 68 SEGMENTS (rows out/hazard/rows_knee1.jsonl, 6 starts 97100-97105 x 12 s per command, segment stats over t >= 7 s; `kneesum.py out/hazard/rows_knee1.jsonl`; brake params, soccer7-bh1):
    b_sw_knee -> parked knee_r, inter-leg contact force (late third), and the segments that spend > 2 % of the window within 1e-2 of their tangent (worst start):
      1.2 -> 1.168, 163 N: none | 1.3 -> 1.270, 177 N: bfsh_r 67 % within 1e-2 (min |m| 7.7e-7, 34 crossings) + a TRUNK tendon LTpL_L1_r (17 %, min 8e-5, 12 crossings) | 1.4 -> 1.359, 191 N: none | 1.5 -> 1.449, 207 N: none | 1.55 -> 1.492: none | 1.6 -> 1.530, 204 N: none | 1.65 -> 1.562: none |
      1.7 -> 1.592, 212 N: vasmed_r 37 % within 1e-2 (never within 1e-3: min 3.5e-3) | 1.75 -> 1.629: none | 1.8 (base) -> 1.6757, 218 N: recfem_r 92 % within 1e-2, 81 % within 1e-3, min 2.9e-7, 108 crossings |
      1.85 -> 1.719, 218 N: none | 1.9 -> 1.764, 220 N: none | 1.95 -> 1.810, 223 N: none.   All 6 starts stand 12 s at every command (0 falls in 78).
    So the static map (kneeseg.py) is right: hovering happens where the parked knee sits within ~0.01-0.02 rad of a tangent; the free bands are command 1.4-1.65 (not 1.3, not 1.7) and command >= 1.85. The base 1.8 is the worst spot, 1.7 the second worst.
    Candidates for the guarded 20 s screens: K16 (1.6, contact 204 N), K19 (1.9, 220 N: the contact of the champion is kept), T25 (b_sw_th 0.25).
- 21:14 SCREEN 2 (K16, K19, T25 on 60 starts 97100-97159 x 20 s, all-segment watch t >= 3 s, 4 workers because the 5-min load fell to 14): `mkarms.py out/hazard/jobs_scr2.json 20 97100:97160 K16@P@C@b_sw_knee=1.6 K19@P@C@b_sw_knee=1.9 T25@P@C@b_sw_th=0.25`,
    `wscan2.py --jobs out/hazard/jobs_scr2.json --out out/hazard/rows_scr2.jsonl --workers 4` pid 99471 (out/hazard/scr2.pid, log out/hazard/scr2.log). Compare against B0 / K17 rows of rows_scr1.jsonl (same seeds, same telemetry-only difference).
    NOTE on the freezes: the machine (my shell included) freezes for 8-18 min at times (a `sleep 25` loop returned after 9 min, rows stood still): bounded polls only, every run resumable.
