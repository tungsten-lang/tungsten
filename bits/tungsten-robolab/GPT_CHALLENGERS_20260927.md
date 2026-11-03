# GPT challenger campaign — 2026-09-27

Worktree: `codex/robolab-challengers`. No commits. Experiments and local promotions live in this worktree. The other agent later imported selected frozen contenders into the main arena; those comparisons are reported separately with their own incumbents.



<!-- current-results-start -->
## Original campaign result (rounds 1–3)

Arena wins on all three selected problems, including both original standing-jump trials. All six initial challengers and four jump refinements are retained, with failed entries reported below.

| Existing trial | Original valid mean (passes) | New valid mean (passes) | Promoted family | Arena p |
|---|---:|---:|---|---:|
| search_jump_legal | 1.2665 (8/8) | 1.3630 (8/8) | tcn | 0.00375 |
| search_jump_robust_legal | 1.2503 (31/32) | 1.2722 (32/32) | tcn | 0.00000 |
| bat_power | 13.1633 (18/18) | 14.7206 (18/18) | pure | 0.00000 |
| dribble_crossover_25 | 3.7200 (25/25) | 7.5200 (25/25) | tcn | 0.00000 |

Jump distances are metres, batting is m/s, and crossovers are counts per run. Sampled p = 0 means 0/4,000 sign flips. Guard-coded paired differences, complete matched-budget comparisons, attribution, failure modes, and videos follow. At the end of round 3, the separate six-second champion passed 26/32 starts. Round 4 improves it to 31/32; later refinements and their limits appear below.

<!-- current-results-end -->

## Latest verified status (through round 10)

Ten rounds are complete: **26 selected challengers, 70 arena entries**, and nine local promotion events across three problems. Round 10 produces **no qualifying promotion**. Its temporal outgoing-stroke refinement scores **9.32 versus the retained round-nine champion’s 9.08**, paired **+0.24**, **p = 0.40975** on 25 starts. It beats the older main incumbent’s 7.52 (p = 0.0025), but promotion requires beating both. Pure scores 6.68.

On the ten-start trial, temporal scores **7.9 versus main 7.3**, p = 0.3275; pure scores 7.0. Both fail the conditional arms-only comparison: temporal 0.3808 and pure 1.0 versus incumbent 0.1823, where lower is better. All six entries and direct family comparisons are preserved below.

The training gains did not reliably transfer. On the same **64 untouched starts**, temporal averages **8.65625 crossovers and 6.8928125 s control**, down from its parent’s **9.09375 and 7.10703125 s**. Pure improves modestly from 6.609375 to 6.921875 crossovers. All 64 selected runs per family eventually lose. Eight thirty-second continuations per selected and parent policy also end in loss. Body contacts, loading rates, ablations and failures are explicit in the report.

Round 10 passes **36 audit checks**. It applies equal additional backbone search to different inherited policies with residual heads and catch feedback fixed; it is not a new common-initialization neural comparison. The earlier round-nine crossover champion remains **9.08**; retained jump champions are round-seven robustness **1.33965625 m, 32/32**, and round-four six-second recovery **31/32**. Latest main import and external publication remain unconfirmed. The improvement goal remains active.

## Protocol

Three problems: legal standing broad jump and landing stability; batter power; successful basketball crossovers. Each has a phase-indexed pure-search challenger and a causal temporal-convolution residual challenger. Both retain the champion's contraction keyframes, chunk sequencing, reflexes, and spring-filtered corrections. No raw activations, physics changes, strength changes, or test-seed inputs are added.

The temporal model samples at 50 Hz. It groups all measured muscle contractions into four deterministic groups, with contraction, velocity, finite-difference acceleration, and jerk channels per group, plus six task sensors. Its two causal separable convolution layers have kernel width three; the second has dilation two. The history spans seven samples. The fixed filters feed a **learned, zero-initialized 20-weight readout**. The convolution kernels themselves are not trained in this experiment. The pure baseline substitutes motion-phase features for those temporal features. Both search the same eight additional backbone parameters per problem.

All six zero-residual builds reproduce a matched champion rollout **exactly**, including targets, measured contractions, activations, and joint positions. The compiled residual spec passes 50 checks. A separate nonzero-residual integration check verifies that all six challengers change both commanded and measured motion. Shared SDK, original skills, tasks, bodies, bridges, and arena implementation are unchanged. Existing trial definitions are unchanged; `gpt_jump_stable6` is an additive six-second legal-jump trial.

| Problem | Training rollouts per challenger | Fixed training starts | Fresh validation starts | Optimizer |
|---|---:|---:|---:|---|
| Jump | 1,536 | 8 | 24 | (1+1)-ES, initial normalized sigma 0.025 |
| Bat | 512 | 4 | 24 | same |
| Crossover | 512 | 4 | 24 | same |

Each candidate is ranked during training by `0.5 * mean(seed scores) + 0.5 * min(seed scores)`, the search framework's risk-0.5 aggregate. Optimizer seed is 270927.

Training seeds start at 270901; validation uses 271001–271024. The added arena trial uses 272001–272032. These IDs are disjoint from existing arena seeds. Batter training/validation samples continuous pitch speeds and locations because the original seeded task maps **every** seed onto the same 18-pitch grid. One search runs at a time with at most three rollout workers.

Training penalizes foot-ground peak vertical force and loading rate:
`0.01 max(peak_BW - 4, 0)^2 + 0.0002 max(peak_BW_per_s - 100, 0)`.
These are observed over the full rollout. Training scores and fresh validation do not decide arena verdicts. `gpt_arena_entry.py` calls the existing arena and only saves its per-seed rows.

The six-second diagnostic matters: the starting jump lands at roughly 1.60 s but stays in the flight chunk until its 1.2 s timeout at roughly 2.42 s; its later landing target is followed by a backward fall after the original three-second evaluation ends.

The initial crossover implementation omitted an underscore in joint names, making its residual a no-op. Those 512 pure and 144 completed temporal training rollouts (plus interrupted in-flight work) are archived under `invalid_dribble_v1` and excluded. The corrected `gpt-dribble-*-v2` binaries restart both full 512-rollout budgets from the original champion. The original frozen binaries remain preserved.

## Designs

**Jump, pure search.** Four bounded, phase-indexed joint-equivalent contraction synergies adjust hip flexion, knee flexion, spine flexion, and shoulder flexion through the existing crouch, flight, and landing correction springs. Their bounds are 0.6, 0.6, 0.4, and 0.6 radians. Eight latch, landing-duration, gain, and balance parameters are also searched. The objective includes six-second recovery, legality, distance at three seconds, and impact penalties.

**Jump, temporal residual.** The same bounded synergies are driven by the causal temporal readout using measured contraction derivatives plus COM height, forward/vertical velocity, trunk pitch/rate, and motion phase. The launch keyframes and reflex architecture remain explicit. The zero head reproduces the starting jump exactly; ES learns the correction coefficients and the identical eight backbone parameters.

**Bat, pure search.** Phase-indexed residual contraction targets adjust spine rotation/flexion and bilateral elbow/wrist flexion through the existing aiming springs, with bounds 0.16, 0.16, 0.20, and 0.20 radians. The eight shared timing/gain parameters cover trigger, segment delays, whip/drive timing, and arm/wrist gains. Training uses bat speed at contact, a small ball-quality term, and impact penalties. The arena's athlete body is retained; its strength is not comparable to the normal-strength human-body trial.

**Bat, temporal residual.** The same targets use temporal muscle-state features plus predicted time and location of contact, trunk pitch/rate, and phase. Explicit via keyframes and the existing feed-forward swing remain the backbone. This challenger targets power; neither a command-smoothness score nor more bat speed will be described as proof that the measured hitch is fixed.

**Crossover, pure search.** Phase-indexed arm-only residual synergies adjust shoulder flexion/abduction, elbow flexion, and wrist flexion through the existing hand correction spring. Bounds are 0.18, 0.18, 0.25, and 0.18 radians. Eight shared crossover, catch, recovery, and pump parameters are tuned. The underlying champion still has a trunk pump and paddle hands; this is not a claim of a complete fingers-and-elbow technique.

**Crossover, temporal residual.** The same bounded arm corrections use recent measured muscle derivatives and ball position/velocity. The original crossover, catch, and recovery chunks remain explicit. Its readout can react to different ball trajectories during the same movement phase. A separate zero-readout ablation holds the candidate's tuned backbone fixed, and a bias-only ablation removes temporal dependence.

## Round 1 results

Arena comparisons below use the original champion for both entrants. A failed guard is scored as -1e9, so large paired differences are **guard-coded scores, not metres**. The tables retain the arena's exact decision rule. Its p values use 4,000 sampled sign flips; a reported zero means no sampled permutation was as favorable, not a mathematical zero. These are unadjusted per-trial decisions for fixed candidates, from one optimizer seed per challenger.

| Trial | Challenger | Valid / total | Mean on valid starts | Paired difference | p | Verdict |
|---|---|---:|---:|---:|---:|---|
| search_jump_legal | pure | 8/8 | 1.2830 | +0.0165 | 0.19425 | LOSE |
| search_jump_legal | tcn | 8/8 | 1.2325 | -0.034 | 0.88475 | LOSE |
| search_jump_robust_legal | pure | 30/32 | 1.2615 | -3.125e+07 | 0.56575 | LOSE |
| search_jump_robust_legal | tcn | 25/32 | 1.2095 | -1.875e+08 | 1.00000 | LOSE |
| gpt_jump_stable6 | pure | 0/32 | — | +0 | 1.00000 | LOSE |
| gpt_jump_stable6 | tcn | 9/32 | 1.1904 | +2.8125e+08 | 0.00200 | WIN |
| bat_power | pure | 18/18 | 14.7206 | +1.55722 | 0 (0/4000 sampled flips) | WIN |
| bat_power | tcn | 18/18 | 13.9206 | +0.757222 | 0 (0/4000 sampled flips) | WIN |
| dribble_crossover_25 | pure | 25/25 | 4.6800 | +0.96 | 0.00025 | WIN |
| dribble_crossover_25 | tcn | 25/25 | 7.5200 | +3.8 | 0 (0/4000 sampled flips) | WIN |

### Fresh validation and attribution

The zero-readout ablation retains all tuned backbone parameters. The bias-only ablation additionally retains constant learned offsets but removes temporal dependence. These checks use 24 validation starts and do not enter the arena.

**Jump**

| Controller | Fresh result |
|---|---|
| pure_baseline | 0/24 legal six-second landings; mean legal mark — |
| pure_candidate | 0/24 legal six-second landings; mean legal mark — |
| tcn_candidate | 5/24 legal six-second landings; mean legal mark 1.218 m |
| tcn_bias_only | 5/24 legal six-second landings; mean legal mark 1.180 m |
| tcn_zero_head | 0/24 legal six-second landings; mean legal mark — |

Learned outputs (hip / knee / spine / shoulder flexion): sampled peak degrees **2.37 / 3.16 / 1.96 / 3.89**; RMS degrees **1.21 / 2.04 / 1.24 / 2.89**. These are requested joint-equivalent offsets logged at 10 Hz, before geometry conversion, chunk masks, and spring filtering; they are not raw activations or an exact maximum of the continuous motion.

Full-rollout force telemetry, original → learned: mean peak **6.06 → 6.54 body weights**; mean peak loading rate **1777 → 1865 BW/s**. The learned controller's largest peak on validation was 7.11 BW.

**Bat**

| Controller | Fresh result |
|---|---|
| pure_baseline | power 12.682 m/s; ball quality 0.171 |
| pure_candidate | power 14.705 m/s; ball quality 0.168 |
| tcn_candidate | power 13.357 m/s; ball quality 0.191 |
| tcn_bias_only | power 13.362 m/s; ball quality 0.295 |
| tcn_zero_head | power 13.233 m/s; ball quality 0.198 |

Learned outputs (spine rotation / spine flexion / elbow / wrist flexion): sampled peak degrees **3.73 / 0.98 / 1.77 / 1.33**; RMS degrees **3.23 / 0.49 / 1.44 / 0.93**. These are requested joint-equivalent offsets logged at 10 Hz, before geometry conversion, chunk masks, and spring filtering; they are not raw activations or an exact maximum of the continuous motion.

Full-rollout force telemetry, original → learned: mean peak **3.58 → 3.58 body weights**; mean peak loading rate **5111 → 5127 BW/s**. The learned controller's largest peak on validation was 3.58 BW.

**Dribble**

| Controller | Fresh result |
|---|---|
| pure_baseline | 3.750 successful crossovers per 15 s |
| pure_candidate | 4.417 successful crossovers per 15 s |
| tcn_candidate | 7.708 successful crossovers per 15 s |
| tcn_bias_only | 5.042 successful crossovers per 15 s |
| tcn_zero_head | 3.792 successful crossovers per 15 s |

Learned outputs (shoulder flexion / shoulder abduction / elbow / wrist flexion): sampled peak degrees **1.93 / 0.69 / 0.87 / 0.80**; RMS degrees **1.29 / 0.43 / 0.61 / 0.73**. These are requested joint-equivalent offsets logged at 10 Hz, before geometry conversion, chunk masks, and spring filtering; they are not raw activations or an exact maximum of the continuous motion.

Full-rollout force telemetry, original → learned: mean peak **1.87 → 1.90 body weights**; mean peak loading rate **378 → 397 BW/s**. The learned controller's largest peak on validation was 2.68 BW.

### Twelve-second jump observation

- baseline: 0/8 legal at twelve seconds.
- pure: 0/8 legal at twelve seconds.
- tcn: 3/8 legal at twelve seconds.

### Budget accounting

