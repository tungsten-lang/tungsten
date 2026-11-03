"""Judge the frozen Round 13 fingered low-ball challengers without promotion."""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

import arena
import gpt_dribble_fingers_lowball as r13

ROOT = r13.ROOT
OUT = r13.OUT
MAIN = r13.MAIN
TRIALS = r13.TRIALS
ARENA_WORKERS = 2


def file_sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def snapshot_frontier(champions, root):
    files = {}
    for trial in TRIALS:
        entry = champions[trial]
        for key in ("frozen_controller", "frozen_params"):
            path = Path(root) / entry[key]
            files[str(path)] = file_sha(path)
    return files


def run_replays(champions, root, trials, label):
    result = {}
    for trial_name in TRIALS:
        entry = champions[trial_name]
        trial = trials[trial_name]
        rows, scores = arena.evaluate(
            trial,
            arena.read_params(str(Path(root) / entry["frozen_params"])),
            str(Path(root) / entry["frozen_controller"]),
            entry["task"],
            ARENA_WORKERS,
        )
        assert scores == entry["scores"], f"{label} incumbent drift: {trial_name}"
        result[trial_name] = {"exact": True, "scores": scores, "rows": rows, "trial": trial}
        print(f"{label} exact replay {trial_name}", flush=True)
    return result


def invoke_arena(trial, candidate, artifact, log):
    note = (
        f"gpt: round13 low-apex fingered crossover {candidate['label']}; "
        "frozen after matched 2048-rollout search and 64 untouched validations"
    )
    command = [
        sys.executable,
        "playground/gpt_arena_entry.py",
        "--artifact",
        str(artifact),
        "eval",
        trial,
        "--params",
        candidate["params_file"],
        "--controller",
        candidate["controller"],
        "--task",
        "dribble_v3",
        "--note",
        note,
        "--workers",
        str(ARENA_WORKERS),
    ]
    with (OUT / log).open("w") as stream:
        subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, check=True)


