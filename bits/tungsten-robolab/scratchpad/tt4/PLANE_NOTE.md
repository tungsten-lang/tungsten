# Table tennis: does the paddle hold one plane? (30 Sep 2026)

Written by the main session after Erik's notes of 30 Sep. Everything measured here is read-only on existing records (no champion, trial or param file touched).

## Erik's design notes, in order

1. The model holds the paddle very strangely, in a way that would make the plane of the paddle hard to control.
2. Regardless of the stroke, the paddle's orientation plane is often kept constant as it moves towards the ball; the angle and the velocity vector at contact govern the specifics of the strike.
3. So the muscles are solving for the vector that holds the paddle in a consistent plane.
4. The wrist flick is a different stroke: the plane is NOT constant there.
5. Many forehand strokes, chops and backhand chops can all use a consistent plane.

## What the champion does (measured)

Data: T3's per-tick records of the champion (`bin/challengers/myo_tt_r10-n`, `params/myo_tt_p2_r10_c3.txt`) on 200 serves (sets 98000-98099 and 830000-830099), 177 of them hit; script `scratchpad/tt4/plane_probe.py`, full output `scratchpad/tt4/plane_probe_report.txt`. The hand kinematics were checked against the logged palm position (median error 0.1 cm).

| | forehand (91 hits) | backhand (86 hits) |
| --- | --- | --- |
| face normal turns between t_contact - lag and contact, median: 50 / 100 / 200 / 300 ms | 4.6 / 7.4 / 12.1 / 14.3 deg | 8.4 / 18.0 / 54.0 / 103.3 deg |
| turning rate of the normal AT contact, median (p90) | 91 (153) deg/s | 164 (263) deg/s |
| a contact-time shift of +-10 ms moves the face by, median (p90) | 0.9 (1.5) deg | 1.6 (2.6) deg |
| angle between the pad's direction of travel and its normal at contact, median | 63 deg | 68 deg |
| pad speed at contact, median | 1.10 m/s | 0.69 m/s |
| grasp: the normal turns relative to the HAND in the last 200 / 100 / 50 ms, median | 8.1 / 3.4 / 1.4 deg | 12.2 / 8.4 / 4.8 deg |
| grasp: the pad centre slides in the hand in the last 200 / 100 ms, median | 3.3 / 1.4 cm | 3.4 / 2.0 cm |

- **The plane is not constant.** The forehand's face swings 12 deg in the last 200 ms; the backhand's 54 deg. At contact it is still turning at 90-160 deg/s, so timing errors of a few milliseconds become a degree or two of face angle (the 90% target needs pitch within 3 deg and yaw within 1.5 deg).
- **The stroke is slow and sideways.** The pad moves mostly across its own face (63-68 deg off the normal) at 0.7-1.1 m/s: neither a block (velocity along the normal) nor a brush.
- **The grasp is loose.** The paddle is a free body (`freejoint`, no weld: `myoarm_tabletennis.xml`) held only by finger contact; the champion's `grip` is a contraction vector on the hand muscles (`grip_drive` 0.12; the backhand squeezes harder, `bh_grip` 0.16 and `bh_grip_drive` 0.8). In the hand's frame the paddle starts 21 deg from the model's keyframe, swings to 43 deg by 0.1 s while the fingers close (`grip_ramp` 0.096 s), settles at about 15 deg by 0.3 s, and then still turns 3-8 deg relative to the hand over the last 100-200 ms. In the final 50 ms that swivel is roughly a third to a half of the face's own turn.
- **Every joint can swing the face.** The lever of each arm and trunk joint on the normal at contact is 0.5-1.0 (forearm rotation 0.86, so it is not an idle DOF). The turning at contact is the net of several fast joints: forehand, the plane-of-elevation joint contributes about 117 deg/s and trunk flexion 44 deg/s; backhand, shoulder elevation 90, shoulder rotation 71 and wrist flexion 64 deg/s (upper bounds that ignore cancellation).
- **Caveats.** Only the normal is logged (no roll about it, so the swivel axis is unknown); the joint contributions are upper bounds; 23 of the 200 serves are never touched and are not in these numbers.

## What was already known (README)