| Problem | Pure rollout budget / wall seconds | TCN rollout budget / wall seconds |
|---|---:|---:|
| jump | 1536 / 366.0 | 1536 / 416.2 |
| bat | 512 / 1053.5 | 512 / 1129.9 |
| dribble | 512 / 6318.4 | 512 / 805.6 |

Training wall times include shared-machine contention. The pure crossover run also contains a 5,436-second gap between two generations (see `wall_clock_anomaly.json`); its cause is not established. Wall time is not a compute-speed comparison. Validation, ablations, rechecks, rendering and arena entries are additional evaluations, excluded from both matched training budgets.

### Learned versus pure: direct arena comparisons

| Trial | TCN minus pure, guard-coded where applicable | p | TCN wins the same arena test |
|---|---:|---:|---|
| search_jump_legal | -0.0505 | 0.94250 | False |
| search_jump_robust_legal | -1.5625e+08 | 0.99275 | False |
| gpt_jump_stable6 | +2.8125e+08 | 0.00200 | True |
| bat_power | -0.8 | 1.00000 | False |
| dribble_crossover_25 | +2.84 | 0.00000 | True |

The fixed convolution filters and small learned readout limit this experiment: it does not test end-to-end convolution training, larger neural policies, or performance outside the evaluated tasks and seed distributions.

## Reproduction and evidence

- `playground/gpt_competitor.py`: equal-budget training, fresh validation, exact zero-residual parity, GRF/loading telemetry and traces.
- `playground/gpt_arena_entry.py`: unmodified arena judge plus saved per-seed evidence.
- `playground/gpt_ablate.py`: remove the learned readout while retaining tuned backbone parameters.
- `playground/gpt_render.py`: render a frozen controller on an exact arena seed.
- `playground/gpt_integration.py`: assert nonzero residuals affect commands and measured motion for every challenger.
- `playground/gpt_audit.py`: verify frozen artifacts, inherited files, trial preservation, budgets, parity, and integration evidence.
- `spec/gpt_residual_spec.w`: zero initialization, hard output bounds, temporal dependence, and sample clock.
- `out/competitor_20260927/protocol.json`, `baseline_files.json`, `champions_before.json`, and `frozen_manifest.json`: provenance.
- `params/competitor_20260927/`: full-precision learned parameters and search baselines.
- `out/competitor_20260927/`: complete curves, evaluated candidate archives, training summaries, validation rows and traces.

Example:

```sh
.venv/bin/python playground/gpt_competitor.py train jump tcn --budget 1536 --seeds 8 --sigma 0.025
.venv/bin/python playground/gpt_competitor.py validate jump tcn
.venv/bin/python playground/gpt_arena_entry.py --artifact out/competitor_20260927/example.json eval search_jump_legal \
  --params params/competitor_20260927/jump_tcn.txt --controller bin/challengers/gpt-jump-tcn --note 'gpt: temporal residual' --workers 3
```

## Failure modes and whole-motion inspection

**Jump.** The temporal candidate loses both existing jump-distance trials. The new six-second trial records partial recovery, with only 9/32 legal starts. Fresh success is 5/24 for both temporal and bias-only residuals, but just one successful seed overlaps: temporal feedback changes which starts recover without demonstrating a higher recovery rate. Twelve-second diagnostics cover eight fresh starts, so they establish finite examples rather than robust sustained balance. The temporal candidate also increases mean peak landing force and loading rate despite the training penalty.

**Bat.** The arena improvement is in contact speed. The original whole-sequence `hitch_full` metric is computed from commanded contractions; it is not a measured-joint smoothness certificate. Fresh means are:

| Controller | Command-based hitch_full (lower better) |
|---|---:|
| pure_baseline | 0.2453 |
| pure_candidate | 0.2597 |
| tcn_candidate | 0.2404 |
| tcn_bias_only | 0.2360 |

Measured joint traces cover the full 0–7.799 s rollout on fresh seed 271001. During the explicitly marked leg-lift-to-finish interval, the longest quiet spans (RMS angular speed below 0.1 rad/s, approximately 10 ms sampling) are:

| Controller | Arms quiet ms | Trunk quiet ms | Front hip quiet ms during lift | Front knee quiet ms during lift | Plant-to-swing ms |
|---|---:|---:|---:|---:|---:|
| pure_baseline | 99.0 | 79.2 | 39.6 | 39.6 | 155.0 |
| pure_candidate | 99.0 | 79.2 | 39.6 | 39.6 | 145.0 |
| tcn_candidate | 99.0 | 79.2 | 39.6 | 39.6 | 155.0 |
| tcn_bias_only | 99.0 | 79.2 | 39.6 | 39.6 | 155.0 |
| tcn_zero_head | 99.0 | 79.2 | 39.6 | 39.6 | 155.0 |

The diagnostic JSON also records the longest quiet intervals, total joint travel and peak measured speed across the entire visible rollout, including the initial setup and final reset. These threshold measurements are descriptive and do not establish perceptual smoothness. The unchanged quiet spans and full video prevent a claim that either batter challenger fixed the hitch.

**Later saved-motion diagnosis (no new rollouts).** Baseline, pure, temporal, bias-only and zero-head trajectories on consumed seed 271001 are byte-identical before pitch release at 2.9 s: 580 control samples and 291 sampled joint-position states. The private residual is added through the aiming correction, which remains disabled until pitch aiming starts; it therefore cannot affect the checked earlier stride pause. A future hitch experiment needs bounded preparatory motion before that gate. This is a limitation of this integration, not of temporal models generally. [Saved diagnosis](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_bat_diagnosis/REPORT.md) and [pinned evidence](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_bat_diagnosis/evidence.json).

**Crossover.** All full 15-second rollouts are retained, including motion after loss of control. Fresh-seed failure observations:

| Controller | Mean controlled seconds | Mean successful crossovers | Mean ball/body contacts | Runs with recorded ball loss | Mean trunk share of upper-body activation |
|---|---:|---:|---:|---:|---:|
| pure_baseline | 3.73 | 3.750 | 0.125 | 24/24 | 11.7% |
| pure_candidate | 4.02 | 4.417 | 0.000 | 24/24 | 12.1% |
| tcn_candidate | 6.22 | 7.708 | 0.292 | 24/24 | 11.6% |
| tcn_bias_only | 4.60 | 5.042 | 1.708 | 24/24 | 11.6% |

The correction itself uses only arm joints, but the backbone retains its trunk pump. The body retains paddle hands; this campaign does not provide articulated-finger technique or an arms-only solution. A higher crossover count must not be read as continuous control for the entire 15 seconds.

## Promoted champions and videos

Promotions below were made only by `arena.py eval --promote` in this isolated worktree. Their frozen binary and parameter files are checked byte-for-byte against the selected challengers. The original checkout's board is unchanged. Videos use declared arena seeds and show the full trial; the jump is extended to twelve seconds. Visual inspection shows that its representative six-second passing start falls backward around seven seconds. The separate failure example falls earlier. The crossover video shows eight completed transfers before ball control is lost; its remaining motion is retained. The batter video includes the setup, swing, follow-through, and reset.

- **bat_power — pure**, seed 16: [video](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_20260927/video_bat_power_pure.mp4); [contact sheet](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_20260927/video_bat_power_pure_sheet.png); [frozen parameters](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/playground/arena/params/bat_power-20260927-190350.txt).
- **dribble_crossover_25 — tcn**, seed 404: [video](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_20260927/video_dribble_crossover_25_tcn.mp4); [contact sheet](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_20260927/video_dribble_crossover_25_tcn_sheet.png); [frozen parameters](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/playground/arena/params/dribble_crossover_25-20260927-190424.txt).
- **gpt_jump_stable6 — tcn**, seed 272024: [video](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_20260927/video_gpt_jump_stable6_tcn.mp4); [contact sheet](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_20260927/video_gpt_jump_stable6_tcn_sheet.png); [frozen parameters](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/playground/arena/params/gpt_jump_stable6-20260927-190440.txt).
  Failure example, seed 272001: [full video](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_20260927/video_gpt_jump_stable6_tcn_failure.mp4).

## Round 1 conclusion

The temporal residual is most convincing for crossovers: it beats pure search by 2.84 completed crossovers in the arena, and its fresh-seed score falls from 7.708 to 5.042 when temporal features are removed and to 3.792 when the entire readout is removed. Pure search is better for batting by 0.80 m/s in the arena; the temporal batter performs almost identically with bias only. Jump residuals enable some six-second recovery, but constant offsets match their fresh success count, and neither challenger beats the existing distance trials. These results support bounded temporal feedback for the crossover task and retain explicit keyframes as the effective backbone. They do not establish a general advantage for learned residuals.

The comparison covers one optimizer seed per challenger and these task/seed distributions. Only the zero-initialized readout is trained over fixed convolution filters; this is not an end-to-end TCN training study. All arena verdicts, including losses, are above. No shared SDK changes or commits were made.

## Round 1 verification

The provenance audit passes for 682 inherited files, with no unexpected changes and no frozen artifact drift. All six zero-head parity checks and all six nonzero integration checks pass. The residual spec passes 50 checks. Existing trials are byte-identical after removing the additive trial. Validation and ablations recorded no simulator errors. All three promoted frozen champions reproduce their stored per-seed scores exactly (`out/competitor_20260927/recheck_promoted.log`). All four videos decode successfully and cover their full simulation horizons (`video_audit.json`). Active crossover binaries are `bin/challengers/gpt-dribble-pure-v2` and `bin/challengers/gpt-dribble-tcn-v2`; the earlier binaries are retained only as provenance.

## Round 2: recovery and the original jump trials

The first continuation focused on the unbeaten original standing-jump trials. On new training start 273101, the original flight phase continued until 2.424 s. Raising the touchdown COM threshold from 0.478 to 0.85 m moved landing to 1.672 s. That alone still failed every eight-second probe. Positive capture-point feedback plus the existing rise-to-crouch keyframe moved the next transition to 1.972 s and kept 7/8 probe starts legal for eight seconds.

**Recovery pure search.** The explicit original take-off contraction keyframes are followed by the earlier sensed landing and a balanced-crouch target. Phase-indexed bounded hip, knee, spine, and shoulder offsets are searched along with twelve launch, landing, and standing parameters. This is the same private controller implementation in a new frozen binary copy, with the opt-in recovery phase enabled. No shared SDK, task, body, or existing trial changes are involved.

**Recovery temporal residual.** The same backbone uses the existing causal convolution features of contractions, velocities, acceleration, jerk, and sensors. Its twenty output weights start at zero; ES trains those weights and the identical twelve backbone parameters. The four offsets remain bounded at 0.6/0.6/0.4/0.6 rad and pass through geometry conversion and correction springs. Convolution filters remain fixed.

Both searches use 2,048 rollouts, eight training starts 273101–273108, optimizer seed 270929, initial normalized sigma 0.015, and the same risk-0.5 aggregation. The objective rewards legal distance at both three and eight seconds and includes the same impact/loading penalty. The preceding 64 diagnostic rollouts are additional shared setup work. Validation uses 32 fresh starts 274101–274132; longer checks use the first eight of those starts for twenty seconds.

### Arena verdicts

Each candidate was entered before any second-round promotion, against the round-start champions. Failed guards score -1e9; large differences below are guard-coded scores, not metres. The unchanged arena samples 4,000 sign flips, so a sampled p of zero is not an exact mathematical zero.

| Trial | Candidate | Valid starts | Mean valid mark, m | Paired difference | p | Verdict |
|---|---|---:|---:|---:|---:|---|
| search_jump_legal | pure | 8/8 | 1.3020 | +0.0355 | 0.00800 | WIN |
| search_jump_legal | tcn | 8/8 | 1.3630 | +0.0965 | 0.00375 | WIN |
| search_jump_robust_legal | pure | 31/32 | 1.2891 | +0.0375312 | 0.25825 | LOSE |
| search_jump_robust_legal | tcn | 29/32 | 1.3523 | -6.25e+07 | 0.68450 | LOSE |
| gpt_jump_stable6 | pure | 21/32 | 1.2781 | +3.75e+08 | 0.00125 | WIN |
| gpt_jump_stable6 | tcn | 26/32 | 1.3517 | +5.3125e+08 | 0.00000 | WIN |

### Fresh validation and attribution

| Controller | Legal at 3 s | Mean legal mark at 3 s | Legal at 8 s | Mean legal mark at 8 s | Mean peak GRF, BW | Mean peak loading, BW/s |
|---|---:|---:|---:|---:|---:|---:|
| original | 30/32 | 1.238 | 0/32 | — | 5.97 | 1775 |
| pure_start | 32/32 | 1.194 | 28/32 | 1.169 | 5.55 | 1605 |
| pure_candidate | 29/32 | 1.288 | 19/32 | 1.275 | 5.43 | 1478 |
| tcn_candidate | 29/32 | 1.348 | 24/32 | 1.349 | 5.81 | 1404 |
| tcn_bias_only | 20/32 | 1.325 | 10/32 | 1.329 | 5.93 | 1426 |
| tcn_zero_head | 22/32 | 1.225 | 15/32 | 1.180 | 5.31 | 1492 |

Twenty-second legality: pure **3/8**, temporal **6/8**. These are finite checks, not a guarantee of indefinite balance.

Temporal output magnitude, hip / knee / spine / shoulder: sampled peak **5.24 / 9.50 / 2.04 / 7.72 degrees**; full-rollout RMS **4.17 / 7.06 / 1.30 / 6.73 degrees**. These are requested joint-equivalent offsets sampled at 10 Hz before geometry and spring filtering. Zero-head and bias-only rows retain the tuned backbone, isolating the residual and its time dependence.

### Direct temporal-versus-pure arena comparison

