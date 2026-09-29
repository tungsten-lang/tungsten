## Touch-only sprint: one keyframe at toe-touch, bursts in between

Erik's test: "model the toe touches with everything in between eased ... toe-touch
followed by max power on the muscles that give a sprint its speed."
`SprintTouchSkill` (`lib/robolab/skills/sprint_touch.w`, `bin/robolab_sprint_touch`)
has ONE keyframe, the right touchdown (the left is its mirror). The stride is two
chunks, touch -> touch, each a single spline to the next touchdown pose, latched
on the swing foot's contact; there is no mid-stance, toe-off or knee-lift target.
Everything between the touches is the reflexes holding that spline plus
phase bursts on the sprint muscles, each leg timed on its own sensed touchdown
and toe-off (Dorn, Schache & Pandy 2012: the plantarflexors give the support
that buys stride length up to ~7 m/s, the hip muscles the swing that buys
frequency; Morin et al. 2015: end-of-swing hamstring activity drives
horizontal force):

| phase | burst (searched level, onset, duration) |
| --- | --- |
| stance, from touchdown, latched off at toe-off | gluteus + hamstrings (hip extension), soleus + gastrocnemius (push); vasti pulse at landing; the iliopsoas + rectus femoris swing burst may start in late stance (pre-swing) |
| swing, from toe-off | iliopsoas + rectus femoris (knee drive), knee flexors (heel tuck) |
| late swing, from the other leg's toe-off | hamstrings + gluteus ("claw": brake the shank, pull the foot back), pre-landing vasti and soleus tone |

Feedback is run_natural's: the hop-height loop (k_z, k_zk), the SIMBICON
stance-hip trunk servo with the swing-hip reaction, the trailing leg as the
torso's reaction mass in flight, and Raibert foot placement from speed with
swing-leg retraction.

**What it took.** With alternating keyframes the Catmull-Rom tangent at every
touch is zero, so a pure touch-to-touch spline dwells at each touch: the stance
leg's command drifts toward the trailing posture (the knee folds while it should
push) and the swing thigh sits at ~30 deg, so bursts alone had to swing it.
Every such gait fell within two steps, at every speed and from every start,
including snapshots of the champion's own running state. The lever that
made it run is still a touchdown keyframe: **the keyframe carries each leg
joint's velocity at the touch** (`w_st_*` / `w_sw_*`, a quintic `Chunk#knot`),
so the one touch -> touch segment bends between touches: the landing hip
arrives retracting and sweeps on back through stance, the trailing hip leaves
the touch swinging forward, overshoots into the knee drive and comes back into
the next touch. Survival went from 0.6 s to 2 s at once, and the search took it
from there. The found touchdown: landing hip 18 deg, knee 26 deg; trailing hip
50 deg, knee 130 deg (Bolt's max-velocity touchdown: 28 / 4, trailing 18 /
140); touch velocities landing hip -7, trailing hip +15, trailing knee +25 rad/s.

Other pieces the stride needed: a toe-off confirmed after 12 ms unloaded (the
foot rocking heel to toe unloads mid-stance), a touchdown only ahead of the
stance foot (a trailing toe scuffing behind is not a step), the claw timed on
the *other* leg's toe-off (a fixed delay after the own toe-off yanked the thigh
back mid-swing), and a pre-swing iliopsoas onset in late stance.

**Practice** (sep-CMA, every stage on a frozen binary; training seeds 31-42,
held-out checks 51-62): (1) flying starts from snapshots of the run_v2 champion's
steady running (5 m/s) and then of its acceleration (1.6-4.9 m/s), a "pace"
score (distance, a 10-point fall penalty: running on beats surviving slowly;
a 30-point one let the search stop and stumble); (2) the standing start, with
its own push posture (`s0`, start only); (3) perturbed standing starts, 15 s x
4 and 20 s x 6.

| | touch-only, v3 average body (`params/sprint_touch_v3.txt`) | run_v2 champion, same body (RunSkill) | human ~5 m/s |
| --- | --- | --- | --- |
| steady speed (last 10 strides), peak 1 s | 4.62-4.68, 4.72 m/s | 5.00, 5.06 m/s | |
| step rate, step length | 3.0-3.2 /s, 1.44-1.55 m | 2.8 /s, 1.78 m | ~3.0 /s, ~1.7 m |
| contact, flight | 0.196 s, 0.107 s | 0.196 s, 0.145 s | ~0.20 s, ~0.13 s |
| peak vertical GRF | 4.0 body weights | 4.0 | ~2.5-3 |
| trunk lean | 14 deg | 28 deg | ~8-10 deg |
| 100 m from standing | 24.3 s | 22.8 s | |
| kin_rms vs the human reference at the measured speed | **15.7 deg** | - | 0 |