- Round 7 (3534-3565): the backhand's face turned 163 deg/s in the last 40 ms and the grip 22 deg; wrist extension steadied the face (163 to 117-137 deg/s); "90% needs a controller whose face follows its aim, not a better aim law".
- Round 8 (3572-3614): the follow ratio of the reached face on the aim trim was 0.66 yaw / 0.53 pitch on the forehand and 0.13 / 0.28 on the backhand. The champion holds the face steady with saturated co-contraction and the wrist at its limits (extension -0.78, deviation -0.16); "face authority and stability trade against each other".
- Round 9 (3619-3678), live tracking: the contraction vector that reaches a commanded posture, from the muscles' live moment arms. It cut the backhand's command-minus-reached error from 0.80 to 0.21 rad and raised the forehand's yaw follow to 1.01, but the champion's practised parameters no longer fit (7 of 400 solved) and 16 generations of re-practice reached 18.3% (backhand) and 10% (forehand) against 25% and 40%: "needs far more practice than a few hours on this machine give".
- Round 1 (2936-2944) already built Erik's parametrization: stroke families `block` (still pad), `over` (forward and up, face closed), `chop` (forward and down, face open) and `give` (back with the ball), each a paddle velocity at contact plus the face the aim law needs (`fam_mode`, off in the champion). It did not help then, because nothing held the plane.
- T3's oracles (`scratchpad/tt3/LOG.md`): a still kinematic paddle at the best aim returns 200 of 200 serves; 90% needs pitch 3 deg, yaw 1.5 deg, pad velocity 0.2 m/s and placement 2 cm SIMULTANEOUSLY (the champion: 11.3 deg, 3.5 deg, 0.54 m/s, 4.3 cm); this needs the arm settled on a plan-exact pose (every joint within about 1.5 deg and slower than about 0.2 rad/s at contact). An ideal pad-space arm (computed-torque PD to the plan's pad centre and normal) reached only 28%, ended 6 cm and 6 deg off the plan, and the paddle left the hand on 4-25% of serves: the grasp is what breaks under an aggressive arm.

## What this says

1. The constant-plane stroke family is the right parametrization and its code home exists, but nothing HOLDS the plane, so every family collapses into the same near-still block.
2. Three separate things stack: (a) the arm does not reach its commanded posture (live tracking fixes most of it), (b) the arm is still moving at contact (the plane turns 90-160 deg/s; it has to settle), (c) the paddle swivels in a loose grasp (3-8 deg in the last 100-200 ms, about as large as the whole 3 deg pitch budget).
3. The flick stays a separate rotating-plane family (`flick_mode`, off in the champion; in round 5 it did nothing: 10 solved against 11).
4. Honest ceiling: the 2025 MyoChallenge winner scored 64%; 90% needs all four error sources 2.2-3.8x lower at once. A plane-hold controller is worth trying for a step towards 50-65%, not as a promise of 90%.

## Proposed plan, with the rules fixed before anything runs

- **Stage 0 (running, hours of wall clock, no API cost): does muscle-level tracking already hold the plane better?** The round-9 live-tracking controller (`bin/challengers/myo_tt_r9-a` with `params/myo_tt_p2_r9_lt_fh.txt` and `_bh.txt`) on serves 98000-98099 with the same probe (`scratchpad/tt4/run_lt.sh`). Read as: if the last-200-ms rotation falls to 5 deg or less on the forehand, tracking holds the plane and the missing piece is practice; if it does not fall, the arm cannot hold it with this control and the grasp and arm dynamics are the limit.
- **Stage 1: firm the grasp.** Measure the in-hand swivel (probe section 3) for firmer finger postures, NOT the score; aim for under 1 deg in the last 100 ms and a pad-centre slide under 0.5 cm. Then re-run T3's ideal pad-space servo with the firm grasp; it passes if the paddle stays in the hand on at least 95% of serves and ends within 2 cm and 3 deg of the plan (it was 6 cm and 6 deg).
- **Stage 2: plane-hold strokes on live tracking,** forehand block and drive first (91 of the 177 hits): the joints settle at least 120 ms before contact (speed at most 0.2 rad/s), the plane n* is held, the velocity vector comes from a short translation; measure the last-200-ms rotation (target 3 deg or less) and the pitch/yaw scatter at contact (5 deg / 2.5 deg or less, against 11.3 / 3.5).
- **Stage 3: re-practise** the stroke parameters at scale (hours of CPU on the quiet machine); target 50% or more on `tt_p2_300` (champion 40.0%).
- **Stop rule:** if Stage 0 and Stage 1 both fail (the plane cannot be held within 5 deg and the grasp cannot be firmed), stop the line and report it as a negative result.
- Effort: Stages 0 and 1 are hours; Stage 2 is about a day of agent work; Stage 3 is CPU time. Erik decides whether Stage 2 is worth starting.