| Trial | TCN minus pure | p | TCN wins |
|---|---:|---:|---|
| search_jump_legal | +0.061 | 0.00375 | True |
| search_jump_robust_legal | -6.25e+07 | 0.74775 | False |
| gpt_jump_stable6 | +1.5625e+08 | 0.04450 | True |

### New champion videos

Each video shows twenty seconds on the declared arena seed, including the motion after the scoring horizon.

- **search_jump_legal**, tcn, seed 102: [full video](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round2/video_search_jump_legal_tcn.mp4); [contact sheet](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round2/video_search_jump_legal_tcn_sheet.png).
- **gpt_jump_stable6**, tcn, seed 272006: [full video](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round2/video_gpt_jump_stable6_tcn.mp4); [contact sheet](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round2/video_gpt_jump_stable6_tcn_sheet.png).

The original six-challenger evidence remains in `out/competitor_20260927`. This continuation has its own protocols, frozen hashes, diagnostic probes, complete search archives, fresh validation, ablations, arena rows, and long-horizon traces in `out/competitor_jump_round2`.

## Round 3: closing the original robustness gap

**Stability pure search.** Keep the round-2 phase-indexed residual, launch keyframes, and learned parameters fixed. Search only the delay before the balanced-crouch keyframe and its standing feedback gain. The selected delay is 0.18 s and gain is 0.6. This improves recovery by changing the explicit chunk timing and balance feedback, without further fitting the residual weights.

**Stability temporal residual.** Keep the round-2 causal-convolution readout and launch parameters fixed and search the same two recovery parameters. The selected delay is 0.18 s and gain is 1.0. It retains temporal feedback learned in round 2; no neural weights are retrained in this grid. Both controllers are new frozen copies under `bin/challengers/gpt-jump-stable-{pure,tcn}`.

Each family receives **544 full eight-second training rollouts**: its unchanged round-2 candidate plus a 4×4 recovery grid, evaluated on 32 new starts 275101–275132. Selection ranks the number legal at eight seconds, then the number legal at three seconds, then distance minus the same impact/loading penalty. This fixed bounded grid does not adapt to validation or arena scores. Validation uses **64 new starts 276101–276164**; twenty-second checks use the first eight. These seed sets are disjoint from all earlier training, validation, and arena starts.

### Arena verdicts

Both candidates entered all three trials before any round-3 promotion. The distance and six-second comparators are the round-2 champions; the robustness comparator is the original champion. Failed guards still score -1e9. Thus the robustness paired difference includes removal of one guard failure and must not be read as a distance gain in metres.

| Trial | Candidate | Valid starts | Mean legal mark, m | Paired difference | p | Verdict |
|---|---|---:|---:|---:|---:|---|
| search_jump_legal | pure | 8/8 | 1.2913 | -0.07175 | 1.00000 | LOSE |
| search_jump_legal | tcn | 8/8 | 1.2928 | -0.07025 | 1.00000 | LOSE |
| search_jump_robust_legal | pure | 32/32 | 1.2696 | +31250000.1 | 0.00075 | WIN |
| search_jump_robust_legal | tcn | 32/32 | 1.2722 | +31250000.1 | 0.00000 | WIN |
| gpt_jump_stable6 | pure | 28/32 | 1.2741 | +62500000 | 0.34150 | LOSE |
| gpt_jump_stable6 | tcn | 27/32 | 1.2735 | +31250000 | 0.50175 | LOSE |

The temporal challenger was promoted for robustness because both beat the incumbent and it had the higher mean. Its direct advantage over pure search is **0.00259375 m, p = 0.2445**; this does not establish temporal superiority on robustness. Neither grid candidate replaces the 1.363 m distance champion or the existing six-second champion. A displayed p = 0 means 0/4,000 sampled sign flips, not an exact zero.

### Fresh validation and attribution

A reporting audit caught a reference error in the first round-3 original-controller diagnostic: it loaded the round-2 champion and forced pure mode. Those invalid files are preserved, and this table uses a corrected 64-start replay pinned to the round-1 frozen original. This correction changes only the baseline diagnostic, not search, candidate validation, endurance, or arena evidence. Round-2 original identity was also checked and was correct. Provenance is in `original_pinned_provenance.json`.

| Controller | Legal at 3 s | Mean legal mark at 3 s | Legal at 8 s | Mean legal mark at 8 s | Mean peak GRF, BW | Mean peak loading, BW/s |
|---|---:|---:|---:|---:|---:|---:|
| original | 64/64 | 1.2507 | 0/64 | — | 5.98 | 1779 |
| pure_previous | 62/64 | 1.2890 | 54/64 | 1.2799 | 5.37 | 1465 |
| pure_candidate | 64/64 | 1.2741 | 60/64 | 1.2753 | 5.37 | 1465 |
| tcn_previous | 62/64 | 1.3539 | 54/64 | 1.3559 | 5.72 | 1394 |
| tcn_candidate | 63/64 | 1.2794 | 56/64 | 1.2818 | 5.72 | 1394 |
| tcn_bias_only | 64/64 | 1.1759 | 41/64 | 1.1783 | 5.95 | 1399 |
| tcn_zero_head | 52/64 | 1.2277 | 21/64 | 1.1841 | 5.41 | 1549 |

Twenty-second legality is **8/8 pure and 8/8 temporal**. The 64-start eight-second check still has **4 pure and 8 temporal failures**. Every candidate failure is flagged `fallen`; there are no fouls or inversions. This flag includes a final pelvis below 0.5 m as well as non-foot ground contact. Passing eight twenty-second starts is finite evidence, not a balance guarantee.

Temporal outputs, hip / knee / spine / shoulder: sampled peak **5.22 / 9.49 / 1.99 / 7.72 degrees**; full-rollout RMS **4.27 / 7.14 / 1.33 / 6.71 degrees**. These are 10 Hz joint-equivalent requests before geometry conversion, chunk masks, and springs. The weights are unchanged from round 2; changed sensor trajectories alter their outputs. Removing the entire head reduces eight-second legality from 56/64 to 21/64; retaining only bias gives 41/64. These are matched ablations with the same tuned backbone. The complete controller still does not outperform pure search in fresh eight-second success count (56/64 versus 60/64).

### Direct temporal-versus-pure arena comparison

| Trial | TCN minus pure | p | TCN wins |
|---|---:|---:|---|
| search_jump_legal | +0.0015 | 0.37475 | False |
| search_jump_robust_legal | +0.00259375 | 0.24450 | False |
| gpt_jump_stable6 | -31250000 | 0.72175 | False |

### New champion video

- **search_jump_robust_legal**, temporal, seed 3024: [twenty-second video](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round3/video_search_jump_robust_legal_tcn.mp4); [contact sheet](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round3/video_search_jump_robust_legal_tcn_sheet.png). The landing settles into a crouch, with legal posture through the end of the visible motion.

## Rounds 1–3 completion checks

The final audit rechecked hashes for 682 inherited files and all round-1, round-2, and round-3 frozen manifests. Shared SDK, original controllers, task physics, bridges, and arena implementation have no unexpected changes. Original trials are byte-identical after removing the one additive trial. No commits or tracked edits were made; all promotions are local to this worktree.

All matched training budgets and private seed separation checks pass. Round-2 zero-head pure and temporal traces are exactly equal in commanded contractions, measured contractions, activations, and joint positions. Nonzero temporal effects reach measured motion in both later rounds. The earlier six integration checks and 50-check compiled residual spec remain valid for the unchanged code. No new training, validation, ablation, or arena artifacts contain simulation errors or nonfinite values.

All twelve round-2/3 arena verdicts were independently recomputed with the unchanged arena comparison. Every promoted binary and parameter copy matches its evaluated candidate. The three current jump champions replay their stored per-seed scores exactly; the unchanged bat and crossover champions passed their earlier replay. All three later champion videos were fully decoded at 30 fps, 800×448, and cover their complete twenty-second rollouts. Earlier videos and failures are retained in the round-1 section.

Machine-readable evidence: [completion audit](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round3/completion_audit.json), [champion replay](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round3/recheck_final.log), [video audit](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round3/video_audit.json), [round-3 summary](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round3/summary.json).

The three research problems now each have two genuinely different evaluated challenger families and at least one win on an existing arena trial. The robustness win is on the original 32-start trial; the added six-second diagnostic is additional evidence. These remain local simulator results. Repeated rounds and comparisons use the arena’s unadjusted rule, so this campaign is exploratory evidence rather than a multiple-testing-adjusted statistical claim.

## Rounds 1–3 learned-residual versus pure-search comparison

**Crossovers provide the clearest temporal benefit.** The learned candidate scores 7.52 versus pure search’s 4.68 in the arena, a +2.84 paired gain with no as-favorable result in 4,000 sampled sign flips. Fresh mean crossovers fall from 7.708 to 5.042 with bias only and to 3.792 with zero head. Control is still eventually lost, and the inherited trunk pump and paddle hands do not satisfy the broader arms-only/finger technique request.

**Pure search remains better for batting.** It reaches 14.7206 m/s versus temporal 13.9206 m/s on the same 18 arena pitches. The temporal ablation is almost unchanged with bias only; learned time dependence has not shown useful value here. Full measured-joint diagnostics still show the hitch. More contact speed does not mean smoother technique.

**Jump benefits from the explicit recovery mechanism and can benefit from temporal residuals.** Round-2 temporal distance beats pure by 0.061 m (p = 0.00375) and beats the original champion by 0.0965 m. The final stability versions both beat the original robustness champion with 32/32 legal starts, while temporal versus pure is inconclusive (p = 0.2445), and pure has fewer fresh eight-second failures. Earlier touchdown and a balanced-crouch chunk account for an essential part of the improvement. Zero-head/bias ablations show that the trained temporal head contributes to recovery, but do not support a universal advantage over pure search. Only the readout is trained; convolution filters stay fixed throughout.

## Main-arena cross-evaluation after the original campaign

These are the main agent’s recorded arena decisions, separately from this worktree’s original campaign. The main board has continued to change after these entries.

| Trial | Challenger result | Paired difference in arena orientation | p | Decision |
|---|---:|---:|---:|---|
| search_jump_legal | 1.363 | +0.033625 | 0.00375 | promoted |
| search_jump_robust_legal | -93749999 | -93750000 | 0.87625 | lose |
| bat_power | 14.720556 | +0.94 | 0.00000 | promoted |
| bat_flow | 7.3250889 | -5.2775611 | 1.00000 | lose |
| dribble_crossover_25 | 7.52 | +3.8 | 0.00000 | promoted |
| dribble_crossover | 7.3 | +3.6 | 0.00225 | promoted |
| dribble_arms_only | 0.7345 | -0.5522 | 0.99475 | lose |
| bat_power_fresh | 14.78875 | +0.92458333 | 0.00000 | promoted |
| bat_power_fresh_clean | -1e+09 | -1e+09 | 1.00000 | lose |

Guard failures score -1e9; guard-scored differences are not physical distances or speeds. For lower-is-better trials, the paired comparison reverses the raw metric direction. A sampled p of zero means 0/4,000 sampled sign flips, not an exact zero.

Training-provenance correction: the independent pure batter used four fixed continuous randomized training pitches and 24 different validation pitches. It did not train on the arena’s 18-pitch grid. Main’s later note is inaccurate on that point; the saved source retains it for audit.

The main-arena technique checks confirm the limitations: bat flow 7.3251 loses to 2.0475, and the conditional dribble arms-only score 0.7345 loses to 0.1823. This score is the trunk activation share only when a run completes at least ten dribbles; shorter runs receive 1.0, so the mean is not a raw trunk-activation percentage. The bat-power controller subsequently wins the main fresh-pitch power trial at 14.78875 m/s, but fails its clean-motion variant.

Source: [captured main history and preceding incumbents](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round4/main_cross_evaluations.json). These are recorded cross-evaluations, not a claim to the current main board. Round 4 is complete and reported below.

## Round 4: challenging the current robustness frontier

The main arena advanced after the original campaign. Its P6 temporal-convolution keyframe policy reached 1.31534375 m on all 32 perturbed starts. This continuation pins that frozen champion and requires its exact per-seed replay before any comparison. The main agent’s separately recorded cross-evaluations are preserved in `out/competitor_jump_round4/MAIN_CROSS_EVALUATION.md`.

**General-recovery pure search.** Start from the round-3 phase-indexed controller, keep its residual weights and contraction keyframe vectors fixed, and tune sixteen explicit launch, balanced-crouch, timing, and landing-feedback parameters. The score heavily penalizes losing legality at either three or eight seconds, then rewards distance and penalizes impact/loading.

**General-recovery temporal.** Start from the round-3 learned temporal controller and search the same sixteen explicit parameters under the identical new budget. The inherited twenty readout weights are frozen in this continuation; it is a refinement of a previously learned policy, not new neural training or a common-initialization comparison. Convolution filters remain fixed.

Each family receives **3,072 rollouts**, 16 new training starts 277101–277116, optimizer seed 280928, normalized sigma 0.012, and risk-0.5 (1+1)-ES. Fresh validation uses 64 new starts 278101–278164. The cumulative accepted jump-search budget is now 7,200 rollouts per family, plus the separately disclosed shared probes and validation. P6 has its own training history, so the incumbent comparison is not an equal-compute architecture experiment.

### Arena outcomes against both boards

All six entries precede any round-4 promotion. Promotion requires beating both the worktree incumbent and the recorded main incumbent, where one exists. The six-second trial belongs only to this worktree. Large paired differences are guard-scored values, not metres.

