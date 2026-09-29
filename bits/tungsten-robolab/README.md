# robolab: a muscle-contraction control plane

robolab drives a body the way the nervous system is thought to: not with
joint torques but with **contraction vectors**, one entry per muscle.
Compound movements are **chunks**, contraction-rate vectors applied over a
short time with human-like easing, every muscle moving at once. Chunk
boundaries **latch** on sensation (a foot loading, a palm touching a ball, a
pitch leaving the hand), and chunks can carry **real-time corrections** (a
swing re-aimed at a ball's predicted path) that are eased in through
springs so nothing ever steps.

```
            skill (Tungsten)                                  body (MuJoCo today)
 ┌──────────────────────────────────────────┐   S line   ┌────────────────────────┐
 │ Movement = [Chunk, Chunk, ...]  per Track │ <───────── │ proprioception:        │
 │   Chunk: rate / to / pose goal, easing,   │  sensors   │  c, cdot, force /muscle│
 │          latch, drive, gain, correction   │            │ contacts, IMU, COM,    │
 │ commanded contraction c*  (+ springs)     │            │ task objects (ball...) │
 │ Reflex (lambda model): a = f(c* - c, cdot)│ ─────────> │ muscles (MuJoCo        │
 └──────────────────────────────────────────┘   A line   │  <muscle>, FLV + act.) │
                                              activations └────────────────────────┘
```

## The model

- **Muscles come in antagonist pairs.** Joint `j` has `j_pos` (pulls the
  angle up) and `j_neg` (pulls it down). Contraction `c` is the fraction of a
  muscle's length range it has shortened through (0 = long, 1 = short), so
  `c_pos + c_neg = 1` across a joint. A commanded pair that sums above 1 is
  **co-contraction**: stiffness without motion.
- **Contraction vector** (`Contraction`): the state of the plane. `Pose`
  builds one from joint angles plus stiffness (`pose.set("l_knee", 0.6, 0.05)`).
- **Rate vector** (`Rate`): contraction per second. A chunk given `rate(v)`
  arrives at `start + v * duration`; `to(c)` or `pose(p)` give the goal
  directly. The easing (`min_jerk` by default, the Flash & Hogan human
  profile) shapes the velocity so the average rate is the rate vector.
- **Latch** (`Latch.contact`, `.release`, `.after`, `.above`, `.below`,
  `.test(label, ->(frame, elapsed, ctl) ...)`, `.any`, `.all`): a chunk holds
  its goal after `duration` until its latch fires; an early latch cuts it
  short. `after_min(s)` ignores the latch for the first `s` seconds.
- **Drive**: a feed-forward activation burst on top of the reflexes (push-off,
  the start of a swing). **Gain** scales the reflexes (loose vs firm).
- **Correction**: `correct(->(frame, ctl) offsets)` returns a length-n array of
  contraction offsets each tick; a critically damped spring (after
  pmndrs/math's `spring.damp`) eases them in and back out.
- **Branching**: `followed_by(name)` names the chunk that follows (default:
  the next in the movement); `branch(->(frame, ctl) name_or_nil)` chooses it
  at run time, so gaits, rallies and choreographies need no hand-built router.
- **Via-points**: `via` makes a chunk's goal a keyframe the motion passes
  through (Catmull-Rom velocity toward the next goal, cubic Hermite), and the
  next chunk inherits that velocity, so a series of contraction vectors eases
  as one smooth motion instead of stopping at every keyframe.
- **Quintic keyframes**: `knot(vel, acc)` makes a chunk's goal a C2
  keyframe: the command arrives with a given contraction velocity and
  acceleration per muscle, and the next knot chunk starts from that state
  (quintic Hermite; zero knots are exactly min-jerk). A run of knot chunks
  is a linear convolutional decoder of its keyframe vectors (see
  `playground/SEARCH.md`, "P6").
- **Convolutional policy** (`ConvPolicy`, `tcn.w`): a small residual causal
  TCN that reads ~0.2 s of proprioception and adds a correction to the
  command each tick, called from `Skill#after`; its last layer starts at
  zero, so it starts as the hand-authored controller.
- **Knot trains** (`RunKnotsSkill`, `skills/run_knots.w`): a gait's stride
  as a periodic train of quintic knots, one per gait event (the left step
  mirrored), so imitating a reference is a least-squares fit and the
  command-to-motion gap is closed by iterative learning control from
  per-stride error curves (`playground/runknots.py`; SEARCH.md, "P7"). On the
  runner it rides as a zero-initialised residual on the posture keyframes.
- **Staggered timing**: `stagger(muscles, delay, easing, duration)` lets
  muscle groups inside one chunk start late or move on their own easing, so a
  single rate vector can carry limbs that move at different times (a bound's
  stance knee yields while the swing knee folds).
- **Reflex** (`Reflex`): the spinal layer, after Feldman's equilibrium-point
  (lambda) model. `a = clamp(drive + g * (kp * (c* - c) - kd * cdot), 0, 1)`:
  the command sets threshold lengths and stretch reflexes find the forces.
  `ctl.reflex.set_integral(muscles, ki, limit)` adds an opt-in, clamped
  integral of the contraction error (postural tone), which removes the
  steady-state sag a proportional servo leaves under gravity.
  `ctl.set_reciprocal(pairs, k)` (opt-in; off by default) adds reciprocal
  inhibition: while a muscle carries feed-forward drive, its antagonist's
  activation is scaled by `max(0, 1 - k * drive)` (both ways per `[a, b]`
  pair), so a burst on a prime mover is not fought by its antagonist's
  stretch reflex (see "Touch-only sprint").
  `ctl.reflex.set_velocity_reference(muscles, w)` (opt-in; off by default,
  spec-tested) replaces the damping term `kd * cdot` with
  `kd * (cdot - w * cdot*)` for those muscles, `cdot*` being the rate of the
  muscle's target (command plus correction, computed by the controller each
  tick, clamped to +-10 /s): the plain term brakes every fast movement, the
  agonist's shortening and the antagonist's stretch alike, so a chunk that
  commands a velocity (a quintic knot) is tracked instead of braked. With it
  off the activations are bit-identical to before (checked tick by tick on
  the dribble and p95-sprint controllers).
- **Internal-model feed-forward** (MyoSuite bodies): `ctl.enable_feedforward(
  muscles, gain)` splits the gravity + Coriolis torque at each joint (the
  bridge's `bias` sensor) over the muscles able to supply it, using their
  moment arms and peak forces (`MFORCE`), and adds it as drive; the reflexes
  then only correct what the model misses. Holding a posture on the
  table-tennis body, it cut the settled joint error from 0.20 to 0.14 rad and
  effort from 0.43 to 0.33. `ctl.set_feedforward_torque(tau)` adds any other
  per-joint torque the same way (e.g. inverse dynamics from the bridge's
  opt-in `mcol_<joint>` mass-matrix columns), and
  `ctl.set_feedforward_allocation(groups, couplings)` solves joint groups
  together over equality-coupled joints (see "Table tennis: execution").
- **Tracks** run movements in parallel on disjoint muscle masks (legs
  running while an arm dribbles). A `Skill` builds tracks in `start`,
  declares tunables with `param(name, default, lo, hi)`, and gets `before` /
  `after` hooks each tick for task logic.

## Layout

| path | what |
| --- | --- |
| `lib/robolab/*.w` | the SDK: `easing` (Easing, Quintic, SpringVector), `body` (Muscle, Body), `contraction` (Contraction, Rate, Pose), `sensors` (Schema, Frame), `latch`, `chunk` (Chunk, Movement), `reflex`, `controller` (Track, Controller), `link` (StdioLink, Robolab.serve), `skill` (Skill), `tcn` (CausalConv, ConvPolicy) |
| `lib/robolab/skills/*.w` | skills (one class each) |
| `lib/entry/<skill>.w` | a controller binary per skill (`./build.sh <skill>` -> `bin/robolab_<skill>`) |
| `playground/body.py` | MJCF generator for the muscle humanoid (planar / free / pivot roots) |
| `playground/body_profile.py`, `playground/profiles/*.json` | population-percentile bodies (`p50`, `p95`): opt-in multipliers with their sources (`ROBOLAB_PROFILE`) |
| `playground/sprint_limits.py` | ideal-control sprint capacities (joint speeds, stance force, swing time) and Weyand's top-speed model |
| `playground/bat_power_diag.py`, `bat_ceiling.py`, `bat_program_export.py` | the batter's power diagnostics (kinematic chain, joint speeds against their limits, activation timing and co-contraction), its ideal-control swings (CMA-ES over open-loop excitations, on the real pitch with `--ball`) and their export as the v6 swing program (see "Batting: bat speed") |
| `playground/bridge.py` | MuJoCo bridge and protocol; `python playground/bridge.py <task> --video out/x.mp4 --gif out/x.gif --sheet out/x.png` |
| `playground/render.py` | activation-tinted rendering with a contraction HUD |
| `playground/practice.py` | CMA-ES over a skill's tunables: `python playground/practice.py <task> --gens 40 --workers 3 --out params/<task>.txt`; `--method <name> --budget <rollouts>` picks another optimizer |
| `playground/search.py`, `playground/SEARCH.md` | 13 search methods (CMA-ES, sep-CMA, IPOP, GA, (1+1)-ES, random, CEM, DE, OpenAI-ES, Nelder-Mead, pattern, BO, MAP-Elites) behind one ask/tell interface with rollout budgets and robust multi-seed scoring; SEARCH.md benchmarks them and recommends a method and a representation per kind of problem |
| `playground/tasks/<task>.py` | scene, sensors, metrics, score and camera per task |
| `params/<task>.txt` | practised parameters (`--params params/<task>.txt`) |

## Setup

```sh
cd bits/tungsten-robolab
uv venv --python 3.12 .venv && uv pip install --python .venv/bin/python mujoco numpy imageio imageio-ffmpeg pillow
./build.sh
.venv/bin/python playground/bridge.py stand --video out/stand.mp4
```

## Protocol

See the docstring of `playground/bridge.py`. One `S` line of sensation in,
one `A` line of activations (plus commanded contractions, the chunk label,
and task commands such as `grip:l:0`) out, every 5 ms. The controller never
sees MuJoCo; any transport that carries the lines can host it.

## v3 anatomy: series-elastic tendons

MuJoCo muscles have rigid tendons, so a v2 leg stores no energy in stance and
returns none at push-off; human running and jumping lean on the Achilles and
patellar tendons for exactly that. `HumanoidV3Builder` (`playground/body.py`,
opt-in; v1 and v2 are untouched) is the v2 body with a compliant tendon in
series with the fibres of the plantarflexors (`ankle_pos` = soleus, `gas`:
the Achilles tendon) and the knee extensors (`knee_neg` = vasti, `rf`: the
quadriceps and patellar tendons). Each elastic muscle-tendon unit is two
elements in series:

```
 skeleton joints q ──[ tendon <m>_see: F_T = K max(0, L_MTU(q) - x) ]── fibre DOF x <m>_fiber ──[ MuJoCo <muscle> <m> ]
```

- the **fibre** is the unchanged v2 `<muscle>` (force-length-velocity curves,
  peak force, vmax, activation dynamics and length range copied exactly) acting
  on its own slide DOF `x`, on a weightless body, so it touches the skeleton
  only through the tendon;
- the **tendon** is a fixed tendon of length `L_MTU(q) - x` (`L_MTU` = the v2
  muscle's path) with a linear, tension-only spring (MuJoCo tendon stiffness,
  dead band below the slack length).

| parameter | value | source |
| --- | --- | --- |
| Achilles (soleus + gastrocnemius) | 200 N/mm at a 5.0 cm moment arm: 500 N m/rad about the ankle | in vivo Achilles stiffness ~150-250 N/mm at running loads (Lichtwark & Wilson 2005; Magnusson et al. 2003); moment arm ~5 cm (Maganaris et al. 1998) |
| quadriceps (vasti + rectus femoris) | 250 N/mm at 4.5 cm: 506 N m/rad about the knee | whole knee-extensor series elasticity (quadriceps tendon, patellar tendon, aponeurosis; Kubo et al.'s tendon-aponeurosis values); the free patellar tendon alone is ~2-4 kN/mm (Hansen et al. 2006) |
| sharing within a group | by peak torque about the joint (each muscle stretches the same joint-equivalent amount at peak) | a shared tendon |
| slack length | the fibre at a slack tendon is exactly as long as the v2 muscle | same posture-to-contraction map as v2 |
| fibre inertia | 1.0 kg per group at the moment arm (fibre-tendon mode ~450-500 rad/s) | effective belly mass, rounded up for numerics |
| fibre damping | 0.1 F0 / (vmax L0) | Millard et al. 2013 damped fibre |
| tendon losses | none (lossless spring) | real tendons return ~90-95 % |
| timestep | 1 ms (control stays at 4 ms) | drop-jump tendon energy within 3 % of 0.25 ms (2 ms: 6 %) |

**Contraction and geometry.** The bridge reports contraction from each
actuator's length, which for an elastic muscle is its fibre: `c` and `cdot`
are spindle (fibre) signals and the reflexes act on them. The posture
geometry sent to the controller (`JOINT` / `MLEN` / `MRANGE`) is the whole
MTU path (fibre + tendon; the builder's `muscle_geometry`, which the bridge
uses when a builder has one): a `Pose` maps to the fibre contraction that holds
it with a slack tendon, and under a load F the fibre sits F / K shorter, which
the reflexes see as error. Fibre DOFs are internal and never appear as joints.
Tasks call `settle_fibers(m, d)` after their reset so every tendon starts at
its slack length. The v3 tables equal v2's exactly.

**Tools.** `playground/tasks/run_v3.py` and `long_jump_v3.py` (the v2 skills;
`bin/robolab_run_v3` and `bin/robolab_long_jump_v3` are copies of the v2
builds; env `ROBOLAB_V3_TIMESTEP`, `ROBOLAB_V3_TENDON_SCALE`, and
`ROBOLAB_V3_RIGID=1` for the rigid v2 body at the v3 timestep), and
`playground/tendon_v3.py`, which does the hopping and drop-jump validation
(`validate`) and the per-stance tendon, fibre and MTU energetics of any run or
jump (`stance`). `playground/eval_v3.py` scores params with the v2 protocols
(clean 40 s + 12 held-out perturbed starts; nominal + 12 perturbed jumps).

**Validation** (`out/tendon_v3_hop_validation.json`): the same spinal
controller (positive force feedback on soleus, gastrocnemius and vasti) on the
rigid and elastic bodies. A 30 cm drop jump rebounds 0.187 m elastic vs 0.152 m
rigid at the same fibre work (~248 J); the tendons store and return 79 J, 28 %
of the muscle-tendon units' positive work. Repetitive hopping: 85 J peak
Achilles energy, 88 of 90 J stored returned per cycle, tendon recoil 39 % of
MTU positive work (27-43 % at 0.5-2x stiffness). Timestep: the drop jump's
returned tendon energy at 1 ms is within 3 % of 0.25 ms (6 % at 2 ms) and its
rebound 0.18-0.20 m at every step size (the periodic hopper settles into
different limit cycles at different steps, so it is not the convergence test).

**Sprint** (`out/run_v3_metrics.json`; clean 40 s + 12 held-out perturbed
starts, `playground/eval_v3.py`). All strength 1.0 with v2's muscle speeds; the
control is the rigid v2 body at the v3 timestep through the identical practice
stages and budgets (sep_cma from `params/run_v2.txt`: 1500 clean + 2500 robust
rollouts).

| | v2 rigid, 2 ms (`params/run_v2.txt`) | v2 rigid, 1 ms, same practice as v3 | **v3 elastic** (`params/run_v3.txt`) |
| --- | --- | --- | --- |
| steady speed (last 10 strides) | 4.04 m/s | 4.58 m/s | **5.00 m/s** |
| 100 m from standing | 27.8 s | 24.9 s | **22.6 s** |
| perturbed starts surviving 30 s | 12/12 (4.04) | 10/12 (4.52) | **12/12 (5.00)** |
| arena `run_v2` (seeds 201-212, paired) | 4.04 | 4.53 (-0.47 vs v3) | **4.998** (champion, +0.96, p < 0.001) |
| step length, frequency | 1.34 m, 3.0 /s | 1.53 m, 3.0 /s | 1.79 m, 2.8 /s |
| contact, flight time | 0.20, 0.11 s | 0.18, 0.14 s | 0.20, 0.15 s |
| ankle positive work per stance | 48 J | 88 J | 123 J |
| Achilles: peak energy, recoil per stance | - | - | 63 J, 59 J |
| tendon share of plantarflexor MTU positive work | 0 | 0 | 42 % (Achilles recoil = 48 % of ankle positive work; human running ~35-50 %) |

About half of the gain over the recorded v2 sprint is re-practice (the rigid
control reaches 4.58), the other half (+0.43-0.47 m/s at equal practice, and
12/12 instead of 10/12 robust starts) is the tendons: at the same
plantarflexor fibre work per stance (103 J), the elastic units deliver 139 J to
the skeleton against the rigid 103 J. 5.0 m/s is a trained distance runner's
pace; the 22.6 s 100 m is far from human sprinting (elite 9.6 s, recreational
13-17 s): no metric exceeds human ability at normal strength.


**Long jump** (`out/long_jump_v3_comparison.json`; `params/long_jump_v3.txt`,
LongJumpSkill re-practised in six sep_cma stages from `params/long_jump_v2.txt`,
run-up 12.74 m from a check-mark scan):

| | v2 rigid, 2 ms | v2 rigid, 1 ms, same practice | **v3 elastic** |
| --- | --- | --- | --- |
| nominal start, official (effective) | **1.88 m** (1.94) | 1.54 m (1.64, own check mark) | 1.39 m (1.76); stage E 1.65 (1.92) |
| arena `long_jump_robust`, 16 held-out perturbed starts | 1.15 m | 0.71 m | **1.47 m** (champion, +0.33, p = 0.002) |
| 12 perturbed starts (100-111): legal, mean official | 10/12, 1.32 m | - | 11/12, 1.43 m |
| take-off velocity, contact | 3.45 m/s at 14°, 0.33 s | 3.51 m/s at 13°, 0.22 s | 3.99 m/s at 13°, 0.26 s |
| take-off stance: quadriceps tendon recoil | - | - | 73 J (62 % of knee-extensor MTU positive work) |

The tendons buy a faster run-up and take-off (+0.5 m/s) and a shorter board
contact, and the robust jump beats the rigid body's on paired perturbed starts,
but the nominal-start record stays with v2 (the arena's single-start
`long_jump_v2` trial: v3 1.65 vs 1.875). Latching take-off on the COM state and
gating the landing latch on a low, falling COM (`LongJumpComSkill`,
`lib/robolab/skills/long_jump_com.w`, switches `com_to` / `com_td`) changed
nothing on either body (paired +0.002 m, p = 0.5). About 1.5-1.9 m is far below
human jumps (amateurs ~5-6 m, record 8.95 m): the practised approach is only
~4 m/s and the take-off angle ~13°. The sprinter's run-up (LongJumpRunSkill,
below) takes it to 1.85 m robust / 2.47 m on one start on this body.

## Bodies: population percentiles (p50 / p95)

Every body above models an AVERAGE young man: strength 1.0, v2's calibrated
muscle speeds (V2_OMEGA), v3's mean tendon stiffnesses, a 1.75 m / 67.5 kg
skeleton. `playground/body_profile.py` rescales any builder to a population
percentile from a profile file, `playground/profiles/<name>.json`, which holds
every multiplier with the statistic it stands for, its sources and whether a
population statistic backs it. Opt-in: unset, every builder emits exactly its
old XML (checked on all 19 task bodies), and `p50` (all 1.0) is byte-identical
too.

| part | p95 | statistic (young men) | sources | verified |
| --- | --- | --- | --- | --- |
| `strength` | peak force x1.32 | P95 of joint torque per kg (size-normalised CV ~18-22 %) | Maden-Wilkinson et al. 2020 (knee extension 245 ± 43 N m, CV 17.6 %); NHANES 1999-2002 knee extension (torque/kg CV 22.1 %, empirical P95 x1.34); Fujimori & Sado 2025 (plantarflexion CV 18 %); Harbo et al. 2012 (size explains ~25 % of the variance) | yes (knee, ankle; hip assumed alike) |
| `speed` | vmax x1.20 | P95 joint speed = fibre-type mix x fascicle length | Staron et al. 2000, Simoneau & Bouchard 1989 (type I 41 ± 10-12 %); Trappe et al. 2015 (Vo IIa 3.4x, IIx 5.0x type I): x1.15-1.20; fascicle length CV ~10 % (Maden-Wilkinson 2020): combined ~x1.22 | yes |
| `tendon` | stiffness x1.50 | P95 in vivo stiffness (CV ~31 % net of measurement error) | Achilles 258 ± 86 N/mm (Fujimori & Sado 2025), CV ~34 % (Lichtwark & Wilson 2005); patellar CV 25-46 % (Alegre 2016, Murtagh 2018) | yes |
| `activation` | time constants x0.87 (8.7 / 34.8 ms) | inferred from the P95 fibre mix (type II twitches ~2x faster) | no population distribution exists (RFD 0-50 ms CV 43 %, Tillin et al. 2010) | **no** |
| `anthro` | lengths x1.065, mass x1.134 | P95 stature (1870 vs 1756 mm) at constant BMI | ANSUR II men (n = 4082); NHANES 2015-18 men 20-39 (x1.066) | yes |
| joint ranges | not applied | CDC normal ROM study, men 20-44 | the model's hip extension (34°) and dorsiflexion (34°) already exceed the P95 passive range (27.5°, 23°) | yes |

Strength and tendon stiffness are per unit of body size. `anthro` scales the
skeleton (every length, mass, capsule radius at constant density, the starting
pelvis height: 1.86 m, 76.5 kg, pelvis 1.017 m) and scales joint torques and
tendon stiffnesses with body mass (moments ~ m^1, Jaric 2002), so strength per
kg stays the strength part's alone. Joint angles and the JOINT / MLEN / MRANGE
geometry do not change; practised distances (COM leads, clearances) do.

Use: `ROBOLAB_PROFILE=p95` gives every task's builder the four muscle parts;
`ROBOLAB_PROFILE_PARTS=all` (or e.g. `strength,anthro`) picks parts, so each
can be tested alone; builders take `profile=` / `profile_parts=` too (explicit
arguments win). Tasks `run_v3_p95` (muscle parts) and `run_v3_p95a` (+
anthropometry). The P95 knee extensors (vasti) have F0 304 instead of 230, the
hip extensor 158 instead of 120, soleus 198 instead of 150; joint speeds
hip / knee / ankle 18 / 30 / 24 rad/s instead of 15 / 25 / 20; Achilles
300 N/mm instead of 200.

**Sprint on P95** (arena `sprint_top_speed_p95`: `sprint_top_speed`'s seeds
221-232, metric and guard, env `ROBOLAB_PROFILE=p95`, so a challenger's own
`--task` gets the P95 body too):

| | peak 1 s speed | steady | 12 starts |
| --- | --- | --- | --- |
| average body, run_v2 champion (`sprint_top_speed`) | 5.05 m/s | 5.00 m/s | 12/12 |
| P95, the same champion unchanged | falls ~3 s into the acceleration | - | 0/12 |
| **P95, re-tuned** (sep-CMA from its params: 900 rollouts on the clean start + 2 perturbed starts at sigma 0.06, then 750 on the clean start + 4 at 0.03; `params/run_v3_p95.txt`) | **5.97 m/s** (champion) | 5.86 m/s | 12/12 |
| P95 + anthropometry (`run_v3_p95a`), the P95 re-tune unchanged | 6.19 m/s | 6.06 m/s | 12/12 |

Clean start on P95: 5.90 m/s steady, 2.27 m steps at 2.6 /s, contact 0.17 s,
flight 0.18 s, 100 m in 20.0 s (average body 22.6 s). The champion's
parameters sit on a knife edge: strength or muscle speed ±3 % keep it running,
but every muscle-level P95 part alone makes it fall, tendon stiffness +5 % alone
included (anthropometry alone does not: 4.92 m/s steady). Reflex gains and drive
bursts are in activation units, so a stronger, faster body is a different
plant: params need re-practice on it.

**Speed limit** (`playground/sprint_limits.py`). What could each body sprint
under ideal control? No skill: the body's capacities are measured in isolation
with open-loop excitations found by CMA-ES and combined through Weyand et al.
2000's model, v = f x Lc x Favg/Wb (f = 1/(tc + taer), Lc = v tc, Favg/Wb =
(tc + taer)/tc), with the swing constraint t_sw = tc + 2 taer. At each speed
it finds (1) the stance that leaves the most swing time in a steady gait (one
contact at v, landing as fast as the flight after it takes off; the stance leg's
11 muscles on piecewise-linear excitations, touchdown posture and retraction
free; pelvis pitch and the other leg's swing driven by ideal actuators along
parametrised paths; stiff penalties on net braking, peak vertical force above
5 body weights (human top-speed peaks are ~3.6-4.5) and net pitch impulse),
(2) the fastest swing after it (bang-bang flexor / extensor switching from the
stance's lift-off state to its touchdown posture, foot clear of the floor), and
(3) the margin tc + 2 taer - t_sw, refined jointly; the top speed is where the
margin crosses zero. Replaying a real champion stance through the rig
reproduces its lift-off velocity to 0.005 m/s. Every optimisation is good to
~±0.04 s of margin (repeat seeds), and everything is idealised in the body's
favour, so these are upper bounds.

Capacities in isolation (`sprint_limits.py omega`: full activation, pelvis held,
other joints locked):

| joint action | fibre limit p50 / p95 (rad/s) | with the limb's inertia p50 / p95 |
| --- | --- | --- |
| hip flexion (knee at 1 rad) | 15 / 18 | 11.5 / 13.9 (80 % of range in 0.28 / 0.24 s) |
| hip extension | 15 / 18 | 13.9 / 16.3 |
| knee extension | 25 / 30 | 23.7 / 27.5 |
| knee flexion | 25 / 30 | 20.8 / 25.1 |
| plantarflexion | 20 / 24 | 22.3 / 26.5 (tendon recoil beats the fibre) |

Top speed under ideal control (margin in s; + = the swing fits):

| body | 5.5 | 6.0 | 6.5 | 7.0 | 7.5 | 8.0 | 8.5 | 9.0 | 9.5 | 10.0 | 10.5 | 11.0 | top speed |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| p50 | +0.06 | -0.00 | +0.02 / +0.04 | -0.09 / -0.07 | -0.08 | -0.11 | | | | | | | **~6.6 m/s** |
| p95 | | +0.26 | +0.17 | +0.12 | +0.09 | +0.03 | +0.07 | -0.03 / +0.02 | +0.04 / +0.05 | +0.04 | -0.04 | -0.15 | **~10.2 m/s** |
| p95 + anthro | | | +0.18 | +0.15 | +0.10 | +0.02 | +0.06 | | -0.02 | -0.03 | +0.01 | | **~10 m/s** (flat 9.5-10.5) |

At the limits:

| | v | tc | taer | step f | Lc | Favg/Wb (needed) | peak | swing |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| p50 | 6.5 m/s | 0.137 s | 0.165 s | 3.3 /s | 0.88 m | 2.20 (2.07) | 4.1 W | 0.38 s |
| p95 | 10.0 m/s | 0.103 s | 0.166 s | 3.7 /s | 1.00 m | 2.61 (2.41) | 4.3 W | 0.39 s |
| p95 | 10.5 m/s | 0.097 s | 0.112 s | 4.8 /s | 0.99 m | 2.15 (2.36) | 3.7 W | 0.36 s |
| elite humans, Weyand 2000 at 11.1 m/s | | 0.093 s | 0.130 s | 4.3 /s | 0.85 m | 2.38 | | 0.36 s |

What binds: **force in short contacts**. The swing takes ~0.3-0.43 s at every
speed and body, as in humans (Weyand's 0.37 s), while the mean vertical force a
stance can deliver falls as contacts shorten (p95: 2.6 Wb at 0.103 s, 2.15 at
0.097 s, 1.8 at 0.094 s) below the 0.5 + t_sw / (2 tc) a steady gait needs. That
is the muscles' force-velocity limit: at 10 m/s the thigh sweeps ~1 rad in
0.10 s (~10 rad/s), well over half the hip extensors' fibre limit (18 rad/s on
P95, 15 on p50), where MuJoCo's force-velocity curve leaves ~15-20 % of the
isometric force. Ablations at 7 m/s (p50 margin -0.09 s): P95 strength alone +0.11 s,
P95 muscle speed alone +0.07 s, allowing impact peaks above 5 Wb +0.10 s (with
16 Wb spikes), while P95 tendons (-0.01), P95 activation (+0.01), rigid v2
tendons (+0.01), 4 ms control quantisation (+0.04) and dropping the pitch
balance (+0.04) are within the ±0.04 s noise: neither the tendons nor the 4 ms
control rate limit the speed. The body is planar and its trunk pitch is held
ideally; the 3D costs of a real body (lateral balance, pelvis rotation) are not
modelled, so the ceilings are optimistic.

**10 m/s needs a P95 body and near-ideal control.** The average body cannot
sprint 10 m/s: even under ideal control it tops out near 6.6 m/s, and the run_v2
champion's 5.0 m/s is already three quarters of that. P95 muscles (strength
per kg x1.32 and speed x1.2) raise the ceiling to ~10.2 m/s: 0.10 s contacts
of ~2.4-2.6 Wb mean force (peaks ≤ 5 Wb), ~1.0 m contact length (longer than
humans' 0.85 m; the planar leg sweeps from ~0.45 rad ahead to ~0.55 rad behind)
and a ~0.39 s swing. P95 anthropometry does not raise it further (longer
contacts, but a heavier swing leg). Clear margin at 10 m/s takes more: P95 with
strength x2 has +0.08 s at 10 m/s, P95 with muscle speed x2 +0.01 s. The
re-tuned RunSkill reaches 5.97 m/s on P95, 59 % of that ceiling: on P95 the
controller, not the body, is the gap. A skill aiming at 10 m/s should target the
ideal-control stance above: land ~0.4-0.6 rad ahead with the knee near straight
(0.2-0.5 rad), retract at ~6-10 rad/s, leave with the thigh ~0.55 rad behind,
contacts of ~0.10 s, flights of ~0.12-0.17 s at ~3.7-4.8 steps/s.

```sh
.venv/bin/python playground/sprint_limits.py omega --profile p95
.venv/bin/python playground/sprint_limits.py speeds --profile p95 --v 9.5 10 10.5 --cycle-gens 25 --name p95_top --init out/sprint_limits/p95_speeds.json
.venv/bin/python playground/sprint_limits.py report --name p95,p95_hi,p95_top,p95_rep
.venv/bin/python playground/arena.py eval sprint_top_speed_p95 --params p.txt --controller bin/challengers/x --task <task> --promote
```

**Elite sprinter body** (`profiles/elite.json`, `ROBOLAB_PROFILE=elite`; a
separate, labelled body, not a percentile): the muscle morphology and fibre
make-up measured in world-class sprinters, relative to the average untrained
body. Strength per kg is set per muscle, since sprinters' hypertrophy is
non-uniform (Handsfield et al. 2017; Miller et al. 2021): hip extensors x1.6,
hamstrings x1.55, hip flexors x1.45, rectus femoris x1.35, vasti x1.3, soleus
x1.25, gastrocnemius x1.3, every other muscle x1.3. Muscle speed is x1.3 (a
~70-75 % fast fibre mix, Costill et al. 1976 and Trappe et al. 2015, times
longer fascicles, Abe et al. 2000), tendon stiffness x1.3 (Arampatzis et al.
2007), activation time constants x0.8; the anthro part (1.03 x length, 1.15 x
mass) is opt-in as for p95. The magnitudes were chosen within ranges recalled
from those papers without re-reading them. **Checked against the papers on
2026-09-28** (each part's `literature` block in `elite.json`): the pattern
holds (hip extensors and hamstrings grow most, fibres are faster, fascicles
longer), but iliopsoas (x1.2), vasti (~x1.1 once sprinters' +24 % longer
fascicles are divided out: knee-extension torque per kg is only ~+7 %, Miller
et al. 2021), soleus (~x1.1), gastrocnemius (~x1.05), the x1.3 default, the
quadriceps tendon (x1.0, Kubo et al.) and faster activation (x1.0: Tillin et
al. 2010 found the difference neural) are all lower than set; hip extensors
(~x1.5), hamstrings (~x1.4), speed x1.3 and the anthropometry (Uth 2005) hold.
`elite.json`'s numbers are kept because `sprint_top_speed_elite` was scored on
them: **results on that body are on an unverified, too-strong profile.** The
literature-based body is `profiles/elite2.json` (every value with its source
and a `verified` flag; trial `sprint_top_speed_elite2`, same seeds and guard).
elite2 is weaker than P95 below the hip (P95 scales every muscle x1.32; an
elite sprinter's knee and ankle muscles per kg are near the untrained mean):
the elite RunRI params run 5.86 m/s on it where they pass (5 of 12 starts).
Strength keys may now name one direction of a joint
(`hip_flex_neg` = hip extensors, `knee_neg` = vasti, `ankle_pos` = soleus, ...):
`Profile.strength(group, muscle)` looks up the muscle's `<dof>_<pos|neg>` key
before its group's, so p50 and p95 build byte-identical XML (checked on v2 and
v3, muscle parts and `all`). Trial `sprint_top_speed_elite`: `sprint_top_speed`'s
seeds and guard on the elite body (`env` sets the profile; seeded with the P95
champion unchanged, which falls on 4 of 12 starts).

## Long jump on the sprinter's run-up (LongJumpRunSkill)

`LongJumpRunSkill` (`lib/robolab/skills/long_jump_run.w`, entry
`lib/entry/long_jump_run.w`, binary `bin/robolab_long_jump_run`) is the long
jump with the fastest robust runner as its approach. It subclasses
`RunRISkill`, so it runs with whatever params that runner was practised
with. When the sprint work promotes a faster runner, the jump takes the new
run params, keeps its own `j_*` lines, and is practised again; this happened
twice here: p95 6.66 -> 6.94 m/s, then the elite-sprinter runner at 7.44 m/s.

Every jump tunable is prefixed `j_`. The opt-in switches are `j_hk`
(hitch-kick), `j_plan2` (plant step planned from the running stride), `j_ri`
(reciprocal inhibition from the plant on), `j_run` (never take off) and
`j_debug`. What the skill adds to the run (the file's header has the chunk
graph):

- **Run-up planner.** At every touchdown, the distance to the ideal
  penultimate touchdown is split into whole steps. The next flight nudges the
  landing leg and scales the push toward that step. The touchdown within
  `j_win` steps of the ideal point becomes the penultimate. Either foot may
  take off.
- **Upright final approach.** Over the last `j_fin_d` m, the trunk target
  rises by `j_fin_dlean` and the trunk servo stiffens by up to `j_fin_kp`.
  The p95 sprinter runs with its trunk about 43 deg forward. Every take-off
  from that lean somersaulted; with this, the trunk is about 3 deg from
  vertical at take-off.
- **Lowered penultimate step** (`j_pn_knee`, `j_pn_drv`) and **plant
  flight**: the take-off leg reaches long and straight (`j_pl_*`), its vasti
  and soleus pre-activate (`j_pl_pre`), and the free leg swings through early.
- **Plant and drive.** `T_board` is a stiff, pre-activated strut. `T_takeoff`
  fires full-power bursts on the take-off leg's hip, knee, ankle and toe
  extensors and hamstrings, the free hip's flexors, and the arms.
- **Flight.** In the hang, the arms go up and the legs back, and both servo
  trunk pitch. `j_hk 1` or `2` replaces it with a 1.5- or 2.5-stride
  hitch-kick. The tuck and then the **reach** (both legs forward) are latched
  on the ballistic time left before the sand.
- **Landing.** In the absorb chunk the knees give, and the trunk and arms are
  thrown forward while the COM is behind the heels. A sit follows.

**Rules** (`playground/tasks/long_jump_run.py`). The other task files
(`long_jump_p95.py`, `long_jump_p95b.py`, `long_jump_elite.py`,
`long_jump_run_b.py`) change only the body or the check mark. The scene is
long_jump's: board, 0.5 m to the sand, a 9 m pit, on the v3 body. World
Athletics TR 29-30 (2026 edition) are encoded in `official_m`:

- **TR 30.1.1, foul.** The front of the take-off foot (the toe box's
  forward-most corner) breaks the vertical plane of the take-off line at any
  tick of the take-off stance, or any body part touches the runway beyond the
  line.
- **TR 30.1.3, no somersault.** The jump fails if the torso pitches past
  120 deg from vertical at any time after the take-off, in the air or while
  landing.
- **TR 30.1.4 and 30.1.5.** Landing short of the sand fails, and so does
  touching the runway after the landing.
- **TR 29.9, the mark.** The mark is the nearest break in the sand made by any
  part of the body (feet, hands, seat, head, a fall back) at any time after the
  landing. The rollout runs at least 2 s past the landing, so the metrics
  cover everything the video shows.
- **TR 29.1, runway length.** The runway is at least 40 m, 45 m where
  possible. The check marks used here are 35.3-44 m.

These rules changed the result. The first searches, run without the
somersault rule, learned a "3.5 m jump" that dived head first and rolled over
in the sand.

**Arena** (all promotions paired; robust trials use 16 held-out perturbed
starts):

| trial | body, runner | before | champion now | verdict |
| --- | --- | --- | --- | --- |
| `long_jump_v2` (1 start) | average v3, RunSkill 5.0 m/s | 1.875 m (LongJumpSkill, v2) | **2.47 m** | promoted three times: 2.05, then 2.34 (learned check mark), then 2.47 (take-off reciprocal inhibition) |
| `long_jump_robust` | average v3 | 1.47 m | **1.85 m** (1 failed start) | +0.38, p = 0.043; the take-off reciprocal-inhibition variant scored 1.95 but +0.10 is p = 0.16 |
| `long_jump_p95` (1 start, new) | p95, 6.66 m/s runner | 0 (the old skill falls) | **3.68 m** | 3.58, then +0.10 from a double-arm take-off; the hitch-kick scored 3.17 |
| `long_jump_p95_robust` (new) | p95, 6.94 m/s runner | 0 | **3.22 m** (0 failed, 2.11-3.81) | 2.13 (6.66 runner, nominal practice), then 3.22 (+1.08, p = 0.009; faster runner, robust practice); `j_plan2` 2.85 and the hitch-kick 1.33 lost |
| `long_jump_elite` (1 start, new) | elite sprinter, 7.44 m/s runner | 0 | **3.97 m** | promoted |
| `long_jump_elite_robust` (new) | elite sprinter | 0 | **3.66 m** (0 failed, 3.11-4.05; the feet mark on 16/16) | 2.57 (nominal practice only, 4 failed starts), 3.48 (+0.91, p = 0.043: robust practice, 820 rollouts), then 3.66 (+0.18, p < 0.001: the same run to 1800 rollouts) |

**Per body** (robust champions on their 16 arena starts, means; nominal
champions in brackets):

| | average (p50) | p95 | elite sprinter |
| --- | --- | --- | --- |
| official distance | 1.85 m (2.47) | 3.22 m, best start 3.81 (3.68) | 3.66 m, best start 4.05 (3.97) |
| run-up speed, last 5 m | 4.98 m/s (5.01) | 6.65 m/s (6.60) | 6.99 m/s (7.01) |
| take-off speed and angle | 4.23 m/s at 18.5 deg (4.51 at 20.9) | 5.83 m/s at 19.5 deg (5.90 at 21.7) | 6.44 m/s at 17.2 deg (6.02 at 22.6) |
| take-off vx / vz | 4.01 / 1.33 m/s | 5.50 / 1.94 m/s | 6.15 / 1.91 m/s |
| board contact | 0.22 s | 0.18 s | 0.17 s |
| take-off foot behind the line | 0.12 m | 0.46 m | 0.51 m |
| nearest mark | the head on 13/16 (falls back) | the feet on 11/16 | the feet on 16/16 |

**Against humans**, men unless noted. Every row is from a source; D marks a
value derived from quoted numbers or figures.

| level | distance | run-up and take-off | source |
| --- | --- | --- | --- |
| untrained adult | 4.95 ± 0.55 m (women 3.57 ± 0.54): sports-science students not specialised in the long jump; PE students before training 4.70-4.80 m | not reported | Romdhani et al. 2026, Sports 14(5):193; Lai et al. 2026, J Exerc Sci Fit |
| high-school competitor | state qualifying (4-year average of 4th place): boys 6.07-6.65 m, girls 4.67-5.45 m (Oregon 2026); CIF at-large boys 6.95, girls 5.58 m; jumpers aged 14-28: 6.30 ± 0.71 m | 8.89 ± 0.58 m/s over the last 10 m | OSAA 2026 standards; CIF State; Bayraktar & Cilli 2018 |
| trained collegiate jumper | NCAA D1 outdoor finals medians 2023-25: men 7.56-7.75 m, women 6.08-6.27 m (D) | national/regional jumpers (7.27 m jumps): 9.39 m/s at touchdown, vz 3.01 m/s, 18 deg, 0.125 s | NCAA results; Willwacher et al. 2017, Sci Rep 7:16058 |
| world record | 8.95 m (Powell, 1991) | run-up 11.00 m/s; take-off 9.09 / 3.70 m/s, ~22-23 deg | Fukashiro & Wakayama 1992, via Shimizu et al. 2018 |
| speed-matched elite | an 8.30 m jumper from short run-ups of 6.1-6.6 m/s: 4.33-4.77 m | vz 3.2-3.4 m/s, 32-36 deg, 0.17-0.19 s (D, read off figures) | Bridgett & Linthorne 2006, J Sports Sci 24:889 |

At full length the models reach 28-45 % of the world record (best jump
4.05 m) and stay below all four human levels. The one exception: the elite
body's robust mean (3.66 m) and the p95 and elite bodies' best jumps
(3.7-4.05 m) exceed the mean *untrained woman* (3.57 m), but not the mean
untrained man (4.95 m).

Matched on run-up speed, the result is mixed:

- The p95 (6.65 m/s, 3.22 m) and elite (7.0 m/s, 3.66 m) bodies beat Hay's
  across-athlete line (d = 1.281 v - 5.56, D; data from 6.6 m/s up: 2.96 and
  3.41 m).
- They fall short of the jumpers' regression d = 1.067 v - 3.184 (Bayraktar &
  Cilli 2018; 3.91 and 4.28 m, extrapolated below its 7.3 m/s floor).
- They fall well short of an elite jumper at the same speed (4.3-4.8 m).

The gap is the take-off, not the run-up alone. At the same run-up speed the
elite athlete leaves the board at 32-36 deg with vz 3.2-3.4 m/s; the models
leave at 17-24 deg with vz 1.3-2.4 m/s. The models are also not held back by
drive: the take-off leg's hip extensors, vasti and the free hip's flexors are
above 0.95 activation for 85-93 % of the stance.

**What worked:**

- **The sprinter's run-up.** The approach went from 4 m/s to 5.0, 6.65 and
  7.0 m/s on the average, p95 and elite bodies.
- **The upright final approach.** Without it, every jump somersaulted.
- **The hang.** It beat the hitch-kick: 3.58 vs 3.17 m on one start, and on
  16 starts 3.22 m vs 1.33 m with half the hitch-kick jumps failing.
- **Robust practice** with the official score on 6-8 perturbed starts took
  the p95 robust trial from 2.13 to 3.22 m and the elite one from 2.57 to
  3.66 m.
- **Learning the check mark across attempts** (average body,
  `playground/long_jump_run_checkmark.py`). The foot moved from 0.43 to 0.10 m
  behind the line and the robust mean from 1.57 to 1.85 m (promoted).
- **Take-off reciprocal inhibition** on the average body (`j_ri 0.5`). vz rose
  from 1.33 to 1.6 m/s: +0.14 m on one start (promoted), +0.10 m on 16 starts
  (p = 0.16).
- **A double-arm take-off** on p95: +0.10 m on one start.

**What didn't:**

- **Capture-point landing reach** (`j_cp_*`, average body). It was mixed on
  single starts: -0.3 m on the nominal start and +0.4 m on another at the
  weakest gain. Stronger gains lost on both starts, and the body sits back
  anyway.
- **Stronger plant pre-activation:** -1.0 m.
- **A stiffer, straighter plant knee:** -0.09 m.
- **Lowering the penultimate step by other amounts.** The practised extra knee
  flexion is about 0.13-0.22 rad; 0.35 rad cost 0.25 m, and 0.05 rad cost
  0.38 m.
- **Planning the plant step from the running stride** (`j_plan2`). It was
  better on validation starts but lost on the arena starts (2.85 vs 3.22 m).
- **Steering the run-up by nudging the landing hip.** The sprint gait's step
  length barely responds to small nudges, and large ones break the gait.
- **Landing on the average body.** Most of its landings fall back, so the
  mark is at the head.
- **Moving the check mark on the p95 body.** Shifting it by a few centimetres
  flips jumps between landing and failing, so the check-mark ILC did not
  carry over.
- **The runners' own falls.** The p95 and elite runners fall on about 1 in 12
  of these standing starts, before any jump logic acts.

Champion params: `params/long_jump_run_ri.txt` (average body, one start),
`params/long_jump_run_cm.txt` (average body, robust), `params/long_jump_p95_c_arms.txt`
and `params/long_jump_p95_e2.txt` (p95), `params/long_jump_elite.txt` and
`params/long_jump_elite_robust2.txt` (elite); every one runs on
`bin/challengers/long_jump_run-a8` (the arena froze copies under
`bin/champions/`).

**Practice** (`playground/long_jump_run_practice.py`) runs search.py's
methods in lockstep on one pool and scores rollouts with the task's `score`:

- `ROBOLAB_LJR_SCORE=jump` scores the effective distance, with light costs
  for taking off far behind the line and graded costs for fouls, somersaults
  (graded by the forward rotation in the air) and steps into the pit.
- `ROBOLAB_LJR_SCORE=official` scores the arena metric.

The stages were: 1500 rollouts on the nominal start from an upright final
approach, then 1700-2400 robust rollouts on 6-8 perturbed starts (starts on
which the runner itself falls were excluded), then check-mark ILC.

Videos: `out/long_jump_v4.mp4` and `.gif` show the best jump, 4.05 m: the
elite-sprinter robust champion on arena start 503. The side view follows the
jumper past the board, and the take-off, flight and landing play at 1/4
speed. The others are:

- `out/long_jump_v4_elite_nominal.*`: the elite body's one-start champion,
  3.97 m;
- `out/long_jump_v4_p95.*`: the p95 robust champion's 3.87 m on a validation
  start;
- `out/long_jump_v4_p50.*`: the average body's 2.47 m.

Each has a `_sheet.png` and a `_metrics.json`.

```sh
./build.sh long_jump_run
ROBOLAB_LJR_SCORE=official ROBOLAB_CONTROLLER=bin/challengers/long_jump_run-a8 .venv/bin/python playground/long_jump_run_practice.py \
  long_jump_p95b --init params/long_jump_p95_e2.txt --only 'j_*' --exclude 'j_st_*,j_leg_len,j_cp_*' \
  --methods sep_cma:1 --sigma 0.05 --budget 2400 --workers 4 --seeds None,1001,1002,1003,1004,1006,1007,1008 --out out/long_jump_run/x
ROBOLAB_CONTROLLER=bin/challengers/long_jump_run-a8 .venv/bin/python playground/long_jump_run_checkmark.py long_jump_run \
  --params params/long_jump_run_c.txt --seeds None,1001-1007 --iters 3 --out params/x.txt
.venv/bin/python playground/long_jump_run_render.py long_jump_elite --params params/long_jump_elite_robust2.txt \
  --controller bin/challengers/long_jump_run-a8 --seed 503 --out out/long_jump_v4
```

## High-school 110 m hurdles

The boys' high-school course: 10 hurdles 0.991 m (39 in) high, 13.72 m to the
first, 9.14 m apart, 14.02 m to the finish (`playground/tasks/hurdle_hs.py`;
the rocking hurdles, sensors and per-hurdle metrics are `tasks/hurdle.py`'s,
unchanged). Bodies: `hurdle_hs` (v1, vmax 3.0), `hurdle_hs_v2`, `hurdle_hs_v3`
and `hurdle_hs_v3h` (v3 with 3D hips: the hips' abduction and rotation joints
freed under the planar root, `ROBOLAB_HURDLE_HIP3D=1` on the others).

Arena curriculum (8 fixed starts each: the clean start and 7 perturbed standing
starts; metric `hs_score` = hurdles cleared - time/100, where a run that does
not finish counts 60 s + 0.3 s per metre short):

| trial | height | champion | hs_score | cleared / 10 |
| --- | --- | --- | --- | --- |
| `hurdle_076` | 0.762 m (30 in) | HurdleHSSkill, v3 + 3D hips | -0.379 ± 0.377 (baseline -0.887; +0.509, p = 0.022) | 0.5: hurdle 1 on 4 of 8 starts |
| `hurdle_084` | 0.838 m (33 in) | baseline (the 0.45 m champion) | -0.889 | 0 |
| `hurdle_091` | 0.914 m (36 in) | baseline | -0.891 | 0 |
| `hurdle_hs` | 0.991 m (39 in) | baseline | -0.889 | 0 |

**Skill** (`lib/robolab/skills/hurdle_hs.w`, `HurdleHSSkill < RunSkill`,
binary `bin/robolab_hurdle_hs`): RunSkill's stride on whatever body it runs
(`params/run_v3.txt` for v3), plus a stride planner (touchdowns split the
distance to the take-off spot into whole steps; the flight nudges the landing
toward the planned step), take-off routing (the touchdown within half a step of
`h_d_to` becomes the plant) and one clearance per lead leg: plant -> attack
(take-off drive, lead-knee drive, trunk and opposite arm forward) -> lead (the
lead leg unfolds heel first; `heel_aim` opens the knee exactly as fast as the
sensed thigh angle and hip height allow the heel to pass bar + `h_want`) ->
trail (the trail leg, abducted and turned out on a 3D-hip body, comes around
the side; latched on the trail knee's sensed position passing the bar) -> snap
-> land -> back into the run. Each keyframe is a pose goal with a searched
duration and easing (`h_via 1` chains the air keyframes as via-points), with
drive bursts and sensed clearance corrections (lead hip and knee, trail knee,
hip and abduction).

**Practice** (`playground/hurdle_hs_practice.py`: several searches of
`search.py` in lockstep on one 3-worker pool, rollouts on a frozen copy of the
controller). What worked, in order: (1) a take-off search alone
(`ROBOLAB_HURDLE_SCORE=jump`: highest COM within 1 m of the bar plus the speed
kept) raised the COM peak from 1.20 to 1.30 m; (2) the air choreography alone
(`=air`: the lowest body point over the bar's place during the whole crossing,
`vmargin`) found a clean crossing; (3) the full practice score on the full
10-hurdle model over 4 training starts (BO best) made it land and clear on
perturbed starts. BO beat (1+1)-ES in every stage here; sep-CMA over all 102
tunables at sigma 0.05 made every candidate worse (the motion is too fragile
for full-dimensional steps). The via-point air keyframes (`h_via 1`) are
built but were not practised or entered.

**Findings.**

- The planar body's sagittal trail leg cannot clear 0.762 m at this body's
  speed: with the thigh hanging, its knee passes 0.2-0.4 m under the bar. Freeing
  hip abduction and rotation (0.8 rad and 0.6 rad limits) and holding the trail
  thigh back and out until the knee has passed the bar is what first cleared it.
- The run-up is slow: ~4.1 m/s at the first hurdle, ~3.3 m/s over it. The body
  is ~1 m long over the bar, so it hangs there ~0.3 s and the COM must peak at
  ~1.25-1.3 m (0.49 m above a 0.762 m bar). A human carries it only
  0.25-0.35 m above the bar, at 7-8 m/s.
- A spine "dive" (trunk curled over the lead leg) tilts the pelvis back by
  reaction and drops the trail leg 12-15 cm; leaning the whole pelvis forward at
  take-off keeps the clearance but makes the landing harder. The pelvis-dive
  challenger (with a longer landing stance and knee pre-activation) lost on
  `hurdle_076` (paired -0.25, p = 0.92), as did a stronger stride planner
  (push-off scaled by the planned step, a take-off guard, a flat trail foot;
  -0.25, p = 0.77): both beat the champion on their training starts and cleared
  only 2 of 8 arena starts. The margins are within ±2 cm of the bar and the
  run-up varies the take-off by ±0.2 m, so a clearance found on a few starts
  does not carry to others.
- Where the run falls: after the landing the body is rotating backward (the
  lead leg's snap-down swings 1.6 rad in ~0.13 s and the trunk counter-rotates),
  the landing knee folds under ~2 m/s of sink, and the next steps are short.
- Two measurement traps fixed in `hurdle_hs.py` (hurdle.py untouched): hurdle.py
  samples foot corners only in their y = 0 plane, which misses a turned-out 3D
  foot; and a hurdle crashed through just before a fall is not cleared (it had
  not yet tipped when the run ended). Practice on a 1-hurdle model overfits the
  solver's numerics: the same parameters fell in the approach on the 10-hurdle
  model, so late stages practise on the full course.

**Against humans.** Humans are far ahead, and the table says why. High-school boys over
0.991 m run 110 m in about 14-16 s when good (state level ~14 s) and 17-18 s on
average; elite men run 12.80 s over 1.067 m. The model has not finished the
course at any curriculum height. At 0.991 m it takes off and gets the lead leg
over, but the trail leg catches the bar and it falls at the first hurdle. At
0.762 m it clears the first hurdle on half the starts and falls before the
second. Its run-up is the limit: ~4.1 m/s at the first hurdle (a human arrives
there at ~7 m/s after ~2.6 s; the model needs ~4.8 s) and ~3.3 m/s over the bar,
so it must carry its COM ~0.5 m above the bar where a human carries it 0.25-0.35
m. The flat run on the same body is ~5.0 m/s steady (~23-24 s for 110 m from a
standing start without hurdles), below a high-school sprinter's ~8-9 m/s.

Videos: `out/hurdle_hs_076.mp4` (+ `.gif`, `_sheet.png`, `_clearance.png`;
three-quarter view `ROBOLAB_HURDLE_CAM=55`), the 0.991 m attempt
`out/hurdle_hs.mp4` (+ `.gif`, `_sheet.png`, `_clearance.png`).

```sh
./build.sh hurdle_hs
ROBOLAB_HURDLE_HEIGHT=0.762 ROBOLAB_HURDLE_CAM=55 .venv/bin/python playground/hurdle_hs_render.py hurdle_hs_v3h \
  --params params/hurdle_hs_076.txt --controller bin/challengers/hurdle_hs-r076bo --out out/hurdle_hs_076
.venv/bin/python playground/arena.py eval hurdle_076 --task hurdle_hs_v3h --params params/hurdle_hs_076.txt \
  --controller bin/challengers/hurdle_hs-<tag> --note "..." --promote
```

## Sprint from starting blocks, keyframed on Usain Bolt

**Reference** (`playground/refs/bolt/`; the footage stays local in the
gitignored `clips/`, is listed in `SOURCES.md`, and no pixel of it reaches
any output). `keyframes.py` runs MediaPipe Pose (heavy) on side-view clips of
Bolt: practice block starts at Nitro Athletics 2017 (240 fps, clocked from
the stadium lights' 100 Hz flicker), a Daegu 2011 200 m slow-motion
broadcast for the max-velocity cycle (Osaka 2007 as a cross-check). It
writes `bolt_keyframes.json` (per event: mean, SD, n, source frames, in the
video's angle conventions), `out/bolt_keyframes.png` (stick figures from the
keypoints, the table) and the keypoint arrays. The video's set pose is
unreliable (Bolt in black; MediaPipe folds the knees), so the set is the
2018 World Indoor 60 m finalists' mean; steps 3-10 have no usable side view
(interpolated between step 2 and the max-velocity cycle, the trunk from a
lean model); arm angles are low-confidence (the keyframes use a literature
arm swing, and the form metric scores the trunk and legs only).

| Bolt (video) | trunk | stance hip / knee / ankle | swing hip / knee | n |
| --- | --- | --- | --- | --- |
| block exit | 46 | front 12 / 26 / 39 | rear 95 / 110 | 2 |
| step 1 TD / TO | 44 / 40 | 84 / 89 / 34 ; 8 / 25 / 33 | 22 / 41 ; 104 / 99 | 2 |
| max-v TD | 4 +-2 | 28 +-3 / 4 +-2 / 30 +-2 | 18 +-13 / 140 +-9 | 4-5 |
| max-v MS / TO / MKL | 6 / 3 / 1 | 11 / 26 ; -13 / 27 ; -24 / 35 | 54 / 145 ; 69 / 108 ; 73 / 81 | 3-5 |

`playground/tasks/sprint_blocks.py` turns these into model postures
(`BoltRef.model`: the hip->shoulder trunk line split into pelvis pitch and
spine flexion), writes the skill's table `lib/robolab/skills/sprint_ref.w`
(`refw`) and the keyframe editor's files `playground/refs/bolt/editor/<event>.json`
(`editor`; `--achieved` adds our runner's angles). A params entry
`ref_<event>_<key>` (degrees) overrides one reference value.

**Task** `sprint_blocks` (average v3 body; `sprint_blocks_p95`,
`sprint_blocks_athlete` and `sprint_blocks_v2` swap the body). The set
posture is placed with both hands on the track just behind the line and two
angled pads (front 56 deg, rear 63 deg) under the soles, each only on its
own foot's line; a seed perturbs the set. The gun fires at 1.4 s (`gun`
sensor: time since the gun; `blocks`: the pads' normal forces). Rules: false
start = a hand, a foot or the pelvis moving in the set, or a start-system
reaction under 0.100 s (World Athletics TR 16.6: pad force departing by 0.2
BW from its pre-gun level); fall = anything but the feet touching the track
(the hands until they leave it) or the pelvis / torso limits. Metrics:
reaction, block times, 10 m splits (the chest crossing), the first-hurdle
split (13.72 m) and speed, steps, contact / flight, `form_err` (RMS angle
error vs Bolt's max-velocity keyframes, the video's own definitions measured
on the model's keypoints, 40 m to the finish) and `acc_form` (steps 1-2).
`SPRINT_START=flying` is a development start in flight (the stride alone).

**Skill** `SprintBlocksSkill` (`lib/robolab/skills/sprint_blocks.w`,
standalone: run_natural's stride machinery is copied in, so it does not
change when that skill does): set -> rear push (latched on the rear pad's
force) -> front push (front pad) -> flight -> acceleration steps (keyframes
blended by step index from Bolt's steps 1-2 to the max-velocity cycle) ->
run_natural's six-chunk loop on Bolt's max-velocity keyframes, via-chained
and latched on contact, with the hop-height loop. What the start needed on
top: a still set (integral postural tone; the pads' faces push the body
forward, so the COM's drift flexes the shoulders), feed-forward block pushes
with the pushing extensors' stretch reflex turned down, the swinging leg's
hip in world frame (`k_swcomp`), the trunk servo on the pelvis, not the
torso (`servo_pelvis`: the lumbar spine had hidden a pelvis folded forward
at the hips), arms held at their world angle against trunk pitch and swung
narrower in the first steps, and the set's servo gains kept apart from the
stride's. `build_start(frame, ctl, mv, n)` lets another skill (the hurdler)
run the set, the pushes and n acceleration steps and hand over to its own
gait.

**Practice.** The stride first (it did not run at all from the blocks' params):
sep-CMA from flying starts (3 s, 8 s, then a 1.6-3.2 m/s curriculum, so it
also accelerates). The block exit then fell every time: at strength 1.0 the
rear leg cannot swing through while the front leg's hip extension lifts the
trunk (the pads push the COM ahead of the feet; strength x1.5 and vmax x2
alone did not help either). A strength curriculum (x1.5 -> x1.3, the 95th
percentile's 1.32) with 4-6 perturbed starts found an exit (trunk ~85 deg at
front-foot release, rear thigh +19 deg, 2.7 m/s rising 0.56 m/s), then p95
robustness (8 starts, 6 s) and a form-weighted refinement (distance +
survival - 1 per degree of form error). The average body still cannot get
out of Bolt's set: every one of its starts falls within 1 s.

**Arena** (12 held-out perturbed set positions each; all champions on the
p95 body):

| trial | champion | pass | Bolt, Berlin 2009 | Bolt scaled to our legs |
| --- | --- | --- | --- | --- |
| `sprint_blocks_30` (s, gun to 30 m) | **6.72** | 11/12 | 3.78 | ~4.0 |
| `sprint_blocks_100` (s) | **19.08** | 11/12 | 9.58 | ~10.1 |
| `sprint_bolt_form` (deg, trunk + legs) | **26.7** | 11/12 | 0 | |

| challenger (30 m unless stated) | mean paired diff | p | verdict |
| --- | --- | --- | --- |
| drive phase over 6 steps instead of 2 (no re-practice) | 5 more falls | 1.0 | lose |
| the same controller on the average v3 body | all fall | 1.0 | lose |
| athlete body (strength x1.5 only) with its own start | 4 more falls | 0.996 | lose |
| form refinement of the max-velocity cycle (all three trials) | 1-4 fewer falls, 30 m -0.14 s, 100 m -0.13 s, form -3.5 deg | <= 0.005 | **promoted** x3 |
| `sprint_top_speed_p95` (peak 1 s speed, 30 s) | 5.93 vs 5.97 (RunSkill) | 0.83 | lose |

The rendered champion (seed 5, `out/sprint_blocks.mp4`, `.gif`,
`out/sprint_blocks_keyframes.png`: our runner with Bolt's keyframe ghosted,
Bolt's and our stick figures, the angle table): reaction 0.237 s, rear foot
off 0.34 s, block exit 0.50 s, 10 m 2.89 s, 13.72 m 3.63 s at 5.0 m/s,
30 m 6.68 s at 5.5 m/s, 60 m 12.0 s, 100 m 19.16 s, fastest 10 m 5.7 m/s;
at speed 3.3 steps/s of 1.71 m, contact 0.14 s, flight 0.07 s. Bolt: 1.89,
3.78, 6.29 and 9.58 s, peak 12.3 m/s (11.7 scaled to our legs), contact
0.09-0.10 s, 4.5 steps/s of 2.4-2.7 m. Recreational sprinters run 100 m in
13-15 s: the body is ~5 s slower than them and ~2x Bolt's time. It is 3.5 s
faster than the v3 standing-start sprint (22.6 s) because the p95 muscles
are stronger and faster, not because of the blocks. The form error is
largest at touchdown (34 deg: the trunk leans ~30 deg more than Bolt's
upright 4 deg, and the swing knee folds far less than his 140 deg).

```sh
./build.sh sprint_blocks          # bin/robolab_sprint_blocks (the frozen champion: bin/champions/sprint_blocks_*)
.venv/bin/python playground/tasks/sprint_blocks.py render --task sprint_blocks_p95 --params params/sprint_blocks_p95.txt \
  --seed 5 --seconds 21 --video out/sprint_blocks.mp4 --gif out/sprint_blocks.gif --keyframes out/sprint_blocks_keyframes.png
.venv-pose/bin/python playground/refs/bolt/keyframes.py      # the reference (needs the local clips)
```

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

### Toward 10 m/s (P95 and the elite bodies)

Erik's target: better than 10 m/s. The RunRI gaits were capped by their own
speed plan (v_top ~7.1, a brake above v_cap 6.8); lifting the caps changed
nothing by itself (6.6 m/s at 3.0 steps/s: the stride was at its limit), so
the speed stages search the stride with the plan uncapped (v_top = v_cap = 10,
no brake) under a top-speed objective (tasks/sprint_touch.py objective 2, the
body from `ROBOLAB_PROFILE`), then a worst-case robustness stage.

**The ceiling needs a free trunk.** sprint_limits.py's ideal stance holds the
pelvis pitch with an ideal stabiliser and penalises only its NET impulse over
the stance. Replayed at 7.5 m/s on P95 (`scratchpad/sprint_knot/ideal_pitch.py`)
that stabiliser applies up to 3.9 kN m (mean 1.4 kN m) inside a 0.12 s stance,
cancelling the ground force's moment about the COM, while the stance hip's
muscles give at most 185 N m: no controller has that actuator. With the pitch
released at touchdown and the same excitations, the trunk pitches 0.66 rad
back, its pitch rate changes by 3.5 rad/s and the body never leaves the ground.
`sprint_limits.py speeds --pitch-free` (opt-in; the default path is unchanged)
drops the stabiliser in the stance and instead penalises a trunk rocking of
more than 0.1 rad and a net pitch-rate change above 0.5 rad/s (a steady gait
must not leave the trunk spinning); each speed is warm-started from the speed
below (chained), 120 stance generations and 40 joint refinements:

| body | ceiling, rigid stabiliser (least-squares zero of the margin) | ceiling, pitch free (round 3's probe: fastest positive margin, fitted zero; two chains) | champion, peak 1 s (12/12 starts) | steady | share of the pitch-free ceiling |
| --- | --- | --- | --- | --- | --- |
| average (p50) | ~6.6 m/s | **7.0** (fit 7.22-7.35) | 5.05 (RunSkill) | 5.00 | ~70 % |
| P95 | 9.42 (~10.2 read off the top grid points) | **8.5-9.0** (fit 9.05-9.42) | **7.021** (`params/run_ri_p95_h1.txt`) | 6.88 | ~75-78 % |
| elite (`elite.json`, unverified magnitudes) | ~10.5 (one run) | - | 7.437 (`params/run_ri_elite.txt`) | 7.34 | - |
| elite2 (literature, `elite2.json`) | - | **8.5** (fit 8.33-9.26) | **6.564** (`params/run_ri_elite2.txt`; the elite params unchanged passed 5/12) | 6.51 | ~71-77 % |

**Correction (round 3).** Round 2 first reported the pitch-free ceilings as
"below ~6" (average), 8.45-8.53 (P95) and ~8.3 (elite2). Those came from single
chains that started from a poor solution; the optimiser often finds no flight
at all from there. Chained upward from 5 m/s, with the better of two
optimisations per speed and two chains per body
(`scratchpad/sprint_knot/ceiling_probe.py`), the ceilings are the ones in the
table. The two restarts at one speed differ mostly in the SWING optimisation
(e.g. 0.28 against 0.52 s at the same speed), so single points carry
+-0.3-0.5 m/s. Against human data (round 3), the average body's ~7.0-7.35 is
below untrained men's measured ~7.8 m/s (7.3-8.3), and P95's ~8.5-9.4 matches the
untrained 95th percentile (~8.8-9.2). Elite2's ~8.5-9.3 is far below elite
sprinters (11.5-12.3; ~11.6-11.8 at 1.75 m).

**Round 2: moving the stance toward the ideal** (P95, stance of the steady tail;
tasks/sprint_touch.py records `thigh_td`, `thigh_lo`, `stance_t`, `stance_fz`):

| stage | peak 1 s | thigh touchdown | thigh lift-off | mean vGRF | vz lift-off | result |
| --- | --- | --- | --- | --- | --- | --- |
| ideal control, rigid pitch, 7.5 m/s | - | +0.46 | -0.72 | 2.57 BW | +1.04 | needs the stabiliser |
| ideal control, pitch free, 7.5 m/s | - | +0.51 | -0.71 | 2.30 | - | |
| sp2 (round 1 champion) | 6.936 | +0.665 | -0.192 | 1.98 | +0.65 | |
| H1: landing reach toward the ideal, re-tuned (objective 4) | **7.021** | +0.622 | -0.219 | 1.97 | +0.65 | **champion** (+0.086, p < 0.001) |
| K1: knot stance (RunKnotSkill), switch speed searchable | 6.77, falls at 12 s | +0.61 | -0.26 | 1.99 | | the search raised the switch above the gait's speed: knots never used |
| K2: knot stance forced on above 6 m/s | 6.03, falls at 12-17 s | +0.52 | -0.16 | 1.73 | +0.45 | touchdown reaches the ideal, lift-off does not |
| PT1: `push_through` (the swing waits for toe-off, full push drive while loaded), re-tuned | 6.42 | +0.71 | -0.23 | 1.80 | +0.55 | longer contact (0.17 s) at lower force |

Why the stance does not follow: in stance the champion's prime movers are
already saturated (gluteus and hamstrings at 1.0 throughout, vasti from 30 ms,
soleus and gastrocnemius from ~60 ms), so a different command changes nothing
there. What differs from the ideal is geometry (it lands with the knee at 0.56
against 0.29 and collapses it to ~1.0 against 0.59) and the late-stance
antagonists (its push chunk times out after 80 ms, so the flight chunk's tuck
pose and swing drives reach knee flexors 0.6-0.9 and dorsiflexors 0.4-0.8
while the foot still pushes). Freeing either (knots, push-through) moved one
angle and cost speed. The long sweep is not an artefact of the rigid trunk
at 7.5 m/s (the pitch-free ideal still lifts off at -0.71 rad there, P95 and
elite2 alike), but it shortens with speed (-0.46 to -0.49 rad at 8.5-9 m/s on
P95, -0.33 at 8.5 on elite2): the champions' ~-0.2 rad lift-off with ~2.0 BW
of mean force, against the ideal's ~-0.7 with 2.0-2.3 BW, is where the
remaining ~17 % of the P95 ceiling is.

**RunKnotSkill** (`lib/robolab/skills/run_knot.w`, `bin/robolab_run_knot`;
RunRISkill exactly without `knots 1`): the ideal stance distilled, not
replayed. Knot chunks beside RunSkill's own, entered from any flight once the
filtered speed reaches `kn_v_on`: a landing knot (the flight chunk's goal for
the landing leg is the touchdown keyframe, arriving with its joint velocities:
the retracting hip), a timed touchdown -> mid-stance knot, a mid-stance ->
lift-off knot latched on the release, every value a tunable seeded from the
ideal (P95, 7.5 m/s), joint velocities turned into contraction velocities
through the geometry; phase-gated full drive on the stance prime movers
(windows after the sensed touchdown) with RunRI's reciprocal inhibition; the
reflexes, hop height, trunk servo and placement on top. Two flying-start bugs
found on the way are fixed in it (a command seeded at the sensed posture
leaves the reflexes no tone at the landing; RunSkill ramps v_des only while
`t_go >= 0`), and so is one in the snapshot recorder
(`scratchpad/sprint_touch/snapshots.py`): a foot rocking on its toe late in
stance re-contacts briefly, and those onsets were taken as touchdowns (why
some held-out snapshot starts always fell at ~0.35 s); a touchdown now needs
>= 60 ms in the air and the foot ahead of the COM (`snap_ver 1` files).
RunRISkill gained `push_through` / `pt_delay` / `pt_drv` (opt-in).

**Residual TCN** (`tcn 1` in RunRISkill: P6's ConvPolicy, 33 proprioceptive
inputs normalised on the champion's own running, three fixed random dilated
layers, a 63-weight head declared as tunables, joint offsets on hips, knees,
ankles and spine; `scratchpad/sprint_knot/tcn_stats.py` writes the fixed
part). A zero head replays the P95 champion exactly. Trained on 4 perturbed
starts with the top-speed objective: at sigma 0.03 no head beat zero in 1600
rollouts; at 0.004 the best gained +0.01 m/s on its training starts and fell
on 4 of 8 held-out ones (the champion: 8/8). Not entered. ILC was not run: it
learns to track a kinematic target, and the only target at hand, the ideal
stance, is not one the saturated stance can follow (K2).

Stance of the elite2 champion (6.48 m/s steady): touchdown +0.53 rad, knee
0.36, lift-off -0.25, contact 0.148 s, mean / peak vertical force 1.87 / 4.2
BW, lift-off vz +0.55 m/s (pitch-free ideal at 7.5 m/s on elite2: +0.51 /
-0.72 / 0.125 s / 2.03 BW / +0.76).

Video: `out/sprint_touch.mp4` (+ `.gif`, `_sheet.png`; body tinted by muscle
activation, contraction HUD), the average-body `run_natural_fast` champion from
a standing start.

```sh
./build.sh sprint_touch run_ri
.venv/bin/python playground/tasks/sprint_touch_v3.py render --params params/sprint_touch_v3.txt \
  --controller bin/robolab_sprint_touch --seconds 14 --video out/sprint_touch.mp4 --gif out/sprint_touch.gif --sheet out/sprint_touch_sheet.png
RUN_NATURAL_START=flying .venv/bin/python playground/search.py sprint_touch_v3 --attrs fly_touch=2,snap_acc=1,objective=3 ...  # flying-start stage
.venv/bin/python playground/arena.py eval run_natural_fast --task run_natural_fast_v3 --params params/sprint_touch_v3.txt --controller bin/challengers/<copy>
.venv/bin/python playground/arena.py eval sprint_top_speed_p95 --params params/run_ri_p95.txt --controller bin/challengers/<run_ri copy>
```

`tasks/sprint_touch.py` / `sprint_touch_v3.py` are the practice tasks
(run_natural_fast's metrics; `objective` 0 speed, 1 naturalness, 2 top speed,
3 pace; `fly_touch 2` starts from a champion snapshot,
`playground/cache/sprint_touch_<body>[_acc].npz`, 8 ms before a right
touchdown; with `ROBOLAB_PROFILE=p95` the P95 champion's). A search's
`--fixed` values lose to `--init`'s for the same names (search.py BoxRep): put
fixed values in the init file.

### Round 3: body fidelity and the calibrated v4 body

The pitch-free ceilings above put the average body below untrained men. Round 3
asks why. It sets human targets from sources, uses the ideal-control analysis
as a probe with one model factor changed at a time, and builds a calibrated
body, **v4**. v4 is opt-in, and every change in it rests on a citation.

**Human targets.** Every number below was read in the source (verified),
calculated from verified numbers (derived), or read off a plotted figure
(fig-read). The full list is in `playground/calibrations/v4.json`
(`human_targets`).

| population | top speed | contact / aerial | step | mean / peak vertical force | status |
| --- | --- | --- | --- | --- | --- |
| untrained young men | ~7.8 m/s (7.3-8.3); Lazarczuk et al. 2025: 7.77 +- 0.86; Clark, Meng & Stearne 2020: 8.23 +- 0.41 | 0.130 / 0.109 s (Clark 2020); 0.120 / 0.124 at 8 m/s (Weyand et al. 2000 regressions) | 1.96 m at 4.21 /s (Clark 2020); 2.00 m at 3.96 /s (Weyand 2000) | 2.07 BW at 8 m/s (Weyand 2000) / ~3.2 BW (Clark & Weyand 2014 Fig. 7A, athlete non-sprinters) | verified; derived; peak fig-read and weakly sourced |
| untrained, 95th percentile | ~8.8-9.2 m/s (mean + 1.645 SD, SD 0.4-0.9) | contact ~0.105-0.112 s | ~2.0-2.1 m at 4.4-4.6 /s | ~2.0-2.1 BW mean | derived |
| trained sprinters, 1.75 m / 66.6 kg | 9.90 +- 0.46 m/s (Miyashiro et al. 2019, 79 sprinters) | 0.103 / 0.113 s | 2.15 m at 4.60 /s | 2.30 / 3.93 +- 0.51 BW (Weyand et al. 2009, at 10.8 m/s) | verified |
| elite sprinters | 11.5-12.3 m/s (Bolt 12.26; 2009 finalists 11.80 +- 0.23; ~11.6-11.8 at 1.75 m) | 0.084-0.104 / 0.104-0.136 s | 2.26-2.70 m at 4.4-5.0 /s | 2.3-2.45 / ~3.8-4.5 BW | verified (Krzysztof & Mero 2013; Bissas et al. 2018 World Athletics report); forces fig-read / derived |

**The probe.** The probe is `sprint_limits.py speeds --pitch-free`, chained
upward from 5 m/s. It reports two ceilings:

- **Margin:** the fastest speed at which the swing-time margin
  tc + 2 taer - t_sw stays positive.
- **Stance budget:** the speed at which the best penalised stance budget
  tc + 2 taer falls to a human swing time of 0.35 s (Weyand 2000: 0.373 +- 0.03;
  sprinters 0.33-0.36). This one needs no swing optimisation and is steadier.

Parameter changes come from `ROBOLAB_CALIB_SET` on a v4 body with an empty
calibration, which is v3 exactly (`scratchpad/sprint_knot/probe_batch.sh`,
`budget_ceiling.py`). Each screen row is one chain with one optimisation per
speed, so it carries about +-0.5-0.7 m/s: v4 itself measures 7.46 on one chain
and 8.2 on two. Only the strength and force-length rows stand clear of that
noise.

| factor (average body) | stance-budget ceiling, m/s (v3: 6.89) | what the literature says | in v4 |
| --- | --- | --- | --- |
| plantarflexor strength x1.5 | **9.10 (+2.2)** | the model's isometric capacities are already 1.4-2.9x young men's voluntary maxima (Anderson et al. 2007; Maden-Wilkinson et al. 2020; Krantz et al. 2020), as is usual in models | kept |
| vasti strength x1.5 | **8.91 (+2.0)** | as above | kept |
| force-length width 0.85-1.15 L0 (v3: 0.75-1.05, 0.5 of isometric at the short end) | **7.72 (+0.8)** | already generous: human muscles keep 0.1-0.35 at the short end (Anderson 2007; Maganaris 2001, 2003) | kept |
| foot friction 2.0 (v3: 1.2) | 7.50 (+0.6) | no source says 1.2 is too low; noise-level | kept |
| hip joint speeds 18.5 extension / 29 flexion rad/s (v3: 15 / 15) | 7.33 (+0.4) | derived: the standard models' 10 L0/s fibre speed (Thelen 2003; gait2392; Rajagopal 2016; Arnold & Delp 2011) x Ward et al. 2009's fibre lengths / hip moment arms. At 15 the muscles have ~0 force at sprinters' measured 14.8 rad/s hip extension and 13.8 rad/s thigh lift (Miyashiro 2019) | **applied (derived)** |
| hip extensor strength x1.5 | 7.32 (+0.4) | already above voluntary maxima | kept |
| Achilles stiffness x2 | 7.33 (+0.4) | 200 N/mm matches 188 +- 43 in hopping (Lichtwark & Wilson 2005); 306-319 (Rosager et al. 2002) | kept |
| quadriceps series stiffness x4 (250 -> 1000 N/mm) | 7.11 (+0.2; -0.1 in the first screen) | the OpenSim models' whole vasti series is ~976 N/mm (gait2392) / ~927 N/mm (Rajagopal 2016); the free patellar tendon is 1076-4334 N/mm (O'Brien et al. 2010; Hansen et al. 2006; and others) | **applied (verified)** |
| eccentric force plateau fvmax 1.6 (v3: 1.2) | 7.10 (+0.2; +0.9 in the first screen, +1.0 on the margin probe) | models use 1.4 (Millard et al. 2013; Rajagopal 2016) to 1.8 (De Groote et al. 2016; Thelen). This is modelling convention, and there is no in-vivo whole-muscle measurement | **not applied (uncertain)** |
| foot contact solref 0.01 s (v3: MuJoCo's 0.02) | 5.68 (-1.2; -0.2 in the first screen, -0.6 on the margin probe) | heel-pad and track stiffness suggest 0.005-0.01 s (Aerts et al. 1995; Kerdok et al. 2002), but this is checked only against peak forces, not measured | **not applied (uncertain)** |
| activation / deactivation x0.5 (v3: 10 / 40 ms) | 6.26 (-0.6) | 10 / 40 ms is the OpenSim default (Millard 2013); sprint simulations use 10 / 30 ms (Chumanov et al. 2011) | kept |
| hip flexor strength x1.5; leg mass x0.85 | the chains broke at 5.0-5.5 m/s (unreliable) | Dempster / Winter / de Leva masses match | kept |

**What caps the ceiling** is the vertical impulse that a short stance can
deliver. The knee and ankle extensors' force moves the ceiling most, then the
force-length width. The literature says the model is already generous in both,
so neither is raised to buy speed. Two v3 values are below the evidence: the
hip speeds (a 15 rad/s cap on a joint that sprinters move at 14.8 rad/s) and
the quadriceps series stiffness (a quarter of the models' value). **v4
changes exactly those two**, and nothing else.

**v4 build.** v4 is `HumanoidV4Builder` in `playground/body.py`, with its
calibration in `playground/calibrations/v4.json`:

- **What the JSON records:** each parameter's v3 and v4 values, its sources and
  its verification status. It also lists the parameters kept at v3 and why,
  the uncertain changes not applied with their measured effect, and the
  superseded first draft.
- **How to select it:** `ROBOLAB_CALIB` names a calibration file, and
  `ROBOLAB_CALIB_SET` overrides values for probes. `sprint_limits.py` builds v4
  under `ROBOLAB_BODY=v4`, and the tasks are `run_v4` and `sprint_touch_v4`.
- **Byte-identity:** the v2 and v3 XML are unchanged for the default, p95,
  elite and elite2 bodies, and an empty calibration reproduces v3's XML exactly.
- **v4a (superseded):** the first draft took the high-speed models' 15 L0/s
  (hip 30 rad/s both ways) and a recoil-assisted ankle speed (27). It was
  replaced before any sprinter was tuned on it; its ceilings were 8.35 / 10.95 /
  9.39 m/s.

**Validation** (ideal control, pitch free, the better of two chains per body):

| body | ceiling v3 | ceiling v4 | human | v4 at speed: contact / aerial / step / rate / mean F / peak F | human at that speed |
| --- | --- | --- | --- | --- | --- |
| average | 6.89 | **8.2** (7.9-8.6 for t_sw 0.37-0.33; margin chains 8.5, 6.5) | 7.8 (7.3-8.3) | at 8.0: 0.124 s / 0.146 s / 2.16 m / 3.71 /s / 2.18 / 4.81 BW | 0.120-0.130 / 0.109-0.124 / 1.96-2.00 / 3.96-4.21 / 2.07 / ~3.2 |
| P95 | 9.69 | **10.45** (margins 10.0, 10.5) | untrained P95 8.8-9.2; trained sprinters 9.90 +- 0.46 | at 10.0: 0.100 / 0.161 / 2.61 / 3.83 / 2.61 / 5.06 | sprinters at 9.9: 0.103 / 0.113 / 2.15 / 4.60 |
| elite2 | 8.5 | **9.28** (margins 8.0, 8.5) | elite 11.5-12.3 | at 9.0: 0.112 / 0.169 / 2.53 / 3.56 / 2.51 / 4.79 | - |

- **Average body:** its ceiling and its contact time land in the untrained
  range. Its ideal-control gait flies ~25 % longer than humans do. It steps
  ~10 % longer at a ~10 % lower rate, with ~6 % more mean and ~40 % more peak
  vertical force. The optimiser uses the 5 BW cap that the analysis allows,
  and the peak human forces are the least certain targets.
- **P95:** above the untrained 95th percentile and near trained sprinters.
  The profile is a composite, with every part at its own 95th percentile at
  once.
- **elite2:** far below elite sprinters, and below P95. The literature keeps
  elite knee and ankle extensor strength per kg near the untrained mean, and
  those extensors are what the ceiling is most sensitive to. Whatever else
  makes elites fast is not in the model. Stance technique and tendon
  properties beyond the Achilles are candidates.

**Sprinters on v4** (trials `sprint_top_speed_v4`, `_v4_p95`, `_v4_elite2`; the old trials and champions are untouched): in progress.

## MyoSuite bodies (MyoChallenge)

`playground/myo_bridge.py` hosts the same controller on a MyoSuite
environment: the MyoChallenge tasks with their official models (80-290
muscles on wrapped tendons) and scoring. It needs its own venv
(MyoSuite pins numpy < 2 and mujoco 3.6):

```sh
uv venv --python 3.12 .venv-myo && uv pip install --python .venv-myo/bin/python myosuite "numpy<2" scipy imageio imageio-ffmpeg pillow
./build.sh myo_hold
.venv-myo/bin/python playground/myo_bridge.py myo_hold --sheet out/myo_hold.png
.venv-myo/bin/python playground/practice.py myo_hold --gens 20 --workers 2 --out params/myo_hold.txt
```

The handshake adds `JOINT`, `MLEN` (each muscle's length sampled along
every joint it crosses), `MRANGE` and `MOTOR` lines. On the Tungsten side
`body.geometry` (class `Geometry` in `body.w`) turns a `Pose` into one
contraction per muscle, so skills still author equilibrium postures and
the reflexes hold them; `Skill#joint_offset` shifts every muscle crossing a
joint; `frame.q(body, joint)` / `frame.qd` read joint angles; non-muscle
actuators (the table-tennis pelvis, the prosthetic knee and ankle) are set
with `ctl.motor(name, value)`. MyoSuite's action normalisation
(`sigmoid(5 (a - 0.5))`, so control saturates at 0.924) is inverted by the
bridge. Environment observations arrive as sensor blocks named `env_<key>`
(e.g. `env_ball_pos`). Tasks subclass `MyoTask` (see `tasks/myo_hold.py`).
Two opt-in task flags make posture-to-contraction more exact:
`coupled_geometry = True` samples lengths with MuJoCo's joint-equality
couplings applied (the knee's patella and dependent joints), and
`geometry_pairs = True` adds validated joint-pair length corrections (`MPAIR`
lines, cached in `playground/cache/`). Measured end to end against exact
MuJoCo lengths, the chase-tag legs' mean contraction error drops from 0.014
to 0.0025 and soccer's from 0.009 to 0.0027.

Challenge environments (MyoSuite 2.12.2): `myoChallengeTableTennisP1-v0`
(273 muscles + 2 pelvis actuators, 3 s), `myoChallengeSoccerP1-v0` (290
muscles, 20 s), `myoChallengeChaseTagP1-v0` (80 muscles, 20 s),
`myoChallengeOslRunFixed-v0` (54 muscles + prosthetic knee/ankle motors),
plus `P2` variants, `myoChallengeBimanual-v0`, relocate, baoding and
die-reorientation environments.

### Soccer penalty kick (`skills/myo_soccer.w`)

`MyoSoccerSkill` on `myoChallengeSoccerP1-v0` / `P2-v0` (290 muscles; task
`tasks/myo_soccer.py`, `MYO_SOCCER_ENV` selects the phase). Phase 1 (identical
start, stationary keeper) with `params/myo_soccer.txt`: **100 / 100 goals**
(seeds 0-99, Wilson 95 % [0.963, 1.0]), ball 12.0-12.6 m/s, goal at
2.9-3.0 s, no falls (`out/myo_soccer_metrics.json`).

Phase 2 (start x in [38, 39], y in [-1, 1], +-0.02 rad joint noise, moving
keepers): **0 / 100 goals** (seeds 20000-20099, Wilson 95 % [0, 0.037]) for
every controller tried, against the 2025 winner's 32 %
(`out/myo_soccer_p2_metrics.json`, `out/myo_soccer_p2.{mp4,gif}`,
`out/myo_soccer_p2_sheet.png`). What was found:

- The practised kick rides the key-frame start's transient: it misses even
  from a 2 cm offset with the reset's joint noise.
- Quiet standing with the phase-1 gains falls on 28 / 30 phase-2 starts
  within 10 s (a thorax-roll hip term feeds back positively); the stance
  re-practised on fresh phase-2 starts falls on 2 / 30.
- Single support is the blocker for an approach: the COM drifts outward over
  the stance foot and the pelvis yaws by up to 1 rad, so quasi-static steps
  succeed about once (median 1 step) before a fall.

The phase-2 machinery is in the skill, all opt-in (the phase-1 params
reproduce exactly): the approach (branching quasi-static steps, min-jerk
weight shift, IK placement with pelvis-yaw compensation, apex / abort
latches, capture-point term), `kv2` (the plant step as an approach step
beside the ball, then lunge, wind-back and kick), `kf_ref` (postures
anchored to the key frame), `hq` (stance hip as a decoupled torque servo,
`MyoSoccerHip`), `ff_trunk`, and a side-foot swing (`side`). Params:
`params/myo_soccer_p2_robust_kick.txt`, `params/myo_soccer_p2_approach_plant.txt`,
`params/myo_soccer_sidefoot.txt`.

Where the ball is struck: the task records the ball-foot contacts of the
first 0.1 s in the foot's frame (`strike_zone`, `strike_point_all`: toe if
>= 0.17 m ahead of the heel origin, inside / outside if >= 2.5 cm to the
medial / lateral side). The phase-1 kick strikes with the ball of the foot
and toes (100 / 100 `toe`, contact 0.21 m ahead, 1.4 cm medial). The
side-foot variant (hip turned out to its -0.7 rad limit, ankle locked in
dorsiflexion) also scores 50 / 50 in phase 1 at 11 m/s but meets the ball
with the medial side of the toes (0.24 m ahead, 1.9 cm medial), not the arch:
the pelvis yaws toward the plant side during the swing and cancels the
turn-out. Inside-of-the-foot strikes: 0 %.

```sh
./build.sh myo_soccer
.venv-myo/bin/python playground/myo_bridge.py myo_soccer --params params/myo_soccer.txt --episodes 100 --seed 0 --json /tmp/p1.json
.venv-myo/bin/python playground/tasks/myo_soccer.py summary /tmp/p1.json
MYO_SOCCER_ENV=myoChallengeSoccerP2-v0 .venv-myo/bin/python playground/myo_bridge.py myo_soccer \
    --params params/myo_soccer_p2_robust_kick.txt --seed 20000 --gif /tmp/p2.gif
```

#### Round 3: standing on one leg, and the inside of the foot (`skills/myo_soccer_v3.w`)

`MyoSoccerV3Skill` (entry `lib/entry/myo_soccer_v3.w`, `./build.sh myo_soccer_v3`)
subclasses the round-2 skill; everything is behind params-file switches
whose tunables are only declared when on, so older params files replay
unchanged: `bal` (the single-leg routine), `ap3` (a quasi-static approach
built from its chunks), `inside` (the inside-of-the-foot kick), `sb_ap`,
`dec` / `dec_nf`, `sbf`, `in_direct` (see the file's header). Single
support is its own controller, one gain set for both legs (sign-mirrored):
stance ankle on the COM's fore-aft error, stance subtalar inversion and hip
adduction on its outward offset and velocity, the swing side's pelvis drop,
the swing leg as a counterweight, lumbar lateral bend toward the stance
leg, a heading servo on the stance hip's rotators, antigravity /
abductor / ankle co-contraction drives. Two new arena trials:

- `soccer_single_leg`: from 40 phase-2 resets, stand on the left leg, then
  the right; `bal_s` = seconds on each leg alone (other foot < 5 % body
  weight), up to 3 s per leg, counted while still standing (pelvis above
  0.7 m, thorax within ~45 deg). Baseline (robust stance + untuned routine)
  1.28 s; sep-CMA over 50 tunables on fresh phase-2 starts 1.88 s (paired
  diff +0.60 s, p < 0.001); champion **1.96 s**: that plus co-contraction of
  the stance hip's rotators (`sb_rot_cc` 0.15, +0.08 s, p = 0.03;
  `params/myo_soccer_single_leg_rotcc.txt`), median 2.0 s, two starts at
  the full 3 s on the left leg; the right leg is rarely reached (`bal_r`
  0.05 s). Challengers that lost: the hip's COM-velocity term reversed (the
  fast hip strategy, +0.003 s, p = 0.48), COM errors in the joints' own
  frames (`sbf`, -0.03 s, p = 0.63), pelvis heading held (`dec_nf`,
  1.31 s), stronger rotator co-contraction (0.3, -0.002 s). Video:
  `out/soccer_balance.{mp4,gif}`.
- `soccer_p1_inside`: phase-1 goals struck with the inside of the right
  foot (`goal_inside`: goal and `strike_zone` inside). Baseline (the
  soccer_p1 champion) 0 / 50 (it scores 50 / 50 with the toes). No
  challenger has struck the ball with the inside yet.

What the model taught (measured, and built around):

- Double-support hip terms push the pelvis toward the loaded foot; on one
  leg the same terms feed a fall outward. Single vs double support is now
  decided by the loads, not the phase.
- The weight shift has to arrive with the capture point on the stance
  foot (damping `b_kayv` 1.3 -> 3 took the routine from 0.8 to 1.5 s); a
  pelvis-roll rate term on the stance hip drives an 8 Hz abductor /
  adductor limit cycle (stance-foot load swinging 0.4-1.4 body weights).
- The feet have almost no torsional grip (condim-3 contacts a few cm
  apart): a hip rotation torque above ~40-60 N m spins the foot, not the
  pelvis, and the hip's internal rotators give only ~54 N m (external
  ~120). Standing on one leg the pelvis still yaws to the stance hip's
  rotation limit (0.8 rad) in the champion. The hip's rotation stiffness
  is ~13x below its flexion stiffness and 0.42 coupled to it, so a
  decoupled (`dec`) flexion offset carries 1.5x its size of external
  rotation; plain rotation offsets turn the pelvis the right way.
- The inside of the foot needs the pelvis turned toward the kicking side.
  Swept over the right leg's joint ranges on the model: the foot's inside
  faces within 15 deg of the goal only with the pelvis at -0.5 to -0.7 rad
  (hip turned out to its -0.7 limit, abducted 0.2-0.45, knee 0.6-1.0,
  ankle up); square it is 38 deg off, and at +0.6 rad, where every
  left-foot plant step leaves it (the swing's reaction, the stance foot
  spinning up to 150 deg on its toes in the push-off), 71 deg (47 with the
  pelvis rolled). Turning it back on the plant foot exceeds the foot's grip.
  Built and tried (`inside 1`): the run-up plus a foot pivot and
  double-stance pre-turn (reaches -0.2 rad), a lunge plant with a two-hip
  pelvis turn, the inside swing straight off the plant (`in_direct`), a
  turned `ap3` approach; sep-CMA on the shaped `inside` objective found toe
  pokes and falls. Inside strikes: 0 %. Video of the failure mode (the
  turned-out foot meets the ball with its outside): `out/soccer_inside.{mp4,gif}`.
- Phase 2: `ap3` steps (the routine's shift and lift, an IK-placed reach
  with ground clearance and capture-point placement, the heading servo),
  sep-CMA 15 generations on the `ap3` objective
  (`params/myo_soccer_p2_ap3.txt`): on 9 soccer_p2 starts one step that
  closes 0.2 of 0.96 m on average, 3.8 s standing, then a fall (the pelvis
  yaws ~1 rad in single support, as in the balance routine); no phase-2
  goals, so no soccer_p2 entry. The shared blocker for balance, stepping
  and the inside kick is holding the pelvis heading on one leg within the
  stance foot's torsional grip.

```sh
./build.sh myo_soccer_v3
.venv-myo/bin/python playground/arena.py eval soccer_single_leg --params params/myo_soccer_single_leg_rotcc.txt \
    --controller bin/robolab_myo_soccer_v3
MYO_SOCCER_CAM=front MYO_SOCCER_ENV=myoChallengeSoccerP2-v0 ROBOLAB_CONTROLLER=bin/robolab_myo_soccer_v3 \
    .venv-myo/bin/python playground/myo_bridge.py myo_soccer --params params/myo_soccer_single_leg_rotcc.txt \
    --seed 81032 --video out/soccer_balance.mp4
```

#### Round 4: turning by stepping, and five minutes on one leg (`skills/myo_soccer_v4.w`)

`MyoSoccerV4Skill < MyoSoccerV3Skill` (entry `lib/entry/myo_soccer_v4.w`,
`./build.sh myo_soccer_v4`); every behaviour is a params switch, and files
without them replay V3 exactly (the rotcc champion scores 2.09 s on seed
81000 on both builds). Switches: `tlh` (twist-limited heading hold),
`fyaw` (swing foot turned in the air to its landing heading), `hg` (stance
hip kept off its extension limit), `ap4` (the approach as a turning gait),
`in4` (angled approach + standing inside kick), `rk4` (the round-4 terms in
the running side-foot kick, `rk_wait` waits on the plant foot for the turn),
`bcatch` (falls caught by stepping), `cp4` (single support on the sensed
centre of pressure), `sense_arms` / `live_axes` (hip offsets through live
moment arms). The task gained opt-in sensors, sent only when the params
carry `sense_arms 1` (older controllers see the same handshake): the hips'
live moment arms (`arm_<joint>`), each foot's torsional grip (`grip_cap`,
sum mu N |r - cop| over its ground contacts) and centre of pressure in the
foot's frame (`foot_cop`).

What was measured (and what it overturned):

- **The stance foot does not spin in single support.** In the round-3
  champion's hold the foot's heading stays within 0.02 rad while the pelvis
  swings to the stance hip's external-rotation stop (-0.7 rad); the ground
  twist is 1-15 N m against a grip of 45-68 N m. Grip is a contact count
  problem: condim-3 contacts have no torsional friction, so a flat foot
  holds ~60-68 N m at one body weight and a foot on one point (the toes in
  push-off, an edge) holds none; that, not the hip, is where the running
  kick's twist comes from (the push-off foot spins 2 rad on its toes).
- **The controller's hip geometry is wrong exactly where single support
  lives.** The geometry is additive (each joint swept alone at the reset
  posture), and the gluteal moment arms flip with hip flexion and rotation:
  over the stance range glmed1's rotation torque per activation runs from -29
  to +37 N m and glmax1/2 from -58 to +23; at the one-leg corner (hip
  extended to its -0.53 limit, adducted, turned out) glmed1, glmin1 and TFL
  extend and externally rotate the hip. A commanded internal rotation there
  drove them to 0.9 activation and produced -9 N m (the wrong way), and a
  flexion offset pushed the hip further into extension: the corner is an
  attractor. `sense_arms` fixes the actuation (the hip guard then holds
  flexion at -0.3 instead of -0.53); only iliacus and adductor longus keep an
  internal-rotation arm everywhere (~12 N m together).
- **The lateral base of support is ±2 cm.** The two sole capsules touch the
  ground along their axes, 2 cm either side of the foot's centre line, so the
  measured COP never leaves ±0.02 m. In the round-3 hold the COM target sat
  4 cm medial (sb_y -0.041, the optimizer's answer to a proportional loop with
  a bias) and the ankle drove the COM into a medial fall; the capture point
  diverges from the COP within 0.25 s of lift-off.

**Balance, `cp4`** (single support on the sensed COP): the capture point
(COM + v / omega) in the stance foot's frame sets a COP target
`cp + cp_k (cp - ref)` clipped to the sole; the subtalar (inversion moves the
COP outward) and the ankle servo the measured COP to it; what the sole
cannot take goes to the stance hip's adduction (a hip strategy, sign found by
test: an inward excess adducts, throwing the trunk into the fall); a slow
integrator (`cp_ki`, positive) moves the reference so the COP stays centred.
Without that integrator the best hold stood 96 s and fell: the pelvis yaw
crept 0.2 rad over 90 s and walked the COM onto the sole's edge; with it the
same start stands the full 300 s. Tuned with sep-CMA on fresh P2 starts,
30 s episodes: G (hold gains) then H (the shift, capture and lift into single
support).

| trial (arena) | champion before | round 4 | paired diff, p |
| --- | --- | --- | --- |
| `soccer_single_leg` (s per leg, max 6) | 1.96 (rotcc) | 2.32 `bcatch` + `tlh` (sep-CMA D) | +0.36, p = 0.007 |
| `soccer_single_leg` | 2.32 | **2.59** `cp4` hold, 3.05 s per leg (`params/myo_soccer_single_leg_cp4.txt`) | +0.27, p = 0.048 |
| `soccer_single_leg_300` (new: longest continuous stretch on one leg, 300 s episodes, 20 fresh P2 starts) | 1.07 (round-3 routine, unlimited holds) | **149.9 s**, 10 of 20 starts the full 300 s (`params/myo_soccer_single_leg_300_cp4.txt`) | +148.8, p = 0.001 |

The 300 s distribution is bimodal: 10 / 20 starts stand 298.4-298.5 s (the
whole episode after the shift), 2 more pass 3 s, and 8 fall within 2 s of
lift-off (the transition, not the hold). In `soccer_single_leg` the left leg
reaches 2.41 s on average but the right leg rarely follows (0.18 s): the
put-down and the second shift are where it falls. Challengers that lost:
`tlh` alone, untuned (1.97 vs 1.96, p = 0.43), `bcatch` untuned (1.96,
p = 0.50); live arms on the round-3 gains (1.7 s on 12 validation starts:
every gain was tuned against the wrong slopes).

**Turning by stepping** (`ap4`): each step's foot lands turned by at most
`s4_turn` from the stance foot toward the walking heading (at the spots
while far, the final heading near), its spot clipped in that heading's
frame; `fyaw` turns the foot in the air (the hip's rotation servoing the
foot's measured heading); `tlh` holds the pelvis square to the loaded feet,
its twist clipped to each foot's grip. On P2 (sep-CMA C, 16 gens) the
approach still takes one step and falls (standing 4.3 s; the reach's swing
reaction yaws the pelvis into the stance hip's stop): soccer_p2 **0 / 100**
(`params/myo_soccer_p2_ap4.txt`, `out/soccer_p2_v4.{mp4,gif}`, seed 6106).
With the `cp4` hold (untuned for stepping) it also falls after one step.

**Inside of the foot** (`rk4` on the side-foot running kick, sep-CMA E 20
gens on the inside objective): 50 % goals at 8.2 m/s with the contact 2.8 cm
medial but on the toes (0.24 m ahead): the pelvis still turns +50 deg toward
the plant side in the run-up (the push-off foot, on its toes, has no grip);
waiting on the planted foot for the turn (`rk_wait`) does not stop it.
soccer_p1_inside **0 / 50** (`params/myo_soccer_inside_rk4.txt`,
`out/soccer_inside_v4.{mp4,gif}`). The angled quasi-static approach and
standing inside kick (`in4`) is built but untuned.

```sh
./build.sh myo_soccer_v4
.venv-myo/bin/python playground/arena.py eval soccer_single_leg_300 --params params/myo_soccer_single_leg_300_cp4.txt \
    --controller bin/challengers/soccer4-bal300 --workers 4
MYO_SOCCER_CAM=front MYO_SOCCER_ENV=myoChallengeSoccerP2-v0 MYO_SOCCER_MAX_TIME=300 ROBOLAB_CONTROLLER=bin/challengers/soccer4-bal300 \
    .venv-myo/bin/python playground/myo_bridge.py myo_soccer --params params/myo_soccer_single_leg_300_cp4.txt \
    --seed 88005 --seconds 300
```

Video: `out/soccer_balance_300.{mp4,gif}` (seed 88005, the first 40 s of a
298 s stance, 15 fps).

#### Round 5: five minutes strictly, the lift, and the phase-2 approach

New V4 switches (all opt-in; older params files replay): `bsettle` (the set
and every mid-stance wait for a still, square double stance), `bplace` (the
put-down steered toward the capture point), `bdown` (in the mid-stance,
single support by the loads until the put-down foot carries weight),
`tl_cf` (a landing or lightly loaded foot's hip stops pulling toward the
posture's rotation, so it does not twist the foot it lands on), `bcout`,
`blv` (lift guards, both rejected), `cp_khf` (a sagittal hip strategy in
`cp4`), `s4set` (the approach's steps wait for a settled stance), `k4`
(after the approach, a standing kick: weight onto the plant foot, the kicking
leg wound back on the one-leg posture, the parent's swing). A new skill
`skills/myo_soccer_walk.w` (entry `myo_soccer_walk`) runs the chase-tag
walker on the soccer body (the 80 leg muscles by name, a trunk track on the
210 lumbar muscles); the task sends `muscle_fmax` / `muscle_range` with
`walk_consts 1` and scores the walking approach (`walk_closed`,
`walk_t_arrive`; practice stages `walk`, `p2`).

New trial `soccer_single_leg_310` (310 s episodes, 20 fresh P2 starts,
metric `bal1_300` = 1 when the one-leg hold itself reaches 300 s; the 300 s
trial's hold stopped at 298.4 s inside its episode). Seeded with the
`soccer_single_leg_300` champion: **12 / 20** stances hold five minutes.
Challengers: the round-5 transitions (sep-CMA J) 13 / 20 (p = 0.49), the
lift tuned on an 8 s proxy (sep-CMA L: 16 fresh starts per generation;
falls within 8 s on 40 held-out starts 37.5 % -> 7.5 %) **15 / 20** (mean
hold 232 s; p = 0.23 on 20 starts, champion kept). Every remaining failure
is still the lift: in the failing starts the swing foot leaves the ground
while carrying 20-40 % of the weight and throws the capture point 5-6 cm
outward, past the ±2 cm the sole's COP can reach, and the stance foot spins
0.3-0.4 rad; waiting for a fully unloaded foot or a still COM before the
lift makes it worse (90-100 % falls: the double-support shift is not stable
once the weight is over one foot).

| trial | before | round 5 | paired diff, p |
| --- | --- | --- | --- |
| `soccer_single_leg` | 2.59 | **3.08** (`params/myo_soccer_single_leg_trans.txt`: bsettle, bplace, fyaw, tl_cf, sep-CMA J); right leg 0.18 -> 0.63 s | +0.49, p = 0.028 |
| `soccer_single_leg_310` (new) | - | 12 / 20 seeded; 15 / 20 challenger (`params/myo_soccer_single_leg_310_lift.txt`) | +0.15, p = 0.23 |

Phase 2 (no goals yet). The P2 starts sit 0.02-1.4 m from the phase-1
stance (arena seeds: 20 % within 0.5 m, 77 % within 1 m) and the episode is
10 s; a kick needs ~2 s plus ~1 s of ball travel, leaving ~6 s for the
approach. Measured so far:

- The phase-1 kick is a trajectory from its key-frame start: from a settled
  stance (t_set 0.8 / 1.5 s) its plant step lands short or the ball goes
  32 deg wide at 5.5 m/s. Re-practised on 40 P2 starts within 0.3 m of the
  phase-1 stance (sep-CMA K, 24 gens, kick2 objective) it scored 2 training
  goals and otherwise falls in the run-up (stand time ~2 s).
- The quasi-static approach steps take 2.5-3 s each (at most two fit), and
  the first step still fails on the right leg: the reach's swing reaction
  turns the pelvis to the right hip's external-rotation stop (+1.1 rad) with
  the hip at its extension limit. The long hold's tuning is left-leg only.
- The chase-tag walker on the soccer body folds at the lumbar spine within
  0.5 s (flexion -0.6 to -1.0, thorax pitched 1-2 rad): the soccer trunk's
  rectus abdominis pulls the spine into flexion unless the pelvis is tipped
  back, and the walker's hip servo and poses assume a rigid upright torso.

#### Rounds 6-7: the trunk, and a kick for phase 2 (no goals yet)

The trunk, measured statically (`scratchpad` trunk map: every pelvis tilt x
lumbar angle at the key-frame legs, the extension torque the rectus
abdominis's passive pull plus the upper body's weight need, over all the
extensors' capacity at full activation): **84-123 % whenever the thorax is
upright**, whatever the pelvis does; 50-73 % only with the thorax leaning
back 0.45-0.7 rad (lumbar extended), 76-84 % with the pelvis tipped back
0.4 rad or more (the soccer stance, which uses up the hip's extension
range). The walker port (`skills/myo_soccer_walk.w`) therefore stands, in a
set that holds the soccer stance's trunk (6 s: lumbar -0.22, thorax -0.06,
pelvis -0.50), but every stepping attempt folds or falls within 0.6-1.8 s;
sep-CMA on the walker's gait from that set (W2, W3) only closed distance by
falling forward, and the lean-back posture could not be reached (the lumbar
never extended past -0.05 rad with every extensor saturated).

Round 7 kept the soccer skill's trunk and built the phase-2 kick from its
pieces (V4 switches `ks5`: the routine's settle, then the parent's run-up and
kick, optionally after `ap4` steps; `s4_knee`, `s4_hip`, `s4_tmove`: a
crouched step stance and a smooth swing for the approach steps; `rk4` with a
yaw-compensated plant placement, `rk_yawc`). The task gained `plant_err`
(distance of the body's state at the plant from the phase-1 champion's,
`playground/tasks/data/soccer_plant_ref.json`) and practice stages `clone`,
`plant5`, `step`, `walk2`. Measured on 30 held-out P2 starts within 0.3 m of
the phase-1 stance:

| kick | goals | notes |
| --- | --- | --- |
| phase-1 champion as is | 0 / 30 | falls within ~2 s (the reset's joint noise) |
| settled stance, run-up + kick re-practised (sep-CMA K, N: 24-30 gens, kick2) | 0 / 30 | ball 1-2 m/s: the plant lands across the ball's line or the body falls onto it |
| settled lunge-plant, practised to stand on the plant foot (P, P2) | - | never holds the plant foot (0.1-0.27 s): the lunge turns the pelvis +1 rad |
| plant state cloned to the phase-1 champion's (sep-CMA R, 30 gens) | 0 / 30 | plant_err 4.5-5 on good starts (COM and pelvis yaw match, the kicking leg's hip does not); ball 1-2 m/s |

The approach steps (sep-CMA Q, 30 gens on fresh P2 starts): at most two
steps (1.5-2 s each) before a fall. No soccer_p2 entry this round (0 on
its most favourable starts).

### Locomotion on the myoLeg (chase-tag)

`skills/myo_walk.w` walks the 80-muscle ChaseTag myoLeg (free root, torso
rigid on the pelvis) under the official dynamics and actuators;
`skills/myo_chase.w` (`MyoChaseSkill < MyoWalkSkill`) steers it at the
opponent from the official observations. Tasks: `tasks/myo_chase.py` (the
official P1/P2 env untouched; the score is the official `rwd_sparse` sum),
`tasks/myo_walk.py` (courses `straight`, `turn`, `uturn`, `circle`,
`waypoints` and practice mixtures, optional pushes) and `tasks/myo_stand.py`
(quiet stance with a push schedule). Pushes are robustness tests only.

```sh
./build.sh myo_walk myo_chase
.venv-myo/bin/python playground/myo_bridge.py myo_chase --params params/myo_chase.txt --seed 184 --video out/myo_chase.mp4
.venv-myo/bin/python playground/myo_bridge.py myo_chase --params params/myo_chase_v2.txt --seed 353 --video out/myo_chase_v2.mp4   # round 2: turning loop, opponent 3.4 m behind
CHASE_SETUP=turn CHASE_SECONDS=12 .venv-myo/bin/python playground/search.py myo_chase --method sep_cma --seeds 0,1,2,3,4,5,6,7 --init params/myo_chase_v2.txt --only th_on,lead_max_t,yq_kd_t,hr_lim_t --out p.txt
WALK_COURSE=turn WALK_T0=0.8 .venv-myo/bin/python playground/myo_bridge.py myo_walk --params params/myo_walk.txt --seconds 10
```

Walking (mode 1) is two tracks, one per leg, each looping four chunks
latched on that leg's own sensations: `stance` (COM passes `d_push` ahead of
the foot, other leg not pushing) -> `push` (toe-off) -> `lift` (thigh swung
past `psi_go` in world frame) -> `reach` (heel contact) -> `stance`. Loaded
hips servo the trunk in torque units through `MyoWalkHip`, a decoupled map
from hip torque to per-muscle contraction offsets: on the myoLeg hip the
lambda servo is not axis-pure (a 0.1 rad kinematic offset gives 72 N m of
adduction but 4 N m of rotation and leaks 2-18 N m across axes). Swing
placement (Raibert/SIMBICON, forward and lateral, plus a centripetal turn
term) lives in a travel frame that follows the smoothed COM velocity, so a
yawing pelvis (this model has no arm swing) is not read as a sideways fall.
Mode 2 is Song and Geyer's reflex walker as ported to the myoLeg in
MyoSuite (`agents/baseline_Reflex`), rewritten as chunks and group drives.
Mode 0 is quiet standing (ankle, hip and lateral-shift strategies).

Practice was CMA-ES from the official P1 reset (mid-stride at 1.5 m/s),
through a curriculum: straight walking, then turns and circles (with a
pelvis-yaw penalty), then U-turns. Results on the final parameters:

| measure | result |
| --- | --- |
| ChaseTag P1, official score, 100 held-out seeds (100-199) | **0.501 ± 0.032** (tagged 77%, fell 17%, out of bounds 0%, mean tag 7.0 s) |
| by opponent bearing at the start | ahead (<45°) 0.71, tag 4.4 s (straight-line optimum ≈4.2 s); 45-90° 0.47; behind (>90°) 0.35-0.36 |
| ChaseTag P2 (random terrain and reset, CHASE/EVADE), 30 episodes | 0.110 ± 0.028 (falls 73%; EVADE 0.25 by survival time, CHASE 0) |
| walking speed (v_des 1.0 / 1.3 / 1.5) | 1.20 / 1.34 / 1.42 m/s (human preferred ≈1.3-1.4) |
| cadence, step length | 3.6-3.9 steps/s, 0.33-0.36 m (human ≈1.8-2.0 steps/s, ≈0.7 m: short fast steps) |
| sustained turn | 0.5 rad/s left for 19 s; right turns and 3 m circles fall within 2-9 s |
| effort (mean squared activation, 80 muscles) | 0.069-0.074 |
| positive muscle work / (m g d) | 0.73-0.75 (≈7 J/kg/m; human walking's positive mechanical work is ≈0.8 J/kg/m) |
| pushes while walking (0.2 s, circle course) | falls after the first push at 50 N and above |
| quiet stance (mode 0, `params/myo_stand.txt`) | 10 s at effort 0.004; survives 60-80 N x 0.2 s pushes (2-4 of 4), not 100 N (feet in place, no stepping) |

For reference, the 2023 challenge was won by GaitNet at 0.666 on the final
(P2-style) evaluation. The walker reaches the edge of the arena upright in
a straight line, and the Song-Geyer port does too (6.6 m in 4.0 s, effort
0.17). The limits are turning (the hip rotators hold 49 N m internally and
there is no arm swing, so each swing kicks the pelvis in yaw), push
robustness, rough terrain, and a costly short-stepped gait.

#### Round 2: a turning loop, longer strides

Every new behaviour is a params flag; files without it run the round-1 gait
exactly (seeds 100-105 reproduce round 1 score for score on the new build).

- **Turning loop** (`turn_gait 1`, `params/myo_chase_v2.txt`). Each leg's
  movement holds a second loop, `X_tstance -> X_tpush -> X_tlift ->
  X_treach`, and every chunk names its successor with `Chunk#branch`. So any
  chunk boundary can enter the loop while the goal heading is more than
  `th_on` off the direction of motion, and leave it below `th_off`. In the
  loop:
  - the walker aims at the target bearing itself (`psi_goal`), not the
    chase skill's rate-limited command;
  - the travel frame may lead the motion by up to `lead_max_t`;
  - the stance hip turns the pelvis over the planted foot, but only within
    +-`hr_lim_t` of hip rotation, with yaw damping and a torque cap (the
    joint stops at 40 deg, and a pelvis carried into the stop spins both
    soles);
  - the swing foot lands outside the turn (`k_turn_t`).

  Tuned with sep-CMA (sigma 0.04) on 8 fixed turn setups (`CHASE_SETUP=turn`
  in `tasks/myo_chase.py`: a stationary opponent at +-90, +-135, +-160, 180
  and 40 deg, 2.5-4 m away). With the tuned values it is a
  brake-free step turn: speed stays near `v_chase`, and the gain comes from
  aiming at the bearing, twice the travel-frame lead (0.2 rad), yaw damping
  and the hip-range limit. Braking harder (`v_t`) or leading harder
  (`lead_max_t` 0.5) fell every time.
- **Longer strides** (`stride 1` adds a trailing-leg push-off latch on the
  leading foot's load; `lift_via 1` makes the lift a `Chunk#via` keyframe).
  Changing the landing angle, swing timing or push-off by hand stalled the
  gait within 2-4 s (the COM loses its speed over the longer step), and so
  did `lift_via`. Four approaches were tried:
  - a cadence penalty: the gait slowed down instead;
  - a pace-held cadence penalty: no gain;
  - MAP-Elites over (step length, speed): 16 cells in 1800 rollouts;
  - sep-CMA paying step length at held pace (`WALK_STEP_REWARD`,
    `WALK_SPEED_W`, course `multi_stride`): the two stride results below.
- **Tried and rejected on the chase**:
  - the internal-model feed-forward (`ff_gain` 0.3 / 0.6 on top of v2):
    falls 4 -> 20 of 30 episodes;
  - exact geometry (`MYO_GEOM_PAIRS=1`): falls 4 -> 19 of 30;
  - standing-key geometry (`MYO_GEOM_REF=0`): every turn setup fell within
    3 s;
  - the circle-robust gait below, in the chase: 0.46 -> 0.36.

  The round-1 tunables are fitted to the reset-posture additive geometry,
  so any of these needs the gait re-practised. `playground/myo_bridge.py`
  gained a `geometry_ref_key` task hook for this.

| measure (round 1 -> v2) | result |
| --- | --- |
| ChaseTag P1, official score, 100 fresh seeds (300-399), same seeds | 0.462 +- 0.070 -> **0.595 +- 0.058** (paired +0.133 +- 0.054, p < 0.001); tagged 69 -> 83 %, fell 21 -> 17 %, mean tag 6.6 -> 5.7 s |
| by opponent bearing (300-399) | ahead 0.64 -> 0.63, side 0.38 -> 0.66, behind 0.29 -> 0.52 |
| arena `chase_p1` (seeds 700-799) | 0.392 -> **0.564 +- 0.060** (paired +0.172, p < 0.001; promoted) |
| ChaseTag P2, 100 fresh seeds (400-499) | 0.141 +- 0.036 -> 0.155 +- 0.040 (n.s.; CHASE 0.00, EVADE 0.29 -> 0.32 by survival time); arena `chase_p2`: 0.160 -> 0.152, champion kept |
| stride gait `myo_walk_v2_stride.txt` (straight, v_des 1.3) | 3.77 -> 3.33 steps/s, 0.354 -> 0.393 m, 1.34 -> 1.31 m/s, effort 0.069 -> 0.062; less robust in turns and circles |
| stride gait `myo_walk_v2_stride_b.txt` | 0.47 m at 3.2-3.3 steps/s, but ~1.5 m/s at any v_des (it trades pace control for step length), effort 0.050; falls in circles |
| arena `walk_stride` (step length, 8 speeds, no-fall guard) | 0.362 -> 0.394 (p = 0.007) -> **0.462** (p = 0.004), promoted twice |

The 2023 winner's 0.666 is still ahead on P2. P2 is decided in the first
seconds:
- the random reset adds N(0, 0.02) noise to the knee's coupled
  translation dofs, and the equality constraints snap them back. On flat
  ground 8 of 12 P2-style resets fall with the noise, 4 of 12 with noise on
  the independent joints only, and 3 of 12 with none;
- the walker often starts on a rough or hilly patch. Its feet touch the
  heightfield at 5-13 cm in the first 0.1 s, and it falls within 0.5-3 s.

Human strides (0.6-0.7 m at 1.8-2.0 steps/s) were not reached. The chunk
gait's swing is ballistic and short (0.25 s against a human's 0.4 s), and a
longer landing angle costs more speed at every touchdown than the push-off
returns. A slower swing likely needs a keyframed swing (the human gait
cycle, velocity-continuous) trained for balance from scratch.

### Table tennis: spin and stroke families (`skills/myo_tt.w`)

The table-tennis skill (block with an aim law; see the file's header) has an
opt-in spin model and stroke-family choice (`spin_mode 1`, `fam_mode 1`;
`params/myo_tt_spin.txt`). Every contact (an opponent's paddle, the table,
our pad) follows one linear friction model: it removes the share `k` of the
slip of the ball's surface over the other surface, and the friction impulse
spins the ball by `c k (n x slip)` (`c = r m / I`). Spin is estimated from
what is seen: the ball's horizontal velocity just before and just after the
table bounce (position differences on each side), whose change gives the
friction impulse and so the spin (`cb (dv_t x z)`); the serve's own spin
comes from the opponent's paddle (face pitch and swing, `opp_mode 1`) or is
zero from the challenge's launcher. At our pad, spin adds `ks r (w x n)` to
the return (topspin jumps up off a still face, so the face closes; backspin
drops, so it opens), and the aim law solves the face for the target with it.

Stroke families: `block` (still pad), `over` (forward and up, face closed),
`chop` (forward and down, face open), `give` (back with the ball). For each,
the contact solution is the paddle's velocity at contact plus the face the
aim law then needs; the family is chosen per serve (`Chunk#branch` out of
`ready`) by its robust landing margin (the worst landing, net clearance
included, over pad normals `fam_sig` off) less `fam_turn` per radian of face
turn. The stroke is a `Chunk#via` keyframe at the contact pose, passed with
the command's velocity toward the family's follow-through (the Hermite from
rest draws the backswing).

`playground/myo_tt_spin_fit.py` fits the model to MyoSuite 2.12.2, using the
simulator's true angular velocity only offline: table bounce `cb` 0.432
(estimate error 0.0005 rad/s), our pad `e` 0.97, `k` 0.011, `ks` 0.0075.
The challenge's model clamps every body's inertia to at least 1e-4 kg m^2
(`boundinertia`), 139 times the ball's shell inertia (7.2e-7), so friction
barely spins the ball (0.024 rad/s after the bounce) and spin barely moves
it; with no air (`opt.density` 0) there is no Magnus curve either. The spin
model is exact here, and its compensation is negligible.

```sh
./build.sh myo_tt
.venv-myo/bin/python playground/myo_tt_spin_fit.py bounce      # and: pad
TT_ENV=P2 .venv-myo/bin/python playground/tasks/myo_tt.py --params params/myo_tt_spin.txt --episodes 100 --seed0 2000000 --out out/x.json
TT_ENV=P2 TT_SPIN_ORACLE=1 .venv-myo/bin/python playground/tasks/myo_tt.py --params params/myo_tt_spin.txt --set spin_oracle=1 ...
```

Results (`out/myo_tt_spin_metrics.json`; P2 seeds 2000000-2000099, never used
in tuning; Wilson 95% intervals; every row on the same serves):

| P2 variant | success | hit |
| --- | --- | --- |
| previous P2 controller (`params/myo_tt_p2.txt`) | 11% [6, 19] | 44% [35, 54] |
| spin + stroke families (`params/myo_tt_spin.txt`, sep-CMA on fresh serves) | 9% [5, 16] | 40% [31, 50] |
| the same with the simulator's true spin (oracle) | 9% [5, 16] | 40% [31, 50] |
| robust aim target (`params/myo_tt_robust_aim.txt`) | 12% [7, 20] | 46% [37, 56] |

The spin estimate is off by 0.0006 rad/s against a true 0.024 rad/s, and
perfect spin knowledge changes no episode. The chooser picks `block` (26
serves) or `give` (44); on the give serves the stroke's own motion costs
pad height (pad below the ball 25 against 20 for the previous controller on
the same serves). Neither variant beat the champion in the arena (`tt_p2`:
9% and 8% against 8%, p 0.49 and 0.76). P1 stays at 100% [96, 100] (100
seeds). With real-ball coefficients (`spin_c 75`, `spin_k`/`spin_ks`/`mu_t`
0.4) and a spinning opponent serve, the same controller closes its face by
about 13 degrees and gives against topspin, and opens it by about 15 and
brushes over against backspin.

### Table tennis: execution (round 3)

P2 fails on execution, not on the plan. On the arena's serves (`tt_p2`,
97000-97099) the previous champion missed below the ball 31 times, hit out
25, and its backhand could not reach 18 far-left serves. The dominant cause
is the pelvis slide: the 139 kg pelvis starts at 18-20 m/s^2 (actuator
limited, 1.8 m/s top speed), which asks 420-500 N m of the spine's lateral
bend for ~0.1 s; the trunk muscles can give at most ~315 N m, so the trunk
bends 0.28 rad, the right shoulder drops 14 cm and the arm hanging off the
tilted thorax drops the pad another ~20 cm, with the shoulder abductors
saturated. Forehand serves that need a long left slide fail below the ball
22 times in 23.

Five execution approaches were champion-challenged (`out/myo_tt_r3_metrics.json`):

| `tt_p2` challenger (100 serves, paired against the champion's 8%) | solved | diff, p |
| --- | --- | --- |
| 1 inverse-dynamics feed-forward (`id_mode 1`, `id_alloc 1`) | 4% | -0.04, 0.97 |
| 2 min-jerk pelvis slide timed on the ball (`pel_mj 1`) | 12% | +0.04, 0.14 |
| 2 + 3 backhand posture re-practised on far-left serves | 13% | +0.05, 0.09 |
| 2 + 3 + height corrections through the elbow (`lam`, `reg_sh`) | 5% | -0.03, 0.91 |
| 2 + 3 + 4/5 forehand aim and servo re-practised | 7% | -0.01, 0.70 |
| **2 + 3 + 5 backhand posture and aim gains, second round** (`params/myo_tt_p2_r3_bh2.txt`) | **16%** | **+0.08, 0.021: champion** |

- **Inverse dynamics** (`id_mode`): the bridge's opt-in `coupling_joints`
  sends each slide joint's mass-matrix column (`mcol_pelvis_x`,
  `mcol_pelvis_y`) and its measured acceleration (`cacc`); the skill turns
  `M[j, pelvis] a_pelvis` (the acceleration the pelvis command about to be
  sent will produce) into drive through `Controller#set_feedforward_torque`,
  split per joint like the bias, or with `set_feedforward_allocation`
  solved jointly over the coupled spine and shoulder (equality-slaved
  joints folded onto their masters, nonnegative minimum-norm activations).
  Applied as exact joint torques (an oracle, `qfrc_applied`) it keeps the
  trunk within 0.05 rad and halves the height miss; through the muscles it
  changes the trunk bend by under 0.01 rad, because the torque exceeds what
  the trunk muscles have and arrives through 15-50 ms of activation. It is
  not worth making standard for skills whose base accelerates this hard; the
  plumbing is general (any body, any driving joint) and cheap.
- **Min-jerk slide**: lower peak acceleration (trunk bend 0.13-0.21 rad) and
  the backhand reaches the far-left serves (lateral misses 18 -> 2); medium
  forehand slides arrive 5-6 cm left instead (lateral misses 1 -> 12).
  Gating it (`pel_vmax`, `pel_mj_min`) or arriving earlier (`slide_margin`)
  was worse on fresh serves.
- **Backhand**: its face came in ~30 degrees off the aim law's normal; the
  backhand servo gains did not fix it, re-practising its posture with a
  dense face-angle term did.
- **Practice signal**: serves pre-classified by side (`TT_ENV=P2`, the
  predicted crossing), fresh serves per generation, and a shaped score:
  10 solved + 2 hit - 0.1 x the face's angle to the aim law (degrees) - 5 x
  the miss distance - the landing error. On the backhand it lifted held-out
  success from 0% to 13-20%; on the forehand (aim, impact model, target box,
  elbow share) the held-out gain (8% -> 20% on 40 serves) did not survive
  the arena.

| failures on `tt_p2` serves | before | after |
| --- | --- | --- |
| forehand solved / below / out / lateral | 8 / 31 / 25 / 1 | 12 / 33 / 12 / 12 |
| backhand solved / lateral / out / below | 0 / 18 / 9 / 0 | 4 / 2 / 15 / 6 |

On 100 fresh serves (600000-600099) the new champion solves 20% against the
old one's 10%; `tt_p1` stays 100% (its own params, same binary). The new P2
params play the P1 serve worse than the old ones (4/50 against 35/50: the
min-jerk slide). The MyoChallenge 2025 P2 winner scored 64%.

```sh
./build.sh myo_tt_v4    # round-3 development build (bin/robolab_myo_tt keeps the old one)
TT_ENV=P2 ROBOLAB_CONTROLLER=$PWD/bin/champions/tt_p2-20260927-120626 .venv-myo/bin/python playground/tasks/myo_tt.py \
  --params params/myo_tt_p2_r3_bh2.txt --render 4 --seeds 97011,97083,97001,97039 --video out/myo_tt_r3.mp4
```

### Table tennis: forehand height and backhand depth (round 4)

Round 3 left the forehand missing below the ball on long left slides and the
backhand returning long. A time series of one such serve shows where the
height goes: the slide saturates at the actuator's ~2.2 m/s and then brakes
at +31 m/s^2 in the 0.1 s before contact. During the acceleration the arm is
flung up and the adductors are stretch-reflexed (activation 0.33); the
braking then drops the shoulder's elevation from 0.76 to 0.15 rad and swings
the plane of elevation 0.6 rad past ready, though the abductors still have
headroom (group mean 0.2-0.3; only the trunk's left side-benders saturate,
at 0.9). The same swing carries the pad 10 cm past the ball on medium slides
(the lateral misses): the slide's goal chases the pad's measured offset from
the pelvis, which swings between 0.54 and 0.78 m.

| `tt_p2` challenger (100 serves, paired) | solved | diff, p |
| --- | --- | --- |
| b anticipatory trunk lean into the slide (`k_lean` -0.15, `k_apa` 0.02) | 9% | -0.07, 0.98 against 16% |
| **a+d forehand fly-by slide + 3 cm lateral trim** (`params/myo_tt_p2_r4_fly.txt`) | **25%** | **+0.09, 0.044: champion** |
| c + sag-model height match (`params/myo_tt_p2_r4_sag.txt`) | 29% | +0.04, 0.060 against 25% |
| c + f side routing (`y_switch` 0.1; `params/myo_tt_p2_r4_route.txt`) | 29% | +0.04, 0.058 against 25% |

- **Fly-by slide** (`pel_fly`): the forehand's lateral slide is a
  minimum-jerk path that reaches its goal at contact still moving (at
  `pel_fly` times the average speed the rest of it needs: the initial jerk
  60 d / T^3 - (36 v + 24 v_f) / T^2 - 9 a / T), coasts through the last
  50 ms and brakes only after the ball has gone. Its reference is held to
  `pel_vcap` (a reference that outruns the actuator reaches the goal first,
  and the servo then brakes the lagging pelvis just before contact), and
  `y_trim` moves the goal 3 cm right (the pad sat ~5 cm left of the ball even
  on short slides). Lateral misses 12 -> 0, hits 45 -> 65. On the backhand it
  hurts (fresh backhand solved 11 -> 6), so it is forehand-only
  (`bh_pel_fly` is the backhand's own factor, 0).
- **Sag model** (`hx_sag`, `hx_s0`): with the braking gone, what is left of
  the height miss is the trunk's side bend at contact (up to 0.19 rad, pad
  27-33 cm low). The pelvis's fore-aft height matching now aims at the
  height the pad will have: 0.3 m lower per m of planned left slide beyond
  0.3 m, so the ball is met earlier on its rise. Forehand below-the-ball
  23 -> 11; most of the rescued hits then land long, with the face ~7
  degrees more open than the aim law's.
- **Side routing** (`y_switch` 0.1): forehands whose ball crosses at y in
  [-0.4, 0) were solved 0/29 on fresh serves (the long left slides), while
  the backhand, which needs almost no slide there, hits them. Forehand
  below-the-ball 23 -> 6, but the backhand returns them long.
- **Trunk lean** (b) trades below-the-ball misses for lateral and out ones:
  the left side-benders are already saturated during long slides.

On 200 fresh serves (600000-600199): round-3 champion 37, fly-by 53
(p 0.014), + sag model 56, + routing 58 (29%; p 0.002 against round 3, 0.093
against the fly-by). Sag and routing gain on both serve sets but not enough
on the arena's 100 to clear p < 0.05; `tt_p1` stays 100%.

| failures on `tt_p2` serves | round 3 | round 4 champion |
| --- | --- | --- |
| forehand solved / below / out / lateral | 12 / 33 / 12 / 12 | 20 / 23 / 21 / 0 |
| backhand solved / out / below / lateral | 4 / 15 / 6 / 2 | 5 / 11 / 8 / 3 |

**The backhand.** The backhand's servo Jacobians (`jv_bh`, `jw_bh`) were
taken at the round-1 backhand posture; the round-3 posture is far from it
(several columns change sign), which is why no backhand servo gain ever
helped. The task now sends the hand's Jacobians at the observed posture
every step (`hand_jac`: forward kinematics of the model, the joint
equalities folded in; checked against finite differences), and `jac_live`
uses them instead of the constants. With them the backhand servo works on
the arena's 51 routed backhand serves (8 -> 10) but not on fresh serves
(16 -> 9). The deeper cause: the arm swings across at 4-5 m/s toward a
posture it never reaches (plane of elevation 0.28 at contact against a
target of -1.34), so the face at contact depends on when the ball arrives
(correlation -0.38 with contact time; contacts at 0.44-0.48 s find it 11
degrees open and solve 0/13, at 0.52-0.56 s 36%). None of four fixes held
up: a give (`bh_dd_push`, `bh_dt_swing`: 5 against 8 of 51), targets at the
angles actually reached at contact (0-3 of 51: it sags below the ball), a
swing timed on each serve (`bh_tdur`: 5 and 8 against 13 of 120) and later,
higher contact (`bh_dz_hit`, `bh_dx_hi`: 2 and 0 of 120). The backhand needs
its posture, swing timing and servo re-practised together, now with correct
Jacobians. The MyoChallenge 2025 P2 winner scored 64%.

```sh
./build.sh myo_tt_v5    # round-4 development build (every round-4 option opt-in)
TT_ENV=P2 ROBOLAB_CONTROLLER=$PWD/bin/champions/tt_p2-20260927-132854 .venv-myo/bin/python playground/tasks/myo_tt.py \
  --params params/myo_tt_p2_r4_fly.txt --render 4 --seeds 97081,97038,97045,97012 --video out/myo_tt_r4.mp4
```

### Table tennis: the backhand, a flick and real spin (round 5)

The backhand plays 55% of P2 serves (those crossing left of y 0.1) and solved
15% of them against the forehand's 46% (fresh serves 600000-600199). A new
trial, `tt_p2_backhand`, holds only backhand serves: the 131 of seeds
99000-99259 that the champion's side rule sends to the backhand. On the other
129 seeds of that block the champion's forehand solves 36%. A working backhand
should reach that.

**Why the backhand fails.** Joint time series, muscle activations and the
pad's state at contact show four things.
- The backhand posture is out of reach. The commanded plane of elevation is
  -1.34 and the arm gets to 0.25; the commanded rotation is 1.33 and it gets
  to 0.6. From 0.35 s the posterior deltoid, supraspinatus, subscapularis,
  teres major, pectoralis and latissimus sit at full activation, and so do the
  forearm's flexors and pronators from 0.2 s. The arm ends where the maximal
  forces balance. Neither the servo nor a wrist snap has any activation left
  to work with.
- The face is still turning at contact: 130-160 deg/s over the last 40 ms
  (forehand 90-107). Its error to the aim law is 5 deg in yaw and 10 in pitch
  (forehand 2 and 7). Commanding reachable angles does not help: the arm
  arrives 0.2-0.3 s late. For example, a commanded rotation of 0.63 reaches
  0.23 at contact.
- The paddle turns in the grip on both sides. Measured in the palm's frame
  from 0.25 s to contact, the median turn is 20-24 deg, and a few backhands
  turn 140-180 deg.
- The impact model is not the problem. With the face and pad velocity
  actually at contact it predicts the return: velocity error std 0.5 m/s on
  the forehand, against 1.05 m/s when the aim law assumes a still pad. The
  backhand misses because its face is wrong.

The approaches below were screened on 60 held-out pool backhands (champion
22%), then entered in the arena.

| backhand approach | held-out | `tt_p2_backhand` (131, paired against 13.0%) |
| --- | --- | --- |
| **A** backhand re-practised jointly with live Jacobians (`jac_live` 2): posture, swing time, reflex gain, servo gains and start, slide offset (sep-CMA, 15 parameters, shaped score) | 18% | **19.1%, +0.061, p 0.092** |
| **A2** the same, practised again from A (sigma 0.03, 14 serves per generation) | 27% (other 60) | **22.9%, +0.099, p 0.018: champion** |
| B settled block: postural tone (`bh_ki`), pulse-step swing (`bh_ps`), reachable posture, coached Gauss-Newton fit of the posture to the aim, lower co-contraction and gain (`bh_stiff`, `bh_gain`) | 0-10% | not entered |
| B' contact-timed swing: the swing starts 0.55 s before contact (`bh_lead`) | 13% of 30 | 6.1%, -0.069, p 1.0 |
| B'' learned serve map for the backhand (`lff_side` 2, Gauss-Newton over 30 weights) | cost not reduced | not entered |
| C backhand topspin flick (see below) | 20% (always on) | 12.2%, -0.008, p 1.0 |

Approach A is the round-5 champion:
- `tt_p2_300`: 33.0% against 26.7% (+0.063, p 0.001).
- `tt_p2`: 36% against 25% (+0.11, p 0.007).
- Fresh serves 600000-600199: 65 of 200, against 58.
- `tt_p1` stays 100%.

What changed is mostly the servo. With the Jacobians taken at the observed
posture, moderate integral gains help the backhand: `bh_k_z` 2.3, `bh_k_n` 3.7,
servo from 0.27 s. The posture moved little.

A2 (`params/myo_tt_p2_r5_bhprac2.txt`) is the `tt_p2_backhand` champion.
Against A it gains on the backhand and loses a little overall:

| A2 against A | A2 | A | diff, p |
| --- | --- | --- | --- |
| `tt_p2_backhand` | 22.9% | 19.1% | not paired |
| `tt_p2_300` | 32.0% | 33.0% | -0.010, p 0.77 |
| `tt_p2` | 31% | 36% | -0.05, p 0.97 |
| fresh serves 600000-600199 | 69 | 65 | not paired |

On fresh backhands A2 returns long less often (out 49 -> 32). Its face turns
less at contact (158 -> 106 deg/s median) and its yaw error falls from 5.0 to
3.7 deg. It misses below the ball more often (15 -> 22).

| fresh serves 600000-600199 | round 4 | round 5 (A) | A2 |
| --- | --- | --- | --- |
| backhand solved / hit / out / below / lateral (of 109) | 16 / 81 / 56 / 21 / 6 | 23 / 83 / 49 / 15 / 7 | 27 / 78 / 32 / 22 / 9 |
| forehand solved / out / below (of 91) | 42 / 23 / 9 | 42 / 23 / 9 | 42 / 23 / 9 |

**The working-backhand bar is not met.** The backhand solves 21-25% (23% on
`tt_p2_backhand`), against 36-46% for the forehand; its face still turns at
contact and it still returns long. The problem sits in the arm's actuation, not in the plan. The
backhand's targets must become reachable and unsaturated (with the arm's reflex gain,
the co-contraction term `stiff` 0.11 alone asks about 1.4 activation of the
elbow and wrist muscles), and
its posture, swing and servo must then be practised again in that regime.
The coached fit in that regime (`bh_stiff` 0.02, `bh_gain` 0.6) raised the
hit rate from 1 to 10 of 12 serves, but it has solved none yet.

**The flick** (family 5, backhand only; `flick_mode`, `fl_*`):
- **What it is.** The arm sets the pad at the contact point. A late wrist snap
  then fires `fl_t` + `t_lead` before the predicted contact: forearm rotation,
  wrist deviation and flexion only, brushing up and over at 52 deg. It is a
  via keyframe at the contact pose, then a follow-through.
- **When it is chosen.** While the aim law's untrimmed face, at the flick's
  speed, lands with at least `fl_margin` to spare, net clearance included.
  The margin is judged on the untrimmed face because the pitch trims made
  every margin -0.7 to -2.5 m.
- **Usage and result.** It was chosen on 44% of the trial's backhands and
  solved 10 of them, against 11 without it.
- **Why it does nothing.** Return speed is 5.41 m/s against 5.45. Even a
  stronger snap (0.5 m, burst 0.8, fired 0.13 s early) raises the pad's
  speed at contact only from 0.85 to 0.92 m/s. The forearm muscles are
  already at full activation.

**Real spin (`TT_REAL_SPIN=1`, `tt_p2_realspin`; not the challenge).** The
official env hardly spins the ball, so this variant makes spin real:
- **Ball physics.** The ball gets the thin shell's inertia, drag
  (Cd 0.5, rho 1.2) and Magnus force (C 0.3), all applied every physics
  substep.
- **Contact friction.** Our own Coulomb contact friction: table 0.25, rubber
  0.8. MuJoCo's soft friction rows do not spin the ball.
- **Observation.** A world-frame `ball_vel` observation, because the
  velocimeter turns with a spinning ball.
- **What this does to the serve.** The table bounce now gives +90 to +110
  rad/s of topspin and takes about 40% off the ball's horizontal speed.
- **Result.** The champion solves 0 of 100 (64% hit). Every return leaves at
  about 2 m/s with 20-70 rad/s of backspin and lands on our own half.

On 20 serves per stroke:

| stroke (realistic variant, spin out: + top / - back) | forehand | backhand |
| --- | --- | --- |
| single stroke (champion) | -27 rad/s, 2.0 m/s | -19, 1.8 |
| near-vertical chop, pad moving down (`chop_down` 1.3) | -40, 2.0 | -22, 1.8 |
| topspin flick | - | -3, 1.7 |
| over (topspin drive) | -6, 1.8 | -24, 1.9 |
| low scoop (`scoop_mode`) | -43, 2.1 | - |
| chooser (families + spin estimate, real-ball coefficients) | picks over every time | picks over every time |

The strokes shift the spin in the right direction:
- The chop adds backspin.
- The flick and the over drive take backspin off.
- Against the bounce's +100 rad/s topspin the chooser closes the face with
  "over", which is the textbook answer.

None of them makes real pace, and none lands. The strokes reach only
0.7-0.9 m/s of pad speed at contact. The skill's flight model has no drag, and
it assumes the bounce keeps 99.6% of the horizontal speed.

**Forehand depth.** Two options were screened on 60 forehand serves, against
25 solved for the champion:
- the measured pad velocity in the aim law (`k_vpm` 1): 23;
- live forehand Jacobians (`jac_live` 1): 23.

The forehand's long returns remain open.

```sh
./build.sh myo_tt_v6    # round-5 development build (every round-5 option opt-in)
.venv-myo/bin/python playground/arena.py eval tt_p2_backhand --params params/myo_tt_p2_r5_bhprac.txt --controller bin/challengers/myo_tt_r5-a
TT_ENV=P2 ROBOLAB_CONTROLLER=$PWD/bin/champions/tt_p2_300-20260927-194659 .venv-myo/bin/python playground/tasks/myo_tt.py \
  --params params/myo_tt_p2_r5_bhprac.txt --render 5 --seeds 98045,98046,98047,98048,98049 --video out/myo_tt_r5.mp4
```

Videos:
- `out/myo_tt_r5.mp4`: five consecutive solved serves by the round-5
  champion.
- `out/myo_tt_backhand.mp4`: four backhands in the broadcast view, two from
  the side, one at the hand.
- `out/myo_tt_flick.mp4`: three flicks and one at the hand.
- `out/myo_tt_strokes.mp4`: the chop on both sides, the flick and the scoop
  under real spin (re-rendered in round 6: the power strokes at the angle
  sweeps' best settings).

Each has a gif under 6 MB.

### Table tennis: the backhand's mechanics, power strokes and angle sweeps (round 6)

`skills/myo_tt_v7.w` (`MyoTTV7Skill < MyoTTSkill`, entry `lib/entry/myo_tt_v7.w`) adds the round-6
options, each off by default. With every option off it plays the round-5 champions serve for serve (60 of
60 P2 serves identical: contact time, landing, pad normal, joint angles; P1 20 of 20).

**Where P2 still fails.** The `tt_p2_300` champion on all 300 serves (99 solved, 33.0%):

| cause (primary) | forehand (156) | backhand (144) | all |
| --- | --- | --- | --- |
| solved | 60 (38%) | 39 (27%) | 99 (33.0%) |
| hit, face more than 8 deg off the aim law's | 33 | 60 | 93 (31%) |
| missed below the ball | 17 | 14 (+2 with the trunk bent) | 33 (11%) |
| hit, face on the aim, return long | 13 | 13 | 26 (9%) |
| hit, face on the aim, return on our own half | 13 | 0 | 13 (4%) |
| hit, face on the aim, return wide | 11 | 2 | 13 (4%) |
| missed out of reach (lateral) | 0 | 7 | 7 (2%) |
| missed within 10 cm (timing) | 5 | 2 | 7 (2%) |
| other | 4 | 5 | 9 (3%) |

The paddle's turn in the grip is never the primary cause (no hit with the face turned more than 45 deg in
the palm). Being on the aim law's face is not enough either: of the forehand hits within 4 deg of it, 57%
solve; of the backhand hits 8-12 deg off it, 60% (the aim law's own model misses by as much as the face does).

**The grip.** Measured in the palm's frame from 0.25 s to contact, the paddle turns 18-21 deg (median) on
both sides, but mostly about the blade's own normal (the handle pivots in the palm within the blade's
plane, under gravity): the face itself turns 12-16 deg, the forehand's as much as the backhand's. Over the
last 40 ms the face turns 85-126 deg/s, about two thirds of it the palm (the arm), a third the grip.
- Squeezing harder turns the paddle further, because the curling fingers roll the handle: a squeeze
  from 0.15 s before contact (`gsq`) took the turn from 19 to 29 deg and solved 1 of 36 backhands against
  5; from the start of the serve, 34 deg and 0 of 36.
- Holding the finger posture (`glk`, thresholds locked at the measured contractions) or moving the
  grip's thresholds with the arm (`gcp`, the geometry's length tables) did not reduce it (21-30 and 20 deg).
- The finger flexors cross the wrist, and at 0.9 activation they pull it into flexion with ~20 N m, several
  times what the wrist extensors can answer. So the grip flexes the wrist; the flexed wrist slackens the
  flexors below their thresholds (activation 0.9 at 0.15 s, 0.35 at contact); the grip weakens and the
  paddle hangs. In a held, settled backhand (below) this loop lets the paddle swing out of the hand
  (84-108 deg, the paddle dropped).

**Reachable backhand postures.** `playground/myo_tt_posture.py`: the pad's pose from
the model's kinematics with the grasp measured at contact, the minimum-norm activations that hold a
posture still against gravity and the stretched muscles' passive pull, and the upper arm's and forearm's
clearance from the thorax (the model's contact pairs). The passive pull dominates: at the round-5
backhand's contact posture it asks 11.8 N m of internal rotation and 9.8 N m of elbow flexion, against 2.6 N m
of gravity. The optimizer finds postures that put the pad at the contact point with the aim's face for a
sum of squared activations of 0.07-0.3 (the round-5 contact posture: 1.5). With low co-contraction
(`bh_stiff` 0.02) and those activations as a static drive (`b7_sff`, `b7_a*`) the arm reaches them by
0.3 s and holds still (palm turning 73-94 deg/s at contact against 98-121), but:
- internally rotated postures collapse into the chest (the humerus on the thorax at 65-160 N): the
  internal rotators (SUBSC, PECM, LAT, TMAJ) also adduct;
- the forearm settles 0.3-0.5 rad supinated of its command (the biceps holding the elbow supinate; past
  ~0.3 rad of pronation the pronators give 2.8 N m against 7.6 N m of supination);
- the wrist drifts into flexion (the grip's torque), and the paddle is lost (see the grip);
- the trunk turns only 0.05-0.15 rad by 0.45 s.
Every settled posture tried played 0-1 of 36 backhands.

**The aim hardly moves the backhand's face.** Trims of the backhand's aim (pitch `bh_dnz` +-0.08,
an expected pad velocity `bh_vpe`) changed 0-2 of 96 backhands: the face at contact is set by where the
swing is when the ball arrives. On the trial's backhands, hits at 0.55-0.62 s solve 20 of 34, at
0.44-0.52 s 5 of 36 (fast serves met low, the pad still swinging, the return 2-3 m/s too steep).

| backhand approach (dev: fresh pool backhands) | result |
| --- | --- |
| grip squeeze / lock / follow (`gsq`, `glk`, `gcp`) | 0-3 of 36 against 5 |
| lower co-contraction alone (`bh_stiff` 0.06, 0.03) | 5, 2 of 36 (more below the ball) |
| reachable settled postures + static drive + postural integral | 0-1 of 36 (paddle lost) |
| serve-timed swing (`bh_tdur` 0.12) | 6 of 96 against 22 |
| contact no earlier than 0.53 s (`bh_tmin`, `bh_tx`) | 22 of 96 (the 0.49-0.52 s bin 5/26 against 0/15; more below) |
| practice: headroom dims (co-contraction, static drive, transfer bursts; 21 params) | held-out 2% at gen 4 (stopped) |
| practice: per-serve posture slopes on contact time (`bh_tk`; 12 params) | held-out 10% at gen 4 (stopped) |
| **practice D**: posture, servo, `bh_tmin`, `bh_tx`, `bh_dnz` (16 params, sigma 0.03) | held-out 30.0% against 31.7%; `tt_p2_backhand` **24.4% against 22.9%, +0.015, p 0.39** (not promoted) |

| `tt_p2_backhand` (131) | solved | hit | out | below | lateral | own | net | grip turn | face turn, last 40 ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| round-5 champion (A2) | 30 | 91 | 43 | 26 | 13 | 13 | 5 | 19.8 deg | 85 deg/s |
| round-6 practice D | 32 | 100 | 48 | 19 | 11 | 13 | 7 | 20.8 deg | 118 deg/s |

**The working-backhand bar is not met** (24% against the forehand's 36-46%). What blocks it is the
arm's mechanics, not the plan: a backhand the arm can hold still drops the paddle, and the swinging
backhand that keeps the paddle sets its face by timing.

**Power strokes (`pw`, realistic variant).** A burst on the stroke's prime movers from its firing
(`pw_a` 1 for `pw_t` 0.12 s, full at a contraction change of `pw_sc` 0.01), the antagonists inhibited
(`pw_inh` 1) with their reflex gain at `pw_g` 0.1 (`pw_all` 1: the whole arm's, the flick's choice); the
arm keeps its other reflexes, which hold it up (lowering every gain dropped the arm: the scoop's pad
moved down). On 20 serves (99700-99719):

| stroke | pad speed at contact (round 5 -> 6) | spin out (rad/s) | return |
| --- | --- | --- | --- |
| forehand chop | 0.68 -> 2.74 m/s (max 3.3) | -36 -> -55 | 1.9 -> 3.1 m/s |
| backhand chop | 1.14 -> 2.56 m/s (max 2.8) | -22 -> -75 | 2.3 -> 4.5 m/s |
| backhand flick (`pw_all` 1) | 1.20 -> 1.41 m/s (max 1.9) | -10 -> **+31 (topspin)** | 2.1 -> 1.8 m/s |
| forehand scoop, up and forward (`sc_fwd`) | 0.69 -> 3.45 m/s | -45 -> -149 (with the aim law's open face: a push) | 2.2 -> 6.9 m/s |

On `tt_p2_realspin` the power chop on both sides hits 23% (the champion 64%) and lands none (0%, the
champion 0%); its returns leave at 4.3 m/s (2.1) with -42 rad/s.

**Angle sweeps.** `fc_open` fixes the face's opening in place of the aim law's pitch (+ open, - closed; the
aim law keeps the yaw), per stroke `ch_open`, `fl_open`, `sc_open`, per side `fh_open`, `bh_open`; the
path is the family's own (`chop_down`, `fl_a`, `sc_a` with `sc_fwd`); `ap_on`/`ap_dz` meet the ball a set
distance below its bounce's apex (not swept). Every stroke with power, the same serves in every cell
(realistic variant: 30 serves 99700-99729 for the chop and the blocks, 20 pool backhands for the flick,
20 pool forehands for the scoop). The commanded angles are not what the arm reaches: the tables give the
face and path reached at contact (medians over hits), apex above the table top, net clearance (ball bottom
over the net), spin (+ top).

| chop | face / path commanded | face / path reached | landed | net clearance | apex | spin | return |
| --- | --- | --- | --- | --- | --- | --- | --- |
| forehand | aim law / 40 down | +38 / -39 | 1 of 19 | 0.04 m | 0.48 m | -21 rev/s | 3.5 m/s |
| forehand | aim law / 60 down | +44 / -38 | 1 | 0.18 | 0.48 | -18 | 3.7 |
| forehand | 0 / 40 | -26 / -5 | 0 | into the net | 0.06 | +9 | 5.7 |
| forehand | 20 / 40 | +2 / -41 | 1 | 0.18 | 0.40 | -3 | 2.7 |
| forehand | 50 / 60 | +46 / -30 | 2 | 0.26 | 0.45 | -18 | 4.7 |
| backhand | aim law / 40 | -6 / -39 | 0 of 11 | - | 0.44 | -11 | 5.9 |
| backhand | **60 / 40** | **-4 / -33** | **3** | **0.04** | 0.43 | **-11** | 5.9 |
| backhand | 50 / 60 | -9 / -38 | 2 | 0.07 | 0.42 | -11 | 6.1 |

Why the chop went high:
- The aim law opens the forehand's face to ~40 deg: it models a still pad and a spinless ball, and expects
  0.9 m/s of pad against the 2.5-3 m/s reached. Telling it the reached speed (`k_ach` 1-2) did not help
  (0-1 of 19).
- The forehand's path never gets steeper than ~40 deg down (commanded 60-80, reached 38-50), so the pad's
  descent cannot cancel what the open face lifts.
- Closing the face below ~+5 deg sends the ball into the net (apex under 0.1 m), and the spin flips to
  topspin: the incoming +100 rad/s topspin wins.
- The returns that clear leave near the contact height (apex 0.40-0.48 m above the table is the contact
  point itself). The best backhand chop keeps the ball low with backspin: 4 cm over the net at -11 rev/s,
  3 of 11 landed. The forehand's best clears by 26 cm.

| flick (backhand, 20 serves) | face reached | path reached | landed | spin | return |
| --- | --- | --- | --- | --- | --- |
| aim law, path 20 / 45 / 70 up | -14 / -9 / -2 | +28 / +49 / +64 | 0 | +1.3 / -0.5 / -2.4 rev/s | 3.0-3.2 m/s |
| face vertical (cmd), path 20 up | -16 | +18 | 0 | **+4.6** | 3.3 |
| face 20 closed (cmd), path 45 up | -20 | +28 | 0 | +1.9 | 2.3 |

| scoop (forehand, 20 serves) | face reached | path reached | landed | spin | return |
| --- | --- | --- | --- | --- | --- |
| aim law, path 45 up (cmd) | +21 | -30 | 2 | -16 rev/s | 5.0 m/s |
| aim law, path 70 up | +25 | +28 | 1 (17 hits) | -9 | 6.6 |
| 15 closed, path 70 up | -13 | -33 | 1 | **+12** | 6.0 |
| 60-75 open, path 70 up | +40 to +46 | +106 to +109 (up and back) | 0 | +5 to +6 | 2.3-2.6 |

- The flick's topspin stays small (under 5 rev/s) because its pad reaches only 1.3-1.5 m/s: the
  wrist-only snap has little muscle behind it.
- The scoop brushes topspin only with its face closed (the pad meets the ball's upper back) or on a
  near-vertical path up and back. With the aim law's open face it is a push, and backspin.

The blocks, face fixed from 10 closed to 10 open against the aim law:
- Realistic variant: nothing lands in any cell (returns 1.7-2.6 m/s).
- Official env, 30 serves: the forehand solves 4-8 of 19 against 5, the backhand 5 of 11 against 6. The
  backhand's reached face stays within -1.5 to +1 deg, whatever is commanded.
- On 96 fresh forehands the vertical face (reached +7 deg against the aim law's +10) solves 36 against 31
  (+0.052, p 0.20). On `tt_p2_300` (`fh_open` 0): **34.3% against 33.0%, +0.013, p 0.29**, not promoted.

`st_best 1` makes the sweeps' best settings the strokes' defaults: the chop's face 60 open on a path 40
down, the flick's face vertical on a path 20 up, and the scoop up and forward at 70 with its face 15
closed (its topspin variant). `out/myo_tt_strokes.mp4` (re-rendered; gif 2.5 MB) shows the backhand and
forehand power chops at those angles (both land, -88 and -62 rad/s), the flick (+124 rad/s) and the
scoop (+136 rad/s). The last two do not land.

**Toward 90% on P2.** The largest failure class is the face at contact, 31% of all serves (60 of the
backhand's 144). For the backhand this report shows why:
- the aim does not move its face;
- a still, reachable backhand loses the paddle;
- the swinging backhand sets the face by its timing.
Next on the forehand is its misses below the ball (11%), then the aim law's own error with the face on
target (long, own half, wide: 17%). A learned residual on the aim law would need the face to follow the
aim; on the backhand it does not.

```sh
./build.sh myo_tt_v7
.venv-myo/bin/python playground/arena.py eval tt_p2_backhand --params params/myo_tt_p2_r6_bhD.txt --controller bin/challengers/myo_tt_r6-a
TT_ENV=P2 ROBOLAB_CONTROLLER=$PWD/bin/challengers/myo_tt_r6-a .venv-myo/bin/python playground/tasks/myo_tt.py \
  --params params/myo_tt_p2_r6_bhD.txt --render 5 --seeds 99091,99092,99094,99105,99107 --video out/myo_tt_r6_backhand.mp4
```

`out/myo_tt_r6_backhand.mp4` (gif 3.2 MB): five solved `tt_p2_backhand` serves by the round-6 backhand.

### Table tennis: a learned contact model, side choice and the backhand's grasp (round 7)

`skills/myo_tt_v8.w` (`MyoTTV8Skill < MyoTTV7Skill`, entry `lib/entry/myo_tt_v8.w`) adds the round-7
options, each off by default. With every option off it plays the round-5 champion serve for serve (20 of 20
P2 serves identical). At the servo's lock it now emits `l8:` for training fits. The fields: side, the aim law's
target, the plan, the pad plane's x, the pad's and the aim's normals, and the learned outputs. Every fit
below used training serves from the practice pool only (400, `train`). Every screen used 200 other pool serves
(`val`). The arena trials served only as judges.

**The aim law's impact model is not what fails.** With the face and pad velocity actually reached at contact,
the aim law's own model (restitution 1, no tangential loss) predicts the return to 0.6 / 0.24 / 0.43 m/s
(x, y, z std). A still pad, as the aim law assumes, doubles the x error (1.14). What goes wrong is elsewhere:
- **Rim hits.** 12-20% of hits are rim hits: the ball meets the pad 9 cm or more from its centre (pad
  radius 9.3 cm) and carries on past it. All of them fail.
- **The forehand's pitch barely follows its aim.** With the serve's features held, the reached face moves
  0.37-0.42 of an aimed pitch change (yaw 0.8-1.0). Doubling the servo's pitch gains leaves this at 0.42.
  The forehand's wrist sits at its extension limit.
- **The reached face is set by the serve.** The serve's features predict it to R^2 0.81 (forehand
  pitch, training).
- **Learned corrections to the aim do not help.** Per side, linear maps of the serve's features (`lm`)
  were fitted: the pad velocity to expect at contact and a trim cancelling the face's predictable error.
  - 200 val serves: 51 solved, against 58.
  - A trim-only overdrive (x 2.5), forehands: 39 of 113, against 43.
  - The trims are not carried out: the reached face moved 0.147 std against the untrimmed aim, 0.161 before.

**Contact centring.** How far from the pad's centre the ball is met decides most forehand outcomes. On one
val run (`z_bias` -0.05):

| forehand hits, offset from the pad's centre | hits | solved |
| --- | --- | --- |
| under 3 cm | 30 | 20 (67%) |
| 3-6 cm | 32 | 14 (44%) |
| 6-9 cm | 26 | 8 (31%) |
| 9 cm or more (rim) | 7 | 1 |

The ball met the pad 2.3 cm above its centre on average. Raising the pad's height target (`z_bias` from
-0.0735):

| `z_bias` | -0.0735 (champion) | -0.05 | -0.03 | -0.02 | -0.01 |
| --- | --- | --- | --- | --- | --- |
| val solved (of 200) | 58 | 66 | **69** | 62 | 68 |

- Training serves: 119 solved of 400 at -0.0735, 139 at -0.03.
- Arena, `z_bias` -0.03 (`params/myo_tt_p2_r7_zb.txt`): **`tt_p2_300` 35.7% against 33.0% (+0.027, p 0.15)**,
  and `tt_p2` 27% against 36% (-0.09, p 0.99). Not promoted.

A learned centring (`lc`) fits, per side, the ball's offset on the pad from the serve's features (DAgger).
- **Lateral:** it halves the forehand's lateral offset (std 2.7 -> 1.4 cm).
- **Height:** the height offset is hardly predictable (5.4 -> 4.9 cm). It follows the trunk's
  flexion at contact (r -0.48).
- **Results:** 72 of 200 val serves (+3 on `z_bias` -0.03, p 0.34), but 136 of 400 training serves
  (against 139). The second round scored 65 of 200.

Any change flips 15-25% of serves both ways, so single 200-serve screens differ by +-5 points from noise.

**Side choice.** Each training serve was also played on the side the side rule did not pick:
- Forehand on the backhand's 194 serves: 6 solved, 124 out of reach.
- Backhand on the forehand's 206: 7 solved.
- An oracle choosing the better side per serve gains 9 of 400 (2.3 points). Half of those sit
  within 0.1 m of the switch (crossing y in [0, 0.1): forehand 5, backhand 3). A learned side classifier
  (`sd`) cannot gain more than that, so I did not fit one.

**The backhand's grasp** (96 pool backhands; the champion solves 19):

| variant | solved | face turn, last 40 ms | grip turn |
| --- | --- | --- | --- |
| champion | 19 | 163 deg/s | 22 deg |
| lower steady finger drive (`bh_grip_drive` 0.4) + wrist-extensor burst around contact (`gp_we` 0.5) | 14 | 184 | 26 |
| pinch: thumb and index thresholds 0.15 shorter, the other fingers 0.15 longer (`gp_th`, `gp_ix`, `gp_rest`) | 0 | 301 (paddle lost) | 74 |
| wrist-extension bias `bh_wflex` 0.30 -> 0.10 | **21** | **137** | 21 |
| `bh_wflex` -0.10 | 3 | 117 | 25 |
| `bh_wflex` -0.30 | 0 | 118 | 30 |
| `bh_wflex` 0.10 + wrist co-activation around contact | 20 | 126 | 21 |
| all combined | 0 | 241 | 71 |

- Extending the wrist steadies the face (163 -> 117-137 deg/s).
- Past 0.1 the practised posture's face yaws off (20 deg of yaw error at -0.3). The posture would have to be
  practised again with the wrist extended.

**Where it stands.** Still 33.0% on `tt_p2_300` (the winner scored 64%). The val breakdown with `z_bias` -0.03:

| cause | champion | `z_bias` -0.03 |
| --- | --- | --- |
| face more than 8 deg off the aim | 32% | 29% |
| return long, face on the aim | 9.5% | 12% |
| return wide, face on the aim | 6% | 6% |
| missed below the ball | 11% | 5.5% |
| return on own half, face on the aim | 5% | 3.5% |
| missed out of reach (lateral) | 4% | 3.5% |

- The face class dominates, and the arm sets it (the forehand's pitch at the wrist's limit, the backhand's
  by its swing), not the aim.
- The outcome is chaotic per serve.
- 90% needs a controller whose face follows its aim, not a better aim law.

```sh
./build.sh myo_tt_v8
.venv-myo/bin/python playground/arena.py eval tt_p2_300 --params params/myo_tt_p2_r7_zb.txt --controller bin/challengers/myo_tt_r7-a
```

### Table tennis: the face-follow ratio, forehand headroom and a learned wrist residual (round 8)

`skills/myo_tt_v9.w` (`MyoTTV9Skill < MyoTTV8Skill`, entry `lib/entry/myo_tt_v9.w`) adds the round-8
options, each off by default. With every option off it plays the round-5 champion serve for serve (20 of 20).

**The follow ratio.** Round 7 found that the aim is right but the arm does not carry it out. The gate is now
measured directly. `ft_amp`/`ft_yaw` add a pitch/yaw trim to the aim law's normal: a pseudo-random number in
[-1, 1] per serve (from the ball's first seen state) times 0.12 / 0.08. The follow ratio is the slope of the
reached face (unit normal, y and z) on the trim, with the serve's features held (`follow` in the round-8
scratch tools; the trims are reported in `l8`).

Screening used 400 validation serves from the practice pool, disjoint from everything trained on. Paired
tests are against the round-5 champion on the same serves (128 of 400 solved, 32%; forehand 86 of 218,
backhand 42 of 182). The trials were used only as judges.

| step | forehand follow, yaw / pitch | backhand follow, yaw / pitch | val solved, paired |
| --- | --- | --- | --- |
| champion (with the probe) | 0.66 / 0.53 | 0.13 / 0.28 | 119 of 400 (the probe's own cost) |
| forehand posture moved off the wrist's limits (IK: wrist flexion -0.45, deviation +0.05, the face kept) | - | | 0 of 218 (every serve met above the ball) |
| live Jacobians on the forehand (`jac_live` 1) | 0.78 / 0.36 | | 63 of 218 against 80 |
| forehand co-contraction 0.06 (`fh_stiff`) | 0.68 / 0.50 | | 61 of 218 against 80 |
| forehand co-contraction 0.03 | 0.49 / **0.69** | | 51 of 218 against 80 |
| forehand re-practised at co-contraction 0.03 (posture, servo, pitch trim, height; 14 params, sep-CMA; held-out 36.7%) | 0.47 / 0.22 | | 72 of 218 against 86 (-0.064, p 0.94) |
| backhand re-practised with the wrist extended (`bh_wflex` -0.1; 14 params; held-out 31.7% at gen 4) | | 0.33 / 0.24 | 39 of 182 against 42 (-0.016, p 0.71) |
| learned residual on the backhand's forearm and wrist (`rn`: 9-12-3 tanh network, bounded 0.3 rad, ES 20 generations; held-out 30% at gen 10) | | 0.14 / 0.32 | 33 of 182 against 42 (-0.049, p 0.94) |

- **Why the wrist posture fails.** The forehand's forearm and shoulder are not at their commanded posture
  either. Commanded shoulder rotation -1.29 reaches -0.78 at contact, forearm rotation 1.20 reaches 0.44,
  plane of elevation 0.36 reaches 0.96. The servo's corrections are small, except that the shoulder's
  elevation hits its clamp on 19% of serves. So a posture solved for the reached angles and added to the
  command lands nowhere near.
- **Why lowering co-contraction fails.** It gives the pitch servo authority (0.53 -> 0.69: the shared
  co-contraction saturates every forearm muscle, so a servo offset does nothing until an error beats the
  saturation), but the arm then sags and its returns fall short. Practice at that setting moves the wrist
  straight back to its extension and deviation limits (-0.78, -0.16). There the follow ratio drops to 0.22,
  and the solved rate does not come back.
- **Why the learned residual fails.** It acts through the same contraction offsets as the servo. It follows
  no better and returns long (112 of 182 out).

**Blocked.** In this body and grip, face authority and stability trade against each other. The saturated
co-contraction and the wrist at its limits hold the face steady, and every change that frees the face costs
more solved serves than it gains. None of the round-8 challengers improved on the champion on the 400
validation serves, so none was entered in the arena. `tt_p2_300` stays at 33.0%.

Params: `params/myo_tt_p2_r8_fhstiff.txt`, `params/myo_tt_p2_r8_bhwext.txt`, `params/myo_tt_p2_r8_esB.txt`
(with `bin/challengers/myo_tt_r8-a`).

### Table tennis: live tracking from the muscles' moment arms, and a drive residual (round 9)

`skills/myo_tt_v10.w` (`MyoTTV10Skill < MyoTTV9Skill`, entry `lib/entry/myo_tt_v10.w`) adds the round-9
options, each off by default. With every option off it plays the round-5 champion serve for serve (20 of 20).
The task has a new opt-in sensor: with `lt_arms 1` it sends `arm_mom`, the live moment arms (MuJoCo's
d length / d q) of the 32 arm muscles over the 8 servo joints, with the equality-slaved joints folded in.
Without it the handshake is unchanged.

**Why the arm misses its commands.** The controller turns a posture into muscle thresholds with an
additive length model: each joint is swept alone from the reset posture, with the shoulder girdle's coupled
joints set by linear coefficients. Checked against the model's own muscle lengths
(the round-9 check with `playground/myo_bridge.muscle_geometry`):
- At the forehand's commanded posture, the thresholds are off by up to 0.36 of a muscle's range (BIClong;
  SUBSC 0.14, INFSP 0.12).
- At the backhand's, by up to 0.86 (BIClong; SUPSP 0.64, SUBSC 0.46, DELT2 0.37).
- No posture satisfies those thresholds. Taken alone (forces ignored), the forehand's commanded thresholds
  are met at plane of elevation 0.63 and rotation -1.0 (commanded 0.36 and -1.29).

**Live tracking (`lt`).** Each arm muscle's threshold is set from its measured contraction and its live
moment arms: c*_m = c_m - sum_j arm_mj / range_m (q*_j - q_j) + stiff / 2. Here q* is the arm chunk's
joint goal, eased from the posture measured when the chunk began, plus the servo's corrections. The
postures are the ones the champion actually reached at contact on training serves (the commands had been
practised against the wrong map). On 400 validation serves (pool, disjoint from training):

| command - reached at contact, median (rad) | plane | elevation | rotation | elbow | forearm rot. | deviation | flexion | trunk | shoulder + forearm mean |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| forehand, champion | -0.64 | -0.22 | -0.48 | -0.09 | +0.65 | +0.04 | +0.07 | -0.03 | 0.50 |
| forehand, live tracking | -0.47 | -0.20 | -0.30 | -0.07 | +0.29 | +0.04 | 0.00 | -0.03 | 0.32 |
| backhand, champion | -1.52 | +0.32 | +0.87 | +0.02 | +0.50 | -0.02 | -0.04 | +0.21 | 0.80 |
| backhand, live tracking | -0.09 | +0.16 | +0.19 | -0.04 | +0.40 | -0.08 | -0.07 | +0.03 | 0.21 |

| follow ratio (round-8 probe), yaw / pitch | forehand | backhand |
| --- | --- | --- |
| champion | 0.66 / 0.53 | 0.13 / 0.28 |
| live tracking | **1.01 / 0.63** | 0.39 / 0.28 |

- What is left of the forehand's error is the forearm's pronation (0.29-0.40: the pronators are weak at
  those lengths) and the plane of elevation (the pelvis slide swings the arm).
- The champion's calibration (slide offsets, height target, trims, servo gains) no longer fits:
  7 of 400 solved.
- Re-practised per side in the live-tracking regime (16 generations each, sep-CMA, 14-16 params):
  - backhand, best held-out 18.3%;
  - forehand, 10%;
  - the champion's own held-out rates are about 25% and 40%.
  - The tracked arm is a different player: it needs far more practice than a few hours on this machine
    give (params `params/myo_tt_p2_r9_lt_bh.txt`, `..._lt_fh.txt`).

**Drive residual (`rd`).** A 9-12-3 network adds signed feed-forward drives on the backhand's forearm and
wrist pairs (pronators/supinator, wrist flexors/extensors, ulnar/radial), bounded 0.6. A negative drive
inhibits, so it works under the saturating co-contraction, where a threshold offset does nothing. It ran on
the champion's map, trained by ES (20 generations, 6 antithetic pairs x 10 fresh training serves; held-out
25%).
- 400-serve validation backhands: 42 of 182, against 42 (+0.000, p 0.58).
- Follow 0.15 / 0.19.
- Not entered.

**Where it stands.** `tt_p2_300` 33.0% (the winner scored 64%). Live tracking makes the arm reach its
commands (backhand error 0.80 -> 0.21 rad) and the forehand's yaw follow its aim (0.66 -> 1.01). A game
rebuilt on it needs more practice than was available here. No round-9 challenger won the 400-serve screen,
so none was entered in the arena.

```sh
./build.sh myo_tt_v10
# live tracking (the task sends arm_mom when lt_arms is 1):
.venv-myo/bin/python playground/arena.py eval tt_p2_300 --params params/myo_tt_p2_r9_lt_bh.txt --controller bin/challengers/myo_tt_r9-a
```

### Relocate: controlled transport, hold-inside placement, far-side arm control (round 5)

`skills/myo_relocate_v5.w` (`MyoRelocateV5Skill < MyoRelocateV4Skill`, entry
`lib/entry/myo_relocate_v5.w`) adds round-5 options, each off by default
(with every switch off it reproduces the round-4 champion episode for
episode). `playground/tasks/myo_relocate_v5.py` is the relocate task plus an
`obj_see` perception sensor and grasp and transport diagnostics.

What 400 dev seeds of the round-4 champion showed (50000-50199, 60000-60199):

- 40% of episodes fail the grasp. The hand closes at 0.59 s (median) with the
  palm still moving at ~1 m/s. Aim errors over 4 cm (22% of episodes) lift
  almost nothing. Even with good aim the thumb often arrives after the index
  finger has pushed the object away.
- The lift and carry fling the held object at 2.5-3 m/s: the posture table's
  elbow changes by 0.7-0.9 rad over the 20 cm lift, and the shoulder lags its
  command. Of the 126 objects lifted above the rim but not placed, 69 left
  the hand before the release.
- The far side (object y < -0.3, 21% of episodes) lifts 6% (40% elsewhere).
  The forearm rolls from pro_sup 1.3 to ~0.1, because the biceps out-pulls
  the pronators, and elv_angle overshoots its command.
- The outcome is chaotic: any change flips 15-20% of episodes in both
  directions. On 300 fresh seeds the round-4 champion scores 0.20
  (success_lift), against 0.27 on its own 100 arena seeds. Hence the new
  trials `relocate_p2_300` and `relocate_p2_placed_300` (seeds 71000-71299;
  each seeded with its 100-seed trial's champion).

| challenger (paired, 300 seeds) | relocate_p2_300 (success_lift) | relocate_p2_placed_300 |
| --- | --- | --- |
| round-4 champions (seeded) | 0.200 (official 0.233) | 0.133 |
| **D hold-inside + controlled transport** (`params/myo_relocate_v5_hold.txt`) | **0.327, +0.127, p < 0.001: champion** (official 0.393) | **0.200, +0.067, p 0.001: champion** |
| B seen-object aim on D (`params/myo_relocate_v5_see.txt`) | 0.287, -0.040, p 0.94 | |
| A settle-then-close on D (`params/myo_relocate_v5_settle.txt`) | 0.277, -0.050, p 0.96 | |
| **C far-side arm control on D** (`params/myo_relocate_v5_far.txt`) | **0.353, +0.027, p 0.010: champion** (official **0.470**) | 0.213, +0.013, p 0.062 |

On the 100-seed trials D took `relocate_p2` (0.27 -> 0.36, p 0.029, official
0.40); C scored 0.38 there (+0.02, p 0.25). On `relocate_p2_placed` D scored
0.22 and C 0.23, against the champion's 0.16 (p 0.16 and 0.12). The
MyoChallenge 2023 winner scored 0.343 (official).

- **D: controlled transport and hold-inside placement** (`carry5 1`,
  `drop_in 0`).
  - The servo's integrals restart at the lift, so no push wound up during
    the grasp carries over.
  - The lift heads `lift_to` (0.31) of the way to the box as it rises.
  - The lift and carry run their own resolved-rate gains (`rr_kp_c` 7.6,
    `rr_ki_c` 32) with task-space damping (`lf_kd` 3.0).
  - The carry ends over the interior, and the lower brings the object into
    the box at `z_low` 0.97; the hand keeps holding it there, since a held
    object inside the box already counts.
  - Tuned by sep-CMA: 9600 rollouts, 48 fixed seeds, optimizer mean.
  - Lifted-above-rim to placed goes from 44% to 68% on the dev seeds.
- **C: far-side arm control** (`y_far5`). For objects beyond y = -0.3, every
  arm-servo, pronation, joint-space-PD, wrist-offset and reach/close-timing
  param has a `_f` twin, alongside round 4's grasp twins (`y_far`). The twins
  were searched on far-side episodes only (sep-CMA 7536 rollouts on 48 fixed
  far seeds; near objects run D unchanged). Held-out far seeds: 0.07 ->
  0.23 lifted placements (official 0.10 -> 0.36). Aim errors over 4 cm: 89
  -> 41 of 400. A second search from C's mean, on 48 other far seeds, fell
  back to 0.11 on the same held-out far seeds: these 48-seed optima are
  fragile, so validate on held-out seeds.
- **B: seen-object aim** (`see 1`) aims at the centroid of the object's three
  random primitives. That centroid comes from `obj_see`, a perception sensor
  the official observation lacks. The reported site sits 1.5-3 cm from it in
  1 of 13 episodes, and none of those lift. Grasps improve (G 172 -> 157 of
  400), but more objects then drop in transport, whose gains were tuned to
  the site-aimed grip.
- **A: settle-then-close** (`settle 1`). The descend stops `h_hov` over the
  grasp point, and a settle chunk closes the hand only on a latched still
  test: the pinch within `r_still`, slower than `v_still` for `n_still`
  ticks. The palm's speed at close falls from 1.0 to 0.45 m/s, but the extra
  ~0.06 s and the unchanged aim cost more than they gain.
- Dev-only rejects (200-400 dev seeds, champion params):
  - a time lead on the servo target (`lead_g`/`lead_c`): -0.11;
  - a start blend from the arm's start posture into the table (`t_blend`):
    -0.09 to -0.18;
  - a transport squeeze (`squeeze_c` 0.25/0.45): 0 / -0.03;
  - the lift anti-windup alone: +0.05 on dev, -0.02 on fresh seeds;
  - the round-3 pronation-capped table on the far side only (`tab3_y`):
    lifts 0 of 95 far episodes without re-search;
  - a new start-anchored, smoothed posture table (`tab5`,
    `myo_ik` profile `relocate_v5`): 0.05 without re-search.

| 400 dev seeds, G / L / R / S | round 4 | D | C |
| --- | --- | --- | --- |
| grasp failed / lifted below rim / above rim not placed / placed (success_lift) | 160 / 14 / 126 / 100 | 172 / 17 / 68 / 143 | 155 / 23 / 68 / 154 |
| official success, strict placement | 0.297, 0.140 | 0.407, 0.198 | 0.455, 0.220 |
| far side lifted placements (85 episodes) | 0.06 | 0.08 | 0.21 |

In the showcase (seed 50179: the round-4 champion flung this object at
4 m/s during the lift), the held object sinks into the receptacle's solid
base. In MyoSuite 2.12.2 the object-receptacle contact is unreliable
(`reset()` rewrites the object geoms' bounding volumes). The hand's own
contacts with the walls hold.

```sh
./build.sh myo_relocate_v5
ROBOLAB_CONTROLLER=$PWD/bin/champions/relocate_p2_300-20260927-200114 .venv-myo/bin/python playground/myo_bridge.py myo_relocate \
  --params playground/arena/params/relocate_p2_300-20260927-200114.txt --seed 50179 --video out/relocate_v5.mp4 --gif out/relocate_v5.gif
.venv-myo/bin/python playground/arena.py eval relocate_p2_300 --params params/myo_relocate_v5_far.txt --controller bin/challengers/myo_relocate_v5-f
```

### Relocate on the evaluation env: an invisible receptacle, left-side settings, object-following heights (round 6)

`skills/myo_relocate_v6.w` (`MyoRelocateV6Skill < MyoRelocateV5Skill`, entry
`lib/entry/myo_relocate_v6.w`) adds round-6 options, each off by default
(with every switch off it reproduces the round-5 champion episode for
episode, checked on 400 eval seeds). `playground/tasks/myo_relocate_v6.py`
runs the evaluation env (`RELOC6_ENV=p2`: the P2 env) with the round-5
diagnostics plus the object's mass, size and drop roll, and the pose and
contacts of the receptacle the physics actually steps.

What 1200 dev episodes of the round-5 champion on the eval env showed
(seeds 80000-81199; P2 on the same seeds for comparison):

- Official success 0.19 (P2: 0.40). Grasps fail in 72% of episodes (P2: 39%).
- **The physics steps a receptacle the observation does not show.** MyoSuite
  2.12.2 keeps two MjData: `env.mj_data`, observed and scored, whose mocap
  receptacle stays at (0, -0.25, 0.9), and `env.robot.mj_data`, the one
  `mj_step` advances, whose mocap receptacle sits at the pose `reset()` draws
  from `target_xyz_range` / `target_rxryrz_range`. So an invisible 20 cm box
  with 20 cm walls stands at a random place: on the eval env anywhere over
  x -0.5..0.4, y -0.5..-0.1, z 0.9..1.1 (tilted up to 0.3 rad), on P2 over
  x 0..0.3, right of the visible box. The goal test uses the visible one,
  which has no walls in the physics (why round 5's showcase object sank into
  the receptacle's base, and why objects slid in at table height count).
  - Eval env: the arm starts inside the invisible box in 32% of episodes
    (success 0.03) and runs into it later in another 19% (0.11); episodes
    that never touch it succeed 0.28. Moved out of the workspace (a
    diagnostic env override), the same controller scores 0.27 instead of 0.17.
  - P2: the invisible box is involved in 48 of the 87 episodes lifted above
    the rim but not placed: round 5's "drops during the carry" are largely
    carries into its walls. Removing it lifts P2 only from 0.40 to 0.42,
    since it also catches some objects near the goal.
  - Swapping one env's randomisation into the other separates the causes:
    the eval object range costs about 0.13 (P2 env with eval positions:
    0.27), the invisible box about 0.10 (eval env with P2 positions: 0.31).
    Mass, size and the start offset alone change nothing (0.17-0.18).
- By where the object starts: the P2-like core 30% of episodes (0.34),
  beyond y = -0.3 29% (0.08), left of x = -0.3 26% (0.10), nearer than
  y = -0.16 15% (0.24). The palm-down pinch cannot reach past y ~ -0.35 at
  table height (the posture table's own error there is 5-10 cm). Near
  reaches rise instead of approaching: 78% of those that never touch the
  invisible box time out.
- Heavy lifts are lost more often (0.2-0.3 kg: 32% of lifted objects placed,
  against 55% at 0.1-0.2 kg), suddenly (flung at ~2.5 m/s), not by slow slip.
  The drop rolls objects 3 cm (median; 10% over 7 cm) before the grasp.

The options:

- `x_left6` / `y_near6`: position-indexed settings. Objects starting left
  of `x_left6` (and not beyond `y_far5`) take the `_l` twin of every param in
  `reg6_name?` (arm servo, pronation, joint loop, wrist offsets, reach and
  grasp targets and timing, transport); objects nearer than `y_near6` the
  `_n` twin. Far objects keep round 5's `_f` twins.
- `zrel6 1`: the reach, descend and settle heights follow the object's site
  above `z_rest6` (0.94). The reach then tracks the falling object (it
  starts 6 cm higher and comes down with it) and objects resting high (on the
  invisible box) are approached at their height.
- `grip6 1`: a reactive grip: `sq_boost` more flexor drive once the held
  object sinks in the hand or falls away from it, plus `w_load` x the lift's
  vertical lag (a mass proxy) from the lift on.
- `stall6 1`: a stalled reach (no `st_eps` progress for `st_win` s after
  `st_late` s) lifts the hand to `z_esc` and reaches again at `z_trav`;
  `esc0 1` escapes at the first tick (a diagnostic).

Validation: 600 fresh eval seeds (84000-84599). Arena: the 300-seed trials
(73000-73299), paired against the round-5 champion unless noted.

| challenger | dev (1200), official / lift | validation (600), official / lift | arena |
| --- | --- | --- | --- |
| A: shared grasp and transport params re-searched on eval seeds (26 params, sep-CMA 7200 rollouts, 48 training seeds 90000+ without a start inside the invisible box) | -0.038 / -0.032 (best), -0.083 / -0.073 (mean) | | |
| L: left twins (`x_left6 -0.3`, 26 `_l` params, sep-CMA 6288 rollouts, 48 left training seeds, `params/myo_relocate_v6_left.txt`) | +0.010 (p 0.053) / +0.007 | +0.008 / +0.007 | 0.240 / 0.153 (-0.017 / -0.017 against Lz) |
| N: near twins on L (`y_near6 -0.16`, 26 `_n` params, 6288 rollouts) | -0.004 / +0.001 against L | | |
| F: far twins re-searched on eval far seeds | training 0.669 -> 0.685 only | | |
| B: mass-aware grip (`grip6`; `w_load` 4; or `squeeze_c` 0.25), 400 dev | +0.003 / 0 (boost: 1 episode changes); +0.008 / +0.008; +0.008 / +0.010 | with L, Z, D: +0.008 / -0.010 | |
| D: settle-then-close (round 5's A) on the champion | +0.008 / +0.003 | with L, Z: +0.012 / -0.005 | |
| G: stalled-reach escape (`stall6`; `esc0`), 400 dev | -0.060 / -0.038; -0.103 / -0.078 (inside-the-box starts 0.031 -> 0.023) | | |
| Z: `zrel6 1` (`params/myo_relocate_v6_zrel.txt`) | +0.012 (p 0.09) / +0.013 (p 0.044) | +0.002 / +0.015 | 0.247 / 0.157 (-0.010 / -0.013 against Lz) |
| **Lz: L + Z** (`params/myo_relocate_v6_lz.txt`) | +0.018 (p 0.038) / +0.016 (p 0.031) | +0.008 / +0.020 (p 0.068); pooled 1800: +0.014 (p 0.04) / +0.017 (p 0.008) | **relocate_p2eval_official 0.210 -> 0.257 (+0.047, p 0.015): champion; relocate_p2eval_lift 0.127 -> 0.170 (+0.043, p 0.014): champion** |

On P2, Lz scores 0.337 on `relocate_p2_300` (champion 0.353, -0.017, p 0.86;
official 0.417 against 0.470) and ties `relocate_p2_placed_300` at 0.200; on
400 P2 dev seeds it gained (+0.015 lift, +0.035 strict placement, p 0.024).
Other dev-only rejects: a high reach altitude (`z_above` 1.18 / 1.25:
-0.015 / -0.10 official) and a high carry (`z_carry` 1.18 / 1.22: eval
-0.015 / -0.035, P2 -0.045 / -0.10). The 48-seed optima generalise poorly
on this env (A, N, F): any change flips 10-15% of episodes both ways.

The MyoChallenge 2023 winner's 0.343 was scored on the challenge's own
evaluation, where the receptacle stood (visibly and physically) at the
randomised goal. Here the goal is fixed and wall-less while an invisible box
blocks the arm in half the episodes, so 0.257 is not a like-for-like
comparison.

In the showcase (seed 84379, a 295 g object starting at x = -0.35, left of
round 5's range; the round-5 champion lifted it but did not place it), the
left twins carry it over and the hand holds it inside the box.

```sh
./build.sh myo_relocate_v6
ROBOLAB_CONTROLLER=$PWD/bin/champions/relocate_p2eval_official-20260927-234238 .venv-myo/bin/python playground/myo_bridge.py myo_relocate_eval \
  --params playground/arena/params/relocate_p2eval_official-20260927-234238.txt --seed 84379 --video out/relocate_v6.mp4 --gif out/relocate_v6.gif
.venv-myo/bin/python playground/arena.py eval relocate_p2eval_official --params params/myo_relocate_v6_lz.txt --controller bin/challengers/myo_relocate_v6-lz
RELOC6_ENV=p2 ROBOLAB_CONTROLLER=$PWD/bin/challengers/myo_relocate_v6-lz .venv-myo/bin/python playground/tasks/myo_manip.py eval myo_relocate_v6 \
  --params params/myo_relocate_v6_lz.txt --n 400 --seed0 80000 --workers 3 --json out/relocate_v6_p2.json
```

## Batting: bat speed (v6, 2026-09-28)

The athlete batter (`BAT_BODY=athlete`, `tasks/bat.py`, `skills/bat.w`)
swung the v5 load swing at 13.78 m/s at the sweet spot at contact
(`bat_power`); the Codex pure-search swing reached 14.72 m/s with the old
48 ms pre-swing stall (bat_flow 7.3). Hitters: ~32 m/s MLB average; Welch et
al. 1995 (J Orthop Sports Phys Ther 22:193) 31 m/s with pelvis 714 and upper
torso 937 deg/s.

**Where the speed went** (`playground/bat_power_diag.py`: segment peaks and
their timing; every joint's peak rate against its unloaded limit, vmax / 0.3
ranges per second; per muscle group over each track's power phase, the share
of time the prime movers (and the pair's more active muscle) sit at
activation >= 0.9, and the co-contraction index CCI = 2 sum min / sum). On v5
the arm and wrist joints stay at 15-60 % of their limits, the arm and wrist
prime movers spend 2-8 % of the swing at >= 0.9 with CCI 0.19-0.28, the arms
peak 130-160 ms before contact while the bottom wrist casts, and the bat's
angular speed peaks 42 ms early: the reflexes track a slow plan. Raising the
plan's contact speed (`con_speed` 13 -> 26: +0.19 m/s), reciprocal inhibition
(-2.4, 15/18 hits), drive along the v5 plan (0 hits: the bat arrives early),
wrist lag and release on the v5 plan (+0.25, 8 fair instead of 12), the
Codex gains on v5 (-0.6 to -2.9) and a 90-candidate sep-CMA re-tune of 28 v5
tunables for power (no gain) all stay near 14 m/s (paired on the 18 pitches).

**What the body can do** (`playground/bat_ceiling.py`). From the moment a
practised swing's hips fire, CMA-ES drives the 16 upper-body joints open loop
(a net excitation per joint every 40 ms, so no co-contraction; legs replayed;
MuJoCo's activation dynamics, force-velocity curves and the top hand's grip
apply): 27.6 m/s through the v5 contact point. The pattern: the pelvis turns
at full activation into its yaw limit, the spine stays coiled, the top arm's
elbow extends, the lead shoulder abducts and rotates, and the bottom wrist,
held at full radial deviation, whips through 0.8 rad of ulnar deviation in
the last 60 ms: 1070 deg/s, 1.7x what its own muscles can drive unloaded (the
arms fling it; Flynn et al. 2021 measured 1093 +- 354 deg/s in college
hitters). `--ball` scores the real pitch instead: the ball flies on from the
captured state, the score is the speed at the first bat-ball contact plus a
fair-ball bonus. Captured from the v6 controller itself, one run is one
iteration of learning its feed-forward with the body in the loop.

**v6** (`skills/bat_power.w`, `BatPowerSkill < BatSkill`, `bin/robolab_bat_v6`;
every feature opt-in, and the v5 params replay v5 exactly):

- `prog` (ORACLE, `params/bat_v6_prog.txt`): the upper body plays one
  ideal-control program per pitch location (`skills/bat_program.w`, from
  `bat_ceiling.py --ball` on the 6 grid locations at 76 mph, exported by
  `playground/bat_program_export.py`), blended by inverse squared distance to
  the predicted crossing, from the hips firing, with the program joints'
  reflex gain 0 and no chunk bursts; every track fires 0.23 s before the
  plate. It bypasses the contraction-target + reflex layer, so it is a
  ceiling-class controller, labelled ORACLE in the arena.
- `train` (robolab representation, `params/bat_v6_knots.txt`): each track's
  swing is 11 quintic contraction knots (`Chunk#knot` + via) whose keyframes
  (c, v, a) are the program's own joint trajectory, set from the predicted
  crossing while the pitch flies; each knot chunk drives the muscles the
  program excited over its segment (phase-gated drive), with reciprocal
  inhibition (`ri 1`) and the reflexes on at the swing gains. Each train holds
  its load's aim correction and its keyframes subtract it (without that, the
  decaying aim offsets pulled the swing off by 0.1-0.3 rad and it missed half
  the pitches). The step lands 62 ms later (`step_delay` 0.165), which cut the
  pre-swing stall from 115 to 50 ms.
- also: `ri`, `pw_*` (drive along the plan), `lag` / `rel_*` (wrist lag and
  a release latched on the trunk's yaw rate braking), `off_*` (per-phase
  offsets, the Codex idea). None of them beat v5 on their own.

| arena (athlete body) | v5 load | Codex | v6 knots | v6 knots b | **v6 oracle** |
| --- | --- | --- | --- | --- | --- |
| bat_power (18 grid pitches), m/s | 13.78 | 14.72 | 23.12 | 24.45 | **25.17** (champion) |
| bat_power_clean (bat_flow <= 3 on every pitch) | 13.78 | fails guard | 23.12 | 24.45 | **25.17** (champion) |
| bat_power_fresh (24 held-out pitches) | 13.86 | 14.79 | 21.57 (22/24 hit) | 20.63 (~20/24) | **25.24** (champion, 24/24) |
| bat_power_fresh_clean | 13.86 | fails guard | fails (2/24) | fails (4/24) | **25.24** (champion) |
| bat_flow (lower is smoother) | **2.05** (champion) | 7.33 | 2.77 | 2.67 | 2.18 |
| bat_quality | 0.04 | 0.13 | 0.05 | 0.14 | **0.42** (champion) |
| hits / fair on the grid | 18 / 12 | 18 / 12 | 18 / 13 | 18 / 14 | 18 / 15 |

v6 knots is `params/bat_v6_knots.txt`; knots b (`params/bat_v6_knots_b.txt`)
is it re-tuned by sep-CMA (40 candidates: reflex gain x1.29, arm damping
0.027, drive x1.10) on the grid plus 12 practice pitches from the fresh
distribution (seeds 2000-2011): better on the grid (97 % of the oracle), worse
on the held-out pitches, i.e. over-fitted. In robolab's own representation
(knots, reflexes on) 92-97 % of the oracle's speed survives on the grid and
82-85 % on held-out pitches, where 2-4 of 24 pitches are missed by 1-3 cm.

The programs saw 6 of the 18 grid pitches (the 6 locations at 76 mph); the
other 12 grid pitches share those locations at 83 and 91 mph. The
`bat_power_fresh` trials (`BAT_FRESH_PITCH`: speed 34-40.5 m/s, crossing
x -0.15..0.15 m, height 0.62-1.00 m, uniform, seeds 1000-1023) were never
used to train anything (knots b practised on seeds 2000-2011 of the same
distribution). A second program library (`out/bat_ceiling/lib2/`: 14
programs, 8 of them off-grid at 83/91 mph, blended by speed as well, the step
62 ms later) did worse on the faster grid pitches (16/18 hits): blending
programs from different optima makes a swing none of them is, and with the
later step the 91 mph pitches start the swing only ~10 ms after the plant, from
a different state.

Kinematics (peak over the swing; deg/s): pelvis 397 (v5) -> 425 (oracle) /
427 (knots), MLB 714; upper torso 607 -> 533 / 479, MLB 937; top-arm elbow
extension 488 -> 604 / 591, pros 1539 (Dowling & Fleisig 2016); bottom wrist
ulnar deviation 329 -> 1069 / 930, college 1093 +- 354; bat 1196 -> 2079 /
1914, peaking at contact (v5: 42 ms before). The speed comes from the wrist
whip at a human wrist rate; the trunk and arms stay at 50-65 % of MLB rates,
which is where the rest of the gap to 32 m/s is.

Activation over the power phase (hips firing to contact; % of it at >= 0.9
for the pair's more active muscle, CCI):

| group | v5 | v6 oracle | v6 knots |
| --- | --- | --- | --- |
| pelvis | 31 %, 0.03 | 45 %, 0.03 | 37 %, 0.01 |
| trunk | 57 %, 0.15 | 38 %, 0.00 | 39 %, 0.05 |
| shoulders | 5 %, 0.28 | 25 %, 0.00 | 10 %, 0.09 |
| elbows | 8 %, 0.19 | 22 %, 0.00 | 16 %, 0.09 |
| wrists | 2 %, 0.24 | 5 %, 0.00 | 4 %, 0.12 |

The optimum is not sustained full drive: the pelvis and trunk sit at full
activation for 40-45 % of the swing, the arms fire short full bursts that
reverse, and co-contraction goes to zero.

```sh
.venv/bin/python playground/bat_power_diag.py --params params/bat_v6_knots_b.txt --controller bin/challengers/bat_v6-knots1
.venv/bin/python playground/bat_ceiling.py --params P --controller C --seed 0 --ball --lead 0 --gens 400 --workers 4 --name ball_s0
.venv/bin/python playground/bat_program_export.py out/bat_ceiling/ball_s{0,1,2,3,4,5}.json && ./build.sh bat_v6
```

Video: `out/bat_v6.mp4`, `out/bat_v6.gif`, `out/bat_v6_sheet.png` (the oracle
on the 4 demo pitches: 25.6, 24.9, 24.3, 25.8 m/s; 3 fair).
