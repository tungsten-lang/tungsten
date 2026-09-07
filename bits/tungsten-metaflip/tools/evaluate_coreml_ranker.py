#!/usr/bin/env python3
"""Evaluate actual Core ML scores on every held-out origin, without training.

This explicit CPU-only fallback is not Neural Engine offload and does not
establish a fleet throughput or record benefit. Two requests cover the full
72-row default holdout; each request contains at most 64 genuine candidates.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import time

from train_coreml_ranker import FEATURES, evaluate, forward, grouped_split, load_dataset, np


def tree_sha256(directory):
    digest = hashlib.sha256()
    for path in sorted(directory.rglob("*")):
        if path.is_file():
            digest.update(str(path.relative_to(directory)).encode() + b"\0")
            digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def run_helper(command, requests, timeout):
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
    started = time.monotonic()
    try:
        out, err = process.communicate(requests, timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise RuntimeError("Core ML helper exceeded the bounded evaluation deadline")
    return process.returncode, out, err, time.monotonic() - started


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", type=Path, required=True)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--compiled-model", type=Path, required=True)
    parser.add_argument("--helper", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--timeout", type=float, default=15)
    parser.add_argument("--parity-tolerance", type=float, default=0.02)
    args = parser.parse_args()
    if not 0 < args.timeout <= 30 or not 0 < args.parity_tolerance <= 0.1:
        parser.error("timeout must be 0..30 seconds and parity tolerance 0..0.1")
    evidence = json.loads((args.model_dir / "evaluation.json").read_text())
    dataset_sha = hashlib.sha256(args.dataset.read_bytes()).hexdigest()
    if evidence["dataset_sha256"] != dataset_sha or evidence["feature_names"] != FEATURES:
        raise ValueError("Reference model evidence does not match this dataset/feature contract")
    metadata, rows = load_dataset(args.dataset)
    split, groups = grouped_split(rows, evidence["seed"])
    test = split["test"]
    if [rows[i]["candidate_id"] for i in test] != evidence["splits"]["test"]["candidate_ids"]:
        raise ValueError("Held-out origin/basin membership changed")
    raw = np.array([row["features"] for row in rows], np.float32)
    with np.load(args.model_dir / "weights.npz", allow_pickle=False) as saved:
        weights = {key: saved[key].copy() for key in ("w1", "b1", "w2", "b2", "w3", "b3")}
        reference = forward((raw - saved["mean"]) / saved["scale"], weights)[0][:, 0]
    requests = []
    batches = {}
    for begin in range(0, len(test), 64):
        identity = f"actual-heldout-{begin // 64}"
        indices = test[begin:begin + 64]
        batches[identity] = indices
        requests.append({"id": identity, "rows": raw[indices].tolist()})
    body = "".join(json.dumps(request) + "\n" for request in requests)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    (args.out_dir / "requests.jsonl").write_text(body)
    command = [str(args.helper), "--model", str(args.compiled_model), "--jsonl", "--compute", "cpuOnly", "--workers", "1"]
    code, stdout, stderr, elapsed = run_helper(command, body, args.timeout)
    (args.out_dir / "responses.jsonl").write_text(stdout)
    (args.out_dir / "events.jsonl").write_text(stderr)
    if code != 0:
        raise RuntimeError(f"Core ML helper failed ({code}); see saved events.jsonl")
    events = []
    for line in stderr.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(event, dict):
            events.append(event)
    ready = [event for event in events if event.get("event") == "ready"]
    if len(ready) != 1:
        raise ValueError("Expected exactly one checked Core ML ready event")
    ready = ready[0]
    placement = ready.get("placement", {})
    if ready.get("compute") != "cpuOnly" or ready.get("anePlacementVerified") is not False or placement.get("preferredNeuralEngine") != 0 or placement.get("preferredGPU") != 0 or placement.get("preferredCPU", 0) < 1 or ready.get("featureNames") != FEATURES or ready.get("preprocessWorkers") != 1:
        raise ValueError("CPU-only placement/feature/thread contract was not confirmed")
    actual = np.full(len(rows), np.nan, np.float64)
    seen = set()
    for line in stdout.splitlines():
        response = json.loads(line)
        identity = response.get("id")
        if identity not in batches or identity in seen or response.get("ok") is not True or response.get("op") != "score":
            raise ValueError("Unknown, repeated, failed, or malformed response id")
        seen.add(identity)
        scores = response.get("scores", [])
        indices = batches[identity]
        if len(scores) != len(indices) or any(not isinstance(score, (int, float)) or not math.isfinite(score) or not -1e9 < score < 1e9 for score in scores):
            raise ValueError("Nonfinite, missing, extra, or out-of-range Core ML score")
        actual[indices] = scores
    if seen != set(batches) or not np.isfinite(actual[test]).all():
        raise ValueError("Core ML did not score every held-out candidate exactly once")
    errors = np.abs(actual[test] - reference[test])
    coreml_evaluation = evaluate(rows, actual, groups["test"], evidence["seed"])
    reference_evaluation = evaluate(rows, reference, groups["test"], evidence["seed"])
    actual_selection = set(coreml_evaluation["learned_selected_candidate_ids"])
    reference_selection = set(reference_evaluation["learned_selected_candidate_ids"])
    report = {"schema": "metaflip-coreml-heldout-v1", "dataset_sha256": dataset_sha, "reference_weights_sha256": hashlib.sha256((args.model_dir / "weights.npz").read_bytes()).hexdigest(), "compiled_model_sha256": tree_sha256(args.compiled_model), "compiled_model": str(args.compiled_model), "command": command, "rows": len(test), "batches": len(batches), "heldout_origin_seeds": evidence["splits"]["test"]["origin_seeds"], "placement": ready, "wall_seconds_including_load": elapsed, "parity": {"max_absolute_error": float(errors.max()), "mean_absolute_error": float(errors.mean()), "tolerance": args.parity_tolerance, "passed": bool(errors.max() <= args.parity_tolerance), "same_top25_percent_selection": actual_selection == reference_selection, "top25_percent_selection_overlap": len(actual_selection & reference_selection) / len(reference_selection)}, "actual_coreml": coreml_evaluation, "numpy_float32_reference": reference_evaluation, "limitations": ["Core ML executed with cpuOnly; no Neural Engine or GPU offload", "Real origin/basin heldout results use actual converted-model scores, not only a NumPy proxy", "Small fixed-step offline selection study, not an end-to-end fleet benefit or rank-record improvement", "Novelty is canonical-aware term turnover relative to each starting candidate, not archive admission"]}
    # The live coordinator requests debt-1 and debt-2 seeds separately. Report
    # these deployment-matched comparisons too; unrestricted bank selection
    # can otherwise compare learned escaped seeds against rank-93 controls.
    report["runtime_debt_strata"] = {}
    for debt in (1, 2):
        eligible_groups = [[i for i in group if rows[i]["start_rank"] == 93 + debt] for group in groups["test"]]
        eligible_groups = [group for group in eligible_groups if group]
        if eligible_groups:
            report["runtime_debt_strata"][str(debt)] = {"rows": sum(map(len, eligible_groups)), "actual_coreml": evaluate(rows, actual, eligible_groups, evidence["seed"]), "numpy_float32_reference": evaluate(rows, reference, eligible_groups, evidence["seed"])}
    (args.out_dir / "evaluation.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"evaluation": str(args.out_dir / "evaluation.json"), "rows": len(test), "batches": len(batches), "parity": report["parity"], "actual_coreml": {key: coreml_evaluation[key] for key in ("learned", "heuristic", "random_100_trials")}, "wall_seconds_including_load": elapsed}, indent=2))
    if not report["parity"]["passed"]:
        raise SystemExit("Core ML numeric parity tolerance exceeded; evidence saved but gate failed")


if __name__ == "__main__":
    main()