(Human: Dorn et al. 2012, Weyand et al. 2000, Hamner & Delp 2013, as in
tasks/run_natural_fast.py.) Arena: **`run_natural_fast` champion** (10 of 12
perturbed starts in the 4.5-6 m/s band for 30 s, kin_rms 15.5-15.9 deg; the
previous champion failed every start: p = 0.001). It loses `run_v2` (11/12 at
~4.6 m/s against 5.00) and `sprint_top_speed` (10/12 against 5.05). On the
rigid-tendon v2 body the v3 params run 13.6 s and fall; one v2 stage
(`tasks/sprint_touch.py`) holds 3/3 held-out 30 s starts at 4.48 m/s.

Which bursts matter (average body, each burst zeroed on 3 held-out 20 s
starts; `scratchpad` ablation): the gait **falls without** the stance
hamstrings (3.9 s), the stance gastrocnemius (9 s), the swing iliopsoas (2.4
s), the pre-landing vasti + soleus tone (7 s) or the touch velocities (2 s);
the **landing vasti pulse is worth 0.72 m/s** (4.63 -> 3.91); the stance gluteus
and soleus bursts, rectus femoris, heel tuck and both claw bursts change
nothing here (the stance-hip trunk servo already saturates the gluteus, and the
touch velocities already retract the landing leg). The search itself turned
the stance soleus burst down to 0.05 and kept a strong pre-landing
plantarflexor tone (0.66).

### Full power and reciprocal inhibition

Erik: "make sure you're using full power in the large muscles in the stride."
`Controller#set_reciprocal(pairs, k)` (opt-in, spec-tested) scales an
antagonist's activation by `1 - k * drive` of its agonist; `ri <k>` switches
it on in SprintTouchSkill and in `RunRISkill` (`lib/robolab/skills/run_ri.w`,
`bin/robolab_run_ri`: RunSkill unchanged plus the switch), per leg for hip
flexors / extensors, knee flexors / vasti, soleus / dorsiflexors, rectus
femoris / hamstrings and gastrocnemius / dorsiflexors. Full drive = RunSkill's
push drives (vasti, soleus, gastrocnemius, gluteus, hamstrings) and swing
hip-flexor drive at 1.0.

| P95 body (`sprint_top_speed_p95`, 12 perturbed starts) | peak 1 s speed | vs previous |
| --- | --- | --- |
| previous champion (RunSkill re-tuned on P95) | 5.97 m/s | |
| **RunRI: k 0.5 + full drives, re-tuned** (`params/run_ri_p95.txt`) | **6.663 ± 0.009** | **+0.70, p < 0.001: champion** |
| control: same full drives, no RI, same kind of re-tuning (`params/run_full_p95_control.txt`) | 6.544 ± 0.007 | RI's paired effect +0.12 m/s on 12/12 starts |
| the RunRI params with RI switched off | falls in 4.4-5.6 s | RI is load-bearing in that gait |
| average body (`sprint_top_speed`): RunRI re-tuned from the champion | 4.84 | -0.21 against 5.05 (2900 rollouts did not catch up) |

So on P95 most of the gain is re-tuning with full drives (+0.58), and
reciprocal inhibition adds +0.12. Activation (P95, 16 s, steady tail;
`acttable` in the practice notes):

| group (both legs) | champion: stance % >= 0.9, mean | RunRI: stance % >= 0.9, mean | champion: swing mean | RunRI: swing mean |
| --- | --- | --- | --- | --- |
| hip extensors | 90 %, 0.97 | 75 %, 0.93 | 0.39 | 0.34 |
| hip flexors | 6 %, 0.24 | 0 %, 0.23 | 0.77 | 0.79 (61 % >= 0.9) |
| hamstrings | 68 %, 0.91 | 75 %, 0.93 | 0.43 | 0.39 |
| vasti | 79 %, 0.93 | 67 %, 0.89 | 0.24 | 0.25 |
| soleus / gastrocnemius | 53 / 38 %, 0.71 / 0.69 | 55 / 41 %, 0.70 / 0.66 | 0.10 / 0.22 | 0.11 / 0.24 |
| mono knee flexors / dorsiflexors | 8 / 16 %, 0.31 / 0.38 | 5 / 19 %, 0.29 / 0.39 | 0.92 / 0.72 | 0.87 / 0.73 |
| co-contraction index (stance) hip / knee / ankle / ham-rf | 0.37 / 0.44 / 0.37 / 0.53 | 0.40 / 0.42 / 0.33 / 0.41 | | |

The whole-cycle view (soleus >= 0.9 only 13 % of the time, knee flexors 65 %)
mixes phases: in stance the champion's prime movers already run near full
(gluteus 90 %, vasti 79 %, soleus mean 0.71), and the high knee-flexor and
dorsiflexor activity is the swing's heel tuck and toe clearance. RI mainly
removed stance co-contraction at the ankle and between hamstrings and rectus
femoris.

