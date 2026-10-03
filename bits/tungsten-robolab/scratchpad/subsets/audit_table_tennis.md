# Subset-keyframe audit: MyoSuite table-tennis family (`myo_tt.w` and v7 to v11)

Read-only audit by agent K5 on 30 Sep 2026 (verbatim report; paths are under `bits/tungsten-robolab/`).

Champion is c3 (`params/myo_tt_p2_r10_c3.txt`, 40.0 % on `tt_p2_300`). Best on fresh serves is c5 (40.9 % of 900 fresh serves). Both run only the base chunks. `fam_mode`, `flick_mode`, `scoop_mode`, `bh_ps`, `bh_tk`, `lt` and `rn` are absent, so they are off. `trunk_lim` is 0, so the trunk axial servo is off.

The Keyframe Bench does not apply to this family as it stands: it edits sagittal runner angles, while TT postures are 10-joint radian commands.

## Semantics deviation from the SDK answer

`posture()` (`myo_tt.w:935-954`) poses all 10 joints (3 trunk, 7 arm), 24 slaved joints and `Abs_t1`/`Abs_t2`, with one shared `stiff`. No joint is ever left unset, so there is nothing to observe. By `contraction.w:149-169`, a left-out joint would be evaluated at the reference posture for every muscle that also crosses a posed joint. Muscles crossing only that joint would keep their start command, which for the first chunk is the measured contraction (`controller.w:647-648`). So "leave it out" is not "don't care" on this body.

## 1. Forehand `ready` (arm track)

- **Definition.** `myo_tt.w:326-328, 374`; params `:533-538, :563-569`. Champion values: elv 0.360, sh_elv 0.487, sh_rot -1.294, elbow 1.222, pro_sup 1.203, dev -0.170, wflex -0.769; trunk fe 0.052, lb 0, ar 0; stiff 0.1117 on every joint.
- **Intent.** "IK: pad centre at the P1 crossing, normal for a block" (`:561-562`). At contact what matters is pad height, lateral position, face pitch and yaw, and pad velocity. The ceiling needs 3 deg / 1.5 deg / 0.2 m/s / 2 cm (`tt3/LOG.md:115-116`).
- **Evidence.**
  - Not attained: command minus reached at contact is plane -0.64, rotation -0.48, forearm +0.65 rad, while elbow, deviation and wrist flexion are within 0.09 (README 3635).
  - The asked posture is a calibrated fiction: a literal ideal arm that follows it scores 0/200 (`tt3/LOG.md:92-94`).
  - At the champion's regime, +0.1 rad on `pro_sup` changes pad pitch, yaw and z by 0/0/0 (`tt/LOG.md:179-181`, taken under `qa=3`, not the exact champion regime).
  - Dev and wflex are pinned at their joint limits (`myo_tt.w:568`, `tt/LOG.md:96`).
  - Counter-evidence: moving the wrist off its limits scored 0/218 (README 3580). Solving the 7 joints for pad pitch, yaw and height by least squares scored 29 % / 33 % against 45 % (README 3770).
- **Proposed subset.** Pin wflex, dev, elbow, sh_elv and trunk fe/ar. Free elv, sh_rot and pro_sup, but fill them with their current values, not "hold".
- **Today.** Not by omission. Only filling them with values works, and then the flags are inert.
- **Estimate.** Value 2, cost 3, risk 4. The forehand "sits on a sharp optimum of every parameter screened" (README 3842-3843).

## 2. Backhand `bh_ready`

- **Definition.** `myo_tt.w:329-336, 384`; params `:576-583`. c3 values: elv -1.227, sh_elv 0.743, sh_rot 1.282, elbow 2.025, pro_sup 0.887, dev -0.0575, wflex 0.246, trunk ar 0.418.
- **Intent.** Backhand ready posture plus trunk turn (`:570-572`). The face at contact is set by where the swing is when the ball arrives (README 3340-3343).
- **Evidence.**
  - Command minus reached at contact: plane -1.52, rotation +0.87, forearm +0.50 rad. Elbow, deviation and flexion are within 0.04 (README 3637).
  - Plane of elevation commanded -1.23 reaches +0.41 to +0.53, "the sign is wrong on every arm" (`tt2/LOG.md:60`).
  - Six posterior shoulder and pectoral muscles are at full activation from 0.35 s (README 3137-3142).
  - Per +0.1 rad, pitch/yaw/dz change by: sh_rot 0/0/0, pro_sup -0.3/0/0, elv -0.6/-0.5/-0.2. Elbow gives -4.0/-4.5/-2.2, dev -3.6/-2.3/-1.4, sh_elv -3.7/0/+0.8 (`tt/LOG.md:243-246`).
  - rsm_bh5 posture effects: elbow t 2.4, dev 1.6, trunk_ar 1.4, elv -0.9, sh_elv and wflex |t| < 0.6. `bh_sh_rot` and `bh_pro_sup` were not in the design (`rsm_run7.sh`).
  - The wrist is very sensitive: `bh_wflex` moves solved by -22 points (`tt/LOG.md:246`).
  - Counter-evidence: reachable settled postures scored 0-1 of 36, and removing the face's closed bias scored 9/9 against 16 of 60 (README 3338, `tt/LOG.md:246`).
