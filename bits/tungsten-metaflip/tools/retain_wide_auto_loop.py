#!/usr/bin/env python3
"""Retain a minimal exact lineage of improved shapes from a completed loop."""
import argparse
import base64
import gzip
import json
from pathlib import Path

from search_wide_projection_walks import verify_file
from wide_composition_recipes import recipe_dependencies


def retained_rows(manifest):
    if (manifest.get("schema") != 1 or manifest.get("field") != "GF(2)" or
            manifest.get("record_claim") is not False or
            manifest.get("status") != "complete"):
        raise ValueError("campaign is not a completed exact GF(2) loop")
    rows = manifest["rows"]
    by_sha = {}
    initial_price = {}
    best = {}
    for row in rows:
        sha = row["sha256"]
        shape = tuple(sorted(row["shape"]))
        if sha in by_sha:
            raise ValueError("duplicate campaign identity")
        by_sha[sha] = row
        initial_price.setdefault(shape, row["old_price"])
        if shape not in best or (row["rank"], sha) < (best[shape]["rank"],
                                                     best[shape]["sha256"]):
            best[shape] = row
    selected = set()
    for shape, row in best.items():
        if row["rank"] >= initial_price[shape]:
            continue
        pending = [row["sha256"]]
        while pending:
            sha = pending.pop()
            if sha in selected:
                continue
            if sha not in by_sha:
                raise ValueError("missing campaign parent")
            current = by_sha[sha]
            selected.add(sha)
            if current["parent"] is not None:
                pending.append(current["parent"])
            if current.get("kind") == "closure-composition":
                pending.extend(recipe_dependencies(current["details"]["recipe"]))
    return [row for row in rows if row["sha256"] in selected]


def retain(campaign, output):
    if output.exists():
        raise ValueError("retained output already exists")
    report = json.loads((campaign / "manifest.json").read_text())
    rows = retained_rows(report)
    if not rows:
        raise ValueError("campaign has no improved shapes")
    checked = []
    for row in rows:
        path = Path(row["path"])
        if (path.is_absolute() or ".." in path.parts or not path.parts or
                path.parts[0] != "states"):
            raise ValueError("unsafe campaign state path")
        shape, terms, sha = verify_file(campaign / path)
        if (list(shape) != row["shape"] or len(terms) != row["rank"] or
                sha != row["sha256"]):
            raise ValueError("campaign state disagrees with manifest")
        checked.append((row, (campaign / path).read_bytes()))
    output.mkdir(parents=True)
    retained = []
    for row, raw in checked:
        name = ("x".join(map(str, row["shape"])) + f'-r{row["rank"]}-' +
                row["sha256"][:8] + ".mfw.gz.b64")
        (output / name).write_bytes(base64.b64encode(gzip.compress(raw, mtime=0)) + b"\n")
        retained.append({key: row[key] for key in
                         ("kind", "parent", "details", "shape", "rank", "sha256",
                          "old_price", "external_best_rank", "external_best_source",
                          "external_gap") } | {"file": name})
    summary = dict(schema=1, field="GF(2)", record_claim=False,
                   source=report["source"],
                   catalog_sha256=report["catalog_sha256"],
                   steps_per_walk=report["steps_per_walk"], rows=retained)
    (output / "manifest.json").write_text(json.dumps(summary, indent=2) + "\n")
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("campaign", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    report = retain(args.campaign, args.output)
    print(json.dumps(dict(retained=len(report["rows"]), output=str(args.output))))


if __name__ == "__main__":
    main()