| Trial | Family | Valid | Mean valid mark, m | Local paired diff | Local p | Local verdict | Main paired diff | Main p | Main verdict |
|---|---|---:|---:|---:|---:|---|---:|---:|---|
| search_jump_legal | pure | 8/8 | 1.3141 | -0.048875 | 1.00000 | LOSE | -0.048875 | 1.00000 | LOSE |
| search_jump_legal | tcn | 8/8 | 1.2756 | -0.087375 | 1.00000 | LOSE | -0.087375 | 1.00000 | LOSE |
| search_jump_robust_legal | pure | 32/32 | 1.2820 | +0.00984375 | 0.20450 | LOSE | -0.0333125 | 0.99775 | LOSE |
| search_jump_robust_legal | tcn | 32/32 | 1.2881 | +0.01590625 | 0.01925 | WIN | -0.02725 | 1.00000 | LOSE |
| gpt_jump_stable6 | pure | 28/32 | 1.2997 | +62500000 | 0.32950 | LOSE | — | — | — |
| gpt_jump_stable6 | tcn | 31/32 | 1.2872 | +156250000 | 0.03050 | WIN | — | — | — |

### Fresh validation and residual attribution

| Controller | Legal at 3 s | Mean legal mark, m | Legal at 8 s | Mean legal mark, m | Peak force, BW | Peak loading, BW/s |
|---|---:|---:|---:|---:|---:|---:|
| p6 | 64/64 | 1.3254 | 0/64 | — | 6.42 | 1865 |
| pure_previous | 64/64 | 1.2822 | 60/64 | 1.2846 | 5.39 | 1468 |
| pure_candidate | 64/64 | 1.2994 | 59/64 | 1.2978 | 5.46 | 1475 |
| tcn_previous | 64/64 | 1.2821 | 59/64 | 1.2848 | 5.70 | 1392 |
| tcn_candidate | 64/64 | 1.2831 | 60/64 | 1.2868 | 5.67 | 1396 |
| tcn_bias_only | 64/64 | 1.2337 | 63/64 | 1.2337 | 5.73 | 1412 |
| tcn_zero_head | 43/64 | 1.2198 | 12/64 | 1.1694 | 5.43 | 1502 |

Twenty-second legality: pure **6/8**, temporal **8/8**. These remain finite tests. The table reports conditional means on legal starts; failures remain in the arena's guard-coded decision.

Temporal hip / knee / spine / shoulder output magnitudes: sampled peak **5.17 / 9.37 / 2.05 / 7.72 degrees**; full-rollout RMS **4.32 / 7.23 / 1.36 / 6.70 degrees**. These 10 Hz samples precede geometry conversion, chunk masks, and springs. Output differences from round 3 reflect changed trajectories with the same frozen readout.

### Temporal versus pure on identical arena starts

| Trial | TCN minus pure | p | TCN wins |
|---|---:|---:|---|
| search_jump_legal | -0.0385 | 1.00000 | False |
| search_jump_robust_legal | +0.0060625 | 0.25250 | False |
| gpt_jump_stable6 | +93750000.1 | 0.12775 | False |

### Promoted motion and checks

- **gpt_jump_stable6**, tcn, seed 272029: [twenty-second video](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round4/video_gpt_jump_stable6_tcn.mp4) and [contact sheet](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round4/video_gpt_jump_stable6_tcn_sheet.png). Legal at the end of this video: **True**.

All 27 round-4 audit checks pass: [audit](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round4/audit.json), [complete summary](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round4/summary.json), [P6 exact replay](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round4/p6_arena_replay.json). No shared SDK or existing trial changes, no commits, and no edits to the main board. Any remaining fresh-start or twenty-second failures are reported above and prevent claims of universal recovery.

### Round-4 interpretation and remaining failures

The temporal controller wins the existing local six-second diagnostic with **31/32 legal starts versus 26/32**, p = **0.0305**. Its mean valid mark is lower (1.2872 m versus 1.3517 m), so this is a recovery win rather than a distance win. It also beats the older worktree robustness incumbent, but **neither family beats P6**; the stronger-frontier gate correctly prevents a robustness promotion. P6 remains ahead by 2.73 cm versus temporal and 3.33 cm versus pure on the 32 arena starts, while P6 fails all 64 fresh eight-second checks.

Fresh eight-second failures are five pure and four temporal runs, all flagged `fallen`, with no fouls or inversions. The pure failures are seeds 278102, 278105, 278138, 278143, and 278148; temporal failures are 278145, 278157, 278159, and 278161. As before, `fallen` includes either non-foot ground contact or a final pelvis below 0.5 m. Pure loses two of the eight twenty-second checks; temporal passes all eight. The new champion video, seed 272029, visibly settles into a crouch and stays balanced through twenty seconds; its decoded metadata and final legal flags agree.

## Updated learned-residual versus pure-search comparison

The earlier conclusions for crossovers and batting remain unchanged: temporal feedback provides the clearest crossover gain, while pure search produces the stronger batter and neither repairs the measured hitch. The new main-arena tests confirm the bat-flow and arms-only limitations.

For jumping, the frozen temporal head still matters: removing it reduces fresh eight-second legality from **60/64 to 12/64**. Bias-only achieves **63/64**, however, while shortening the mean legal three-second mark from **1.2831 to 1.2337 m**. Time-dependent feedback trades some recovery reliability for distance in this ablation. The complete temporal controller wins the six-second incumbent comparison, but its direct advantage over pure on that trial is inconclusive (**p = 0.12775**); robustness is also inconclusive (**p = 0.2525**), and pure jumps farther on the short distance trial. Round 4 tuned explicit movement parameters with both inherited heads frozen, so it supplies no evidence about learning new convolution filters. The remaining research target is to combine P6-level distance with sustained recovery, not to relabel the old-incumbent win as a frontier win.

## Round 5: conditional landing support

Round 4 improved longer recovery but did not beat the newer P6 robustness champion. This round returns to the longer-distance round-2 policies and changes recovery only when the measured landing warrants it. Launch parameters, explicit contraction keyframes, and inherited residual weights remain frozen.

**Pure search.** Retain the phase-based offset policy. Record the lowest pelvis height during the landing chunk; when it crosses the selected threshold, enter the existing balanced-crouch recovery at the selected time and apply the selected bounded reflex gain. Otherwise, keep the original timing and gain.

**Temporal residual.** Apply the same conditional recovery mechanism to the earlier temporal controller. Its convolution features and twenty learned readout weights stay unchanged; sensor-dependent residuals and the explicit gate affect subsequent motion. This round trains gate parameters, not new neural weights.

The first pilot used predicted torso-angle thresholds that proved too low for the observed body-frame angles: the enabled gate triggered on every start. That negative calibration result is preserved, without arena entry. The second pilot uses the lowest measured landing pelvis height and adjusts both recovery timing and support gain. Both private builds reproduce their previous controller exactly when disabled, across four eight-second parity pairs each.

Each family receives **296 first-pilot rollouts + 368 landing-depth rollouts = 664**, on the same eight private starts 279101–279108, plus eight parity rollouts per family across the two builds. Selection rules were frozen before the second grid: best recovery score, and a distance alternative legal at three seconds on all eight training starts with at least six eight-second successes. Every distinct selected candidate then faces **64 untouched starts 281101–281164**, its static timing/gain counterpart, and temporal bias/zero-head ablations. P6 is a separately trained incumbent, not an equal-compute architecture comparison.

| Candidate | Trigger height, m | Recovery delay, s | Reflex gain | Pilot legal 3 s / 8 s |
|---|---:|---:|---:|---|
| pure_recovery | 0.615 | 0.22 | 1.0 | 8/8 / 8/8 |
| pure_distance | 0.605 | 0.22 | 0.8 | 8/8 / 6/8 |
| tcn_recovery | 0.595 | 0.18 | 1.2 | 8/8 / 7/8 |
| tcn_distance | 0.575 | 0.18 | 1.2 | 8/8 / 6/8 |

### Arena outcomes

All entries precede promotion. Promotion requires a win against both the local and recorded main incumbents wherever both exist. Large guard-scored differences are not metres; a sampled p of zero means zero as-favorable results in 4,000 sampled sign flips. These are unadjusted exploratory comparisons.

| Trial | Candidate | Valid | Mean valid mark, m | Local diff | Local p | Local verdict | Main diff | Main p | Main verdict |
|---|---|---:|---:|---:|---:|---|---:|---:|---|
| search_jump_legal | pure_recovery | 8/8 | 1.28775 | -0.07525 | 1.00000 | LOSE | -0.07525 | 1.00000 | LOSE |
| search_jump_legal | pure_distance | 8/8 | 1.30200 | -0.061 | 1.00000 | LOSE | -0.061 | 1.00000 | LOSE |
| search_jump_legal | tcn_recovery | 8/8 | 1.36300 | +0 | 1.00000 | LOSE | +0 | 1.00000 | LOSE |
| search_jump_legal | tcn_distance | 8/8 | 1.36300 | +0 | 1.00000 | LOSE | +0 | 1.00000 | LOSE |
| search_jump_robust_legal | pure_recovery | 32/32 | 1.25537 | -0.0168125 | 0.94850 | LOSE | -0.05996875 | 1.00000 | LOSE |
| search_jump_robust_legal | pure_distance | 32/32 | 1.28547 | +0.01328125 | 0.00600 | WIN | -0.029875 | 1.00000 | LOSE |
| search_jump_robust_legal | tcn_recovery | 32/32 | 1.31838 | +0.0461875 | 0.00025 | WIN | +0.00303125 | 0.40675 | LOSE |
| search_jump_robust_legal | tcn_distance | 30/32 | 1.34727 | -62500000 | 0.74775 | LOSE | -62500000.1 | 0.74775 | LOSE |
| gpt_jump_stable6 | pure_recovery | 30/32 | 1.23983 | -31250000.1 | 0.99975 | LOSE | — | — | — |
| gpt_jump_stable6 | pure_distance | 21/32 | 1.27810 | -312500000 | 0.99950 | LOSE | — | — | — |
| gpt_jump_stable6 | tcn_recovery | 26/32 | 1.34396 | -156250000 | 0.93950 | LOSE | — | — | — |
| gpt_jump_stable6 | tcn_distance | 26/32 | 1.35173 | -156250000 | 0.96950 | LOSE | — | — | — |

### Fresh validation, static-gate comparison, and head ablations

| Controller | Legal 3 s | Mean legal mark, m | Legal 8 s | Gate triggered | Mean peak force, BW |
|---|---:|---:|---:|---:|---:|
| pure_previous | 62/64 | 1.28758 | 50/64 | 0/64 | 5.41 |
| tcn_previous | 57/64 | 1.35391 | 51/64 | 0/64 | 5.75 |
| pure_recovery | 64/64 | 1.25248 | 62/64 | 18/64 | 5.41 |
| pure_recovery_static | 64/64 | 1.19795 | 62/64 | 0/64 | 5.41 |
| pure_distance | 62/64 | 1.28565 | 51/64 | 4/64 | 5.41 |
| pure_distance_static | 62/64 | 1.24405 | 61/64 | 0/64 | 5.41 |
| tcn_recovery | 64/64 | 1.32583 | 55/64 | 11/64 | 5.75 |
| tcn_recovery_static | 64/64 | 1.24825 | 51/64 | 0/64 | 5.75 |
| tcn_recovery_bias | 64/64 | 1.20331 | 43/64 | 35/64 | 5.94 |
| tcn_recovery_zero | 49/64 | 1.22606 | 22/64 | 0/64 | 5.44 |
| tcn_distance | 61/64 | 1.34205 | 52/64 | 4/64 | 5.75 |
| tcn_distance_static | 64/64 | 1.24825 | 51/64 | 0/64 | 5.75 |
| tcn_distance_bias | 41/64 | 1.30456 | 26/64 | 3/64 | 5.94 |
| tcn_distance_zero | 49/64 | 1.22606 | 22/64 | 0/64 | 5.44 |
| p6_reference | 63/64 | 1.32468 | 0/64 | 0/64 | 6.46 |

A static counterpart applies the selected recovery time and gain to every landing; it disables the conditional gate. Bias/zero-head rows retain the candidate gate and tuned backbone, so they test the contribution of the inherited temporal head within the complete policy. Conditional distance means exclude invalid starts; the arena includes all guard failures.

### Longer motion and learned correction magnitude

- pure_recovery: **8/8** legal at twenty seconds.
- pure_distance: **5/8** legal at twenty seconds.
- tcn_recovery: **7/8** legal at twenty seconds.
- tcn_distance: **6/8** legal at twenty seconds.
- tcn_recovery, hip/knee/spine/shoulder: sampled peak **5.24 / 9.54 / 1.99 / 7.71°**; RMS **4.26 / 7.17 / 1.34 / 6.70°**. These 10 Hz requests precede geometry and spring filtering; sampled peaks are not continuous maxima.
- tcn_distance, hip/knee/spine/shoulder: sampled peak **5.24 / 9.54 / 1.99 / 7.71°**; RMS **4.22 / 7.12 / 1.32 / 6.72°**. These 10 Hz requests precede geometry and spring filtering; sampled peaks are not continuous maxima.

### Direct comparisons

| Trial | Comparison | Oriented paired diff | p | First policy wins |
|---|---|---:|---:|---|
| search_jump_legal | tcn_recovery minus pure_recovery | +0.07525 | 0.00375 | True |
| search_jump_legal | tcn_distance minus pure_distance | +0.061 | 0.00375 | True |
| search_jump_legal | tcn_distance minus tcn_recovery | +0 | 1.00000 | False |
| search_jump_robust_legal | tcn_recovery minus pure_recovery | +0.063 | 0 / 4,000 sampled flips | True |
| search_jump_robust_legal | tcn_distance minus pure_distance | -62500000 | 0.74775 | False |
| search_jump_robust_legal | tcn_distance minus tcn_recovery | -62500000.1 | 0.76325 | False |
| gpt_jump_stable6 | tcn_recovery minus pure_recovery | -125000000 | 0.89300 | False |
| gpt_jump_stable6 | tcn_distance minus pure_distance | +156250000 | 0.04450 | True |
| gpt_jump_stable6 | tcn_distance minus tcn_recovery | +0.00631250069 | 0.49025 | False |