def main():
    assert not (OUT / "arena_summary.json").exists(), "Never duplicate a completed judging round"
    r13.check_manifest()
    for path, digest in r13.read(OUT / "judge_manifest.json").items():
        assert r13.sha(ROOT / path) == digest, path

    protocol = r13.read(OUT / "protocol.json")
    preflight = r13.read(OUT / "preflight.json")
    candidates = r13.read(OUT / "candidates.json")
    assert preflight["passed"]
    assert {candidate["label"] for candidate in candidates} == {"pure_lowball", "tcn_lowball"}
    for candidate in candidates:
        variant = candidate["variant"]
        training = r13.read(OUT / f"{variant}.json")
        assert training["used"] == protocol["training_rollouts_per_family"]
        assert r13.sha(candidate["params_file"]) == candidate["params_sha256"]
        assert r13.sha(candidate["controller"]) == candidate["controller_sha256"]
        assert candidate["params"] == training["params"]
        assert r13.read_params(candidate["params_file"]) == candidate["params"]

    validation = r13.read(OUT / "validation.json")
    groups = protocol["validation_groups"]
    seeds = set(protocol["validation_seeds"])
    assert len(validation) == len(groups) * len(seeds)
    assert all("error" not in row["metrics"] for row in validation)
    assert all({row["seed"] for row in validation if row["label"] == group} == seeds for group in groups)
    endurance = r13.read(OUT / "endurance30.json")
    expected_endurance_seeds = set(protocol["endurance_seeds"])
    assert len(endurance) == 3 * len(expected_endurance_seeds)
    assert all("error" not in row["metrics"] for row in endurance)
    assert all(
        {row["seed"] for row in endurance if row["label"] == group} == expected_endurance_seeds
        for group in groups
    )

    local_trials_path = ROOT / "playground/arena/trials.json"
    main_trials_path = MAIN / "playground/arena/trials.json"
    assert local_trials_path.read_bytes() == (OUT / "trials_before.json").read_bytes()
    trials = r13.read(local_trials_path)
    main_trials = r13.read(main_trials_path)
    assert all(trials[name] == main_trials[name] for name in TRIALS)

    local_path = ROOT / "playground/arena/champions.json"
    main_path = MAIN / "playground/arena/champions.json"
    local_before = r13.read(local_path)
    main_before = r13.read(main_path)
    r13.write("champions_before.json", local_before)
    r13.write("main_champions_at_judging.json", main_before)
    frontier_hashes = snapshot_frontier(main_before, MAIN)
    r13.write("main_frontier_manifest.json", frontier_hashes)

    history_path = ROOT / "playground/arena/history.jsonl"
    history_before = history_path.read_bytes() if history_path.exists() else b""
    history_before_lines = len(history_before.splitlines())
    r13.write(
        "arena_history_before.json",
        {"sha256": hashlib.sha256(history_before).hexdigest(), "lines": history_before_lines},
    )

    local_replay = run_replays(local_before, ROOT, trials, "Local")
    main_replay = run_replays(main_before, MAIN, trials, "Main")
    r13.write("local_replay.json", local_replay)
    r13.write("main_replay.json", main_replay)

    records = {}
    entries = []
    comparisons = []
    for trial_name in TRIALS:
        records[trial_name] = {}
        for candidate in candidates:
            artifact = OUT / f"arena_raw_{trial_name}_{candidate['label']}.json"
            log = f"arena_{trial_name}_{candidate['label']}.log"
            assert not artifact.exists(), f"Arena artifact already exists: {artifact.name}"
            invoke_arena(trial_name, candidate, artifact, log)
            result = r13.read(artifact)
            assert result["task"] == "dribble_v3"
            assert len(result["scores"]) == len(trials[trial_name]["seeds"])
            assert len(result["rows"]) == len(result["scores"])
            assert not any("error" in metrics for metrics in result["rows"])
            records[trial_name][candidate["label"]] = result

            valid_scores = [score for score in result["scores"] if abs(score) < 1e8]
            row = {
                "trial": trial_name,
                "label": candidate["label"],
                "variant": candidate["variant"],
                "metric": trials[trial_name]["metric"],
                "n": len(result["scores"]),
                "passes": len(valid_scores),
                "mean_valid": sum(valid_scores) / len(valid_scores) if valid_scores else None,
                "mean_guard_coded": sum(result["scores"]) / len(result["scores"]),
                "ci95": arena.summary(valid_scores)["ci95"] if valid_scores else None,
                "local": arena.compare(trials[trial_name], local_before[trial_name]["scores"], result["scores"]),
                "main_frontier": arena.compare(trials[trial_name], main_before[trial_name]["scores"], result["scores"]),
                "params_sha256": candidate["params_sha256"],
                "controller_sha256": candidate["controller_sha256"],
            }
            entries.append(row)
            print(json.dumps(row), flush=True)

        pure = records[trial_name]["pure_lowball"]
        tcn = records[trial_name]["tcn_lowball"]
        comparisons.append(
            {
                "trial": trial_name,
                "comparison": "tcn_lowball minus pure_lowball",
                **arena.compare(trials[trial_name], pure["scores"], tcn["scores"]),
            }
        )

    local_after = r13.read(local_path)
    main_after = r13.read(main_path)
    assert all(local_after[name] == local_before[name] for name in TRIALS), "Local champion changed"
    assert all(main_after[name] == main_before[name] for name in TRIALS), "Main champion changed"
    assert snapshot_frontier(main_after, MAIN) == frontier_hashes, "Main frontier binary/params changed"
    assert local_trials_path.read_bytes() == (OUT / "trials_before.json").read_bytes()

    history_after = history_path.read_text().splitlines()
    new_lines = [json.loads(line) for line in history_after[history_before_lines:]]
    round13_history = [
        row
        for row in new_lines
        if row.get("note", "").startswith("gpt: round13 low-apex fingered crossover ")
    ]
    assert len(round13_history) == 6, f"Expected six append-only arena entries, found {len(round13_history)}"
    assert all("promote" not in row.get("note", "").lower() for row in round13_history)

    eligible = [row for row in entries if row["local"]["wins"] and row["main_frontier"]["wins"]]
    summary = {
        "round": 13,
        "status": "complete",
        "task": "dribble_v3",
        "arena_workers": ARENA_WORKERS,
        "entries": entries,
        "comparisons": comparisons,
        "eligible_against_both_frontiers": eligible,
        "promotion_attempted": False,
        "champions_unchanged": True,
        "trials_unchanged": True,
        "local_replays_exact": True,
        "main_replays_exact": True,
        "main_frontier_manifest": "main_frontier_manifest.json",
        "main_frontier_file_hashes": frontier_hashes,
        "history_before": r13.read(OUT / "arena_history_before.json"),
        "history_added_entries": len(round13_history),
    }
    r13.write("arena_summary.json", summary)
    r13.write("promotions.json", [])
    r13.write(
        "pipeline_state.json",
        {"state": "arena_complete", "entries": 6, "promotion_attempted": False},
    )
    print(json.dumps({"entries": entries, "comparisons": comparisons, "eligible": eligible}, indent=2))


if __name__ == "__main__":
    main()
