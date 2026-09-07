#!/usr/bin/env python3
"""Build a pinned, tensor-verified minimum-rank F2 comparison library.

Research only: catalog minima are comparison bounds, not a novelty oracle or
permission to redistribute the coefficients. All rank ties are retained.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import time
import urllib.parse
import urllib.request

import catalog_gf2_import as importer


def minima(index: dict, maximum: int) -> list[dict]:
    grouped = {}
    for entry in index["schemes"]:
        shape = entry.get("format")
        if (entry.get("verified") is not True or entry.get("commutative") or
                entry.get("scheme_type") == "non_bilinear" or
                "F2" not in entry.get("fields", []) or "F2" in entry.get("fields_not", [])):
            continue
        if (not isinstance(shape, list) or len(shape) != 3 or
                any(type(d) is not int or not 1 <= d <= maximum for d in shape)):
            continue
        if type(entry.get("rank")) is not int or entry["rank"] <= 0:
            raise ValueError("admissible entry lacks a positive integral rank")
        grouped.setdefault(tuple(sorted(shape)), []).append(entry)
    result = []
    for shape, entries in sorted(grouped.items()):
        best = min(e["rank"] for e in entries)
        result.extend(sorted((e for e in entries if e["rank"] == best), key=lambda e: e["file"]))
    if len({e["file"] for e in result}) != len(result):
        raise ValueError("duplicate minimum source paths")
    return result


def source_path(entry: dict) -> str:
    value = entry["file"]
    path = PurePosixPath(value)
    if not value or path.is_absolute() or ".." in path.parts or "\\" in value:
        raise ValueError("unsafe catalog source path")
    return "src/main/resources/schemes/" + value


def check_blob(raw: bytes, blob: str) -> None:
    actual = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
    if actual != blob:
        raise ValueError("Git blob mismatch")


def fetch_one(entry: dict, *, commit: str, tree: dict, root: Path, caches: list[Path]) -> dict:
    path = source_path(entry)
    node = tree[path]
    if node.get("type") != "blob" or not re.fullmatch("[0-9a-f]{40}", node["sha"]):
        raise ValueError("source is not a pinned Git blob")
    blob = node["sha"]
    url = f"https://raw.githubusercontent.com/solven-eu/matmulcatalog/{commit}/" + urllib.parse.quote(path)
    cached = next((c / (blob + ".json") for c in caches if (c / (blob + ".json")).is_file()), None)
    if cached:
        raw = cached.read_bytes()
    else:
        for attempt in range(3):
            try:
                request = urllib.request.Request(url, headers={"User-Agent": "MetaFlip-exact-library-audit"})
                with urllib.request.urlopen(request, timeout=30) as response:
                    raw = response.read()
                break
            except OSError:
                if attempt == 2:
                    raise
                time.sleep(attempt + 1)
    check_blob(raw, blob)
    source = root / "sources" / (blob + ".json")
    source.write_bytes(raw)  # Retain even a rejected source for the field/index audit.
    data = json.loads(raw)
    if (data.get("commutative") or data.get("scheme_type") == "non_bilinear" or
            data.get("verified") is not True or "F2" not in data.get("fields", []) or
            "F2" in data.get("fields_not", []) or sorted(data.get("n", [])) != sorted(entry["format"]) or
            data.get("m") != entry["rank"]):
        raise ValueError("source/index/field/bilinearity mismatch")
    name = f"matmul_{'x'.join(map(str, data['n']))}_rank{data['m']}_{blob}_gf2.txt"
    witness = root / "witnesses" / name
    shape, rank = importer.convert(source, witness)
    return dict(file=entry["file"], shape=list(shape), rank=rank, git_blob=blob, url=url,
                source=str(source.relative_to(root)), source_sha256=hashlib.sha256(raw).hexdigest(),
                witness=str(witness.relative_to(root)), witness_sha256=hashlib.sha256(witness.read_bytes()).hexdigest(),
                cached=cached is not None, exact_f2_verified=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--index", type=Path, required=True)
    p.add_argument("--tree", type=Path, required=True)
    p.add_argument("--commit", required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--cache", type=Path, action="append", default=[])
    p.add_argument("--maximum", type=int, default=16)
    p.add_argument("--workers", type=int, default=4)
    args = p.parse_args()
    if not 1 <= args.maximum <= 32 or not 1 <= args.workers <= 16:
        p.error("maximum must be 1..32 and workers 1..16")
    tree_data = json.loads(args.tree.read_text())
    if (not re.fullmatch("[0-9a-f]{40}", args.commit) or tree_data["sha"] != args.commit or
            tree_data.get("truncated")):
        p.error("require a complete Git tree at the exact commit")
    chosen = minima(json.loads(args.index.read_text()), args.maximum)
    if not chosen:
        p.error("no explicit F2 minima")
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / "sources").mkdir()
    (args.output / "witnesses").mkdir()
    tree = {e["path"]: e for e in tree_data["tree"]}
    rows, errors = [], []
    started = time.monotonic()
    inputs = [args.index, args.tree, Path(__file__), Path(importer.__file__)]
    pins = {str(f.resolve()): hashlib.sha256(f.read_bytes()).hexdigest() for f in inputs}

    def save():
        expected_shapes = {tuple(sorted(e["format"])) for e in chosen}
        verified_shapes = {tuple(sorted(r["shape"])) for r in rows}
        report = dict(schema=1, field="GF(2)", record_claim=False, redistribution_cleared=False,
                      catalog_commit=args.commit, maximum=args.maximum, input_sha256=pins,
                      expected_sources=len(chosen), expected_shapes=len(expected_shapes),
                      verified_sources=len(rows), verified_shapes=len(verified_shapes),
                      complete=len(rows) == len(chosen) and not errors,
                      scan_complete=len(rows) + len(errors) == len(chosen),
                      coverage_complete=verified_shapes == expected_shapes,
                      missing_shapes=sorted(expected_shapes - verified_shapes),
                      rows=sorted(rows, key=lambda r: (sorted(r["shape"]), r["file"])), errors=errors,
                      elapsed_seconds=time.monotonic() - started)
        (args.output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        progress = {k: report[k] for k in ("expected_sources", "verified_sources", "verified_shapes", "complete", "elapsed_seconds")}
        print(json.dumps(dict(progress, errors=len(errors))), flush=True)

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        jobs = {pool.submit(fetch_one, e, commit=args.commit, tree=tree, root=args.output, caches=args.cache): e for e in chosen}
        for job in concurrent.futures.as_completed(jobs):
            try:
                rows.append(job.result())
            except Exception as error:
                errors.append(dict(file=jobs[job]["file"], error=str(error)))
                print(json.dumps(errors[-1]), flush=True)
            if (len(rows) + len(errors)) % 25 == 0:
                save()
    if any(hashlib.sha256(Path(f).read_bytes()).hexdigest() != sha for f, sha in pins.items()):
        errors.append(dict(error="source tool or index changed during run"))
    save()
    return bool(errors)


if __name__ == "__main__":
    raise SystemExit(main())