### New champion videos and audit

No round-5 candidate qualified for promotion; earlier champions remain in place.

All **24 audit checks** pass: [audit](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round5/support/audit.json), [complete summary](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round5/support/summary.json), [frozen selections](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round5/support/candidates.json). Shared SDK, simulator, and existing trial definitions are unchanged; no commits or main-checkout edits were made. There were no qualifying promotions in round 5.

### Round-5 interpretation and remaining failures

**No candidate beats both required incumbents.** The temporal recovery candidate clears all 32 robustness starts at **1.318375 m**; its **+0.00303125 m** difference from P6 is inconclusive (**p = 0.40675**). The two temporal candidates exactly match the existing distance champion at **1.363 m**, so neither wins that trial. The temporal distance alternative fails two robustness starts. Both temporal candidates clear only 26/32 on the six-second diagnostic, behind the round-4 champion's 31/32.

The conditional gate has a measurable benefit: fresh temporal recovery clears **64/64** three-second starts, versus **57/64** for its unchanged round-2 policy, while retaining a **1.32583 m** conditional mean. Static recovery also clears 64/64 but shortens that mean to **1.24825 m**. Conditional recovery clears **55/64** at eight seconds and **7/8** at twenty; pure recovery is more reliable (**62/64**, **8/8**) but shorter (**1.25248 m** at three seconds). Every candidate's fresh eight-second invalid run is flagged fallen, with no foul or inversion; the exact seeds are in the linked failure evidence.

On the matched arena starts, temporal recovery is **0.063 m** ahead of pure recovery on robustness (0 of 4,000 sampled flips as favorable), and **0.07525 m** ahead on distance (p = 0.00375). Those family comparisons do not turn the P6 comparison into a win. The zero-head ablation reduces temporal recovery's eight-second legality from **55/64 to 22/64**; bias-only gives **43/64** and shorter jumps. This supports a contribution from the inherited temporal head within this policy, while the pure policy retains the strongest longer-horizon validation in this round.

[Exact fresh failure flags and seeds](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round5/support/failure_modes.json). No new champion video is claimed because no candidate qualifies for promotion.

## Round 6: launch and conditional-support refinement

Round 5 restored 32/32 short-horizon legality but did not decisively beat P6. This round starts from its pure and temporal recovery candidates and tunes twelve explicit launch, recovery-pose, and conditional-support parameters. Contraction keyframe vectors and inherited learned heads remain frozen.

**Pure search.** Retain the phase-indexed correction model and measured landing-depth gate. Tune crouch and extension duration, takeoff height, hip/arm drive, recovery duration and hip/knee/ankle posture, plus gate delay, height, and gain.

**Temporal residual.** Tune the identical twelve explicit parameters around the earlier causal-convolution policy. Its twenty learned readout weights remain frozen. This is equal-budget refinement of two previously trained policies, not a common-initialization neural architecture experiment.

Each family receives **4,096 rollouts on 32 new starts (282101–282132)**, (1+1)-ES seed 280930, normalized sigma .008, risk .5. The score prioritizes three-second legality and distance, rewards eight-second legality and mark, and penalizes full-rollout peak force and loading. Exactly one best training candidate per family is frozen before **64 untouched starts (283101–283164)**. P6 is a separately trained incumbent.

### Arena outcomes

All six entries precede promotion. A candidate must beat both the worktree and recorded main incumbent where both exist. Large guard-scored differences are not metres. The arena uses unadjusted sign-flip comparisons.

| Trial | Family | Valid | Mean valid mark, m | Local diff | Local p | Local verdict | Main diff | Main p | Main verdict |
|---|---|---:|---:|---:|---:|---|---:|---:|---|
| search_jump_legal | pure | 8/8 | 1.23525 | -0.12775 | 1.00000 | LOSE | -0.12775 | 1.00000 | LOSE |
| search_jump_legal | tcn | 8/8 | 1.311 | -0.052 | 1.00000 | LOSE | -0.052 | 1.00000 | LOSE |
| search_jump_robust_legal | pure | 32/32 | 1.26403125 | -0.00815625 | 0.77100 | LOSE | -0.0513125 | 1.00000 | LOSE |
| search_jump_robust_legal | tcn | 32/32 | 1.323125 | +0.0509375 | 0 / 4,000 sampled flips | WIN | +0.00778125 | 0.18750 | LOSE |
| gpt_jump_stable6 | pure | 30/32 | 1.2391333333333334 | -31250000.1 | 0.86350 | LOSE | — | — | — |
| gpt_jump_stable6 | tcn | 31/32 | 1.3189677419354837 | +0.0308125003 | 0.24025 | LOSE | — | — | — |

### Fresh validation and ablations

| Controller | Legal 3 s | Mean legal 3 s mark, m | Legal 8 s | Mean legal 8 s mark, m | Gate triggered | Peak force, BW | Loading, BW/s |
|---|---:|---:|---:|---:|---:|---:|---:|
| pure | 64/64 | 1.252375 | 62/64 | 1.2309838709677419 | 5/64 | 5.48 | 1462.8 |
| pure_previous | 64/64 | 1.240484375 | 62/64 | 1.2384032258064517 | 25/64 | 5.39 | 1472.7 |
| pure_static | 64/64 | 1.21890625 | 62/64 | 1.2156290322580645 | 0/64 | 5.48 | 1462.8 |
| tcn | 64/64 | 1.310578125 | 61/64 | 1.315344262295082 | 3/64 | 5.69 | 1424.8 |
| tcn_previous | 64/64 | 1.31725 | 51/64 | 1.3374509803921568 | 13/64 | 5.75 | 1413.7 |
| tcn_static | 64/64 | 1.23690625 | 57/64 | 1.250280701754386 | 0/64 | 5.69 | 1424.8 |
| tcn_bias | 64/64 | 1.27521875 | 61/64 | 1.2822459016393442 | 10/64 | 5.73 | 1424.0 |
| tcn_zero | 35/64 | 1.2336857142857143 | 11/64 | 1.1626363636363637 | 0/64 | 5.24 | 1536.9 |
| p6_reference | 64/64 | 1.317953125 | 0/64 | — | 0/64 | 6.49 | 1865.8 |

Static recovery applies the selected time and gain on every landing. Bias-only and zero-head ablations retain the tuned backbone and gate. Conditional means exclude invalid starts; arena decisions include all failures.

### Longer recovery and correction magnitudes

- pure: **8/8** legal at twenty seconds.
- tcn: **8/8** legal at twenty seconds.
- pure_8s, same starts legal at both horizons (n=62): mean mark drop after three seconds **0.020709677419354817 m**, maximum **0.1280000000000001 m**. [Per-seed distance retention](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round6/distance_retention.json).
- tcn_8s, same starts legal at both horizons (n=61): mean mark drop after three seconds **0.0 m**, maximum **0.0 m**. [Per-seed distance retention](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round6/distance_retention.json).
- pure_20s, same starts legal at both horizons (n=8): mean mark drop after three seconds **0.02474999999999994 m**, maximum **0.07599999999999985 m**. [Per-seed distance retention](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round6/distance_retention.json).
- tcn_20s, same starts legal at both horizons (n=8): mean mark drop after three seconds **0.0 m**, maximum **0.0 m**. [Per-seed distance retention](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round6/distance_retention.json).
- Temporal hip/knee/spine/shoulder: sampled peak **5.21 / 9.46 / 2.07 / 7.69°**, RMS **4.34 / 7.29 / 1.39 / 6.70°**. These 10 Hz requests precede geometry and spring filtering; sampled peaks are not continuous maxima.

### Direct temporal minus pure comparisons

| Trial | Oriented paired diff | p | Temporal wins |
|---|---:|---:|---|
| search_jump_legal | +0.07575 | 0.00375 | True |
| search_jump_robust_legal | +0.05909375 | 0 / 4,000 sampled flips | True |
| gpt_jump_stable6 | +31250000.1 | 0.13250 | False |

### New champion videos, failure evidence, and audit

No candidate qualifies for promotion; earlier champions remain in place.
- pure, three_second: fallen: []; foul: []; inverted: []
- pure, eight_second: fallen: [283114, 283116]; foul: []; inverted: []
- tcn, three_second: fallen: []; foul: []; inverted: []
- tcn, eight_second: fallen: [283124, 283158, 283163]; foul: []; inverted: []

All **25 audit checks** pass: [audit](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round6/audit.json), [complete summary](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round6/summary.json), [frozen selections](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round6/candidates.json). Shared SDK, simulator, and existing trials are unchanged; no commits or main-checkout edits. Finite recovery tests do not establish universal stability.

### Round-6 interpretation

**No candidate qualifies for promotion.** Temporal is legal on all 32 robustness starts and averages **1.323125 m**. Its **+0.00778125 m** paired gain over P6 remains inconclusive (**p = 0.1875**), despite a decisive win over the older local robustness incumbent. Both families lose the existing distance trial. Temporal reaches **31/32** on the six-second diagnostic, with mean valid mark **1.31897 m**, but does not beat the incumbent under the arena rule (**p = 0.24025**). Equal success counts hide a different failed start, which the paired guard-scored comparison retains.

Fresh temporal recovery improves from the round-5 starting policy's **51/64 to 61/64** eight-second legal runs on these same untouched starts, while its mean three-second mark falls from **1.31725 to 1.31058 m**. Pure improves three-second distance from **1.24048 to 1.25238 m**, with **62/64** eight-second legality unchanged. Both refined policies pass the eight twenty-second checks. These are finite validation outcomes, not an arena win over P6.

Longer scoring exposes a useful distinction: on the 61 temporal starts legal at both three and eight seconds, the mark is unchanged; on the 62 comparable pure starts it falls by **2.07 cm on average**, at worst **12.8 cm**. At twenty seconds, temporal again retains the mark on all eight surviving starts; pure loses **2.48 cm on average**. The reported eight-second conditional means use different surviving subsets, so they must not be subtracted from the all-legal three-second means to estimate retreat. The linked distance-retention table uses identical starts.

The temporal controller beats pure by **0.07575 m** on distance (p = **0.00375**) and **0.05909375 m** on robustness (0 of 4,000 sampled flips as favorable). Its direct six-second advantage remains inconclusive (p = **0.1325**). Zeroing the inherited temporal head reduces fresh eight-second legality from **61/64 to 11/64**. Bias-only also reaches **61/64**, but shortens mean three-second distance from **1.31058 to 1.27522 m**. The inherited temporal dependence contributes distance here; it is not a new convolution-training result.

This refinement used a blend of mean and minimum training scores. The next bounded experiment tests mean-score selection with the same per-start legality, distance, recovery, and impact terms, starting from these frozen policies on new private starts. Its outcome is not yet known.


## Round 7: mean-score launch and support refinement

Round 6 improved longer recovery but still did not decisively beat P6. This round starts from its frozen pure and temporal candidates and tunes the same twelve explicit launch, recovery-pose, and conditional-support parameters, ranking candidates by mean per-start score instead of the prior mean/minimum blend. Contraction keyframe vectors and inherited learned heads remain frozen.

**Pure search.** Retain the phase-indexed correction model and measured landing-depth gate. Tune crouch and extension duration, takeoff height, hip/arm drive, recovery duration and hip/knee/ankle posture, plus gate delay, height, and gain.

**Temporal residual.** Tune the identical twelve explicit parameters around the earlier causal-convolution policy. Its twenty learned readout weights remain frozen. This is equal-budget refinement of two previously trained policies, not a common-initialization neural architecture experiment.

Each family receives **2,048 rollouts on 32 new starts (284101–284132)**, (1+1)-ES seed 280931, normalized sigma .008, risk 0 (mean aggregation). The score prioritizes three-second legality and distance, rewards eight-second legality and mark, and penalizes full-rollout peak force and loading. Exactly one best training candidate per family is frozen before **64 untouched starts (285101–285164)**. P6 is a separately trained incumbent.

### Arena outcomes

All six entries precede promotion. A candidate must beat both the worktree and recorded main incumbent where both exist. Large guard-scored differences are not metres. The arena uses unadjusted sign-flip comparisons.

| Trial | Family | Valid | Mean valid mark, m | Local diff | Local p | Local verdict | Main diff | Main p | Main verdict |
|---|---|---:|---:|---:|---:|---|---:|---:|---|
| search_jump_legal | pure | 8/8 | 1.290875 | -0.072125 | 1.00000 | LOSE | -0.072125 | 1.00000 | LOSE |
| search_jump_legal | tcn | 8/8 | 1.349 | -0.014 | 1.00000 | LOSE | -0.014 | 1.00000 | LOSE |
| search_jump_robust_legal | pure | 32/32 | 1.2635625 | -0.008625 | 0.83525 | LOSE | -0.05178125 | 1.00000 | LOSE |
| search_jump_robust_legal | tcn | 32/32 | 1.33965625 | +0.06746875 | 0 / 4,000 sampled flips | WIN | +0.0243125 | 0 / 4,000 sampled flips | WIN |
| gpt_jump_stable6 | pure | 31/32 | 1.2356129032258065 | -0.0499375001 | 0.74475 | LOSE | — | — | — |
| gpt_jump_stable6 | tcn | 26/32 | 1.3345384615384615 | -156250000 | 0.97500 | LOSE | — | — | — |

