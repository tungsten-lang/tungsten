#!/usr/bin/env python3
"""SAT Competition 2026 harness: fetch a subset, run a solver, score it.

The competition publishes three artefacts we use here (see
https://satcompetition.github.io/2026/):

  downloads/benchmark-compilation-script.tar.xz
      ``select26.py`` plus ``meta.db`` / ``benchmarks2026.csv``. It is a
      *benchmark selection* script — it draws the 400 main-track instances,
      it does NOT run solvers. ``--select`` below re-runs it.
  downloads/scores.csv
      instance-wise results: one row per (solver, instance) with runtime and
      status for all 31 entrants, CaDiCaL 3 and Kissat among them.
  https://benchmark-database.de/file/<instanceid>
      the instance itself, xz-compressed.

Subcommands
    fetch     download a size- and difficulty-bounded subset of the 400
              main-track instances into ``--dir`` (default /tmp/satbench-2026)
    run       run a solver over that subset and emit the competition's own
              results format: solverid,instanceid,runtime,status,score,vresult
    compare   join a ``run`` output against the published scores.csv

Deviations from the official configuration are printed by ``run`` and must
travel with any number taken from it: the competition allows 5000s per
instance on a dedicated cloud node, this runs a short timeout on a shared
laptop over a subset chosen to be tractable.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import subprocess
import sys
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

SITE = "https://satcompetition.github.io/2026"
FILE_API = "https://benchmark-database.de/file"
OFFICIAL_TIMEOUT = 5000.0
CADICAL3 = "biere_cadical3[main]"
KISSAT = "biere_kissat-biere[main]"

DEFAULT_DIR = Path(os.environ.get("SATBENCH_2026", "/tmp/satbench-2026"))
CACHE = Path(os.environ.get("SC2026_CACHE", "/tmp/sc2026"))


# --------------------------------------------------------------------------
# published data


def curl(url: str, dest: Path | None = None, head: bool = False) -> str:
    cmd = ["curl", "-sSL", "--max-time", "900"]
    if head:
        cmd.append("-I")
    if dest:
        cmd += ["-o", str(dest)]
    cmd.append(url)
    return subprocess.run(cmd, capture_output=True, text=True, check=False).stdout


def scores_csv() -> Path:
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / "scores.csv"
    if not path.is_file() or path.stat().st_size == 0:
        curl(f"{SITE}/downloads/scores.csv", path)
    return path


def published() -> dict[str, dict]:
    """instanceid -> published field results, keyed by competition hash."""
    ok = {"sat-verified", "unsat-verified"}
    rows = list(csv.DictReader(scores_csv().open()))
    by: dict[str, dict] = defaultdict(dict)
    for r in rows:
        by[r["instanceid"]][r["solverid"]] = r
    out = {}
    for h, d in by.items():
        solved = {s: float(r["runtime"]) for s, r in d.items() if r["status"] in ok}
        verdicts = {r["vresult"] for r in d.values() if r["status"] in ok}
        out[h] = {
            "n_solvers": len(d),
            "n_solved": len(solved),
            "best": min(solved.values()) if solved else None,
            "cadical3": solved.get(CADICAL3),
            "kissat": solved.get(KISSAT),
            "verdict": verdicts.pop() if len(verdicts) == 1 else "unknown",
        }
    return out


def instance_meta(hashes: list[str], jobs: int = 12) -> dict[str, tuple[int, str]]:
    """HEAD each instance for size and the original filename."""
    cached = CACHE / "inst_meta.tsv"
    known = {}
    if cached.is_file():
        for line in cached.read_text().splitlines():
            h, size, name = line.split("\t")
            known[h] = (int(size), name)
    todo = [h for h in hashes if h not in known]

    def probe(h):
        out = curl(f"{FILE_API}/{h}", head=True).replace("\r", "")
        size = re.findall(r"(?im)^content-length:\s*(\d+)", out)
        name = re.findall(r"(?im)^content-disposition:.*filename=(\S+)", out)
        return h, int(size[-1]) if size else 0, name[-1] if name else "unknown"

    if todo:
        CACHE.mkdir(parents=True, exist_ok=True)
        with ThreadPoolExecutor(max_workers=jobs) as ex:
            for h, size, name in ex.map(probe, todo):
                known[h] = (size, name)
        with cached.open("w") as fh:
            for h, (size, name) in sorted(known.items()):
                fh.write(f"{h}\t{size}\t{name}\n")
    return known


def stem(filename: str) -> str:
    name = re.sub(r"^[0-9a-f]{32}-", "", filename)
    return re.sub(r"\.cnf$", "", re.sub(r"\.sanitized", "", re.sub(r"\.xz$", "", name)))


# --------------------------------------------------------------------------
# fetch


def cmd_fetch(args) -> None:
    field = published()
    meta = instance_meta(sorted(field))
    picks = []
    for h, f in field.items():
        size, name = meta.get(h, (0, "unknown"))
        if not size or size > args.max_bytes or f["verdict"] not in ("sat", "unsat"):
            continue
        best = f["best"]
        if best is None or not (args.min_field_seconds <= best <= args.max_field_seconds):
            continue
        picks.append((h, stem(name), size, best, f["verdict"]))
    # one instance per name prefix keeps family diversity ahead of raw count
    seen: dict[str, int] = defaultdict(int)
    chosen = []
    for h, name, size, best, verdict in sorted(picks, key=lambda p: (p[3], p[2])):
        key = re.sub(r"\d+$", "", re.split(r"[-_.]", name)[0]) or name
        if seen[key] >= args.per_family:
            continue
        seen[key] += 1
        chosen.append((h, name, size, best, verdict))
    args.dir.mkdir(parents=True, exist_ok=True)
    print(f"selecting {len(chosen)} instances across {len(seen)} name-families, "
          f"{sum(c[2] for c in chosen) / 1e6:.0f} MB compressed")

    def get(item):
        h, name, _size, _best, _verdict = item
        out = args.dir / f"{re.sub(r'[^A-Za-z0-9._-]', '_', name)[:70]}.cnf"
        if out.is_file() and out.stat().st_size:
            return "skip"
        tmp = args.dir / f".{h}"
        curl(f"{FILE_API}/{h}", tmp)
        if subprocess.run(["xz", "-t", str(tmp)], capture_output=True, check=False).returncode == 0:
            with out.open("wb") as fh:
                subprocess.run(["xz", "-dc", str(tmp)], stdout=fh, check=False)
            tmp.unlink()
        else:
            tmp.replace(out)
        return "ok"

    with ThreadPoolExecutor(max_workers=args.jobs) as ex:
        got = list(ex.map(get, chosen))
    index_path = args.dir / "index.json"
    index = json.loads(index_path.read_text()) if index_path.is_file() else {}
    index.update({name: {"hash": h, "field_best": best, "verdict": verdict}
                  for h, name, _s, best, verdict in chosen})
    index_path.write_text(json.dumps(index, indent=1, sort_keys=True))
    print(f"downloaded {got.count('ok')}, already present {got.count('skip')} -> {args.dir}")


# --------------------------------------------------------------------------
# run


def verdict_of(text: str) -> str:
    for line in text.splitlines():
        if line.startswith("s "):
            v = line[2:].strip()
            return "sat" if v.startswith("SATISFI") else ("unsat" if v.startswith("UNSATISFI") else "unknown")
    return "none"


def cmd_run(args) -> None:
    index = json.loads((args.dir / "index.json").read_text()) if (args.dir / "index.json").is_file() else {}
    files = sorted(p for p in args.dir.glob("*.cnf"))
    if args.limit:
        files = files[: args.limit]
    print(f"# solver: {' '.join(args.solver)}")
    print(f"# DEVIATIONS FROM OFFICIAL SC2026 CONFIGURATION")
    print(f"#   timeout      {args.timeout:g}s per instance (official: {OFFICIAL_TIMEOUT:g}s)")
    print(f"#   instances    {len(files)} (official main track: 400)")
    print(f"#   machine      shared developer laptop (official: dedicated cloud node)")
    print(f"#   selection    biased to instances the field solved quickly")
    print("solverid,instanceid,runtime,status,score,vresult")
    writer = csv.writer(sys.stdout)
    for path in files:
        entry = index.get(path.stem, {})
        t0 = time.perf_counter()
        try:
            proc = subprocess.run(args.solver + [str(path)] + args.solver_args,
                                  capture_output=True, text=True, timeout=args.timeout, check=False)
            elapsed = time.perf_counter() - t0
            code, out = proc.returncode, proc.stdout
        except subprocess.TimeoutExpired:
            elapsed, code, out = args.timeout, None, ""
        if code is None:
            status, vresult = "solver-timeout", ""
        else:
            vresult = verdict_of(out)
            status = {"sat": "sat", "unsat": "unsat"}.get(vresult, "unknown")
            expected = entry.get("verdict")
            if expected and vresult in ("sat", "unsat") and vresult != expected:
                status = "wrong"
        score = elapsed if status in ("sat", "unsat") else args.timeout
        writer.writerow([args.solverid, entry.get("hash", path.stem), f"{elapsed:.2f}", status,
                         f"{score:.2f}", vresult])
        sys.stdout.flush()


# --------------------------------------------------------------------------
# compare


def cmd_compare(args) -> None:
    field = published()
    mine = [r for r in csv.DictReader(l for l in args.results.open() if not l.startswith("#"))]
    print(f"{'instance':46s} {'ours':>9s} {'cadical3*':>10s} {'kissat*':>9s} {'field best*':>12s}  verdict")
    faster = slower = missing = 0
    for r in mine:
        f = field.get(r["instanceid"])
        if not f:
            missing += 1
            continue
        ours = float(r["runtime"])
        solved = r["status"] in ("sat", "unsat")
        best = f["best"]
        mark = ""
        if solved and best is not None:
            if ours < best:
                faster += 1
                mark = f"  {best / ours:.1f}x faster than field best"
            else:
                slower += 1
                mark = f"  {ours / best:.1f}x off field best"
        elif not solved:
            slower += 1
            mark = "  UNSOLVED here"
        def fmt(x):
            return "  -" if x is None else f"{x:.2f}"
        print(f"{r['instanceid'][:46]:46s} {ours:9.2f} {fmt(f['cadical3']):>10s} {fmt(f['kissat']):>9s} "
              f"{fmt(f['best']):>12s}  {r['vresult'] or '-'}{mark}")
    print(f"\n* published SC2026 runtimes: different hardware, 5000s budget — "
          f"treat as an ordering, not a ratio.")
    print(f"ahead of the published field best on {faster}, behind on {slower}, "
          f"no published row for {missing}")


def cmd_select(args) -> None:
    """Re-run the competition's own benchmark compilation script."""
    root = CACHE / "bcs" / "benchmark-compilation-script"
    if not root.is_dir():
        CACHE.mkdir(parents=True, exist_ok=True)
        tar = CACHE / "benchmark-compilation-script.tar.xz"
        curl(f"{SITE}/downloads/benchmark-compilation-script.tar.xz", tar)
        (CACHE / "bcs").mkdir(exist_ok=True)
        subprocess.run(["tar", "xJf", str(tar), "-C", str(CACHE / "bcs")], check=True)
    script = root / "select26.py"
    print(f"running {script} (needs gbd-tools>=5.0.1, polars>=1.36.1, numpy, packaging)")
    subprocess.run([args.python, str(script)], cwd=root, check=False)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    f = sub.add_parser("fetch", help="download a tractable subset of the main track")
    f.add_argument("--dir", type=Path, default=DEFAULT_DIR)
    f.add_argument("--max-field-seconds", type=float, default=60.0,
                   help="keep instances the fastest entrant solved within this many seconds")
    f.add_argument("--min-field-seconds", type=float, default=0.0,
                   help="lower bound on the same, for fetching a harder tier separately")
    f.add_argument("--max-bytes", type=int, default=25_000_000, help="compressed size ceiling")
    f.add_argument("--per-family", type=int, default=2)
    f.add_argument("--jobs", type=int, default=8)
    f.set_defaults(func=cmd_fetch)

    r = sub.add_parser("run", help="run a solver, emit competition-format rows")
    r.add_argument("--dir", type=Path, default=DEFAULT_DIR)
    r.add_argument("--solver", nargs="+", default=[str(Path(__file__).resolve().parents[1] / "bin" / "wassat")])
    r.add_argument("--solver-args", nargs="*", default=["--fast"])
    r.add_argument("--solverid", default="tungsten_wassat[local]")
    r.add_argument("--timeout", type=float, default=60.0)
    r.add_argument("--limit", type=int, default=0)
    r.set_defaults(func=cmd_run)

    c = sub.add_parser("compare", help="join a run against the published scores")
    c.add_argument("results", type=Path)
    c.set_defaults(func=cmd_compare)

    s = sub.add_parser("select", help="re-run the official benchmark compilation script")
    s.add_argument("--python", default=sys.executable)
    s.set_defaults(func=cmd_select)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
