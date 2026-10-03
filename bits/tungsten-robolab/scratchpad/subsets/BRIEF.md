# Brief for the subset-keyframe audits (read fully, then do the AREA you were given)

You are auditing the "robolab" muscle-control code base for SUBSET-KEYFRAME opportunities. READ-ONLY audit.

Repo: /Users/erik/tungsten/bits/tungsten-robolab (all paths below are relative to it). Robolab drives MuJoCo/MyoSuite musculoskeletal bodies with a contraction-vector controller written in Tungsten (.w files: indentation blocks, `->` defines a method, `@x` is an instance field, `+ Name` a class; read them like Python-flavoured pseudocode). SDK core: lib/robolab/{chunk,contraction,controller,easing,latch,skill,reflex,body}.w; per-event controllers ("skills"): lib/robolab/skills/*.w; entry programs: lib/entry/*.w; champion parameter files: params/*.txt (key value per line); the arena of trials and champions: playground/arena/{trials,champions}.json; long-form history: README.md, HANDOFF_20260929.md, scratchpad/*/LOG.md.

## Background

The user (Erik) asked: "seems like we should be able to define a keyframe based on a subset of muscles/joints. for instance, in the runner's toe-off keyframe, all we care about is that the toe extends. in the other trials, i'm sure there are subset keyframes that would better model what is needed or intended."

We built subset keyframes into the Keyframe Bench (site/keyframe_bench/keyframe_bench.html and seed.py): each keyframe has a `pinned` map over the 14 sagittal channels (st_/sw_ hip, knee, ankle, toe, shoulder, elbow; spine; pelvis); pinned joints constrain the motion, free joints follow a min-jerk interpolation between the neighbouring keyframes that pin them.

Your job: for the champion controller(s) of ONE area (below), find out what each keyframe / chunk / knot / posture really constrains and where a subset keyframe would model the intent better.

## What to report

For every keyframe-like element of the champion(s):

1. Definition: file:line, the parameter names and the champion values.
2. Intent: what it is for.
3. Evidence about which joints or muscle groups matter: ablations, sensitivity tests, "dead tunables", joint limits, "command minus reached" gaps in README / LOG files (quote file:line).
4. Proposed subset: pinned vs free joints or groups, and whether the free ones should hold, interpolate or be released.
5. Expressible with today's SDK or not (chunk.w / contraction.w / controller.w: what does a joint that is left out of a pose do?).
6. Value, cost, risk as 1-5 integers.

Also list keyframes that are pure via-points or do nothing and could be dropped. Be honest: if the evidence says a full-vector keyframe is right, or there is none, say so. Do not guess: cite file:line for every claim, and mark unverified things "unverified".

The format reference is scratchpad/subsets/audit_table_tennis.md (read it first; it is short and also explains what a left-out joint does in this SDK).

## Rules

READ-ONLY. Do not edit, move or delete any existing file; the only file you may create is your own report `scratchpad/subsets/audit_<area>.md` (the name is given with the area). Do not run simulations, builds, background jobs or git commands that change state (the machine is loaded by other jobs; leave every running process alone). Use many SMALL tool calls (grep -n, sed -n ranges) and keep your reasoning between tool calls SHORT: a stretch of 10 minutes without output kills an agent, and the API has been dropping connections (agents die mid-run), so WRITE YOUR REPORT INCREMENTALLY: create the report file after your first finding and append one section per keyframe-like element as soon as you have it (use Bash `cat >> file <<'EOF'` or Edit), so that a run that dies leaves a usable partial report; if your report file already exists when you start, read it and continue where it stops instead of starting over. Tool hygiene (this matters): every Bash, Write and Edit call passes a permission classifier that has been flaky today ("auto mode classifier gave no verdict"), and a stalled call can kill an agent. So read with the Read tool (offset/limit; it needs no classifier), use Bash only for things Read cannot do (one combined `grep -n` over several files is better than five calls), write each report section with ONE call, and when a call fails with that error retry it once and otherwise keep reading with Read. Time box: 25 minutes of real time. Final reply: at most 15 lines: the top three findings and the report path.