### Fresh validation and ablations

| Controller | Legal 3 s | Mean legal 3 s mark, m | Legal 8 s | Mean legal 8 s mark, m | Gate triggered | Peak force, BW | Loading, BW/s |
|---|---:|---:|---:|---:|---:|---:|---:|
| pure | 64/64 | 1.259546875 | 64/64 | 1.24415625 | 5/64 | 5.42 | 1466.6 |
| pure_previous | 63/64 | 1.2504285714285714 | 59/64 | 1.2333559322033898 | 1/64 | 5.48 | 1460.9 |
| pure_static | 64/64 | 1.214953125 | 64/64 | 1.21334375 | 0/64 | 5.42 | 1466.6 |
| tcn | 64/64 | 1.334140625 | 57/64 | 1.338684210526316 | 2/64 | 5.72 | 1407.7 |
| tcn_previous | 64/64 | 1.309375 | 60/64 | 1.3123833333333335 | 2/64 | 5.65 | 1419.1 |
| tcn_static | 64/64 | 1.236328125 | 54/64 | 1.2402962962962962 | 0/64 | 5.72 | 1407.7 |
| tcn_bias | 64/64 | 1.271453125 | 47/64 | 1.2956808510638298 | 11/64 | 5.83 | 1412.3 |
| tcn_zero | 49/64 | 1.2415714285714285 | 17/64 | 1.1758235294117647 | 0/64 | 5.40 | 1535.6 |
| p6_reference | 64/64 | 1.32309375 | 0/64 | — | 0/64 | 6.41 | 1855.5 |

Static recovery applies the selected time and gain on every landing. Bias-only and zero-head ablations retain the tuned backbone and gate. Conditional means exclude invalid starts; arena decisions include all failures.

### Longer recovery and correction magnitudes

- pure: **8/8** legal at twenty seconds.
- tcn: **8/8** legal at twenty seconds.
- pure_8s, same starts legal at both horizons (n=64): mean mark drop after three seconds **0.015390624999999995 m**, maximum **0.08000000000000007 m**. [Per-seed distance retention](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round7/distance_retention.json).
- tcn_8s, same starts legal at both horizons (n=57): mean mark drop after three seconds **0.0 m**, maximum **0.0 m**. [Per-seed distance retention](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round7/distance_retention.json).
- pure_20s, same starts legal at both horizons (n=8): mean mark drop after three seconds **0.015625 m**, maximum **0.08000000000000007 m**. [Per-seed distance retention](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round7/distance_retention.json).
- tcn_20s, same starts legal at both horizons (n=8): mean mark drop after three seconds **0.0 m**, maximum **0.0 m**. [Per-seed distance retention](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round7/distance_retention.json).
- Temporal hip/knee/spine/shoulder: sampled peak **5.24 / 9.52 / 2.05 / 7.72°**, RMS **4.30 / 7.21 / 1.36 / 6.71°**. These 10 Hz requests precede geometry and spring filtering; sampled peaks are not continuous maxima.

### Direct temporal minus pure comparisons

| Trial | Oriented paired diff | p | Temporal wins |
|---|---:|---:|---|
| search_jump_legal | +0.058125 | 0.00375 | True |
| search_jump_robust_legal | +0.07609375 | 0 / 4,000 sampled flips | True |
| gpt_jump_stable6 | -156250000 | 0.94625 | False |

### New champion videos, failure evidence, and audit

- search_jump_robust_legal, **tcn**, seed 3024: [twenty-second video](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round7/video_search_jump_robust_legal_tcn.mp4) and [contact sheet](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round7/video_search_jump_robust_legal_tcn_sheet.png); legal at the end: **True**.
- pure, three_second: fallen: []; foul: []; inverted: []
- pure, eight_second: fallen: []; foul: []; inverted: []
- tcn, three_second: fallen: []; foul: []; inverted: []
- tcn, eight_second: fallen: [285122, 285123, 285150, 285152, 285154, 285157, 285160]; foul: []; inverted: []

All **27 audit checks** pass: [audit](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round7/audit.json), [complete summary](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round7/summary.json), [frozen selections](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round7/candidates.json). Shared SDK, simulator, and existing trials are unchanged; no commits or main-checkout edits. Finite recovery tests do not establish universal stability.

The new robustness champion remains a tradeoff: its distance-only entry is 1.349 m versus the earlier 1.363 m champion, and its six-second entry falls to 26/32 versus the retained 31/32 recovery champion. On the same fresh starts, refinement raises temporal mean three-second distance from 1.309375 to 1.334140625 m while reducing eight-second legality from 60/64 to 57/64. Pure reaches 64/64 but with shorter marks. Temporal keeps the measured mark on all 57 surviving starts; pure retreats 1.54 cm on average, at most 8 cm. The representative champion video (seed 3024, 1.341 m) visibly settles into a balanced crouch and stays there through twenty seconds.


## Rounds 1–7 completion evidence and interpretation

The work used the requested isolated worktree, left inherited SDK and simulation files unchanged, preserved existing trials, and created no commits. One search ran at a time with at most three rollout workers. All initial problems include both the explicit phase-based baseline and the bounded, zero-initialized temporal-convolution residual. Only the twenty-weight neural readout was learned; the convolution filters remained fixed. Follow-up rounds explicitly disclose when those learned weights were frozen.

The separate final audit passes **27 checks**: [requirement audit](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/gpt_campaign_final/requirements_audit.json) and [all 52 arena decisions](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/gpt_campaign_final/arena_ledger.json). It recomputes every recorded verdict, checks all twenty frozen selections, confirms validation preceded each arena entry, verifies shared-file and trial integrity, and fully decodes all 8 promoted-champion videos. Previous round audits and unsuccessful candidates are retained.

**Learned residual versus pure search.** Temporal feedback has its clearest benefit in crossovers: 7.52 versus 4.68 on the same 25 arena starts, paired +2.84, with no favorable null sample among 4,000 sign flips. Fresh bias-only and zero-head ablations lose much of that gain. Pure search wins the batting comparison: 14.72056 versus 13.92056 m/s, while the learned time dependence adds little beyond a constant offset. The measured hitch remains. For jumping, temporal wins the original distance trial at 1.363 m and contributes to longer recovery, but explicit landing logic is essential and the strongest later robustness comparisons must be read individually. Round 7 wins the pinned P6 comparison. These results do not establish general neural superiority, sustained ball control, arms-only finger technique, or universal landing stability.

Arena decisions use the project's unadjusted exploratory rule, and multiple follow-ups reused its held-out starts. Fresh validation supports the reported finite behavior; it does not turn a borderline arena gain into a confirmed frontier improvement. P6 has a different training history and was never part of the matched-compute family comparison.


## Continuing research: sustained crossover control

A read-only review of the initial 24 fresh temporal runs clarifies the arms-only limitation. Their raw trunk share averages **0.115625**, but only **7/24** reach ten dribbles; the conditional arms-only score therefore averages **0.742**. Control lasts **6.2246 seconds** on average, with **22/24** losses caused by two floor bounces without a touch and two losses caused by lateral drift. These are already-consumed validation runs, not new evidence of an arena win. The arena verdicts stay unchanged. Sustained catching is the next candidate for investigation; the inherited trunk pump and paddle hands still remain. [Metric definition and diagnostic evidence](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round8/dribble_followup_diagnosis.json).

Code inspection also identifies a limitation of the original pure crossover baseline: it indexes its offsets by the **right-hand track phase**, even when the left hand is active. The temporal model instead uses measured muscle-state and ball channels. The recorded arena gap remains valid for those controllers, and the temporal bias-only ablation still loses performance, but the family comparison does not establish superiority over an active-hand phase baseline. That stronger baseline is a planned follow-up; no new performance claim is made.


## Round 8: landing-feedback refinement

Round 7 won the three-second robustness comparison but still lost several later recoveries. Read-only diagnostics of its consumed validation starts found backward motion and capture points behind the feet. This round tunes eight existing landing-feedback parameters around the frozen round-7 policies. Launch, standing pose, conditional recovery gate and inherited learned heads remain fixed.

**Pure search.** Retain the phase-indexed correction model. Tune the capture-point target and ankle, hip, knee, spine and arm feedback gains, plus trunk-angle and trunk-rate feedback. All other explicit movement parameters remain fixed. The audit compares commands, activations and measured joint motion exactly before landing on the first untouched start.

**Temporal residual.** Tune the identical eight landing-feedback parameters around the round-7 causal-convolution policy. Its twenty learned readout weights remain frozen. This is equal-budget refinement of two previously trained policies, not a common-initialization neural architecture experiment.

Each family receives **2,048 rollouts on 32 new starts (286101–286132)**, (1+1)-ES seed 280932, normalized sigma .02, risk .5 (equal blend of mean and worst start). The score prioritizes eight-second legality, also rewards three-second legality, both marks and time before a fall, and penalizes full-rollout peak force and loading. Exactly one best training candidate per family is frozen before **64 untouched starts (287101–287164)**. P6 is a separately trained incumbent.

### Arena outcomes

All six entries precede promotion. A candidate must beat both the worktree and recorded main incumbent where both exist. Large guard-scored differences are not metres. The arena uses unadjusted sign-flip comparisons.

| Trial | Family | Valid | Mean valid mark, m | Local diff | Local p | Local verdict | Main diff | Main p | Main verdict |
|---|---|---:|---:|---:|---:|---|---:|---:|---|
| search_jump_legal | pure | 8/8 | 1.288 | -0.075 | 1.00000 | LOSE | -0.075 | 1.00000 | LOSE |
| search_jump_legal | tcn | 8/8 | 1.348375 | -0.014625 | 1.00000 | LOSE | -0.014625 | 1.00000 | LOSE |
| search_jump_robust_legal | pure | 32/32 | 1.27059375 | -0.0690625 | 1.00000 | LOSE | -0.04475 | 1.00000 | LOSE |
| search_jump_robust_legal | tcn | 32/32 | 1.335 | -0.00465625 | 1.00000 | LOSE | +0.01965625 | 0 / 4,000 sampled flips | WIN |
| gpt_jump_stable6 | pure | 29/32 | 1.2688620689655172 | -62500000.1 | 0.99925 | LOSE | — | — | — |
| gpt_jump_stable6 | tcn | 31/32 | 1.3260645161290323 | +0.0376875004 | 0.24550 | LOSE | — | — | — |

### Fresh validation and ablations

| Controller | Legal 3 s | Mean legal 3 s mark, m | Legal 8 s | Mean legal 8 s mark, m | Gate triggered | Peak force, BW | Loading, BW/s |
|---|---:|---:|---:|---:|---:|---:|---:|
| pure | 64/64 | 1.268328125 | 61/64 | 1.2722786885245903 | 5/64 | 5.45 | 1469.9 |
| pure_previous | 64/64 | 1.266875 | 64/64 | 1.2558125 | 5/64 | 5.41 | 1469.5 |
| tcn | 64/64 | 1.3252187500000001 | 62/64 | 1.3294032258064516 | 5/64 | 5.76 | 1407.9 |
| tcn_previous | 64/64 | 1.32525 | 61/64 | 1.330655737704918 | 5/64 | 5.74 | 1407.1 |
| tcn_bias | 64/64 | 1.28159375 | 61/64 | 1.2834918032786886 | 10/64 | 5.82 | 1407.0 |
| tcn_zero | 43/64 | 1.2334418604651163 | 17/64 | 1.1865294117647058 | 0/64 | 5.51 | 1604.4 |
| p6_reference | 62/64 | 1.3203709677419355 | 0/64 | — | 0/64 | 6.48 | 1861.8 |

Previous policies are evaluated unchanged on the same fresh starts. Bias-only and zero-head ablations retain all tuned feedback, backbone and gate parameters. Conditional means exclude invalid starts; arena decisions include all failures.

### Longer recovery and correction magnitudes

- pure: **8/8** legal at twenty seconds.
- tcn: **8/8** legal at twenty seconds.
- pure_8s, same starts legal at both horizons (n=61): mean mark drop after three seconds **0.0015081967213114694 m**, maximum **0.05499999999999994 m**. [Per-seed distance retention](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round8/distance_retention.json).
- tcn_8s, same starts legal at both horizons (n=62): mean mark drop after three seconds **0.0 m**, maximum **0.0 m**. [Per-seed distance retention](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round8/distance_retention.json).
- pure_20s, same starts legal at both horizons (n=8): mean mark drop after three seconds **0.00012499999999998623 m**, maximum **0.0009999999999998899 m**. [Per-seed distance retention](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round8/distance_retention.json).
- tcn_20s, same starts legal at both horizons (n=8): mean mark drop after three seconds **0.0 m**, maximum **0.0 m**. [Per-seed distance retention](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round8/distance_retention.json).
- Temporal hip/knee/spine/shoulder: sampled peak **5.26 / 9.58 / 1.92 / 7.70°**, RMS **4.35 / 7.27 / 1.37 / 6.66°**. These 10 Hz requests precede geometry and spring filtering; sampled peaks are not continuous maxima.

### Direct temporal minus pure comparisons

| Trial | Oriented paired diff | p | Temporal wins |
|---|---:|---:|---|
| search_jump_legal | +0.060375 | 0.00375 | True |
| search_jump_robust_legal | +0.06440625 | 0 / 4,000 sampled flips | True |
| gpt_jump_stable6 | +62500000.1 | 0.06175 | False |

### New champion videos, failure evidence, and audit

