#!/usr/bin/env python3
"""Replay an offline learned-completion run, including independent Ruby gates."""
import argparse
from collections import Counter
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("completion", HERE / "learned_residual_completion.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def audit(root):
    report = json.loads((root / "report.json").read_text())
    if report["record_claim"] or report["production_enabled"]:
        raise ValueError("experimental report changed scope")
    if digest(root / "source.py") != report["training"]["source_sha256"]:
        raise ValueError("source snapshot hash mismatch")
    if digest(root / "training.jsonl") != report["training"]["dataset_sha256"]:
        raise ValueError("training corpus hash mismatch")
    cases = {r["id"]: r for r in map(json.loads, (root / "cases.jsonl").read_text().splitlines())}
    synthetic = {r["id"]: r for r in map(json.loads, (root / "training.jsonl").read_text().splitlines())}
    rows = list(map(json.loads, (root / "results.jsonl").read_text().splitlines()))
    seen, ruby, exact, ranks = set(), set(), 0, Counter()
    for row in rows:
        key = (row["kind"], row["case"], row["max_terms"], row["policy"])
        if key in seen or row["xor_checks"] > report["config"]["budget"]:
            raise ValueError("duplicate result or exceeded work budget")
        seen.add(key)
        if ("completion" in row) != (row["status"] == "exact"):
            raise ValueError("inconsistent exact result")
        if "completion" not in row:
            continue
        case = cases[row["case"]] if row["kind"] == "real" else synthetic[row["case"]]
        if row["kind"] != "real" and row["case"] not in report["training"]["test_ids"]:
            raise ValueError("synthetic evaluation outside held-out groups")
        if (len(row["completion"]) > row["max_terms"] or
                m.tensor(row["completion"], case["dims"]) != int(case["target"])):
            raise ValueError("invalid residual completion")
        exact += 1
        if row["kind"] != "real":
            continue
        source = Path(case["source"])
        if digest(source) != case["source_sha256"]:
            raise ValueError("changed source tensor")
        parent = m.read_seed(source, case["shape"])
        if list(map(tuple, case["parent"])) != parent:
            raise ValueError("case parent differs from source")
        replacement = m.lift(row["completion"], case["bases"])
        candidate = m.splice(parent, case["selected"], replacement, case["shape"])
        text = str(len(candidate)) + "\n" + "".join(" ".join(map(str, t))+"\n" for t in candidate)
        if (hashlib.sha256(text.encode()).hexdigest() != row["candidate_sha256"] or
                row["rank"] != len(candidate) or row["rank_drop"] != len(parent)-len(candidate) or
                row["distinct_from_parent"] != (candidate != m.canonical(parent)) or not row["exact_full"]):
            raise ValueError("candidate accounting mismatch")
        path = Path(row["candidate_path"]) if row["candidate_path"] else source
        if row["candidate_path"] and path.read_text() != text:
            raise ValueError("candidate artifact differs from completion")
        identity = (str(path), tuple(case["shape"]))
        if identity not in ruby:
            output = subprocess.run(["ruby", str(HERE / "verify_tensor.rb"), "--shape",
                                     "x".join(map(str, case["shape"])), str(path)],
                                    capture_output=True, text=True, check=True, timeout=30)
            checked = json.loads(output.stdout)[0]
            if not checked["exact"] or checked["rank"] != row["rank"]:
                raise ValueError("independent Ruby gate failed")
            ruby.add(identity)
        if row["rank_drop"] > 0:
            ranks[row["policy"]] += 1
    expected = 3 * (2 * len(cases) + min(report["config"]["holdout"], len(report["training"]["test_ids"])))
    if len(rows) != expected:
        raise ValueError("incomplete run")
    return dict(result="pass", rows=len(rows), exact_completions=exact,
                independent_full_tensors=len(ruby), rank_drops=dict(ranks), record_claim=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    print(json.dumps(audit(parser.parse_args().directory.resolve()), indent=2))
