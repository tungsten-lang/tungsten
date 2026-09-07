#!/usr/bin/env python3
"""Train/evaluate a tiny local ranker using real exact-verified CPU rollouts.

No Hub access, synthetic examples, GPU training, or random row holdout. The
supervised target is observed (93 - best_rank) + 0.25 * term_set_novelty: any
one-rank improvement dominates the entire bounded novelty tie-break. It does
not assert a new record, and the model is only a scheduling suggestion.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import time

# Apply before importing NumPy; tiny full-batch updates do not need a BLAS pool.
for variable in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS"):
    os.environ[variable] = "1"
import numpy as np

FEATURES = ["rank", "rank_debt", "total_bits", "bits_per_term", "flip_pairs", "flip_pairs_per_term", "c3_symmetric", "unique_u", "unique_v", "unique_w", "singleton_u", "singleton_v", "singleton_w", "max_bucket_u", "max_bucket_v", "max_bucket_w"]


def load_dataset(path):
    records = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    metadata = [row for row in records if row.get("type") == "metadata"]
    if len(metadata) != 1 or metadata[0].get("feature_names") != FEATURES:
        raise ValueError("Exactly one metaflip-ranker-v1 feature contract is required")
    rows = [row for row in records if row.get("type") == "rollout"]
    if len(rows) < 24:
        raise ValueError("At least 24 real rollout rows are needed; no synthetic fallback")
    budgets = set()
    seen_ids = set()
    for row in rows:
        if row.get("schema") != "metaflip-ranker-v1" or row.get("verified") is not True:
            raise ValueError("Every row must come from the exact-gated dataset harness")
        values = row.get("features", [])
        if len(values) != 16 or not all(math.isfinite(float(v)) for v in values):
            raise ValueError("Every row must contain exactly 16 finite features")
        if not (1 <= row["best_rank"] <= row["start_rank"] <= 160 and 0 <= row["novelty"] <= 1):
            raise ValueError("Invalid observed rank/novelty outcome")
        if row["rank_improvement"] != row["start_rank"] - row["best_rank"]:
            raise ValueError("Rank-improvement label does not match the exact outcome")
        if row["candidate_id"] in seen_ids:
            raise ValueError("Duplicate candidate id")
        seen_ids.add(row["candidate_id"])
        candidate = Path(row["candidate_path"])
        if hashlib.sha256(candidate.read_bytes()).hexdigest() != row["candidate_sha256"]:
            raise ValueError(f"Candidate artifact changed: {candidate}")
        budgets.add(row["requested_steps"])
    if len(budgets) != 1:
        raise ValueError("Training rows must use a matched fixed CPU step budget")
    return metadata[0], rows


def grouped_split(rows, seed):
    """Union origins and repeated canonical input basins before any split."""
    parent = list(range(len(rows)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    first = {}
    for index, row in enumerate(rows):
        keys = [("origin", row["origin_sha256"]), ("basin", row["origin_basin"]), ("basin", row["basin_id"])]
        for key in keys:
            if key in first:
                parent[find(index)] = find(first[key])
            else:
                first[key] = index
    members = {}
    for index in range(len(rows)):
        members.setdefault(find(index), []).append(index)
    groups = list(members.values())
    groups.sort(key=lambda indices: hashlib.sha256((str(seed) + ":" + min(rows[i]["origin_sha256"] for i in indices)).encode()).hexdigest())
    if len(groups) < 4:
        raise ValueError(f"Need at least four distinct origin/basin groups, found {len(groups)}; refusing leaked holdout")
    test_count = max(1, len(groups) // 4)
    validation_count = max(1, len(groups) // 4)
    split_groups = {"test": groups[:test_count], "validation": groups[test_count:test_count + validation_count], "train": groups[test_count + validation_count:]}
    split = {name: np.array([i for group in values for i in group], dtype=np.int64) for name, values in split_groups.items()}
    return split, split_groups


def dot(left, right):
    # These tiny matrices do not benefit from dispatching Accelerate/BLAS.
    # Keep the offline trainer's arithmetic and thread budget self-contained.
    return np.einsum("ij,jk->ik", left, right, optimize=False)


def forward(x, weights):
    a = np.maximum(dot(x, weights["w1"]) + weights["b1"], 0)
    b = np.maximum(dot(a, weights["w2"]) + weights["b2"], 0)
    y = dot(b, weights["w3"]) + weights["b3"]
    return y, a, b


def train(x, target, split, seed, epochs, hidden):
    rng = np.random.default_rng(seed)
    weights = {}
    for layer, (left, right) in enumerate(((16, hidden[0]), (hidden[0], hidden[1]), (hidden[1], 1)), 1):
        weights[f"w{layer}"] = (rng.standard_normal((left, right)) * math.sqrt(2 / left)).astype(np.float32)
        weights[f"b{layer}"] = np.zeros(right, np.float32)
    m = {key: np.zeros_like(value) for key, value in weights.items()}
    v = {key: np.zeros_like(value) for key, value in weights.items()}
    best = None
    best_loss = float("inf")
    best_epoch = 0
    xt, yt = x[split["train"]], target[split["train"], None]
    losses = []
    for epoch in range(1, epochs + 1):
        prediction, a, b = forward(xt, weights)
        dy = 2 * (prediction - yt) / len(xt)
        db = dot(dy, weights["w3"].T) * (b > 0)
        da = dot(db, weights["w2"].T) * (a > 0)
        gradients = {"w3": dot(b.T, dy), "b3": dy.sum(0), "w2": dot(a.T, db), "b2": db.sum(0), "w1": dot(xt.T, da), "b1": da.sum(0)}
        for key, gradient in gradients.items():
            if key.startswith("w"):
                gradient = gradient + 0.0001 * weights[key]
            gradient = np.clip(gradient, -5, 5)
            m[key] = 0.9 * m[key] + 0.1 * gradient
            v[key] = 0.999 * v[key] + 0.001 * gradient * gradient
            weights[key] -= 0.003 * (m[key] / (1 - 0.9 ** epoch)) / (np.sqrt(v[key] / (1 - 0.999 ** epoch)) + 1e-8)
        val_prediction = forward(x[split["validation"]], weights)[0][:, 0]
        loss = float(np.mean((val_prediction - target[split["validation"]]) ** 2))
        if not math.isfinite(loss) or not all(np.isfinite(value).all() for value in weights.values()):
            raise ValueError("Training produced non-finite arithmetic; refusing model export")
        if loss < best_loss:
            best_loss = loss
            best = {key: value.copy() for key, value in weights.items()}
            best_epoch = epoch
        if epoch == 1 or epoch % 50 == 0:
            losses.append({"epoch": epoch, "train_mse": float(np.mean((prediction - yt) ** 2)), "validation_mse": loss})
    return best, {"best_epoch": best_epoch, "validation_mse": best_loss, "losses": losses}


def metrics(rows, chosen):
    selected = [rows[i] for i in chosen]
    return {"selected": len(chosen), "mean_best_rank": float(np.mean([r["best_rank"] for r in selected])), "minimum_best_rank": min(r["best_rank"] for r in selected), "rank_improvement_fraction": float(np.mean([r["rank_improvement"] > 0 for r in selected])), "mean_rank_improvement": float(np.mean([r["rank_improvement"] for r in selected])), "new_basin_fraction": float(np.mean([r["novel_basin"] for r in selected])), "mean_novelty": float(np.mean([r["novelty"] for r in selected])), "mean_utility": float(np.mean([93 - r["best_rank"] + 0.25 * r["novelty"] for r in selected])), "rollout_cpu_ms": sum(r["elapsed_ms"] for r in selected)}


def evaluate(rows, predictions, groups, seed, fraction=0.25):
    # Splits are basin-unioned, but each origin gets the same selection quota.
    banks = {}
    for group in groups:
        for index in group:
            banks.setdefault(rows[index]["origin_seed"], []).append(index)
    selected = {"learned": [], "heuristic": [], "oracle": []}
    by_origin = {}
    for origin, group in banks.items():
        count = max(1, math.ceil(len(group) * fraction))
        learned = sorted(group, key=lambda i: (-predictions[i], rows[i]["candidate_id"]))[:count]
        # Existing archive-style ordering, measured before rollout only.
        heuristic = sorted(group, key=lambda i: (rows[i]["start_rank"], rows[i]["start_bits"], -rows[i]["features"][4], rows[i]["candidate_id"]))[:count]
        oracle = sorted(group, key=lambda i: (rows[i]["best_rank"], -rows[i]["novelty"], rows[i]["candidate_id"]))[:count]
        by_origin[origin] = {}
        for name, chosen in (("learned", learned), ("heuristic", heuristic), ("oracle", oracle)):
            selected[name].extend(chosen)
            by_origin[origin][name] = metrics(rows, chosen)
    result = {name: metrics(rows, indices) for name, indices in selected.items()}
    rng = np.random.default_rng(seed)
    trials = []
    origin_trials = {origin: [] for origin in banks}
    for _ in range(100):
        chosen = []
        for origin, group in banks.items():
            count = max(1, math.ceil(len(group) * fraction))
            sample = rng.choice(group, size=count, replace=False).tolist()
            chosen.extend(sample)
            origin_trials[origin].append(metrics(rows, sample))
        trials.append(metrics(rows, chosen))
    for origin, samples in origin_trials.items():
        by_origin[origin]["random_100_trials"] = {key: float(np.mean([trial[key] for trial in samples])) for key in samples[0]}
    result["random_100_trials"] = {key: float(np.mean([trial[key] for trial in trials])) for key in trials[0]}
    result["random_utility_p05_p95"] = np.percentile([trial["mean_utility"] for trial in trials], [5, 95]).tolist()
    result["selection_fraction"] = fraction
    result["by_origin"] = by_origin
    result["learned_selected_candidate_ids"] = [rows[i]["candidate_id"] for i in selected["learned"]]
    return result


def export_model(weights, mean, scale, output, batch_size, layout):
    import coremltools as ct
    from coremltools.converters.mil import Builder as mb

    @mb.program(input_specs=[mb.TensorSpec(shape=(batch_size, 16))], opset_version=ct.target.macOS13)
    def program(features):
        x = mb.sub(x=features, y=mean)
        x = mb.real_div(x=x, y=scale)
        if layout == "conv1x1":
            # Same learned affine maps, expressed with NE-friendly channels.
            x = mb.reshape(x=x, shape=[1, batch_size, 16, 1])
            x = mb.transpose(x=x, perm=[0, 2, 1, 3])
            for layer in (1, 2, 3):
                weight = weights[f"w{layer}"].T[:, :, None, None]
                x = mb.conv(x=x, weight=weight, bias=weights[f"b{layer}"], pad_type="valid")
                if layer != 3:
                    x = mb.relu(x=x)
            x = mb.transpose(x=x, perm=[0, 2, 1, 3])
            return mb.reshape(x=x, shape=[batch_size, 1], name="scores")
        x = mb.relu(x=mb.linear(x=x, weight=weights["w1"].T, bias=weights["b1"]))
        x = mb.relu(x=mb.linear(x=x, weight=weights["w2"].T, bias=weights["b2"]))
        return mb.linear(x=x, weight=weights["w3"].T, bias=weights["b3"], name="scores")

    model = ct.convert(program, source="milinternal", convert_to="mlprogram", minimum_deployment_target=ct.target.macOS13, compute_precision=ct.precision.FLOAT16, inputs=[ct.TensorType(name="features", shape=(batch_size, 16), dtype=np.float32)], outputs=[ct.TensorType(name="scores", dtype=np.float32)])
    model.short_description = "Experimental MetaFlip exact-rollout ranker; scheduling advice only"
    model.user_defined_metadata["feature_schema"] = "metaflip-ranker-v1"
    model.user_defined_metadata["feature_names"] = json.dumps(FEATURES)
    model.save(str(output))
    return ct.__version__


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset", type=Path)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--epochs", type=int, default=400)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--seed", type=int, default=20260906)
    parser.add_argument("--hidden", default="32,16", help="Two hidden widths; choose for hardware placement, not test-set tuning")
    parser.add_argument("--layout", choices=("linear", "conv1x1"), default="linear")
    parser.add_argument("--reuse-weights", type=Path, help="Re-export genuinely trained weights in another arithmetic-equivalent layout")
    parser.add_argument("--no-export", action="store_true")
    args = parser.parse_args()
    if not 1 <= args.epochs <= 2000 or args.batch_size != 64:
        parser.error("epochs must be 1..2000 and the production batch contract is 64")
    hidden = [int(value) for value in args.hidden.split(",")]
    if len(hidden) != 2 or any(value < 1 or value > 256 for value in hidden):
        parser.error("hidden must be two widths in 1..256")
    started = time.monotonic()
    metadata, rows = load_dataset(args.dataset)
    split, groups = grouped_split(rows, args.seed)
    raw = np.array([row["features"] for row in rows], dtype=np.float32)
    mean = raw[split["train"]].mean(axis=0)
    scale = raw[split["train"]].std(axis=0)
    scale[scale < 1e-6] = 1
    x = (raw - mean) / scale
    target = np.array([93 - row["best_rank"] + 0.25 * row["novelty"] for row in rows], np.float32)
    if args.reuse_weights:
        with np.load(args.reuse_weights, allow_pickle=False) as saved:
            if not np.array_equal(saved["mean"], mean) or not np.array_equal(saved["scale"], scale):
                raise ValueError("Reused normalization does not match this training-only split")
            weights = {key: saved[key].copy() for key in ("w1", "b1", "w2", "b2", "w3", "b3")}
        expected_shapes = {"w1": (16, hidden[0]), "b1": (hidden[0],), "w2": (hidden[0], hidden[1]), "b2": (hidden[1],), "w3": (hidden[1], 1), "b3": (1,)}
        if any(weights[key].shape != shape or not np.isfinite(weights[key]).all() for key, shape in expected_shapes.items()):
            raise ValueError("Reused weights do not match the declared learned architecture")
        training = {"reused_weights": str(args.reuse_weights), "weights_sha256": hashlib.sha256(args.reuse_weights.read_bytes()).hexdigest()}
    else:
        weights, training = train(x, target, split, args.seed, args.epochs, hidden)
    prediction = forward(x, weights)[0][:, 0]
    args.out_dir.mkdir(parents=True, exist_ok=True)
    np.savez(args.out_dir / "weights.npz", mean=mean, scale=scale, **weights)
    report = {"schema": "metaflip-ranker-evaluation-v1", "dataset_sha256": hashlib.sha256(args.dataset.read_bytes()).hexdigest(), "dataset_metadata": metadata, "feature_names": FEATURES, "target": "93 - observed_best_rank + 0.25 * observed_term_set_novelty (rank strictly dominates novelty)", "architecture": [16, *hidden, 1], "seed": args.seed, "epochs": args.epochs, "normalization_fit": "training origins only", "training": training, "splits": {}, "evaluations": {}, "limitations": ["Tiny fixed-step offline study, not a new-record result", "Origin/basin holdout prevents duplicate input leakage; origins may still share deeper undiscovered lineage", "Candidate escape precondition failures are excluded, not relabeled", "Novelty is canonical-aware term turnover from the starting candidate, not verified archive admission", "Reported model efficacy uses the NumPy FP32 reference; Core ML parity and placement are separate gates", "Offline candidate selection does not establish end-to-end fleet throughput benefit"]}
    for name, indices in split.items():
        report["splits"][name] = {"rows": len(indices), "groups": len(groups[name]), "origin_seeds": sorted({rows[i]["origin_seed"] for i in indices}), "candidate_ids": [rows[i]["candidate_id"] for i in indices]}
        report["evaluations"][name] = evaluate(rows, prediction, groups[name], args.seed)
    # Feed genuine held-out rows to the standalone backend/parity check.
    test_indices = split["test"][:64]
    request = {"id": "heldout-0", "rows": raw[test_indices].tolist()}
    (args.out_dir / "heldout_request.jsonl").write_text(json.dumps(request) + "\n")
    (args.out_dir / "heldout_expected.json").write_text(json.dumps({"id": "heldout-0", "candidate_ids": [rows[i]["candidate_id"] for i in test_indices], "scores": prediction[test_indices].tolist()}, indent=2) + "\n")
    if not args.no_export:
        report["coremltools_version"] = export_model(weights, mean, scale, args.out_dir / "ranker.mlpackage", args.batch_size, args.layout)
    report["export_layout"] = args.layout
    report["elapsed_seconds"] = time.monotonic() - started
    (args.out_dir / "evaluation.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"evaluation": str(args.out_dir / "evaluation.json"), "splits": {k: {"rows": len(v), "groups": len(groups[k])} for k, v in split.items()}, "test": report["evaluations"]["test"], "elapsed_seconds": report["elapsed_seconds"]}, indent=2))


if __name__ == "__main__":
    main()