No candidate qualifies for promotion; earlier champions remain in place.
- pure, three_second: fallen: []; foul: []; inverted: []
- pure, eight_second: fallen: [287117, 287142, 287149]; foul: []; inverted: [287117, 287142]
- tcn, three_second: fallen: []; foul: []; inverted: []
- tcn, eight_second: fallen: [287110, 287117]; foul: []; inverted: [287110]

All **27 audit checks** pass: [audit](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round8/audit.json), [complete summary](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round8/summary.json), [frozen selections](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round8/candidates.json). Shared SDK, simulator, and existing trials are unchanged; no commits or main-checkout edits. Finite recovery tests do not establish universal stability.

### Interpretation and unchanged launch

The audit verifies identical pre-landing commands, measured contractions, activations and joint positions for each family on the first untouched start (pure: 429 control samples; temporal: 433). No launch, stance-pose, gate or learned-head parameters changed. The eight feedback changes act together; these results do not isolate the contribution of any single gain.

A post-hoc comparison against the frozen round-7 temporal parent improves six-second legality from 26/32 to 31/32, with the arena sign-flip calculation giving p = 0.0235. This is a reference-policy diagnostic, not the reigning-champion promotion test. The new controller fails seed 272003; the actual six-second champion fails 272023. Against that champion the paired result remains p = 0.2455, so no promotion is justified. [Parent comparison and failed starts](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_jump_round8/parent_recovery_comparison.json).

On fresh starts, temporal fixes 287134, 287144 and 287158 but introduces failures on 287110 and 287117. Pure introduces failures on 287117, 287142 and 287149 where its predecessor passed. The training improvement therefore does not establish broadly better recovery. Both frozen candidates and all negative results are retained for future investigation.


## Round 9: sustained crossover catching

Both contenders start from the same previously selected crossover backbone with twenty zero residual weights. The pure contender now conditions its bounded shoulder, elbow and wrist offsets on the active hand's motion phase. The temporal contender uses fixed causal convolution features of measured muscle contraction, derivatives and ball state with a learned bounded readout. The explicit contraction/keyframe choreography and reflex layer remain the backbone; neither controller emits raw activations. The inherited trunk pump and paddle-hand mechanics remain.

Each receives **1,024 rollouts on eight new starts**, (1+1)-ES seed 280933, sigma .025, with the same mean/worst-start aggregate. They tune the same eight catch-feedback parameters and twenty residual weights. Training rewards successful crossovers and duration of control while penalizing failed moves, missed-catch distance, body contacts, drift, apex variability and whole-rollout force/loading. One best training policy per family is frozen before **32 untouched validation starts**. This is a matched-compute comparison from a common starting motion; the predecessor has a separate training history.

### Arena verdicts

| Trial | Family | Mean score | Local paired gain | Local p | Local win | Main paired gain | Main p | Main win |
|---|---|---:|---:|---:|---|---:|---:|---|
| dribble_crossover_25 | pure | 6.8 | -0.720000 | 0.936 | False | -0.720000 | 0.936 | False |
| dribble_crossover_25 | tcn | 9.08 | +1.560000 | 0.0065 | True | +1.560000 | 0.0065 | True |
| dribble_crossover | pure | 6.2 | +2.500000 | 0.001 | True | -1.100000 | 0.89225 | False |
| dribble_crossover | tcn | 9.4 | +5.700000 | 0.001 | True | +2.100000 | 0.092 | False |
| dribble_arms_only | pure | 0.9114 | -0.729100 | 0.99925 | False | -0.729100 | 0.99925 | False |
| dribble_arms_only | tcn | 0.2039 | -0.021600 | 0.502 | False | -0.021600 | 0.502 | False |

The arms-only trial is a **conditional penalty score, lower is better**: runs below ten dribbles receive 1.0. It is not raw trunk activation share. The task measures trunk share while ball control lasts; the force/loading instrumentation covers the full fifteen-second rollout. Paired gains are oriented so positive favors the challenger. All six entries precede promotion; promotion requires beating both recorded incumbents. p=0 means zero of 4,000 sampled sign flips, not an exact zero probability. Tests are unadjusted exploratory comparisons.

### Fresh validation and ablations

| Controller | Crossovers | Control, s | Dribbles | Runs ≥10 | Raw trunk share | Conditional score | Lost |
|---|---:|---:|---:|---:|---:|---:|---:|
| pure | 6.4688 | 5.5600 | 7.3750 | 4/32 | 0.11541 | 0.88938 | 32/32 |
| pure_bias | 3.1562 | 3.4778 | 4.1250 | 0/32 | 0.11628 | 1.00000 | 32/32 |
| pure_right_phase | 3.2500 | 3.4472 | 4.2500 | 0/32 | 0.11653 | 1.00000 | 32/32 |
| tcn | 9.0625 | 7.1263 | 10.0312 | 15/32 | 0.11616 | 0.58544 | 32/32 |
| tcn_bias | 3.3125 | 3.5184 | 4.3125 | 0/32 | 0.11669 | 1.00000 | 32/32 |
| tcn_zero | 2.0312 | 2.7103 | 3.0312 | 0/32 | 0.11859 | 1.00000 | 32/32 |
| previous | 7.8438 | 6.1706 | 8.5938 | 9/32 | 0.11578 | 0.75125 | 32/32 |
| common_zero | 3.7500 | 3.8272 | 4.7500 | 0/32 | 0.11572 | 1.00000 | 32/32 |

The common-zero policy restores the shared starting movement. Bias-only and zero-head ablations retain tuned catch feedback. The pure right-phase ablation alone restores the old phase selection. The previous champion is evaluated unchanged on the same fresh starts.

### Direct architecture comparison

| Trial | Temporal minus pure, oriented gain | p | Temporal wins |
|---|---:|---:|---|
| dribble_crossover_25 | +2.280000 | 0.00025 | True |
| dribble_crossover | +3.200000 | 0.009 | True |
| dribble_arms_only | +0.707500 | 0.00425 | True |

**Learned residual versus pure search.** Temporal wins the direct arena comparison on dribble_crossover_25, dribble_crossover, dribble_arms_only. On the same 32 fresh starts it averages 9.0625 crossovers versus 6.4688 for the corrected active-hand phase baseline. Temporal bias-only and zero-head ablations average 3.3125 and 2.0312; the earlier champion averages 7.8438. Restoring the old right-hand-only phase in the newly trained pure policy reduces it to 3.2500. These ablations support contributions from both the active-phase correction and temporal inputs in the tested policies. They are interventions on selected weights, not separately retrained equal-budget architectures. The pure-versus-temporal contenders themselves have matched budgets and a common starting movement. Every fresh selected run still loses the ball; this is an improvement in finite control, not sustained fifteen-second control or general neural superiority.


### Residual magnitude and measured movement

- pure, shoulder flexion / shoulder abduction / elbow / wrist: sampled peak **1.49 / 1.67 / 2.08 / 1.60°**, RMS **0.89 / 0.62 / 0.57 / 1.02°**. Mean measured arm-excursion shares: {'shoulder': 0.4236875, 'elbow': 0.338125, 'wrist': 0.2381875, 'fingers': 0}.
- tcn, shoulder flexion / shoulder abduction / elbow / wrist: sampled peak **0.49 / 1.95 / 4.49 / 0.96°**, RMS **0.24 / 1.48 / 2.97 / 0.76°**. Mean measured arm-excursion shares: {'shoulder': 0.430375, 'elbow': 0.33437500000000003, 'wrist': 0.23525, 'fingers': 0}.

Offsets are limited to .18 / .18 / .25 / .18 radians and act through geometry conversion and spring filtering. The 10 Hz diagnostic peaks are sampled requests, not continuous maxima. Exact preflight tests preserve zero-head and disabled-mode trajectories. Nonzero active-phase changes first appear when the receiving left hand recovers; temporal mode is exactly independent of this phase argument. Full-horizon commands, activations and measured joint motion are compared in the audit.

### Failures and champion videos

**Separate consumed-start diagnosis.** Offline forward kinematics of two predecessor traces shows one outgoing pass remaining on the wrong side, and another dropping low and forward beyond the receiving stroke. These sampled geometric gaps are not official force-threshold contacts and are not new validation. They motivate a later outgoing-stroke or recovery-selection experiment without changing this round. [Measured trajectory figure](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_dribble_round9/saved_crossover_geometry.png) and [source-pinned replay evidence](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_dribble_round9/saved_geometry_diagnosis.json).

- pure: losses {'two floor bounces without a touch': 29, 'bounced 0.54 m from home': 1, 'bounced 0.59 m from home': 1, 'bounced 0.46 m from home': 1}; fallen starts [].
- tcn: losses {'two floor bounces without a touch': 31, 'bounced 0.50 m from home': 1}; fallen starts [].
- previous: losses {'two floor bounces without a touch': 24, 'bounced 0.79 m from home': 1, 'bounced 0.61 m from home': 1, 'bounced 0.51 m from home': 1, 'bounced 0.52 m from home': 1, 'bounced 0.47 m from home': 2, 'bounced 0.67 m from home': 1, 'bounced 0.59 m from home': 1}; fallen starts [].
- dribble_crossover_25, tcn, seed 401: [full fifteen-second video](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_dribble_round9/video_dribble_crossover_25_tcn.mp4) and [contact sheet](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_dribble_round9/video_dribble_crossover_25_tcn_sheet.png). 9 crossovers; control 7.19 s; loss: two floor bounces without a touch; fell: False.

All **30 audit checks** pass. [Complete evidence](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_dribble_round9/summary.json), [audit](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_dribble_round9/audit.json), [frozen candidates](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_dribble_round9/candidates.json). Existing trials, shared SDK and physics are unchanged; no commits. Finite crossover results do not establish indefinite ball control or a complete arms-only/finger technique.


## Round 10: outgoing crossover refinement

The pure contender inherits the corrected active-hand phase policy from round 9. The temporal contender inherits the corresponding bounded convolutional residual policy. Both retain every residual weight and catch-feedback parameter. Twelve explicit outgoing-stroke parameters can change: target x/y, flight time, tilt gain and limit, sweep, low-point x/y/height/pitch, roll and push duration. The shared low-pose height/pitch and push duration also affect launch, and push duration affects trunk-pump timing. This is not an isolated post-release intervention. Geometry, spring filtering and contraction/reflex control remain the backbone; neither contender emits raw activations.

Each receives **2,048 rollouts on sixteen new starts**, (1+1)-ES seed 280934 and sigma .015, using the same mean/worst-start objective. It rewards successful crossovers and control time while penalizing move failures, catch miss, body contacts, drift, apex variability and complete-rollout force/loading. The best training candidate per family is frozen before **64 untouched starts**, eight validation groups and eight thirty-second continuations for each selected and parent controller. This is matched additional compute on different inherited policies, not a common-initialization architecture experiment.

### Arena verdicts

| Trial | Family | Mean score | Local paired gain | Local p | Local win | Main paired gain | Main p | Main win |
|---|---|---:|---:|---:|---|---:|---:|---|
| dribble_crossover_25 | pure | 6.6800 | -2.400000 | 1.0 | False | -0.840000 | 0.99075 | False |
| dribble_crossover_25 | tcn | 9.3200 | +0.240000 | 0.40975 | False | +1.800000 | 0.0025 | True |
| dribble_crossover | pure | 7.0000 | +3.300000 | 0.001 | True | -0.300000 | 0.6495 | False |
| dribble_crossover | tcn | 7.9000 | +4.200000 | 0.001 | True | +0.600000 | 0.3275 | False |
| dribble_arms_only | pure | 1.0000 | -0.817700 | 1.0 | False | -0.817700 | 1.0 | False |
| dribble_arms_only | tcn | 0.3808 | -0.198500 | 0.87425 | False | -0.198500 | 0.87425 | False |

[Completed training curves](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_dribble_round10/training_curves.png) and [source-pinned training evidence](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_dribble_round10/training_curves.json). These describe training only; the arena verdicts above are separate.


Both current boards replayed exactly before the six entries. Promotion requires paired wins against both. The arms-only metric is a conditional penalty (lower is better), set to 1.0 below ten dribbles. Raw trunk share is separate and covers time in control; force/loading cover the complete rollout. p=0 means zero of 4,000 sampled sign flips. These are unadjusted exploratory comparisons.

### Fresh validation

| Controller | Crossovers | Control, s | Dribbles | Runs ≥10 | Raw trunk share | Conditional penalty | Lost |
|---|---:|---:|---:|---:|---:|---:|---:|
| pure | 6.9219 | 5.8742 | 7.8750 | 9/64 | 0.11531 | 0.87550 | 64/64 |
| pure_previous | 6.6094 | 5.6545 | 7.5469 | 8/64 | 0.11544 | 0.88934 | 64/64 |
| pure_bias | 3.0781 | 3.3353 | 4.0781 | 0/64 | 0.11784 | 1.00000 | 64/64 |
| pure_zero | 3.5000 | 3.6131 | 4.4375 | 0/64 | 0.11653 | 1.00000 | 64/64 |
| tcn | 8.6562 | 6.8928 | 9.6250 | 30/64 | 0.11613 | 0.58561 | 64/64 |
| tcn_previous | 9.0938 | 7.1070 | 10.0156 | 35/64 | 0.11600 | 0.51642 | 64/64 |
| tcn_bias | 4.0156 | 3.9539 | 5.0156 | 0/64 | 0.11689 | 1.00000 | 64/64 |
| tcn_zero | 2.2188 | 2.8114 | 3.2031 | 0/64 | 0.11847 | 1.00000 | 64/64 |

