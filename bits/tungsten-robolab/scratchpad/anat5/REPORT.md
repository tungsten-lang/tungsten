# anat5 report: does the anatomy, not the controller, block the swing-leg fold?

Written 30 Sep 2026 from `scratchpad/anat5/LOG.md` (agent A5 measured everything below; its stream stalled before it could write a summary, so the main session wrote this one from the log; no number here is new).

## The question

Erik (29 Sep): why do our runners' trail-leg heels stay low (peak swing knee flexion about 98 deg, heel 0.35 m above the ground) while the Bolt reference folds to about 140 deg with the heel near the glute? A human mistake in our controllers, or something missing in the model, for example momentum?

## What was already known (`scratchpad/heel/LOG.md`)

Momentum and body mass ARE modelled: MuJoCo integrates rigid bodies with their inertia, and the series-elastic tendon force of the knee extensors acts at the knee. The v4 anatomy split makes the rectus femoris (rf, 150 N) 60 % of the hip flexion capacity and 34 % of the knee extension capacity.

## Findings

1. **The v4 split is stronger in the rectus femoris than the sources.** The rf share of hip flexion capacity is 19 to 41 % across OpenSim gait2392, Rajagopal 2016 and Arnold 2010 forces on the Rajagopal geometry (hip -20 to 60 deg, knee 90 deg); its share of knee extension is 15 to 22 % (capacity), 15 to 21 % (force), 15.7 % (PCSA, Ward 2009). The sources, moment-arm scripts and numbers are in `scratchpad/anat5/lit/` (`sources.json`, `moment_arms.py`, `osim_paths.py`; the downloaded model files are not to be committed).
2. **Two data-only bodies, no code change.** `playground/calibrations/v5.json` (rf 80, hip_flex_pos 170, knee_neg 286: keeps the joint totals) and `playground/calibrations/v5b.json` (rf 80, hip_flex_pos 170, knee_neg 230: the vasti unchanged, so the knee extension total falls 16 %). `playground/body.py` is untouched; the scene XML of 19 task/body combinations is byte-identical before and after (`identity_before.txt` against `identity_after.txt`); the v4 to v5 XML difference is 14 elements (v5b: 12).
3. **The champion runner does not survive v5, and survives v5b.** The unchanged sprint champion falls on v5 (0 of 12, 12.7 to 18.8 s) through a forward trunk-pitch runaway (touchdown pitch 0.17 to 0.49 rad over the run). The vasti are what break it: with the vasti unchanged (v5b) gear 3 of the champion survives 12 of 12 and 18 of 19 paired starts with no retuning.
4. **On v5b the same stride folds deeper and runs faster (no retuning).** Paired over the 40 unseen gear-2 flying starts both bodies survive (gear 3, 16 s): steady speed +0.183 m/s (CI95 +0.163 to +0.205), fold +15.2 deg (94.8 to 109.9; maximum 99 to 113), heel height at the fold +0.067 m (0.335 to 0.402), heel-to-hip distance -0.099 m, step frequency +0.20 per s, swing time -0.017 s. After 1000 rollouts of the same evolution search on each body (38 shared survivors): +0.295 m/s (CI95 +0.252 to +0.336), fold +12.7 deg. The control body (v4) gains only +0.05 to +0.08 m/s on unseen survivors over 5059 rollouts and pays with falls (8 seeds overfit); the v5b search was still climbing on its training seeds (282.9 to 291.5 at 1888 rollouts) while the control stalled at 283.8. A second control search seed (`es_v4_g3_s2`, finished at 1537 rollouts) agrees: it gained 2.8 points on its training seeds (277.76 to 280.56).
5. **The command does not set the fold.** Commanding the maximal follow-through (140 deg, `g3_k_fo` 1.65 + `g3_heel_tuck` 0.8) folds v4 to only about 101 deg on average (114 at most) and v5b to about 111 (121 at most), and costs speed on both (v4 7.82 to 7.03 m/s; v5b 7.99 to 6.63) until the gait is retuned to a higher cadence (4.5 to 4.7 per s) and a shorter swing (0.31 to 0.33 s).
6. **Knee-torque decomposition (v4 against v5b, per interval after toe-off):** the rf chain torque at the knee is -110 and -152 N m (0 to 30 and 30 to 60 ms) on v4 against -70 and -89 on v5b (-40 %); the vasti are recruited harder on v5b (-52 and -37 to -86 and -66), so the total extension pull falls by only about 35 N m in the 30 to 60 ms interval. Knee flexion 100 to 150 ms after toe-off is 68 deg on v4 and 56 deg on v5b (`decomp2.py`, `decomp_table.py`; sign convention in those scripts).

