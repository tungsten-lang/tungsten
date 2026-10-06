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
| `playground/arena.py`, `playground/arena/` | the champion-challenger arena: `trials.json`, `champions.json`, `history.jsonl`; rules in `playground/arena/README.md` |
| `tools/` | `snapshot_commit.sh` (commit this directory to the branch `robolab-campaign-2026-09` without touching the shared checkout), `land_snapshot.sh` (fast-forward or merge that branch onto `main`, healing the shared index), `arena_board_md.py` (the board with each champion's frozen artifacts), `check_doc_paths.py` (checks the backticked paths of a Markdown file) |
| `site/progress/` | generator of the progress page (`build_progress.py` writes `progress.html`; numbers come from `champions.json`; `--publish` / `--mark-published` with `published.json` track which videos the live artifact holds) |
| `site/keyframe_bench/` | the Keyframe Bench artifact (`keyframe_bench.html`, https://claude.ai/artifact/L6CSUpkUVwrygS5yP6UmaB): drag-the-joints keyframes with an onion skin of the whole stride and subset keyframes (`pinned` per joint; the export gives free joints their interpolated value plus `ref_<event>_<key>_free 1`); `seed.py` writes the database seed docs, `check_bench.py` runs 30 headless checks against a mock database, `bench_perf.py` times a refresh |
| `HANDOFF_20260929.md`, `HANDOFF_20260929_board.md` | where everything stands on 29 Sep, who owns which workstream, next steps and traps |

## Setup

```sh
cd bits/tungsten-robolab
uv venv --python 3.12 .venv && uv pip install --python .venv/bin/python mujoco numpy imageio imageio-ffmpeg pillow
./build.sh
.venv/bin/python playground/bridge.py stand --video out/stand.mp4
```

The recorded arena numbers assume the exact package versions in `requirements/` (MuJoCo 3.14.0 for the robolab
bodies, MuJoCo 3.6.0 with MyoSuite 2.12.2 for the MyoChallenge tasks); `requirements/README.md` has the pinned install
commands. Frozen champion binaries (`bin/champions/`, `bin/challengers/`) are not in git: a fresh clone can run
`arena.py board` and `arena.py eval`, which compare against the recorded scores, but not `arena.py recheck`.

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

### Long jump, round 2 (28-29 Sep): the ideal take-off, a landing that stops rolling over, and what a fresh start does

The tables above are round 1; the arena board is authoritative. Round 2 replaced the chunk take-off with the
**ideal-control take-off** of each body's own approach state, added a learned **landing program**, and then spent a
night finding out why the robust means stayed far below the one-start jumps.

**The method** (`playground/long_jump_limits.py`; the runner's own approach state in, jump out):

1. `capture` a real rollout at the start of the plant flight (`--from pen`: at the penultimate touchdown): position,
   velocities, muscle activations and tendon fibre states, exactly.
2. `optimise`: all 32 muscles follow open-loop excitations from that state to the take-off; sep-CMA maximises the ballistic
   distance from the board. That is the **ideal-control ceiling** of the body from that approach: 4.93 m for the 7.02 m/s
   p95 runner (vx 6.27, vz 2.89 m/s, contact 0.112 s), 4.25 m for the 6.56 m/s elite2 runner.
3. `distil` the ideal into quintic contraction knots plus drive knots every 30 ms, latched on the plant touchdown (`j_ik`, `ik_*`;
   `ik_from 1` starts the program at the penultimate touchdown) and re-optimise it over captured perturbed approaches
   (`robust`).
4. `handover` the program on many approaches, then `landing`: a landing program (`j_il`, `il_*`: excitation knots on their own clock,
   latched on the first sand contact) learned by sep-CMA on the hand-over states. **ORACLE-class**: the landing table is an
   open-loop excitation program, and so is the p95 take-off (reflex gain 0.03); the residuals added this round are sensed,
   bounded and zero-initialised.

**Arena** (all promotions paired; `long_jump_p95_robust32`, `_robust96` and `long_jump_elite2_robust32` are new trials on starts
that no search or practice ever used, seeded with the champion they replaced):

| trial | body | before | champion now | verdict |
| --- | --- | --- | --- | --- |
| `long_jump_p95` (1 start) | p95 | 4.895 m | **5.122 m** (feet mark, 0.37 m beyond the ballistic 4.75) | promoted three times (4.958, 5.100, 5.122): a landing program learned for this start; overfit to it by construction |
| `long_jump_p95_robust` (16) | p95 | 3.924 m | **4.631 m**, 16/16 legal (4.30-4.79) | +0.706, p < 0.001 |
| `long_jump_p95_robust32` (new, 32 fresh) | p95 | 3.445 m | **4.546 m**, 31/32 legal | +1.10, p < 0.001 |
| `long_jump_p95_robust96` (new, 96 fresh) | p95 | 4.084 m (the 16-start champion, pn1) | **4.317 m**, 89/96 legal (median of the legal 4.68) | +0.234, p = 0.003 (pn2: swing-foot lag feedback) |
| `long_jump_elite2_robust32` (new, 32 fresh) | elite2 | 3.011 m | **3.592 m**, 31/32 legal | +0.58, p = 0.001 (run-up steering 0.3, check mark +0.04 m) |
| `long_jump_elite2_robust` (16) | elite2 | 3.936 m | 3.936 m (kept) | the steered variant scores 3.68 there and does not beat it |
| `long_jump_v4_p95` (1 start, new) | v4 p95 | 0 (baseline: the default chunk jump) | **4.945 m** (the seat marks; 5.05 m from the take-off foot) | promoted three times (4.632 with the chunk landing; 4.901 and 4.945 with a landing program learned for this start, generations 30 and 50): the ideal-control take-off of the calibrated body's runner (ceiling 4.89 m ballistic), 44 m check mark (`long_jump_v4_p95b`) |
| `long_jump_v4_p95_robust` (16), `_robust32` (new, 32 fresh) | v4 p95 | 0 | **2.145 m** (9/16 legal), **2.851 m** (25/32 legal) | promoted, PROVISIONAL: the one-start take-off with a practised run-up planner (`params/long_jump_v4_p95_ik2.txt`) |
| `long_jump_v4_elite2`, `_robust` (new) | v4 elite2 | 0, 0.45 | baseline only | not built |

`long_jump_p95_robust` and `_robust32` hold pn1 (`params/long_jump_p95_pn1.txt`), `_robust96` holds pn2
(`params/long_jump_p95_pn2.txt`; on the arena's 16 starts pn2 scores 4.38 with one somersault, so pn1 keeps that trial).
Controller: `bin/challengers/long_jump_run-b20p` / `-b20q` (frozen copies of the skill build b20). One-start jump:
`params/long_jump_p95_ik11.txt`, `-b20t`.

**A champion's 16 fixed starts hide the failure rate.** The arena scores a champion on the same 16 perturbed starts forever, and
16 of 16 can be legal by luck: the p95 champion of 28 Sep scored 3.92 m there but 3.27 m on 96 fresh starts (90 legal: 2 stumbled in
the run-up, 2 somersaulted, 1 fouled, 1 touched the runway after landing) and 3.44 m on 32 others; the elite2 champion scored 3.94
there and 3.01 on 32 fresh (on 80 starts, 64 fresh and the 16, 5 landed short and 6 fouled). Judge a controller on fresh starts.

**Why the robust means were far below the one-start jumps** (112 fresh starts with the p95 penultimate-touchdown program; the
harness `handover` reproduces every class on the captured states):

- **The landing rolls over: a timing problem, not a rotation-control problem.** The landing program's knots run on a clock started at
  the hand-over; the sand only re-syncs it. A flight 0.09 m lower or 0.2 m/s slower than the ones it was learned on lands 30-50 ms
  earlier than the program expects. The legs are still hanging when the toes touch the sand, the COM 1.0 m up and 0.1-0.2 m behind the toes,
  and the body vaults over its feet (Ly 0 to 75-110 kg m2/s in 0.1 s, torso pitch through pi). The fix is a **ballistic-time clock**
  (`il_tg`, `il_zl`): before the sand the program time is tg minus the COM's ballistic time to fall to zl (a flight is ballistic whatever the limbs
  do), so the legs' tuck and reach are locked to the predicted landing. On the 32 hand-overs of the landing search the 3 roll-overs went to 0
  for tg 0.58-0.66 (`playground/long_jump_diag.py --tgs`). The program was learned on those 32 hand-overs only and overfits the clock:
  tg 0.70 makes 48 of 112 fresh starts somersault. On the average body's hand-overs the clock changes nothing (4 of 23 roll over
  for another reason).
- **A scuffing swing foot** (4 of 96 fresh starts). The plant-side toe clears the runway by 12 mm in a healthy start (site height 0.032 m; the ground
  contact is at 0.019 m) and drags for 0.1-0.15 s in a bad one. The plant-touchdown latch (force above 0.05 body weights) fires on the scuff at
  0.10 s, 0.14 s before the ideal touchdown; the program clock jumps ahead and runs the stance in the air. `ik_fmin 1.5` (the latch needs 1.5
  body weights; a real plant reads 4 on its first tick, scuffs 0.2-0.94) removes the class.
- **Weak take-offs** (vz 1.6-2.4 m/s, typical 2.7-3.0): a late stride phase, the swing foot 0.5-0.7 m behind the COM and the trunk 0.15-0.2 rad
  forward at the penultimate touchdown (0.08 +- 0.03 typical; vz = 3.05 - 4.0 x pitch in the harness), about 10% of starts. The flight is short
  (0.4-0.6 s) and lands with the legs hanging. A one-sided torso-pitch feedback on the free leg's hamstrings lifts vz (vz < 2.4: 10 to 1 of
  161 mined starts) but turns those starts into forward-rotating take-offs (L +2 to +23 kg m2/s instead of -5.8 +- 2) that no landing recovers:
  every somersault of the 112 has L above 1.7 or a take-off pitch of 0.24 rad or more. What helped is a **swing-foot lag feedback** (`ik_fx*`,
  `ik_kf_*`, found by greedy forward selection on 119 mined approaches under penalties L <= -1.5, pitch <= 0.25, vz >= 2.55): 87 legal of 96 to
  92 on 7001-7096, 84 to 89 on 9033-9128.
- **Fouls** (3 of 112, 5-49 mm): the take-off foot's front lands 0.06 +- 0.05 m behind the line. A check mark 0.05 m longer (task
  `long_jump_p95g`; `j_board_shift` and `ik_gap0` move with the board, so the run-up is identical) removes them for 0.05 m.
- **The runner's own stumbles** (2-3%): a fall in the acceleration phase (steps of 0.9, 0.9, 0.7 m at 3.5 s); not the jump's.
- **Elite2 has a different problem**: its run-up cannot be steered (`j_st_w 1.5` makes it fall), so the take-off foot lands 0.2-0.5 m behind
  the line or well over it. A gentle steering (`j_st_w 0.3`; 0.6 falls) plus a check mark 0.04 m longer (`long_jump_elite2b`) lifts the fresh-start
  mean by 0.3-0.6 m; 0.08 and 0.12 m of check mark were worse.

Roll-over rates on fresh starts (somersaults per start): the 28 Sep champion 2/96 (2.1%); pn1 16/240 (6.7%: the clock and the latch alone);
pn2 9/384 (2.3%), with 7/384 stumbles in the run-up and 368/384 legal (95.8%) on four sets of 96 fresh starts (7001-7096, 9033-9128, 9129-9224, 9225-9320:
4.48, 4.32, 4.53, 4.58 m; mean 4.48 m, 4.67 m of the legal). The pn family jumps 1.2 m farther than the old chunk landing at the same roll-over rate. Six of the seven remaining somersaults of the
first 192 starts take off with the trunk 0.39-0.9 rad forward (the seventh with L +9.6 kg m2/s). A short-flight landing that survives them is still open: a hand-set time-to-strike reflex
(`il_ctau`, `il_kc_*`) rescued 2 of 5 weak hand-overs, a learned one 13 to 8 of the 56 hardest (5 to 4 of 75 held out); a pitch feedback aimed at the
take-off trunk angle (`ik_kp_*`, tried on top of pn2) made fresh starts worse (90 legal of 96 against 93), and a full-dimension landing retrained on 64
hand-overs of pn2's take-off (marks +0.03 held out in the harness) changed nothing in full rollouts (93 legal of 96, 4.547 m, against 94 and 4.579).

**Against humans** (men; sources and levels as in round 1; D marks a value derived here):

| level | distance | our body |
| --- | --- | --- |
| untrained woman | 3.57 +- 0.54 m | elite2: 3.59 m fresh mean, best start 4.1 |
| untrained man | 4.95 +- 0.55 m | p95: **5.12 m** best (103%; the 62nd percentile), 4.63 m robust on the arena's 16 starts, 4.32-4.53 m on fresh starts (87-92%; the 13th-22nd percentile of untrained men) |
| speed-matched elite jumper (an 8.30 m jumper from 6.1-6.6 m/s run-ups; Bridgett & Linthorne 2006) | 4.33-4.77 m | p95 at 6.7 m/s: 4.4-4.6 m robust, 5.1 m best: at or above |
| high-school state qualifying | 6.07-6.65 m from 8.9 m/s | not reached |
| NCAA D1 finals median, world record | 7.56-7.75 m, 8.95 m | not reached |

Body by body (official marks, metres; "fresh" = starts no search or practice used; the arena board is authoritative):

| body (runner peak) | one start | arena, 16 starts | fresh starts | human level reached |
| --- | --- | --- | --- | --- |
| average (p50, 5.0 m/s) | 2.47 (`long_jump_v2`) | 1.85 | not measured (48 starts: 1.86, 3 fouls) | below the untrained woman (3.57 m) |
| elite2 (literature body, 6.56 m/s) | 4.01 | 3.94 | 3.59 (32) | the untrained woman's mean; 4.1 m on its best start |
| p95 (v3, 7.02 m/s; 6.7 at the board) | **5.12** | **4.63** | 4.32-4.53 (96 each) | the untrained man's mean (4.95) on one start only; 87-92% of it robustly; inside the speed-matched elite jumper's range (4.33-4.77) |
| v4 p95 (calibrated, 7.0 m/s; 6.4 at the 44 m board) | **4.945** | 2.15 (provisional) | 2.85 (32, provisional) | the untrained man's mean on one start (99.9%); the family is not robust yet |