**Whole-motion and contact evidence.** pure: mean body contacts 0.312, mean peak ground force 1.874 body weights, mean peak loading 377.949 BW/s; tcn: mean body contacts 0.250, mean peak ground force 1.886 body weights, mean peak loading 387.639 BW/s; pure_previous: mean body contacts 0.297, mean peak ground force 1.878 body weights, mean peak loading 377.949 BW/s; tcn_previous: mean body contacts 0.281, mean peak ground force 1.870 body weights, mean peak loading 377.949 BW/s. Body contacts remain a failure mode even if the arena crossover count improves.

Training gains did not reliably transfer: temporal fresh crossovers change 9.0938 → 8.6562, with control 7.1070 → 6.8928 s; pure changes 6.6094 → 6.9219. Validation never changes selection.

Previous controllers run unchanged. Bias and zero ablations retain newly tuned outgoing parameters; they are interventions on the selected inherited head, not separately retrained architectures.

### Thirty-second continuations

| Controller | Starts | Crossovers | Control, s | Ball lost |
|---|---:|---:|---:|---:|
| pure | 8 | 6.6250 | 5.7425 | 8/8 |
| pure_previous | 8 | 7.0000 | 5.9463 | 8/8 |
| tcn | 8 | 8.3750 | 6.7312 | 8/8 |
| tcn_previous | 8 | 10.2500 | 7.9100 | 8/8 |

These continuations use the first eight fresh starts and never determine selection. Continued movement after ball loss does not count as sustained control.

### What changed

| Parameter | Pure before | Pure after | Temporal before | Temporal after |
|---|---:|---:|---:|---:|
| x_dx | 0.082615 | 0.084299 | 0.082615 | 0.082625 |
| x_y | -0.202275 | -0.199644 | -0.202275 | -0.202370 |
| x_kv | 0.712517 | 0.706509 | 0.712517 | 0.712271 |
| x_t | 0.377401 | 0.390046 | 0.377401 | 0.377240 |
| x_tmax | 0.695806 | 0.685728 | 0.695806 | 0.696022 |
| x_steer | 0.027814 | 0.024615 | 0.027814 | 0.028059 |
| x_dxl | -0.079357 | -0.080495 | -0.079357 | -0.079240 |
| x_dyl | 0.039499 | 0.037062 | 0.039499 | 0.040917 |
| x_roll | 0.000000 | 0.003880 | 0.000000 | 0.000404 |
| z_low | 0.710137 | 0.713043 | 0.710137 | 0.710466 |
| pitch_low | -0.527818 | -0.506334 | -0.527818 | -0.529808 |
| t_push | 0.083849 | 0.085433 | 0.083849 | 0.083207 |

pure shoulder flexion / shoulder abduction / elbow / wrist requests: sampled peak 1.49 / 1.67 / 2.08 / 1.60 degrees; RMS 0.90 / 0.62 / 0.57 / 1.01 degrees. Mean measured arm-excursion shares: {'shoulder': 0.417453125, 'elbow': 0.34121875, 'wrist': 0.241375, 'fingers': 0}.

tcn shoulder flexion / shoulder abduction / elbow / wrist requests: sampled peak 0.50 / 1.96 / 4.51 / 0.94 degrees; RMS 0.26 / 1.52 / 2.96 / 0.75 degrees. Mean measured arm-excursion shares: {'shoulder': 0.4314375, 'elbow': 0.33487500000000003, 'wrist': 0.233703125, 'fingers': 0}.

Residual weights are unchanged, but state-dependent outputs can change with the new motion. Bounds remain .18/.18/.25/.18 radians, before spring filtering and geometry. Ten-Hz sampled peaks are not continuous maxima. Full measured q, contraction, command and activation effects are recorded in the audit.

### Failures and videos

- pure: {'two floor bounces without a touch': 61, 'bounced 0.47 m from home': 1, 'bounced 0.57 m from home': 1, 'bounced 0.48 m from home': 1}; fallen starts [].
- tcn: {'two floor bounces without a touch': 62, 'bounced 0.50 m from home': 1, 'bounced 0.54 m from home': 1}; fallen starts [].
- pure_previous: {'two floor bounces without a touch': 59, 'bounced 0.46 m from home': 2, 'bounced 0.69 m from home': 1, 'bounced 0.51 m from home': 1, 'bounced 0.50 m from home': 1}; fallen starts [].
- tcn_previous: {'two floor bounces without a touch': 59, 'bounced 0.46 m from home': 3, 'bounced 0.48 m from home': 1, 'bounced 0.55 m from home': 1}; fallen starts [].
No qualifying promotion; the earlier champions remain in place.

### Learned residual versus pure search

| Trial | Temporal minus pure, oriented | p | Temporal wins |
|---|---:|---:|---|
| dribble_crossover_25 | +2.640000 | 0.00025 | True |
| dribble_crossover | +0.900000 | 0.101 | False |
| dribble_arms_only | +0.619200 | 0.00925 | True |

Temporal averages 8.6562 crossovers on fresh starts versus pure 6.9219; their unchanged parents average 9.0938 and 6.6094. Both heads are inherited and fixed. The comparison measures how the two selected policies respond to equal additional backbone search; it does not show that new neural training caused the difference. Trunk pumping and paddle hands remain, and finite success does not establish indefinite control or finger technique.

All 36 focused audit checks pass. [Summary](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_dribble_round10/summary.json), [audit](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_dribble_round10/audit.json), [frozen candidates](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_dribble_round10/candidates.json), [consumed parent geometry](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_dribble_round10/parent_geometry.json). No existing trial, shared source or physics changed; no commits.


## Batter preparation follow-up: locating the quiet intervals

This is a consumed-start integration diagnostic, with no new training or arena entry. The prototype reuses earlier power-trained residual heads and permits their bounded corrections in the inherited stride/plant/load callbacks. No callback acts during leglift. All fifteen full-motion parity/effect checks passed on two previously consumed starts.

The unchanged99ms longest arm-quiet interval occurs at2.207–2.296s, just after leglift begins at2.2s. It is not evidence of a top-of-lift pause. A separate stride interval changes under the enabled correction:

| Measured interval | Preparation disabled | Pure enabled | Temporal enabled |
|---|---:|---:|---:|
| Pre-release arm stride quiet |89.1ms|0ms|29.7ms|
| Pre-release trunk stride quiet |79.2ms|0ms|0ms|
| Longest arm quiet from leglift to finish |99ms|99ms|99ms|

Both consumed pitch seeds271001/271002 show these values, but their pre-release commands, measured contractions, activations, labels and joint trajectories are exactly identical. They provide one preparatory trajectory, not two independent robustness tests. Quiet means RMS joint speed below0.1rad/s, sampled about every10ms; it is not a perceptual hitch judgment. Pitch-dependent contact quality changes in both directions across the two families. All runs complete7.8s without falling; full-motion peak force stays about3.576BW and peak loading remains roughly5,083–5,159BW/s. This supports a later matched fresh test of the existing preparatory integration, not a verified hitch fix or champion claim.

[Measured arm-speed figure](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_bat_prepare_prototype/preparation_speed.png), [source-pinned figure data](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_bat_prepare_prototype/preparation_speed.json), [quiet-interval locations](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_bat_prepare_prototype/quiet_locations.json).

Threshold sensitivity qualifies the observation: at0.125rad/s, arm stride quiet227.7ms becomes39.6ms for pure and108.9ms for temporal; at0.15rad/s,237.6ms becomes69.3ms for pure but remains237.6ms for temporal. The stride RMS joint acceleration increases from4.931 to5.567rad/s²(pure) or5.101rad/s²(temporal). Less quiet is not proof of smoother motion. Fresh pitch-only validation cannot establish robustness of identical pre-release motion. [Source-pinned sensitivity evidence](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_bat_prepare_prototype/preparation_sensitivity.json).


## In-control temporal-input clipping diagnosis

Six already-consumed baseline and untrained probe traces were analyzed offline; no rollout was added. The diagnostic reconstructs ball velocity from the saved 100 Hz joint positions and muscle derivatives from the saved 200 Hz measured contractions, then samples the declared 50 Hz temporal features. During the task-reported interval from right-hand release through control loss, ball-relative-x, ball-y, ball-z and horizontal-velocity inputs never exceed their clip limits in these six traces. Ball vertical velocity exceeds its limit on 2.5–7.6% of samples. Estimated muscle jerk exceeds its feature limit on 3.2–4.8%; contraction velocity and acceleration saturation remain below1.4%. Much of the high position clipping in whole-motion traces occurs after control is lost. This does not show that clipping causes performance limits; it makes broadening the frozen Round11 inputs a low-priority follow-up. Velocity is estimated from saved q, so these rates are approximate. Evidence: `out/competitor_dribble_fingers_prototype/feature_saturation_controlled_window.json`; script: `playground/gpt_finger_sensor_saturation.py`.

## Round 11: fingered crossover control (arena results and diagnostics)

Both frozen candidates completed the six-entry arena pass after exact local and main-incumbent replays. Neither qualifies for promotion against both frontiers.

**Design and budget.** Both challengers preserve the same fingered DribbleV3 contraction-keyframe backbone, quiet-trunk choreography, stance and drive gains. Pure search uses active-hand phase features; the temporal policy uses fixed causal convolutions over muscle-state and ball signals. Its zero-initialized readout adds bounded elbow, wrist, finger-MCP and finger-PIP offsets (0.18 / 0.15 / 0.20 / 0.20 rad) through existing geometry and spring filters; it does not output raw activations. Each family completed 4,096 recorded rollouts over 32 training starts and was frozen before 64 fresh validation starts per condition. The interrupted first temporal attempt has unknown unlogged overhead, so equal total attempted compute is not established.

**Fresh validation.** The table reports seven conditions over the same 64 fresh starts. All 448 runs completed without runtime errors, and every condition lost the ball on all 64 starts.

| Controller condition | Crossovers | Control, s | Runs ≥10 dribbles | Ball lost |
|---|---:|---:|---:|---:|
| Pure · selected | 2.7344 | 2.8289 | 0/64 | 64/64 |
| Pure · bias only | 4.0313 | 3.5328 | 5/64 | 64/64 |
| Pure · zero head | 3.5156 | 3.2530 | 4/64 | 64/64 |
| Temporal · selected | 5.2656 | 4.1958 | 11/64 | 64/64 |
| Temporal · bias only | 5.4844 | 4.2609 | 10/64 | 64/64 |
| Temporal · zero head | 4.6875 | 3.8233 | 10/64 | 64/64 |
| Common starting motion | 4.3594 | 3.6019 | 5/64 | 64/64 |

Temporal produced more crossovers and control time than pure on these held-out starts, with more measured body contacts (1.312 vs 0.781 per run). These finite transfer metrics do not establish sustained control.

**Dominant failure mode.** Two floor bounces without a touch account for 58/64 pure starts, 61/64 temporal starts and 57/64 common-start starts. The remaining selected runs bounced away from home, with maximum distances of 1.48 m (pure) and 1.19 m (temporal). Reliable recontact after a rebound remains a hypothesis from the observed loss reasons, not a result.

**Matched-start readout ablations.** On the same 64 fresh starts, zeroing the four global offsets in the frozen pure readout changed crossovers by +1.297 per run (paired bootstrap 95% interval +0.484 to +2.250) and control time by +0.704 s (+0.261 to +1.216); its catch-miss metric changed by -0.035 (-0.053 to -0.018). Zeroing the full pure head changed crossovers by +0.781 (+0.203 to +1.359) and control by +0.424 s (+0.098 to +0.750). Temporal mask intervals cover zero for the reported outcomes. These are 30,000-resample paired percentile bootstrap intervals, unadjusted across four comparisons. Masks were applied to frozen selected readouts and were not separately retrained; they are diagnostics, not arena results. A bias-free retraining run is a candidate follow-up, while rebound recontact remains a separate mechanism hypothesis.

**Thirty-second continuations.** These 24 runs also completed without errors. Pure averaged 2.500 crossovers and 2.800 seconds of control; temporal averaged 7.250 and 5.241; the common starting motion averaged 4.500 and 3.650. All three lost the ball on 8/8 starts. Movement after loss does not count as sustained control.

**Arena verdicts.** Six entries were scored on the three unchanged trials. The temporal candidate wins its local comparison on the 10-start crossover trial, but loses against the current main frontier; no candidate beats both frontiers.

| Trial | Family | Mean score | Local gain / p / win | Main gain / p / win |
|---|---|---:|---|---|
| Crossovers · 25 starts | Pure | 3.0800 | -6.0000 / 1.000 / no | -6.0000 / 1.000 / no |
| Crossovers · 25 starts | Temporal | 5.8800 | -3.2000 / 1.000 / no | -3.2000 / 1.000 / no |
| Crossovers · 10 starts | Pure | 3.3000 | -0.4000 / 0.821 / no | -4.0000 / 1.000 / no |
| Crossovers · 10 starts | Temporal | 6.7000 | +3.0000 / 0.016 / yes | -0.6000 / 0.608 / no |
| Arms-only penalty | Pure | 1.0000 | -0.8177 / 1.000 / no | -0.8177 / 1.000 / no |
| Arms-only penalty | Temporal | 0.9037 | -0.7214 / 0.999 / no | -0.7214 / 0.999 / no |

Paired gains are oriented so positive favors the challenger; p values use 4,000 sampled sign flips. The same-body temporal-versus-pure arena comparison favors temporal on both crossover trials, but the challenger still does not clear the updated main frontier. All 44 audit checks passed; no champion changed and no new champion video was produced. [Frozen protocol](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_dribble_round11/protocol.json), [arena summary](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_dribble_round11/arena_summary.json), [audit](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_dribble_round11/audit.json), [fresh validation summary](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_dribble_round11/validation_summary.json), and [recovery audit](/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/out/competitor_dribble_round11/recovery_20260929/recovery_audit.json) preserve the evidence and compute caveat.