## Verdict

- **Erik's question:** part model, part controller, part physics. The model's rf strength is above the literature and does hold the heel down: with a literature-consistent split the same stride folds 13 to 15 deg deeper. It does not reach Bolt's 140 deg, because the achieved fold is not set by the command (item 5); Bolt-like heel recovery needs a retuned gait (cadence, swing time) on a body with this split, not only a stronger command.
- **GO as an opt-in labelled body.** `v5b` is a better-sourced body for the rectus femoris split and is data-only and identical for every other body. Use it only under its own name and never compare its scores with the v4 trials.
- **NO-GO as the default body or as a route to 10 m/s.** Every champion (sprint, long jump, hurdles, bat) is tuned on v4, and v5b breaks the sprint chain's start (below). Its measured gain is +0.2 to +0.3 m/s; the human-body ideal-control ceilings (P95 10.45 m/s) are what block 10 m/s, and the best measured human-body gait is 8.29 m/s.

## Caveats and costs

- v5b is the vasti-unchanged sibling, not the brief's totals-kept v5: its knee extension total is 16 % lower, which lowers the push-off and the ideal-control ceiling (v4.json: vasti x1.5 = +2 m/s of ceiling), so its advantage lives below the ceiling.
- The unchanged standing-start chain on v5b plateaus at 6.4 m/s in gear 1 (12 of 12 survive, peak 6.38): the start plan is tuned to the v4 knee extension total. Entering the later gears earlier (switch speeds -0.4 m/s) gives 4 of 6 survivors with peak 6.95; -0.8 m/s gives 1 of 6 with a peak of 8.385 m/s (steady 8.08, fold 106) and late falls at 17 to 20 s. So a full retune of the five-gear chain on v5b is needed to realise the gain, and its cost was not measured (the current chain took three sprint rounds on v4).
- More unseen falls on v5b after search (5 of 44 against 1 of 44 at 1000 rollouts).
- The long jump champion's take-off program (oracle-class, body-specific) does not transfer to either body without retuning (v5b: board foul, effective 2.85 m; v5: foul, 4.48 m against 5.28 m on v4): nothing to conclude about the jump itself. The run-up approach speed is within 1 % on both bodies.
- Dead tunables in the six-chunk stride (`k_syn`, `t_swing`, `k_trail`, `t_soft`, `t_kext`, `t_stance`, `t_drive`, `psi_drive`, `k_drive`, `t_kdur`, `t_step_min`): forcing them to extreme values gives bit-identical results; the live swing-recovery tunables are listed in `LOG.md` (23:58).
- Not run: the totals-kept v5 arm (C) and the gear-4 stage pair, cut for machine time (load 26 to 58 from other jobs made the search run at 0.1 to 0.7 rollouts per second).

## Files