## Stage 0 result (30 Sep, `run_lt.sh`, `compare_plane.py`, `compare_plane_report.txt`)

Serves 98000-98099, median over the hits of each side; the champion row is the same serves from T3's record.

| controller | side | hits | solved | face turns in the last 50 / 100 / 200 ms (deg) | turning at contact (deg/s) |
| --- | --- | --- | --- | --- | --- |
| champion c3 | forehand (46 serves) | 42 | 19 | 5.2 / 8.4 / 12.1 | 101 |
| champion c3 | backhand (54) | 49 | 24 | 8.2 / 18.3 / 52.2 | 139 |
| r9 live tracking, forehand-practised | forehand | 9 | 1 | 4.2 / 6.8 / 10.7 | 95 |
| r9 live tracking, forehand-practised | backhand | 43 | 0 | 12.0 / 28.6 / 65.0 | 160 |
| r9 live tracking, backhand-practised | forehand | 16 | 1 | 6.0 / 9.7 / 15.2 | 179 |
| r9 live tracking, backhand-practised | backhand | 42 | 9 | 13.9 / 30.7 / 59.9 | 233 |

Read against the rule fixed above (5 deg or less over the last 200 ms on the forehand): it does not fall (10.7-15.2 deg), and the backhand is no steadier (60-65 deg against 52). So the posture-reaching mechanism alone does not make the plane constant; the trajectory has to settle the arm before contact. Caveat: this controller was not designed to hold a plane, its practised parameters no longer fit (the forehand hits only 9-16 of 46 serves, so those medians are thin), and it is a negative on "tracking alone", not on plane-hold strokes.

## Stage 1 result (30 Sep, `run_grip.sh`, `run_grip2.sh`, `grip_table.sh`)

The champion with grip overrides only (`tt_eval --set`), serves 98000-98099; the swivel is the pad normal's rotation relative to the hand frame (probe section 3) over the last 200 / 100 ms, median; solved = serves solved of 100 (the champion's other parameters were practised around its own grip, so the score is context, not the measure).

| grip variant (overrides on the champion) | forehand swivel 200 / 100 ms (deg) | backhand swivel 200 / 100 ms (deg) | solved of 100 (hits) |
| --- | --- | --- | --- |
| champion (`grip_drive` 0.12) | 8.3 / 3.3 | 11.7 / 8.6 | 43 (91) |
| `grip_drive` 0.4 | 8.4 / 3.2 | 10.4 / 6.9 | 30 (82) |
| `grip_drive` 0.8 | 7.8 / 3.0 | 11.3 / 6.2 | 38 (89) |
| `grip_drive` 1.5 | 5.6 / 2.5 | 9.4 / 5.9 | 19 (83) |
| `gfull`: `grip_drive` 0.8, flexor groups at 0.6 (ring 0.4) | 3.4 / 2.3 | 9.7 / 3.1 | 11 (71) |
| `bhmax`: `bh_grip` 0.4, `bh_grip_drive` 0.8 | 8.3 / 3.3 | 10.7 / 7.1 | 24 (78) |
| `gmax`: `grip_drive` 2.0, flexors 0.6, extensors lengthened | 8.1 / 3.8 | 1.9 / 1.6 | 0 (22) |
| `gmaxbh`: `gmax` + `bh_grip` 0.4 | 8.1 / 3.8 | 1.7 / 1.6 | 0 (22) |

Read against the rule fixed above (under 1 deg in the last 100 ms, pad centre slide under 0.5 cm): not met. The swivel can be cut by about 60% (forehand over 200 ms 8.3 to 3.4 deg, backhand over the last 100 ms 8.6 to 3.1 deg with `gfull`, the firmest grip under which the arm still works: 71 of 100 serves hit), but never below 2 deg, and each step costs the champion's score (43 to 11 solved) because the finger flexors cross the wrist and shift the plane its parameters were practised around. Past `gfull` the arm stops working (22 of 100 hit), so the `gmax` swivel numbers rest on a handful of hits and mean little.