- **Proposed subset.** Pin elbow, dev, wflex, sh_elv and trunk_ar. Free elv, sh_rot and pro_sup, the three unreached joints with about 0 pad effect. Time the shoulder group earlier than the wrist group.
- **Today.** Same as item 1, but stagger is usable now. `myo_tt.w:1026` already calls `stagger(@arm_mask, 0, nil, dur)` uniformly. Per-group delays inside `bh_ready` need no SDK work. The chunk ends on its latch (`controller.w:209-211`).
- **Estimate.** Value 3, cost 3, risk 4. This is the only place per-joint timing is plausible. Uniform retiming lost (`bh_tdur` 6 of 96 against 22, README 3350), and no per-group delay was ever tried.

## 3. `stroke` / `follow` (`bh_stroke` / `bh_follow`)

- **Definition.** `myo_tt.w:375-376, 385-386`; goal built in `stroke_due` at `:1579-1623` as ready plus `d_push` (-0.1) along the push vector, on all 7 joints.
- **Evidence.** With `d_push` 0 and `drv_push` 0, the outcome is identical serve for serve, 34/120 both ways: "the stroke does nothing" (`tt/LOG.md:70`, README 3761).
- **Proposed subset.** None. Drop the keyframe.
- **Today.** Set `d_push` to 0.
- **Estimate.** Value 1, cost 1, risk 1. Nothing to gain.

## 4. Trunk `brace` / `hold` (`bh_brace` / `bh_hold`)

- **Definition.** `myo_tt.w:356-359`; same trunk joints as items 1 and 2.
- **Evidence.** `trunk_fe` -0.08 scored 1/120 (`tt/LOG.md:175`). Lateral bend is bent 0.13-0.28 rad by the pelvis slide (README 2978-2984, 3011-3013). The trunk turns only 0.05-0.15 rad by 0.45 s against 0.42 commanded (README 3337). Command minus reached is +0.21 for the backhand trunk (README 3637). Free `lat_bending`: none found.
- **Proposed subset.** Pin fe, and ar on the backhand only.
- **Estimate.** Value 1, cost 2, risk 3.

## 5. Uniform co-contraction across all posed joints (a per-pose property)

- **Definition.** `myo_tt.w:335, 942-953`.
- **Evidence.** Comments at `:733-737` and README 3200-3203 say `stiff` 0.11 alone asks about 1.4 activation of the elbow and wrist muscles. Lowering it uniformly hurt on both sides (README 3348, 3582-3583).
- **Proposed subset.** Stiffness on the wrist only. No per-joint stiffness experiment found.
- **Today.** `Pose#set(joint, q, stiff)` (`contraction.w:113`) already takes a per-joint value, so this needs no SDK work.
- **Estimate.** Value 3, cost 1, risk 3. Best cheap experiment in this family.

## 6. Grip (`grip` / `bh_grip`)

- **Definition.** `myo_tt.w:440-469`. It is a full-vector goal via `Chunk#to` on the hand mask.
- **Evidence.** Pinching (thumb and index short, other fingers long) lost the paddle and scored 0 (README 3530). Not a candidate.

## 7. Opt-in chunks, all off in the champion

- Families, flick and scoop: `:393-427`, `:1632-1739`. The flick (`push_vector_wrist`, `:1701-1739`) is already a subset expressed as deltas on a full posture. It did nothing: 10 solved against 11 (README 3216-3221).
- Pulse-step `bh_ps` and `bh_set` (`:429-433`) is a two-keyframe design (overshoot pulse, then set posture). It was not entered (README 3163).

## Cheapest later A/B (top candidate from this family)

Trial `tt_p2_backhand` (131 seeds from 99000-99259), champion c3. Challenger changes only the co-contraction of `bh_ready` and its chunks: wrist joints at `bh_stiff`, shoulder/elbow joints lower. Add a screen on the fresh `bh[400:600]` serves, paired. Expect this to lose or tie, given README 3348.

## Other observations for the SDK answer

- The tuned arm is calibrated around the command-versus-reached gap, so subset keyframes there need re-practice, not just omission.
- Run-time re-keyframing exists: `c.pose(p)` on live chunks (`myo_tt_v9.w:44-52`, `myo_tt.w:1609-1610`).
- `Chunk#duration` is read-only, so `stagger` with all muscles and delay 0 (`:1026`) is the only run-time retime.