The p95 body's take-off (vz 3.0 m/s, contact 0.13 s) equals that of Willwacher et al.'s 7.27 m jumpers (vz 3.01 m/s); what it lacks is speed: 6.7 m/s at
the board (the runner tops out at 6.9 m/s at 37-45 m and 7.0 m/s at 55 m: a longer run-up adds 0.06 m/s). The fit to the best jump,
D = 0.88 v t_air(vz) + 0.52 m, with v the run-up speed at the board (a projection, not a measurement), needs for vz 3.0 (the model's own
take-off) / 3.3 m/s (Bridgett & Linthorne's speed-matched jumper): 4.95 m at 6.5 / 6.1 m/s, 5.5 m at 7.3 / 6.9 m/s, 6.07 m at 8.2 / 7.7 m/s,
6.65 m at 9.0 / 8.4 m/s, 7.56 m at 10.3 / 9.7 m/s, 8.95 m at 12.4 / 11.6 m/s. So the next level (robustly above the untrained man's mean, 5.5 m) needs a 7.3 m/s run-up at the
board, high-school state level 8.2-9.0 m/s. The sprint work's v4 P95 body has a 10.45 m/s ideal-control ceiling; its promoted runner (`sprint_top_speed_v4_p95`, a crouched high-cadence gait, 10 of 12
starts) tops out at 7.0 m/s, no faster than the v3 p95's, and gets 6.4 m/s at 37.5 m, 6.7 at 45 m and 6.8 at 55 m through the long jump skill. The v4
long-jump family is started: trials `long_jump_v4_p95`, `_p95_robust`, `long_jump_v4_elite2`, `_robust` (env `ROBOLAB_CALIB=v4`, tasks
`long_jump_v4_p95`, `long_jump_v4_p95b` with the 44 m check mark, `long_jump_v4_elite2`). The ideal-control ceiling of the v4 P95 runner from its own plant-flight
state is 4.89 m (L <= -1.5; v3 p95: 4.93 m); distilled into knots and closed on that one start, the take-off jumps **4.632 m** in a full rollout
(`params/long_jump_v4_p95_ik1.txt`; the chunk landing falls back onto the head) and **4.945 m** with a landing program learned for that start
(`params/long_jump_v4_p95_ik5.txt`, generation 50 of the search, `-b20x`; 4.901 m at generation 30 in `_ik3`; promoted on the one-start trial), so the method transfers to the calibrated body. It is not robust: the run-up planner's parameters are the v3
gait's and the take-off foot's position relative to the line has a standard deviation of 0.47 m on 32 fresh starts (v3 p95: 0.05), so half of them foul.
Nine generations of run-up planner practice (`long_jump_run_practice.py`, official score, 12 starts) reach 25 legal of 32 fresh starts at 3.65 m (mean 2.85), with the
same 0.5 m spread and the foot 0.66 m behind the line on average; that is what the v4 robust trials hold. What is missing is what the v3 pn family
has: a take-off program that reads the gap to the board (the `robust` stage over many captured v4 approaches, which learns the gap knots), and a landing
table trained on many hand-overs; the speed is what limits the human level, not the calibration.

**What is next.** (1) The elite2 body: its 159 mined plant-flight states (`out/long_jump_limits/e2m_s*_capture.npz`, hand-overs `e2mh`) show the champion's take-off vz
following the gap to the board (r = 0.79 in `playground/long_jump_mine.py`: 1.9 to 2.6 m/s), 3.71 m on the 151 legal (3 invalid, 5 fouls, no roll-over), against an
ideal-control ceiling of 4.25 m; a `robust` stage over 40-60 of them with gap knots and a landing table on their hand-overs is the analogue of what lifted the p95 from
3.92 to 4.63 on the arena's 16 starts (round 2 did not get to it; the machine ran at a load average above 100 for the last day). (2) The v4 family needs the same two stages plus a run-up that
puts the foot within 0.05 m of the line. (3) Any level above the untrained man needs run-up speed: 7.3 m/s at the board for 5.5 m, 8.2 to 9.0 m/s for the high-school state
qualifying level (table above); the v4 P95 runner's 7.0 m/s peak (6.4 to 6.8 m/s at the board) does not reach either.

**Practice and the harness.** `playground/long_jump_diag.py` (a landing tick by tick; `--tgs` scans the clock), `playground/long_jump_mine.py` (approach
features against outcomes over captured starts) and `playground/long_jump_eval.py` (full rollouts, one line per start, for starts that are not the arena's).
The harness is not exact: take-off vx and vz differ from the full rollout by 0.2-0.4 m/s on some starts for the base program too, and a
feedback selected in it screens candidates that full rollouts must decide. A pitfall found on the way: the take-off tables are by muscle role
(T_ = the plant leg's side), and 4 of 161 mined starts take off with the left foot; a search that reads the tables with the first capture's side
mirrors them wrongly for those starts (they appeared as failed take-offs). `greedyfb` builds tables and gains per capture side.

```sh
.venv/bin/python playground/long_jump_limits.py capture long_jump_p95e --params out/long_jump_run/p95pn_approach.txt \
  --controller bin/challengers/long_jump_run-b20 --seeds 8001,8002 --name p95mn --from pen
.venv/bin/python playground/long_jump_limits.py handover out/long_jump_run/p95pn_latch.txt --captures p95mn_s8001,p95mn_s8002 --name h
.venv/bin/python playground/long_jump_mine.py p95mn h out/long_jump_limits/land_p95pn3.txt --tg 0.61
.venv/bin/python playground/long_jump_limits.py greedyfb out/long_jump_run/p95pn_ik.txt --prefix p95mn --channels kp,kf \
  --lmax=-1.5 --lw 0.3 --pmax 0.25 --pw 3 --fmin-on --delta 0.05 --out out/long_jump_run/fb.txt
.venv/bin/python playground/long_jump_eval.py long_jump_p95_robust96 --params params/long_jump_p95_pn2.txt \
  --controller bin/challengers/long_jump_run-b20q --task long_jump_p95g
.venv/bin/python playground/long_jump_run_render.py long_jump_p95e --params params/long_jump_p95_ik11.txt \
  --controller bin/challengers/long_jump_run-b20t --out out/long_jump_v5_p95_5122
```

Videos: `out/long_jump_v5_p95_5122.mp4` (the 5.12 m one-start jump: take-off, flight and landing at 1/4 speed; the jumper tumbles in the pit but no
rule is broken; feet mark), `out/long_jump_v5_p95_robust.mp4` (the robust champion on arena start 404, 4.79 m), `out/long_jump_v5_elite2_robust.mp4`
(the elite2 champion on fresh start 9030, 4.10 m), `out/long_jump_v5_p95_4958.*` (the intermediate 4.958 m; the hand marks), `out/long_jump_v5_p95.*` (the 4.895 m of
round 2's first champion) and `out/long_jump_v5_v4p95.*` (the calibrated v4 P95 body, 4.945 m, the seat marks); each has a `_sheet.png` and a `_metrics.json`. The run's log is `out/long_jump_run/LOG.md`. New task modules:
`playground/tasks/long_jump_p95g.py` (check mark 37.54 m), `playground/tasks/long_jump_elite2b.py` (38.89 m), `playground/tasks/long_jump_v4_p95.py`,
`playground/tasks/long_jump_v4_p95b.py` (44.0 m) and `playground/tasks/long_jump_v4_elite2.py`.

### Long jump, round 3 (29 Sep): the two-gear runner, steered foot placement, a take-off program that survives a fresh start

Erik's goal: the best runner for the long jump, then beyond human ability, legality first (World Athletics TR 29-30). Body: v4 P95 (`ROBOLAB_CALIB=v4`, p95 profile),
the trials of round 2 (`long_jump_v4_p95`, `_robust` 16 starts, `_robust32` 32 fresh starts) plus the new `long_jump_v4_p95_robust96` (96 fresh starts, seeds 9033-9128).
The runner is part of the challenger, not of the trial. Label used throughout: ORACLE = open-loop excitation programs and near-open-loop knots (the take-off program's
reflex gain is 0.46 around its excitation table, the landing table's 0.14); one-start numbers are overfit to that start by construction; only the robust trials count as the jump.

**The runner.** The sprint agent's champion `sprint_top_speed_v4_p95` became RunGearSkill (`lib/robolab/skills/run_gear.w`, RunRI with gears: the stride is rebuilt from `g<k>_`
twins of every tunable the first flight after the filtered speed reaches `g<k>_v_on`). Frozen copies for the jump: `params/lj_runner_gear_v4_p95.txt` (= `run_gear_v4_p95_c.txt`,
29 Sep 05:37, 7.449 m/s peak, gears 2), `params/lj_runner_gear3_v4_p95.txt` (= `_e.txt`, 06:45, 7.862) and `params/lj_runner_gear4_v4_p95.txt` (= `_g.txt`, 07:53, 7.907).
Gears 1 and 2 are identical in all three files, and gear 3 needs the filtered speed to reach 7.0 m/s, which a 44 m run-up does not: the jump reaches 6.6-6.9 m/s at the
board (the sprint numbers are 20 s / 100 m speeds), and approach-only rollouts of the two- and three-gear params are identical start by start. The jump uses the two-gear file.

**Wiring.** `LongJumpRunSkill < RunGearSkill` (was RunRISkill). `add_jump_chunks(mv)` puts the take-off, ik, il and flight chunks on a movement; it is called from `start` and from a
`switch_gear` override, because a gear change builds a fresh stride movement (RunGearSkill#switch_gear) and swaps it under the track. Opt-in: the params-file switch `gears N`
(plus the `g<k>_` twins); without it the run is RunRISkill's exactly. Replays with the final build (c3) are per-seed identical to the stored scores for the frozen params of all 17 current long-jump champions (`scratchpad/lj2/replay_all.py`:
`long_jump_p95` 5.1220, `long_jump_p95_robust` 4.6305 over 16 starts, the elite and v3 P95 trials, the round-3 v4 champions) and for round 2's superseded v4 champions, start by start against their frozen binaries
(`replay_round2.py`: one start 4.945, 16 starts 2.1452, 32 starts 2.8508, 96 starts 2.5355; 145 starts, none differs). New opt-in skill options (defaults bit-identical):
`j_st_rnd` (rounding of the step count in the run-up plan), `j_st_up`, `j_st_zk`. Harness (`playground/long_jump_limits.py`): `robust` and `landing` train on both plant sides
(`side_perm` / `mirror_tab`), plus `ROBOLAB_LJ_BOARD` / `_TD` / `_MARGIN` / `_DV` / `_FSCALE` options (a board-relative ideal, a fixed plant-touchdown time, a foul margin,
a faster or stronger body); single-side runs are unchanged (checked against the HEAD version of the file).

**Speed at the board** (approach only, `j_run 1`, last 5 m before the check mark, 17 starts, no falls in any cell):

| check mark | RunRI (round 2's runner) | two-gear as frozen (switch 6.5 m/s) | two-gear, `g2_v_on` 5.0 |
| --- | --- | --- | --- |
| 30 m | 6.02 | 6.02 | 6.22 |
| 35 m | 6.28 | 6.28 | 6.48 |
| 40 m | 6.47 | 6.47 | 6.69 |
| 44 m | 6.59 | 6.62 | **6.83** |
| 45 m | 6.62 | 6.67 | 6.86 |

The frozen switch at 6.5 m/s comes at 40 m, so the two-gear runner is RunRI up to there. Moving it to 5.0 m/s gives +0.22 m/s (4.5: +0.03 more; 4.0: 3 falls in 8). Speed profile with it (5 m windows): 5.1 m/s at 15 m,
6.0 at 25, 6.6 at 35, 6.9 at 44, 7.05 at 50, 7.25 at 65: a longer run-up adds about 0.1 m/s per 5 m between 45 and 55 m and 0.05 beyond. What the jump does with it: the upright final approach that the take-off needs costs 0.2 m/s
(torso servo over the last 12.6 m: 6.61 m/s against 6.83 without), so the jump's last-5-m speed is 6.6 m/s.

**Ideal-control ceiling, recomputed for this runner** (`long_jump_limits.py optimise`: open-loop excitations of all 32 muscles from the captured penultimate-touchdown state,
forward angular momentum at take-off <= -1.5 kg m2/s; ORACLE-class, one start). From the nominal start of the first approach (COM 6.59 m/s at the penultimate touchdown, 120k evaluations):
**5.219 m ballistic from the take-off foot** (vx 6.32, vz 3.10 m/s, 26.1 deg, contact 0.088 s, foot 0.17 m behind the line: 5.05 m from the line). Round 2's ceiling for the calibrated body was 4.89 m from a
6.37 m/s state, the v3 P95's 4.93 m from 6.8-6.9 m/s. The estimate moves by about +-0.2 m between neighbouring starts (the search plateaus): 5.03 (upright approach, other steering), 4.96 (natural run), 4.83 (trunk
forward), so read it as 5.0-5.2 m. Board-relative (foot held 3 cm behind the line) the same state gives 5.13 m from the line. What the ceiling depends on (same state, 60k evaluations from the same start;
`ROBOLAB_LJ_DV`, `ROBOLAB_LJ_FSCALE`): a body moving 0.4 / 0.8 m/s faster: 5.22 / 5.52 m (vs 5.03: +0.5 to +0.6 m per m/s); muscles 20 / 40 % stronger: 5.43 / 5.91 m (+0.39 / +0.88 m).

**Foot placement was the v4 jump's real problem.** Round 2's planner had `j_st_w` 0.09, i.e. no steering. The plant foot's offset from the line then was -1.01 x (the penultimate toe's gap error) - 0.02
(residual sd 0.036: the take-off program did not compensate), and the penultimate touchdown's position varies over a full step (1.6 m) from start to start: the stride pattern's phase at 44 m does (the k-th
touchdown's position has sd 0.4-0.7 m from the second step on; the first foot is left on 28 of 49 starts, right on 21). On 32 fresh starts that was 13 legal, mean 1.58 m. The hip-nudge steering
(`j_st_w` 0.5, `j_st_max` 0.25, `j_st_n` 5) holds the penultimate gap to sd 0.13-0.17 m; its price is a stumble in 1-3 % of starts. Two things about it: a request to LENGTHEN the next step comes out as a
shorter one (arena starts 404 and 416: plan 1.83 m against a stride of 1.65, step 1.45 m: a forward reach makes the foot touch down early), shortening works, so the starts that need lengthening ended with the
penultimate touchdown 0.2-0.5 m too far from the line and no program takes those; `j_st_rnd` 0.75 rounds the number of steps left up, so the plan shortens instead (gap errors on 80 starts -0.38..+0.18 against -0.34..+0.32).
Options that did not steer: hop height (`j_st_zk`), a speed clamp (`g2_v_cap` with `g2_k_brake`), gentler or longer horizons (`j_st_n` 7-10, caps 0.1-0.15), larger caps. Other steering settings give more invalid or
foul starts (125 captured approaches each, fixed program, legal mean: 3.2-3.8 m against 4.0 m for the chosen one).

**Take-off program (`j_ik` from the penultimate touchdown; `long_jump_limits.py robust`).** The program is trained over captured approach states (board-relative ballistic distance, fouls and invalid take-offs
penalised), and the gap knots let it place the plant foot whatever the penultimate gap: on 125 captured approaches its plant offset is -0.05 m with sd 0.05 against a gap sd of 0.15 (slope -0.04..-0.26, was -1).
Two lessons. (1) The approach decides whether one program is enough. With the natural run (torso servo only after the penultimate touchdown, 6.81 m/s over the last 5 m) 9 of 20 training starts were invalid:
all the fast ones (COM 6.9-7.1 m/s at the penultimate touchdown, gap 1.64-1.79 m: the plant comes 0.07 s early, the free leg is still down and its toes touch the runway 0.03-0.05 s after the take-off). With the upright final
approach (torso servo over the last 12.6 m, 6.60 m/s) all 20 were valid. The upright approach costs 0.2 m/s and is what a single program can be robust to. (2) Training on both plant sides (mirrored role tables) and on a
gap-stratified set (32 of the 125 approaches captured from seeds 8001-8128) took the held-out harness score to 86 valid of 93 (3 fouls), mean 4.39 m board-relative. The price of one program (the first robust program on its nominal start): it takes off with vz 2.4 m/s where
its own ideal has 3.1 (harness 4.13 m against 4.86 m), and the fast short-gap starts (gap 1.6-1.8 m, COM 6.7-6.9 m/s) get vz 1.4-1.8 m/s: keeping the foot behind the line from a short gap takes a shorter plant step. The harness predicts the
full rollouts start by start (the harness-invalid starts of the 16 arena starts are the fell-in-run ones; the valid ones jump within -0.1..+0.3 m of their harness distance).
What did not work: interpolating two ideals (nominal and short gap) into a linear-in-gap program (the short-gap ideal from the foot-based search put the foot 0.45 m over the line, the board-relative one stopped at 3.1 m); a swing-foot lag feedback by
greedy selection (the v3 recipe: the invalid count did not fall); a chunk take-off as a fallback for the invalid starts (1 of 12 legal).

**Landing.** The landing program (`il_*`, excitation knots on the ballistic-time clock `il_tg`) was learned on 62 hand-overs (32 starts and a variant each), then 30 generations over all 117 valid hand-overs of the captured approaches, both sides: the
chunk landing rolls over on every short-flight hand-over (vz 1.4-1.9 m/s), the table lands 114-116 of the 117 (marks 4.2-4.9 m from the line in the harness). It took the legal count on 96 fresh starts from 60 to 72 (the take-off unchanged).

**Arena** (all promotions paired; `long_jump_v4_p95_robust96` is new: 96 fresh starts, seeds 9033-9128, seeded with round 2's champion). ORACLE-class programs throughout:

| trial | body | before | champion now | verdict |
| --- | --- | --- | --- | --- |
| `long_jump_v4_p95` (1 start) | v4 P95 | 4.945 m | **5.209 m** (feet mark, ballistic 5.035, foot 0.07 m behind the line) | promoted three times: 5.065 (this start's ideal-control program, chunk landing: head mark), 5.166 (+ a learned landing table), 5.209 (a board-relative ideal, chunk landing); overfit to the start by construction |
| `long_jump_v4_p95_robust` (16) | v4 P95 | 2.145 m (9 legal) | **3.412 m**, 12 of 16 legal (`params/long_jump_v4_gear_final1.txt`) | +1.27, p = 0.047 |
| `long_jump_v4_p95_robust32` (32 fresh) | v4 P95 | 2.851 m (25 legal) | **4.501 m**, 31 of 32 legal (`final1`) | 3.923 (milestone M1, p = 0.005), then 4.501 (+0.58, p = 0.002) |
| `long_jump_v4_p95_robust96` (96 fresh, new) | v4 P95 | 2.536 m (baseline) | **3.724 m**, 77 of 96 legal (`params/long_jump_v4_gear_final2.txt`) | 3.471 (M1, p < 0.001), then 3.724 (+0.25, p = 0.039); `final1` scored 3.659 there (p = 0.14) |

Controller for all of them: `bin/challengers/long_jump_run-c3` (skill build c3; the arena froze copies under `bin/champions/`). `arena.py recheck` reproduces every long-jump champion, per seed, with its frozen binary.

**Per start** (official mark in m; a failed jump scores 0; the class of each failure). `final1`, the 16 arena starts (12 legal, mean 3.412; mean of the legal 4.549, 4.10-4.84):
401 4.25; 402 4.68; 403 4.59; 404 fell in the run; 405 4.84; 406 4.53; 407 somersault; 408 4.77; 409 foul (27 mm); 410 4.61; 411 4.75; 412 4.10; 413 4.48; 414 4.63; 415 4.35; 416 somersault.
`final1`, the 32 fresh starts (31 legal, mean 4.501; legal mean 4.646, 3.91-4.86): 9001 4.38; 9002 4.50; 9003 4.84; 9004 4.79; 9005 4.74; 9006 4.37; 9007 4.46; 9008 4.68; 9009 4.86; 9010 somersault; 9011 4.85; 9012 4.74; 9013 4.62;
9014 4.58; 9015 4.85; 9016 4.69; 9017 4.60; 9018 4.86; 9019 4.75; 9020 4.80; 9021 4.07; 9022 4.54; 9023 4.75; 9024 4.82; 9025 4.58; 9026 4.82; 9027 4.58; 9028 4.65; 9029 3.91; 9030 4.81; 9031 4.72; 9032 4.81.
The 96 fresh starts with `final2` (seeds 9033-9128): 77 legal, mean 3.724, legal mean 4.643; the 19 failures are 11 fell in the run (9033, 9045, 9047, 9054, 9055, 9058, 9060, 9086, 9105, 9119, 9128), 6 somersaults (9064, 9065, 9083, 9093, 9098, 9112) and 2 fouls (9075, 9126). Every start of `final1` on the 16, 32 and 96
is in `out/long_jump_run/round3_final1_per_start.txt`, of `final2` in `round3_final2_per_start.txt` (same directory).
More fresh starts (`final1` with the 0.03 shift; the aim shift of `final2` was chosen on the first set, the others were not used in the choice): seeds 7001-7096: 3.726 m (79 legal: fell in run 12, somersault 4, foul 1) with `final1`, 3.958 (83 legal) with `final2`;
seeds 9129-9224: 4.050 (84 legal: fell 7, foul 2, somersault 3) with `final1`, **4.230 (87 legal: fell 6, somersault 3; legal median 4.70 m, 10th percentile 4.30, best 4.90)** with `final2`.
`final2` pooled over the 336 starts above: 3.97 m (`final1`: 3.86).
The aim shift itself is within noise. Paired over the same starts `final2` beats `final1` by +0.11 m on all 336 (p = 0.12) and by +0.06 m on the 240 starts not used to choose it (p = 0.44); per set: 16 arena starts
2.887 against 3.412 (starts 406 and 415 fail), 32: 4.514 against 4.501 (p = 0.32 in the arena), 96: 3.724 against 3.659 (p = 0.54), 7001-7096 (where the shift was chosen) +0.23, 9129-9224 +0.18 (p = 0.13). `final2` is the 96 champion because it beat
the previous champion M1 where `final1` did not (p = 0.039 against 0.14); `final1` stays the 16 and 32 champion. `ik_fmin 1.5` (the plant-touchdown latch at 1.5 body weights that round 2's v3 champion has; `params/long_jump_v4_gear_final3.txt` = `final2` + it)
changes 12 of 288 fresh starts, 8 of them for the better: +0.04 m on each of 7001-7096 and 9129-9224, +0.13 on the arena 96 (80 legal, p = 0.12), nothing on the 16 and 32. Not significant, not adopted.

**480 never-used starts** (seeds 10001-10480, controller c3, nothing was chosen on them; `scratchpad/lj2/big_eval.sh`, per-start files `scratchpad/lj2/eval_big_*.json`):

| params | mean (95 % CI) | legal | fell in the run | somersault | foul | legal marks: median, 10th-90th percentile, best |
| --- | --- | --- | --- | --- | --- | --- |
| `final2` (96 champion) | 4.001 +- 0.144 m | 415 (86.5 %) | 54 | 10 | 1 | 4.70 m, 4.38-4.83, 4.92 |
| `final1` (16 and 32 champion) | 3.956 +- 0.146 m | 411 (85.6 %) | 49 | 17 | 3 | 4.68 m, 4.34-4.82, 4.93 |
| `final3` (`final2` + `ik_fmin 1.5`, not adopted) | 4.026 +- 0.140 m | 419 (87.3 %) | 45 | 15 | 1 | 4.70 m, 4.37-4.83, 4.92 |
| `final1` without the check-mark shift (`j_board_shift 1.11`, `ik_gap0 1.847`) | 3.603 +- 0.175 m | 371 (77.3 %) | 47 | 14 | 48 | 4.73 m, 4.40-4.86, 4.95 |

Paired: `final2` against `final1` +0.045 m (p = 0.42), `final3` against `final2` +0.025 m (16 starts differ, p = 0.10): the aim shift and the latch are noise at this sample size. The 0.03 m check-mark shift is not: +0.353 m (`final1` against no shift, p < 0.0001; 48 fouls become 3,
the legal marks give up 0.04 m). **This is the number to quote for the robust jump: a mean of 4.0 m over fresh starts, 86.5 % of them legal; the legal jumps have median 4.70 m (95 % of the untrained man's mean) and reach 4.92 m; 11 % of the starts fall in the run and 2 % somersault.**
If the fell-in-run starts jumped like the rest the mean would be the legal mean, 4.63 m.

**What limits the jump, and what would change it.**
- *Speed at the board.* The jump reaches 6.6 m/s over the last 5 m (6.83 m/s if it did not have to straighten up). Each 1 m/s is worth 0.5-0.6 m of ballistic distance at the ceiling (the what-ifs above; round 2's fit says
  D = 0.88 v t_air + 0.52 m), so the 7.3 m/s that 5.5 m needs is 0.7 m/s away, and the 8.2-9.0 m/s of the high-school state level (6.07-6.65 m) is 1.6-2.4 m/s away. A longer run-up helps slowly: the runner adds
  about 0.1 m/s per 5 m from 45 to 55 m and 0.05 beyond (7.05 m/s at 50 m, 7.25 at 65 m), i.e. about +0.05 m of ideal jump per 5 m; the runway rule allows 45 m. The sprint agent's later gears (7.86 / 7.91 m/s) start at 7.0 m/s and are never used in 44 m; what would move the
  jump is a gear for the 3-7 m/s range (an acceleration gear), not a fourth gear.
- *The approach state.* The steered penultimate touchdown has a gap sd of 0.15 m; the starts with a late stride phase (COM low, trunk forward, swing foot far behind; step lengths of 1.0-1.4 m where the run has 1.5 m; five of the
  eight invalid captured approaches have their last three steering nudges pinned at the 0.25 m cap) cannot take off with any program: they are the 6-11 % of fresh starts (per 96) that fall in the run (the same starts do not fall in an unsteered
  approach, and a chunk take-off saves 1 of 12 of them). More steering authority (caps 0.30-0.40), other gains, rounding 0.9-1.0 all make it worse. One open lever: a one-step longer horizon (`j_st_n` 6 instead of 5) cuts the stumbles
  from 26 to 9 of 288 fresh starts with the frozen programs (per 96: 9 to 3, 11 to 3, 6 to 3), but its penultimate gaps spread wider (sd 0.24 m against 0.16) and 0.03 m shorter, so the frozen take-off fouls (29 of 125 in the harness) and,
  retrained on its states (`params/long_jump_v4_gear_n6_d03.txt`, `_d06.txt`: fouls gone, stumbles 4-6 of 96), the frozen landing table somersaults on 20 of 96 (3.39 m against 3.96 on 7001-7096). The landing table needs retraining on those hand-overs
  (about 1.5 h) before the horizon can pay; not done. Longer horizons (7, 8, 10) only add falls (17, 29, 43 of 96).
- *One program for all starts.* On the nominal start the robust program takes off with vz 2.4 m/s where its own ideal has 3.1 (harness 4.13 against 4.86 m); the short-gap fast starts get vz 1.4-1.8. The legal jumps of the 336 starts above
  are 4.07-4.90 m, median 4.66-4.70 m; the ideal for one start is 5.0-5.2 m. Per-gap programs (two tables selected by the gap) would be the next step.
- *Take-off and landing.* Contact 0.09-0.11 s. The robust take-offs leave at 18-21 deg with vz 2.1-2.4 m/s on average (harness range 1.4-2.8), the one-start jumps at 26-29 deg with vz 3.0-3.3 (a human jumper: 20-23 deg, 3.0-3.7 m/s). The landing marks 0.12-0.17 m beyond the ballistic point on the one-start jumps; the table removes most somersaults of the robust ones.
- *Body.* At the ceiling a 20 % stronger body jumps 0.4 m farther and a 40 % stronger one 0.9 m (at the same 6.6 m/s): strength and speed are worth about the same per percent, and neither reaches 6 m (next paragraph).

**What a stronger body or a longer run-up would change** (ideal-control what-ifs, ORACLE-class, one start: the nominal penultimate-touchdown state of the upright approach, 60k evaluations of the open-loop 32-muscle program from the same initial guess,
ballistic distance from the take-off foot; `ROBOLAB_LJ_FSCALE` scales every muscle's peak isometric force, `ROBOLAB_LJ_DV` adds forward speed to the whole body at the penultimate touchdown):

| what-if | ballistic distance | against the base | take-off vz |
| --- | --- | --- | --- |
| base (COM 6.6 m/s) | 5.03 m | | 2.70 m/s |
| +0.4 m/s | 5.22 m | +0.19 m | 3.09 |
| +0.8 m/s | 5.52 m | +0.48 m | 3.18 |
| muscles 20 % stronger | 5.43 m | +0.39 m | 3.31 |
| muscles 40 % stronger | 5.91 m | +0.88 m | 3.57 |
| run-up 65 m instead of 44 m (the plain run gains about 0.35 m/s, 6.9 to 7.25 m/s; not run through the take-off) | about 5.2 m | about +0.2 m | |

A 20 % stronger body is worth about 0.8 m/s of extra speed (+0.39 m against +0.48 m), and it spends the strength on vertical velocity at the same horizontal speed (vz 2.7 to 3.3 m/s): the model's weak point at the take-off is lift, not speed.
A longer run-up buys little: a standard runway offers 45 m (TR 29.1: at least 40 m, 45 m where conditions permit), the runner adds 0.05-0.1 m/s per 5 m beyond 45 m, and its fast gears never engage (an acceleration gear for 3-7 m/s
would move the jump; a fourth gear would not). Neither lever alone gets the ideal past 6 m (the best case here, 40 % more force, is 5.9 m for one start), and none of these numbers is a robust one: the robust take-off program reaches about 90-94 % of
its ideal's distance on the starts that succeed (legal median 4.66-4.70 m against 5.0-5.2 m) and loses the failed starts on top, and it was trained for this body and this speed, so a stronger or faster body would need the take-off and landing programs retrained before any of this shows up in a fresh-start mean.

**Against humans** (men; sources as in round 1):

| level | distance | this model |
| --- | --- | --- |
| untrained man | 4.95 +- 0.55 m | one start (ORACLE, overfit): 5.209 m = 105 %; robust: the legal jumps of fresh starts have median 4.66-4.70 m (94-95 %) but 9-20 % of starts fail (13.5 % on the 480 never-used starts), so the mean over fresh starts is 4.0 m (81 %; 3.7-4.2 m per 96) |
| high-school state qualifying | 6.07-6.65 m from 8.9 m/s | not reached: 6.1 m needs 8.2-9.0 m/s at the board, the model has 6.6-6.9 |
| NCAA D1 finals median, world record | 7.56-7.75 m, 8.95 m | not reached |

The jump does not go beyond human ability. The best one-start jump is 0.26 m past the untrained man's mean (0.5 sd); the honest robust number is a mean of 4.0 m over fresh starts (81 % of the untrained man's mean): 4.70 m (95 %) when a start succeeds, and about 1 start in 7 fails. The ceiling for this
body at this speed is 5.0-5.2 m; getting past 5.5 m robustly needs about 0.7 m/s more at the board (or 20 % more strength plus 0.3 m/s), the high-school level needs the speed of a trained jumper.

**What worked:** the gear switch at 5.0 m/s (+0.22 m/s); hip-nudge steering with the plan rounded toward shortening; training the take-off program on both plant sides over a gap-stratified set of captured approaches (mirrored role tables);
the landing table on 117 hand-overs; the 0.03 m check-mark shift (chosen on seeds 7001-7096 that the training never saw: 3.15 -> 3.73 m there; on the 480 never-used starts +0.35 m, p < 0.0001, fouls 48 -> 3) and the aim shift (+0.23 m there, +0.18 on the never-used 9129-9224, but +0.06 over the 240 starts not used to choose it, p = 0.44: within noise); the board-relative ideal for the one-start trial. **What did not:** the natural (non-upright) run for one program (9 of 20
training starts invalid), hop-height steering, speed clamp, more steering authority or other rounding, interpolating two ideals into a linear-in-gap program, greedy swing-foot lag feedback, a chunk take-off fallback, a learned landing table on the board-relative one-start
program (5.167 against the chunk landing's 5.209), the `ik_fmin 1.5` latch (`final3`, not significant), the strength what-if through `ROBOLAB_LJ_STRENGTH` (the v4 jump tasks ignore it).

**Files.** Skill `lib/robolab/skills/long_jump_run.w` (+ `lib/entry/long_jump_run.w`), harness `playground/long_jump_limits.py`. Params: runners `params/lj_runner_gear_v4_p95.txt`, `lj_runner_gear3_v4_p95.txt`, `lj_runner_gear4_v4_p95.txt`;
one start `params/long_jump_v4_gear_nom1.txt` (5.065), `_nom2.txt` (5.166), `_nom3.txt` (5.209, champion), `_nom4.txt` (5.167); robust `params/long_jump_v4_gear_a4_m1.txt` (milestone), `_a4_l60.txt`, `_a4_l2.txt`, `_final1.txt` (16 and 32 champion),
`_final2.txt` (96 champion), `_final3.txt` (`final2` + `ik_fmin 1.5`, not adopted), `_n6_d00.txt` / `_d03.txt` / `_d06.txt` (steering horizon 6 with a retrained take-off, not adopted: somersaults). Pieces: take-off `out/long_jump_limits/rob_a4_final.txt`, landing `scratchpad/lj2/land_a4b_g30.txt`, approach `scratchpad/lj2/A4c.txt`; ideals `out/long_jump_limits/gp_nom_ideal.json`, `gp_nom_bd.json`, `lean_*_ideal.json`, `am_nom_*.json`.
Log with every command: `scratchpad/lj2/LOG.md`; scripts in `scratchpad/lj2/` (`runup.py`, `ikgap.py`, `harness_eval.py`, `eval_all.sh`, `assemble.py`, `capture_set.sh`, `post_robust.sh`, `rob_*.sh`, `land_*.sh`, `whatif*.sh`, `replay_all.py` (replays every long-jump champion's frozen params with the current build and compares per seed: all 17 identical), `replay_round2.py`, `big_eval.sh`, `big_report.py`, `scan_stn.sh` / `rob_a6.sh` / `select_train.py` / `eval_cands.sh` (the steering-horizon experiment)).
Per-start results of every evaluation are in `scratchpad/lj2/eval_*.json` / `.txt` (`long_jump_eval.py`), those of `final1` on the arena trials in `out/long_jump_run/round3_final1_per_start.txt`.

```sh
./build.sh long_jump_run && cp bin/robolab_long_jump_run bin/challengers/long_jump_run-c3
scratchpad/lj2/capture_set.sh scratchpad/lj2/A4c.txt a4 bin/challengers/long_jump_run-c3 8001 8128 4        # penultimate-touchdown states of 128 starts
scratchpad/lj2/rob_a4.sh                                                                                       # robust take-off program over 32 of them (both plant sides)
VARIANTS=1 RECSEED=8039 scratchpad/lj2/post_robust.sh a4 && scratchpad/lj2/land_a4.sh                            # hand-overs, chunk landing record, landing table
.venv/bin/python scratchpad/lj2/assemble.py params/x.txt scratchpad/lj2/A4c.txt out/long_jump_limits/rob_a4_final.txt scratchpad/lj2/land_a4b_g30.txt j_board_shift=1.04 ik_gap0=1.876777
.venv/bin/python playground/arena.py eval long_jump_v4_p95_robust96 --params params/long_jump_v4_gear_final2.txt --controller bin/challengers/long_jump_run-c3 --task long_jump_v4_p95b --workers 4
```

### Long jump past the human record on a LABELLED beyond-human body with an unlimited run-up (30 Sep 2026, agent L3)

Erik's goal: "use the best runner for long jump and then exceed human ability". The best runner is S4's labelled beyond-human sprinter (`playground/profiles/beyond.json`: strength x2.4, muscle speed x2.0, tendon x1.5, activation x0.8; an invented stretch; chain C `params/run_gearx_v4_beyond_c.txt`), which needs about 140 m to reach 10 m/s, so the task's run-up is lengthened to 150 m (`ROBOLAB_LJ_APPROACH`; a 14 m pit). EVERY number here is for that labelled body and run-up and is never to be compared with the human-body jump trials (best 5.209 m on one start, about 4.0 m mean on 480 fresh starts). Full report `scratchpad/lj3/REPORT.md`, log `scratchpad/lj3/LOG.md`.

- **Run-up:** 13 of 16 perturbed starts reach the line at 9.5 m/s or more over the last 5 m (mean 9.91 m/s).
- **One start (the nominal start): official 10.848 m, legal**, against 8.95 m (arena trial `long_jump_v4_beyond`; an open-loop 32-muscle program, overfit to that start by construction; frozen controller `bin/challengers/long_jump_run_x-l3b`, skill `lib/robolab/skills/long_jump_run_x.w`, a copy of `long_jump_run.w` with a different base class). The first take-off was a locked-knee strut held by the joint limit (28 BW instantaneous); a yielding knee (20 deg at peak force, 14 BW over 12 ms) gives 10.807 m, and a plant-force cap of 8 BW still gives 9.98 m, so neither is what limits the jump.
- **Robust program (one take-off program for every start), 96 fresh starts never used:** mean 5.644 m, 69 of 96 legal (71.9%), legal median 7.89 m, best 9.28 m, and 8 legal jumps (8.3% of starts) above 8.95 m (trial `long_jump_v4_beyond_robust96`); 16 perturbed starts: mean 5.660 m. The failures are the runner's own falls and the steering's stumbles (17 of 96), 7 fouls and 2 somersaults.
- **What drives it:** approach speed about 1.1 m per m/s (the 150 m run-up is worth about 2.8 m over a 44 m one), strength about 0.5 m per 0.1 of the strength factor (P95-level strength with the same 10 m/s approach still gives 8.4 m): the jump is speed-limited.
- **Verified:** `arena.py recheck` reproduces the three trials per seed; the human-body champion still replays 5.209 m through the new controller; the shared skill files are unchanged. The tasks set `profile = "beyond"` in the class because `LongJumpP95Task` hard-codes `profile = "p95"` and an explicit profile beats `ROBOLAB_PROFILE`.

**Round 2 (1 Oct 2026, agent L4): the robust program re-trained on S5's fall-reduced runner.** Same labelled body and run-up. L3's take-off and landing tables were tied to chain D's approach states, whose runner falls on 15-20% of starts; L4 (`scratchpad/lj4/LOG.md`, section FINAL STATE) rebuilt them on S5's chain F1 (skill `lib/robolab/skills/long_jump_run_y.w`, a copy of `long_jump_run.w` with base class `RunGearYSkill`; entry `lib/entry/long_jump_run_y.w`; frozen controller `bin/challengers/long_jump_run_y-l4b`; final params `params/long_jump_beyond_rob2.txt`), with a steering re-tuned for F1 (gap stumbles 18.8% to about 2%).

| 96 fresh test starts 10001-10096 | mean | legal | legal jumps above 8.95 m |
| --- | --- | --- | --- |
| L3's robust program (chain D) | 5.644 m | 69 of 96 (71.9%) | 8 |
| L4's champion (F1 runner, `rob2`) | 7.075 m | 87 of 96 (90.6%) | 2 |

- **Checked on starts nobody had used:** L4 on 400 seeds (11001-11400): 6.874 m, 88.5% legal against 4.959 m, 62.8% for L3's program (paired +1.915 m, SE 0.241); my own check on 96 seeds (21001-21096): 6.551 m, 85.4% legal against 5.030 m, 63.5% (paired +1.521 m, SE 0.499); `arena.py recheck` reproduces all three beyond trials exactly (`long_jump_v4_beyond_robust96` is now L4's, promoted by the arena's paired test, p 0.001; the 16-start trial was not promoted, p 0.065).
- **The trade-off to be honest about:** the mean and the legal fraction rose but the jumps above the record did not (2 of 96 against 8; 1.0% against 4.8% of 400 seeds), because F1 arrives about 0.2 m/s slower at the line (about -0.2 m on every jump) and the robust training spends the upper tail on legality. The legal mean is 7.8 m against 10.85 m for the one-start program.
- **What limits it:** failures cost about 0.9 m (runner falls 3.3%, steering stumbles about 2%, collapsed take-offs about 2%, somersaults 2%, fouls 1-2%); one fixed open-loop program cannot follow the chaotic per-state optimum; the take-off foot lands 0.40 +- 0.16 m behind the line; the landing loses 0.2-0.4 m.
- **What did not help (M3):** a program set chosen at the plant by gap or plant side (the per-state difference between two good programs is not predictable from what the planner measures, |corr| 0.12 at most; even a perfect selector adds +0.22 in the harness), per-regime offsets by plant-touchdown time (+0.007), swing-foot lag feedback (+0.04, not adopted). Next, by L4's list: a take-off with feedback instead of tables, a runner that arrives at 10 m/s with F1's fall rate, a landing that does not fall back, more captured states per update.

**Round 3 (3-4 Oct 2026, agent L6): the record in a six-attempt competition.** Same labelled body, run-up and rules. Athletics counts the BEST legal mark of the attempts, six in a final,
while L3's and L4's programs were trained for the MEAN mark. From L4's 400 never-used starts (resampling six starts without replacement) P(best of six legal marks > 8.95 m) was 5.7% for L4's C7 and 25.5% for L3's
champion; for the median competition to beat the record a program needs about 11% per attempt (1 - (1 - p)^6 >= 0.5). L6 (`scratchpad/lj6/LOG.md`, section FINAL STATE; the metric is `scratchpad/lj6/bo6.py`:
exact order statistics plus a bootstrap over starts, fixed before any run) trained for that. The candidate K3 is a params file on L4's frozen controller (`scratchpad/lj6/params/long_jump_beyond_bo6a.txt`,
`bin/challengers/long_jump_run_y-l6a`, a byte copy of `-l4b`: no new build and no new skill key, so C7 replays identically), made of four parts in the order of their effect:

1. a faster runner, H011 = F1's start with chain D's gears 2 and 3 and the SB2 steering (9.92 m/s over the last 5 m against F1's 9.77; 15% of starts fall before the line against F1's 7.5%: under the best-of-six rule a fall costs one attempt, not the competition);
2. a risk-seeking take-off: L4's R3 retrained for 70 generations of mini-batch CMA on 1291 captured penultimate-touchdown states with a success-count objective (a smoothed count of states whose harness take-off distance beats 8.735 m, a convex reward above 7.8 m, failed starts scored 0, L4's somersault penalties, 20 BW plant-force cap and `fmin` kept): the whole take-off distance distribution of held-out states moves by +0.2 m, worth a factor 2.3 in the count above the bar;
3. a joint board shift of 0.10 m (the whole plan 0.10 m closer to the line, the program's gap input unchanged; a planner-only shift gains nothing, a joint shift above 0.10 buys 2-3 times more fouls than distance);
4. L4's landing table unchanged (a retrained landing, K4, gave +2.6 points of best of six for -4 points of legal fraction: a variant, not adopted).

| 480 starts per set; best of six > 8.95 m [95% interval] / legal / per attempt > 8.95 m / mean mark | K3 (L6) | C7 (L4) | L3's champion |
| --- | --- | --- | --- |
| CONFIRMATION 32001-32480 | **64.7%** [55.3, 72.3] / 73.3% / 15.8% / 6.00 m | 9.6% / 89.4% / 1.7% / 6.94 m | 25.6% / 64.0% / 4.8% / 5.05 m |
| TEST 33001-33480, run once | **60.8%** [51.3, 68.7] / 74.4% / 14.4% / 6.02 m | 7.3% / 87.7% / 1.3% / 6.73 m | 14.2% / 60.6% / 2.5% / 4.75 m |
| 960 further seeds 37001-37960 | **66.1%** [60.1, 71.8] / 74.1% / 16.5% / 6.05 m | | |
| MY OWN CHECK, 480 starts nobody had used (41001-41480) | **60.2%** [51.3, 68.7] / 76.7% / 14.2% / 6.21 m | 11.1% [4.9, 18.5] / 91.0% / 1.9% / 7.04 m | |

Pooled over the three unbiased sets (1920 starts) K3: 64.4% [59.8, 68.2], median best-of-six mark 9.08 m, mean 8.99 m, legal 74.0%, per attempt 15.8%; P(best of k legal marks > 8.95 m) for k = 1 ... 6:
15.8, 29.1, 40.3, 49.7, 57.7, 64.4%. On my seeds the paired differences K3 minus C7: best of six **+49.4 points** [+37.7, +60.0], per attempt +12.3 points [+9.0, +15.6], mean mark -0.83 m [-1.18, -0.47], legal fraction -14.4 points.
The pass rule (at least 50% on confirmation and on TEST, with at least 50% legal) is MET; the stretch (70%, which needs about 18% per attempt) is not. Ladder on the selection set (best of six): C7 9.6% -> joint shift 0.10 19.5% ->
chain D's runner with C7's tables 28.5% (H011 19.5%) -> H011 + a 10-generation risk-seeking take-off + shift 44.8% -> 70 generations 63.6%.

**The trade to be honest about.** This is not a better jumper by the mean: the mean official mark falls from 7.0 to 6.0 m and the legal fraction from 91% to 74% (17% of attempts never reach the take-off: 7.4% runner falls between
20 and 140 m, 9.9% steering stumbles or collapsed take-offs within 12 m of the line; fouls 4.4%, somersaults 5.4%). It is the better competitor under the rule that counts the best of six: the median competition ends at 9.08 m,
0.13 m past the record, on a LABELLED beyond-human body with a 151 m run-up (the human record is set after about 40 m). Of the legal jumps 20.6% pass 8.95 m (legal median 8.35 m, p90 9.15 m, longest 9.6 m); the human-body trials are untouched.
**Arena.** The mean-mark trial `long_jump_v4_beyond_robust96` scores K3 below C7 (-1.21 m, p 0.997: a read-only test, not promoted), as expected, and C7 keeps the mean-mark trials. A new trial `long_jump_v4_beyond_record480` (the 480 seeds 41001-41480 of my check; metric `record_beaten`, 1 for a legal jump past 8.95 m, a key the task `long_jump_v4_beyond_a` gained; `scratchpad/lj6/add_record_trial.py`; no existing trial was touched) was seeded with C7 (0.0187) and **K3 won it (0.1417 +- 0.031, paired +0.123, p < 0.001) and is its champion** (`bin/champions/long_jump_v4_beyond_record480-*`); for independent attempts the trial's mean p is the number the competition rates are made of, 1 - (1 - p)^6.

Two things L6 disclosed: the runner was chosen by a harness surrogate calibrated on paired pools (H011 over the pure chain D variant D7), against its own pre-declared rule (D7 28.5% against H011 19.5% on the selection set), and a planned extra
evaluation set overlapped a training pool and was replaced before it ran (the extra set is 37001-37960). **What did not help:** the planner-only shift, a joint shift above 0.10 (D7 28.5 / 32.2 / 30.4% at 0 / 0.10 / 0.20, fouls 9 / 26 / 65), global
knobs on R3 (it is a sharp optimum), a runner extrapolated beyond chain D (more falls, no speed), chain D's top gear alone on F1's start (slower, 9.56 m/s), the retrained landing, and a 260-state training set (overfit within 20 generations; 1291 states did not).
**What limits it, and next:** reach (the 17%), fouls and somersaults, the plant foot's authority (the plant step follows the penultimate gap with a slope of -0.86), a saturated landing search (+0.07 m in 20 generations). Next: a steering retuned
for the faster runner (its gap sd is 0.17 against F1's 0.14, worth 2-3 points), a handover that keeps chain D's speed with F1's stability, a state-dependent landing, a plant step with feedback instead of tables.
Files: params `scratchpad/lj6/params/{long_jump_beyond_bo6a,TO1_risk_takeoff,runner_H011_SB2}.txt`, tools `scratchpad/lj6/` (`bo6.py`, `ljx_risk.py`, `mkrunner2.py`, `avgprog.py`, `arena_check.py`, `add_record_trial.py`), evaluations and pools `out/lj6/`, `out/long_jump_limits/`.

**Round 4 (4 Oct 2026, agent L7): steering precision, not risk.** L6's FINAL STATE found that the plant toe's offset sd (0.16 m) is the penultimate gap's own sd (0.17 m, the plant foot barely follows the gap), so the plan had to stay 0.10 m
behind the foul cliff. L7 (`scratchpad/lj7/LOG.md`, section FINAL STATE) cut the gap sd instead. One new opt-in key in `lib/robolab/skills/long_jump_run_y.w` (`j_nat 1`, 24 changed lines): at toe-off the run-up planner predicts the natural length of
the step that is about to land from the COM velocity there (step = c0 + cx vx + cz vz; residual 0.067 m against 0.117 m for the running-average step the planner used before; fitted on 96 seeds, tested on 160 others), and the landing leg's nudge corrects
the plan against that prediction. What remains is the flight duration (sd 16 ms), which the foot's descent does not predict better, so in-flight feedback would not help. Candidate l7a = K3 + `j_nat 1` + steering weight 0.75 + a joint board shift of 0.15 m
(`scratchpad/lj7/params/long_jump_beyond_l7a.txt`, controller `bin/challengers/long_jump_run_y-l7a`); K3 and C7 replay bit-identically through the new build with the key absent. The gap sd falls from 0.174 to 0.071 m (384 steering-scan seeds; 0.089
including outliers on 1000 fresh seeds; 1.6% more starts without a plant flight), the legal take-off toe sd from 0.155 to 0.12 m, and the best joint shift moves from 0.10 to 0.15 m. Ladder on the selection set (best of six): K3 62.5% -> `j_nat` at the same shift 72.7%
-> shift 0.15 77.1% -> steering weight 0.75 **80.2%**.

| 480 starts per set; best of six > 8.95 m [95% interval] | l7a (L7) | K3 (L6) |
| --- | --- | --- |
| SELECTION 61001-61480 (the choice set) | 80.2% [74.0, 85.7] | 62.5% |
| CONFIRMATION 62001-62480 | **84.4%** [78.9, 88.8] | 72.3% |
| TEST 63001-63480, opened once | **81.2%** [74.8, 86.1] | 69.2% |
| EXTRA 67001-67960 (960 starts) | **80.1%** [75.7, 84.0] | 62.9% |
| MY OWN CHECK, 480 starts nobody had used (71001-71480) | **79.2%** [72.3, 84.9] | 62.5% [52.7, 70.1] |

Pooled over the three unbiased sets (1920 starts) l7a: 81.4% [78.3, 84.0], legal 77.7%, per attempt 24.4%, mean mark 6.52 m, median best-of-six mark 9.21 m (P(best of six > 9.20 m) 49.8%); K3: 66.9% [62.5, 70.6], legal 73.0%, per attempt 16.8%, mean 5.98 m. Paired l7a minus K3: confirmation + TEST (960 starts)
+12.07 points [+5.66, +18.09]; on my seeds best of six **+16.7 points** [+7.0, +26.8], per attempt +7.9 points [+3.3, +12.5] (22.9% against 15.0%), mean mark **+0.65 m** [+0.30, +1.02], legal fraction +5.8 points [+1.5, +10.2] (78.3% against 72.5%). The pass rule (at least 70% on confirmation and TEST each,
at least 50% legal, +5 points paired with the interval above zero) is MET and so is the stretch (at least 80% on both). **The trade of round 3 is gone:** this is a precision gain, not a risk trade, so the legal fraction and the mean mark rise together (6.5 m against K3's 6.0 m; C7, trained for the
mean mark, still has 6.7-7.0 m, so it keeps the mean-mark trials). Arena: `long_jump_v4_beyond_record480` PROMOTED, `record_beaten` 0.2521 +- 0.039 against K3's 0.1417 (paired +0.110, p < 0.001). L7's own `arena.py recheck` reproduces the champion exactly (stored 0.2521, now 0.2521); my own recheck of the four beyond long-jump trials reproduces them exactly as well (0.2521, 7.0750, 10.8480, 5.6600; `out/lj7/recheck_lj.log`).

**Not adopted:** a take-off retrained on the new pool of 861 states (+0.4 points of surrogate on 439 held-out states, noise +-0.7, legal -4 points: TO1 is on its plateau); runner and gear variants (the mid-run falls are forward pitch falls of chain D's gear 2, 0.5-12 s after the gear 1 to 2 switch, and every variant trades speed for falls at a loss:
blending halfway removes 13 falls but costs 0.059 m/s, about -24% of the count against +4%); the K4 landing (+3.0 points on selection, +0.5 on confirmation, -5 points of legal fraction, somersaults 17 -> 42: the pre-declared rule is not met); a feed-forward of the penultimate state into the program's gap input
(harness only: +1.0-1.3 points of surrogate, about +2 points of best of six); steering variants (more steps, caps, weights, randomisation, windows) beat nothing over `j_nat`. **What limits it now:** reach 83.8% (16.2% of attempts never take off: 8.3% mid-run falls in gear 2, 7.6% within 12 m of the line), fouls 3.1%,
somersaults 3.0%; 29.1% of the take-offs pass the record and 31.4% of the legal jumps (legal median 8.65 m, p90 9.28 m, longest 9.80 m); the legal toe sits 0.253 +- 0.123 m behind the line, and each +0.1 m of take-off distance is worth about x1.5 in the count above the bar. Next: the feed-forward as a key with a take-off retrained
with it, gear-2 stability of the runner at unchanged speed, a plant-flight predictor at the penultimate toe-off (the plant step's timing noise, about 0.09 m, is now the largest toe-offset term), a landing that keeps K4's tail without its somersaults. Disclosures by L7: the steering was developed on the steering-scan seeds 65001-65384 (the gap-sd target
re-measured on 1000 pool seeds); selection chose the steering weight, the shift and the runner / retrain / K4 decisions; confirmation saw three programs (an intermediate 82.7%, l7a 84.4%, K4 84.9%); TEST was opened once for l7a and once for K3 after the candidate was fixed. Files: params `scratchpad/lj7/params/{long_jump_beyond_l7a,approach_nat_w75}.txt`,
tools `scratchpad/lj7/` (`natfit.py`, `steppred*.py`, `falltrace.py`, `ffcoef.py`, `ffeval.py`, `train7.sh`, `mkapp7.py`), evaluations and pools `out/lj7/`, `out/long_jump_limits/`; the working binary `bin/robolab_long_jump_run_y` is now the l7a build (the previous one, = l4b, is `out/lj7/robolab_long_jump_run_y.pre_l7`).

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

**Sprinters on v4** (trials `sprint_top_speed_v4`, `_v4_p95`, `_v4_elite2`; the old trials and champions are untouched). Practice task
`sprint_touch_v4` (objective 2 or the flying-start pace objective 3), controllers `RunRISkill` and, for the final entries, `RunGearSkill`
(`lib/robolab/skills/run_gear.w`). Ceilings are the pitch-free ideal-control ceilings above (8.2 / 10.45 / 9.28 m/s). P95 and elite2 are the
literature profiles (`profiles/p95.json`, `elite2.json`); no result of the unverified `elite.json` profile is reported here. The run-by-run log is
`scratchpad/sprint_knot/LOG.md`.

**Arena** (12 perturbed standing starts, 30 s, a fall scores -1e9; validation = 40 further unseen starts, seeds 141-180, and 40 more, 181-220, never trained on):

| trial | champion (params, controller) | peak 1 s speed | starts surviving | share of the ceiling | unseen seeds: falls in 40 + 40 |
| --- | --- | --- | --- | --- | --- |
| `sprint_top_speed_v4` (8.2) | `params/run_gear_v4_avg_c.txt`, RunGear, 3 gears | **6.170 +- 0.003** | 12/12 | 75.2 % | 0 + 5 (4 of them at 5-7 s) |
| `sprint_top_speed_v4_p95` (10.45) | `params/run_gear_v4_p95_g.txt`, RunGear, 4 gears | **7.907 +- 0.019** | 12/12 | 75.7 % | 2 + 1 (the 3-gear `_e`: 1 + 1) |
| `sprint_top_speed_v4_elite2` (9.28) | `params/run_gear_v4_elite2_c.txt`, RunGear, 3 gears | **6.78** | 11/12 (seed 231 falls) | 73.1 % | 1 + 2 |

Every entry (eleven promotions, one loss; `playground/arena/history.jsonl`; all paired tests p <= 0.001 except the loss):

| stage (share of the ceiling) | average body | P95 body | elite2 body |
| --- | --- | --- | --- |
| the v3 champions' params on v4 | fall (0/12) | fall (0/12) | fall (0/12) |
| first v4 search (RunRI from the v3 params) | v4s1 3.92 (48 %), v4s2 4.68 (57 %), **v4r1 4.65 (56.7 %, entered, 11/12)** | p1: 6.60 at 1500 rollouts (63 %), 7.05 at 2400 (67.5 %; 17/24 seeds survive) | e1 (from the average-body gait) 6.42 (69 %; 7/24 falls) |
| + start plan v0 2.0, foot clearance | a2 (from the P95 gait) **5.875 (71.6 %, entered, 11/12)**; a2v 12/12 at 5.873, loses the paired test (p 0.30) | **p2b 7.00 (67 %, entered, 10/12)** | **e1v 6.44 (69 %, entered, 10/12)** |
| two gears | **6.045 (73.7 %, entered, 12/12)** | **7.449 (71.3 %, entered, 12/12)** | **6.61 (71.3 %, entered, 11/12)** |
| three gears | **6.170 (75.2 %, entered, 12/12)** | **7.862 (75.2 %, entered, 12/12)** | **6.78 (73.1 %, entered, 11/12)** |
| four gears | - | **7.907 (75.7 %, entered, 12/12)**; the first four-gear search (4 falls in 40) was not entered, the 19-seed-cascade one was | - |

**What the searches found.**

- *The v3 params fall on v4, and the first v4 gait is a dead end.* Started from the v3 average-body params, sep-CMA (v4s1, v4s2, v4r1: 6600 rollouts) ends in a straight-leg
  pogo (touchdown knee 0.14, peak 0.14 rad; 60 % of the vertical impulse arrives in the first 35 ms as a 10.6 BW collision, foot vz -2.3 m/s): 4.65 m/s, an isolated basin (almost any
  change falls; objective 5 with the v4 ideal stance moved its score 350.1 -> 351.4 in 7 generations; `knots 1` seeded from the ideal falls). The same search started from the *P95* v4 gait
  (a smooth bent-knee stance, peak vGRF 3.8 BW, found from the v3 P95 champion in 1500 rollouts) reached 5.875 m/s on the average body in 600 rollouts. The lesson is the basin, not the
  budget: try the other bodies' gaits as starts. (The P95 gait is a crouched, ~4 steps/s bounce, knee 0.8-0.9 rad at touchdown, torso upright: not the ideal stance.)
- *Falls are the score, and the falls were three different things* (traced with `scratchpad/sprint_knot/stridetab.py`, `pitchmax.py`, `alt_growth.py`):
  (1) the searched **start plan speed `v0` sits at ~0.25 m/s** (the drives scale with v_des / v_top from the first push, so the start has almost no drive): every searched gait falls in 4-9 s on
  10-25 % of starts, and `v0 = 2.0` (the tunable's box is [0, 2.5]) removes these falls with the stride untouched (average a2: 4/40 -> 0/40; P95 hard seeds 7/8 -> 1/8; elite2 8/8 -> 1/8);
  (2) **swing-foot trips** in the crouched gaits (4 scuffs / s): `clear_h 0.16, k_clear 2, heel_tuck 0.6` at no speed cost; (3) a residual **late fall** (13-30 s) of the ~4 steps/s bounce, a sudden bad step
  after an intermittent period-2 burst of the aerial gaps (15-25 ms against 2-4 ms), not a drift: max torso pitch after 5 s is 0.23-0.38 rad on every surviving seed and crosses 0.6 rad only ~0.05 s before the fall,
  and stride, stance or pitch variability do not predict it. A single-parameter tweak "fixes" a failing seed by chance (any perturbation reshuffles a chaotic outcome): only fresh seeds tell.
- *Search on few seeds overfits.* Hardening a stride on 8-10 mined hard seeds produced gaits that survive those seeds and fall MORE on fresh ones (average 8/30 against 4/40, P95 9/42 against 15/64,
  extended-mode P95 10/40 early falls): at a 20 % hazard, passing 8 seeds is luck 17 % of the time. What works is a long cascade: a candidate stops at its first bad rollout, only low-hazard ones run
  all 12-19 seeds. Gear 2 of the P95 champion trained on 4 seeds fell on 8/40 unseen seeds, on 16 seeds on 2/40.
- *`playground/hsearch.py`* (new, opt-in): scores a candidate by its worst rollout and runs the seeds as a cascade inside one worker (stop at the first score below the incumbent's; a short "gate" horizon per seed,
  `84g10`); a (1+lambda)-ES with sparse mutations, a success-rate step size, one combination of the improving offspring and one extrapolation step per generation (or sep-CMA with restarts around the incumbent).
  sep-CMA stalled on the fragile optima (sigma 0.04 in 94 dimensions is a 0.4 step against ~4 % of a box that breaks ~40 of the parameters); the ES moved 3-5 x faster per rollout. `search.py --box name=lo:hi`
  widens a search box (a skill does not clamp a params-file value; the searched gaits sit on the bounds of t_push_max, k_land, t_land, z_ref, hip_lead, g_kl, a_push, k_late).
- *One parameter set cannot both start and cruise; gears.* A flying start (`RunKnotSkill` `fly_entry 2`: enter the right stance chunk from a snapshot of the champion's own steady running,
  `playground/cache/sprint_touch_run_v4_*.npz`; 8-24 s rollouts, 3-5 x cheaper than a standing start) lets a search tune the cruising gait alone: on P95 it gained 0.5 m/s in 20 minutes
  (6.95 -> 7.46 steady) and that gait falls from a standing start (6/6 at 4 s). **`RunGearSkill`** (opt-in `gears N`; without it RunKnotSkill exactly, checked to the digit): every tunable X has gear twins
  g2_X .. gN_X (default: the previous gear's value) and the first flight after the filtered speed reaches `g<k>_v_on` rebuilds the whole stride (chunks, poses, corrections, reflex gains, reciprocal inhibition)
  from gear k's values; `Track#set_movement` (controller.w, a new method with an SDK spec) swaps the movement under the running track. Gear 1 is the start and the acceleration; each later gear is searched by
  flying-start ES from snapshots of the gear before it (`gear0 K` starts a practice run in gear K). Gear 2 trained on 4 seeds x 8 s exploited its horizon (fell at ~19 s on 6/6); on 16 seeds x 24 s (`fall_pen 300`) it holds.
  The gain per gear on P95 is +0.45, +0.41, +0.05 m/s: the crouched family saturates near 8 m/s.
- *The requested experiments, all opt-in and reported as run.* Objective 5 (above): no gain from the pogo basin. Knots: seeded from the ideal (v4 P95 at 9 m/s, average at 8 m/s) the stance falls (the touchdown knee
  comes out 0.81 for a commanded 0.54); seeded from the gait's own distilled stance (`knot_seeds.py`; the world thigh has to be shifted by the pelvis pitch, -0.25 rad) it runs (6.29 m/s against 6.45, contact 0.176 s
  against 0.124), a start for a knot search that was not run because the gears gained more per hour. Spine trunk servo (`k_sp`, `k_spd` in RunRISkill; the lumbar spine has 200-250 N m, as strong as a hip): small gains change
  nothing measurable, gains from 0.5 break the gait. Residual TCN (`tcn 1`, 63-weight zero head on the P95 four-gear gait, ES over the head from gear-4 flying starts, 12 seeds x 24 s, sigma 0.03 and 0.006): both heads found a candidate
  that survives all 12 training starts (the zero-head baseline fell on one) and neither generalises: on 40 fresh flying starts the falls are 3/40 (zero head), 3/40 and 5/40, mean peak 7.937 / 7.917 / 7.932; the head selects luck on the
  training seeds, as the v3 attempt did. ILC was not run: it needs a kinematic target and the only one at hand, the ideal stance, is one the saturated stance cannot follow.

**Why not 10 m/s.** The best controller is at 7.91 m/s on P95 (75.7 % of the 10.45 ceiling), 6.17 on the average body (75 %) and 6.78 on elite2 (73 %). The standing-start searches (CMA, then ES) ended at 67-72 % of the ceilings, the gears lifted every body to 73-76 %, and the knots
were never run past a reproduction test: nothing passes 76 %. The ideal at the P95 ceiling is contact 0.100 s, flight 0.161 s, 3.83 steps/s, 2.61 m steps, mean / peak force 2.61 / 5.06 BW, touchdown knee 0.54, lift-off thigh -0.66;
the four-gear runner at 7.9 m/s has contact 0.102 s, flight 0.139 s, ~4.15 steps/s, ~1.9 m steps, 2.35 / 4.5 BW, knee 0.67, thigh -0.41: force and contact are within 10 %, but it flies 14 % less and steps 27 % shorter, so 10 m/s at its cadence would
need 2.4 m steps. Every search preferred the crouched bounce because the ideal's extended stance (touchdown knee 0.5, lift-off thigh -0.66, a trunk that rocks less than 0.1 rad) cannot be started (60 % of standing starts of the extended gait fall in
acceleration) and no controller here holds the trunk against the stance hip's hip-extension torque (the trunk pitches 0.36 rad per stance in the extended gait, against the ideal's 0.1). What would still move the numbers: a robust fourth gear
(the P95 hazard at 7.7+ m/s is the limit), a third-gear-style search for the extended stance from flying starts on top of a crouched acceleration, and a trunk actuator in the stance (the spine servo was too weak alone).

Recipe for one more gear on a body (all in `scratchpad/sprint_knot/`): record snapshots of the champion's steady running (`snapshots2.py`, env `SECS`, `SEED`, `T0`), write a practice file (the champion's
params + `gears K`, `gear0 K`, `fly_entry 2`, no `g<k>_v_on`), then `RUN_NATURAL_START=flying ROBOLAB_SNAP=<snapshots> playground/hsearch.py sprint_touch_v4 --method es --seconds 24 --seeds <12-19 snapshot indices>
--attrs objective=3,fly_touch=2,fall_pen=300 --init <practice file> --only "gK_*" --exclude <the gK_ start-phase twins and drives> --box <widened gK_ boxes> --controller bin/challengers/run_gear-v4c`; the standing-start entry drops
`gear0` and `fly_entry` and sets `g<k>_v_on` a little below the snapshots' speed (`combine_gears.py` writes a two-gear file from two params files; `select.py` ranks candidates on unseen seeds by falls, then speed).

Files: `lib/robolab/skills/run_gear.w` + `lib/entry/run_gear.w` (RunGearSkill); `run_knot.w` (`fly_entry`), `run_ri.w` (`k_sp`, `k_spd`); `controller.w` (`Track#set_movement`); `playground/hsearch.py`, `search.py --box`, `tasks/sprint_touch_v4.py`
(`start_noise`, `ROBOLAB_SNAP`); champions' params `params/run_ri_v4_*.txt`, `params/run_gear_v4_*.txt`, frozen binaries `bin/challengers/run_ri-v4base`, `run_knot-v4*`, `run_gear-v4*`; diagnostics and every search's params and logs in `scratchpad/sprint_knot/`.

### Sprinters on v4, round 2 (29 Sep): the extended stance held, and what it took

Round 1 ended at 7.907 m/s on P95 (75.7 % of the 10.45 pitch-free ideal-control ceiling) with four crouched gears, and named one untried thing: a gear whose stride is the
ideal's extended stance, searched from flying starts. **It works.** A fifth gear searched that way lifts the standing-start P95 champion to **8.276 +- 0.049 m/s (79.2 % of the
ceiling)**, +0.369 m/s on all 12 arena starts (paired p < 0.001, 12/12 survive; `params/run_gearx_v4_p95_x5a.txt`, controller `bin/challengers/run_gearx-a` = RunGearX, promoted in
`sprint_top_speed_v4_p95`). It is 79 % of a ceiling that is an upper bound built from separate capacity tests under idealised stabilisers, not a demonstrated gait: no muscle-only
stride at 10 m/s is known to exist, and this one is **not** 10 m/s (2.2 m/s short of the ceiling). Gears 1-4 are round 1's untouched; the entry says "five gears, v4 P95, standing
start". Log of every run with its command line: `scratchpad/sprint2/LOG.md`.

| per-start peak (m/s), seeds 221-232 | 221 | 222 | 223 | 224 | 225 | 226 | 227 | 228 | 229 | 230 | 231 | 232 | mean |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| four gears (previous champion) | 7.924 | 7.920 | 7.900 | 7.930 | 7.812 | 7.916 | 7.931 | 7.914 | 7.887 | 7.921 | 7.905 | 7.929 | 7.907 |
| five gears, extended-stance gear 5 (`x5a`) | 8.272 | 8.291 | 8.280 | 8.278 | 8.010 | 8.285 | 8.336 | 8.319 | 8.324 | 8.284 | 8.301 | 8.334 | 8.276 |

Falls (30 s, standing start, never trained on): seeds 141-180 **3/40** (153, 161, 175 at 19.6-25.2 s; survivors' peak 8.302, min 8.163), seeds 181-220 **1/40** (193 at 19.8 s; peak
8.303, min 8.240); the four-gear champion has 2 + 1 (its 153 and 175 are among the falls here). Flying starts (24 s, the champion's own steady-running snapshots at 7.6-8.0 m/s;
`playground/cache/sprint_touch_run_v4_p95j.npz` for training, `_p95k.npz`, 42 snapshots of 42 other runs, for validation): the extended gear survives 18/19 training starts and 36/40
unseen ones (peak 8.330, steady 8.253), the champion's own gear 4 restarted the same way 33/40 (peak 7.939, steady 7.891): the flying-entry transient (falls at 0.8-2.6 s) is
a property of the protocol, and the extended gear is not worse at it.

**The stride (mean over the steady stances, right foot).** The search did not reach the ideal; it reached its touchdown and its peak force:

| | crouched gear 4 (flying, 40 unseen) | extended, first search (f3c) | extended gear 5 (`x5a`, standing start seed 221) | ideal at 10.0 m/s (P95 v4) |
| --- | --- | --- | --- | --- |
| steady speed (m/s) | 7.891 | 7.756 | 8.234 | 10.0 |
| contact / flight (s) | 0.101 / 0.138 | 0.106 / 0.153 | 0.108 / 0.150 | 0.100 / 0.161 |
| step length (m) / step rate (1/s) | 1.91 / 4.13 | 2.02 / 3.86 | 2.14 / 3.85 | 2.61 / 3.83 |
| thigh at touchdown / lift-off (rad, + ahead) | +0.57 / -0.41 | +0.49 / -0.37 | +0.57 / -0.37 | +0.44 / -0.70 |
| knee at touchdown / stance maximum (rad) | 0.66 / 0.71 | 0.48 / 0.76 | 0.55 / 0.79 | 0.52 / 0.6 |
| ankle at touchdown (rad, - dorsiflexed) | 0.00 | | -0.21 | -0.44 |
| mean / peak vertical force (BW) | 2.37 / 4.12 | 2.42 / 4.37 | 2.38 / 4.84 (5.04 flying) | 2.61 / 5.06 |
| trunk pitch touchdown -> lift-off (rad) | 0.15 -> 0.17 (rock +0.016) | 0.24 -> 0.35 (+0.11) | 0.28 -> 0.37 (+0.09) | rock < 0.1 (penalised) |

So the extended gear lands with the ideal's knee, dorsiflexes the ankle half way to the ideal's, delivers the ideal's peak force in a 0.108 s contact and keeps the trunk inside the
ideal's 0.1 rad rock. What it still lacks against the ideal: 7 % of the flight, 17 % of the step length (the lift-off thigh is set by geometry, contact time x speed, so it follows
speed), 9 % of the mean force.

**What the searches were and what worked.**

- *Lab first* (all in `scratchpad/sprint2/`: `lab.py` per-stance table from flying starts, `snap.py` snapshot sets, `mkgear.py` gear-K params files, `scan.py` one-at-a-time moves, `morph.py`
  / `line.py` interpolation and line search, `mtab.py` muscle-level view, `val.sh` / `standval.sh` validation). Round 1's extended-mode gait (`p1_snap1`, the ideal-like 6.6 m/s gear) run as gear 5 from the 7.9 m/s
  snapshots falls in 1.2-1.4 s on 8/8: its trunk pitches +0.28..+0.39 rad per stance (torso_kp at its 0.3 floor) and the chain of pitching and a mistimed landing ends in a forward fall.
  Interpolating only its leg-geometry tunables from the champion's gear 4 (`morph.py`, no re-tuning) lowers the speed monotonically: peak 7.93 / 7.83 / 7.75 / 7.69 / 7.65 / 7.50 / 7.49
  m/s for alpha 0 / .1 / .2 / .3 / .5 / .75 / 1 while the touchdown knee goes 0.65 -> 0.56, the contact 0.100 -> 0.122 s and the trunk rock +0.02 -> +0.21 rad, at a peak force that stays 4.0-4.2 BW.
  The alpha 0.5 point survives 18/19 training starts (steady 7.47) and is the start of the search.
- *The search that failed, and the one that worked.* round 1's `hsearch` scores a candidate by its WORST of 12-19 seeds and prunes on it. From a gait that survives every seed, that statistic
  moves by luck with every small mutation (the worst of 18 seeds), so sparse mutations of a good stride almost never pass: 5 generations, 0/24 offspring, on the alpha 0.5 start
  (`f2`, scratchpad log). **`hsearch.py --agg mean`** (new, opt-in; the default is unchanged) scores a candidate by the MEAN of its seeds' scores and stops it at its first fall (fall_pen 300),
  so small mutations move the score smoothly while robustness stays a hard rule. With it, 8 flying-start seeds x 16 s, (1+16)-ES on the 73 gear-5 twins, from the alpha 0.5 start and the
  ideal-stance objective 6 (`sprint_touch_v4x.py`: pace less 40 points per rad the touchdown knee misses 0.55, the touchdown thigh 0.5, the lift-off thigh stays ahead of -0.55, the stance knee
  passes 0.75): 7.47 -> 7.77 steady in ~3900 rollouts (`f3`, `f3b`, `f3c`; validated 37/40 unseen, more robust than the crouched gear's 33/40 but 0.13 m/s slower), then, with the same
  search continued for 2300 rollouts on RunGearX (`f4`), **8.26 steady**. The moves that carried it (single changes reverted in the lab, 8 seeds x 16 s, peak from 8.32): the landing ankle
  target `a_reach` -0.13 <- -0.30 (its box floor) costs **0.48 m/s** (3/8 fall), `k_land` 0.209 <- 0.136 costs 0.15 (3/8 fall), `psi_reach` 0.060 <- 0.016 costs 0.14, `toe_land` 0.07; the arm reflex
  (`k_arm_p` 0.66) and `lean_v` (0.018) found by the same search are NOT the cause: with either or both at 0 the gait runs 8.29-8.31 (1-2 falls in 8 instead of 0). The touchdown posture is the mechanism:
  a dorsiflexed ankle and a knee near 0.54 at contact, which is the ideal's touchdown.

**The trunk, which round 1 named the blocker.** Measured, the trunk was one of two things that stopped the hand-made extended stances (a forward pitch runaway, and a touchdown placement that a held trunk does not cure);
the search found an extended stride whose trunk rocks 0.09 rad under the champion's own trunk servo, and no trunk mechanism was needed for it (mechanisms are all opt-in in `RunGearXSkill`,
`lib/robolab/skills/run_gearx.w`, `bin/robolab_run_gearx`; every tunable defaults to 0 and the P95 champion's 12 arena starts replay to the digit):

- *Where the trunk goes.* The crouched champion's trunk rocks +0.016 rad over a stance. p1_snap1's extended stride rocks +0.36, and a pre-activated one (vasti drive `drv_pre` 0.7 on the alpha 0.5 gear, which
  produces the ideal's stance in the first strides: contact 0.097 s, flight 0.160, step 2.04 m, touchdown knee 0.47, mean / peak force 2.6 / 4.0 BW) pitches +0.11..+0.30 rad per stance and a further +0.3
  in flight, cumulatively, and falls forward in 1.3-1.6 s (drv_pre 0.4 / 0.7 / 1.0: 4/8, 5/8, 7/8 falls). The searched extended gear rocks +0.09 (0.28 -> 0.37): the ideal's 0.1 rad.
- *What a perfect trunk is worth.* `sprint_touch_v4x` opt-in env `ROBOLAB_TRUNK_STAB=kp,kd,limit` applies a DIAGNOSTIC ideal external torque to the torso body (not an actuator the body has). On the crouched
  gear it is worth +0.10 m/s (300 N m, pitch held to its own slow mean) to +0.17 (100 N m, lean held at 0.3 rad; 200 N m 8.08; 400 N m all 4 fall); on the alpha 0.5 extended gear +0.08 (rock +0.15 -> +0.014),
  and the pre-activated extended gear still falls with the trunk held (it runs ~10 strides at the ideal's stance and then its touchdown thigh wanders 0.44..0.90 rad and the knee collapses to 1.3-1.8).
  On the searched extended gear the torque makes it fall 8/8 at 300, 150 and 80 N m: that orbit uses its 0.11 rad rocking.
- *Real mechanisms* (4 flying seeds, 12 s, on the alpha 0.5 gear): arm counter-rotation `k_arm_p` 8 cuts the stance rock from +0.15 to +0.08..+0.12 (30-50 %) and moves the speed by nothing (1/4 falls);
  `k_arm_d` 0.3 to +0.11..0.14; swing-hip synergy `k_swh` 0.5 falls 2/4 and 1.5 changes nothing; a lean that grows with speed (`lean_v` 0.05-0.1) falls 3/4. Put in the search as tunables (f4) the search kept
  `k_arm_p` 0.66 and `lean_v` 0.018 and they are not the source of the 0.5 m/s (ablation above). The spine servo of round 1 stays off (`k_sp` 0.03).

**What limits the stride now** (muscle level, `mtab.py`, crouched gear 4 at 7.9 m/s; force fraction = force / peak isometric at the stance's peak-load quarter, activation 1.0 in all):
vasti 0.72, soleus 0.83, gastrocnemius 0.80, toe plantarflexors 0.9-1.1 (saturated), hip extensors 0.2-0.3 (they shorten at 3-4 range/s: power-limited). A stronger muscle does not help an untuned gait
(single group x1.25 on the P95 body, 4 flying seeds, peak from 7.931: gastrocnemius 8.124 with no fall, soleus 7.990 (2/4 fall), toe plantarflexors 7.945, hip extensors 7.935, hamstrings 7.834 (3/4 fall),
vasti 4/4 fall: the controller is tuned to its vasti), so of the strengths tried the plantarflexors (the gastrocnemius most) are the ones that move the untuned gait, a stronger vastus breaks the tuned knee behaviour, and hip extension is limited by shortening speed
(force fraction 0.2-0.3), not by strength.
The one-parameter line search along the search's own direction (alpha 0.5 -> `f3c`) shows the ridge is narrow: 1.5 x the step falls 5/8, 2 x 6/8, with no speed gain in the survivors.

**Refinement, and the fall hazard.** The landing ankle's box floor (-0.3) was still the lever. Single edits of the promoted gear 5, in the standing-start chain (arena starts; falls on unseen standing starts
141-220 and 251-330; survivors' peak):

| variant | arena starts | unseen falls, 80 + 80 | survivors' peak (unseen) |
| --- | --- | --- | --- |
| `x5a` (entered) | 8.276, 12/12 | 4/80 + 3/80 | 8.30 |
| `a_reach` -0.33 (`scratchpad/sprint2/x5a_ar-0.33_stand.txt`) | 8.373, 12/12 (min 8.341) | 6/80 + 6/80 | 8.36-8.37 |
| `a_reach` -0.35 | 8.394, 10/12 (223, 224 fall at 20-21 s) | 7/80 | 8.40 |
| `a_reach` -0.40 and 1400 more ES rollouts (`f7_snap1`, `f7s1_stand.txt`) | 8.48, 11/12 (224 falls) | 11/80 (flying: 9/40) | 8.47-8.48 |
| `d_push` back to the previous stage's -0.1285 (`x5b_stand.txt`) | 8.337, 12/12 | 8/80 | 8.35 |

Each is +0.06..+0.2 m/s and each has more late falls (all at 19-28 s, 8-15 s after gear 5 is entered): the hazard rises with speed along this ridge, and the searches' 16-24 s flying horizons do not reach
it. `x5a` (7/160 = 4.4 %) is what round 1 would have entered by its own rule (3/80 for the four-gear champion); the `a_reach` -0.33 variant (12/160 = 7.5 %, Fisher p 0.34 against `x5a`; the -0.40 variant's 11/80 against `x5a`'s 4/80 has p 0.10) is left out for +0.10 m/s. A search on 30 s
standing-start chain rollouts (or 30 s flying ones) is the next step for those variants.

**Not done / not entered.** A sixth gear (`f6`, `f6b`: 2400 rollouts on snapshots of `x5a`, `sprint_touch_run_v4_p95m.npz` / `_p95n.npz`) does not beat gear 5: a restarted copy of gear 5 falls on 7/19
flying starts at 8.3 m/s, the search repaired survival (16/19) and not speed (steady 8.21 against 8.26). The recipe was not run on the average and elite2 bodies; the entry speed of gear 5 (7.8 m/s) was not
searched (the champion's gear 4 is entered at 7.7). What would move the numbers next: the landing ankle towards the ideal's -0.44 with a search that sees 30 s, a longer flight at the same contact (0.150 ->
0.161 s, 9 % more mean force), and a step length that the lift-off geometry allows only at higher speed.

Recipe (the round-1 recipe with the two changes that mattered: a start inside the extended family, and `--agg mean`): snapshots of the champion's steady running (`scratchpad/sprint2/snap.py PARAMS CONTROLLER OUT.npz
--seeds 31-50 --t0 20 --t1 29`), a practice file (`mkgear.py PARAMS OUT --gears K --fly`, plus the start's twins), then `RUN_NATURAL_START=flying ROBOLAB_SNAP=<snapshot set>
hsearch.py sprint_touch_v4x --method es --agg mean --lam 16 --seconds 16 --seeds <8 seeds> --attrs objective=6,fly_touch=2,fall_pen=300,st_ktd=0.55,st_td=0.5,st_lo=-0.55,st_kmax=0.75
--init <practice file> --only "gK_*" ...` (`scratchpad/sprint2/es.sh`; the ES needs `RUN_NATURAL_START=flying` exported or its rollouts are standing starts, and a start value outside its box is clipped:
both cost round 2 an hour). Check the search's `start` line is a survivor's score (> 0) before trusting the run. The standing-start entry: `mkgear.py PARAMS OUT --gears K --von <0.1 m/s below the snapshots>`.

Files: `lib/robolab/skills/run_gearx.w`, `lib/entry/run_gearx.w` (RunGearX); `playground/tasks/sprint_touch_v4x.py` (objective 6, the diagnostic torque); `playground/hsearch.py` (`--agg mean`, opt-in);
`params/run_gearx_v4_p95_x5a.txt` (the champion; frozen binary `bin/challengers/run_gearx-a`, copy in `bin/champions/`); snapshot sets `playground/cache/sprint_touch_run_v4_p95{j,k,m,n}.npz`; every tool,
practice file, search log and the run-by-run log in `scratchpad/sprint2/`.

### Sprinters on a stronger body (labelled) (29 Sep, round 3)

Round 2 ended at 8.276 m/s on P95 (79 % of its 10.45 ceiling) and named the one honest route left to 10 m/s: a stronger, **labelled** body, the move that took the bat from 26.5 to 32.4 m/s.
This round defines that body from the literature, computes its ideal-control ceiling, ports the five-gear runner to it and enters a new arena trial. **Everything below is a labelled body
variant (`playground/profiles/sprinter.json`, trial `sprint_top_speed_v4_sprinter`): never compare it with the average, P95 or elite2 trials.** Log of every run with its command line:
`scratchpad/sprint3/LOG.md`.

**The body** (fixed 2026-09-29 18:28, before any runner, replay or ceiling was run on it; `changes` in the file is empty). The same v4 anatomy and the average 1.75 m / 67.5 kg skeleton,
so lengths and masses stay comparable; the rule was the middle of the ranges the literature gives, not their top:

| part | P95 | elite2 | **sprinter** | status |
| --- | --- | --- | --- | --- |
| strength (peak force per kg, every muscle) | x1.32 | hip ext. 1.5, ham 1.4, vasti 1.1, plantarflexors 1.05-1.1, dorsiflexors 1.0 | **x1.55** | literature for hip extensors and hamstrings (Miller 2021 x1.4-1.6 per kg; Handsfield 2017); **chosen stretch** for knee and ankle extensors (strength-trained men x1.58, Maden-Wilkinson 2020; sprinters only x1.07-1.26 vasti, x1.09-1.18 plantarflexors) and every other muscle |
| muscle speed (fibre mix x fascicle length) | x1.2 | x1.3 | **x1.45** | derived: fibre mix x1.23-1.31 (Trappe 2015) times fascicles +12-24 % (Abe 2000, Kumagai 2000) = 1.3-1.5, the middle taken |
| tendon stiffness | x1.5 | Achilles 1.3, quadriceps 1.0 | **x1.5** (P95's) | unchanged on purpose: the sprinter differs from P95 in strength x1.17, speed x1.21, activation x0.92 only; the quadriceps value is P95's, not a sprinter's (Kubo: sprinters' knee tendons are more compliant) |
| activation time constants | x0.87 | 1.0 | **x0.8** | **unverified stretch** (fibre-mix inference gives 0.87-0.89; Tillin 2010's faster neural force onset has no place else in the model); the v4 screen says it barely matters |
| anthropometry | 1.0 | not applied | 1.0 | `ROBOLAB_PROFILE_PARTS=all` builds the same XML as the four muscle parts (checked byte-identical) |

The bat's athlete body is strength x1.5 on every muscle and a uniform fibre speed of 3.0 L0/s on the v1 placeholder body (not comparable with the v2+ speed multipliers); this body's x1.55 sits
on top of the model's peak forces, which are already 1.4-2.9x young men's voluntary maxima (`calibrations/v4.json`), so it is stronger than any measured person in the knee and ankle
extensors, the groups the ceiling is most sensitive to. A result on this body says what a runner could do if a body really had these muscles, not what any person does.

**The ideal-control ceiling of the sprinter (step 2): 12.36 m/s** (stance-budget ceiling at t_sw 0.35 s, 12.01-12.71 for t_sw 0.37-0.33; the margin chain is positive to 12.0 and its line
fits 12.75). Same recipe and measure as the other bodies (`scratchpad/sprint_knot/ceiling_probe.py`, pitch-free, v4 anatomy, default four muscle parts; `budget_ceiling.py v4b_sprinter`),
with one difference in effort: **one sparse chain** (1 m/s spacing from 10 m/s, warm-started from P95's 10 m/s solution, no joint stance-plus-swing refinement, two restarts per speed)
plus the dense points at 8-9.5 m/s of two earlier chains that an external load spike made too slow to finish. The estimate carries the usual +-0.5-0.7 m/s.

| body | average | P95 | elite2 | **sprinter** |
| --- | --- | --- | --- | --- |
| ideal-control ceiling, m/s | 8.20 | 10.45 | 9.28 | **12.36** |
| best runner, m/s (share of the ceiling) | 6.170 (75 %) | 8.276 (79 %) | 6.78 (73 %) | **8.407 (68 %; 8/12 starts survive)** |

The ideal stance at the ceiling (best stance budget of the sprinter's chains): at 12.0 m/s contact 0.066 s, aerial 0.154 s, step 2.64 m at 4.54 /s, mean / peak vertical force 3.34 / 4.72 BW,
thigh +0.38 at touchdown / -0.73 at lift-off, touchdown knee 0.60, touchdown ankle -0.37 (dorsiflexed, as P95's -0.43), trunk excursion 0.05 rad. At 10 m/s (the
sprinter's ideal is far from its limit there): contact 0.085 s, aerial 0.225 s, step 3.10 m, 3.65 / 5.25 BW. 10 m/s is 81 % of the sprinter's ceiling; round 2's P95 runner reached 79 % of P95's.

**Result: no fall-free runner, and not 10 m/s.** The best chain (`params/run_gearx_v4_sprinter_g5a.txt`, promoted in `sprint_top_speed_v4_sprinter`) reaches **8.407 m/s (survivors' mean
peak_speed_1s, 68 % of the 12.36 ceiling)** and survives **8 of the 12 arena starts**; on 80 unseen standing starts it falls 19 times. 10 m/s is 1.6 m/s away and 81 % of the ceiling.
Round 2's P95 champion, replayed on this body, falls on all 12 starts.

**Porting the runner** (each row is a run in `scratchpad/sprint3/LOG.md`; standing starts 30 s, flying starts 24 s from the champion's own steady-running snapshots on THIS body,
`sprj` = 17 training snapshots at 7.5-8.2 m/s, `sprk` = 36 unseen ones at 7.4-8.3):

| stage | flying, 17 training | flying, 36 unseen | standing, 12 arena starts | unseen standing (40 + 40) |
| --- | --- | --- | --- | --- |
| P95 five-gear champion replayed (`x5a`) | | | **0/12** (falls 12.0-16.3 s on ten, 3.5 and 3.8 s on 226 and 230); peaks before the falls 7.6-8.65 | |
| P95 four-gear champion replayed | | | **0/12** (13.0-16.5 s; 226, 230 at 3.5, 3.8 s); peaks before the falls 7.6-8.54 | |
| gear 5 = gear 4's values (control) | 0/17 survive (0.4-5.2 s, after 8.3-8.5 m/s) | | | |
| `x5a`'s extended gear 5 | 0/17 (0.7-6.3 s) | | | |
| V1: gear 5 = gear 4's values, **lean 0.10** (from 0.23) | 8/17 survive, steady 8.35-8.48 | 12/36 survive, peak 8.562 | 6/12, peaks 8.484-8.589 (mean 8.535) | |
| **g5a**: V1 + one generation of gear-5 ES (entered) | 15/17, steady 8.24-8.50, peak 8.428 | | **8/12, mean peak 8.407** | 30/40 (8.385) + 31/40 (8.423) |
| g5a5: the same ES, generation 5 | | 19/36 survive, peak 8.509 | 7/12, mean peak 8.532 | |

- *What breaks on the stronger body is the trunk.* The P95 chain accelerates FASTER here (6.2 m/s at 7.8 s, 8.26 at 12.4 s), then the trunk pitches forward stance after stance (touchdown pitch
  0.13 -> 0.21 -> 0.42 -> 0.54 -> 0.77 rad, peak force 4.2 -> 6.3 BW) and it falls at 15.8 s: the round-2 trunk runaway, reached at ~8.3 m/s. The crouched control rocks the trunk +0.10-0.20
  rad per stance (P95: +0.016). Working reading: the stance hip extensors deliver ~1.5x P95's torque at the same command (strength x1.17, and in the fast retraction the force-velocity factor
  x1.2-1.3 from the x1.21 speed) and the stance-hip trunk servo does not hold it.
- *One lever moves it: the forward-lean set point.* One-at-a-time probes on the control (8-12 flying seeds, 12-14 s): every drive (hamstring, knee, hip, gastrocnemius, ankle) x0.6-0.8, the
  servo gain `torso_kp` 0.4 / 1.5 and `leg_kp` 8 leave 8/8 falling at 3-4.6 s; **`lean` 0.23 -> 0.10: 4/12 fall, steady 8.40** (0.05: 2/12, steady 8.21; 0.0: 6/12; 0.3: 8/8). A lower speed plan
  (`v_top` 8.2 / 8.5) does not prevent the falls (6/6 fall at 11-18 s). Lowering the lean in gears 2-4 as well (V2) is worse (7/12 fall). The extended gear does not survive on this body with any
  lean tried (0.1, 0.0, -0.08: 12/12 fall each time, mean survival 2.4-3.2 s): the crouched family is the base here, the reverse of P95.
- *The gear-5 search* (`hsearch.py --agg mean`, (1+16)-ES on the 78 `g5_*` tunables, 10 training flying starts x 16 s, objective 3, fall penalty 300, `scratchpad/sprint3/es3.sh`, 4 workers)
  was stopped by the machine load and two harness stalls after 8 generations (436 rollouts, against 3900 + 2300 for round 2's gear 5). Its first generation already found a survivor of all 10 seeds
  (15/17 on the training snapshots); the fifth generation's incumbent flies faster (8.53) and falls about as often (5/12 arena starts against 4/12). Its late falls (10 of the 17 on unseen flying starts come at 17-24 s) are
  beyond its 16 s horizon, as in round 2. A start-phase search (`st.sh`, the 12 gear-1 start tunables, standing starts) reached generation 3 and was not usable.
- *What is left are gears 1-4, which nobody re-searched.* Seed 221 falls at 13.048 s in EVERY variant (steady 7.29 m/s; the fall time is identical to the digit with different gear-5 parameters, so gear 5 was never active): a gear 1-4 event. The start plan tuned on P95 is a
  hazard of ~12 % here (5 of 40 unseen 8 s starts fall at 3.3-4.0 s; `accel` 2.0 makes it 3/40; k0, drv0_* and psi0 change it by chance). Switching to gear 5 earlier rescues 221 and 229 and
  drops two others.

**Arena** (`sprint_top_speed_v4_sprinter`, a new trial: the rules of `sprint_top_speed_v4_p95`, 12 perturbed standing starts 221-232, 30 s, `peak_speed_1s`, guard no fall,
`ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=sprinter ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation`, task `run_v4`; no existing trial was edited). Seeded with the P95 five-gear champion
replayed on this body (-1e9 on 12/12); challenged with the chain above (`arena.py eval ... --promote`): **wins, mean paired difference +6.7e8, p = 0.004, promoted**
(frozen `bin/champions/sprint_top_speed_v4_sprinter-20260929-210109`, controller `bin/challengers/run_gearx-s3a` = RunGearX). Not comparable with the P95 trials.

| per-start peak (m/s) | 221 | 222 | 223 | 224 | 225 | 226 | 227 | 228 | 229 | 230 | 231 | 232 | mean of survivors |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `run_gearx_v4_sprinter_g5a` | fall 13.0 s | 8.504 | 8.432 | 8.326 | 8.486 | fall 3.5 s | 8.361 | 8.334 | fall 11.5 s | fall 3.8 s | 8.349 | 8.461 | **8.407** (8/12) |

Falls on unseen standing starts (30 s, never trained on): seeds 141-180 **10/40** (five start falls at 3.5-3.9 s: 141, 148, 150, 164, 176; 155 at 22.9 s, 156 at 15.6, 157 at 11.5,
161 at 16.8, 162 at 12.1; survivors' peak 8.385, min 8.306, max 8.533); seeds 181-220 **9/40** (182 at 6.2 s, 184 at 27.1, 193 at 9.7, 196 at 4.7, 202 at 13.3, 209 at 28.8, 211 at 10.3, 214 at
10.8, 215 at 5.6; survivors' peak 8.423, min 8.300, max 8.569). 19 of 80 (24 %) fall, against 4 of 80 for round 2's P95 champion.

**The stride against the ideal** (entered chain at its steady state, seed 222, 26 stances of the last 12 s, `stridetab.py`; the ideal is the best stance budget of the sprinter's ceiling chains):

| | entered chain, 8.44 m/s | ideal at 8.5 m/s | ideal at 12.0 m/s (the ceiling) |
| --- | --- | --- | --- |
| contact / flight (s) | 0.093 / 0.133 | 0.116 / 0.256 | 0.066 / 0.154 |
| step (m) / rate (1/s) | 1.92 / 4.4 | 3.16 / 2.69 | 2.64 / 4.54 |
| thigh at touchdown / lift-off (rad, + ahead) | +0.56 / -0.42 | +0.46 / -0.52 | +0.38 / -0.73 |
| knee at touchdown (rad) | 0.69 (max 0.72) | 0.56 | 0.60 |
| ankle at touchdown (rad, - dorsiflexed) | 0.00 | -0.50 (the box floor) | -0.37 |
| mean / peak vertical force (BW) | 2.38 / 4.15 | 3.21 / 4.98 | 3.34 / 4.72 |
| trunk pitch touchdown -> lift-off (rad) | 0.086 -> 0.097 (rock +0.011) | excursion 0.11 (penalised above 0.1) | 0.05 |

It is P95's crouched high-cadence bounce at a higher speed: at 8.44 m/s the ideal stance has a 0.26 s flight and a 3.2 m step (the budget optimiser buys swing time with flight at low speed),
the runner flies half as long and steps 40 % shorter; it uses 4.15 of the ~5 BW peak force the ideal uses and 2.4 of its 3.2 BW mean, so the body's strength is largely unused. The trunk, the
problem of this body, rocks only 0.011 rad per stance in the steady gait.

**Long jump (reported, not started).** The runner does not exceed 10 m/s, so no jump work; its runway profile from a standing start (seed 222, `scratchpad/sprint3/runway.py`): 10 m at 5.1 s
(4.1 m/s), 20 m at 7.1 s (5.8), 30 m at 8.7 s (6.5), 40 m at 10.2 s (7.3), **44 m mark at 10.7 s: 7.50 m/s, mean 7.27 m/s over the last 5 m** (P95's runner: 6.6-6.9 m/s at 44 m). The
acceleration between 3 and 7 m/s is still the slow part (44 m to reach 7.5).

**What worked / what did not.** Worked: fixing the body before anything ran; the ceiling (12.36); the lean lever (0/12 -> 6/12 standing survivors with one number); a mean-aggregate ES from a
surviving crouched start (15/17 on its training snapshots). Did not: replaying either P95 champion (0/12 each); the extended gear on this body; drive, servo-gain and speed-plan changes; lowering
the lean in gears 2-4; earlier gear switches (they trade one fall for another); the start search (too slow under the machine load). **What would be needed for 10 m/s:** the start and gears 1-4
re-searched on this body from flying starts as round 1 did (they carry the start hazard and the 13 s falls), a trunk mechanism that scales with the stronger hips, an extended-stance gear searched
from the crouched 8.4 m/s gait (round 2's recipe; the extended gear of round 2 does not transfer), and the ~1.6 m/s between 8.4 and 10, which on P95 all of round 2 bought +0.37 m/s: the runner uses
68 % of the ceiling, and P95's best was 79 %.

Files: `playground/profiles/sprinter.json`; `playground/arena/trials.json` (+ `champions.json`, `history.jsonl` by `arena.py`); `params/run_gearx_v4_sprinter_{v1,g5a,g5a5}.txt` (the entered chain is `g5a`);
frozen binary `bin/challengers/run_gearx-s3a` (RunGearX, the same build as `run_gearx-a`); snapshot sets `playground/cache/sprint_touch_run_v4_sprj.npz` / `_sprk.npz` (git-ignored); ceiling data
`out/sprint_limits/probe_v4b_sprinter_*`; every tool (`snap3.py`, `val3.sh`, `rep.sh`, `qv.sh`, `scan3.sh`, `es3.sh`, `st.sh`, `stab.py`, `runway.py`), search log and run-by-run log in `scratchpad/sprint3/`,
outputs in `out/sprint3/`.

### Sprinters on a beyond-human body (labelled) (29 Sep, round 4)

**BEYOND-HUMAN, not a human profile.** Round 3's labelled elite-sprinter runner ended with 8/12 fall-free arena starts on its own body and named what was left: the start and gears 1-4 were never
re-searched on a stronger body. This round asks the honest open-ended question for the control plane: on a clearly invented body **chosen up front**, can the same runner family (`RunGearXSkill`, the gears, the
mean-of-seeds search) be tuned to a fall-free standing-start peak speed above 10 m/s, and what did that body need? **Everything below is a labelled body variant (`playground/profiles/beyond.json`, trial
`sprint_top_speed_v4_beyond`): BEYOND-HUMAN. It is not a claim about human sprinting and is never to be compared with the average, P95, elite2 or sprinter trials.** Run-by-run log with every command line:
`scratchpad/sprint4/LOG.md`.

**The body** (rule and ladder written 2026-09-29 21:18 before any runner, replay or ceiling ran on it; the pick made at 21:52 from two measured ceilings; `changes` in the file is empty). The sprinter profile scaled UP by
round numbers, the smallest step whose ideal-control ceiling is above 14.5 m/s (so that 10 m/s is about 70 % of it; the ladder had no finer step). **The multipliers are an invented stretch**: no measurement or literature
value stands behind strength x2.4 or speed x2.0 on top of a model whose peak forces are already 1.4-2.9x young men's voluntary maxima.

| body (listed to DEFINE the beyond body, not to compare runners across bodies) | strength | muscle speed | tendon | activation | ideal-control ceiling (t_sw 0.35) |
| --- | --- | --- | --- | --- | --- |
| average | 1.0 | 1.0 | 1.0 | 1.0 | 8.20 m/s |
| P95 | x1.32 | x1.2 | x1.5 | x0.87 | 10.45 |
| sprinter (labelled, round 3) | x1.55 | x1.45 | x1.5 | x0.8 | 12.36 |
| ladder step 1 (measured, not used) | x2.0 | x1.7 | x1.5 | x0.8 | 13.51 (13.09-13.94) |
| **beyond = ladder step 2 (BEYOND-HUMAN)** | **x2.4** | **x2.0** | x1.5 | x0.8 | **16.32 (14.99-16.69 for t_sw 0.37-0.33)** |

Ceiling recipe = the sprinter's (`scratchpad/sprint_knot/ceiling_probe.py`, pitch-free, v4 anatomy, four muscle parts, one sparse chain at 1 m/s from the sprinter's 10 m/s solution, `--cycle 0`, two restarts per speed;
`budget_ceiling.py` at t_sw 0.35), so it carries the usual +-0.5-0.7 m/s. Step 1 gave 13.51 < 14.5 and step 2 16.32 > 14.5, so the rule picked step 2 (step 3, x3.0 / x2.4, was never needed or computed). 10 m/s is 61 % of the
beyond body's ceiling. Budgets per speed (best penalised stance budget, s): step 2: 10 m/s 0.580, 12: 0.481, 14: 0.408, 15: 0.370, 16: 0.367, 17: 0.314, 18: 0.280; the ideal at 16 m/s: contact 0.061 s, aerial 0.157 s, step
3.49 m at 4.59/s, peak vertical force 5.0 BW. Data `out/sprint_limits/probe_v4b_beyondc{1,2}_s1_v*`.

**Porting the runner** (each row is a run in `scratchpad/sprint4/LOG.md`; standing starts are the arena's 221-232, 30 s; flying starts are snapshots of the chain's own running on THIS body; every BEYOND-HUMAN number):

| stage | what it is | result |
| --- | --- | --- |
| replay of round 3's sprinter chain (`run_gearx_v4_sprinter_g5a`) | the entered chain of the sprinter body, unchanged | **0/12**: all fall in the start (2.2-6.4 s), the trunk pitching 0.56 -> 0.69 -> 0.86 rad in the first strides; one-number levers (lean, lean_acc, accel, torso_kp, drives x0.5-0.7, start drives) do not fix it |
| start ES `sa` (gear 1 only, 27 generations, 4 014 rollouts, 10 min) | `hsearch --agg meanall` over the 100 gear-1 tunables from standing starts 31-42, 7 s | lean 0.19 -> 0.02 (the sprinter lever, found by the search); 12 s: 11/12; 30 s: 0/12 (falls 15-27 s after a steady 8.4-8.5 m/s: ONE searched gear already equals the sprinter chain's speed) |
| gear 2 ES `gb` (40 generations, 3 019 rollouts, 16 min) | gear 2 = a copy of gear 1, flying starts from 10 entry + edge-of-instability snapshots (7.2-8.6 m/s), 14 s | 21 unseen snapshots, 24 s: 17/21 survive, **peak 9.87 m/s**; chain 1+2 on the arena starts: 9/12, peaks 9.81-9.88 (9.855) |
| gear 3 ES `gc`/`gd`/`ge` | gear 3 = a copy of gear 2, flying starts from the top of chain 1+2 (9.3-9.9 m/s), 16 s | with the plan caps at their boxes (v_top 9.75, v_cap 10.0) chain 1+2+3: 10/12, peaks 9.82-10.005 (9.924); with the caps raised (v_top 11, v_cap 11.5) peak 10.2 |
| final chain | start (`lean_acc` 0, `lean` 0.06) + gear 2 (`g2_v_on` 7.6) + gear 3 (`g3_v_on` 9.4, caps 11 / 11.5) | see the arena table |

*The finding that mattered: the speed-plan caps bound the top gear.* The gear searches had pushed `v_cap` to 10.0 (its box top) and `v_top` to 9.75: above `v_cap` the landing foot moves forward (speed brake, `k_brake`), and `v_top` sets the drive scale
(`s = drv_floor + (1 - drv_floor) v_des / v_top + k_vd (v_des - v)`), so no chain could exceed ~10 m/s however well its stride was tuned. Widening the two boxes to 8-14 and starting gear 3 at 11.0 / 11.5 moved the same gait from 9.94 to 10.23 m/s
(lab, 14 top-speed snapshots). Every earlier runner box (2.5-10.0) was set on bodies that never reached them.

*What the search needed here that round 3 did not have:* (1) an aggregate that lets a search climb out of a failing incumbent (`hsearch --agg meanall`, opt-in: the mean over ALL seeds, falls do not stop a candidate, so the number of survivors moves the score; the `--agg mean` of round 2
needs an incumbent that already survives every seed); (2) edge-of-instability snapshots (states taken 2 s before a fall) as training states, so 10-16 s rollouts see the trunk drift that only shows after 15-25 s of running; (3) gear twins frozen explicitly (`freeze_twins.py`), so a
search of one gear cannot move another through the fallback; (4) a pruning bound `HSEARCH_UB` above the best possible per-seed score (a bound of 350 under an incumbent scoring 351 pruned every candidate for 15 minutes).

**Arena** (`sprint_top_speed_v4_beyond`, a new trial: the rules of `sprint_top_speed_v4_p95`, 12 perturbed standing starts 221-232, 30 s, `peak_speed_1s`, guard no fall, `ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=beyond ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation`,
task `run_v4`; no existing trial was edited). Seeded with round 3's sprinter chain replayed on this body (-1e9 on 12/12); challenged with chain C (`arena.py eval ... --promote`): **wins, mean paired difference +7.5e8, p = 0.002, promoted** (frozen
`bin/champions/sprint_top_speed_v4_beyond-20260929-233725`, controller `bin/challengers/run_gearx-s4a` = RunGearX, params `params/run_gearx_v4_beyond_c.txt`). BEYOND-HUMAN: not comparable with any other trial.

| per-start peak (m/s) | 221 | 222 | 223 | 224 | 225 | 226 | 227 | 228 | 229 | 230 | 231 | 232 | survivors' mean |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| chain C (promoted) | 10.159 | 10.105 | 10.185 | 10.178 | fall | 10.152 | fall | 10.153 | 10.146 | 10.170 | fall | 10.103 | **10.150 (9/12)** |
| chain D (`..._d.txt`, not promoted: p = 0.267 against C) | 10.164 | fall 23.9 s | 10.195 | 10.173 | 10.174 | 10.176 | fall 13.0 s | 10.174 | 10.127 | 10.171 | fall 6.6 s | 10.178 | 10.170 (9/12) |

**Result: above 10 m/s on every survivor (10.10-10.20 m/s), but NOT fall-free**: 9 of 12 arena starts survive 30 s, and on unseen standing starts C falls 20/80 (the two official sets) and 26/80 (80 fresh seeds, 251-330) and D 14/80 and 14/80, against the target of at most 10 % on each set. Chain D is chain C with two numbers of gear 3 changed (`g3_k_swh` 1.87 -> 3.0, the swing-hip trunk synergy, and `g3_lean` -0.151 -> -0.10; chosen on the 141-180 set): on the fresh seeds it cut the top-speed falls from 15 to 3 of 80, so **D is the better chain (17.5 % falls on 160 unseen starts, survivors' peak 10.16-10.17 m/s)**; the arena's paired test on the 12 starts could not tell it from C (3 falls each, different seeds, p = 0.267), so C stays the promoted champion.

Falls on unseen standing starts (30 s, never trained on; type: START = gear 1 before 8 s, HANDOVER = the gear-1 -> gear-2 switch at 7.6 m/s, TOP = gear 2/3 above 9.4 m/s):

| chain | seeds 141-180 | seeds 181-220 | seeds 251-330 (fresh: selected nothing) |
| --- | --- | --- | --- |
| C (entered) | **9/40**: 155 (6.1 s, START), 171 (11.8), 173 (11.1) HANDOVER, 142 (28.8), 160 (23.6), 163 (26.8), 175 (23.9), 176 (24.7), 180 (26.6) TOP; survivors' peak 10.134 (min 9.944, max 10.227) | **11/40**: 216 (6.1 START), 182 (10.1), 196 (12.6), 218 (12.5) HANDOVER, 181 (24.8), 185 (22.6), 194 (23.5), 198 (24.5), 202 (24.1), 212 (26.5), 217 (29.2) TOP; survivors' peak 10.136 (min 9.877, max 10.197) | **26/80**: START 260 (7.2 s), 271 (6.2), 278 (2.2), 295 (6.1), 298 (6.6), 310 (5.1), 318 (7.7); HANDOVER 277 (14.6), 280 (11.4), 300 (9.3), 301 (12.0); TOP (15) 259, 261, 262, 263, 264, 270, 276, 283, 289, 312, 314, 317, 319, 323, 330 at 19.9-29.9 s; survivors' peak 10.134 (9.909-10.217) |
| D | **4/40**: 155 (START), 171, 173 (HANDOVER), 149 (27.1 TOP); survivors' peak 10.172 (10.107-10.223) | **10/40**: 216 (START), 182, 196, 218 (HANDOVER), 191 (21.8), 201 (24.9), 202 (28.4), 203 (18.9), 206 (29.4), 212 (26.9) TOP; survivors' peak 10.171 (10.127-10.234) | **14/80**: START 260, 271, 278, 295, 298, 310, 318 (same seeds as C, 2.2-7.7 s); HANDOVER 277, 280, 300, 301 (9.3-14.6 s); TOP (3) 258 (25.8 s), 273 (24.2), 309 (27.7); survivors' peak 10.159 (10.073-10.259) |

By type: over 141-220 C has 2 start + 5 handover + 13 top falls and D 2 + 5 + 7; over the fresh 251-330 both have 7 start + 4 handover, and C 15 top falls against D's 3 (the same start and handover seeds fall for both, as the gears below the top are identical). Every fall is one of three chaotic hazards, roughly 4-9 % (start), 5 % (handover) and 4-19 % (top) per run; the top falls come 10-15 s after the gait reached ~10 m/s (a slow trunk drift: pitch at touchdown 0.13-0.16 in the tail of the
falling runs against 0.05 in the survivors).

**The stride against the ideal** (chain D at its steady state, seed 224, 15 stances of the last 30 % of a 24 s run, `scratchpad/sprint_knot/stridetab.py`; the ideal is the best stance budget of the beyond body's ceiling chain, `probe_v4b_beyondc2`):

| | chain D, 10.05 m/s | ideal at 10 m/s | ideal at 16 m/s (the ceiling) |
| --- | --- | --- | --- |
| contact / flight (s) | 0.080 / 0.149 | 0.092 / 0.262 | 0.061 / 0.157 |
| step (m) / rate (1/s) | 2.31 / 4.36 | 3.54 / 2.83 | 3.49 / 4.59 |
| mean / peak vertical force (BW) | 2.79 / 4.81 | 3.84 / 5.18 | 3.57 / 5.0 |
| thigh at touchdown / lift-off (rad) | +0.66 / -0.46 | +0.65 / -0.55 | +0.93 / -0.28 |
| trunk pitch at touchdown (rad) | 0.055 (rock over the stance -0.01) | free (excursion 0.07) | free (excursion 0.11) |

It is the crouched high-cadence bounce family the runner started from (4.2-4.4 steps/s) run at a higher speed: its cadence and flight time are the ideal's at 16 m/s, and the speed comes from the step growing from 1.9 m (8.4 m/s) to 2.3 m; the peak force
(4.8 BW) is the ideal's, so the strength of this body is not what limits it.

**Runway profile of chain D from a standing start** (`scratchpad/sprint4/runway.py`, seed 224; seed 222 in brackets): 10 m at 4.08 s (4.97 m/s), 20 m at 5.84 s (6.32), 30 m at 7.33 s (7.14), 40 m at 8.69 s (7.63), **44 m mark at 9.21 s: 7.74 m/s, mean 7.62 m/s over the last 5 m** (seed 222: 7.19 / 7.40),
50 m at 9.98 s (8.25), 60 m at 11.18 s (8.61), 80 m at 13.46 s (9.14), 100 m at 15.62 s (9.51), 120 m at 17.69 s (9.83): 10 m/s only after about 140 m (about 19 s). A long jump from a 44 m run-up would still take off at about 7.4-7.7 m/s, 2.5 m/s below this chain's top speed: the
3-7 m/s acceleration (30 m to reach 7.1 m/s) is the slow part, so a faster start gear is the next thing the jump needs. Its gear 1 has a ~6 % start hazard (gear-1 falls at 5-7 s), and the searches on 12-14 seeds did not reduce it on unseen seeds, so the acceleration gear has to be searched on 40+ seeds
first. **The long jump was not started.**

**What worked / what did not.** Worked: choosing the body by a written rule and two measured ceilings (13.51, 16.32) before any runner ran; **re-searching the runner from the start on the new body, gear by gear from flying (and edge-of-instability) snapshots with the mean-of-seeds search**: one searched gear 1 reaches 8.4 m/s
in 10 minutes, gear 2 9.87 m/s in 16, and the three-gear chain passes 10 m/s on every survivor; finding that the speed-plan caps (`v_cap`, `v_top`) bound the top gear at 10.0 m/s; `lean_acc` 0 halving the start hazard (13 % -> 6 %, 136 seeds); the gear-3
trunk synergy `k_swh` 3.0 with `lean` -0.10 on the set it was selected on (141-180, 30 s: 9/40 -> 4/40 falls at 10.17 m/s), only 11/40 -> 10/40 on 181-220, and 26/80 -> 14/80 on the 80 fresh seeds (top falls 15 -> 3), i.e. a real but partial gain. Did not: replaying round 3's sprinter chain (0/12); any single lever on the start (12/12 fall); a start / handover search on 12-14 seeds (fixes those seeds, not the hazard: 9/56 unseen starts still fall);
a 40-seed `mean` search (stopped before its first generation ended: 16 candidates x 40 seeds is ~5 min per generation); lowering the handover speed (5.0-6.5 m/s: gear 2 does not take over below ~7 m/s) or moving it in 7.2-8.0 (the handover hazard stays 6-8 %); trading speed for stability with `lean` (-0.25: 8/40 falls at 9.64 m/s) or `torso_kp` / `torso_kd` / `hip_lead` (worse). **What would be needed for a
fall-free 10 m/s:** the three hazards below 3 % each: a start / acceleration gear searched on 40+ seeds, a handover trained on the chain's own switch (standing-start rollouts), and a top gear searched with 25-30 s horizons on many seeds (or a speed-dependent trunk set point: `lean_v` < 0, which `RunGearX` ignores today).
About 2 h 40 min of wall clock, of which ~50 min were lost to machine stalls (a 26 min hole at 21:23-21:49, 20 min at 23:12-23:33 and several 5 min ones; load 20-28 from other agents).

Files: `playground/profiles/beyond.json` (rule, ladder, decision, ceilings); `playground/arena/trials.json` (+ `champions.json`, `history.jsonl` by `arena.py`); `playground/hsearch.py` (opt-in `--agg meanall`, `HSEARCH_UB`); `params/run_gearx_v4_beyond_{a,b,c,d}.txt` (the entered chain is `c`; `d` is the better one on the unseen sets);
frozen binaries `bin/challengers/run_gearx-s4a` / `-s4b` (RunGearX, the same build as `run_gearx-a`: `lib/robolab/skills/run_gearx.w` was NOT edited, so the P95 champion still replays 8.272 8.291 8.28 8.278 8.01 8.285 8.336 8.319 8.324 8.284 8.301 8.334 and round 3's sprinter chain 8/12 at 8.407 with it: both re-checked);
snapshot sets `playground/cache/sprint_touch_run_v4_{bj,bk,bh,bm,ct,cv,cm}.npz` (git-ignored); ceiling data `out/sprint_limits/probe_v4b_beyondc{1,2}_s1_*`; every tool (`freeze_twins.py`, `mkchain3.py`, `nextgear.sh`, `stb.sh`, `stc.sh`, `esk.sh`, `rep.sh`, `qv.sh`, `qbatch.sh`, `val.sh`, `valchains.sh`, `runway.py`, `stab.py`, `snap3.py`), every search
log (`sa`, `ga`, `gb`, `gc`, `gd`, `ge`, `sb`, `sb2`, `sc`) and the run-by-run log in `scratchpad/sprint4/`, outputs in `out/sprint4/`.

### Sprinters on a beyond-human body (labelled), round 5 (1 Oct 2026, agent S5): the fall rate from 31% to 7-8%

All numbers are for the LABELLED beyond-human body (`playground/profiles/beyond.json`; an invented stretch), 30 s perturbed standing starts, task `run_v4`; never compared with the human-body sprint trials. Round 4's chains reach 10.15 m/s but fall on 14-26 of 80 unseen starts; round 5 attacked the falls (log `scratchpad/sprint5/LOG.md`, brief `scratchpad/sprint5/BRIEF.md`).

| chain | falls on 128 fresh seeds never used (15001-15128; my own check) | survivors' mean peak |
| --- | --- | --- |
| entered champion (S4's chain C) | 38 (29.7%) | 10.127 m/s |
| S5's F1 (`params/run_geary_v4_beyond_s5b.txt`, controller `bin/challengers/run_geary-s5-final`, skill `lib/robolab/skills/run_geary.w`) | 10 (7.8%) | 10.116 m/s |

- S5's own numbers: headline seeds 12001-12128: champion 31.2% (start 13, handover 6, top gear 21 falls), chain D 21.9%, F1 7.0% (9/128); confirmation 13001-13128: 35.9%, 24.2%, 9.4%; over 512 fresh seeds F1 8.4% and the primary candidate F0 (fixed before any headline run) 11.5%; falls before 20 s, the long jump's run-up: 7.0% against 15-20%. F1 was picked on selection seeds and then measured on the same headline sets as F0, so it is a labelled second look.
- **The PASS RULE (under 5% on the headline and under 7% on the confirmation) is NOT met** (F1: 7.0% and 9.4%); the survivors' mean peak of 10.11 m/s meets its speed condition. A sustained fall-free 10 m/s is not achieved: over 45 s F0 falls 1.6 / 6.2 / 10.9 / 11.7% by 20 / 30 / 40 / 45 s (the top gear escapes at about 0.4% per second).
- **What worked:** the ES-tuned spine servo `k_sp` of gears 2 and 3 in S4's chains was a destabiliser (set to 0), and its OPPOSITE sign (new tunable `k_sps` -0.06) stabilises the top gear (14.8% to 1-2% real falls in 20 s from 9.2 m/s); a start search with fresh seeds every generation and a validated acceptance (start falls 18 to 8 of 256); gear-2 `cv` 0.04, gear-3 `k_fly` 1.1 and takeover at 9.2 m/s. **What did not:** (1+lambda)-ES on gears 2 and 3 (the acceptance test on 48-96 starts is a coin flip at 4-8% falls), margin and kick-stress proxies, pitch-feedback placement, catch step, blends, gated switches, intermediate and cool-down gears.
- **What limits it (F1, 512 fresh seeds):** start 3.9% (the early backward collapse in the stand and lean chunks, the COM starting 4 cm behind the feet, a 1.6% floor no lever touched), handover 2.9% (the 1 to 2 switch transient), top gear 1.6%; every stabiliser trades speed, and the 30 s window leaves only 2-3 s of slack.
- Arena: new trial `sprint_top_speed_v4_beyond_fresh128` (seeds 12001-12128, seeded with the champion): F0 beat it (p 0.00025), then F1 beat F0 (p 0.0063) and is the champion; the old 12-seed trial is untouched (F1 and F0 are fall-free on 221-232 but p 0.127 against chain C, not promoted). `arena.py recheck` of both trials reproduces exactly; `run_gear.w`, `run_gearx.w` and the other shared skill files are unchanged. Tools in `scratchpad/sprint5/` (`fr.py` fall rate by phase, `rses.py` fresh-seed ES), practice tasks `playground/tasks/sprint_touch_v4y.py` and `sprint_touch_v4z.py`.

### Sprinters on a beyond-human body (labelled), round 6 (3 Oct 2026, agent S6): a rear step for the starts that begin over the heel, falls 7.4% to 5.6%

All numbers are for the LABELLED beyond-human body (`playground/profiles/beyond.json`; an invented stretch), 30 s perturbed standing starts, task `run_v4`; never compared with the human-body sprint trials. Brief `scratchpad/sprint6/BRIEF.md` (rules fixed beforehand), log and FINAL STATE `scratchpad/sprint6/LOG.md`. Erik chose this as the next work on 2 Oct ("Sprint start and handover").

| set (never used for a choice unless marked) | F1 falls | S6a falls | survivors' mean peak |
| --- | --- | --- | --- |
| selection 24001-25000 (1000 seeds; every choice between candidates was made here) | 73 = 7.3% | **51 = 5.1%** (22 recovered, 0 new, p < 0.001) | 10.112 / 10.112 |
| TEST A 22001-22128 (run once) | 5 = 3.9% | **3 = 2.3%** | 10.115 / 10.115 |
| TEST B 22129-22256 (run once) | 5 = 3.9% | **5 = 3.9%** (the same falls) | 10.114 / 10.115 |
| S6's confirmation 26001-26512 (512 seeds, run once) | 41 = 8.0% | **33 = 6.4%** (8 recovered, 0 new, p = 0.008) | 10.111 / 10.111 |
| my own check 50001-50512 (512 seeds nobody had used; arena's way: `scratchpad/sprint6/fresh_check_main.py`) | 44 = 8.6% | **36 = 7.0%** (8 recovered, 0 new) | 10.111 / 10.110 |
| all five sets (2280 seeds) | 168 = 7.4% (Wilson 6.4-8.5) | **128 = 5.6%** (4.7-6.6) | |

- **Pass rule** (under 5% on TEST A, under 7% on TEST B, survivors' mean peak at least 10.0 m/s): **met** by S6a (2.3% and 3.9%, peaks 10.115). Read it honestly: F1 also meets it on those two sets (3.9% each, a lucky draw: its rate is 7.0-8.6% everywhere else), because the only starts S6a changes (3.3% of starts) are 3 + 1 seeds there. The real gain is the 40 starts recovered with 0 new falls over 2280 seeds (sign test p about 2e-12): **about 1.8 points of the fall rate, a quarter of the falls**; the stretch target (under 3%) is not reached (true rate about 5.6%). Falls before 20 s, the long jump's run-up: 6.2% to 4.4% over S6's four sets.
- **What S6a is:** a new skill `lib/robolab/skills/run_gearz.w` (`RunGearZSkill < RunGearYSkill`, entry `lib/entry/run_gearz.w`, controller `bin/challengers/run_gearz-s6-final`, params `params/run_gearz_v4_beyond_s6a.txt`; the source rebuilds the frozen binary byte for byte). A start whose centre of mass minus the ankles' midpoint at the first tick is below `rk_thr` = -0.05 m (3.3% of starts; 61-70% of them fall under F1) takes a REAR STEP: the right hip extended 0.08 rad and the knee bumped 0.5 rad over 0.2 s from t = 0, the stand chunk ends at 0.3 s instead of 0.5 s and the lean chunk times out at 0.6 s instead of 1.5 s. Every other start is bit-identical to F1 (checked on 80 selection seeds, 127 of 128 arena seeds, all of TEST B); F1's params through the new controller reproduce the arena's recorded per-seed scores on all 128 seeds. On the deep class (609 pool seeds, 6 s) falls drop from 61% to 4.4%, and the gain replicated on a pool the levers were not developed on.
- **Why it works (S6's traces):** the foot box ends 0.063 m behind the ankle, so these starts begin with the COM at the heel edge; the stock ankle strategy rotates the light FOOT toes-up about the heel instead of leaning the shank, which swings the body backward, and the lean chunk's maximal dorsiflexion kick leaves a rigid body balanced on the heel point. Ankle clamps, slew limits and every hip/knee/spine/arm posture shift failed or worsened it (the legs rotate back about the ankle; the heel carries at most 42 N m): the COM needs support behind it, as a person steps back.
- **What did not work:** a (1+8) ES over the 37-144 start tunables (nothing beyond the hand profile), a step on the marginal class (COM0 -0.05 to -0.035: 6% base rate, worth at most one fall per 1000), intermediate gears between gears 1 and 2 (67 and 79 falls against 73: the handover falls halve, the top-gear falls rise by as much; the hazard moves, it is not removed).
- **What limits it now (selection, 51 falls):** start 25 (9 early collapses of starts that begin 1.3-2.8 cm ahead of the heel or drift back, 11 acceleration falls at 3-9 s, 5 at 9.2-9.7 s), handover 17, top gear 9; chaotic escapes with no precursor in the state before the last second (AUC 0.5-0.6 of every initial-state and pre-switch feature). Suggestions: the dynamic rear step for COM drift (`dy_*` tunables, implemented, never evaluated), the hard-coded stand / lean / first-push constants as tunables for all starts, the same support-behind-the-COM idea as a recovery step for the pitch-oscillation falls; the long jump's run-up still runs F1 (checked on 3 Oct, `scratchpad/lj5/LOG.md`: S6a changes nothing there, 0 of 256 jump-task starts are in the deep class because that task perturbs its starts far less than `run_v4`; identical marks on 256 fresh starts).
- **Arena:** the paired test against the `sprint_top_speed_v4_beyond_fresh128` champion has one discordant seed (12116, the only deep-class start of its 128), p 0.51, so S6a cannot win there and F1 stays that trial's champion. I added a 512-seed trial through the arena's own load / save (`scratchpad/sprint6/add_trial.py`, new entry only): `sprint_top_speed_v4_beyond_fresh512` (seeds 50001-50512, the same rules, nobody had used them for a choice), seeded it with F1 and challenged it with S6a (`scratchpad/sprint6/arena_s6.sh`): **S6a WINS, mean paired difference +1.56e7 (8 starts recovered, 0 new), p 0.005, and is the champion of that trial** (`bin/champions/sprint_top_speed_v4_beyond_fresh512-20261003-105956`). `arena.py recheck` of both sprint trials reproduces exactly (no drift); `run_gear.w`, `run_gearx.w`, `run_geary.w`, `run.w` and every earlier champion, params and controller are untouched.

### Heel recovery and the rectus femoris split (30 Sep): a data-only body `v5b`, and what the fold is not

Erik asked why every runner's trail-leg heel stays low (peak swing knee flexion about 98 deg, heel 0.35 m) while the Bolt reference folds to about 140 deg with the heel near the glute, and whether the model is missing momentum. Momentum and mass are modelled (rigid bodies with their inertia; the tendon force of the knee extensors acts at the knee: `scratchpad/heel/LOG.md`). Agent A5 then tested the anatomy (`scratchpad/anat5/LOG.md`, summary `scratchpad/anat5/REPORT.md`):

- The v4 split makes the rectus femoris (rf 150 N) 60 % of the hip flexion capacity and 34 % of the knee extension capacity; the muscle-architecture sources give 19-41 % and 15-22 % (OpenSim gait2392, Rajagopal 2016, Arnold 2010, Ward 2009; `scratchpad/anat5/lit/sources.json`).
- Two opt-in, data-only bodies: `playground/calibrations/v5.json` (rf 80, hip_flex_pos 170, knee_neg 286) and `playground/calibrations/v5b.json` (rf 80, hip_flex_pos 170, knee_neg 230: the vasti unchanged). `playground/body.py` is untouched and the scenes of 19 task/body combinations are byte-identical before and after. The unchanged sprint champion falls on v5 (0 of 12, a trunk-pitch runaway) and keeps running on v5b.
- On v5b the champion's gear-3 stride, unretuned, is faster and folds deeper: over 40 paired unseen flying starts steady speed +0.183 m/s (CI95 +0.163..+0.205), fold +15.2 deg (94.8 to 109.9), heel height at the fold +0.067 m; after 1000 evolution-search rollouts +0.295 m/s and +12.7 deg, while the v4 control gains +0.05..+0.08 m/s over 5059 rollouts.
- Replicated and validated (30 Sep, second seeds, `scratchpad/anat5/ab_final_table.txt`): on the same 44 unseen starts, v5b's final incumbents run 8.55 and 8.44 m/s steady against 7.86 and 7.86 for the two v4 controls (paired +0.68 m/s, CI95 +0.61..+0.76, and +0.59 m/s at equal budget, CI95 +0.57..+0.60), with 1 and 3 falls of 44 against 8 and 5. After search the gain shows up as a longer step (2.07-2.12 m against 1.91-1.96 m) and only +3 to +6.5 deg of fold, not the +15 deg of the unretuned stride. One stage, two seeds, a labelled body.
- **The command does not set the fold**: commanding 140 deg folds v4 to about 101 deg and v5b to about 111 deg and costs speed on both (7.82 to 7.03, 7.99 to 6.63 m/s) until the gait is retuned to a higher cadence and a shorter swing. So the answer is part model (rf strength above the sources), part controller (timing), part whip physics; not momentum.
- Verdict: GO as a labelled opt-in body (never compare its scores with the v4 trials); NO-GO as the default body and as a route to 10 m/s (gain +0.2 to +0.3 m/s; the standing-start chain plateaus at 6.4 m/s on v5b until a retune, and the long jump take-off, being oracle-class, does not transfer). Full numbers and caveats in the report; select the body with `ROBOLAB_BODY=v4 ROBOLAB_CALIB=v5b`.

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

#### Round 8: 40 strict starts, and what makes the transition fail (9/29)

New trial `soccer_single_leg_310_40` (40 fresh P2 resets, seeds 89100-89139;
the soccer_single_leg_310 environment, guards and metric; added through the
arena lock, per-seed rollouts cached under `scratchpad/soccer4/evalcache/`
by `scratchpad/soccer4/arena_cached.py`, which is `arena.py` with resumable
rollouts). The round-4 champion holds 300 s on **24 / 40** starts (0.60); the
round-5 lift challenger (`params/myo_soccer_single_leg_310_lift.txt`) on
**34 / 40** (0.85, paired diff +0.25, p = 0.006): promoted. The set-ramp challenger
below (`params/myo_soccer_single_leg_310_ramp.txt`, `bin/challengers/soccer6-i`)
holds **38 / 40** (0.95; p < 0.001 against the old champion, but the champion had
changed while it ran; against the promoted 0.85 champion +0.10, p = 0.115: it fixed
5 starts, broke 1, one fails in both, so it is not promoted). The shift-brake
challenger (ramp + `bshc`, `params/myo_soccer_single_leg_310_shc.txt`,
`bin/challengers/soccer6-p`) holds **35 / 40** (0.875, +0.025, p = 0.514, not
promoted): it fixes 5 of the champion's 6 falls (89106, 89110, 89115, 89117, 89133)
but 5 of its own 40 runs end in a MuJoCo blow-up inside a motionless hold (89122 at
15.8 s, 89130 at 141.0 s, 89134 at 134.2 s, 89135 at 130.2 s, 89103 at 255.6 s; the
champion and the ramp entry had one each), which breaks 4 starts the champion held.

| trial | champion before | challenger | stances holding 300 s | paired diff, p |
| --- | --- | --- | --- | --- |
| `soccer_single_leg_310_40` (new, 40 starts) | round-4 cp4 hold 24 / 40 | round-5 lift | **34 / 40** | +0.25, p = 0.006, promoted |
| `soccer_single_leg_310_40` | round-5 lift 34 / 40 | round-6 set ramp | 38 / 40 | +0.10, p = 0.115, not promoted |
| `soccer_single_leg_310_40` | round-5 lift 34 / 40 | ramp + shift brake | 35 / 40 | +0.025, p = 0.514, not promoted |

The trial can no longer tell balance controllers apart: the champion's 6 falls are
the only room for a gain, so a challenger needs 5 fixes and no break (p = 0.031), and
one blow-up among the 34 starts it must keep is enough to lose (a 6-1 result is
p = 0.06). Blow-ups hit 7 of the 120 arena runs (lift 1, ramp 1, brake 5: about 6 %).

What the failures are (scans of 120 fresh starts per configuration,
`scratchpad/soccer4/failscan.py`, `LOG.md`): 17 % of attempts fail within 8 s,
by last phase: hold 57 %, shift 33 %, lift 10 %. The outcomes are chaotic
(any change of the first 0.3 s re-draws about half of the failing starts) but
partly persistent, so variants are compared on 120 starts, not on the failing
ones. Measured, in the order they were found:

- **The set's ramp.** The chunk that replaces the reset posture (hip flexed
  +0.15) by the stance (extended -0.26) was a hard-coded 0.3 s and had never
  been tuned; it lurches the body from foot to foot and spins the feet. V4
  `bramp` / `b_t_ramp` makes it a tunable: 0.3 s 83.3 % standing with one-leg
  time (8 s), 0.2 s 91.7, 0.15 s 94.2, 0.1 s 96.7, 0.05 s 97.5 % (z +3.7);
  slower ramps are worse (0.45 s, 0.8 s). On 120 fresh validation starts
  (20 s) 0.05 s gives 93.3 % against 87.5 % (fixed 13, broke 6): the honest
  gain is about +6 %, the rest was selection. With the ramp the failures that
  remain are the lift's (6 of 8 caught by the put-down at ~3 s), and the
  right leg first holds as well as the left (111 / 120 at 8 s; the earlier
  "right leg is poor" was the parent's run-up shift/lift, not the leg).
- **The hold's hip strategy.** In the failing holds the pelvis rolls 0.1 -> 0.9 rad
  outward while the stance hip abducts to its -0.87 limit and the capture point
  runs to 1 m: cp4's hip strategy (throw the trunk into the fall; the sign is
  right, `cp_kh` +6 fails 8 / 10) is positive feedback for a slow outward drift.
  A weaker gain (`cp_kh` -6 against -13.9) fixed 5 of 7 hold failures with none
  broken on paired starts (the pre-lift trajectory is identical, so hold-phase
  parameters can be compared pairwise); `cp_wash` (fast part `cp_kh`, persistent
  part `cp_khs` of the opposite sign) and `cp_more` (swing-hip abduction and trunk
  bend on the excess) are built, untuned.
- **Drifts in the shift.** In the failing shifts the COM drifts 0.1-0.6 m behind
  the feet over ~2 s while both ankles sit at their dorsiflexion limit (+0.524)
  and the lateral shift stalls at 0.7 / 0.3 load. `dsx` (a sagittal hip strategy in
  double support), `dsi` (a lateral integral in the shift), `bfore` (fore-aft
  readiness for the lift), `bgset` (a stiffer set: 2.0 -> 66.7 %, worse) did not
  help; the ramp removed most shift failures by itself.
- **Catching does not help an outward fall.** `bretry` / `bcout` (catch the fall,
  retry the same leg) rescued 0 of 11 failing holds: once the roll has started
  the swing foot on the inner side cannot stop it.
- **The late failures are a simulator artefact.** One of the 34 holds (89106) stood
  perfectly still for 220 s and then fell: MuJoCo reports "Nan, Inf or huge value in
  QACC" at 222.07 s. The set-ramp entry's only late fall (89122, 15.8 s) and the only
  late fall after the brake (validation 91049: motionless from 4.6 s, roll -0.056,
  cp 0.000 cm, loads 1.00 / 0.00, then the warning at 16.52 s) carry the same
  warning. In every hold the swing shank rests on the stance thigh (`tibia_r` -
  `femur_l`, 1.1 mm penetration) with 190-230 N (12 of 12 starts; a steady
  period-5-step pattern, no growth before the blow-up); the sustained contact is what
  the solver blows up on. It is rare and chaotic, not a property of the posture: four
  cases in ~160 start-runs (89106 at 222 s, 89122 at 15.8 s in the ramp and brake
  entries alike, 89103 at 255.6 s in the brake entry, validation 91049 at 16.5 s), and
  shifting any of four hold parameters of 91049 by 0.002 rad removes its blow-up
  (4 of 4 hold 30 s). The official contact parameters are untouched. Clearance by
  posture: 0.1 rad more swing-hip abduction clears the thigh by 3.6 cm kinematically,
  but an abductor drive (`swabd`) leaves 208-219 N, `b_sw_knee` 1.0 gives 140 N (holds
  8 / 8 at 12 s) and `b_sw_knee` <= 0.8 or `b_sw_th` >= 0.5 fall. sep-CMA M (44 lift and
  hold parameters, 7 s, 24 random starts a generation, a penalty on the mean inter-leg
  force above 40 N; `scratchpad/soccer4/search5.py --leg_w`) took the force from
  ~200 N to 94 N in 7 generations (0 / 24 falls throughout); sep-CMA C2 (12 swing-leg
  and stance-posture parameters, 5 s, 4 starts a generation, 0.03 per N) to 25 N in
  18 generations. **Less contact, a less stable hold**: on 120 validation starts (20 s)
  the brake base holds 119, M's best with the brake 116 and C2's best 111 (each fixes
  the 91049 blow-up start and breaks 4 and 9 others); a snapshot of C3 (10 N) fell on 4
  of 8 unseen starts, all four with no inter-leg contact, while the four with 44-73 N
  stood. The leg contact holds the stance up (or 4-24 training starts are too few to
  keep the hold while the force is searched down): a clearance that keeps the hold needs
  16 or more starts per candidate and a re-evaluated elite. `scratchpad/soccer4/legforce.py`
  measures the inter-leg force and contact fraction of a params file (40 of 40
  validation starts: 215 N, contact in every step). Anatomy of one blow-up
  (`blowwarn.py`, a MuJoCo warning callback that dumps the state inside the failing step;
  91049 at 16.517 s): the 221 N `tibia_r` - `femur_l` contact at 1.07 mm, the stance
  foot's 125 + 119 N, 13 contacts against 15 a step earlier, and a swing-ankle chatter:
  `|qacc|` alternates between 5-9 and 83-90 from one control step to the next, all in
  `ankle_angle_r` (`chatter.py`: rms 62 rad/s^2 against <= 2.5 anywhere else in the
  body). It is a limit cycle of the leg reflex loop at the 100 Hz control rate: the
  rms is 60 at `k_leg` 45, 62 at 30, 38 at 28, 14 at 26, 11 at 24, 7 at 22 and none at
  20 (where the contact drops to 135 N but 2 of 8 starts fall), and 83 with lag-1
  autocorrelation -0.73 at `kd_leg` 0.2 (0.05 and 0 fall within 3 s). Every hold carries
  the limit cycle on top of the contact; whether either causes the blow-up (about one
  start in 40 over 310 s) needs a blow-up rate per arm, which one session cannot take.
  **Superseded by round 9 below: the cause is a MuJoCo tendon-wrap NaN (a rectus femoris
  line grazing its wrapping cylinder), not the contact, the solver or the limit cycle;
  the contact/qacc numbers above were read from MyoSuite's observation mirror `env.mj_data`,
  not the stepped data.**
- **The over-shift: what the failing lifts have in common.** The state at the first
  tick of the lift (240 starts, ramp base, left leg: validation 91000-91119 and
  training 90000-90119, `scratchpad/soccer4/liftfeat.py`) sorts the failures by one
  number, the stance foot's lateral capture point (`cpo`, outward +): -1.2 cm +- 0.8
  in the holds that stand, +0.8 cm in the 8 failing validation starts (z +7.5;
  training z +5.4). No hold failed with the capture point at or inboard of the
  foot's centre (0 of 212 lifts); 11 of the 28 lifts outboard of it fell within
  10 s (10 of 14 beyond +0.5 cm). It is set before the lift: the state at the
  shift's start predicts it (R2 0.63; the stance width alone r = -0.75, and every
  outboard lift has a stance narrower than 19 cm), because the shift is
  feed-forward: `b_shift_add` (0.187 rad) pushes the COM the same way whatever
  the width. **Waiting is fatal**: V4 `bcpo` (the lift latch also requires
  cp < b_cpo_max) fixed 0 of 11 and broke 13 of the 17 surviving lifts (36 starts,
  20 s: they fall in the shift 2.2-3.1 s in; the lift itself is what recovers
  them). `bshc` closes the loop inside the shift instead: while the swing foot has
  not unloaded, the stance foot's lateral capture point beyond `bsh_ref` trims the
  push (the stance hip's adduction down, the swing hip's up) by `bsh_k` rad per
  m, at most `bsh_lim`. Dose response on the 28 outboard-lift starts plus 8
  unaffected ones (20 s; a start where the brake stays off is bit-identical to
  the base, and the default-off build replays the base exactly):

  | brake (`bsh_ref`, `bsh_k`, `bsh_lim`) | of the 11 failing starts | broke (of 25 standing) |
  | --- | --- | --- |
  | -0.5 cm, 2 rad/m, 0.08 | 2 fixed | 0 |
  | -1 cm, 4 rad/m, 0.10 | 7 fixed | 0 |
  | -1 cm, 8 rad/m, 0.15 | 9 fixed | 1 |
  | -2 cm, 8 rad/m, 0.15 (`params/myo_soccer_single_leg_310_shc.txt`) | **11 fixed** | 0 |

  The setting was picked on those 36 starts. On all 120 validation starts (20 s) the
  base's 112 becomes **119** (fixed 8, broke 1; one-sided sign test p = 0.02) and on
  fresh starts 92000-92119 (the base already holds 117 / 120 there) 117 becomes 119
  (fixed 3, broke 1). No start falls in the shift or the early hold any more except
  92027 (2.7 s); what is left is the simulator (next bullet).
- **New V4 switches this round** (all opt-in, default off replays the older params
  bit for bit: checked on 36 and 8 starts and the arena's rollouts): `bramp` (`b_t_ramp`),
  `bgset` (`b_g_set`), `bfore` (`b_fx_tol`), `cp_wash` (`cp_khs`, `cp_tau`), `cp_more`
  (`cp_ksw`, `cp_klb`), `dsx`, `dsi`, `bretry` (`bc_retry`, `bc_short`, `bc_arm`), `broll`
  (`bc_roll`), `bwide` (`b_wide`), `swabd` (`sw_drv_abd`), `bcpo` (`b_cpo_max`), `bshc`
  (`bsh_ref`, `bsh_k`, `bsh_lim`); for phase 2 `sd` (`sn_d`), `k6` (`k6_t_hold`), `k7`
  (`k7_lean`, `k7_t_lean`, `k7_go`, `k7_t_max`) and `k4_cp`.
- **No selector for the stance leg.** Left first and right first each hold 112 / 120
  validation starts (20 s), both hold 106, the best leg per start 118 / 120, so a
  choice of leg could gain at most 6 starts. At the shift's start "stand on the right
  leg when the left foot carries more load" picks the better leg on 10 of the 12
  leg-specific validation starts, but on 6 of 10 on the training starts
  (left first 117 / 120, the rule 115): a chance fit among the ~8 features looked
  at (COM offset, stance width, loads, foot yaws, capture point). Dropped.
- **Phase 2 (the staged curriculum): no goals, no `soccer_p2` entry.** The stork stage
  is done (the routine holds either leg; the round-5 "right leg is poor" was the
  run-up's shift, not the leg). The phase-1 champion in the P2 env at the exact
  phase-1 posture and position scores 6 / 6 (12.3 m/s); joint noise of +-0.001 rad
  4 / 8, +-0.002 rad 0 / 8, +-0.01 rad 0 / 6; a start 5 cm short still scores, 10 cm
  short or 10 cm to one side falls at 0.9 s. Under +-0.002 rad the plant lands 30 ms
  later, the snap fires at the same toe-ball distance but the toe's lateral offset
  from the ball grows from 2 cm to 8-21 cm (the ball leaves at 2-7 m/s; a 5x
  stronger lateral aim servo changes nothing): the kick is a knife-edge trajectory,
  not a skill. From the routine's right-leg hold (V4 `k6`) the plant spot is 0.75 m
  ahead and the reach never lands the left foot (sep-CMA A, 13 generations, plant
  score 4.3 of ~13: the parent's reach needs the run-up's forward fall, the COM
  0.24 m ahead at the lift and 1 m/s forward / 0.86 m/s down at the plant); a
  standing kick from the robust left stance with the phase-1 swing (`k4`, `k4_cp`,
  sep-CMA K4, 24 generations) reached a ball speed of 1.7 m/s at best, and a lean
  phase before the reach (`k7`, A3) lands the foot on 1 of 6 starts. Coverage (a
  faster approach, a small ES-trained bounded residual) was not started.
- **Files and tools of this round** (state in the repo, running log
  `scratchpad/soccer4/LOG.md`): params `params/myo_soccer_single_leg_310_ramp.txt`,
  `params/myo_soccer_single_leg_310_shc.txt`; frozen challengers
  `bin/challengers/soccer6-a` ... `soccer6-p` (`-i` ramp, `-p` brake); the trial and
  champion in `playground/arena/`; in `scratchpad/soccer4/`: `arena_cached.py`
  (resumable arena), `evalstatus.py` (partial arena results), `failscan.py` (a params
  file on a seed list, phases and fall times), `cmpscan.py` / `cmpcpo.py` (paired
  comparisons of two scans), `liftfeat.py` (the state at the lift), `search5.py` /
  `search6.py` (sep-CMA on the hold with a leg-force term), `legforce.py`,
  `chatter.py`, `blowwarn.py`, `contactlog.py`, `trace_late.py` (the blow-up tools),
  `p1probe.py` (the phase-1 kick under start noise), `p2/` (the phase-2 stage bests).
  Next: (1) a swing posture or gain set that removes the blow-up without the hold's
  loss (16 or more starts per candidate, a re-evaluated elite, a blow-up rate per arm
  measured over a few hundred hold-seconds x starts) [not needed: round 9]; (2) a trial that can certify the
  gain (more starts, or a 20 s metric beside the 300 s one) [done: round 9]; (3) phase 2 needs a
  closed-loop kick, not another search on the phase-1 trajectory.

#### Soccer round 10: the closed-loop kick (9/29, agent P): no-go, and why

Asked for: the first real phase-2 goals from a closed-loop kick (a toe-to-ball servo in the last 100 ms on the phase-1 trajectory), grown stage by stage, with a
go/no-go after the noise ladder. **Verdict: no-go.** No closed loop on the phase-1 kick closes even the +-0.002 rad rung (29 % of held-out starts score, from
96 % without noise), no `soccer_p2` entry was made (0 / 100 goals for every controller, so nothing to promote), and the measurements below say why: the swing is not
where the noise is decided, and the kick's structure depends on a leg-on-leg contact that the swing-phase controls measured here cannot steer. Everything is in
`scratchpad/kick/LOG.md` (every run with its command line); tools and the skill are listed at the end.

**Three facts about the environment that change the target** (read from the MyoSuite source and checked on the model)

- *The goalkeeper is a decoy.* MyoSuite steps the physics on `robot.mj_data`; `env.mj_data` (what the bridge and the env's `step` read and write) is a mirror rebuilt from
  the sensors after every step. The keeper's mocap body is moved on the mirror only, so the OBSERVED keeper (random y; stationary / random / block_ball for 58 / 30 / 12
  of seeds 5000-5099) never touches the ball, while the PHYSICAL keeper stands still at (50, 0) with a 0.25 m capsule: a 12 m/s ball aimed at y = 0.0 comes back, y = +0.3
  is deflected, |y| >= 0.5 crosses clean. The scoring window is cross y in +-[0.5, 3.2], a launch angle of +-[2.9, 17.8] deg; the champion's two aims (y +1.1 / -1.8) sit in it.
  (Consequence for tooling: snapshots of the physics must read and write `robot.mj_data`; an open-loop replay from a saved state with the recorded activations is then
  bit-identical, and so is a fresh controller re-fed the recorded sensor lines: `scratchpad/kick/kreplay.py`.)
- *Coverage.* The official starts (seeds 5000-5099) are 0.15 / 0.3 / 0.5 / 0.75 / 1.0 m or less from the phase-1 stance for 2 / 6 / 20 / 42 / 77 of the 100; behind the
  stance by <= 0.3 m and |dy| <= 0.3 m: 10. A perfect kick that needs the phase-1 stance to +-0.3 m can score at most ~6-10 goals.
- *The kick needs ~+-2 cm laterally.* Champion, noise 0, root offsets (6 starts each): dx -0.02 / -0.05 m 6 / 6 and 6 / 6, -0.075 / -0.1 m 0 / 6 (the plant lands short and
  the run-up falls), +0.03 / +0.05 m 3 / 6 and 6 / 6; dy +0.02 m 3 / 6, -0.02 m 0 / 6 (a 11 m/s ball, then a fall), +-0.05 and +-0.075 m 0 / 6.

**The noise ladder** (full rollouts, official metric `goal`, held-out seeds 6000-6047, phase-1 champion `bin/champions/soccer_p1-20260926-151503`; noise scale x the P2 draw of
+-0.02 rad on every joint, root at the phase-1 stance; `scratchpad/kick/kltable.py`, `out/ladder_champion_48.json`)

| rung | noise | plant landed (swing reached) | touched | ball >= 8.5 m/s | inside the window | goals | fell before the touch | fell at all |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | none | 48 | 48 | 48 | 47 | 46 | 0 | 2 |
| 0.05 | +-0.001 rad | 48 | 48 | 39 | 27 | 18 | 0 | 27 |
| 0.1 | +-0.002 rad | 48 | 48 | 23 | 15 | 14 | 0 | 28 |
| 0.25 | +-0.005 rad | 48 | 41 | 9 | 6 | 8 | 5 | 36 |
| 0.5 | +-0.01 rad | 48 | 34 | 5 | 1 | 0 | 14 | 44 |
| 1.0 | +-0.02 rad (official noise, phase-1 position) | 47 | 28 | 3 | 1 | 0 | 20 | 46 |

Per stage, all of 48 held-out starts (seeds 6000-6047): the plant lands in every start at every rung, so the failure is not "the run-up falls before the kick" until +-0.005 rad; it is a kick
that happens and goes slow or sideways (mean ball speed 12.3 / 9.8 / 7.9 / 4.8 / 3.8 / 1.9 m/s) and a body that falls after it (27 of 48 at +-0.001 rad).

(Development set, seeds 5000-5071, `kladder.py`: +-0.001 rad 38 / 72, +-0.002 rad 18 / 72.) On the official reset (`soccer_p2` seeds 5000-5099) the champion, whose default
`approach` walks quasi-static steps to the stance first, per stage: on its feet at 1.5 s 75 / 100 (median fall 1.68 s), run-up reached the swing 1, touched the ball 1, goal 0
(within 0.3 m of the stance: 6 / 6 up at 1.5 s, still 1 touch). Agent O's numbers for the other stages stand: plant from the right-leg hold best 4.3 of ~13, standing kick
1.7 m/s, coverage not started. Mine below.

**What limits the swing-phase closed loop** (each item is a measurement; the tools are in `scratchpad/kick/`)

- *Where the noise grows* (`kdiverge.py`, +-0.001 rad, distance to the noise-0 run of the same seed): joint vector 0.02 rad at 0.3 s, 0.04 at 1.0-1.3 s, 0.10 at the reach, 0.22-0.30
  at the plant, 0.68 at 2.0 s; the toe's lateral error 1.5 cm at the swing start, 7.4 cm (max 13.6) at the touch. The state at the swing start predicts the contact badly (ridge on 45
  features: contact y R2 0.3, ball speed 0.7; best single-feature AUC 0.72), yet the swing itself is smooth: +-0.005 rad of joint noise at the swing start moves the contact by
  0.5-0.9 cm (`klip.py`). The deviation is the large structured one (hip rotation -0.29 vs -0.71 rad) that the run-up leaves.
- *Oracle headroom* (`khead.py`, replays from the swing start on 48 noisy starts, champion 16 / 48 good): the best of 24 random +-10 % variants of 13 swing parameters, chosen per
  start, is good on 22 / 48. The failures are set by the state the run-up delivers to the swing (the plant lands in every start, but with a different body); no choice of swing parameters, and so no feedback on them, recovers most of them.
- *No authority in the aim servo.* The kicking hip's adduction sits on its 0.5236 rad limit from 1.87 s to the touch in every kick (the champion's `k_ky` servo drives it there:
  5x its gain changed nothing, as O found), and joint-offset targets on the hip rotation go through the reference length tables, which in the swing posture give the wrong sign
  (`rot_k` +0.3 moved the achieved rotation by -0.07 rad). In torque space (live moment arms, `kauth.py`: 20 N m for 80 ms about one joint of the kicking leg, spread over the muscles
  that cross it) the contact moves +-3-7 cm at best and the ball loses 1-4 m/s; plant-leg and trunk torques move it 1-3 cm.
- *The kick is guided by leg-on-leg contact.* Thigh-thigh and shank-shank contact of 1.3-2.6 kN in every phase-1 kick (14-25 ticks in the fast ones; the slow ones stay in contact 17-65 ticks and add foot-foot contact);
  with the model's 14 explicit contact pairs switched off (diagnostic, `KICK_NOLEGCOL=1`) the champion scores 0 / 16 at noise 0 (16 / 16 with them). Moving the plant foot 5-20 cm
  sideways (`plant_dy`), which would clear the legs, breaks the kick at noise 0: the run-up, plant and aim are co-tuned.
- *Which reset noise matters* (`kladder.py --groups`, +-0.002 rad on a subset of the 48 joints, 16 starts, goals): spine only 13, right leg only 5, left leg only 9; right hips 11, right knee
  13, right feet 13, right SLAVED KNEE JOINTS (the 8 equality-constrained translation/rotation/patella coordinates, given noise of their own = a constraint violation the solver removes
  with a jolt at t = 0) 7, left slaved knee joints 8. A long settle does not filter it (t_set 1.5 s: the joint-vector deviation is still 0.26 rad after 1.4 s at the official noise, the soft joints keep
  their angles, the COM is back within 2 cm), and the phase-1 run-up does not start from a settled stance (0 / 8 at noise 0).
- *The falls after a good kick* (19 % of the +-0.001 rad kicks, 11 % at +-0.002) are a flight, not a loss of balance: 0.2 s after the touch both feet carry 0 % of the weight (straight plant leg,
  the follow-through's reaction; pelvis 1.00 -> 1.07 m, yaw swings -0.27 -> +0.56 -> +2.1 rad), the plant foot whips 0.7 m across, the landing is rotated. The single-leg routine's stance terms after
  the touch (`kr`: cp4 + twist-limited heading hold with the hold's parameters) take the noisy good-contact starts that stay up until the goal from 27 to 31 of 40 on the training set and from 18 to 19 of 27 on held-out ones (fixed 3, broke 2), but at noise 0 they
  break the champion's own follow-through: 6 / 12 goals instead of 12 / 12 (`kltable.py`, seeds 6000-6011). One-parameter scans of the follow-through, landing and plant-leg posture around it move the
  40-start score by at most +1, and a torque-space brake of the follow-through does nothing.
- *Landing the plant foot on the capture point* (`kp`, the plant stage: the reach lands its foot on a fixed spot beside the ball while the body is falling onto it): moving the landing spot by the COM's
  velocity times a gain (`kp_cpx` forward, `kp_cpy` sideways; full rollouts, held-out seeds 6000-6047, goals of 48 at noise 0 / 0.05 / 0.1 / 0.25): champion 46 / 18 / 14 / 8; `kp_cpx` -0.05: 47 / 29 / 11 / 3; -0.1:
  48 / 20 / 9 / 5; the sideways gain trades one side's lateral tolerance for the other's (`kp_cpy` -0.03: dy -0.02 m 6 / 6 but dy +0.02 m 0 / 6 and noise 0 3 / 6). A mixed picture within the sampling noise
  of 48 starts (the champion scores 38 / 72 at +-0.001 rad on the development seeds and 18 / 48 on the held-out ones), so not adopted.
- *The kc terms* (torque-space aim, heading, height and speed channels on the swing): one-at-a-time scans of ten gains by hand on 48 noisy starts (champion 16 / 48 good): +300 / -300 on the rotation
  channel 12 / 14, adduction 16 / 16 (pinned on its limit), velocity terms 9-17; sep-CMA over 40 swing, aim, recovery and kc parameters (`runE2.sh`, replays from the swing start) and over the 11 kc
  gains (`runE2b.sh`) stopped after one generation each: x0 stayed the best, and the headroom measurement above says why.
- *The standing kick* (wind-up on the plant leg, then a swing from rest; the state to start from would be repeatable): with the ball in front of the kicking foot the wound-back foot still ends 0.3 m LEFT of
  the ball's line, because the pelvis yaws -0.45 .. -1.1 rad on the plant foot during the wind-up (the plant hip's rotation hits its -0.7 stop; the known one-leg heading blocker, README round 3). A torque
  heading hold on the plant hip (clipped at the foot's ~50 N m grip) moves the yaw at the swing start from -0.56 to -0.45; kicks 0-2 m/s, 0 goals.

**What was built** (opt-in, the champion replays bit for bit with every switch off: checked on noisy dumps for the first and the last build)

- `lib/robolab/skills/myo_kick.w` (+ `lib/entry/myo_kick.w`, `./build.sh myo_kick`; `MyoKickSkill < MyoSoccerV4Skill`): `kc` torque-space channels on the swing (kicking hip rotation / adduction from the toe's
  lateral error and velocity, plant-hip heading and adduction, knee and hip from the toe's height and speed against the practised path), `kr` (routine stance terms after the touch, plus a plant-leg posture
  and a torque brake for the follow-through), `kp` (capture-point placement of the plant step), `kw` / `kt` (a standing kick's wind-up and swing as a joint torque servo of the kicking leg, and a torque heading hold), the torque ones through one generic channel
  (`kc_torque`: a joint torque spread over the muscles by their live moment arms, the way `Controller#split_torque` does with the geometry's). Params `params/myo_kick_base.txt` (champion + `kc 1`,
  `sense_arms 1`, gains 0), `params/myo_kick_kr0.txt`, `params/myo_kick_kp1.txt` (the best rung-0.05 variant, not adopted), `params/myo_kick_lab0.txt`; frozen `bin/challengers/kick-a0` ... `kick-a9` (a9 is the current `bin/robolab_myo_kick`; with `params/myo_kick_base.txt` it replays the 16 noisy dumps I checked bit for bit and scores 0 / 100 on `soccer_p2` like the champion: entered in the arena for the record, not promoted).
- The harness (`scratchpad/kick/`): `kcommon.py` (per-tick sensor lines, replies and physics state of a run; controllable reset: the P2 draw x a noise scale, joint groups, root offsets), `kladder.py` /
  `kltable.py` / `kstages.py` (ladders and stage counts), `kprobe.py` / `kauth.py` / `kfb.py` (open-loop physics probes and authority maps from a saved state), `kreplay.py` (a saved state restored, a
  fresh controller re-fed the recorded sensors, then live: identity check bit for bit; ~0.5 s per replay), `kbatch.py` / `kscan.py` / `ksearch.py` (batches, one-at-a-time scans and sep-CMA on replays,
  resumable), `khead.py`, `kdiverge.py`, `kpredict.py`, `kdiscrim.py`, `klip.py`.

**Next, if this line is continued** (none of it is a swing-phase feedback): a kick whose plant foot stands beside the ball, so the swing needs no leg-on-leg contact, re-optimised stage by stage from
checkpoints with the replay harness (swing from the plant, plant from the lift, ...); a torque-space stance and heading controller for the run-up in place of the offset servos (live moment arms are
the mechanism that works at the hip); and an approach, which needs a walking gait this body has not shown (the spine folds), since 0.3 m of coverage is at most 6-10 of the 100 starts.

#### Soccer round 9: the hold blow-ups (9/29)

The blow-ups inside motionless one-leg holds ("Nan, Inf or huge value in QACC at DOF 6", 7 of 120 arena runs and validation start 91049)
are **a MuJoCo 3.6.0 arithmetic bug, not a property of the stance**, and not the 215 N leg contact or the solver. Written up with a minimal
reproduction, the source location and a one-line fix in `playground/repros/mujoco_wrap_nan.md` (not filed anywhere: Erik decides); the
arena now has guarded trials that do not lose holds to it.

- **Root cause.** MuJoCo's `length_circle` (`engine_util_misc.c`, tendon wrapping around a cylinder or sphere) computes `acos(dot(p0n, p1n))` of
  the two normalised tangent points. When a tendon line only grazes the wrapping cylinder (relative margin `(r^2 - d^2) / r^2` under
  ~6e-8, a line within ~1 nm of the tangent for r = 25 mm) the points are ~2e-8 rad apart, the dot product of two unit vectors
  rounds above 1.0 in about one case in ten, `acos` returns NaN, and `mju_wrap`'s `wlen < 0` test does not see it: the tendon length,
  moment arms and muscle force turn NaN, `qacc` goes NaN on the whole tree (DOF 6 is only the root's first dof: dofs 0-5 are the ball's
  free joint, 6-11 the kicker's), `mj_checkAcc` resets the data and the kicker falls 0.2-0.4 s later. In every hold blow-up the tendon is
  the same one: `recfem_r_tendon`, the swing leg's right rectus femoris (path pelvis -> cylinder `KnExt_at_fem_r_wrap` -> patella), the only one of the
  68 wrapped tendon segments that hovers at its tangent in the holds (`ring_segments.py`). It is not specific to that muscle or to holds: the guarded
  arena runs also caught `IL_L1_r_tendon` (a trunk muscle wrapping `back_cylinder_s`) at 2.12 s of start 96029, a NaN the official environment would have scored as a balance failure.
- **Evidence.** Deterministic repro (`scratchpad/blowup/capture.py`, 16 s wall, bit-identical MjData over all 1651 control steps on two runs;
  bit-exact open-loop replay of all 16 500 substeps from the recorded controls): 91049 at 16.517 s, 89122 at 15.811 s, 89134 at 134.214 s, 89135 at 130.209 s,
  89130 at 141.040 s, and the guarded reruns hit 89103 at 255.550 s and 89106 at 222.068 s at the same instants. At the failing substep exactly one tendon length
  is NaN and `mj_fwdPosition` (kinematics + tendons: no solver, contact or actuator) already returns it; the state holds no precursor
  (`precursor_scan.py`: contact count, constraint count, solver iterations, largest constraint force, the leg-contact force, joint
  limits, muscle forces: no jump into the last substep beyond their ordinary substep-to-substep changes; the Newton solver converges in one iteration throughout).
  Sweeping one hip angle 2e-6 rad in 1e-10 steps through the failing state (40 001 real `mj_fwdPosition` calls): 272 NaN, all with the wrap active and margin
  <= 5.5e-8, the NaN fraction following the exact 60-digit `1 - dot` (30 % below 1e-17, 6 % near 1e-16, 0 above 2.5e-16). A standalone C harness of the 3.6.0 wrap code
  (`playground/repros/mujoco_wrap_nan_harness.c`): 6834 NaN in 40 001 points, all with `dot > 1.0`, and 0 with the dot clamped. A pure-MuJoCo model (`mujoco_wrap_nan_repro.py`, one
  cylinder, three sites): 859 NaN of 8001 cylinder points, 651 of 8001 sphere points. Upstream `main` (fetched 9/29) has the same four functions byte for byte.
- **What the bisect excludes** (`scratchpad/blowup/bisect_variants.py`, private model copies): on the bit-exact failing substep the tendon NaN survives every change of
  timestep (dt/2), solver (CG, PGS), iterations (500, tol 1e-12), cone, impratio, noslip, islands, integrator (implicitfast), Jacobian, warmstart, contacts off, the
  tibia_r - femur_l pair removed or softened, muscle activation dynamics x2, the wrap's sidesite removed, and swing-ankle damping; only wrap-geometry changes (radius x(1 + 1e-6), x(1 - 1e-3), 0) remove it. From 300 steps earlier only the
  variants that keep the trajectory bit-identical reproduce the event at 16.517 s; every other change re-rolls the rounding, which is why O's 0.002 rad change of a hold parameter "cured" 91049 4 of 4 times.
- **Why it looked rare and chaotic.** The sliver is ~1 nm wide and each visit to it is NaN with probability ~0.1, but the parked swing leg keeps returning to it: the captured
  blow-up holds are strong hoverers (the rectus femoris line within 1e-3 (12 um) of the tangent in 34-94 % of the control steps, 57-335 tangent crossings in 15-20 s; 91049: the margin settles
  from +7e-4 to ~0 within 4 s and stays at 0 +- 2e-4 while the swing ankle chatters by 4e-3 rad from one control step to the next and the hip by 1e-4 rad), and the line visits `0 < margin < 6e-8` at random:
  in 91049 twice in 16.5 s (11.236 s survived, 16.517 s NaN). Telemetry of the guarded runs on 120 fresh starts per entry (below) puts the population figure at 0.4-1.4 % of the hold's substeps within 1e-4 of the tangent,
  and a NaN hazard set by how much of a start's hold sits there, hence ~6 % of the 310 s holds.
- **What O's tools read.** `env.unwrapped.mj_data` (`MyoSim.d`) is not the stepped data: MyoSuite's `Robot` owns its own `MjData` and steps that; `env.mj_data` is a mirror re-synced
  once per control step (time, qpos, qvel, act, then `mj_forward`; ctrl 0, no warm start). The contact, qacc and efc numbers of `blowwarn.py`, `contactlog.py`, `chatter.py` and `legforce.py`
  are the mirror's. The same NaN also reaches the controller through it: a sliver state at a control-step boundary is evaluated by the mirror first, the controller
  receives a NaN muscle length, MuJoCo answers "CTRL at ACTUATOR 239" and zeroes *all* controls (89103, 89130).
- **The fix (a labelled variant, not an edit of the official environment).** The bug is in MuJoCo, so the repo cannot fix it; the report proposes the one-line fix
  (`mju_clip` the cosine in `length_circle`, checked on the C harness: 6834 NaN -> 0). `playground/tasks/myo_soccer_ng.py` (the soccer task with a NaN guard; env
  `MYO_SOCCER_NANGUARD=0` counts only) advances the stepped `MjData` through a guard: snapshot the integration state, `mj_step` exactly as MyoSuite does, and only when MuJoCo reset
  the data *and* a tendon length is NaN at the snapshot redo the substep after a deterministic 1e-10 rad nudge of the joint angles (x10 every three tries); any other
  instability is replayed as MuJoCo produced it (`nan_other`, 0 so far). The mirror (`env.mj_data`) is checked after every control step, because a sliver state at a
  control-step boundary reaches the controller first (guard v1 without this lost 89103 and 89106 within a second of the event: all controls zeroed). Until a NaN a rollout is
  bit-identical to the official environment's: 89101 25 s (same final `MjData` hash), the six event-free re-runs of the failing starts of the guarded trial (5 lift falls, the ramp's 89133: every
  base metric equal to the official row), and the official-vs-guarded identity scan of the 120 hold20 starts (119 of 119 event-free starts identical in every base metric; the 120th, the trunk
  event of 96029, officially falls and passes guarded). All seven known events reproduce at the official instants and are survived:

  | start | entry | official: NaN at, fall | guarded: events | guarded 310 s run |
  | --- | --- | --- | --- | --- |
  | 89106 | lift | 222.068 s, falls 222.4 s | 2 (222.068, 227.74) | holds, bal1 307.6 |
  | 89122 | ramp, brake | 15.811 s, falls 16.15 s | 2 | holds, 308.5 |
  | 89130 | brake | 141.040 s, falls 141.24 s | 1 | holds, 308.1 |
  | 89134 | brake | 134.214 s, falls 134.57 s | 1 | holds, 308.6 |
  | 89135 | brake | 130.209 s, falls 130.55 s | 1 | holds, 308.1 |
  | 89103 | brake | 255.550 s, falls 255.75 s | 1 | holds, 308.2 |
  | 91049 | brake | 16.517 s, falls 16.86 s | 1 | stands to 30 s, bal1 28.3 |

- **New trials** (arena lock, `scratchpad/blowup/add_trials.py`; per-start tables in `scratchpad/blowup/RESULTS.md`; `arena_ng.py` is `arena.py` with a rollout cache keyed by the
  task source): `soccer_single_leg_310_40_ng` (the 40 starts of `soccer_single_leg_310_40`, 310 s, `bal1_300`) and `soccer_hold20_120_ng` (120 fresh starts, seeds 96000-96119,
  20 s, `hold20` = standing since the start and on one leg for the last 15 s). Both run `myo_soccer_ng`. The three entries of round 8:

  | entry | `soccer_single_leg_310_40` official | `_ng` (310 s, 40 starts) | `soccer_hold20_120_ng` (20 s, 120 starts) |
  | --- | --- | --- | --- |
  | round-5 lift | 34 / 40 | 35 / 40 (seeded) | 102 / 120 (seeded) |
  | round-6 set ramp | 38 / 40 | 39 / 40, +0.100, p = 0.066: not promoted | 113 / 120, +0.092, **p = 0.006: promoted** (fixed 14, broke 3) |
  | ramp + shift brake | 35 / 40 | **40 / 40**, +0.125, **p = 0.034: promoted** (fixed 5, broke 0) | 118 / 120, vs ramp +0.042, p = 0.067 (fixed 6, broke 1); vs lift +0.133, p < 1e-4 (fixed 16, broke 0) |

  The guard turns the brake from the entry that lost 5 holds to the blow-up (35 / 40) into the first to hold five minutes on all 40 stances, and reverses the official ranking (lift 34,
  brake 35, ramp 38 -> lift 35, ramp 39, brake 40). The 310_40_ng trial is now saturated (no room above 40 / 40): early-fall gains are certified on `soccer_hold20_120_ng`
  (the ramp's gain, +4 starts at p = 0.066 on the 40-start trial, is +11 starts at p = 0.006 there); a five-minute trial with more starts costs about 3 h per entry for 120 (see the scan below).
  The five real falls of the lift entry (89110, 89115, 89117, 89130, 89133) and the ramp's 89133 reproduce the official rows exactly and had no NaN: they are balance failures.
  hold20 falls happen at 1.3-11 s standing (the lift, the shift, the first seconds of the hold); the passes hold from ~2 s to 20 s. Failing starts, lift (18): 96023 96033 96039 96043
  96045 96052 96055 96064 96067 96070 96081 96086 96095 96096 96098 96100 96105 96116; ramp (7): 96011 96055 96059 96095 96098 96103 96116; brake (2): 96023, 96116.
- **Hazard exposure per entry** (telemetry of the guarded hold20 runs: the right rectus femoris's margin at every substep after 3 s, 120 fresh starts x 20 s per entry, all real runs):

  | entry | substeps within 1e-4 / 1e-5 / 1e-6 of the tangent | starts with > 1 % of the hold within 1e-4 | sliver states (0 < margin < 1e-7), survived + NaN, per 1000 start-seconds |
  | --- | --- | --- | --- |
  | round-5 lift | 0.48 % / 0.047 % / 0.005 % | 5 of 116 | 3 + 0 (1.7) |
  | round-6 set ramp | 1.21 % / 0.119 % / 0.013 % | 25 of 119 | 7 + 0 (3.6) |
  | ramp + shift brake | 1.41 % / 0.153 % / 0.016 % | 25 of 120 | 21 + 1 (10.9) |

  The ramp family parks the swing leg's rectus femoris at its wrap tangent about 3x more than the lift entry does (per-start paired sign-flip p = 1e-4 for ramp and for brake against lift at 1e-4 and 1e-5, 0.005 and 3e-4 at 1e-6),
  while brake against ramp is not different (p = 0.31, 0.12, 0.09): the ramp's swing posture is where the hazard lives, and O's "the brake raises the hazard" was that plus a 5-against-1 draw
  (official counts 1 / 1 / 5 in 10.8 k / 11.8 k / 11.5 k start-seconds; exposure-proportional expectation 0.9 / 2.8 / 3.3).
- **Blow-up rate per entry** (counts, not impressions). Official runs (each first event ends the hold): lift 1 in 10 783 start-seconds, ramp 1 in 11 799, brake 5 in 11 529, i.e. 0.09 / 0.08 / 0.43 per 1000
  start-seconds, 7 in 34 111 pooled (1 per 4.9 ks, 6 % of the 310 s holds; brake against the other two, one-sided p = 0.05). Guarded (every event counted, the passing starts identical to the official runs and so event-free):
  310 s x 40 starts: lift 2 events in 10 876 start-seconds (89106 twice), ramp 2 in 12 095 (89122), brake 6 in 12 400 (0.18 / 0.17 / 0.48 per 1000); 20 s x 120 starts: lift 1 (a trunk tendon) in 2 112 start-seconds,
  ramp 0 in 2 304, brake 1 in 2 375. All 10 distinct events (8 in the 310 s runs, 89122 counted once; 2 in the 20 s runs) were nudged (`nan_nudged` = `nan_events`); no event went unrecovered and no other reset occurred (`nan_other` 0 in every entry); 4 of the 10 were control-step-boundary (mirror-first) events (89103, the second of 89106, 89130, 96029). Mechanism closure on the brake, all 40 starts of the 310 s trial run for real (`full310.py`: the 35 passing starts re-run for the full 310 s, each identical to its official row in every base metric and event-free, plus the
  5 re-runs; 12 400 start-seconds, 12.28 M substeps of the right rectus femoris watched): **60 states in the NaN sliver, 54 survived and 6 NaN**; the table of P(NaN | exact 1 - dot) measured on the real library
  (three geometries) predicts 6.27 events for those 60 states, observed 6 (P(NaN | sliver state) = 0.10, 95 % 0.05-0.20); the exact 1 - dot of the six is 4.6e-19 ... 5.8e-17. The wrap was within 1e-4 / 1e-5 / 1e-6 of the tangent in 1.0 / 0.10 / 0.010 % of the substeps
  (against 1.4 / 0.15 / 0.016 % in the first 20 s: the exposure per second is lower in the long holds).
- **The five-minute hold on fresh starts (a supplementary scan, not an arena trial).** The brake at 310 s under the guard on 69 of the 120 fresh hold20 starts (96000-96038 and 96060-96089; the
  rest was not run, the machine was loaded, and the 120-start trial `soccer_single_leg_310_120_ng` was withdrawn unseeded; `prefill_310_120.py`, `add_trial_310_120.py` and `analyse_120.py` resume it):
  **68 / 69 hold 300 s**. The one failure is 96023, the hold20 fall at 11.1 s; none of the 68 starts that pass hold20 fails later. 15 NaN events in 6 starts, all `recfem_r_tendon`, all survived (`nan_other` 0):
  96081 x7 (first at 14.3 s), 96010 x4 (25.1 s), 96088 (31.4 s), 96070 (50.2 s), 96022 (191.1 s), 96080 (282.7 s); in the official environment each of those six holds would have ended at its first event, so it would
  have held 62 of the 69. Mechanism check on this second set: 224 sliver states (209 survived + 15 NaN), the table predicts 15.8 events, observed 15 (P(NaN | sliver state) = 0.07). Pooled with the 40-start
  trial: **108 / 109 five-minute holds under the guard** (the one fall is the real hold20 failure 96023) against 97 / 109 in the official environment (11 holds lost to the bug, plus that fall).
- **Files and tools of this round** (state in the repo, running log `scratchpad/blowup/LOG.md`, per-start tables `scratchpad/blowup/RESULTS.md`). New: `playground/tasks/myo_soccer_ng.py` (the guarded task);
  `playground/repros/mujoco_wrap_nan.md` with `mujoco_wrap_nan_repro.py`, `mujoco_wrap_nan_harness.c`, `myosuite_soccer_wrap_nan_state.py` and `mujoco_wrap_nan_states/` (five 7.5 KB saved `MjData` states) - self-contained
  and not filed anywhere; the trials `soccer_single_leg_310_40_ng` and `soccer_hold20_120_ng` in `playground/arena/trials.json` (champions frozen in `bin/champions/`, entries in
  `history.jsonl`); in `scratchpad/blowup/`: `capture.py` (an arena rollout with a MuJoCo warning callback and a ring of `mj_getState` per control step), `replaylib.py` (bit-exact replays), `wrapdiag.py` / `wrapscan.py`
  (a port of `wrap_circle`; the margins of all 68 wrapped segments), `hazard_replay.py`, `nan_band_scan.py`, `bisect_variants.py`, `precursor_scan.py`, `knee_map.py`, `ring_segments.py`, `margin_trend.py`,
  `analyse_fail.py`, `guardscan.py`, `test_guard.py`, `arena_ng.py` (the arena with a resumable rollout cache), `add_trials.py`, `prime_310.py`, `full310.py`, `identity_scan.py`, `analyse_arms.py`, `analyse_mechanism.py`,
  `analyse_full310.py`, `analyse_120.py`, `prefill_310_120.py`, `add_trial_310_120.py`, `make_tables.py`. Unchanged: `myo_soccer_v4.w`, the bridge, the SDK, the arena code (`playground/arena/README.md` gained a note on the `_ng` trials). Two things to know about the
  310_40_ng entries: their passing rows were copied from the identical official runs (each cache entry says `primed_from`; 35 of the brake's were then re-run for real and matched), and the `report` means of their
  `nan_*` keys cover only the re-run starts.
- **Next.** (1) Erik decides on an upstream report: the repro file has versions (3.2.7 ... 3.14.0 give the same counts), source lines, a minimal reproduction and the one-line fix. (2) Balance work should use the `_ng`
  trials: `soccer_hold20_120_ng` has room (champion ramp 113 / 120, brake 118 / 120), the 40-start 310 s trial is saturated by the brake. Searches (`search5.py`) still use the unguarded task, where a NaN costs one
  candidate-start in about 5000 s. (3) The official `soccer_single_leg_310_40` board is unchanged (lift, 34 / 40): its brake and ramp entries lost 5 and 1 holds to the bug. (4) Other bodies: the shared
  `MUJOCO_LOG.TXT` has late warnings only from the soccer body (the other tasks' QACC / CTRL warnings are all early, under 5 s, candidate instabilities), so no other task is known to be affected, but any MyoSuite model
  with wrapped tendons can meet the sliver and the guard class is model-agnostic. (5) Phase 2 is unchanged (no goals).

#### Soccer round 11: a hold that avoids the wrap tangent (9/29, agent Z)

**Result.** The OFFICIAL, unguarded `soccer_single_leg_310_40` (unmodified `myo_soccer`, five minutes on one leg, 40 fresh starts, seeds 89100-89139) now comes out at **40 / 40**
(champion round-5 lift 34 / 40; +0.150, paired p = 0.015, fixed 6, broke 0: promoted; against the shift brake it fixes its five blow-ups and breaks none). The controller is the brake with one new opt-in
switch that parks the swing knee 0.2 rad lower in the hold (`params/hazard/myo_soccer_310_shc_h2b.txt`, `bin/challengers/soccer7-bh1`). Nothing of the environment, the bridge, the SDK or the arena code was touched.

- **Why the leg hovers on its wrap tangent (measured, `scratchpad/hazard/`).** The margin `(r^2 - d^2) / r^2` of a wrap (d = distance of the tendon line to the cylinder axis; MuJoCo's NaN needs 0 < margin < 6e-8)
  is, for the swing rectus femoris, a function of the parked swing knee angle: `+2.46` per rad (offline: `geom.py`, `kneeseg.py` on the 91049 capture), plus `-73.8` per METRE of the patella's follower coordinate
  (`knee_angle_r_beta_translation1`: the joint equality is soft and the quadriceps force stretches it by ~0.5 mm = 0.04 of margin = 0.015 rad of knee); hip flexion `-0.27` per rad, hip rotation `+0.11`, hip adduction `+0.013`,
  ankle, subtalar, the other leg and the trunk 0. Every wrap segment of the right leg has its own tangent knee angle: bfsh_r 1.283 rad, vaslat_r 1.447, vasmed_r 1.602, vasint_r 1.646, recfem_r 1.678 (only recfem_r's moves with the hip:
  +0.11 rad per rad of hip flexion; the vasti and bfsh start on the femur); the adductors, gastrocnemii, hamstrings, gracilis, glmax3 and iliacus have none between 0.9 and 2.1 rad. The champion's swing knee COMMAND
  (`b_sw_knee 1.8`, tuned by sep-CMA in rounds 4-5) parks the knee at **1.6757 rad, 0.002 rad from recfem_r's tangent**: in 55 of 60 practice starts the tendon line is within 1e-3 of its tangent in some control steps (worst start
  95 %, 1 545 tangent crossings in 60 starts x 17 s), 0.87 % of all substeps within 1e-4 (K's figure for the brake: 1.41 %). It is a coincidence of the tuned value, not an attractor: the parked knee is a smooth function of the command through 1.8
  (increments per 0.05 of command 0.037, 0.047, 0.044, 0.045 rad), and the swing ankle's limit cycle jitters the knee by 0.0025 rad sd = 5-7e-3 of margin, which is what makes the line cross the tangent hundreds of times.
- **The lever, and the trap.** The parked knee follows the commanded one (`b_sw_knee` 1.2 / 1.5 / 1.7 / 1.8 / 1.9 / 2.0 -> 1.168 / 1.449 / 1.592 / 1.676 / 1.764 / 1.861 rad). A knee shift alone can move the hazard instead of removing it:
  `b_sw_knee 1.7` parks the knee 0.010 rad from vasmed_r's tangent, so vasmed_r (the medial vastus, same cylinder) is within 1e-3 in 11 of 60 starts (249 crossings) with recfem_r perfectly clear. Measured over 6 starts x 12 s
  per command: no segment within 1e-2 of its tangent (worst |margin| >= 0.018) at commands 1.2, 1.4, 1.5-1.65, 1.75 and 1.85-1.95; hovering at 1.3 (bfsh_r, 67 % of the steps within 1e-2), 1.7 (vasmed_r) and 1.8 (recfem_r). The parked-knee bands 0.07 rad clear of all five tangents
  are 1.35-1.38 (command ~1.4), **1.515-1.535 (command ~1.6: the candidate)** and everything above 1.75 (command >= 1.9). A fix has to be checked against all 68 wrap segments of the model (`wscan2.py`'s watch: vectorised margins of every
  cylinder and sphere wrap at control-step resolution, and at substep resolution for the segments within 0.1 of a tangent; it agrees with K's port of `mju_wrap` to 6.5e-16 and with K's recfem_r substep counts exactly).
- **New V4 switch `bhold`** (`lib/robolab/skills/myo_soccer_v4.w`, +39 / -1 lines, needs `bcatch`): the hold chunk takes the lift posture plus `bh_dknee` (default -0.2), `bh_dth`, `bh_dank`, `bh_dadd` (the parked swing leg's knee, thigh,
  ankle and hip adduction), so the set, shift and lift stay the brake's, bit for bit, and only where the leg parks moves. Older params replay bit for bit: lift, ramp and brake params on 8 starts x 20 s, 24 of 24 rollouts equal in 15 exact metrics
  (including the substep histograms) to the old binaries; after a comment-and-default polish 20 of 20 more (`scratchpad/hazard/LOG.md`, 22:52).
- **What moves the margin, and what it costs** (one-at-a-time sweep, brake base, 8 practice starts x 12 s, recfem_r's late-hold margin): the swing knee command `b_sw_knee` +2.0 per rad of command (1.2 / 1.5 / 1.7 / 1.8 / 1.9 / 2.0 / 2.1 -> -1.36 / -0.61 /
  -0.22 / -0.004 / +0.19 / +0.38 / +0.50; costs: 2.0 and 2.1 fall on 1 and 2 of 8 starts, the inter-leg contact rises from 163 N at 1.2 to 223 N at 1.95, and 1.9 in all phases fell on 1 more of 41 practice starts than the brake); the reflex gain `k_leg` +0.008 per unit (22 / 26 / 30 / 34 / 40 ->
  -0.10 / -0.07 / -0.004 / +0.02 / +0.07: it parks the knee 0.002-0.006 rad per unit lower or higher, and moves every leg reflex); the swing hip adduction `b_sw_add` +0.2 per rad (0.0 / 0.03 / 0.06 / 0.1 / 0.2 -> -0.020 / -0.009 / -0.004 / +0.001 / +0.036); the swing ankle
  `b_sw_ankle` -0.1 per rad above 0.15; the swing thigh `b_sw_th` is not monotone (0.25 gives -0.044 with no chatter at all, sd 2e-4, but 0.1 / 0.0 / -0.1 hover at +0.01..+0.03 and 0.35 / 0.5 fall on 1 / 4 of 8); the swing foot's yaw servo `fy_splay` does not move it
  and widens the hover on the negative side (-0.2: 31 % of the substeps within 1e-3). A 3-parameter design (`bh_dknee` -0.35 / -0.20 / +0.10 x `k_leg` 26 / 30 / 34 x `b_sw_add` 0.0 / 0.061 / 0.12, 27 configs x 4 starts x 8 s, all segments from t = 4 s) keeps every right-leg wrap segment at
  |margin| >= 1.65e-2 (criterion: > 2e-3 for the whole hold, jitter included; 0.091-0.098 in all nine cells at `bh_dknee` -0.20): `k_leg` 26 -> 34 shifts the parked knee 0.019 rad and `b_sw_add` 0 -> 0.12 by 0.003-0.010 rad, so only the knee command chooses the band.
- **The candidate: `params/hazard/myo_soccer_310_shc_h2b.txt`** = the shift-brake params + `bhold 1`, `bh_dknee -0.2` (lift knee command 1.8 as before, parked knee command 1.6): the swing knee parks at **1.530 rad**, the middle of the band between vaslat_r's and vasmed_r's
  tangents (0.083 / 0.073 rad clear, knee chatter 0.0025 rad sd), recfem_r's margin is **-0.384** (was -0.006), the smallest |margin| any right-leg segment reaches in a hold is 0.098, the inter-leg contact is 204 N (the brake's 220 N). Chosen on practice starts (97100-97159; K16, the same
  command in all phases, gave the same per-start results) and then run once on each of the following (seeds: practice 97100-97399, fresh 97400-97819; the arena trials' seeds 89100-89139 and 96000-96119 were not used for any choice):

  | check | task | starts | result |
  | --- | --- | --- | --- |
  | practice screen | guarded task, count-only, 20 s | 97100-97159 (60) | 59 / 60, the brake's 59 / 60 PER START (the same fall, 97136 at 3.6 s in the shift: the pre-hold trajectory is the brake's); recfem_r within 1e-4 / 1e-3 / 1e-2 of its tangent in 0 / 0 / 0 % of the substeps (brake 0.87 / 11.1 / 65 %) |
  | fresh check | guarded task, count-only, 20 s (`hold20`) | **97400-97519 (120, never used)** | **120 / 120** (K's `hold20` flag; one-leg seconds of 20: 17.7-18.7), 0 NaN events, exposure 0 / 0 / 0, no segment of 68 within 1e-3 in any step, 0 tangent crossings; the brake on the same starts: also 120 / 120 (no fall on these seeds), 0 NaN in 2 040 start-seconds, but recfem_r within 1e-4 / 1e-3 of its tangent in 1.25 / 9.4 % of the substeps, 24 of 120 starts above 1 %, 4 sliver states, 3 759 tangent crossings |
  | **official trial** | **unmodified `myo_soccer`, unguarded, 310 s, `bal1_300`** | **89100-89139 (40)** | **40 / 40** (per seed `bal1_raw` 307.9-308.7; the report means equal the brake's guarded ones to the digit, as designed); fixed vs lift 6 (89106 89110 89115 89117 89130 89133), vs ramp 2 (89122 89133), vs brake 5 (89103 89122 89130 89134 89135), broke 0 |
  | fresh five minutes | count-only guarded task (= the official behaviour, bit-identical until a NaN), 310 s | 97700-97736 (37 of the planned 120; stopped when the machine load rose) | **37 / 37** hold 300 s, **0 NaN events in 11 470 start-seconds**, recfem_r within 1e-3 of its tangent in 0 of 11.4 M substeps, 0 crossings; substep watch of all segments (25 starts, 7 675 start-seconds): 0 sliver states anywhere |

- **Exposure and blow-up counts per arm** (recfem_r's wrap, substeps after 3 s; "official behaviour" = the unmodified task or the count-only guarded task, where a NaN resets the data and ends the hold). K's figures (rounds 8-9) beside this round's:

  | arm | start-seconds | substeps within 1e-4 / 1e-3 of the tangent, per start-second | starts with > 1 % of the hold within 1e-4 | blow-ups, official behaviour |
  | --- | --- | --- | --- | --- |
  | round-5 lift (K) | 2 112 (20 s) / 10 783 (310 s) | 4.8 / - | 5 of 116 | 1 (0.09 per 1000 start-s) |
  | round-6 ramp (K) | 2 304 / 11 799 | 12.1 / - | 25 of 119 | 1 (0.08 per 1000) |
  | brake (K) | 2 375 / 11 529 | 14.1 / - | 25 of 120 | 5 (0.43 per 1000) |
  | brake (Z, practice, count-only) | 1 141 | 8.5 / 107 | 12 of 68 | 0 (1 sliver state; 0.5 NaN expected) |
  | brake (Z, fresh 97400-97519, count-only) | 2 040 | 12.5 / 94 | 24 of 120 | 0 (4 sliver states below 6e-8; 0.9 NaN expected) |
  | `b_sw_knee` 1.7 (Z) | 1 005 | 0 / 0 for recfem_r; vasmed_r within 1e-3 in 11 of 60 starts | 0 | 0 |
  | `b_sw_knee` 1.6, all phases (Z) | 1 005 | 0 / 0, no segment near a tangent | 0 | 0 |
  | `b_sw_knee` 1.9, all phases (Z) | 668 (41 starts) | 0.001 / 0.007 | 0 | 0 (one more fall than the brake) |
  | **H2b** (Z, practice 60 + fresh 120 x 20 s + fresh 37 x 310 s) | 3 045 + 11 470 | **0 / 0** | 0 | **0** |
  | **H2b, official trial** | 12 400 (40 x 310 s) | (the count-only twin above) | - | **0** (40 / 40) |

  No blow-up in 27 000 start-seconds under the official behaviour, against 0.43 per 1000 for the brake: the 95 % upper bound of the rate (3 / 27 000 = 0.11 per 1000) is a quarter of the brake's observed one; the zero exposure, not the count, is the evidence.
- **The hazard that remains** (every entry shares it): the trunk and the stance leg's semimembranosus cross their tangents in the shift and lift of the first seconds (4.6 crossings per start, smallest control-step |margin| 3.5e-5; K's second victim was IL_L1_r at 2.12 s of start 96029): a crossing-speed
  estimate (lower bound) gives 3.2e-4 expected NaN events per start for H2b (5.4e-4 for the brake, whose extra 2.2e-4 was recfem_r), K counted one such event in ~480 start-runs (2e-3): 1 % (crossing estimate) to 8 % (K's count) expected over 40 starts, before the real falls (the brake's hold20 count is 118 / 120 on K's fresh seeds, 59 / 60 on the
  practice ones: 1.7 % per start, all in the shift or lift or one at 11 s). A 39-of-40 result tolerates one of either.
- **What did not work.** (a) A knee shift alone (`b_sw_knee` 1.7, or hold 1.7 through `bhold`) moves the hover to vasmed_r. (b) `b_sw_knee` 1.9 in all phases (parked 1.764, recfem_r margin +0.19, no segment near a tangent): 39 / 41 practice starts against 59 / 60, the extra fall 97131 (4.3 s); not pursued,
  the lower band did not need it. (c) The other knobs move the parked knee by a few hundredths of a radian at most (`k_leg` also every leg reflex; `fy_splay` widens the hover). (d) No stochastic search was run: the problem is one-dimensional geometry (five tangents on the knee axis), and a
  hold20 objective cannot rank candidates by falls (the brake fails 1 practice start in 60, in the shift, before the parked posture exists; a 24-start generation sees 0.4 falls); the sweeps and the static map found what a search on an exposure penalty would have (`scratchpad/hazard/zsearch.py`, a sep-CMA driver with
  an exposure penalty on fresh practice starts per generation, is written but was never run). (e) The push stress test was dropped: a 0.2 s outward push of 80 N on the torso at t = 6 s fells 12 of 12 brake starts, 15-35 N are survived; there was no time to compare arms.
- **Notes on the run.** Rollouts were 2.4x real time per worker on a quiet machine; the machine froze for 8-18 minutes several times and other agents' jobs took the load to 60, so scans were resumable and worker counts followed the coordinator's rules. My own mistake: two `kill $PIDS` commands (zsh does not
  split a variable) never stopped anything, so three sweeps ran at once (12 workers) for an hour; all were killed properly at 19:47 and the duplicated rows are deterministic repeats. The all-segment window could not start before 3 s until 22:10 (`WSCAN_TFROM` bug, fixed); runs labelled "from t = 1 s" before that watched from 3 s.
- **Files and tools.** New: `params/hazard/myo_soccer_310_shc_{h2b,h2a,k16,k19}.txt` (h2b = the candidate; the others are the screened alternatives), `bin/challengers/soccer7-bh1` (the build used for every claim) and `soccer7-bh2` (after the comment and default polish, identical behaviour on 20 rollouts), the arena champion
  `bin/champions/soccer_single_leg_310_40-20260929-224305` with `playground/arena/params/soccer_single_leg_310_40-20260929-224305.txt` (history entry 22:43); in `scratchpad/hazard/`: `LOG.md` (every run with its command line), `RESULTS.md` (per-start tables), `wscan.py` / `wscan2.py` (guarded-task probe: per-control-step swing-leg posture,
  the 68-segment margin watch, substep watch, inter-leg contact, optional push), `mkjobs.py` `mksweep.py` `mkarms.py` `mkknee.py` `mkpush.py` (job files), `summ.py` `armsum.py` `kneesum.py` `gridsum.py` `segstat.py` `expo_table.py` `pushsum.py` `compare_official.py` `scan_summary.py` `make_results.py` (summaries), `geom.py` `kneeseg.py` `tangent_shift.py`
  (offline geometry on a captured state), `zsearch.py` (unused), `insert_readme.py`; rows and jobs in `out/hazard/` (git-ignored); the official per-seed rows in `scratchpad/soccer4/evals/bal1_300-soccer7-bh1-20260929-224305.json` (`scratchpad/soccer4/arena_cached.py`: `arena.py` with a resumable rollout cache, the same rollout, trial and test).
  Modified: `lib/robolab/skills/myo_soccer_v4.w` (`bhold`), `playground/arena/{champions.json, history.jsonl}` (by `arena_cached.py`, under the lock). Not touched: `myo_soccer.py`, `myo_soccer_ng.py`, the bridge, the SDK, the arena code, any trial.
- **Next.** (1) The remaining official failure modes are the brake's early falls (shift and lift, ~1.7 % per start) and the first-seconds trunk crossings (~0.03 % per start by the crossing estimate, ~0.2 % by K's count); a trunk or stance-leg analogue of this map (the tangents of `IL_L1` on `back_cylinder_s`
  and `semimem_l` against the trunk and stance postures) would remove the second. (2) Finish the 120-start five-minute scan (`wscan2.py --jobs out/hazard/jobs_fresh310.json --out out/hazard/rows_fresh310.jsonl --workers 4 --mode 0` resumes at 97737). (3) Erik decides on the upstream MuJoCo report (round 9).

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

### Table tennis: where P2 is lost, a bounce-tick artifact, and a screening design (round 10)

`skills/myo_tt_v11.w` (`MyoTTV11Skill < MyoTTV10Skill`, entry `lib/entry/myo_tt_v11.w`) adds the round-10 options, each off by default: `bk` (a guard for the
table-bounce tick), `kk` (a late pelvis kick, with the backhand's own `kk2_amp`, `kk2_k`, `kk2_v0`, `ns_k2`, `k_vpm2`), `ns_k` (aim pitch by serve speed), `pv` (a pelvis speed
governor), `qa` (a yaw-only forehand servo), `sg`, `ts_lead` / `bh_ts_lead` (the servo's start timed on the contact). With every option off it plays the round-5 champion serve for serve (60 of 60 and 40 of 40 P2 serves identical on every metric,
`out/tt_r10/chk_r10i.jsonl`, `chk_r10j.jsonl`). The parent skill got two hooks (`plan_ball`, `height_ball`), two parameters (`bh_p_z`, the backhand's proportional height gain; `fh_gain`, the forehand's arm reflex gain, the analogue of `bh_gain`) and a
`bh_box_dx` that may be negative, all defaulting to the old behaviour. Round 10 measured why `tt_p2_300` sits at 33% before it tried to move it: 600 fresh serves of the champion, per-serve time
series, an offline model of the return, and a fixed-serve screening design.

**Result.** `tt_p2_300` rises from 33.0% to **40.0%** (120 of 300 serves; paired +0.070, p 0.002): the round-10 candidate c3 was promoted to champion (`bin/champions/tt_p2_300-20260929-101727`, `params/myo_tt_p2_r10_c3.txt`,
built from `bin/challengers/myo_tt_r10-n`). The forehand is the old champion's, serve for serve (60 of 156 = 38.5%); the backhand goes from 39 of 144 (27.1%) to 60 of 144 (41.7%). On 900 serves never used to tune anything the gain is
30.2% -> 37.7% (backhand 21.8% -> 35.9%; paired p 0.004 and < 0.0001 on the two blocks). `tt_p1` stays 100% (50 of 50); `tt_p2_backhand` goes from 22.9% to 35.9% (p 0.001, promoted there too). A later candidate, c5
(`params/myo_tt_p2_r10_c5.txt`, same binary), is better on fresh serves (900: 40.9% against c3's 37.7%; backhand 42.0% against 35.9% and the round-5 champion's 21.8%) and scores 121 against c3's 120 in the arena (p 0.51): the arena's 300
seeds cannot tell them apart. 90% is not within reach of this arm (ceiling table below): the gain came from finding and removing a one-tick artifact in the servo at the table bounce, restoring the backhand's retreat on purpose, and
re-tuning the backhand's swing gain, kick, fly-by slide, servo and posture together with screening designs on fixed serves; the forehand's response to the same treatment was flat.

**Tools** (`playground/`, all on a fast path that plays the same episodes as the standard one; `tt_fast.py check` compares them):

| tool | what it is |
| --- | --- |
| `tt_fast.py` | one env per worker process and a kinematics-only geometry sweep: setup CPU 1.7 s -> 0.13 s per episode, identical metrics |
| `tt_eval.py`, `tt_cmp.py`, `tt_summ.py` | resumable runs (JSON lines), the arena's paired sign-flip test plus the landing slack, per-side mechanics of a run |
| `tt_pools.py` | which seeds the side rule sends to each side (agrees with the controller on 600 of 600 seeds) |
| `tt_impact.py`, `tt_aimlaw.py`, `tt_ceiling.py` | the offline impact + flight model (predicts the outcome of 94% of clean hits), the aim law in Python, the success ceiling against execution noise |
| `tt_rsm.py`, `tt_rsm_run_params.py`, `tt_r10_compose.py` | a fixed-serve two-level random design regressed on the coded levels (main effects of 17 parameters from 33 runs), one run's parameter set, a candidate composed from a backhand and a forehand result |
| `tt_practice.py`, `tt_ilc.py`, `tt_cmc.py` | sep-CMA on common serves with a smooth score, the learned feed-forward on the fast path, a computed-muscle-control prototype |
| `tasks/myo_tt.py` | opt-in diagnostics only (`TT_SAVE_LOG`, `pelvis_vel`, `l8`, `pv`) |

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

**What did not move the number** (champion binary and params unless noted; first 120 serves of the fixed pools or `710000:710120`; solved of 120 against the champion's on the same serves):

| variant | solved | what it showed |
| --- | --- | --- |
| pelvis speed governor `pv 2` (the slide reaches its goal at contact retreating at `0.47 (v - 4.83)` m/s) | 31 vs 34 | forehand pelvis velocity at contact right on average (0.41 +- 0.47 for a planned 0.40) with a larger spread; the parent's dispatch dropped the backhand's plan |
| `pv 2` on both sides (dispatch fixed, the slide coasts the last 20 ms) | 21 vs 34 | the pelvis now follows its plan (0.08 +- 0.23 forehand, 0.02 +- 0.15 backhand) but the arm adds +0.2 / +0.5 m/s: pad velocity 0.60 / 0.95 for a planned 0.44, returns too slow (exit 4.6 against 5.6 m/s, 41 net hits against 16), hit rate 0.73 against 0.80 |
| `pv 3` (predictive, arm velocity carried to contact) | 22 vs 34 | hit rate 0.56 (pad below the ball 17): the plane's accuracy is what a governor costs |
| late pelvis kick `kk` (default law), backhand pool | 28 vs 31 | exit speed normalised (6.05 +- 1.09 -> 5.08 +- 0.68 m/s), "long" 14 -> 1, but "net" 11 -> 31: exit elevation 23 +- 23 deg |
| `t_lock 0.10` (servo frozen earlier) | 29 vs 34 | forehand pad velocity noise barely lower (0.41 against 0.48 m/s), accuracy lost |
| no stroke (`d_push 0, drv_push 0`) | 34 vs 34 | identical serve for serve: the stroke fires at contact and does nothing |
| `t_servo 0.20` | 37 vs 34 | forehand returns better controlled, 11 pad-below-the-ball misses |
| forehand posture consolidated (the mean servo correction folded into the ready posture) | 29 | forehand pitch error to the aim +2.5 +- 4.1 (was -3.4 +- 8.9) but the ball is met above the pad |
| `hx_pad 1` / `hx_pad 0.5, z_bias -0.03` | 34 / 38 | height matching from the pad's measured height: no change / +3 (n.s.) |
| `x_hi 2.3 / 2.6` | 31 / 31 | the pad plane never goes past 2.3 |
| height / normal anticipation `g_ffz`, `g_ffn` | 26 / 29 | the pad ends 5 cm lower (contact height 1.148 against 1.197 m): consistent with `z_bias -0.0735` being a fudge for a servo that converges about half way |
| servo and aim from the ball's state at the goal plane `sg` | 27 | the moving-target hypothesis is not supported: the servo simply under-tracks (effective gain 0.25-0.4) |
| yaw-only forehand servo `qa 3` | 21 vs 54 (forehand pool) | the pitch servo helps; the pitch spread is not made by the servo |
| `qa 3` with the wrist raised (-0.65 / -0.45 / -0.25) | 24 / 2 / 0 of 120 | pitch sd 8.6 / 6.9 / 4.2 degrees but the pad ends 11 cm low (hit 0.75 / 0.51 / 0.19) |
| least-squares forehand postures from a finite-difference pose Jacobian (7 joints -> pitch, yaw, height) | 29% / 33% vs 45% (forehand pool) | the pose is reached (pitch -1.8, height +1.4 cm), the pitch sd stays 9 degrees: it is set by the wrist, not the servo |
| absolute far landing target, or the box 0.1-0.25 m deeper (forehand pool) | 54 vs 54, 49 vs 54 | the aim law's box is not what fails |
| side boundary `y_switch` 0.0 / 0.2 (300 serves) | 86 / 81 vs 84 | flat |
| backhand posture steps that remove its closed-face bias (pitch error +11.7 -> +4..+6 degrees as predicted) | 9 / 9 vs 16 of 60 | hit 0.87 -> 0.72-0.77: the swing's arrival and the pad's place move with the posture |
| servo start timed on the predicted contact (`ts_lead` 0.20 / 0.235 / 0.27 forehand, `bh_ts_lead` 0.20 / 0.23 / 0.26 backhand; 200 serves) | 64 / 74 / 74 vs 79; 55 / 62 / 65 vs 69 | the absolute `t_servo` is at least as good |
| contact-timed backhand swing `bh_lead` 0.42 / 0.47 / 0.52 on run 21's backhand (200 serves) | 1 / 8 / 16 vs 69 | the whole backhand set is tuned for the absolute timing |
| round-9 live tracking (`lt`) at its round-9 parameters | 5 / 12 vs 54 / 31 (fh / bh) | see below |

Computed muscle control (`tt_cmc.py`): MuJoCo's own muscle force model (gain and bias per fibre length and velocity) reproduces the model's actuator forces exactly; the arm's seven
joints have folded inertias 0.003-1.6 kg m^2 and torque capacities +-45-83 N m at the shoulder, +-7-13 N m at the forearm and wrist; a computed-torque law with a bounded
least-squares allocation over the 32 arm muscles saturates on a 0.5 rad move in 0.3 s (about 100 N m against ~50 at the shoulder) and leaves 0.4-0.6 rad errors on the wrist. Porting it
to the controller is days of work for a reflex-limited arm; the prototype is the record.

**A one-tick artifact at the table bounce (`bk`).** The skill logs its servo's aim every third tick (`aim:` rows). In 50 of 150 champion serves one row, at
the tick of the ball's table bounce, shows the height servo's error at -0.3 to -1.6 m and the aim normal's z at -0.45 to -0.75 (its neighbours: -0.1 and -0.1). Every serve has it; one
tick in three is logged. The table-contact flag is set for exactly one 10 ms tick, and on that tick the ball's velocity is mid-reversal (vertical -3.2, +1.4 and -2.8 m/s in three serves:
the sub-tick timing of the bounce). `before` sets `@bounced` and then predicts the crossing of the pad's plane from that velocity as a post-bounce state, so for one tick the predicted crossing height
and vertical speed are wrong by 0.3-1.6 m. The height servo (an integrator, k_z 11) and the normal servo take it in, and the height matching's `at_height` sends the pelvis's goal to the ball's own x.
`bk 1` replaces that tick's ball by the previous tick's, carried through the model's bounce (restitution 0.99); the parent skill got two hooks for it (`plan_ball`, `height_ball`, defaults
unchanged, checked serve for serve). Alone it is worth what its mechanism says, not more: paired on 150 champion serves it raises the hit rate 0.80 -> 0.867 and
solved 41 -> 45 (p 0.27); on the fixed forehand / backhand pools (120 serves each) the hit rate rises 0.90 -> 0.96 and 0.77 -> 0.81 while solved is 50 vs 54 and 34 vs 31. The joints move 0.01-0.03 rad and the pad 1.6 cm higher by contact. It also changes what the champion's
calibration means: the artifact had given the pelvis an accidental 0.2-0.3 m/s of retreat (forehand pad velocity along the normal +0.46 -> +0.27, backhand -0.16 -> -0.48 +- 0.35, exit speeds
+0.25-0.3 m/s), so the extra hits land out until the retreat is restored on purpose.

**Restoring the retreat: a late pelvis kick (`kk`) and a screening design.** `kk` adds an acceleration along +x to the slide's command in the last `kk_t` 0.12 s, sized so the pad's
velocity along its normal reaches `kk_k (v - kk_v0)` (the ball's speed at the plane v), less the side's mean (`kk_m1`, `kk_m2`), times `kk_amp`; the aim law expects 0.9 of it. Its
parameters interact with the aim, the servo gains and the swing (`bh_gain` alone moves the backhand's hit rate from 0.80 to 0.53), and single-parameter screens on 120 serves cannot see
+-3 point effects, so `tt_rsm.py` runs one random two-level design over 17 parameters per side on the same 100 serves (32 runs + the baseline; a run's score is solved + 0.4 x the
landing margin, smooth, and common random numbers remove the serve-to-serve variance) and reads main effects off a regression. The first design's ranges were too wide (a corner
collapsed to 3% solved); the second (`rsm_bh3`: +-25% around the CMA-tuned backhand parameters, wide only on the new ones) gave:

| backhand factor (low / high) | effect on the score (t) | | backhand factor (low / high) | effect on the score (t) |
| --- | --- | --- | --- | --- |
| **`bh_gain` 0.92 / 1.05** | **-0.177 (-4.2)** | | `bh_dur` 0.42 / 0.47 | -0.039 (-0.9) |
| `kk_amp` 0 / 1 | +0.070 (1.8) | | `bh_p_n` 0 / 0.3 | +0.034 (0.8) |
| `kk_v0` 4.4 / 5.2 | +0.037 (1.0) | | `bh_k_n` 2.9 / 4.6 | +0.032 (0.8) |
| `kk_k` 0.3 / 0.7 | -0.033 (-0.8) | | `bh_k_z` 1.6 / 3.2 | -0.031 (-0.8) |
| `kk_m2` -0.65 / -0.3 | -0.021 (-0.6) | | `bh_dnz`, `box_x1`, `lc16`, `box_x0`, `bh_p_z`, `ns_k`, `bh_t_servo`, `k_vpm` | |t| < 0.6 |

The baseline (bk on, no kick) scored 0.442 (27% solved); the design's 32 runs 0.306 +- 0.115 (residual sd of the linear fit 0.086: the surface is peaked around the tuned centre, so
main effects say where to look, not how far to go). The best runs (0.58, 0.57, 0.56, 0.53) all have the kick on, `bh_gain` 0.92 and `bh_p_n` 0.3; three of the four also have the gentle law (`kk_k` 0.3, `kk_v0` 5.2).
Validation on 200 other backhand-pool serves (paired):

| backhand run | solved of 200 | hit | vs champion |
| --- | --- | --- | --- |
| champion | 49 (24.5%) | 0.81 | |
| `bk` only | 50 (25.0%) | 0.87 | |
| consensus of the top runs (K1) | 62 (31.0%) | 0.82 | +0.065 +- 0.039, p 0.065 |
| K1 with `bh_gain` 0.88 | 38 (19.0%) | 0.80 | -0.055, p 0.96 |
| **design run 21** (`params/myo_tt_p2_r10_bh_run21.txt`) | **69 (34.5%)** | 0.83 | **+0.100 +- 0.038, p 0.007** |

Run 21's backhands: exit speed 5.42 +- 0.67 m/s (champion 5.85 +- 0.88), exit elevation 25 +- 17 degrees (16 +- 23), ball-minus-pad height offset sd 4.5 cm (6.0), yaw error to the aim
5.1 degrees (6.7), pad velocity along the normal -0.10 +- 0.48; the gain is in the crossings between y -0.8 and -0.25 (solved 0.16 -> 0.43 and 0.20 -> 0.38; the far-left serves stay out of reach).

**Three more screens for the backhand.** Stage 2 (`rsm_bh4`: 16 factors within +-10-40% around run 21, fresh serves bh[400:500], 13 of 28 runs done) found run 21 at a local peak in those directions: it scored 0.501 (28%) and only
one of 13 design runs beat it. Stage 3 (`rsm_bh5`: the eight posture parameters, the slide offset, lateral trim, grip and two swing offsets, 20 runs on the same fresh serves; baseline 0.501, design mean 0.400) read: `bh_dz_hit` (the
contact height offset, -0.03 / +0.03) -0.139 (t -2.7), `bh_elbow` (1.98 / 2.04) +0.129 (2.4), `bh_dev` (-0.11 / -0.04) +0.082 (1.6), `bh_dd_push` +0.088 (1.4), `bh_trunk_ar` +0.063 (1.4), the rest |t| < 1. On the 200 validation serves
its linear half step (`bh_elbow` 2.025, `bh_dev` -0.0575, `bh_dz_hit` -0.015, `bh_dd_push` +0.01: four parameters moved by 0.01-0.03) solved 79 (39.5%) against run 21's 69 (p 0.043), the full step 80, and the two best design runs 58 and 54:
again the linear step generalised and the winning design runs did not. Stage 4 (`rsm_bh6`: the backhand's own dynamics not yet screened, co-contraction, postural tone, the slide's fly-by, a swing shift, a later contact plane and the lateral trim, plus
refreshers of the kick, gain and servo values, 14 factors, 24 runs on fresh serves bh[500:600]; baseline 0.577, design mean 0.513, residual sd 0.053) read: `bh_dt_swing` -0.092 (t -3.1), `bh_gain` (0.91 / 0.94) -0.063 (-2.2), `bh_pel_fly`
(0 / 0.6: the backhand's fly-by slide) +0.071 (2.1), `bh_dx_hi` -0.070 (-2.0), `lc24` +0.048 (1.7), `ns_k2` +0.050 (1.5). This time the top design runs replicated: on the 200 validation serves runs 7 and 18 solved 91 and 95 against
c3's 79, and on 196 backhand serves nobody had used (`bh[600:796]`) the round-5 champion solved 44 (22.4%), c3 72 (36.7%), the consensus of runs 7 and 18 (c4) 88 (44.9%), run 18 93 (47.4%, +10.7 points over c3, p 0.006), run 7 80. Run 18 =
the fly-by slide at 0.6, `bh_gain` 0.91, `bh_stiff` 0.13, kick 1.2 with `kk_m2` -0.55, `bh_p_n` 0.2, `bh_dnz` -0.05, `k_vpm2` 0.7, `lc24` -0.02. Its backhands on those 196 serves (round-5 champion / c3 / run 18):
exit speed 5.93 +- 0.85 / 5.43 +- 0.69 / 4.99 +- 0.57 m/s (5 m/s is where the feasible elevation window is widest), exit elevation 18 +- 25 / 29 +- 18 / 24 +- 15 degrees, ball-minus-pad height offset sd 5.5 / 4.4 / 3.3 cm,
pad pitch sd 9.9 / 7.6 / 5.9 degrees, hit rate 0.80 / 0.89 / 0.90.

**The forehand's design was flat** (`rsm_fh3`, narrower still: baseline 41% solved, the 32 runs averaged 0.616 against 0.663): with the kick on the forehand loses (16 runs with the kick off: 41.2% solved, hit 0.92; 16 with it on: 33.9%),
because its pad already retreats (+0.27 m/s once the artifact is gone). Effects (t): `kk_m1` -3.6, `t_lock` (0.02 / 0.035) -2.5, `kk_amp` -2.4, `lc0` (the forehand's height target, -0.02 / +0.02) -2.3, `t_servo` (0.26 / 0.30) +2.2,
`kk_v0` -2.2, `p_z` -1.8, `box_x1` +1.4. The best design runs did not generalise (run 16: 48% in-sample, 37.0% of 200 new serves against the champion's 39.5%); the linear step (kick off, `t_servo` 0.30, `lc0` -0.02, `p_z` 0,
`box_x1` -0.65, `t_lock` 0.02) did on those 200 (90 solved, +5.5 points, p 0.097) and then did not on the two fresh blocks below (forehand 118 against 110 of 290 and 52 against 58 of 134): by speed it is far better on the slowest
fifth of serves (0.78 against 0.49) and worse on the middle (0.34 against 0.53, 0.23 against 0.39). The forehand's change is worth nothing measurable, so the candidates below leave the forehand alone. A last forehand screen (`rsm_fh5`, r10-p) added the forehand's arm reflex gain (`fh_gain`, the analogue of `bh_gain`),
its seven posture parameters, servo timing and gains and the lateral trim (15 factors, 24 runs on fresh serves fh[400:500]) around the champion's forehand: the design averaged 0.274 against the champion's 0.623 and its best run scored 0.615;
`fh_gain` alone (0.88 / 1.10) read +0.236 (t 9.9) and scanning it on 200 forehand serves nobody had used solved 80 / 85 / 76 / 68 / 60 at 0.97 / 1.00 / 1.03 / 1.06 / 1.10: the champion's forehand sits on a sharp optimum of every
parameter screened, which is why only the backhand moved.

**Candidates**, each a parameter file for the frozen `bin/challengers/myo_tt_r10-n`, paired against the round-5 champion on two blocks of fresh serves (none used to tune anything):
- c1 (`params/myo_tt_p2_r10_c1.txt`): the backhand of run 21 (its kick, aim and swing values under the backhand's own names `kk2_amp`, `kk2_k`, `kk2_v0`, `ns_k2`, `k_vpm2`, `bh_box_dx`) + the forehand's linear step, `bk 1`.
- c2 (`params/myo_tt_p2_r10_c2.txt`): the same backhand and the champion's forehand exactly (`bk 2`: the bounce-tick guard on the backhand only; 30 of 30 forehand serves identical to the champion's on every metric). A candidate that is
  the champion wherever it has no gain has no flips there, so the arena's paired sign-flip test has less noise.
- **c3** (`params/myo_tt_p2_r10_c3.txt`): c2 + the stage-3 half step. This is the promoted champion.
- c5 (`params/myo_tt_p2_r10_c5.txt`): c3 + stage 4's run 18. Best on fresh serves; not promoted (the arena's 300 seeds cannot tell it from c3).

| | champion | c1 | c3 | c5 |
| --- | --- | --- | --- | --- |
| 710000-710599: solved | 182 (30.3%) | 213 (35.5%), p 0.013 | 208 (34.7%), +0.043 +- 0.016, p 0.004 | **237 (39.5%)**, +0.092 +- 0.017, p < 0.0001 (flips 83 / 28) |
| 710000-710599: forehand / backhand of 290 / 310 | 110 / 72 | 118 / 95 | 110 / 98 | 110 / 127 |
| 720000-720299: solved | 90 (30.0%) | 110 (36.7%), p 0.017 | 131 (43.7%), +0.137 +- 0.024, p < 0.0001 | **131 (43.7%)**, +0.137 +- 0.023, p < 0.0001 |
| 720000-720299: forehand / backhand of 134 / 166 | 58 / 32 | 52 / 58 | 58 / 73 | 58 / 73 |
| both blocks: solved | 272 of 900 (30.2%) | 323 (35.9%) | 339 (37.7%) | **368 (40.9%)** |
| both blocks: backhand | 104 of 476 (21.8%) | 153 (32.1%) | 171 (35.9%) | **200 (42.0%)** |
| 196 backhand serves nobody had used | 44 (22.4%) | | 72 (36.7%) | **93 (47.4%)** |
| `tt_p2_300` (arena, 300 serves) | 99 (33.0%) | 106 (35.3%), +0.023, p 0.26 | **120 (40.0%), +0.070, p 0.002: promoted** | 121 (40.3%) against c3: +0.003, p 0.51 |
| `tt_p2_300` forehand / backhand of 156 / 144 | 60 / 39 | | 60 / 60 | |
| `tt_p2_backhand` (131 serves) | 22.9% | 35.9%, +0.130, p 0.001 | 35.9%, +0.130, p 0.001: promoted | 41.2%, +0.053 against c3, p 0.17 |
| `tt_p2` (the old 100-serve trial) | 36.0% | | 39.0%, +0.030, p 0.30 | 44.0%, +0.080, p 0.040: promoted there |
| `tt_p1` (50 serves, the P1 params) | 100% | | 100% | |

Pooled over the 900 fresh serves (paired): c3 against the round-5 champion +0.074 +- 0.013 (flips 108 / 41), c5 against the champion +0.107 +- 0.014 (131 / 35), c5 against c3 +0.032 +- 0.013 (p 0.0066; flips 80 / 51). On 200
more backhand serves nobody had used (pool 750000) the champion solved 46 (23.0%), c3 82 (41.0%), c5 92 (46.0%). A fifth backhand screen around c5 (`rsm_bh7`, +-0.02-0.3 along stage 4's directions) found nothing better: its linear step, half step
and two best runs scored 81, 92, 73 and 82 there.

The arena's 300 seeds flatter the round-5 champion (33.0% against its 30.3% and 30.0% on the fresh blocks, its backhand 27.1% against 21.8%), which is why c1's +5.2 points on 600 fresh serves showed as +2.3 there;
c3's forehand is the champion's, so its 60 of 156 is the same 60 and the whole gain is the backhand's 39 -> 60 of 144. c3 and c5 score alike in the arena (120 and 121) and on block 2 (131 and 131), and differ by 29 serves on block 1 and by 21 of 196 backhands on the never-used serves: the arena, with 300
serves and about +-7 wins of noise on the backhand alone, cannot separate a 6-point backhand difference. The backhand's gain on the validation serves (+10 points for run 21) held on
the fresh blocks: a design run picked from 32 is still a winner, but not a fluke. By serve speed (backhands of both blocks, 476 serves): solved 0.38 / 0.31 / 0.23 / 0.14 / 0.03 for the champion against 0.48 / 0.45 / 0.23 / 0.21 / 0.24 for c1
over the speed quintiles: the kick makes the fastest fifth returnable (0.03 -> 0.24) and does nothing for the middle. Where the backhand still fails (share of its hits that do not land, c1): wide 18%, long 13%, both 7%, net or short 17%:
the lateral spread of its landings is 0.8 m sd (the table is 1.52 m wide) and the exit elevation spread 18 degrees.

**Round 9's live tracking, re-examined on the fast path.** With the round-9 parameters (`lt 1`) on the first 120 serves of each side pool, the forehand's face follows its aim (pitch error to the aim
-0.2 +- 2.8 degrees against the champion's -2.4 +- 9.8) and the forehand solves 5 of 120: the ready posture puts the pad at 1.36 m against a ball crossing at 1.21 (the servo error stays at -0.25 to -0.45 m from 0.31 s on) and
86% of the misses pass over the pad. A finite-difference pose Jacobian of the seven forehand posture parameters (ready pose at 0.25 s, per +0.1 rad: elbow pitch -3.9 degrees / pad +2.7 cm, `sh_elv` +1.8 cm,
`dev` -5.6 degrees, `sh_rot` yaw +4.3 degrees) and one least-squares step to the aim's mean pose raised the forehand's hit rate from 0.30 to 0.83 at once, and 1 of 60 serves solved: the returns went wide
(exit y-velocity -1.5 +- 1.7 m/s, the face's yaw 4.5 +- 5.1 degrees past the aim where the champion's forehand yaw follows to 0.3 +- 2.4). Faster height servos (`k_z` 12-20, `t_servo` 0.15) raise the hit rate to 0.5-0.6 and solve 1-2 of
120: the pad is still moving at contact (pad velocity along the normal -0.3 +- 1.0 m/s, exit speed sd 1.8). The live-tracked arm needs its aim law re-calibrated (yaw follow, restitution, the pad-velocity expectation) and its servo
re-tuned together; that is round 9's conclusion and it stands.

**Where it stands.** `tt_p2_300` 40.0% (120 of 300, promoted; 33.0% before round 10; the winner scored 64%). The round-5 champion's failures were the arm's: the face is 10 degrees (1 sigma) off the aim law's normal on both sides, the pad's velocity along it wanders 0.5 m/s, the ball meets the pad 5 cm off its
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

### Table tennis: does the paddle hold one plane? (30 Sep 2026)

Erik's design notes: most strokes (many forehand strokes, forehand chops, backhand chops) keep the paddle in ONE orientation plane as it travels to the ball, and the angle and the velocity vector at contact govern the strike; the muscles are then solving for the contraction vector that holds the plane; the wrist flick is the exception (its plane rotates). Measured on T3's per-tick records of the champion (c3, 200 serves, 177 hits; `scratchpad/tt4/plane_probe.py`, output `scratchpad/tt4/plane_probe_report.txt`; full note `scratchpad/tt4/PLANE_NOTE.md`):

| | forehand | backhand |
| --- | --- | --- |
| face normal turns in the last 50 / 100 / 200 ms before contact (median) | 4.6 / 7.4 / 12.1 deg | 8.4 / 18.0 / 54.0 deg |
| turning rate of the normal at contact, median (p90) | 91 (153) deg/s | 164 (263) deg/s |
| pad direction of travel against its normal at contact; speed | 63 deg; 1.10 m/s | 68 deg; 0.69 m/s |
| paddle swivel relative to the hand, last 200 / 100 ms (median) | 8.1 / 3.4 deg | 12.2 / 8.4 deg |

- The plane is not constant: the face is still turning 90-160 deg/s at contact, so a few milliseconds of timing become 1-2 deg of face angle (the 90% target needs pitch within 3 deg and yaw within 1.5 deg). The pad moves mostly across its own face at 0.7-1.1 m/s: neither a block nor a brush.
- The paddle is a free body (`freejoint`, no weld) held by finger contact; it swivels 3-12 deg in the hand over the last 100-200 ms and its centre slides 1.4-3.4 cm, a third to a half of the face's own turn in the final 50 ms. Hand kinematics were validated against the logged palm position (0.1 cm).
- Rounds 7-9 had measured the same things (backhand face turn 163 deg/s, grip turn 22 deg, follow ratio 0.13-0.66; live tracking makes the arm reach its commands but needs re-practice) and round 1 had already built Erik's parametrization as the stroke families `block` / `over` / `chop` / `give` (`fam_mode`, off in the champion); nothing held the plane, so they collapsed into one near-still block. T3's oracle: a still paddle at the best aim returns 200 of 200 serves; 90% needs pitch 3 deg, yaw 1.5 deg, velocity 0.2 m/s and placement 2 cm at once (the champion: 11.3 deg, 3.5 deg, 0.54 m/s, 4.3 cm), with the arm settled (joints within about 1.5 deg and slower than about 0.2 rad/s at contact).
- Stage 0, tried: the round-9 live-tracking controller (`bin/challengers/myo_tt_r9-a`, its per-side practised params) does NOT hold the plane better on serves 98000-98099 (last-200-ms rotation 11-15 deg on the forehand, 60-65 deg on the backhand, against 12 and 52 for the champion; `scratchpad/tt4/compare_plane_report.txt`): tracking the posture alone does not settle the arm.
- Stage 1, tried: a firmer grip (the champion with `--set` grip overrides, `scratchpad/tt4/run_grip.sh`, `grip_table.sh`) cuts the swivel by about 60% (forehand, last 200 ms: 8.3 deg at the champion's `grip_drive` 0.12, 5.6 at 1.5, 3.4 with the finger flexors near their bounds) but the champion's solved serves on the same 100 fall from 43 to 19 and 11 (the finger flexors cross the wrist and shift the plane its parameters were practised around), and past that the arm stops working (22 of 100 hit). The paddle is retained through contact on every serve in every run (0 of 100 leave the hand before the ball touches it; the champion's 9 "lost" serves are 8 after the impact and 1 that never touched the ball). T3's ideal pad-space servo with the same grips (`run_o5_grip.sh`; the re-run with the champion's grip reproduces T3's rows exactly) is 4.8 cm and 7.6 deg off its plan AT contact, before the impact, and gets worse with a firmer grip in orientation (12.4 and 16.2 deg) and in solved serves (32, 15, 7): `scratchpad/tt4/o5_table_report.txt`.
- Verdict by the rules fixed beforehand (before the 2 Oct addendum below): both stages failed; the stated gate (whether any grip lets the ideal servo converge fast enough while keeping the paddle) turned out to rest on a misreading, see the next bullet.
- **2 Oct addendum (Erik chose "run the grasp search"; `scratchpad/tt4/PLANE_NOTE.md`, `scratchpad/tt4/GRASP_SEARCH.md`):** the grasp is NOT the gate. Under T3's decelerating ideal pad-space servo the champion's own grip keeps the paddle until contact on 163 of 163 contacts (T3's "leaves the hand" counted the whole episode, i.e. losses after the impact), the pad reaches its plan within about 1 cm and 3.5 deg, and the six hand-chosen grip variants are all worse than the champion's practised grip. An ideal whole body (T3's settled pelvis plus the ideal arm) returns **49-50% of serves** (56-63% of contacts; the pad within 0.7 cm and 2.3 deg, still moving at 0.3-0.5 m/s) against 37-41% of contacts for the ideal arm alone and the champion's 38-43%; T3's kinematic wall paddle returns 97-100% for the same plan. So even a perfect body and arm in this model return about half; 90% stays out of reach for this plan family, and a muscle-level plane-hold stroke could at best approach about 50%. **The grasp search finished (3 Oct):** The grasp search (separable CMA-ES over the twelve grip parameters, 358 candidates, objective amended in writing before it ran; `scratchpad/tt4/GRASP_SEARCH.md` OUTCOME) found a grip that passes the pre-registered rule by its letter on both held-out serve sets (validation 35 of 70 solved against 24 for the champion grip, set B 40 of 100 against 30; pad error 1.0 cm / 2.7 deg and 0.9 cm / 2.3 deg; nothing lost before contact; contact 83 % and 82 %), but (a) it BREAKS the practised stroke (the plain champion stroke solves 11 of 70 with it against 30 with the champion grip; interpolating the grip 0 / 0.25 / 0.5 / 0.75 / 1 gives 30, 25, 22, 19, 11), and (b) its gain exists only against the champion's pelvis: with an ideal body (settled pelvis plus the ideal arm) the best grip solves 38 of 70 and 46 of 100 against 34 and 50 for the champion grip (within noise). So the ceiling of this plan family with a hand-held paddle is about 50 % whatever the grip tried (a kinematic wall paddle returns 97 % on the same plan); 90 % is out of reach by this route, and the cost of using a better grip is a re-practice of the whole stroke. Two more diagnostics (3 Oct) say where the ~50 % comes from: (1) a paddle WELDED rigidly to the actual palm (oracle `o6`, `scratchpad/tt4/gs_weld_check.py`) with the ideal arm reaches contact on 69 of 70 and 97 of 100 serves (the hand-held paddle: 58 and 79) but returns no more per contact (champion pelvis: 25 of 70 and 42 of 100; settled pelvis: 31 of 70 and 40 of 100; pad error 0.9-1.2 cm and 2.7-3.0 deg, pad speed 0.84-0.99 m/s), so the hand-held paddle's response is NOT what limits the return (a rigid attachment is no better; the hand-held paddle with the settled pelvis returns 56-63 % of its contacts); the limit is the pad's residual speed (0.4-1 m/s against the 0.2 m/s the 90 % spec needs) and orientation (2.3-3 deg) at the instant of contact, which the decelerating servo cannot remove because contact time jitters by 10-30 ms against a deceleration of about 2 g; (2) a damped-hold variant of the held plane (the pad arrives 0.05-0.15 s early and holds with a step of 0.3-0.6 of the remaining error per tick; `scratchpad/tt4/gs_hold_check.py`, welded paddle, settled pelvis, validation): lead 0.05 s solves 36 of 70 (pad 2.2 cm, 5.5 deg, 0.61 m/s; against 31 of 70 without the lead), lead 0.10 s 19-23 of 70, lead 0.15 s 13 of 70 (41 contacts): the damped hold does not converge onto the plan, so no oracle here shows a clean held plane. A constant-velocity pass (a designed pad velocity, so that the speed at contact does not depend on the contact time) is the untested design that would address the residual speed; it needs a new plan family and servo, and nothing found so far suggests a muscle-level stroke would approach the oracle. The oracle ladder (3 Oct, `scratchpad/tt4/PLANE_NOTE.md` items 7-8; all rows past the first are labelled oracles): plain champion stroke 30 / 70 serves; ideal arm + hand-held paddle 24 / 70; + settled pelvis 34 / 70; rigid weld no better (31 / 70); a held plane (early arrival, damped hold, welded paddle, settled pelvis, trunk locked) 40-48 / 70, and with the arm muscles off while the servo runs **47 / 70 and 63 / 100 (67 %, 63 %)** at pad speed 0.07 m/s, 0.5 cm, 2.1 deg; the kinematic wall 97 %. The return follows the pad's orientation error at contact (at most 1 deg: 9 of 10; 1-3 deg: 34 of 45; above 3 deg: 4 of 13) and the 1-4 deg floor is the wrist's joint limits at the champion's stance (a limit-respecting servo reaches only 37-51 of 70 serves). So an oracle with everything ideal returns about 65 % (the 2025 winner's 64 %, the champion's 40 %), not 90 %; the next lever would be a stance / wrist-range planner, then a muscle-level realization (Erik's call). (Superseded in part later on 3 Oct: planning the contact BACKWARDS from the legal set reaches 84-85 % with the same ideal servo, `scratchpad/tt5/NOTE.md`.) The wrist flick stays a separate rotating-plane family (`flick_mode`, off).

### Table tennis: timing, slicing the ball's path, and solving backwards (3 Oct 2026)

Erik asked (3 Oct): take a miss, slice the ball's path and hit the ball at each position in it, at many angles, orientations and speeds, "see if we have a timing issue"; "otherwise we could consider solving backwards".
Everything but the first bullet is a LABELLED DIAGNOSTIC ORACLE (never comparable with the official trial). Full note, tables and tools: `scratchpad/tt5/NOTE.md`; oracle modes `o4`-`o8` and the `orc_plan` / `orc_traj` / `o2_taumax_j` options in `playground/tasks/myo_tt_oracle.py`.

- **What the champion's 200 serves are** (plain stroke, sets A + B): 77 solved (38.5 %), 100 touched but not returned (50 %), 23 pure misses (11.5 %): the loss is the quality of the contact, not reaching the ball.
- **Timing (the champion's own recorded stroke replayed against the same ball path, shifted -100 ... +100 ms, 4200 physics rollouts):** a timing JITTER, not a bias. The solved rate is flat at 31-32 % for global shifts of -30 to +10 ms; per serve the
  legal window is a median 70 ms wide when the serve is solved and 40 ms for the failing touches, which sit a median 30 ms from their window (a legal return exists within +-100 ms for 57 of 100 failing touches and 9 of 23 misses); the per-serve timing
  error has median -5 ms and sd 40 ms and does not follow the ball's arrival (r 0.07) or the serve (|r| <= 0.16). A timing error of sd 40 ms (today) is worth about 35 % solved, sd 20 ms 47 %, 10 ms 55 %, zero 63 % (replay units; the rigid replay
  solves 31 % where the real run solves 38.5 %). 43 of the 100 failing touches and 14 of the misses have no legal timing at all (orientation, velocity or position).
- **Hit the ball at every position, at many pad angles and speeds (kinematic wall, 8568 rollouts, 7 serves):** the legal region is small, about 3 of 56 pitch x yaw cells (10 degree grid) at a position, none at 2 m/s of retreat: the pad has to be within about
  +-7 degrees of one angle that moves along the path; the champion's pad at the slice nearest its contact is typically 10 degrees from it and 4-7 cm off the ball. The impact model agrees with the physics at the cell level with 46 % precision, 75 % recall.
- **Solving backwards** (ideal-arm oracle, ball path known): for each serve take the legal contact states along the path (11 slices within +-100 ms of the champion's contact; pad angle and retreat speed from the impact model; the landing margin as cushion), execute each
  with the time-to-go pad servo and keep, without looking at the outcome, the best-margin candidate the servo reached to 1.5 cm and 2.5 degrees. **84 % / 85 % solved (validation 70 / set B 100) against 67 % / 63 % for one fixed plan with the same servo**
  (hindsight 93 %); unchanged with 2 cm / 0.2 m/s of error in the planner's ball estimate (86 % / 86 %); a reached candidate with a margin of 0.4 m or more is solved 90-96 % of the time.
- **How much survives a realistic execution:** the servo ran at its 500 N m clip on the shoulders, the muscles manage about 70-110 N m: with per-joint caps at the muscles' isometric capacities the backward plan gives 76 % / 77 % (67 % / 73 % at 60 % of them);
  with the paddle HAND-HELD it gives 34-39 % / 49-53 % (the servo's accelerations shake the paddle off its plan; only 30 of 70 and 54 of 100 serves have a reachable candidate; the searched grip does not help), and a servo of 60 rad/s instead of 150 gives 36 % / 38 % on the same plans.
  So the earlier "65 % ceiling" (PLANE_NOTE items 7-8) belonged to one plan per serve at the edge of the legal region, and the limit has moved to the paddle hold and the arm's bandwidth. Next steps are in the note (section 7).
- **Why the hand loses the paddle (later on 3 Oct, note sections 9):** it is acceleration. Hand-held, the paddle stays in 95 % of the plans whose min-jerk joint move needs at most about 90 rad/s^2 (and 90 % of those are solved) and in 2 % above 400; palm peak acceleration 130 m/s^2 is kept, 360 m/s^2 is lost (the servo's first ticks ask for 10 m/s palm speed). A retention-aware backward plan (the best legal, reachable state among those a joint-space min-jerk move can reach at 40-60 rad/s^2) exists for only 30-45 % of the serves and solves 54-62 % of them hand-held; with the champion's own stroke elsewhere the combination solves 44-46 % of the validation serves (champion 42.9 %) and 39 % of set B (34.0 %). Tried afterwards the same evening: putting the STANCE into the plan (the pelvis moves with the pad) leaves the number of serves with a gentle plan unchanged and makes the hand-held results worse (the pelvis's own acceleration loads the palm), and a faster, stronger grip with an earlier start does not hold the paddle either (note section 10): a GRIP SEARCH with the backward-plan servo as its stress test (12 grip parameters, 20 generations, rules fixed beforehand: held-out solved at least 55 % with the paddle kept on at least 70 %) found nothing: champion grip 29 % solved / 36 % kept, best grip 33 % / 37 % on 113 held-out plans (note section 11). Within this hand model and finger-activation control the hand-held result is 29-37 % whatever the grip, stance or servo shape; the rigid-paddle plan ceiling is 76-85 %. Where the hold fails (note sections 12): the palm's acceleration ACROSS the paddle in its plane (the twist about the handle axis) separates lost from kept (threshold 80 m/s^2, 95 % accuracy; 115-120 along the normal and the long axis), but a retention model built from welded dry runs does not transfer to the hand-held runs (correlation 0.20), and plans selected by it solve 21-23 % hand-held.

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

### Batting round 2 (29 Sep 2026): bat speed in robolab's own representation

Erik's goal is still "increase the bat speed". Round 1 (v6) raised it to 25.2 m/s with open-loop excitation programs (reflex gain 0,
ORACLE-class) and to 23.1 (grid) / 21.6 (24 held-out pitches) in robolab's own representation (11 quintic contraction knots per track
fitted to the programs' joint trajectories, reflexes on, `ri` 1). Round 2 works only in that representation and measures on pitches
nobody trained on. **Result: 26.5 m/s on 24 held-out pitches, 24 of 24 hit, bat_flow 2.32 (the v6 knots swing on the same pitches: 19.4 m/s, 20 of 24,
2.83), and 26.8 m/s on 48 pitches nobody looked at (v6 knots: 17.7, 36 of 48). That is above the open-loop oracle (25.2 / 25.2 on its own
trials, which an in-representation swing now holds: 26.7 on the 18 grid pitches, 26.9 on the 24 oracle-era held-out pitches).** The last 0.1-0.2 m/s
(S10 over S3) cost some ball quality (fair balls 143 of 162 against S3's 153), so S3 stays the swing to use when fair balls matter. On a
labelled 95th-percentile body (`ROBOLAB_PROFILE=p95`, its own arena trial) the same swing structure, retuned, reaches 32.4 m/s on 48 pitches nobody looked at (48 of 48 hit;
the MLB average is 32.0), at a cost in ball quality (fair 35-36 of 48; S9, a second retune that prices the aim harder, 37-44 of 48 at the same speed).

**Yardstick.** Three new arena trials (the ORACLE trials stay as they were):

| trial | pitches | seeded with |
| --- | --- | --- |
| `bat_power_fresh_rep` | 24 fresh continuous pitches, seeds 1100-1123 (`BAT_FRESH_PITCH`: the distribution of `bat_power_fresh`, new seeds) | the v6 knots swing: 19.44 m/s, 20/24 hits |
| `bat_power_fresh_rep_clean` | the same, guard `bat_flow` <= 3.0 on every pitch | the same swing: fails the guard (2 hits above 3.0, and the 4 misses) |
| `bat_power_fresh_rep_p95` | the same pitches, LABELLED BODY VARIANT: the athlete at `ROBOLAB_PROFILE=p95` | the athlete swing carried to that body and retuned once (S7): 27.12 m/s, 21/24 hits; now held by S8b (30.85, 23/24) |

Seed sets used, never mixed: arena 1100-1123 (and the old 1000-1023) only to score; practice 3000-3143 (S1: 16 maximin pitches, S2: 16 more,
S2c: 24 of them), 5000-5047 (taim calibration; P95 training), 7000-7323 (random practice), 8000-8015 (body sweep); validation 4000-4047 (looked at
during the work, as run); untouched final validation 6000-6047.

**Why the knots swing missed (the misses were not "1-3 cm").** A new task, `tasks/bat_rep.py` (every seed one fresh pitch, per-pitch aim
diagnostics: `aim_n_cm`, the ball's offset from the bat's swing plane at contact or closest approach, a hit needs |aim_n| < ~7 cm; `aim_s`,
where along the bat the ball is met), and a cheap evaluator, `playground/bat_rep.py` (4.3-4.6 s rollouts, a 2-4 worker pool; it reproduces
the arena scores exactly), showed on 144 fresh pitches (seeds 3000-3143) 115 hits and aim errors of -7 to -18 cm on the low pitches
(z < 0.68), +7 to +9 on the highest, -7 to -9 near (x 0.1, z 0.9). The error is not noise: with dz, dx the pitch's crossing minus the
location the inverse-squared-distance blend of the 6 grid programs stands for (sum_i w_i z_i, sum_i w_i x_i; the blend is exact at a
program's own pitch but has no slope there), aim_n = -3.2 + 152 dz + 35 dx cm (dz, dx in m; R2 0.88, residual 1.8 cm), against R2 0.28
for aim_n linear in the pitch itself. The knots swing hits where a program was optimised and misses between them.

**taim: a first-order correction of the blend** (`skills/bat_power.w`, `aim_correction`, opt-in; all gains 0 = the v6 swing exactly).
The v5 aim law's own sensitivity vectors (`k_z_u`, `k_x_u`: the joint change that moves the sweet spot 1 m up / out with the top hand on
the handle) are applied to the mismatch and added to every knot's angle, rate and acceleration through a quintic smoothstep ramp
(`taim_ramp` of the train): offset_j = taim_z k_z[j] (dz + taim_z0) + taim_x k_x[j] (dx + taim_x0). Two unit-gain probes on 48 pitches
(`scratchpad/bat/probe1.sh`, `an3.py`) measured the plane offset it moves as a nearly perfect linear response (R2 0.99): -59.4 cm per
m of dz per unit taim_z and -52.4 per m of dx per unit taim_x, so the gains that cancel the blend's 152 / 35 are taim_z 2.56, taim_x
0.68, and taim_z0 -0.021 m removes the 3.2 cm bias. Nothing else changed: on 48 pitches not used for the fit (seeds 4000-4047) the swing
hits 48 of 48 at 23.1 m/s (aim residual 1.2 cm), flow unchanged. (The arena's sign-flip test could not promote this fix: it turns 4 misses
into hits and moves the other 20 pitches by a few tenths, and with 4 dominating differences the smallest possible p is 2^-4; the entry
stands as a loss, p = 0.061, 22.98 m/s.)

**What limited the speed once the aim was right: the reflex layer's damping and the swing's timing.** Every parameter that changes the
drive or the damping shifts the aim by a few cm (train_drv 0.8 alone: 10 misses of 16), so a search on hit/miss sees a cliff.
`playground/bat_search.py` (S1, S2) therefore scored each candidate on the aim it would have after recalibration (per candidate, aim_n
regressed on (1, dz, dx) over its 16 pitches, the residual scored, the fit's own shift left to the taim gains, `scratchpad/bat/calibrate.py`,
a Newton step); the later searches (S2b, S2c, S3, S6-S9) are as-run (`playground/search.py bat_rep`): a hit scores its bat speed minus an aim-plane
margin (0.5 per cm of |aim_n| beyond 3), a contact-position margin (8 per m beyond 0.50-0.80 m along the bat) and, in S2c, a launch-angle
term (0.04 per degree of |launch - 20| beyond 10); a miss scores -5 - 100 x gap; minus 4 per unit of bat_flow beyond 2.5; the batch's worst
pitch weighted (mean - 0.25 (mean - min)); sep-CMA-ES from the taim swing over 23-32 tunables, 16-24 fresh training pitches at a time
(seeds 3000+, never an arena seed). What it found:

- **arm damping**: the arms' reflex velocity term (`arm_swing_kd`, 0.099) braked the swing: 0.03 alone is +1.2 m/s on 16 pitches, 0.0 (the
  box floor) adds another 0.5 on the pitches it still hits. The swing's speed is set by the excitation drive; the reflex is a position servo on
  the program's joint trajectory.
- **timing**: the free swing (fire late so the ball has passed, `scratchpad/bat/freeswing.py`) peaks at 230 ms after the hips fire but the
  swing met the ball at 217 ms, 13 ms before its own peak, where the sweet spot still gains 0.13 m/s per ms. The search fires 11-15 ms
  earlier (`prog_trig` 0.230 -> 0.241-0.245), lets the knots read their targets 18-22 ms ahead of the drive (`train_lead`), and runs the train
  28 ms longer (`train_end`); after the program's own contact its table is the CMA rollout with the ball's impact in it, which the knots braked
  against, so `train_ext` carries the plan on at contact velocity instead. Contact now comes 225-230 ms after the hips fire, at the swing's peak.
- **the aim vectors run out of authority**: the search's calibrated-aim objective promised 26.85 m/s and flow 2.37 for the S2 swing; recalibrating
  its aim to zero cost 0.65 m/s and 0.4 flow and needed taim gains of 6.1 / 3.2 (the k vectors move the sweet spot in the vertical / lateral
  directions, the wrong ones for the offset a timing shift makes). Two swings then missed because the contact fell beyond the bat's tip.
  Hence the as-run objective with a contact-position margin.

**Ball quality is not free.** The S2b swing (26.4 m/s) launched the balls at a mean 49 deg (fair 29 of 48; the arena's bat_quality formula 0.21):
the speed was bought with a steeper uppercut, which nothing in the bat_power metric sees. S2c prices it (0.04 m/s per degree of |launch - 20|
beyond 10): 26.1 m/s, fair 46 of 48, launch 13 deg, quality 0.45. Both are in the arena (S2b held `bat_power_fresh_rep` for a while).

**Results.** Sweet-spot bat speed at contact, m/s (a miss scores 0), athlete body, athlete controller of each stage, as run, no recalibration.
Validation seeds 6000-6047 were untouched until the last step; 4000-4047 were used to pick between candidates.

| stage (what changed) | arena `bat_power_fresh_rep` (24) | validation 6000-6047: power, hits | bat_flow mean / max | plant -> hips fire | notes |
| --- | --- | --- | --- | --- | --- |
| v6 knots (seed) | 19.44, 20/24 | 17.70, 36/48 | 2.80 / 3.00 | 51 ms | 12 misses of 48 |
| + taim (aim correction) | 22.98, 24/24 (p 0.061: not promoted) | 23.14, 48/48 | 2.80 / 2.96 | 51 ms | |
| S1 (+ arm damping 0, fire earlier, train longer) | 25.71, 24/24 | 25.87, 48/48 | 2.63 / 2.97 | 46 ms | |
| S2b (+ targets lead the drive 18 ms, train_ext, ...) | 26.20, 24/24 | 26.45, 48/48 | 2.47 / 2.94 | 33 ms | launch 49 deg, quality 0.21 |
| S2c (+ launch term) | 25.96, 24/24 (below S2b: not promoted here; promoted on the four oracle-era trials) | 26.29, 48/48 | 2.37 / 2.72 | 18 ms | fair 43/48, quality 0.45 |
| S3 (+ drive time profile) | 26.40, 24/24 | 26.70, 48/48 | 2.37 / 2.70 | 18 ms | fair 44/48, quality 0.42 (the fair-ball-friendlier swing) |
| **S10 (+ leg / stride parameters, aim and launch priced harder)** | **26.50, 24/24** (champion) | **26.83, 48/48** | **2.34 / 2.66** | 18 ms | fair 44/48 (arena 22/24), quality 0.35 |

Same swings on the other sets (arena numbers, S10 / S3): `bat_power_fresh` (24 pitches, seeds 1000-1023) 26.86 / 26.67 against the ORACLE's 25.24 and the v6 knots' 21.57; `bat_power`
(the 18-pitch grid) 26.70 / 26.52 against 25.17 and 23.12; all hit, bat_flow 2.24-2.32. The four trials the oracle held (`bat_power`, `bat_power_clean`,
`bat_power_fresh`, `bat_power_fresh_clean`) are now held by this swing, and so are the two new ones: an in-representation controller, reflexes on, is above the open-loop ceiling
of round 1. The hitch guard twins pass on every pitch (max 2.66 against the 3.0 limit). S10 is the arena champion everywhere, but its lead over S3 is 0.10-0.18 m/s
(paired on the 48 untouched pitches: +0.13, better on 40 of 48; p < 1e-4) and its balls are worse: fair 143 of 162 over the five athlete sets against S3's 153 (grid 13 of 18 against 16, arena quality
0.35 / 0.41 / 0.18 against 0.42 / 0.44 / 0.28 on `fresh_rep` / `fresh` / the grid; the oracle's `bat_quality` champion, 0.42 on the grid, is not beaten by either). The launch angle is the
aim's: see the P95 section for why the launch scatters by +-26-30 deg whatever the price on it.

Per pitch, the arena's 24 pitches (`bat_power_fresh_rep`, seeds 1100-1123: release speed m/s, crossing x m from the plate centre, height m; sweet-spot bat speed at contact, m/s, of S10 (the
champion), of S3 and of the v6 knots swing on the same pitch; S10 hits all 24 at 25.35-27.25 m/s (mean 26.50), fouls 1121 and 1123; the four pitches the knots swing missed (1104, 1109, 1113, 1121, the low
ones) are hit at 26.3-27.3 by both):

```
seed  v     x      z     S10    S3     v6 knots | seed  v     x      z     S10    S3     v6 knots
1100 38.4 +0.134 0.813  26.15  25.97  23.71    | 1112 34.3 +0.116 0.764  26.02  26.08  23.31
1101 38.4 +0.056 0.980  26.28  26.08  22.99    | 1113 37.6 -0.088 0.668  27.25  27.32   MISS
1102 38.0 -0.064 0.896  26.71  26.71  23.82    | 1114 37.8 -0.143 0.766  27.19  27.04  24.38
1103 36.7 +0.062 0.704  26.08  26.11  23.58    | 1115 35.1 -0.058 0.978  26.72  26.70  23.04
1104 37.7 +0.000 0.648  26.47  26.51   MISS    | 1116 35.7 +0.137 0.915  26.21  26.15  22.60
1105 36.2 +0.042 0.960  26.53  26.41  23.05    | 1117 34.3 +0.065 0.894  27.13  26.95  23.10
1106 35.8 +0.147 0.686  25.35  25.32  22.75    | 1118 37.8 +0.115 0.867  26.30  26.19  23.28
1107 34.7 -0.062 0.865  26.93  26.86  23.77    | 1119 36.3 +0.064 0.723  25.94  26.05  23.76
1108 40.1 +0.000 0.852  27.11  26.80  23.64    | 1120 34.2 -0.116 0.968  26.98  26.70  22.72
1109 35.7 +0.023 0.640  26.43  26.32   MISS    | 1121 36.5 -0.010 0.674  26.61  26.50   MISS
1110 35.0 -0.039 0.866  27.06  26.86  23.55    | 1122 34.2 +0.133 0.709  25.86  25.74  23.57
1111 38.3 +0.129 0.700  25.96  25.73  23.50    | 1123 35.0 +0.105 0.964  26.72  26.47  22.40
```

The slowest pitches are the outside ones (S3: x > 0.1: 25.3-26.5; S10 25.4-26.7): the contact moves toward the bat's tip (0.48 m along the bat per m of x) and the sweet spot has less speed there (the speed falls 4.4 m/s per m of x,
correlation -0.82; it does not depend on the pitch's release speed).

**The pre-swing pause and the hitches** (Erik's complaint: a stop before and after contact). The bat_flow score is the sum of the deepest dip of the
measured contraction speed lift -> plant, plant -> contact and contact -> +0.8 s, plus the worst command hold or step; means over 48 pitches:

| stage | valley lift | valley pre | valley post | command | stall before the swing | plant -> hips fire | flow |
| --- | --- | --- | --- | --- | --- | --- | --- |
| v6 knots | 0.594 | 0.846 | 0.732 | 0.615 | 31 ms | 51 ms | 2.79 |
| S1 | 0.591 | 0.814 | 0.649 | 0.560 | 27 ms | 46 ms | 2.61 |
| S2b | 0.591 | 0.761 | 0.593 | 0.498 | 18 ms | 33 ms | 2.44 |
| S2c / S3 | 0.607 | 0.685-0.688 | 0.526-0.531 | 0.493 | 7-8 ms | 18 ms | 2.31-2.32 |
| S10 | 0.579 | 0.688 | 0.534 | 0.495 | 8 ms | 17 ms | 2.30 |

The pause between the plant and the hips firing fell from 51 to 17-18 ms (the step landing later, `step_delay`, took the v5 swing from 115 to 50 ms; firing
earlier takes it to 18) and its stall in the measured speed from 31 to 7 ms; the largest command steps of the v6 knots swing were at the START of the swing
(15-20 ms after the fire: the first knot segment goes from the load's velocity to the program's within 20 ms), which the earlier, longer swing softens.
The v5 champion's flow is 2.05, so a lift -> plant dip of 0.58-0.61 (the leg lift's apex) remains: the lift and stride parameters were searched only in S10 (below), which took the lift valley from 0.607 to 0.579.

**A zero-initialised temporal residual on the knots (the Codex recipe).** The recipe is a fixed causal-convolution feature map with a small zero-initialised
readout trained by ES on fresh random pitches, judged on held-out ones. Three tries on the S2c swing, each starting from exactly the controller (all
weights 0), trained by as-run sep-CMA on fresh random pitches and judged on the 48 validation pitches, paired:

- **Codex's own architecture** (`bat_residual.w`: its two convolutions and fixed projections reimplemented; 20 readout weights `tc0-tc19`; outputs bounded 0.16 rad
  on the spine rotation and flexion, both elbows and both wrists' flexion, added to the reflex TARGET): the training objective gained 0.18 in one
  generation and nothing more in eight; held out it is worse: -0.12 m/s (better on 14 of 48 pitches, worse on 33, p < 0.001) and +0.20 bat_flow.
- **the same readout on a temporal basis** (`tres`: 6 gaussian bumps after the fire plus the pitch): not run to a result (the drive profile below was ahead).
- **the readout on the feed-forward DRIVE instead of the targets** (`dshape`: the drive of each joint group scaled by 1 +- 0.5 times a function of time since the
  hips fire, 30 weights `dw0-dw29` on 6 gaussian bumps, 36 random fresh training pitches, 7 generations of 14): the objective gained 1.4; held out **+0.42 m/s on
  all 48 pitches** (26.57 against 26.15, p < 0.001) at unchanged bat_flow (2.31): a hit at 110-190 ms is worth more drive (the pelvis' factor rises to 1.5 at 150 ms,
  the spine's and shoulders' too), the last 40 ms about 15 % less. A second search continuing it on new pitches found nothing more (+0.05).
  So the drive, not the reflex target, is where a learned time-varying correction pays on this controller; feedback features (Codex's) did not.

**Leg and stride parameters (S10).** A one-at-a-time scan around S3 (16 practice pitches, calibrated-aim evaluator, `evalcal.py --sets`, 29 settings) showed that `drv_hips`, `dur_hips`,
`dur_leglift` and `hips_lead` do not change a single bit of the run (the train swing replaces the tracks they parametrise), `leg_follow` and `lift_at` change only the flow, and the rest buy 0.1-0.2 m/s
each at a flow cost or move the aim by centimetres: `leg_swing_kp` 2 +0.19 m/s (flow +0.09), `leg_swing_kd` 0.04 +0.19 (+0.05), `stride_at` 0.40 +0.20 (+0.14, aim shifted), `train_legs` 0.9 +0.08,
`drv_stride` 0.8 (flow -0.04), `lift_at` 0.14 (flow -0.06 for nothing else), `dur_stride`, `step_delay` and `stride_at` 0.55 break the aim. S10 searched them together with the P95 retune's 41 tunables
(50 in all, 24 new training pitches, the aim margin and the launch cost as in S9, the flow term anchored at S3's own 2.35): one generation at two workers, then five with four (about 1,700 rollouts), from 21.7 to 23.6 in
the objective. Held out (paired against S3, as run): **+0.14 m/s on 4000-4047 (better on 44 of 48), +0.13 on the untouched 6000-6047 (40 of 48), +0.10 on the arena's pitches (18 of 24; p 0.0006)**,
the lift valley 0.607 -> 0.579 and bat_flow 2.31 -> 2.30 (4000-4047); what it moved: `drv_stride` 0.53 -> 0.65, `leg_swing_kd` 0.084 -> 0.069, `leg_swing_kp` 1 -> 0.85, the fire 4 ms earlier
(`prog_trig` 0.2437 -> 0.2478), the drive profile by up to 0.29. It is the champion of all six athlete trials, and the balls are worse (above).

**What limits the trunk and the elbows** (`playground/bat_power_diag.py --fresh`, S3, 16 fresh pitches; earlier rows of the round-1 tables are v5 / oracle):
pelvis yaw peaks at 7.6 rad/s (437 deg/s; MLB 714) 127 ms before contact, the torso at 9.9 rad/s (567 deg/s; MLB 937) 160 ms before, the top-arm elbow at 12.8 rad/s
(732 deg/s) and the bottom-arm elbow at 18.2 rad/s (1042 deg/s; pros 1539, Dowling & Fleisig 2016), the bottom wrist at 18.6 rad/s (1065 deg/s; college 1093 +- 354),
the bat at 37.8 rad/s (2164 deg/s). Against each joint's unloaded limit (vmax / 0.3 ranges per second): pelvis yaw 0.32, spine 0.25-0.39, shoulders 0.22-0.45, elbows
0.49 and 0.70 - none is near its speed limit, and none but the wrists is near an end of its range (pelvis yaw stops 4.8 % of its range from the end, 0.3 % of the
swing within 3 %; the wrist deviations spend 11-25 % of it within 3 % of an end). They are limited by torque x time / inertia and by the chain's sequencing:
the pelvis yaw's effective inertia in the start posture is 2.3 kg m^2 (its muscles peak at 375 N m), the bottom elbow's 0.53 (105 N m), and the prime movers are at
>= 0.9 activation for only 46 % (pelvis), 51 % (trunk, shoulders), 48 % (elbows) and 26 % (wrists) of the 220 ms power phase (S1: 43 / 34 / 34 / 33 / 13),
co-contraction 0.02-0.05. The drive profile added sustained drive and 0.4 m/s; the rest is what a torque and a 0.23 s swing allow. The S10 swing gives the same picture (16 fresh pitches:
pelvis yaw 7.70 rad/s at 127 ms before contact, torso 9.89 at 161 ms, bottom elbow 17.7, top elbow 12.6, bat 37.96 rad/s; prime movers at >= 0.9 for 45 % (pelvis), 47 % (trunk), 32 % (shoulders),
24 % (elbows), 14 % (wrists) of the phase, 49-50 % for the instantaneous agonist of trunk, shoulders and elbows, 21 % for the wrists' (`out/bat_r2/diag_s10.json`).

**Would a body change matter? Yes: about +2 m/s per +20 % of strength or of muscle speed, and a labelled P95 body reaches the MLB average.**
The ideal-control ceiling (`bat_ceiling.py --ball`, round 1's recipe: CMA over open-loop excitations of the 16 upper-body joints, captured from the ORACLE program's swing,
the 34 m/s centre pitch, `scratchpad/bat/ceil.sh ... prog_athlete prog_p95`) is 25.5 m/s for the athlete (the program library is already round 1's CMA optimum: no gain in 400
generations; round 1's own run found 25.69) and **at least 32.9 for the P95 body** (400 generations 30.8, 1000 generations 32.9 at a 75 deg popup, still creeping up:
the ball-mode score has no launch term). The in-representation swings on the same pitch: athlete S3 27.2, P95 S8b 32.7. So the closed-loop athlete swing is 1.5 m/s ABOVE round 1's
open-loop ceiling, and the tool cannot be used as a ceiling for it any more: started from the S2c or S3 swing's own state the open-loop CMA never gets back to the swing (its replay of the
net excitations misses the contact point by 8-12 cm; through that point it reaches 22.7 m/s against the swing's 27.2 on the athlete, 28.0 against 32.7 on P95, `--target sweet`,
`scratchpad/bat/ceil_sweet.sh`): the reflex layer's feedback does work the open loop cannot reproduce. The body question is therefore answered by the controller itself:
the S2c controller, unchanged, on the athlete body with one change (16 fresh pitches 8000-8015, `scratchpad/bat/bodysweep.sh`; bat speed at contact or closest
approach with the aim shift re-centred, which the swing needs after a body change; as-run hits in brackets):

| body | bat speed, m/s |
| --- | --- |
| athlete (strength x1.5, vmax 3.0) | 26.40 (16/16) |
| pelvis yaw x2 / trunk (pelvis yaw + spine) x1.5 | 26.86 (16) / 27.68 (15) |
| elbows x2 / arms (shoulders, elbows, wrists) x1.5 | 27.61 (15) / 28.41 (1) |
| all strength x1.2 / x1.33 / x1.5 / x2 | 28.71 (12) / 29.58 (3) / 30.36 (0) / 32.22 (0) |
| muscle speed (vmax) x1.2 / x1.5 / x2 | 27.99 (16) / 29.39 (13) / 30.68 (11) |
| strength x1.5 and vmax x1.5 | 33.14 (0) |
| **ROBOLAB_PROFILE=p95: strength x1.32, speed x1.2, activation x0.87** | **30.83 (0)** |

The arms are a bigger lever than the trunk (the wrist whip carries the speed), and the speed of the fibres matters as much as their force (a faster muscle keeps
more force at the same joint rate). `ROBOLAB_PROFILE=p95` (playground/profiles/p95.json: each multiplier a marginal 95th percentile of healthy young men, with sources; the athlete's
own x1.5 already stands for strength-trained men, x1.58 in Maden-Wilkinson et al. 2020) is the honest, literature-backed body change; it is labelled, opt-in and its own arena trial,
`bat_power_fresh_rep_p95`, never to be compared with the athlete trials. The athlete swing does not carry over as it is: the faster swing reaches the ball's plane earlier and met it
beyond the tip (contact position 0.90 m along a 0.86 m bat), so it needs its fire 12 ms later (`prog_trig`), the taim gains recalibrated (`calibrate.py`, 45 of 48 hits at 29.7) and a search.
S7 (an as-run sep-CMA on this body with the S2c objective) gave 30.64 m/s, 47 of 48 on the validation pitches, arena 27.12 (21/24); carrying the athlete's drive profile over and retuning it
with 41 tunables (S8/S8b, 24 training pitches, seeds 5000-5023) gave `params/bat_r2_p95_s8.txt`: **32.38 m/s, 48/48 hits on seeds 4000-4047 and 32.43 m/s, 48/48 on the untouched 6000-6047**
(bat speeds 31.0-33.4, bat_flow 2.44-2.45, max 2.85), **30.85 m/s, 23/24 on the arena's 24 pitches** (hit speed 32.2; the miss is 1123, the outside high pitch, contact 0.89 m along the bat;
bat_flow 2.44, max 2.64). The price is ball quality: fair 35-36 of 48 (athlete S3: 44-46), mean launch 30-39 deg, 19-27 % of the hits launched above 60 deg (arena quality 0.17).
The launch angle is a straight line in the aim: launch = 31-39 + 10-14 x aim_n deg (aim_n, the ball's offset from the swing plane in cm; correlation 0.85-0.99 on
the validation sets, both bodies), and aim_n has a spread of 1.9-2.6 cm even after the aim correction, so the launch angle scatters by 26-33 deg (1 sd) whatever its mean:
the price on the launch acts on its mean (S8b's 30-42 deg against S9's 19-34 deg below), its spread is the aim's. S9 (S8b's best, the same 41 tunables, 24 new training pitches, seeds 7300-7323,
the launch cost raised to 0.10 per degree beyond 8 off 20 and the aim margin to 1.0 per cm beyond 1.5) keeps the speed and gives part of the ball quality back: `params/bat_r2_p95_s9.txt`,
**32.35 m/s, 48/48 hits (fair 37) on 4000-4047, 32.41 m/s, 48/48 (fair 44) on the untouched 6000-6047 and 32.13 m/s, 24/24 (fair 20, quality 0.29) on the arena's pitches**, mean launch
19.5-34 deg, 8-21 % of the hits above 60 deg, bat_flow 2.43-2.47 (max 2.85); the aim's mean moved 1.3 cm down, its spread stayed at 2.3 cm. S9 is NOT the arena's champion: against S8b its
paired test is p = 0.47 (on the 23 pitches both hit it differs by -0.05 m/s, -0.43 .. +0.23; it only converts the one miss), so `bat_power_fresh_rep_p95` is held by S8b (30.85, 23/24); S9 is the P95
controller to use.
The body sweep's hooks are env vars of `tasks/bat.py` (BAT_STRENGTH, BAT_VMAX, BAT_GROUP_STRENGTH, BAT_GROUP_VMAX; defaults change nothing).

**What did not work / caveats.** `hip_open` (v5) lowers the speed and worsens the flow; `train_drv` +-20 % breaks the aim (10 and 4 misses of 16); the calibrated-aim objective was
optimistic (26.85 promised, 26.19 after recalibration, 2 misses on 48 pitches) when the search wandered far; `train_lead` and the earlier fire move the contact toward the bat's tip (misses
at 0.86-0.92 m), which is why the later searches carry a contact-position margin; the conv residual on the reflex targets hurt; S2b's steep uppercut; the fast S2b swing does not
generalise its quality. **Ball quality is the open problem**: the launch angle is 10-14 deg per cm of the ball's offset from the swing plane, and that offset scatters by 1.9-2.6 cm after the aim
correction (1.2 cm right after taim, before the searches, whose objectives leave +-3 cm free) and is not explained by the pitch (regressed on the release speed, the location, the blend's
mismatch, quadratics of them, the plant-to-swing gap: the residual on the other validation set falls from 1.9-2.3 only to 1.75-2.1 cm), so the launch angle scatters by 26-33 deg (1 sd), fair balls
are 88-95 % and the quality 0.18-0.45, whatever the price on the launch. The arena's paired test cannot see a swing that only converts one miss (S9 against S8b: p 0.47). The 4-pitch demo is
kind to S3 (4 of 4 fair) and unkind to S10 (`out/bat_r2_s10.mp4`, `out/bat_r2_s10_sheet.png`: 27.0, 26.3, 25.9, 27.4 m/s, 2 of 4 fair, both grounders; the fouls are the 76 mph outside pitch, met
1.4 cm beyond the bat's end, and a grounder at -30 deg). Not done: a new program library optimised for the longer swing (the CMA ceiling cannot find one from this state), the `tres` bumps on the reflex targets, a
better aim law (the source of the scatter), the P95 body with the leg parameters.

**Files.** Controller features (all opt-in, the v6 params replay exactly; each build was checked bit for bit against the last): `lib/robolab/skills/bat_power.w`
(taim `taim_z/x/z0/x0/ramp`; `train_first`, `train_legs_ease`, `train_ext`, `train_lead`, `train_dlead`; `dshape`/`dw0-29`; `tres`/`tw`/`tv`/`tc`),
`lib/robolab/skills/bat_residual.w` (`BatConvResidual`), entry `lib/entry/bat_r2.w` -> `./build.sh bat_r2` (`bin/robolab_bat_r2`; frozen copies
`bin/challengers/bat_r2-t1` .. `-t8`: t1 taim, t5 adds the train_* timing features, t8 everything). Tools: `playground/tasks/bat_rep.py`, `playground/bat_rep.py`,
`playground/bat_search.py`, `playground/bat_power_diag.py` (`--fresh`, joint range margins), `playground/tasks/bat.py` (body env hooks). Log and scripts: `scratchpad/bat/`
(`LOG.md` has every run with its command line, seeds, result and pid). Params: `params/bat_r2_taim1.txt` (first fix), `bat_r2_s1.txt`, `bat_r2_s2b_g5.txt` (fastest, steep uppercut),
`bat_r2_s2c.txt`, `bat_r2_s3.txt` (fair-ball-friendlier), **`bat_r2_s10.txt` (fastest; champion of the six athlete trials)**, P95 body (labelled): `bat_r2_p95_s7.txt`, `bat_r2_p95_s8.txt` (arena champion of `bat_power_fresh_rep_p95`), **`bat_r2_p95_s9.txt` (the one to use)**;
searches in `params/search/bat_r2_s*.txt`. Evaluations in `out/bat_r2/`, ideal-control runs in `out/bat_ceiling/r2*_*.json`; scripts `scratchpad/bat/ceil.sh` (`--ball` ceilings, variants `prog_athlete`, `prog_p95`),
`ceil_sweet.sh` (`--target sweet`), `bodysweep.sh`, `s9.sh`, `s10.sh` (resumable: `s10.sh 4 1700 params/search/bat_r2_s10_gen2.txt s10b`).

Video: `out/bat_r2.mp4` and `out/bat_r2_sheet.png` (S3, reflexes on, on the 4 bridge demo pitches of 82.8, 89.5, 76.1 and 86.1 mph: 26.8, 25.9, 25.7 and
27.3 m/s, 59.9-61.1 mph, all 4 fair, bat_flow 2.09-2.38, 225-230 ms from the hips firing to contact; the v6 oracle on the same pitches: 25.6, 24.9, 24.3, 25.8 m/s, 3 fair;
the 76 mph outside pitch is met 0.9 cm from the barrel's end); S10 on the same pitches, `out/bat_r2_s10.mp4` / `out/bat_r2_s10_sheet.png`: 27.0, 26.3, 25.9, 27.4 m/s but 2 of 4 fair.

```sh
.venv/bin/python playground/bat_rep.py eval --params params/bat_r2_s10.txt --controller bin/challengers/bat_r2-t8 --seeds 1100:1124      # = the arena, 25 s
.venv/bin/python scratchpad/bat/calibrate.py --params P --controller C --seeds 5000:5048 --iters 3 --boost 2 --out params/x.txt           # taim gains after a change
ROBOLAB_CONTROLLER=$PWD/bin/challengers/bat_r2-t8 BATREP_FLOW=4 BATREP_FLOW_CAP=2.5 BATREP_LAUNCH=0.04 .venv/bin/python playground/search.py bat_rep \
    --method sep_cma --budget 2600 --workers 4 --sigma 0.15 --pop 14 --risk 0.25 --seconds 4.3 --seeds 7100,7101,... --init params/bat_r2_s2c.txt --only "dw*" --out params/x.txt
BAT_BODY=athlete ROBOLAB_PROFILE=p95 .venv/bin/python playground/bat_rep.py eval ...                                                        # the labelled P95 body
```

## Dribble through the legs, round 2 (29 Sep): muscle programs (ORACLE), and where a chain of passes breaks

Goal: several through-the-legs passes in a row, judged by the task's rules on held-out starts (`btl_streak`, the longest run of good
passes in 15 s; a pass counts only if the ball crosses the leg gate below the crotch, bounces once, is first touched legally by the other
hand and that hand's push lands a legal bounce). Log: `scratchpad/btl2/LOG.md`, tools: `scratchpad/btl2/`.

**Where A4 (the reflex controller, `params/dribble_btl_a4.txt`, `bin/challengers/dribble_btl-a2`) breaks** (`chain.py`, 25 starts): pass 1
(the right hand's launch) is complete on 84 %, pass 2 (the left hand's return) on 44 %, pass 3 on 0 of 12; the ball rises 0.63, 0.43, 0.40 m
after the bounce of passes 1, 2, 3 and meets the receiving hand at 2.15, 1.22, 1.07 m/s. The launch leaves the palm at 3.36 +- 0.12 m/s
down and 2.62 sideways (repeatable). The left hand's return leaves at 1.5 +- 0.8 down and 1.5 sideways (a full return needs 3.3 and
2.6): the lead-leg hand sits at the forced back-left spot (x about -0.12, y 0.38, the leg-clearance and gate rules leave no other),
its arm is at its joint limits there (shoulder rotation -1.34 of -1.40, elbow at 0, wrist flexion 1.0 of 1.2) and the reflex stroke is
a wrist flick. Nothing in the reflex parameters fixes it (scans of the drive, trunk turn, spot placement, the right hand's low
stroke: pass 3 stayed 0 of 12 to 16).

**The arm can do it** (`oracle_lib.py`, `oracle_search.py`): record a controller run, replay its recorded activations from a MuJoCo
snapshot bit-exactly (0.03 s per replay) and replace the 16 arm muscles by a piecewise-linear activation program (a knot every 25 ms,
values 0..1) searched by CMA-ES. On one start the left arm delivers a full-energy return (score 0.008 after 30 generations: release
(2.07, -1.98, -3.27) m/s at z 0.54, apex 0.68, gate crossed, bounce near the ankles; A4 releases (1.25, -1.48, -2.08) on the same
start), and the right arm a full return of the low ball (score 0.000). So the wall is the controller's stroke representation (a reflex
servo plus pose chunks), not the muscles or the geometry.

**What was built** (all opt-in in `skills/dribble_btl.w`; A4's params replay it bit-identically, `scratchpad/btl/identity.py` on seeds
601, 705, 716; ORACLE-class: the tables are open-loop arm activations that bypass the reflex layer):

- `pg_on`: a stage starts `pg_lead` = 0.165 s before the ball's predicted rising crossing of the strike height (`receive_state`, exact
  ballistic), plays a table `pg<p>_<muscle>_<knot>` (16 arm muscles, a knot every 25 ms) as the hand's activations with the reflex gain 0,
  and the hand's touch and release hand the ball over as ever. `pg_first 0` programs the launch too; `pg_stages` / `pg_per` cycle the last tables.
- `pg_gs`: the table is T0 + sum u_i T_i, formed and bounded to [0, 1] at the knots (each gain block bounded to +-`pg_gmax` per unit of its
  feature): u = the predicted crossing (x, y) offset from the stage's nominal, and (`pg_nz`, joints `pgzj<i>`) the stroking arm's posture at
  the trigger, the contraction difference of a joint's muscle pair from the sensor frame (wrist flexion, shoulder abduction, elbow).
- fits (`scratchpad/btl2/oracle_gs.py`, sep-CMA on 816 to 1632 knot values, 80 training starts, the replay costs 0.03 s): the stages are fitted
  in order (launch, left return, right return), each on records of the closed-loop chain with the earlier stages in the loop, to a tight
  arrival target that the next stage is fitted from (position within 3 cm, velocity within 0.15 m/s of what the next hand works best from),
  so a stage's output is repeatable and the next stage sees a narrow input.

**Why open-loop stages need three ingredients** (each found by a closed-loop check on unseen starts, `chain.py` / `stage_stats.py`):

1. *The replay must contain the stage's own program.* Replaying the recorded activations of everything but the 16 arm muscles gives a
   different ball than the closed loop when the stroke changes (the trunk, legs and other arm react): the launch's arrival at the left hand
   came out 4 cm off the replay's on average (up to 8 cm), the release velocity 0.25 m/s off, although the trigger tick, the features and the arm's
   activations were identical to 1e-3. Fitting on records made with the current program in the loop (an iterative refit, "ILC over the
   fit") closes it: the replay's J now predicts the closed loop's (0.037 against 0.057 for the launch, was 0.161 against 0.234) and the
   launch's arrival at the left hand went from (-0.10, 0.39) +- (0.039, 0.042) to (-0.12, 0.37) +- (0.030, 0.027).
2. *The ball's position is not enough of a feature.* After the gain schedule on the predicted crossing the outcome scatter of a stage
   (release velocity, arrival) is explained by the stroking arm's posture at the trigger (leave-one-out R^2 over 95 starts: left release
   vz 0.65, vx 0.43, arrival x 0.29 with the left arm's joints against 0.24, 0.00, -0.06 with the ball alone; for the right arm, which
   is still in the launch's follow-through, vy 0.62, arrival y 0.50), so the posture joints are inputs of the gain schedule.
3. *The objective must price what the next stage needs.* A stage's arrival error of 10 cm cost 0.14 of a J of 0.6, and the closed-loop
   right stage arrived 10 cm off; the arrival weight from 2 to 8 per m put it on target (pass 2 complete 4 of 23 -> 11 of 23).

**Results** (ORACLE-class: the launch, the left return and the right return are open-loop tables, A4's reflexes drive everything else,
including the left hand's second stroke; `bin/challengers/btl2-b12` with `scratchpad/btl2/params/pgP0LRz2.txt`, the arena champions
`bin/champions/dribble_btl_streak_fresh32-*`; each challenge below won on the arena's sign-flip test and was promoted):

| arena trial (15 s) | A4 (reflex) | ORACLE chain | paired difference, p |
| --- | --- | --- | --- |
| `dribble_btl_streak_fresh32` mean longest streak, 32 fresh starts (seeds 1101-1132, never used in any fit or scan) | 1.22 +- 0.28 | **1.84 +- 0.32** | +0.63, p 0.003 |
| `dribble_btl_streak_25` mean longest streak (seeds 701-725) | 1.28 +- 0.29 | **2.12 +- 0.35** | +0.84, p 0.001 |
| `dribble_btl_25` good passes / attempts | 0.104 +- 0.031 | **0.188 +- 0.036** | +0.084, p < 0.001 |
| `dribble_btl` (10 starts) good passes / attempts | 0.080 | **0.220 +- 0.070** | +0.14, p 0.009 |

Per pass on 32 unseen starts (901-932, 15 s; the fits used seeds 801-900): the launch is good on 97 %, the left return on 75 %, the
right return on 42 % (pass 3), then A4's reflex left hand on 14 % (pass 4); streaks [4, 4, 3 x9, 2 x13, 1 x7, 0], mean 2.13, at least 3 on 11
of 32. On 64 further starts no fit or trial ever used (seeds 1301-1364, `chain.py`, 15 s) the same controller scores 1.95 against A4's
1.22 on the same starts (paired +0.73 +- 0.22, sign-flip p < 0.001; a streak of 3 or more on 14 of 64, A4 on 0 of 64; passes 1 to 4
good on 95, 75, 32 and 9 %). The first chain with two programmed returns (`pgLR_b`, before the closed-loop refits and the posture
features) had 1.50 on the fresh trial (p 0.019).

Per-start streaks of the champion (from `playground/arena/champions.json`): fresh32 (seeds 1101-1132) `[1,2,3,2,2,1,3,0,1,0,4,1,2,2,2,3,3,2,
2,2,2,3,0,2,1,2,2,1,2,2,2,2]` (a streak of 3 or more on 6 of 32, one 4, three 0); `dribble_btl_streak_25` (seeds 701-725)
`[3,2,2,2,0,3,1,2,1,3,3,2,2,1,4,2,2,3,2,1,2,2,3,3,2]` (3 or more on 8 of 25). A4 reached 3 on none of the 25 trial starts, the 32 fresh
starts or the 64 further ones (its best is 2).

**What did not work.** Reflex-parameter probes and a sep-CMA of the right hand's low stroke (pass 3 stayed 0 of 12 to 16); one open-loop
table for a stage without a gain schedule (fitted to 12 starts J 0.15, on 8 others 0.45; the ball's arrival varies 0.23-0.48 m in y);
the launch as a replay-fitted table on top of A4's reflex left hand (pass 1 complete 9 of 24 against 21 of 24: the next hand is tuned to
the arrival it knows, so the stages have to be fitted to each other); a joint search of two stages on a two-stage replay (108 s per
generation, no gain); cycling the last two tables for the passes after the third (35 % against 42 % on pass 3); and an open-loop
table for the left hand's second stroke (`--fresh-gains` from the first stroke's table: J 12-16 after 30 generations, no touch on most of
99 starts: at that moment the arm is still recovering, its wrist flexion scatters over +-0.45 against +-0.07 before the first stroke).

**What limits it.** Not the muscles: the muscle-level optimum gives a full-energy return from either forced spot. The open-loop
family is the limit: the left stage's release velocity still scatters +-0.27 (vx), +-0.17 (vy), +-0.21 (vz) m/s over its own training starts
after the ball and posture features (0.39, 0.29, 0.27 with the ball alone), and more on unseen ones
(the closed-loop pass rates on unseen starts are 97 %, 75 %, 42 %, and 14 % for the reflex left hand's second stroke, so a chain
of independent passes is expected to end near the measured mean streak of 2 (15 s)), and inputs the left hand cannot reach are lost
outright: before the launch was refitted 10 % of the arrivals came at y > 0.47 m, where the left hand cannot strike (it sends the ball
toward -x), and arrivals at x < -0.15 m leave the left hand 0.4 m/s short (the ball lands 0.15-0.3 m before the right hand). More
than 4 passes would need the stroke to be closed-loop on the palm-ball relation (a feedback stroke that starts from any recovery
posture), which the table representation cannot express; A4's reflex has the feedback but not the energy.

Files: `lib/robolab/skills/dribble_btl.w` (`pg_*`, `pg_nz`; everything opt-in), `playground/arena/trials.json` (`dribble_btl_streak_fresh32`),
`scratchpad/btl2/` (`LOG.md`, `oracle_gs.py` fit, `oracle_lib.py` replay, `oracle_to_params.py`, `chain.py`, `stage_stats.py`, `diag_gs.py`,
`feat_cv.py`; params `params/pgP0LRz2.txt`, programs `runs/gs_pass0_c_g79.npz`, `gs_left_z1_g179.npz`, `gs_right_z2_g109.npz`); frozen builds
`bin/challengers/btl2-b1` to `btl2-b12`.

## Dribble through the legs, rounds 3 to 6 (3-5 Oct): a stroke with feedback, a leg that gets out of the way, the second-cycle strokes as tables, and the chain as one replay

Same task and judge as round 2 (`btl_streak`, 15 s, the longest run of good passes). Logs with a FINAL STATE section each: `scratchpad/btl3/LOG.md`
(agent D2), `scratchpad/btl4/LOG.md` (agent D3), `scratchpad/btl5/LOG.md` (agent D4) and `scratchpad/btl6/LOG.md` (agent D5). Everything here is ORACLE-class: the launch, the left return and the right return are open-loop
muscle tables, A4's reflexes drive the later strokes, and the legs are open-loop offsets. Every new skill key is opt-in and neutral at its default; the
previous champion replays bit-identically through every new build (seeds 601 / 705 / 716, and a 32-start chain with 32 of 32 equal streaks).

**Round 3 (D2): a low-gain servo around the tables.** `bin/challengers/btl3-e` with `scratchpad/btl3/params/final_e.txt`. Pooled 256 starts, 6 s: a
right-return aim shift +0.17; a tracking servo around the nominal contraction trajectories with velocity-referenced damping (`pg_fb*`, gains 0.1 launch /
0.025 left / 0.05 right) +0.34; `bl_angl` 1.25 on the left second stroke +0.06; the table clock aligned to the ball's predicted crossing +0.05. A gain of
0.3 or more destroys the chain, and the plain reflex blend collapses it (`pg_gain` 0.15 -> 0.41). TEST A (3001-3064) 2.047 -> 2.422, TEST B (3065-3128)
2.141 -> 2.578, pooled paired +0.406 (p 0.0001); 512 starts never used for a choice 2.023 -> 2.520; my own check on 128 starts nobody had used (9001-9128)
1.883 -> 2.414. Arena: `dribble_btl_streak_fresh32` 1.84 -> 2.31 (p 0.013), `dribble_btl_streak_25` 2.12 -> 2.72 (p 0.004) and `dribble_btl_25` 0.188 -> 0.256
(p 0.007) were promoted, `dribble_btl` (10 starts) 0.22 -> 0.26 (p 0.198) was not. The pass rule (at least 2.6 on A and B each, +0.5 paired) was not met.

**Round 4 (D3): lift the lead leg after the release.** Where round 3 breaks, per pass on 128 fresh starts: launch 98 %, left return 84-89 %, right return
59-64 %, left second stroke 27-28 %, right second stroke 0-7 % (the chain of every streak-4 start ends there). Live traces show why the middle passes fail:
the ball that rises after a release clips the lead thigh (17 % of the right returns; 13 % of the left second strokes) or crosses outside the gate (28-32 %
of the left second strokes). Lifting and abducting the lead leg AFTER the release opens the gap: `ll_hip 0.35, ll_abd 0.10` after the right return's
release and `ll_hip1 0.40, ll_abd1 0.30` after the left second stroke's (ramp 0.08 s, window 0.55 s; `bin/challengers/btl4-final` with
`scratchpad/btl4/params/final_f.txt`, fixed before any TEST run). Body failures of the right return 17 -> 9 %, `no gate` of the left second stroke
32 -> 19 %. Dose response of the hip, +0.08 / +0.15 / +0.25 / +0.35: +0.09 / +0.08 / +0.10 / +0.125 (the other direction -0.016); outward abduction helps,
the back leg, the knee, hip rotation and other window lengths add nothing. The lift starts after a table stroke has finished, so the stages before it are
untouched and the paired standard error is only 0.02-0.03.

| set (15 s, paired, sign-flip) | btl3-e + final_e | btl4-final + final_f | difference |
| --- | --- | --- | --- |
| selection 10001-10128 (chose among leg settings) | 2.555 | **2.742** | **+0.188** (se 0.044, p 0.0001) |
| confirmation 12001-12128 | 2.547 | **2.719** | **+0.172** (se 0.043, p 0.0001) |
| TEST C 11001-11064, run once | 2.562 | 2.625 | +0.062 (se 0.049, p 0.17) |
| TEST D 11065-11128, run once | 2.531 | **2.703** | **+0.172** (se 0.052, p 0.002) |
| extra fresh set 14001-14256 | 2.617 | **2.770** | **+0.152** (se 0.029, p < 1e-4) |
| MY OWN CHECK, 128 starts nobody had used (16001-16128) | 2.594 | **2.688** | **+0.094** (se 0.038, p 0.021; better on 18, worse on 6, 104 ties) |

On my check the right return goes 70 -> 75 of 119 and the left second stroke 23 -> 31 of its 85 -> 95 attempts; a streak of at least 3 on 69 -> 73 of 128 starts,
of at least 4 on 23 -> 31. The six sets give +0.06 to +0.19; D3's 512 starts never used for a choice give +0.148 +- 0.02, mine sits at the lower end. Arena
(`arena.py eval ... --promote`, trials of 10-32 starts, where a +0.15 gain has a paired standard error of 0.15-0.2): `dribble_btl_streak_fresh32` 2.3125 ->
**2.50** (p 0.014, promoted, `arena.py recheck` reproduces 2.5000 exactly, also in my own run); `dribble_btl_streak_25` 2.72 -> 2.76 (p 0.49), `dribble_btl_25`
0.256 -> 0.252 and `dribble_btl` 0.22 -> 0.28 (p 0.13, 10 starts) did not beat their champions.

The pre-set pass rule (mean streak at least 2.7 on each of TEST C and D, and +0.35 paired over btl3-e) is NOT met (2.625 and 2.703; pooled +0.117), and neither
is the stop rule's +0.25 on selection and confirmation: an intermediate gain of about +0.15, reported as one.

**What did not work** (numbers in the log; every key stays in the skill, neutral): a feed-forward linear outcome correction (the deviation is predictable,
held-out R^2 0.77 for the vertical speed, but outcomes respond linearly only below |offset| of about 0.02: +4..6 of 89 starts at best); an energy-hinge block
for the right return (-0.04) and the left return (+0.03); an earlier left second stroke (`bl_trec` 0.20 .. 0.06 takes pass 4 from 23 to 5 to 0 of about 80)
and every scan of its aim, sweep, tilt, cock and latch timing (flat or worse: it sits on a sharp optimum); reset dribbles (pass 2 falls to 16 of 127); a static
lead-leg offset from the start (-1.3: all tables were fitted with these legs); a leg lift during the right return's stroke (-0.18 .. -0.40), trunk offsets
(-0.1 .. -0.2) and 0.5 cm of stage-2 aim (-0.04 .. -0.18): any perturbation before or during a table stroke re-rolls a chaotic stroke; a joint CMA of the reflex
keys (7 min a generation, nothing in three).

**What limits it now.** The energy decays along the chain and its scatter is amplified at the left return (predicted vertical speed at the crossing of the
four stage triggers 2.23 (sd 0.08), 1.64 (0.16), 1.22 (0.42), 0.97 (0.69) m/s), and a stage's success collapses where its input energy is low (right return
7 / 19 / 38 / 62-77 % over the deciles); the success of the next stage given the delivered ball has an AUC of only 0.74-0.77, so even a perfect delivery caps the
right return near 75 %. The two reflex strokes of the second cycle are weak (apex 0.45 m, release (0.5, -1.0, -1.9) m/s against the tables' (1.4, -1.7, -3.4)): pass 4
48 % at best, pass 5 about 5 %. Next, in order: a table for the left second stroke fitted on the lifted-leg distribution (start from the stage-1 table recentred, a
hybrid start 0.1 s before the contact); a refit of the right return's table with the leg motion in the loop (opens the left return's flight clearance, about +0.05);
a table for the right hand's second stroke once the left one delivers more energy.

Files: `lib/robolab/skills/dribble_btl.w` (keys `pg_fb*`, `bl_trec / bt_trec`, `pg_vn / pgv*`, `ll_* / l2_* / ls_* / lb_* / lt_*`, `bl_dax / bl_day / bt_dax / bt_day`, `bl_ck*`), frozen
builds `bin/challengers/btl3-e`, `btl3-final` (and the `btl3-s*` scans) and `btl4-a..k`, `btl4-final`; params `scratchpad/btl3/params/` and `scratchpad/btl4/params/` (`final_f.txt`); tools
`scratchpad/btl4/` (`rlib.py` replay with additive offsets, `fit_v.py`, `valfn.py`, `body_by_pass.py`, `scan_pool.py`); my check `out/dribble2/verify3_*.log`
(`scratchpad/btl2/chain.py bin/challengers/<ctl> <params> 16001 16129 15 "" 6`); arena champion `bin/champions/dribble_btl_streak_fresh32-20261003-205634`.

**Round 5 (4 Oct, agent D4): the two second-cycle strokes as tables.** Baseline btl4-final + `final_f.txt` (the lead-leg lift). Where it broke: the left second stroke (pass 4) 31-38% and the right second stroke (pass 5) 1-5%, both A4's reflex
strokes, which end every long streak. Candidate G = `bin/challengers/btl5-a` with `scratchpad/btl5/params/final_g.txt` = `final_f` + two new open-loop muscle tables, fitted in the replay on training seeds 24001-24840 only: stage 3 = the left hand's second
stroke (gain-scheduled on the ball's predicted crossing x, y and the arm's wrist flexion, shoulder abduction and elbow; 1632 numbers; the trigger fires 0.24 s before the predicted crossing, possibly before the bounce) and stage 4 = the right hand's
second stroke (same family, trigger 0.165 s); `pg_n 5`, `pg_gmax 4`, no servo on the new stages. ORACLE-class as before; A4's reflexes take over from pass 6. One new neutral skill key (`pg_trec<stage>`); btl4-final + `final_f` replays
bit-identically through btl5-a (seeds 601 / 705 / 716, and 32 of 32 equal streaks on 901-932). Why it works: the reflex left stroke was only 54% clean (the gate crossed without body contact: it clips the lead leg), the table is 87% clean, so pass 4 goes
from 33% to 56-60%; the right hand's table, fitted with the stage-3 table in the loop and aimed at what the A4 left reflex can take, lifts pass 5 from 1% to 17%. Two pipeline findings made the fits transfer: the skill's trigger can fire before the ball's bounce
(`ball_rise` predicts the post-bounce state), so the replay's trigger tick has to use the pre-bounce prediction (the first fit on the wrong tick was -0.42 in the closed loop, the corrected pipeline reproduces the table's activations to 1e-4), and the table's lead has to come
before the reflex's own swing latch (0.2146 s) or the arm is mid-swing at the trigger for the slowest 20% of balls.

| set (15 s, paired, sign-flip) | btl4-final + final_f | G | difference |
| --- | --- | --- | --- |
| selection 20001-20128 (chose among candidates) | 2.547 | **2.938** | **+0.391** (se 0.069) |
| confirmation 21001-21128 | 2.617 | **2.953** | **+0.336** (se 0.070) |
| TEST E 22001-22064, run once | 2.672 | **2.922** | +0.250 (se 0.094, p 0.015) |
| TEST F 22065-22128, run once | 2.672 | 2.875 | +0.203 (se 0.087, p 0.034) |
| E + F pooled (128) | 2.672 | 2.898 | +0.227 (se 0.064, p 0.0006) |
| extra 23001-23256 | 2.625 | **2.945** | **+0.320** (se 0.049; streak >= 4 on 62 -> 106 of 256, >= 5 on 1 -> 24) |
| the 512 starts never used for a choice | | 2.935 | **+0.300 +- 0.04** |
| MY OWN CHECK, 256 starts nobody had used (25001-25256) | 2.594 | **2.961** | **+0.367** (se 0.046, p < 1e-4; better on 94, worse on 18; streak >= 4 on 51 -> 112, >= 5 on 2 -> 21) |

On my earlier 128 starts (16001-16128) the three generations read btl3-e 2.594, btl4-final 2.688, G 3.086 (streak >= 4 on 60 of 128, >= 5 on 11). Per pass on my 256 (baseline -> G): right return 62 -> 68% (it is judged by the next hand's push), left second
stroke 31 -> 66%, right second stroke 3 -> 17%. Arena: all four dribble trials WON and were promoted, `dribble_btl_streak_fresh32` 2.50 -> **2.75** (p 0.013), `dribble_btl_streak_25` 2.72 -> **3.16** (p 0.003), `dribble_btl_25` 0.256 -> 0.296 (p 0.035), `dribble_btl` 0.22 -> 0.33
(p 0.005); `arena.py recheck` reproduces them exactly. The pre-set pass rule (mean at least 2.9 on TEST E and on F each and +0.25 pooled) was NARROWLY NOT MET on the two 64-start sets (F 2.875, pooled +0.227), while both thresholds hold on every larger never-used set
(extra 2.945 / +0.320, the 512 starts 2.935 / +0.30, mine 2.961 / +0.367): the miss is the sampling noise of 64 starts (se of a mean 0.12). The stretch has two clauses; D4 reported it as not met, but the second (a streak of 4 or more on at least a third of the starts) IS met on every larger set
(41% of its extra starts, 39% of TEST, 44% of my 256 and 47% of my 128); the first (mean 3.2) is not (2.94-3.09).

**What did not work** (numbers in the log): a servo around the new stages (-0.03 .. +0.04), wide-range feature units, a value-function objective for stage 4 (held-out AUC 0.94, no gain), a stronger stage-3 ball (apex 0.66: the right hand cannot take it, +0.23 against +0.30), a refit of stage 2 with the lift in the loop
(-0.10: it re-rolls the downstream tables), scans of the reflex keys, changes of the lift windows, stage 5 as a table (the left arm is mid-recovery at its trigger, wrist flexion 0.21 sd 0.50). **What limits it now:** the right hand strikes the weak stage-3 ball at about 0.5 m and cannot reach a strong release (apex 0.55; a ball of apex 0.69 or more is accepted
58% of the time, below 0.48 never); the schedule features are clamped at +-2.5 spreads (86% of the stage-3 starts lie beyond it in the units of the stage-1 and stage-2 tables; the replay objective is a poor guide to the tails); the right return (60-68%) and the left return (86-89%) were not improved this round. Next: a stage-4 table that
gets the ball up (apex 0.7 or more), ILC rounds that fit stages 3 and 4 together in one chained replay, a stage-5 table with a phase-locked trigger. Files: `lib/robolab/skills/dribble_btl.w` (key `pg_trec<stage>`), build `bin/challengers/btl5-a`, params `scratchpad/btl5/params/` (`final_g.txt`), tools `scratchpad/btl5/`
(`rec5.py`, `prep.py`, `fit3.py`, `valfn4.py`, `paired.py`, `scan_pool5.py`), records and logs `out/btl5/` (10 GB: training records, fits, scans), arena champions `bin/champions/dribble_btl_*-20261004-*`; my check `out/btl5/main_*.log`.

**Round 6 (4-5 Oct, agent D5): the chain as one replay, and what limits it.** Baseline G (btl5-a + `final_g`). Every earlier round fitted one stage on the ball its predecessor delivered and composed them, and a stage-2 refit alone cost -0.10 because it re-rolls the downstream tables. D5
(`scratchpad/btl6/LOG.md`, section FINAL STATE; the host was suspended for 28 h in the middle, logged as a clock note, so the 3.5 h are active compute) built a CHAINED REPLAY (`chainrep.py`, `chainobj.py`): stages 2-4 in one physics rollout from a recorded start's trigger, with the schedule features, triggers and releases computed online by the skill's own rules.
It matches the closed loop to 1.4e-11 on the ball path and 1.8e-14 on the stage tables, with the releases equal on 833 of 833 starts; its emulated pass verdicts agree with the task's pass log on 99 / 88 / 90% (passes 2 / 3 / 4); for a CHANGED table the per-start chain value correlates 0.89 with a new closed-loop record: good enough to rank candidates, not to trust a small gain. What it measured:
G's tables sit on sharp optima of a chaotic surface (noise of 0.003 per knot costs 0.063 of the chain value, 0.03 costs 0.46), so global refits of stages 2, 3 and 4 (full tables, aim / clock / lead knobs, wider feature units) found nothing or did not transfer; only LOCALISED changes, exactly neutral on most balls, transfer with a clean paired standard error.
The chain's energy decays by about 0.1 m of apex per stage (left return 0.72, right return 0.70, left second stroke 0.61, right second stroke 0.52 m) and the tables have NO HEIGHT FEATURE: they touch every ball that peaks above 0.66 m (stage 3 99-100%, stage 4 100% above 0.62) but only 13-36% of the stage-3 balls below 0.62 m. The 31% of starts with a weak stage-3 ball average a streak of 2.2 against 3.55-3.85
for the rest (a gap worth about 0.5). A single-start oracle touches 22 of 24 balls at 0.54-0.64 m but only 13 of 24 below 0.54 (a reach limit), while the policy class reaches about 55% of the middle band.

Candidate `bin/challengers/btl6-final` + `scratchpad/btl6/params/final_i.txt` = G + a stage-3 APEX-HINGE BLOCK (the left hand's second stroke gets its own stroke for a ball that peaks below the strike height and is exactly G for every other ball; three new neutral skill keys `pg_vsel`, `pg_vts`, `pg_gv`; G replays bit-identically). Paired against G (15 s): selection +0.008, confirmation +0.039,
TEST G +0.047 (2.641 -> 2.688), TEST H +0.016 (3.047 -> 3.062), TEST pooled +0.031 (p 0.31), extra 256 starts +0.039 (3.066 -> 3.105, p 0.02, 11 better, 2 worse), all 640 held-out starts **+0.031 +- 0.010**. An INTERMEDIATE gain of about +0.03; I did not re-run it myself because it is too small for my 256-start checks to resolve and it changes no champion. The pass rule (mean at least 3.15 on TEST G and H each, +0.25 paired) is NOT met, the stretch
(mean 3.4, or a streak of 5 or more on at least 20% of starts; it is about 8%, G and candidate alike) is NOT met, and no arena trial was won (`btl_25` +0.012, p 0.24; the streak trials tie exactly), so nothing was promoted: G stays the champion of all four dribble trials. On D5's sets G itself scores 2.64-3.25 (selection 2.977, confirmation 3.250, TEST 2.641 / 3.047, extra 3.066), the 64-start sets differing by 0.4 from each other.
**What did not work:** a stage-2 energy block, clock per energy or reflex gate; the stage-4 apex block (replay train gain, validation about 0); knob fits of aim, clock and lead; a strong-side stage-3 block; wide feature units; a third leg-lift window; the full stage-3 table refit. **Next:** a nonlinear or multi-knee height feature for stages 2 and 3 fitted on all 840 training starts (the replay already has the second block, the skill does not yet), a chained replay from stage 1 so that the launch ball's energy can be a feature,
stage 4 for apex 0.68 or more with the stage-5 value function as objective, more training starts (840 are few for 80-dimensional blocks). Files: skill `lib/robolab/skills/dribble_btl.w` (`pg_vsel<stage>`, `pg_vts<stage>`, `pg_gv<stage>`), builds `bin/challengers/btl6-{a,b,c,d,final}`, params `scratchpad/btl6/params/` (`final_i.txt`), tools `scratchpad/btl6/` (`chainrep.py`, `chainobj.py`, `fitchain.py`, `rec6.py`, `an_*.py`), records `out/btl6/` (498 MB).
