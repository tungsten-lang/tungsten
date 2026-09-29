**What the champion loses on** (600 fresh serves, seeds 710000-710599, none used before; `out/tt_r10/champ_710000.jsonl`):
solved 182 of 600 = 30.3% (forehand 110 of 290 = 37.9%, backhand 72 of 310 = 23.2%), hit 80.2%. Of the serves the pad meets, 62% still fail.

| serve speed quintile (m/s) | 3.7-4.7 | 4.7-5.2 | 5.2-5.7 | 5.7-6.1 | 6.1-7.2 |
| --- | --- | --- | --- | --- | --- |
| solved | 43% | 42% | 28% | 17% | 22% |
| hit | 70% | 85% | 86% | 79% | 81% |

| ball crosses the pad plane at y (m) | serves | hit | solved | solved given a hit |
| --- | --- | --- | --- | --- |
| below -0.8 (backhand) | 45 | 0.33 | 0.07 | 0.20 |
| -0.8 to -0.4 (backhand) | 102 | 0.81 | 0.15 | 0.18 |
| -0.4 to 0 (backhand) | 123 | 0.90 | 0.36 | 0.40 |
| 0 to 0.4 (forehand from 0.1) | 111 | 0.87 | 0.41 | 0.46 |
| 0.4 to 0.8 (forehand) | 120 | 0.91 | 0.44 | 0.49 |
| above 0.8 (forehand) | 99 | 0.67 | 0.22 | 0.33 |

- Fast serves are hit and come back too fast: a still pad returns ~0.95 of the ball's speed, and above ~5.5 m/s the set of pad pitches
  whose return clears the net and lands narrows to 8-13 degrees (25 degrees at 5 m/s). Success is 95-97% when the return's exit
  elevation is within 5 degrees of the centre of the feasible window and 55-60% at 5-15 degrees off; 31% of all hits have no
  feasible elevation at their exit speed and azimuth (68% of those leave at more than 25 degrees of azimuth: rim deflections).
- Failure classes (share of serves): forehand solved 37.9, no hit 19.3, net 16.2 (+2.8 rim), long 11.4, wide 6.2, rim-not-toward-net 4.1;
  backhand solved 23.2, no hit 20.3, wide 13.2, long 11.9, rim-not-toward-net 9.7, net 9.4, own half 4.8.
- Execution noise at contact (instrumented run, 150 serves, deterministic replay of the same serves): pad pitch 10 degrees (1 sigma) off the aim law's,
  yaw 2.3 (forehand) / 7.6 (backhand); pad velocity along its normal +0.4 +- 0.5 m/s forehand, -0.2 +- 0.5 backhand (the pelvis alone +0.54 +- 0.26 and
  -0.52 +- 0.31), every velocity component sd 0.55-0.63 m/s, changing 0.3-0.4 m/s rms over the last 30 ms; the forehand's ball meets the pad 5.4 (height) x
  2.6 (lateral) cm sd off centre, the median in-plane offset is 5-7 cm of a 9.3 cm radius (round 7's table: hits under 3 cm off solve 67%, 6-9 cm 31%, rim hits 5%).
- Serve features explain a lot of the face error and little of the height error. A linear map of the serve's launch state (where and when it crosses x = 1.8:
  t, y, z, vx, vy, vz) predicts the forehand's pitch error to the aim to R^2 0.76 (5-fold CV; 0.90 with the contact time; residual 4.9 of 9.9 degrees), the backhand's to 0.37,
  the forehand's ball-minus-pad height offset only to 0.05 (0.26-0.46 backhand): the arm's face is set by the serve, its height is not.

**The success ceiling against execution noise** (`tt_ceiling.py`; offline model, best plan per serve, the champion's own contact conditions):

| pitch sd | pad-velocity sd | yaw sd | P(lands given a sweet-area hit) | ceiling P(success) at position sd 5 / 3 / 2 cm |
| --- | --- | --- | --- | --- |
| 10 deg | 0.5 m/s | 2.5 deg | 0.59 | 0.45 / 0.58 / 0.59 |
| 6 | 0.35 | 2.5 | 0.78 | 0.59 / 0.76 / 0.78 |
| 4 | 0.25 | 2.0 | 0.91 | 0.70 / 0.90 / 0.91 |
| 3 | 0.2 | 1.5 | 0.98 | 0.75 / 0.96 / 0.97 |
| 2 | 0.12 | 1.0 | 1.00 | 0.76 / 0.98 / 1.00 |

The champion runs at about 10 degrees, 0.5 m/s and 5 cm: with a perfect plan its ceiling is ~45%, it plays 30-33%. 90% needs the face within 4 degrees,
the pad's velocity within 0.25 m/s and its place within 3 cm at once: three to four times quieter than this arm (round 9's live tracking gets the forehand's face to
2.8 degrees of its aim in one probe and loses the height, see below).

**A fast harness** (`tt_fast.py`): one env per worker process and a kinematics-only geometry sweep give bit-identical episodes at 0.13 s of setup instead of 1.7 s
(`tt_fast.py check`: identical on every metric). A job queue runs 120-300-serve screens in 2-5 minutes; every comparison below is paired on the same serves.
