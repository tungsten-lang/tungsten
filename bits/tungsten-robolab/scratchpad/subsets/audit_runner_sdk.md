# Subset-keyframe audit: runner / sprinter controllers and the SDK core (AREA runner_sdk)

Read-only audit on 30 Sep 2026 (paths are under `bits/tungsten-robolab/`). The report is written incrementally: part (b), the SDK core, comes first because it is settled by reading the code; part (a), the runner and sprinter keyframes, follows one section per element.

## (b) SDK core: what a chunk, a pose and a skill do with a joint that is left out

### B1. The chain from `Pose` to the commanded vector (verified by reading)

- A skill builds a `Pose` (`lib/robolab/contraction.w:107-117`): `Pose#set(joint, q, stiff = 0.0)` pushes one (joint, angle, stiffness) triple. There is no other field, so a pose cannot say "this joint is free", only "this joint is at q".
- The pose is the goal of a chunk through `Chunk#pose(p)` (`chunk.w:97-100`). `Chunk#goal_from` (`chunk.w:218-228`) copies the chunk's start vector, asks the pose for `posed = @goal.apply(body, start)` and overwrites only the muscles of the track mask with `posed`. Muscles outside the track mask keep their start value.
- The start vector is the live command (`controller.w:58`, `@start = ctl.command.copy`). Only at the very first tick is the command the measured contraction (`controller.w:644-648`, `@command[i] = frame.c(i)`).
- Between start and goal every muscle of the mask moves together along the chunk easing (`controller.w:197-199`, `cmd = st + (gl - st) * p`). A muscle whose goal equals its start therefore does not move at all.

### B2. What "left out" means, in the two body models (verified)

1. **Body without geometry** (`contraction.w:139-144`): only the joints named in the pose are written with `set_joint`; every other muscle keeps the base (start) value. A left-out joint is HELD at whatever its pair of muscles was commanded at the chunk start.
2. **Body with geometry** (`contraction.w:146-169`, the multi-joint bodies such as the runner's): the doc comment says it plainly: "every muscle crossing a posed joint gets the contraction it has at the posture (unposed joints at the reference posture), plus half the largest stiffness among its posed joints". Line 151 starts from `q = g.reference_posture` (the body's `qref`, `body.w:259-260`), line 159 overwrites the posed joints, line 167 writes `g.contraction(m, q)` for every muscle that crosses a posed joint. `Body#length` (`body.w:284-293`) sums the table lookups of every joint the muscle spans, so the unposed joint of a two-joint muscle enters at its reference angle.
   - Muscles that cross ONLY unposed joints: held at the start command (B1).
   - Muscles that cross a posed and an unposed joint (hip-knee, knee-ankle and hip-spine muscles): computed with the unposed joint at its REFERENCE angle, not held and not interpolated. So "leave the knee out" does not mean "don't care about the knee": it silently asks every hamstring, rectus femoris and gastrocnemius that also crosses a posed joint to act as if the knee were at qref.

### B3. Consequence for a subset keyframe

Omission gives two different behaviours at once (hold for single-joint muscles, reference angle for two-joint muscles). Neither is "free, interpolating between the neighbouring keyframes that pin the joint", which is what the Keyframe Bench's `pinned` map promises. Today the only expressible subset keyframe is therefore "fill every free joint with a value the skill computes itself" (for example the min-jerk value between the neighbouring keyframes that pin it); the flag is then inert in the SDK, it lives in the skill.

### B4. Proposed subset-keyframe API (sketch, 3 to 6 lines of Tungsten; detailed in section B5 below when written)

```
+ Pose
  -> free(joint)              # not pinned here: resolved later, never written by omission
+ Movement
  -> resolve_free(body, times)  # for each free (keyframe, joint): min-jerk between the nearest
                               # earlier and later keyframes that pin it, by keyframe time or phase
```
`resolve_free` would run once in `start` (after the phases and durations are known) and turn every `free` into an ordinary `set(joint, q, stiff)`, so `apply_geometry` needs no change and the two-joint muscles see the interpolated angle instead of qref.

## (a) Runner and sprinter controllers

### A0. Which controllers are the champions (playground/arena/champions.json)

