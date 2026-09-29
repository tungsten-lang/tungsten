**Round 9's live tracking, re-examined on the fast path.** With the round-9 parameters (`lt 1`) on the first 120 serves of each side pool, the forehand's face follows its aim (pitch error to the aim
-0.2 +- 2.8 degrees against the champion's -2.4 +- 9.8) and the forehand solves 5 of 120: the ready posture puts the pad at 1.36 m against a ball crossing at 1.21 (the servo error stays at -0.25 to -0.45 m from 0.31 s on) and
86% of the misses pass over the pad. A finite-difference pose Jacobian of the seven forehand posture parameters (ready pose at 0.25 s, per +0.1 rad: elbow pitch -3.9 degrees / pad +2.7 cm, `sh_elv` +1.8 cm,
`dev` -5.6 degrees, `sh_rot` yaw +4.3 degrees) and one least-squares step to the aim's mean pose raised the forehand's hit rate from 0.30 to 0.83 at once, and 1 of 60 serves solved: the returns went wide
(exit y-velocity -1.5 +- 1.7 m/s, the face's yaw 4.5 +- 5.1 degrees past the aim where the champion's forehand yaw follows to 0.3 +- 2.4). Faster height servos (`k_z` 12-20, `t_servo` 0.15) raise the hit rate to 0.5-0.6 and solve 1-2 of
120: the pad is still moving at contact (pad velocity along the normal -0.3 +- 1.0 m/s, exit speed sd 1.8). The live-tracked arm needs its aim law re-calibrated (yaw follow, restitution, the pad-velocity expectation) and its servo
re-tuned together; that is round 9's conclusion and it stands.

**Where it stands.** `tt_p2_300` TODO_ARENA. The round-5 champion's failures were the arm's: the face is 10 degrees (1 sigma) off the aim law's normal on both sides, the pad's velocity along it wanders 0.5 m/s, the ball meets the pad 5 cm off its
centre, and the success ceiling of a perfect plan at that noise is ~45% (table above). Every plan-level change (pelvis governor, contact-timed starts, aim biases, boxes, side boundary) moved the count by less than the noise. What worked
was different in kind: finding a defect (the servo's one-tick error at the bounce), restoring the retreat it had been giving by accident, and searching the backhand's parameters jointly on fixed serves (a 17-factor design, then a
posture and offset design) with validation on other serves every time. Lessons: a design run picked from 32 is a winner's curse unless it is validated on other serves (of nine design runs validated on other serves three survived: backhand runs 21, 7 and 18), the linear step of a
design generalises better than its best run, and a candidate that is the champion wherever it has no gain (c2, c3: the forehand replays the champion serve for serve) makes the arena's paired test far less noisy than one that also
moves the forehand by an unmeasurable amount (c1: +5.2 points on 600 fresh serves, +2.3 in the arena; c3: +7.4 on 900, +7.0 in the arena).

Blockers, in order: (1) face authority: the forehand's wrist sits at its extension limit, the pitch servo's follow ratio is 0.4-0.5 and the forehand's pitch error is 76% predictable from the serve, i.e. systematic, but
posture changes that remove it move the pad's place (the backhand's hit rate fell 0.87 -> 0.72-0.77 for a 5-8 degree change of its bias); (2) the pad's velocity (0.5 m/s: the arm alone 0.33-0.42), which decides the return's speed
and which the fast half of the serves need to retreat from; (3) the slide's reach for the far-left serves (the pelvis actuator's step response, kp 3500 N/m against 1000 N s/m of damping, ctrl limited to +-1 m, gets it to ~0.85 m in 0.5 s:
7% of serves cross beyond -0.8 m and are hit 33% of the time); (4) rim hits (12% forehand, 21% backhand). A controller that follows its aim to 4 degrees, 0.25 m/s and 3 cm would reach 70-90% (table above). For reference the
challenge's winner scored 64% and the best reported result is 80.3% (Diff-Muscle, arXiv 2603.08617).

What is left: the forehand is at a sharp optimum of everything screened (gain, posture, servo timing, lateral trim, kick, aim box); the backhand screens have converged around c5 (a fifth design found nothing better); a trial with
600 or more fresh serves is needed to tell c5 from c3 in the arena (the pooled 900 fresh serves say c5 by +3.2 points, p 0.007, the 300 arena seeds cannot); beyond that the arm's own noise (blockers above) is the limit.

```sh
./build.sh myo_tt_v11                         # round-10 build (every option off = the round-5 champion serve for serve); frozen copies bin/challengers/myo_tt_r10-a ... -p
TT_ENV=P2 .venv-myo/bin/python playground/tt_eval.py --params params/myo_tt_p2_r10_c3.txt --controller bin/challengers/myo_tt_r10-n \
  --seeds 710000:710600 --out out/tt_r10/mix_c3.jsonl --workers 3          # 600 fresh serves
.venv-myo/bin/python playground/tt_cmp.py out/tt_r10/champ_710000.jsonl out/tt_r10/mix_c3.jsonl                     # paired against the round-5 champion's baseline
.venv-myo/bin/python playground/tt_rsm.py design --params params/myo_tt_p2_r5_bhprac.txt --controller bin/challengers/myo_tt_r10-k --pool bh --n 100 --runs 32 \
  --set "bk=1,kk=1,kk_amp=0,kk_m1=0.27,kk_m2=-0.48,lc=1,lt_arms=0" --out out/tt_r10/rsm_bh3 --factors "kk_amp:0:1,...,bh_gain:0.92:1.05,..."   # scratchpad/tt/rsm_run3.sh
.venv-myo/bin/python playground/tt_rsm.py analyze --out out/tt_r10/rsm_bh3
.venv-myo/bin/python playground/tt_r10_compose.py --bh out/tt_r10/rsm_bh3:21 --set bk=2 --write params/myo_tt_p2_r10_c2.txt     # backhand of run 21 + the champion's forehand
.venv-myo/bin/python playground/arena.py eval tt_p2_300 --params params/myo_tt_p2_r10_c3.txt --controller bin/challengers/myo_tt_r10-n --note "round 10 c3 ..." --promote
```

Campaign log with every command line, pid and result: `scratchpad/tt/LOG.md`; outputs `out/tt_r10/`; analysis scripts `scratchpad/tt/an*.py`.
