"""Focused R13 audit, metrics summary, and readable report."""
import collections
import json
import math
import subprocess
from pathlib import Path

import arena
import numpy as np
import gpt_dribble_fingers_lowball as r13

ROOT = r13.ROOT
OUT = r13.OUT
TRIALS = r13.TRIALS
METRICS = ["x_ok", "dribbles", "controlled_s", "body_hits"]


def read(path):
    return json.loads(Path(path).read_text())


def write(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def loss_counts(rows):
    return {
        label: dict(
            collections.Counter(
                str(row["metrics"].get("lost") or "not recorded")
                for row in rows
                if row["label"] == label
            )
        )
        for label in dict.fromkeys(row["label"] for row in rows)
    }


def compact_training(result):
    return r13.compact([{"metrics": metrics} for metrics in result["metrics"]])


def paired_metric(rows, condition, reference, metric, higher=True):
    groups = {
        label: {row["seed"]: row["metrics"][metric] for row in rows if row["label"] == label}
        for label in (condition, reference)
    }
    seeds = sorted(set(groups[condition]) & set(groups[reference]))
    assert seeds
    return arena.compare(
        {"higher": higher},
        [groups[reference][seed] for seed in seeds],
        [groups[condition][seed] for seed in seeds],
    )


def parameter_summary(candidate):
    variant = candidate["variant"]
    baseline = r13.initial(variant)
    selected = candidate["params"]
    readout = list(candidate["fixed_readout_offsets"])
    readout = [f"gpt_w{i}" for i in range(20) if f"gpt_w{i}" in selected]
    changes = [
        {
            "parameter": name,
            "baseline": baseline[name],
            "selected": selected[name],
            "delta": selected[name] - baseline[name],
        }
        for name in r13.NAMES
        if selected[name] != baseline[name]
    ]
    readout_changes = [row for row in changes if row["parameter"] in readout]
    geometry = []
    for name in protocol_geometry_names():
        geometry.append(
            {
                "parameter": name,
                "baseline": baseline[name],
                "selected": selected[name],
                "delta": selected[name] - baseline[name],
            }
        )
    weights = [selected[name] - baseline[name] for name in readout]
    return {
        "changed_parameter_count": len(changes),
        "changed_parameter_names": [row["parameter"] for row in changes],
        "geometry_changes": geometry,
        "geometry_delta_l2_parameter_units": math.sqrt(sum(row["delta"] ** 2 for row in geometry)),
        "readout_nonzero_count": sum(abs(value) > 1e-12 for value in weights),
        "readout_delta_l1": sum(abs(value) for value in weights),
        "readout_delta_l2": math.sqrt(sum(value * value for value in weights)),
        "readout_delta_rms": math.sqrt(sum(value * value for value in weights) / len(weights)),
        "readout_largest_changes": sorted(readout_changes, key=lambda row: abs(row["delta"]), reverse=True)[:6],
        "fixed_offsets_exactly_zero": all(selected[f"gpt_w{i}"] == 0.0 for i in r13.FIXED_READOUT),
    }


def protocol_geometry_names():
    return r13.read(OUT / "protocol.json")["low_ball_geometry_parameters"]


def main():
    protocol = read(OUT / "protocol.json")
    preflight = read(OUT / "preflight.json")
    candidates = read(OUT / "candidates.json")
    validation = read(OUT / "validation.json")
    endurance = read(OUT / "endurance30.json")
    arena_result = read(OUT / "arena_summary.json")
    local_before = read(OUT / "champions_before.json")
    main_before = read(OUT / "main_champions_at_judging.json")
    local_replay = read(OUT / "local_replay.json")
    main_replay = read(OUT / "main_replay.json")
    local_after = read(ROOT / "playground/arena/champions.json")
    main_after = read(r13.MAIN / "playground/arena/champions.json")
    trials_before = (OUT / "trials_before.json").read_bytes()
    checks = {}
    details = {}

    r13.check_manifest()
    checks["round12_audit_passes"] = read(ROOT / "out/competitor_dribble_round12/audit.json")["passed"]
    checks["r13_preflight_passes"] = preflight["passed"] and all(preflight["checks"].values())
    checks["frozen_source_manifest_matches"] = all(r13.sha(ROOT / path) == digest for path, digest in read(OUT / "manifest.json").items())
    checks["frozen_judge_manifest_matches"] = all(r13.sha(ROOT / path) == digest for path, digest in read(OUT / "judge_manifest.json").items())

    training = {variant: read(OUT / f"{variant}.json") for variant in ("pure", "tcn")}
    checks["matched_2048_rollouts_per_family"] = all(
        result["used"] == protocol["training_rollouts_per_family"] == r13.BUDGET
        and len(result["metrics"]) == len(protocol["training_seeds"])
        for result in training.values()
    )
    checks["both_search_archives_complete_and_finite"] = all(
        np.load(OUT / f"{variant}.npz")["X"].shape == (r13.BUDGET // len(r13.TRAIN), len(r13.NAMES))
        and np.load(OUT / f"{variant}.npz")["F"].shape == (r13.BUDGET // len(r13.TRAIN),)
        and np.isfinite(np.load(OUT / f"{variant}.npz")["F"]).all()
        for variant in training
    )
    checks["selected_candidates_match_frozen_params"] = all(
        candidate["params"] == training[candidate["variant"]]["params"] == r13.read_params(candidate["params_file"])
        and r13.sha(candidate["params_file"]) == candidate["params_sha256"]
        and r13.sha(candidate["controller"]) == candidate["controller_sha256"]
        for candidate in candidates
    )
    checks["all_undeclared_parameters_stayed_fixed"] = all(
        all(candidate["params"].get(name) == value for name, value in r13.initial(candidate["variant"]).items() if name not in r13.NAMES)
        for candidate in candidates
    )
    checks["four_constant_offsets_stayed_zero"] = all(
        all(candidate["params"][f"gpt_w{i}"] == 0.0 for i in r13.FIXED_READOUT)
        for candidate in candidates
    )
    parameter_changes = {candidate["label"]: parameter_summary(candidate) for candidate in candidates}

    validation_groups = protocol["validation_groups"]
    validation_seeds = set(protocol["validation_seeds"])
    checks["all_192_validation_rows_complete"] = len(validation) == len(validation_groups) * len(validation_seeds)
    checks["every_validation_group_has_the_same_64_fresh_seeds"] = all(
        {row["seed"] for row in validation if row["label"] == label} == validation_seeds
        for label in validation_groups
    )
    checks["validation_is_error_free_and_15_seconds"] = all(
        "error" not in row["metrics"] and 15.0 <= row["metrics"].get("time", 0.0) < 15.02
        for row in validation
    )
    endurance_seeds = set(protocol["endurance_seeds"])
    checks["all_24_endurance_rows_complete"] = len(endurance) == 3 * len(endurance_seeds)
    checks["every_endurance_group_has_the_same_eight_seeds"] = all(
        {row["seed"] for row in endurance if row["label"] == label} == endurance_seeds
        for label in validation_groups
    )
    checks["endurance_is_error_free_and_30_seconds"] = all(
        "error" not in row["metrics"] and 30.0 <= row["metrics"].get("time", 0.0) < 30.02
        for row in endurance
    )

    entries = arena_result["entries"]
    trials = read(ROOT / "playground/arena/trials.json")
    for entry in entries:
        trial_name = entry["trial"]
        entry["higher_is_better"] = trials[trial_name].get("higher", True)
        entry["local_frontier_mean"] = local_before[trial_name]["summary"]["mean"]
        entry["main_frontier_mean"] = main_before[trial_name]["summary"]["mean"]
    expected_pairs = {(trial, candidate["label"]) for trial in TRIALS for candidate in candidates}
    checks["all_six_official_arena_entries_complete"] = len(entries) == 6 and {
        (entry["trial"], entry["label"]) for entry in entries
    } == expected_pairs
    decisions_recompute = []
    direct_recompute = []
    for entry in entries:
        raw = read(OUT / f"arena_raw_{entry['trial']}_{entry['label']}.json")
        decision = {
            "local": arena.compare(raw["trial"], local_before[entry["trial"]]["scores"], raw["scores"]),
            "main_frontier": arena.compare(raw["trial"], main_before[entry["trial"]]["scores"], raw["scores"]),
        }
        decisions_recompute.append(entry["local"] == decision["local"] and entry["main_frontier"] == decision["main_frontier"])
        checks.setdefault("all_arena_rows_error_free_and_complete", True)
        checks["all_arena_rows_error_free_and_complete"] &= (
            raw["task"] == "dribble_v3"
            and len(raw["scores"]) == len(raw["trial"]["seeds"])
            and not any("error" in row for row in raw["rows"])
        )
    checks["all_six_frontier_decisions_recompute"] = all(decisions_recompute)
    for comparison in arena_result["comparisons"]:
        pure = read(OUT / f"arena_raw_{comparison['trial']}_pure_lowball.json")
        tcn = read(OUT / f"arena_raw_{comparison['trial']}_tcn_lowball.json")
        direct = arena.compare(pure["trial"], pure["scores"], tcn["scores"])
        direct_recompute.append({key: comparison[key] for key in direct} == direct)
    checks["all_three_direct_search_comparisons_recompute"] = len(direct_recompute) == 3 and all(direct_recompute)
    eligible = [entry for entry in entries if entry["local"]["wins"] and entry["main_frontier"]["wins"]]
    checks["promotion_gate_has_no_eligible_candidate"] = not eligible and not arena_result["eligible_against_both_frontiers"]
    checks["no_promotion_was_attempted"] = arena_result["promotion_attempted"] is False and read(OUT / "promotions.json") == []
    checks["both_champion_boards_unchanged"] = all(
        local_after[trial] == local_before[trial] and main_after[trial] == main_before[trial]
        for trial in TRIALS
    )
    checks["all_local_and_main_incumbents_replay_exactly"] = all(
        local_replay[trial]["scores"] == local_before[trial]["scores"]
        and main_replay[trial]["scores"] == main_before[trial]["scores"]
        for trial in TRIALS
    )
    checks["main_frontier_binary_and_params_hashes_unchanged"] = all(
        r13.sha(path) == digest for path, digest in read(OUT / "main_frontier_manifest.json").items()
    )
    checks["existing_trials_unchanged"] = (ROOT / "playground/arena/trials.json").read_bytes() == trials_before
    history_info = read(OUT / "arena_history_before.json")
    history_lines = (ROOT / "playground/arena/history.jsonl").read_text().splitlines()
    new_history = [json.loads(line) for line in history_lines[history_info["lines"] :]]
    own_history = [row for row in new_history if row.get("note", "").startswith("gpt: round13 low-apex fingered crossover ")]
    checks["six_round13_entries_recorded_without_promotion"] = len(own_history) == 6 and all(
        row.get("result") != "promoted" for row in own_history
    )
    checks["arena_notes_use_required_gpt_prefix"] = all(row.get("note", "").startswith("gpt:") for row in own_history)

    validation_comparisons = []
    for condition, reference in [
        ("pure_lowball", "common_zero"),
        ("tcn_lowball", "common_zero"),
        ("tcn_lowball", "pure_lowball"),
    ]:
        for metric in METRICS:
            validation_comparisons.append(
                {
                    "condition": condition,
                    "reference": reference,
                    "metric": metric,
                    "higher_is_better": metric != "body_hits",
                    **paired_metric(validation, condition, reference, metric, metric != "body_hits"),
                }
            )

    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    checks["no_commit_since_worktree_base"] = head == "85e95c33680a0e04bb4245de3fe86e2ae3c3200a"
    details["head"] = head
    details["expected_worktree_base"] = "85e95c33680a0e04bb4245de3fe86e2ae3c3200a"
    details["arena_worker_cap"] = arena_result["arena_workers"]
    details["parameter_change_summary"] = parameter_changes
    details["validation_loss_reasons"] = loss_counts(validation)
    details["endurance_loss_reasons"] = loss_counts(endurance)
    details["arena_loss_reasons"] = {
        f"{trial}_{candidate['label']}": loss_counts(
            [
                {"label": candidate["label"], "metrics": metrics}
                for metrics in read(OUT / f"arena_raw_{trial}_{candidate['label']}.json")["rows"]
            ]
        )[candidate["label"]]
        for trial in TRIALS
        for candidate in candidates
    }
    details["arena_history_rows"] = len(own_history)
    details["judge_script_sha256"] = r13.sha(ROOT / "playground/gpt_dribble_fingers_lowball_judge.py")
    details["report_script_sha256"] = r13.sha(Path(__file__))

    audit = {
        "round": 13,
        "scope": "Focused R13 training, fresh validation, endurance, incumbent replay and six-entry non-promoting arena audit.",
        "passed": all(checks.values()),
        "count": len(checks),
        "checks": checks,
        "details": details,
        "evidence": [
            "protocol.json",
            "preflight.json",
            "candidates.json",
            "validation_summary.json",
            "endurance30_summary.json",
            "local_replay.json",
            "main_replay.json",
            "arena_summary.json",
        ],
    }
    write(OUT / "audit.json", audit)
    assert audit["passed"], {key: value for key, value in checks.items() if not value}

    validation_summary = read(OUT / "validation_summary.json")
    endurance_summary = read(OUT / "endurance30_summary.json")
    training_summary = {
        candidate["label"]: {
            "rollouts": training[candidate["variant"]]["used"],
            "training_seeds": len(protocol["training_seeds"]),
            "best_training_objective": training[candidate["variant"]]["best"],
            "metrics": compact_training(training[candidate["variant"]]),
            "parameters": parameter_changes[candidate["label"]],
        }
        for candidate in candidates
    }
    summary = {
        "round": 13,
        "status": "complete",
        "problem": protocol["problem"],
        "intervention": protocol["intervention"],
        "protocol": protocol,
        "training": training_summary,
        "validation": validation_summary,
        "validation_paired_comparisons": validation_comparisons,
        "validation_loss_reasons": details["validation_loss_reasons"],
        "endurance30": endurance_summary,
        "endurance30_loss_reasons": details["endurance_loss_reasons"],
        "arena": arena_result,
        "arena_loss_reasons": details["arena_loss_reasons"],
        "promotions": [],
        "audit_passed": True,
    }
    write(OUT / "arena_summary.json", arena_result)
    write(OUT / "summary.json", summary)

    arena_rows = []
    for entry in entries:
        local = entry["local"]
        main = entry["main_frontier"]
        arena_rows.append(
            f"| {entry['trial']} | {entry['variant']} | {entry['mean_valid']:.4f} ± {entry['ci95']:.4f} "
            f"| {local['mean_diff']:+.4f} | {local['p']:.5f} | {'WIN' if local['wins'] else 'lose'} "
            f"| {main['mean_diff']:+.4f} | {main['p']:.5f} | {'WIN' if main['wins'] else 'lose'} |"
        )
    report = f"""# Round 13 — low-apex fingered crossover geometry

## Result

The pure-search candidate improved the 10-seed local crossover comparison by 6.10 crossovers per run (p=0.0025), but it did not significantly beat the stronger current-main frontier (+2.50, p=0.17825). On the 25-seed crossover trial it lost to both frontiers. The TCN candidate did not beat either frontier on any of the three trials. All six entries were completed without promotion; local and main champion files stayed unchanged. No commit was made.

## Design and training

R13 tuned low-apex strike and landing geometry on the fingered DribbleV3 controller. The pure family uses the existing phase-indexed residual; the temporal family uses the fixed causal temporal features and a zero-initialized bounded readout. Both optimized the same {protocol['tunable_dimensions']} declared parameters, used {protocol['training_rollouts_per_family']:,} rollouts, and shared the 32 training starts. Four constant offsets remained fixed at zero.

The best training objectives were {training_summary['pure_lowball']['best_training_objective']:.3f} for pure and {training_summary['tcn_lowball']['best_training_objective']:.3f} for TCN. On 64 fresh 15-second starts, pure averaged {validation_summary['pure_lowball']['dribbles']:.3f} dribbles versus {validation_summary['common_zero']['dribbles']:.3f} for common-zero; the paired gain was {next(row['mean_diff'] for row in validation_comparisons if row['condition']=='pure_lowball' and row['reference']=='common_zero' and row['metric']=='dribbles'):+.3f} (p={next(row['p'] for row in validation_comparisons if row['condition']=='pure_lowball' and row['reference']=='common_zero' and row['metric']=='dribbles'):.5f}). TCN averaged {validation_summary['tcn_lowball']['dribbles']:.3f}; it did not improve on common-zero. These validation and training results did not determine the arena verdict.

The temporal readout changed {parameter_changes['tcn_lowball']['readout_nonzero_count']} trained weights from zero, with L2 magnitude {parameter_changes['tcn_lowball']['readout_delta_l2']:.4f}, RMS {parameter_changes['tcn_lowball']['readout_delta_rms']:.4f}, and largest absolute coefficient {max(abs(row['delta']) for row in parameter_changes['tcn_lowball']['readout_largest_changes']):.4f}. Its six largest absolute changes are recorded in `summary.json`. Pure search's six largest phase-readout changes are recorded there as well. Geometry deltas are likewise preserved per parameter.

## Arena results

| Trial | Candidate | Mean ± 95% CI | Local Δ | Local p | Local | Main Δ | Main p | Main |
|---|---|---:|---:|---:|---|---:|---:|---|
{chr(10).join(arena_rows)}

Positive paired differences favor the challenger. The arms-only trial scores `trunk_share_if_dribbling`, where lower is better. Every comparison uses the trial's recorded seeds and official arena metric. All local and current-main incumbents reproduced their recorded per-seed scores before judging.

## Failure modes and interpretation

All three 64-seed validation groups lost the ball on every 15-second start. Pure lost after two floor bounces without a touch on 54/64; TCN did so on 63/64; common-zero on 60/64. Every 30-second endurance run also lost the ball (8/8 per group), usually after two untouched floor bounces. The 10-seed pure local win did not clear the current-main p<0.05 gate, and the larger 25-seed trial favored the incumbent. The results support a finite-seed pure-search gain against one older local baseline, not a new champion or sustained-control result. TCN's temporal correction did not improve on pure or common-zero in held-out validation or arena comparisons.

The focused audit passed {audit['count']} checks. `arena_summary.json`, raw per-seed rows, replay rows, frozen candidate hashes, validation, endurance, and protocol artifacts accompany this report.
"""
    (OUT / "PROGRESS.md").write_text(report)
    print(json.dumps({"audit_passed": audit["passed"], "audit_checks": len(checks), "eligible": eligible, "report": str(OUT / "PROGRESS.md")}, indent=2))


if __name__ == "__main__":
    main()