## Areas

### AREA longjump_hurdles (report: scratchpad/subsets/audit_longjump_hurdles.md)

The long jump (skills lib/robolab/skills/long_jump.w, long_jump_run.w, long_jump_com.w; entries lib/entry/long_jump*.w) and the hurdles (lib/robolab/skills/hurdle.w, hurdle_hs.w; entries lib/entry/hurdle*.w). Find the current champions (trial names containing "long_jump" or "hurdle" in playground/arena/champions.json, with their params files and controllers) and the README.md / HANDOFF_20260929.md sections on them: the take-off program, the lead-leg and trail-leg hurdle clearance, the run-up gears.

### AREA soccer_balance (report: scratchpad/subsets/audit_soccer_balance.md)

The soccer and balance postures: lib/robolab/skills/myo_soccer_v4.w (and myo_soccer_v3.w, myo_soccer.w, myo_soccer_walk.w), myo_kick.w, myo_hold.w, stand.w, search_balance.w; entries lib/entry/myo_soccer*.w. The official one-leg balance champion is params/hazard/myo_soccer_310_shc_h2b.txt (trial soccer_single_leg_310_40; precursors params/myo_soccer_single_leg_310_*.txt); its `bhold` switch parks the swing knee away from MuJoCo wrap tangents (scratchpad/hazard/LOG.md, README.md "Soccer round 11"). Also the kick and goal-scoring keyframes and the standing postures (scratchpad/soccer4/LOG.md). Typical questions: in the swing-leg park, do only the knee angle and hip flexion matter while hip adduction and rotation float? In the stance-leg posture, which joints are pinned by evidence (the shc_* parameters) and which are inert?

### AREA bat (report: scratchpad/subsets/audit_bat.md)

The bat swing: lib/robolab/skills/bat.w, bat_power.w, bat_program.w, bat_residual.w; entries lib/entry/bat*.w (bat_r2, bat_v5, bat_v6). Find the current champion(s) via playground/arena/champions.json (trial names containing "bat") and their params files (for example params/bat_r2_s10.txt), plus the README.md sections on the bat (stance, load, stride, swing keyframes, the residual). Typical questions: which joints of the wind-up and the contact keyframe matter for bat speed and which are along for the ride; which keyframes are pure via-points.

### AREA dribble (report: scratchpad/subsets/audit_dribble.md)

Dribbling and the through-the-legs (behind-the-legs, "btl") dribble: lib/robolab/skills/dribble.w, dribble_v3.w, dribble_btl.w; entries lib/entry/dribble*.w; params/dribble*.txt; scratchpad/btl2/LOG.md and the other btl scratchpad logs; champions via playground/arena/champions.json (trial names containing "dribble" or "btl"). Typical questions: for the stance and the hand strokes, which joints are pinned by evidence and which are free; which stroke keyframes are one-hand-only (arm subset) while the legs and trunk just need to stay out of the way.

### AREA runner_sdk (report: scratchpad/subsets/audit_runner_sdk.md)

(a) The runner and sprinter controllers: lib/robolab/skills/run*.w, run_natural.w, run_gear*.w, run_knots.w, sprint_*.w and their champions (trial names "run_natural" and "sprint_*" in playground/arena/champions.json; params/keyframes_erik3.txt is the natural-run keyframe set the Bench seeds from; Bolt's blocks sprint is in playground/refs/bolt/editor/*.json). In particular: Erik's toe-off example (does the run_natural keyframe chunk at toe-off constrain all joints, and which are irrelevant?), the "max knee height" keyframe (kl), the removed heel-rise keyframe (hr), and agent A5's note that some gait tunables are dead in the six-chunk stride (scratchpad/anat5/LOG.md lines 23-25).

(b) The SDK core: how a chunk, pose and skill are defined (lib/robolab/chunk.w, contraction.w, controller.w, easing.w, skill.w): can a keyframe pose a subset of joints today; what "left out" means for muscles that cross a posed and an unposed joint; what a subset-keyframe API would need (propose 3-6 lines of sketched Tungsten).