- `LOG.md` (all measurements with clock times), `identity_before.txt` / `identity_after.txt` (+ `_files`), `xml_diff.py`, `make_v5.py`, `make_v5b.py`, `gait_probe.py`, `snap5.py`, `es5.sh`, `queue.sh`, `decomp2.py`, `decomp_table.py`, `bodytry.sh`, `bodytry2.sh`, `vonshift.py`, `lj_check.py`, `ckpt.py`, `params/` (start files), `out/` (probe outputs), `es_*` (search logs, archives and best parameters).
- Bodies: `playground/calibrations/v5.json`, `playground/calibrations/v5b.json` (select with `ROBOLAB_BODY=v4 ROBOLAB_CALIB=v5b`).

## Update, 30 Sep (later): second seeds, validated on the 44 unseen starts

The two arms queue5 never reached were run once the machine was quiet (`queue6.txt`: v5b seed 2, v5 seed 1), and the final incumbents were validated with A5's own protocol (`eval_final.sh`: the 44 UNSEEN v4 gear-2 flying starts `run_v4_a5x`, 16 s, tail from 8 s; `abtable.py`; table in `ab_final_table.txt`). Training-seed scores (8 flying starts, pace): v4 control 277.8 to 283.8 (seed 1, 5059 rollouts) and 277.8 to 280.6 (seed 2, 1537); v5b 282.9 to 302.4 (seed 1, 2758) and 282.9 to 298.8 (seed 2, 1534).

| arm (final incumbent, unseen starts) | falls of 44 | steady m/s | fold deg | heel at the fold | step m |
| --- | --- | --- | --- | --- | --- |
| A1, v4 control, seed 1, 5059 rollouts | 8 | 7.863 | 96.0 | 0.342 m | 1.96 |
| A2, v4 control, seed 2, 1537 rollouts | 5 | 7.858 | 94.2 | 0.323 m | 1.91 |
| B1, v5b, seed 1, 2758 rollouts | 1 | 8.549 | 99.0 | 0.372 m | 2.12 |
| B2, v5b, seed 2, 1534 rollouts | 3 | 8.442 | 100.8 | 0.392 m | 2.07 |

Paired over the starts both arms survive: B1 against A1 (35 starts) steady +0.679 m/s (CI95 +0.613 to +0.757), fold +3.1 deg, gain in the first 0.1 s +8.6 deg, heel height at the fold +3.1 cm; B2 against A2 (37 starts, equal budget) steady +0.586 m/s (CI95 +0.569 to +0.604), fold +6.5 deg, gain +5.9 deg, heel height +6.9 cm.

- The speed gain replicates on both seeds and is larger after search (+0.6 to +0.7 m/s) than the unretuned stride's +0.18 and the 1000-rollout +0.30. The fold gain does not grow with it (+3 to +6.5 deg after search, against +15 deg unretuned): once the search is free to use the new hip-flexion power it buys a longer step (2.07-2.12 m against 1.91-1.96 m) rather than a deeper fold, with cadence unchanged (4.15-4.23 touchdowns/s).
- Still one stage (gear 3 from gear-2 flying starts, 16 s) on two search seeds, and a labelled body: a full sprint needs the five-gear chain retuned on it (its standing start plateaus at 6.4 m/s unretuned), so this does not move the 10 m/s question by itself. It does change the answer to "are our models missing something": with a literature-consistent rectus femoris the same search finds a stride about 0.6 m/s faster with fewer falls.
- The totals-kept v5 arm (seed 1, `es_v5_g3_s1`, 1522 rollouts) climbed from its repaired start (251.0 on the training seeds) to 293.2, above every v4 control. Validated on v5's own 44 unseen starts (`eval_final_v5.sh`, `C1_final_v5_a5x`; its baseline start row is `g3start_v5_a5x`): steady speed 7.00 to 8.34 m/s (survivors), step 1.68 to 1.94 m, fold 109.5 to 101.2 deg, but 12 of 44 starts fall (5 before the search): faster but less robust than v5b (1 and 3 falls) and the v4 controls (8 and 5), i.e. it overfits its 8 training starts. The start sets differ from the v4 and v5b ones, so this row is not paired with them; more search seeds or training starts would be needed before calling the totals-kept body as good as v5b.