- `run_natural_erik3_48` (the trial that scores Erik's set 3 on 48 held-out starts): controller `bin/challengers/rn2-kf3` = `RunNaturalSkill` (`lib/robolab/skills/run_natural.w`), params `params/search/rn2_erik3_nohr.txt` (champions.json:4838-4843). Six chunks per stride, keyframes td / ms / to only (no `ref_hr_phase`, no `ref_kl_phase` in the params, so `step_keyframes` (`run_natural.w:459-482`) returns the three main ids and `start` takes the explicit six-chunk path, `:145-150`). Held out 7101-7148: 1 fall, kin_rms 19.78 (`playground/search_results/p7b/eval_7101-7148.jsonl`, label `rn2_nohr`: kin_hip 16.9, kin_knee 47.9, kin_ankle 24.0, kin_trunk 5.1, kin_shoulder 20.5; event error TD 38.8, MS 27.8, HR 16.7, TO 16.4, KL 14.4 deg).
- `run_natural_erik3`: `run_knots-p7` (`lib/robolab/skills/run_knots.w`), params `params/search/runknots_erik3_nohr.txt`: posture keyframes plus a learnt knot residual; HR is dropped from the reference it is trained toward, KL is only a scoring target (champions.json:4791-4796; `playground/SEARCH.md:1143-1177`).
- `run_natural` (literature curves) is the P7 knot runner on `params/search/runknots_lit_legs.txt` (champions.json:4609-4614); `run_natural_fast` is `sprint_touch-r2` (`:4921-4926`); the sprint family: `sprint_top_speed_v4_p95` = `run_gearx-a` five gears, `params/run_gearx_v4_p95_x5a.txt` (`:6439-6444`); `sprint_bolt_form` / `sprint_blocks_*` = `sprint_blocks-p95form` (`:6131-6136`).
- Erik's set 3 (`params/keyframes_erik3.txt`) has five ids: td 0 %, ms 18 %, hr 30 %, to 36 %, kl 38 % (`:4, :19, :34, :49, :64`). The champions never run hr as a controller keyframe; they run only td / ms / to (rn2) or td / ms / to plus mids (P7).

### A1. What every run_natural keyframe poses (applies to td, ms, to, hr, kl)

- `RunNaturalSkill#keyframe` (`run_natural.w:388-406`) writes a Pose of 13 joints: r/l hip_flex, knee, ankle, toe (8), r/l shoulder_flex, elbow (4), spine_flex. Nothing is ever left out, so no joint is "free" today. The 14th Bench channel, pelvis, is not a command at all: `ref_*_pelvis` only feeds the torso servo's targets through `trunk_targets_from_keyframes` (`:424-441`).
- Stiffness is per group, not per joint: `stiff_st` (stance leg including toe), `stiff_sw` (swing leg including toe), `stiff_up` (arms and spine) (`:393-405`). Champion: stiff_st 0.335, stiff_sw 0.018, stiff_up 0.0 (`rn2_erik3_nohr.txt:121-123`).
- The commanded posture is reference plus a searched offset per leg joint (hip, knee, ankle only; toe, arms and spine carry no offset): `command = ref + d_<kf>_<st|sw>_<joint>` (`run_natural.w:179-184, 393-399`). Champion offsets (`rn2_erik3_nohr.txt:12-30`, box +-60 deg hip, +-40 deg knee/ankle, `lim_td_st_hip 90`, `lim_td_st_ankle 80` at `:68-69`): td st hip -53.1, knee -39.2 (box edge), ankle -20.2; td sw hip +48.1, knee +37.7 (box edge), ankle -15.9; ms st hip +42.0, knee -23.6, ankle +9.1; ms sw hip -58.4 (box edge), knee +22.9, ankle +11.7; to st hip -40.3, knee +14.6, ankle -17.8; to sw hip -7.1, knee -3.9, ankle -36.7 (near the box edge). The command is therefore a long way from the reference ("the learnt command sits 15-30 deg away from the target, as it must", `playground/SEARCH.md:986-989`); practice scores the ACHIEVED kinematics against the reference (`run_natural.w:61-65`).
- Real-time corrections ride on top and override some keyframe joints: stance hip blends toward the measured angle with `w_hip` (0.21 in the champion, `rn2_erik3_nohr.txt:137`) plus a clamped trunk PD (`run_natural.w:950-979`); the swing hip holds its world-frame thigh angle (`comp` 0.74, `:965`); in flight the landing hip is placed by speed error and `retract`, the trailing hip is the torso's reaction mass (`:956-963`); the stance knee is pushed straighter below `z_ref` (`k_zk` 0.037, `:966-968`). Toe, ankle, swing knee, arms and spine are never corrected: they run on the keyframe alone (plus the reflex layer).
- The stance push is mostly ACTIVATION-driven, not pose-driven: `push_drive` adds feed-forward bursts on the stance knee extensor, ankle plantarflexor, gastrocnemius, hip extensor and hamstring (`run_natural.w:908-912, 920-931`), champion drv_knee 0.65, drv_ankle 0.60, drv_gas 0.62, drv_hip 0.43, drv_ham 0.56 (`rn2_erik3_nohr.txt` lines with those names), and `drv_lift` (swing hip flexor during the push) is 0.0 (`:40`).
- What the score sees: `kin_rms` is the mean over six groups hip, knee, ankle, trunk, shoulder, elbow (`playground/tasks/run_natural.py:72, 35-37, 612-621`); `event_rms` excludes every toe channel, pelvis and spine_flex (`:668-669`). **The toe is commanded at every keyframe but scored nowhere.**

### A2. The toe-off keyframe `to` (Erik's example) in the champion

- **Definition.** `params/keyframes_erik3.txt:49-63`; used as the goal of the `r_drive` chunk (MS -> TO) and, mirrored, of the left step (`run_natural.w:147, 150`, `drive_chunk` `:734-742`); the chunk ends on the foot's release (`Latch.release`, after_min 0.03 s, timeout `t_drive_max` 0.187, `:737-738`); champion t_drive is 0.038 s (`rn2_erik3_nohr.txt:125`), so the command reaches the TO posture in 38 ms and then HOLDS it until the foot leaves the ground. Values (deg): stance hip -17.5, knee 8, ankle 25, toe -30; swing hip 75, knee 117, ankle -2, toe 0; shoulders st 59.5 / sw -34.9; elbows 90 / 80.5; spine 3.1; pelvis 3.0.
- **Intent.** The header calls TO "the final motion of each stride: the power leg nearly fully extended behind, the alternate knee driven up, the arm on the power-leg side swung forward" (`run_natural.w:27-30`); Erik's set 3 note: "straight-knee push (stance knee 8-9 at HR/TO), high knee drive (swing hip 73.5-75 at HR/TO)" (`keyframes_erik3.txt:2-3`).
- **What Erik actually edited.** Against the literature TO (`run_natural.w:371`: st hip -12, knee 15, ankle 25, toe -30; sw hip 55, knee 90, ankle -2; shoulders 44.9 / -34.9) set 3 changed only: sw hip +20, sw knee +27, st knee -7, st hip -5.5, st shoulder +14.6. The stance ankle (25), the stance toe (-30), the swing ankle and the swing toe are the literature's untouched values. So the toe extension is not what set 3 moved; the TO edits are about the swing leg's knee drive and a straighter push leg. (Same comparison at MS: only sw hip +10 and sw knee +33 differ from the literature MS, every stance and arm value is literature.)
- **Evidence on which joints matter.**
  - TO as a whole is needed: without the TO keyframe (its chunk then aims at HR's flat ankle) the keyframe-chunk runner "runs 2.7 m/s and fails the speed guard on every start" (`SEARCH.md:1156-1159`; 7 falls + 41 slow of 48, `:1154`). HR and TO differ mainly in stance ankle (-1.3 against +25) and toe (-19.1 against -30) (`kfdrop.py:4-7`), so the evidence points at the stance ANKLE (plantarflexion), not at the toe; nobody has swept the toe alone (unverified whether it matters).
  - The stance ankle at TO is reached (held-out error 4.5 deg for the champion, `eval_7101-7148.jsonl` `st_ankle_TO`, rn2_nohr), while the event as a whole is off by 16.4 deg RMS over the counted joints.
  - The swing ankle at TO is commanded 36.7 deg dorsiflexed from its reference (`d_to_sw_ankle -36.7`, box +-40): a value the search pushes to the box edge, which reads as "the pinned reference is not what the body needs there" (inference).
  - The toe joint: range -0.8 .. +0.4 rad, peak torque 40 / 20 (`playground/body.py:282`), monoarticular (its pair crosses only the toe joint, `body.py:271-274`); no toe metric exists (`run_natural.py:668-669`).
- **Proposed subset.** Pin (stance): ankle +25, toe -30, knee 8, hip -17.5, these are the push-off geometry; pin (swing): hip 75 and knee 117, the "alternate knee up" that Erik edited. Free: swing ankle and toe (the ankle is at its offset bound; the toe is 0 in the set), both arms (`arm_amp` 0.67 already scales them; "the arms are nearly free", `SEARCH.md:990-993`), spine. Free joints should INTERPOLATE (min-jerk between the td goal and the next td) rather than hold or release.
- **Today.** Not by omission: the swing ankle is the two-joint case of B2 (gastrocnemius crosses knee and ankle), so omitting it would pull the gastrocnemius to the reference angle. The toe alone could be posed on its own `Track` with a toe-muscle mask (controller.w:10-14, 321-323), but the loop is one track with `body.all` (`run_natural.w:152`). Cheap and immediate: a params-only sweep of `ref_to_st_toe` (`run_natural.w:396`), for example 0 / -15 / -30 / -45.
- **Estimate.** Value 2, cost 2 (toe sweep) to 4 (true free joints), risk 3. Do the toe sweep first: it tests Erik's claim directly at zero code cost.

### A3. Mid-stance `ms` (td -> ms is the load chunk)

- **Definition.** `keyframes_erik3.txt:19-33`; goal of `r_load` (`run_natural.w:146, 722-730`), ends on the COM-over-foot latch `d_ms` -0.004 after at least `t_ms_min` 0.045 s, timeout `t_ms_max` 0.152 s (`rn2_erik3_nohr.txt:11, 129-130`; `run_natural.w:219-225`). Champion t_load 0.165 s is LONGER than the timeout, so the chunk is always cut before its ease ends. Values: st hip 12, knee 40, ankle -20, toe 0; sw hip 30, knee 143, ankle -5, toe 0; arms 24.3 / -14.3; elbows 87.4 / 82.6; spine 5.9; pelvis 3.0.
- **Intent.** The loaded stance leg at its deepest (stance knee 40, dorsiflexed ankle -20) while the swing leg folds under the body (`run_natural.w:8, 24`).
- **Evidence.** Everything except swing hip and swing knee is literature (see A2). The swing knee value 143 is the model's knee limit and "no command the ILC tried came near" (`SEARCH.md:975-977`; `kin_knee` stays 44-48 deg). Held-out MS error 27.8 deg (`eval_7101-7148.jsonl`, rn2_nohr), the second worst event. Searched offsets push two joints to the box edge (`d_ms_sw_hip -58.4` of +-60).
- **Proposed subset.** Pin the stance leg (hip 12, knee 40, ankle -20): this is the loading that the `d_ms` latch and the hop-height loop (`k_z`) act on. Swing hip and knee: pin knee as a "fold as far as possible" intent but mark the hip FREE (it is the torso's reaction mass and is already under the `comp` world-frame servo, `run_natural.w:965`). Arms at MS are exact points of the arm sinusoid (`shoulder_deg`, `:378-380`; `keyframes_erik3.txt:28-31` equal its values), i.e. pure via-points: free, interpolating between the TD and TO arm extremes.
- **Today.** Only by filling values (the skill would compute the sinusoid itself, which it already does when `ref_*` is absent, `:401-404`). Value 2, cost 2, risk 2 for the arms; the legs are value 2, cost 4, risk 4.

### A4. Touchdown `td`

- **Definition.** `keyframes_erik3.txt:4-18`; the goal of the flight chunk (last chunk of a step, ends on the landing foot's contact, `Latch.contact`, `run_natural.w:634-636`, timeout 0.45 s). Values: st hip 36, knee 3, ankle 44.5, toe -14 (a forefoot landing, "toe landing (TD ankle +44.5, knee 3)", `keyframes_erik3.txt:3`); sw hip 11.5, knee 143, ankle 27.8, toe -8.6; arms -45 / 43; elbows 80 / 91.5; spine 5.5; pelvis 7.0.
- **Evidence.** The worst event of every runner: held-out TD error 38.8 deg (champion), 38.3 (P7 knots), 39.5 (s3c) (`eval_7101-7148.jsonl`; `SEARCH.md:1124-1127`). The drivers are the swing knee (143 at TD: the heel to the glute) and the landing ankle (+44.5): searched offsets d_td_st_knee -39.2 and d_td_sw_knee +37.7 both sit at the +-40 box edge, `lim_td_st_hip` and `lim_td_st_ankle` had to be widened to 90 / 80 (`rn2_erik3_nohr.txt:68-69`). With the landing leg's hip placed by the speed servo (`cv`, `retract`, `run_natural.w:961`) the stance hip value is partly overridden.
- **Proposed subset.** Landing leg (st ankle, knee) pinned: that is the contact geometry. Swing knee: a "fold maximum" wish rather than a pin; hip of the landing leg FREE (placed by the speed servo); arms pinned only here and at TO (the extremes), free at MS.
- **Today.** Not by omission. Estimate value 3 (the largest error is here), cost 4, risk 4: the body cannot fold to 143 (A5's anatomy notes for the sprinter body: peak swing fold 95-98 deg against Bolt's 140, `scratchpad/anat5/LOG.md:4, 17`), so a subset that frees the swing knee removes an unreachable target rather than model new intent.

### A5. The removed heel-rise keyframe `hr` (30 %): a via-point, drop confirmed

- **Definition.** `params/keyframes_erik3.txt:34-48`; in the ordered plan it is `td -> ms -> hr (via) -> to (drive) -> kl (via) -> td` (`run_natural.w:45-59`), ended by `Latch.release(st + "heel")` (`:642-643`). Values: st hip -19.5, knee 9, ankle -1.3, toe -19.1; sw hip 73.5, knee 127, ankle -4.9; shoulders 43 / -33; elbows 89.8 / 80.2; spine 12; pelvis 3.
- **Intent.** The instant the stance heel leaves the ground, between mid-stance and toe-off: "straight-knee push, high knee drive" (`keyframes_erik3.txt:2-3`).
- **Evidence (the ablation Erik asked for, `playground/SEARCH.md:1143-1177`, script `playground/kfdrop.py`).**
  - HR and TO "differ mainly in the stance ankle: -1.3 against +25 deg" (`SEARCH.md:1143-1144`), plus the toe (-19.1 against -30, `kfdrop.py:4-7`). The hr and to keyframes are 6 % of the stride (about 40 ms) apart, so a flat-ankle goal followed 40 ms later by a +25 plantarflexed one conflicts.
  - With HR the keyframe-chunk runner misses HR's ankle by 28.4 deg and TO's by 2.1; the heel rises because the ankle is already plantarflexing at 30 % (`SEARCH.md:1160-1163`, table `:1152`).
  - Dropping HR: 6 falls of 48 -> 1 (2 falls in 96 starts against 11 over both sets, `:1165-1167`), kin_rms 19.43 -> 19.78 (a little worse), and the heel-rise event error does not get worse on the knot residual (14.9 against 15.3, `:1163-1164`). Arena: promoted (p = 0.0095, `:1168-1170`).
- **Proposed subset.** None: drop it. If an hr keyframe is wanted as a WITNESS of Erik's "heel rise" event, keep the latch only (`Latch.release(st + "heel")`, `:642-643`) and pin nothing except the stance knee (9, straight push) and the ankle as a FREE joint that interpolates from MS (-20) to TO (+25); with the ankle left to the interpolation the conflict disappears.
- **Today.** Yes, already: delete the `ref_hr_phase` line (what the champion does). Value 1 (done), cost 1, risk 1.

### A6. The "max knee height" keyframe `kl` (38 %)

- **Definition.** `params/keyframes_erik3.txt:64-78`; its latch is the swing thigh's elevation rate crossing zero, or the landing foot's contact (`run_natural.w:644-646`, `thigh_rate` `:656-657`). Values: st hip -15, knee 16.5, ankle 28.5, toe -26.5; sw hip 68.5, knee 99, ankle -1.3, toe -0.2; shoulders 71 / -34.3; elbows 73 / 80.1; spine 3; pelvis 3.
- **Intent.** The highest point of the swing knee ("high knee drive").
- **Evidence.** Neither champion runs it as a controller keyframe: rn2 has it "already dropped from its targets" (`kfdrop.py:24-25`; no `ref_kl_phase` in `rn2_erik3_nohr.txt`), and the P7 knot runner treats KL only as a scoring event. It is reached without being aimed at: held-out KL error is 11.0 deg (P7 knots) and 14.4 (rn2), lower than TD (38) and MS (21-28) (`eval_7101-7148.jsonl`), and "heel rise and knee lift do not quite [follow from TD and TO]: HR 16.5 against 15.3" (`SEARCH.md:1130-1132`). Internal tension in the set: KL's swing hip (68.5) is BELOW the TO value (75) and HR's (73.5), i.e. the set puts the thigh peak before KL, although the latch fires at the thigh peak (verified from the values; effect unverified). The ordered plan cannot even run inside the P7 subclass: dynamic dispatch takes at most 8 arguments and `step_chunk` has 9 (`SEARCH.md:1174-1177`).
- **Proposed subset.** The only thing the event defines is one joint: the swing hip (thigh elevation peak), and with it the swing knee height. Pin sw hip (and optionally sw knee); everything else (stance leg, arms, spine, toes) FREE and interpolating between TO and the next TD. In practice the stride needs no kl chunk: drop it as a keyframe, keep "thigh apex" as a measured score event.
- **Today.** Dropping is free (omit `ref_kl_phase`). A one-joint keyframe would need the free-joint mechanism of B4 or a separate swing-leg track. Value 1, cost 3 (as a subset), risk 2; recommendation: drop.

### A7. The P7 knot champion (`run_natural_erik3`) and the `run_natural` literature champion

- **Definition.** `lib/robolab/skills/run_knots.w:1-60`: RunNaturalSkill's three posture keyframes plus a zero-initialised residual (`knot_residual 1`): quintic knots `rc_/rv_/ra_<id>_<muscle>` per MUSCLE (32 muscles), learnt by ILC in two stages, "arms alone (shoulders and elbows), then legs and spine at half gain" (`SEARCH.md:949-964`).
- **Evidence.** The residual is already a muscle-space subset: the arm stage moves only the arm muscles, "the arms are nearly free" (shoulder error halved at unchanged speed, `SEARCH.md:990-993`), while "leg steps move the speed (mostly down: a more human, straighter stance knee pushes less) and reshuffle which starts fall" (`:993-994`). Learnt command minus the target's own least-squares knots on set 3: hip 15.7, knee 30.0, ankle 29.4, shoulder 23.2 deg (`:970`): the legs' pinned values are fictions again. The tied / free TD + TO residual variants show what a two-keyframe subset (only TD and TO targeted) does: mid-stance error improves (19.2 deg, the best MS of all) while heel rise and knee lift do not follow (`:1122-1132`), but the tied variant slows the runner below the 3 m/s guard on 6 and 11 of 48 starts.
- **Proposed subset.** Already the right shape for the ARMS: separate muscle group, separate learning stage. Extend it: freeze the arm stage after training and treat arms as pinned only at the TD and TO extremes (A3). For the legs no subset beyond A2 to A4 is supported by evidence.
- **Today.** Yes (a mask on the ILC update; `Track` masks exist, `controller.w:10-14`). Value 2, cost 2, risk 2.

### A8. Standing start: `stand`, `lean`, `l_push0`

- **Definition.** `run_natural.w:761-806`: `stand_pose` all 13 joints at quiet-stance values with `stiff0` (champion 0.011, `rn2_erik3_nohr.txt`), `lean_chunk` pose plus an ankle-strategy COM servo (`balance`, `:835-843`), `l_push0` = the left toe-off keyframe blended `push0_amp` (0.56) of the way from the standing pose (`blend_from_stand`, `:809-824`; `first_push` `:799-806`).
- **Evidence.** The start is tuned (d_go 0.20, push0_amp 0.56, drv0_* 0.10-0.14, t0_max 0.61 in the champion) and is the place where "from rest, the full knee drive throws the trunk back" (`:796-797`).
- **Proposed subset.** `lean`: pin ankles, hips, knees; arms free. `l_push0`: a blend of a full keyframe: pin the pushing leg only, leave the other leg's pose at the lean values (hold). Value 1, cost 2, risk 3 (the standing start is a one-off, not what the trials score).

### A9. The sprinter's six-chunk stride (RunSkill) and the five-gear champion `sprint_top_speed_v4_p95`

- **Definition.** `RunGearXSkill < RunGearSkill < ... < RunSkill` (`run_gearx.w:15`, `run_gear.w:16`); champion `params/run_gearx_v4_p95_x5a.txt` (`gears 5` at `:368`, handovers g2_v_on 6.5 `:115`, g3 7.0 `:198`, g4 7.7 `:281`, g5 7.8 `:359`). Each gear is a whole parameter set: "the stride is rebuilt from gear k's values at the next flight" (`run_gear.w:1-14`, `switch_gear` `:90-120`). The stride is three poses per step: `land_chunk` (`run.w:398-411`), `push_chunk` (`:417-438`), `flight_pose` (`:462-468`), each a `Pose` of 13 joints through `leg()` (hip, knee, ankle, `:584-588`) plus toe plus `upper()` (`:592-598`).
- **Gear-5 values (radians, `x5a.txt:284-355`).** Stance land: psi_ms -0.029, k_land 0.136, a_land 0.219. Stance push (the toe-off analog): psi_to -0.243, k_push 0.409, a_push 0.889, toe_push +0.300. Flight, trailing leg: psi_fo -0.057, k_fo 1.202, a_fo 0.560, toe_fly -0.276; landing leg: psi_reach 0.016, k_reach 0.372, a_reach -0.3, toe_land 0.132. Swing leg at land: psi_mid 0.750, k_mid 2.079; at push: psi_late 1.101, k_late 2.049; heel_tuck 0.559, knee_lift 0.078; stiff_st 0.054, stiff_sw 0.026, stiff_up 0.023; arm 0.386, elbow 2.17, spine 0.282, lean 0.215.
- **Intent.** `run.w:24-31`: soft landing spring, stiff push with a drive burst, follow-through fold of the pushing leg, reach of the landing leg.
- **What is pinned by construction (verified in the code).**
  - The swing ankle is a literal constant in the land (-0.1) and push (0.0) chunks (`run.w:402, 421`): already "not searched".
  - `tuck(k) = min(k + heel_tuck, 2.45)` (`run.w:457-460`): in gear 5 the swing-knee command of the land chunk is `2.079 + 0.559 = 2.64`, capped to 2.45 rad (140 deg), so that command is pinned at the cap and neither `k_mid` nor `heel_tuck` moves it while their sum stays above 2.45; `heel_tuck` still acts through `k_fo` (1.20 + 0.56 = 1.76 rad). `g5_a_reach -0.3` equals the declared lower bound of `a_reach` (`run.w:219`: `param("a_reach", 0.2, -0.3, 0.6)`; A5's later search box was widened to -0.6, `scratchpad/anat5/es5.sh:17`), so the landing ankle sits at its box edge in the champion (the box used when x5a was searched is unverified).
  - `upper()` writes ONE arm / elbow / spine pose for every chunk (`run.w:592-598`; stance-side arm = arm, swing-side arm = -0.7 arm, roles swap each step): there are no arm keyframes, only a per-step flip; RunGearX then uses the shoulders as a trunk actuator (`k_arm_p`, `k_arm_d`, `run_gearx.w:8-10, 35-38`), i.e. the arms are feedback-driven, not posed.
- **Evidence on which tunables are live (A5).** `k_syn, t_swing, k_trail, t_soft, t_kext, t_stance, t_drive, psi_drive, k_drive, t_kdur, t_step_min` belong to gait 1 / gait 2 (`run.w` `add_bounds`, `add_steps`, `step_correction`); forcing them to extreme values in gear 5 gives BIT-IDENTICAL flying-start results on 4 seeds x 16 s (`scratchpad/anat5/LOG.md:23-24`), while `heel_tuck` 0.56 -> 0.2 changes them (falls). They are all still present in the champion file (`x5a.txt:374, 384-385, 395, 413-423`). The live swing-recovery tunables are heel_tuck, k_fo, k_mid, k_late, psi_fo, psi_mid, psi_late, knee_lift, drv_swh, drv_swk, drv_rf, drv_hamb, drv_pre, t_flight, stiff_sw, k_clear, clear_h (`anat5/LOG.md:25`). **`psi_drive` / `k_drive` are the dead "drive-off posture" keyframe: the orphan keyframe of the sprint family (`run.w:566-571`, gait 1 only) and can be deleted.**
- **Command minus reached.** The swing fold is the known gap: peak swing-knee flexion about 95-98 deg (heel 0.34-0.35 m, reached late) against a command of 140 deg here and Bolt's 140 deg (`anat5/LOG.md:4, 17`; `scratchpad/heel/LOG.md` for the earlier measurements). A5's test of whether anatomy blocks it: a body whose rectus femoris is re-proportioned (v5) makes the champion's strides fail (0/12 survive, `anat5/LOG.md:36-43`), and "x5a's extended gear 5 is a knife edge that ANY body change breaks" (`:43`); only a re-split that keeps the vasti unchanged ("v5b") keeps gear 3 alive, folding 110 deg (`:54-58`).
- **Proposed subset.** Land: pin stance hip / knee / ankle (the loading spring) and the swing hip; swing knee pinned as a "fold to the cap" wish (saturated), swing ankle free. Push (toe-off analog): pin stance ankle (0.889 rad, the push), knee, hip and toe_push; swing hip and knee pinned (knee drive); swing ankle free. Flight: trailing leg pinned at the KNEE only (k_fo + heel_tuck), its hip and ankle free; landing leg pinned at hip (overridden by the speed servo, `psi_v` 0.053) and knee, ankle free. Arms and spine: no keyframe, hold (the feedback terms already act on the shoulders). Free joints should INTERPOLATE (hip and ankle of the trailing leg between push and reach).
- **Today.** Only by filling values in `flight_pose` / `leg()` (those helpers take scalars, so a free joint needs a computed value, not an omission). Estimate: value 2, cost 4 (a gear is 79 tunables, each gear re-searched), risk 5 (every one-at-a-time move of the gear-5 stride falls, `anat5/LOG.md:43, 45`). Not recommended for the chain; the cheap parts are deleting the dead gait-1/2 keys and the orphan `psi_drive` / `k_drive`.

### A10. Bolt's blocks sprint (`sprint_blocks`, champion `sprint_blocks-p95form`, params `out/sprint_blocks/formB_p.txt`)

- **Definition.** `lib/robolab/skills/sprint_blocks.w:1-34`; keyframes are `playground/refs/bolt/editor/<event>.json` (set, rear_exit, block_exit, s1_td / s1_to, s2_td / s2_to, s3_td / s3_to, drive_td / drive_to, maxv_td / maxv_ms / maxv_to / maxv_mkl; 14 channels each, with a `source` note and an `achieved` field). Every keyframe is reference plus a searched offset per leg joint; "the arms, elbows, toes and spine come from the reference" (`sprint_blocks.w:30-34`). The form champion searched "the max-velocity cycle's keyframe offsets, trunk servo, swing drives and timing" against 1 deg of form error (champions.json:6131-6136).
- **Evidence from the keyframe files themselves (target / achieved, deg). `achieved` is the body's joint angles at each event in ONE rollout (`write_editor`, `playground/tasks/sprint_blocks.py:1017-1034`, fed by `keyframe_sheet` `:1166-1173, 1268-1271`); which controller and params that rollout used is unverified, so read the gaps as typical, not exact.**
  - maxv_td: sw_knee 139.5 / 53.7, st_ankle 30.4 / 6.1, pelvis 0.8 / 8.3, all other legs within 12. maxv_ms: sw_knee 144.9 / 80.3, sw_ankle 18.3 / 32.4, st_ankle 2.1 / -10.2, pelvis 2.4 / 14.8. maxv_to: sw_hip 65.8 / 89.2, sw_shoulder -44.2 / -4.7, st_shoulder 60.8 / 38.6, st_hip -16.2 / -4.7, **st_toe -25.0 / -22.4 (reached)**. maxv_mkl (max knee lift): sw_hip 69.5 / 100.1, sw_knee 81.4 / 106.1, st_knee 35.3 / 11.5, st_ankle 33.3 / 52.6, st_toe 0.0 / -17.0.
  - **In Bolt's set the stance toe is pinned at toe-off only: st_toe = 0.0 at td, ms and mkl and -25.0 at to.** That is exactly Erik's toe-off sentence; the zeros elsewhere are placeholders (the video does not measure toes; the toe then follows the foot, achieved -7 at ms and -17 at mkl).
  - Elbows are 90.0 in every max-velocity keyframe (achieved 88.9-90.5) and spine 4.0 (achieved 5.2-8.4): constants, nothing is measured. `source` says "video, 9 instances (good (legs), fair (arms))" (`maxv_td.json`); `set` is "literature: W18 ... Bolt-specific set angles not found"; `drive_td` / `drive_to` are "not measured: legs interpolated step 2 -> max velocity (0.36), trunk_by_step ..." i.e. synthetic via-points; `block_exit`, `rear_exit` and `s1_to` (s1_td not read) are "video, 2 instances (fair)" with very large target-minus-achieved gaps (block_exit st_hip 4 / 43, pelvis 38 / 83; rear_exit st_hip 54 / 96, sw_shoulder 23 / 76).
- **Proposed subset.** Max-velocity cycle: pin hip / knee / ankle of both legs (the measured, "good" channels) and st_toe at toe-off only; shoulders pinned at td and to (the swing extremes), free at ms and mkl; hold elbows at 90 and spine at 4 (no keyframe); toes free at td, ms, mkl; the pelvis is not a command. `drive_td` / `drive_to`: drop as keyframes, replace by the step-index blend the skill already does (`sprint_blocks.w:20-27`). Start keyframes (set, rear_exit, block_exit): full vectors are right there (little data, large gaps, nothing to free).
- **Today.** The skill's values come from `SprintRef` with per-key overrides `ref_<event>_<key>` (`sprint_blocks.w:32-34`), so "hold" for elbows, spine and toes is a params-only change (set the constants), and deleting the two drive keyframes is a skill change. Free-and-interpolate needs B4. Value 3 (an honest model of what Bolt's data says), cost 2 (holds) to 4 (free joints), risk 2 (elbows / spine are constants already).

### A11. The touch-only sprint (`run_natural_fast`, `sprint_touch-r2`): the existing time-subset experiment

- **Definition.** `lib/robolab/skills/sprint_touch.w:1-60`: ONE keyframe, the right touchdown (all joints), the left as its mirror, two `via` chunks touch -> touch; "no mid-stance, toe-off or knee-lift target" (README 1190-1199). This is Erik's "model the toe touches with everything in between eased" test, already run.
- **Evidence.** It fell within two steps until the keyframe carried each leg joint's velocity at the touch (`w_st_*` / `w_sw_*`, a quintic knot): survival 0.6 s -> 2 s (README 1216-1227). Found touchdown: landing hip 18 / knee 26, trailing hip 50 / knee 130; touch velocities landing hip -7, trailing hip +15, trailing knee +25 rad/s (`:1228-1230`). Result 4.62-4.68 m/s against 5.00 for the six-chunk `run_v2`, kin_rms 15.7 (`:1246-1254`); arena: 10/12 and it loses `run_v2` (11/12 at 4.6, `:1257-1262`). Which muscle groups matter (each burst zeroed, held-out 20 s): falls without stance hamstrings (3.9 s), stance gastrocnemius (9 s), swing iliopsoas (2.4 s), pre-landing vasti + soleus tone (7 s) or the touch velocities (2 s); landing vasti pulse worth 0.72 m/s; stance gluteus, soleus, rectus femoris, heel tuck and both claw bursts "change nothing here" (`:1264-1273`).
- **Reading.** That experiment subset the keyframes in TIME (one of six) but kept all joints in it; the lesson is that a touchdown keyframe alone is not enough unless joint velocities ride with it. A JOINT subset is the untested complement (A2, A10).
- **Proposed subset.** None for this controller; it is the most subset-like design in the repo already. Value 1, cost 1, risk 1.

## (b, continued) B5. What a subset keyframe can do today, what the runner needs, and the concrete sketch

**Expressible with today's SDK, no new API (verified by reading):**

1. **A separate `Track` on a muscle mask.** The controller runs "parallel movements on disjoint muscle masks" (`controller.w:1-8`; `Track.new(name, movement, mask)` `:14`; `add_track` `:321-323`). A toe-only keyframe is a second track over `r_toe_*` / `l_toe_*`: the toe muscles are monoarticular (`playground/body.py:271-274, 284-288`: only rf, ham, gas are biarticular), so there is no two-joint side effect and nothing else is written. Cost: every runner builds ONE track over `body.all` (`run_natural.w:152`, `run.w:139`, `sprint_blocks.w:41`), and `RunGearSkill` swaps the movement of `ctl.track("body")` only (`run_gear.w:21, 115`; `controller.w:35-40`), so the toe channels would have to move out of `keyframe()` / `leg()` and get their own gear handling.
2. **Hold by construction**: `Chunk#rate(v)` with zeros on the held muscles (`chunk.w:87-90, 220-222`) is an exact hold, but in contraction units, not joint angles; `Chunk#to(c)` writes an absolute state on the track mask only (`:92-95, 223-224`); `Chunk#stagger` gives per-group timing inside one chunk (`:165-173`).
3. **Interpolating a free joint between its neighbours already exists for offsets**: `read_extra_offsets` (`run_natural.w:521-550`) starts an added keyframe's offsets at the phase-weighted blend of its neighbours' (`share_of`, `:509-519`), and `blend_from_stand` (`:809-824`) blends a whole keyframe from the standing pose by an amplitude. The mechanism a `free` joint needs is in the skill, it is just not a property of `Pose`.

**What a joint-level subset must respect in this code base (checked):**

- The stride is PERIODIC and the left step is the mirror (`loop_from`, `run_natural.w:142, 151`; `Pose#mirror` `contraction.w:123-134`; `RunNaturalKeyframe#mirror` `run_natural.w:1032-1045`): the nearest pinning keyframe of a free joint must be searched cyclically through the mirror.
- Chunk durations are LATCH-driven and vary (champion t_drive 0.038 s with a release latch and a 0.187 s timeout, `rn2_erik3_nohr.txt:125-126`): interpolate by PHASE share (`kf_phase`, `share_of`, `run_natural.w:447-519`), not by seconds. B4 said "by keyframe time or phase"; for latch-timed gaits it has to be phase.
- Two-joint muscles read the interpolated angle only if the free joint is resolved to a value BEFORE `Pose#apply_geometry` (`contraction.w:149-169`); `travel()` (`run_natural.w:1061-1068`, used by `timing 1`) also needs filled angles.
- The Bench writes all 14 channels always (`run_natural.w:491-492`); `ov(kf, key, lit)` (`:410-413`) reads `ref_<id>_<key>`, so a pin flag is a params-only plumbing (for example `ref_<id>_pin_<key> 0|1`, not implemented).

**Sketch (Tungsten, 6 lines), replacing the B4 sketch for the runner:**

```
+ RunNaturalKeyframe
  -> pin(joint, q, stiff)      # like set(): writes the joint at this keyframe
  -> free(joint)               # records "no value here"; resolve_free fills it
+ RunNaturalSkill
  -> resolve_free(plan)        # per free joint: cyclic over plan in phase order (left step = mirror);
                               #   q = min_jerk(prev_pin, next_pin, share_of(phase))   then set(joint, q, stiff)
```

Used for Erik's example: `to.pin("r_toe", -0.52, @stiff_st)` and `td.free("r_toe"); ms.free("r_toe")`, so the toe glides between toe-offs instead of being pinned to the placeholders 0 / -14 / 0. `apply_geometry` needs no change because every free joint has become an ordinary `set` before the chunk goal is computed (same conclusion as B4).

## Keyframe-like elements that are pure via-points or do nothing (candidates to drop)

| element | verdict | evidence |
| --- | --- | --- |
| `hr` heel-rise keyframe (30 %) | drop: already dropped in both champions | conflicts with `to` (ankle -1.3 against +25, 6 % apart); 1 fall instead of 6 of 48 (`SEARCH.md:1143-1177`) |
| `kl` max-knee-height keyframe (38 %) | drop as a controller keyframe; keep as a score event | not in either champion's controller; error 11-14 deg reached without aiming (`eval_7101-7148.jsonl`; `SEARCH.md:1130-1132`); its sw hip 68.5 is below `to`'s 75 |
| `ms` arm and elbow values | via-points | equal the literature sinusoid (`keyframes_erik3.txt:28-31`; `run_natural.w:378-385`) |
| Bolt `drive_td` / `drive_to` | synthetic via-points | "not measured: legs interpolated step 2 -> max velocity" (`drive_to.json` source) |
| Bolt elbows (90) and spine (4) in every maxv keyframe; toes 0 at td / ms / mkl | constants / placeholders | `maxv_*.json` angles, achieved 88.9-90.5 / 5.2-8.4 / -7 .. -17 |
| sprint `psi_drive`, `k_drive`, `k_syn`, `t_swing`, `k_trail`, `t_soft`, `t_kext`, `t_stance`, `t_drive`, `t_kdur`, `t_step_min` | dead in the six-chunk stride | bit-identical when forced to extremes (`anat5/LOG.md:23-24`); still in `x5a.txt:374, 384-385, 395, 413-423` |
| sprint swing-ankle constants in land / push | not searched | `run.w:402, 421` |
| `heel_tuck` on the gear-5 land-chunk swing knee | saturated | `k_mid 2.079 + heel_tuck 0.559 > 2.45` cap (`run.w:457-460`) |

**Where a full-vector keyframe is right:** the Bolt start keyframes (set, rear_exit, block_exit: little data, large gaps, nothing to free), the gear strides (a gear is a knife edge, `anat5/LOG.md:43`), the landing leg at touchdown (contact geometry), and any keyframe whose joints are all measured ("good (legs)").

## Ranked candidates (value, cost, risk as 1-5)

1. Toe sweep `ref_to_st_toe` in `rn2_erik3_nohr.txt` (params only; tests Erik's claim, the toe is unscored today): value 2, cost 1, risk 1.
2. Bolt keyframes: hold elbows 90 and spine 4, toes free except at toe-off, drop `drive_td` / `drive_to` (`ref_*` overrides, `sprint_blocks.w:32-34`): value 3, cost 2, risk 2.
3. Delete the dead gait-1/2 keys and the orphan `psi_drive` / `k_drive` from the sprint champion files and search boxes: value 2, cost 1, risk 1.
4. run_natural ms arms as via-points, arms pinned only at td and to (needs `free`, B5 sketch): value 2, cost 2, risk 2.
5. run_natural td / to leg subsets (landing leg and push leg pinned, swing ankle / toe / arms free): value 3, cost 4, risk 4; the swing knee 143 at td / ms is unreachable (kin_knee 44-48 deg), so freeing it removes an impossible target, not a new behaviour.
6. Not recommended: gear-chain subsets (risk 5), touch-only sprint (already a subset).

## Unverified

- Which controller and params produced the `achieved` fields in `playground/refs/bolt/editor/*.json` (the writer is `sprint_blocks.py:1017-1034`; the rollout is not recorded in the files).
- Whether the toe value at `to` (-30) matters at all: no toe-only ablation exists.
- Whether the box used when x5a was searched had `a_reach` at -0.3 (the declared bound in `run.w:219` is -0.3).
- The consequence of KL's hip (68.5) being below TO's (75).
- `RunKnotsSkill` per-muscle residual values of the P7 champion (`runknots_erik3_nohr.txt`, 24 kB) were not read.