Second half of Stage 1 (`run_o5_grip.sh`, `o5_table.py`, `o5_table_report.txt`): T3's ideal pad-space arm servo (o5a: computed-torque PD to the plan's pad centre and normal, first-order approach with a 0.1 s time constant from 0.30 s) with the same grips, serves 98000-98099. The re-run with the champion's grip reproduces T3's recorded rows exactly (identity check).

| variant | hit | solved | paddle more than 0.5 m from the palm: before contact / after the impact / on serves that never touched the ball | pad error against the plan AT CONTACT (median) |
| --- | --- | --- | --- | --- |
| champion grip (T3's o5a) | 84 | 32 | 0 / 9 / 13 | 4.8 cm, 7.6 deg |
| `grip_drive` 1.5 | 81 | 15 | 0 / 8 / 15 | 4.7 cm, 12.4 deg |
| `gfull` | 79 | 7 | 0 / 27 / 19 | 4.7 cm, 16.2 deg |

- **Correction of an earlier reading.** The count "paddle left the hand" (T3's criterion, `palm_err_max` over the whole episode) is NOT a measure of grip failure during the stroke: in no run, for the champion's own motion or the ideal servo, does the paddle leave the hand before the ball has touched it (0 of 100 in every variant); the losses come after the impact (the champion: 8 of its 9, 0.46-0.69 s later, in the follow-through) or on serves that never touched the ball (whose timing against the miss was not checked). So the paddle is retained through contact on every serve, and "a firmer grip loses the paddle more often (22, 23, 46)" is withdrawn.
- **What does get worse with a firmer grip** is plan-following: the pad's orientation error at contact grows from 7.6 to 12.4 and 16.2 deg and the solved count falls from 32 to 15 and 7. That is not a retention effect; a different finger posture changes the paddle's pose relative to the forearm (and the extrinsic finger flexors pull the wrist), so the plan computed for the champion's grip no longer matches. The position error is the same 4.7-4.8 cm at every grip.
- **The ideal servo does not reach its plan even with the champion's grip:** 4.6 / 3.9 / 4.5 / 4.8 cm and 8.0 / 6.8 / 6.8 / 7.6 deg at 100 / 50 / 20 ms before contact and at contact, all BEFORE the impact (the 6 cm / 6-9 deg T3 reported at the servo's end is not an impact artifact). T3 found that converging faster throws the paddle out before contact (the decelerating variant, `o5_togo`: 16-17 of 24 serves), which is why the approach is gentle and too slow (an exponential with a 0.1 s time constant leaves about 13% of the initial error after the 0.2 s available); so the grasp does set how fast the servo may converge, but no grip tried removes that limit.

## Verdict

By the rules fixed before anything ran, both stages fail (tracking alone does not hold the plane; the ideal servo does not reach 2 cm and 3 deg with any grip tried), and the stop rule applies to a plane-hold stroke built from what exists. The corrected reading of WHY matters for what to try next: the paddle is retained through contact in every run, so the failure is precision and convergence time, not retention; the swivel in the hand (3-8 deg over the last 100-200 ms) is real but can only be part of it, and a firmer finger drive trades it against plan-following.

What the evidence does not settle, and the only gating experiment left: whether ANY grip lets the ideal servo converge fast enough (T3's decelerating variant, which ejected the paddle before contact on 16-17 of 24 serves with the champion's grip) while keeping the paddle until contact. That is a bounded CPU experiment (a search over the ten grip parameters with that servo as the stress test, retention before contact of at least 95% and pad error at contact of at most 2 cm and 3 deg as the pass rule; about two hours), not a day of agent work. If a grip passes, a plane-hold stroke is physically possible in this model and Stage 2 (settled arm, held plane, a short translation for the velocity vector, on live tracking, then re-practice) is worth starting; if none does, the line ends as a negative result and the honest answer to "is the paddle held strangely" is that this hand model cannot hold and steer it fast enough for a constant-plane stroke. Erik decides whether to run it; my recommendation is to stop the table-tennis line unless he wants that experiment.
