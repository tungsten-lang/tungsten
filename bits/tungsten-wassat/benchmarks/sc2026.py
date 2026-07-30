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
    fetch     download either a size- and difficulty-bounded subset or the
              complete 400-instance main track into ``--dir``
    verify    verify that a local directory is the complete published track
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
    cmd = ["curl", "-fsSL", "--max-time", "900"]
    if head:
        cmd.append("-I")
    if dest:
        cmd += ["-o", str(dest)]
    cmd.append(url)
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        detail = result.stderr.strip() or f"curl exited {result.returncode}"
        raise RuntimeError(f"download failed for {url}: {detail}")
    if dest is not None and (not dest.is_file() or dest.stat().st_size == 0):
        raise RuntimeError(f"download produced an empty file for {url}")
    return result.stdout


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
        name = re.findall(
            r'(?im)^content-disposition:.*filename="?([^";\s]+)"?', out
        )
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
    name = re.sub(r"^[0-9a-f]{32}-", "", filename.strip().strip('"'))
    return re.sub(r"(?i)(?:\.xz|\.sanitized|\.cnf)+$", "", name)


# --------------------------------------------------------------------------
# fetch


def cmd_fetch(args) -> None:
    field = published()
    meta = instance_meta(sorted(field))
    picks = []
    for h, f in field.items():
        size, name = meta.get(h, (0, "unknown"))
        if not size:
            continue
        if args.all:
            picks.append((h, stem(name), size, f["best"], f["verdict"]))
            continue
        if size > args.max_bytes or f["verdict"] not in ("sat", "unsat"):
            continue
        best = f["best"]
        if best is None or not (args.min_field_seconds <= best <= args.max_field_seconds):
            continue
        picks.append((h, stem(name), size, best, f["verdict"]))

    if args.all:
        chosen = sorted(picks, key=lambda p: p[0])
        seen = {name for _h, name, _size, _best, _verdict in chosen}
    else:
        # One instance per name prefix keeps family diversity ahead of raw
        # count for a developer subset. The complete-corpus path bypasses
        # this sampling deliberately.
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
        local = re.sub(r"[^A-Za-z0-9._-]", "_", name)[:100]
        # The official set contains generic names such as "1" and repeated
        # stems from different benchmark families. Hash-suffixing the complete
        # corpus makes every local path stable and collision-free.
        if args.all:
            local = f"{local}--{h[:12]}"
        out = args.dir / f"{local}.cnf"
        if out.is_file() and out.stat().st_size:
            return "skip", out.stem, h, _best, _verdict
        downloaded = args.dir / f".{h}.download"
        materialized = args.dir / f".{h}.cnf"
        try:
            downloaded.unlink(missing_ok=True)
            materialized.unlink(missing_ok=True)
            curl(f"{FILE_API}/{h}", downloaded)
            compressed = subprocess.run(
                ["xz", "-t", str(downloaded)], capture_output=True, check=False
            ).returncode == 0
            if compressed:
                with materialized.open("wb") as fh:
                    result = subprocess.run(
                        ["xz", "-dc", str(downloaded)],
                        stdout=fh,
                        stderr=subprocess.PIPE,
                        check=False,
                    )
                if result.returncode != 0 or materialized.stat().st_size == 0:
                    detail = result.stderr.decode("utf-8", "replace").strip()
                    raise RuntimeError(
                        f"cannot decompress benchmark {h}: "
                        f"{detail or f'xz exited {result.returncode}'}"
                    )
            else:
                downloaded.replace(materialized)
            # Publish only a complete materialization. A killed fetch leaves a
            # dotfile that the next invocation removes; it can never satisfy
            # the ordinary `out.is_file()` resume check.
            materialized.replace(out)
        finally:
            downloaded.unlink(missing_ok=True)
            materialized.unlink(missing_ok=True)
        return "ok", out.stem, h, _best, _verdict

    with ThreadPoolExecutor(max_workers=args.jobs) as ex:
        got = list(ex.map(get, chosen))
    index_path = args.dir / "index.json"
    # A complete fetch is also an exact manifest refresh.  Earlier subset
    # fetches may have materialized the same official hash under a different
    # stem (for example when benchmark-database corrected a `.xz` filename).
    # Retaining those stale aliases makes `verify` see more than the published
    # 400 rows even though hash coverage is exact.  Subset fetches still merge
    # so independently fetched difficulty tiers remain resumable.
    index = {}
    if not args.all and index_path.is_file():
        index = json.loads(index_path.read_text())
    index.update({local: {"hash": h, "field_best": best, "verdict": verdict}
                  for _status, local, h, best, verdict in got})
    index_path.write_text(json.dumps(index, indent=1, sort_keys=True))
    statuses = [item[0] for item in got]
    print(f"downloaded {statuses.count('ok')}, already present {statuses.count('skip')} -> {args.dir}")


# --------------------------------------------------------------------------
# local-corpus verification


def dimacs_integrity(path: Path) -> str | None:
    """Return a full-file DIMACS error, or None for a well-formed instance."""
    header: tuple[int, int] | None = None
    clauses = 0
    pending = False
    max_variable = 0
    try:
        with path.open("r", encoding="ascii") as stream:
            for line_number, raw_line in enumerate(stream, start=1):
                line = raw_line.strip()
                if not line or line.startswith("c"):
                    continue
                if line.startswith("p"):
                    fields = line.split()
                    if header is not None or len(fields) != 4 or fields[:2] != ["p", "cnf"]:
                        return f"line {line_number}: malformed or duplicate header"
                    try:
                        header = (int(fields[2]), int(fields[3]))
                    except ValueError:
                        return f"line {line_number}: non-integer header"
                    if header[0] < 0 or header[1] < 0:
                        return f"line {line_number}: negative header count"
                    continue
                if header is None:
                    return f"line {line_number}: clause precedes header"
                try:
                    for token in line.split():
                        literal = int(token)
                        if literal == 0:
                            clauses += 1
                            pending = False
                        else:
                            if abs(literal) > header[0]:
                                return (
                                    f"line {line_number}: literal {literal} exceeds "
                                    f"declared variable count {header[0]}"
                                )
                            max_variable = max(max_variable, abs(literal))
                            pending = True
                except ValueError:
                    return f"line {line_number}: non-integer clause token"
    except (OSError, UnicodeError) as error:
        return f"cannot read ASCII DIMACS: {error}"
    if header is None:
        return "missing header"
    if pending:
        return "unterminated final clause"
    if clauses != header[1]:
        return f"declares {header[1]} clauses but contains {clauses}"
    if header[0] > 0 and max_variable != header[0]:
        return (
            f"declares {header[0]} variables but largest appearing identifier "
            f"is {max_variable}"
        )
    return None


def cmd_verify(args) -> None:
    expected = set(published())
    index_path = args.dir / "index.json"
    if not index_path.is_file():
        raise SystemExit(f"missing corpus index: {index_path}")
    index = json.loads(index_path.read_text())
    files = sorted(args.dir.glob("*.cnf"))
    indexed = {entry.get("hash") for entry in index.values()}
    errors = []
    if len(files) != len(expected):
        errors.append(f"expected {len(expected)} CNFs, found {len(files)}")
    if len(index) != len(expected):
        errors.append(f"expected {len(expected)} index rows, found {len(index)}")
    if indexed != expected:
        errors.append(
            f"index hash coverage differs: missing={len(expected - indexed)} "
            f"extra={len(indexed - expected)}"
        )

    total = 0
    for file_number, path in enumerate(files, start=1):
        total += path.stat().st_size
        entry = index.get(path.stem)
        if entry is None:
            errors.append(f"unindexed file: {path.name}")
            continue
        if path.stat().st_size == 0:
            errors.append(f"empty file: {path.name}")
            continue
        with path.open("rb") as stream:
            prefix = stream.read(1 << 20)
        if not re.search(rb"(?m)^p cnf [0-9]+ [0-9]+[ \t]*\r?$", prefix):
            errors.append(f"no DIMACS header in first MiB: {path.name}")
            continue
        if args.deep:
            error = dimacs_integrity(path)
            if error is not None:
                errors.append(f"invalid DIMACS {path.name}: {error}")
            if file_number % 25 == 0:
                print(
                    f"deep DIMACS verification {file_number}/{len(files)}",
                    file=sys.stderr,
                )

    verdicts: dict[str, int] = defaultdict(int)
    for entry in index.values():
        verdicts[entry.get("verdict", "unknown")] += 1
    print(
        f"corpus={args.dir} files={len(files)} bytes={total} "
        + " ".join(f"{key}={verdicts[key]}" for key in sorted(verdicts))
    )
    if errors:
        for error in errors[:20]:
            print(f"ERROR: {error}", file=sys.stderr)
        if len(errors) > 20:
            print(f"ERROR: {len(errors) - 20} more", file=sys.stderr)
        raise SystemExit(1)
    depth = " and full DIMACS integrity" if args.deep else " coverage"
    print(
        f"verified complete published SC2026 main corpus{depth} "
        f"({len(expected)} instances)"
    )


# --------------------------------------------------------------------------
# run


def competition_output(text: str) -> tuple[str, dict[int, bool], str | None]:
    """Parse strict competition output and return verdict, model, error."""
    statuses: list[str] = []
    assignment: dict[int, bool] = {}
    value_lines = 0
    terminated = False
    for line in text.splitlines():
        if not line:
            return "none", {}, "blank stdout line"
        if line.startswith("c "):
            continue
        if line in ("s SATISFIABLE", "s UNSATISFIABLE", "s UNKNOWN"):
            statuses.append(line)
            continue
        if not line.startswith("v "):
            return "none", {}, f"non-competition stdout line: {line!r}"
        if len(line) > 4096:
            return "none", {}, f"value line exceeds 4096 characters ({len(line)})"
        value_lines += 1
        fields = line.split()[1:]
        if not fields:
            return "none", {}, "empty value line"
        for index, token in enumerate(fields):
            try:
                literal = int(token)
            except ValueError:
                return "none", {}, f"non-integer model token: {token!r}"
            if literal == 0:
                if terminated or index != len(fields) - 1:
                    return "none", {}, "model terminator is not the final model token"
                terminated = True
                continue
            if terminated:
                return "none", {}, "model literal appears after terminator"
            variable = abs(literal)
            if variable == 0:
                return "none", {}, "zero model variable"
            value = literal > 0
            if variable in assignment and assignment[variable] != value:
                return "none", {}, f"model assigns variable {variable} both polarities"
            assignment[variable] = value

    if len(statuses) != 1:
        return "none", {}, f"expected exactly one solution line, found {len(statuses)}"
    status = statuses[0]
    if status == "s SATISFIABLE":
        if value_lines == 0 or not terminated:
            return "sat", {}, "SAT output has no terminated model"
        return "sat", assignment, None
    if value_lines:
        return "none", {}, "non-SAT output contains value lines"
    if status == "s UNSATISFIABLE":
        return "unsat", {}, None
    return "unknown", {}, None


def model_satisfies(path: Path, assignment: dict[int, bool]) -> bool:
    """Check a possibly partial SAT model against DIMACS without loading it."""
    header: tuple[int, int] | None = None
    clause: list[int] = []
    clauses = 0
    with path.open("r", encoding="ascii") as stream:
        for raw_line in stream:
            line = raw_line.strip()
            if not line or line.startswith("c"):
                continue
            if line.startswith("p"):
                fields = line.split()
                if header is not None or len(fields) != 4 or fields[:2] != ["p", "cnf"]:
                    return False
                try:
                    header = (int(fields[2]), int(fields[3]))
                except ValueError:
                    return False
                continue
            if header is None:
                return False
            try:
                tokens = (int(token) for token in line.split())
                for literal in tokens:
                    if literal == 0:
                        if not any(
                            assignment.get(abs(item)) == (item > 0)
                            for item in clause
                        ):
                            return False
                        clauses += 1
                        clause.clear()
                    else:
                        if abs(literal) > header[0]:
                            return False
                        clause.append(literal)
            except ValueError:
                return False
    if header is None or clause or clauses != header[1]:
        return False
    return all(1 <= variable <= header[0] for variable in assignment)


def cmd_run(args) -> None:
    index = json.loads((args.dir / "index.json").read_text()) if (args.dir / "index.json").is_file() else {}
    files = sorted(p for p in args.dir.glob("*.cnf"))
    if args.verdict != "any":
        files = [
            path for path in files
            if index.get(path.stem, {}).get("verdict") == args.verdict
        ]
    if args.max_file_bytes:
        files = [path for path in files if path.stat().st_size <= args.max_file_bytes]
    if args.min_field_seconds > 0 or args.max_field_seconds is not None:
        selected = []
        for path in files:
            best = index.get(path.stem, {}).get("field_best")
            if best is None or best < args.min_field_seconds:
                continue
            if args.max_field_seconds is not None and best > args.max_field_seconds:
                continue
            selected.append(path)
        files = selected
    if args.limit:
        files = files[: args.limit]
    print(f"# solver: {' '.join(args.solver)}")
    print(f"# DEVIATIONS FROM OFFICIAL SC2026 CONFIGURATION")
    print(f"#   timeout      {args.timeout:g}s per instance (official: {OFFICIAL_TIMEOUT:g}s)")
    print(f"#   instances    {len(files)} (official main track: 400)")
    print(f"#   machine      shared developer laptop (official: NHR competition node)")
    selection = "complete published track" if len(files) == len(published()) else "developer subset"
    print(f"#   selection    {selection}")
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
            expected = entry.get("verdict")
            vresult, model, output_error = competition_output(out)
            if output_error is not None:
                status = "wrong"
                print(f"# WRONG {path.name}: {output_error}", file=sys.stderr)
            elif vresult == "sat":
                if code != 10:
                    status = "wrong"
                    print(f"# WRONG {path.name}: SAT exit code {code}, expected 10", file=sys.stderr)
                elif not model_satisfies(path, model):
                    status = "wrong"
                    print(f"# WRONG {path.name}: invalid SAT model", file=sys.stderr)
                elif expected == "unsat":
                    status = "wrong"
                    print(f"# WRONG {path.name}: SAT contradicts published UNSAT", file=sys.stderr)
                else:
                    status = "sat"
            elif vresult == "unsat":
                if code != 20:
                    status = "wrong"
                    print(f"# WRONG {path.name}: UNSAT exit code {code}, expected 20", file=sys.stderr)
                elif expected == "sat":
                    status = "wrong"
                    print(f"# WRONG {path.name}: UNSAT contradicts published SAT", file=sys.stderr)
                elif expected == "unsat":
                    status = "unsat"
                else:
                    # The run interface has no certificate path. Never score a
                    # previously unresolved UNSAT claim as a solved row merely
                    # because the solver printed it.
                    status = "unsat-unverified"
                    print(
                        f"# UNVERIFIED {path.name}: no published verdict or proof check",
                        file=sys.stderr,
                    )
            else:
                status = "unknown"
        # PAR-2 charges twice the timeout to every unsolved or invalid row.
        score = elapsed if status in ("sat", "unsat") else 2 * args.timeout
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
    f.add_argument("--all", action="store_true",
                   help="download all 400 official main-track instances; ignore subset filters")
    f.add_argument("--max-field-seconds", type=float, default=60.0,
                   help="keep instances the fastest entrant solved within this many seconds")
    f.add_argument("--min-field-seconds", type=float, default=0.0,
                   help="lower bound on the same, for fetching a harder tier separately")
    f.add_argument("--max-bytes", type=int, default=25_000_000, help="compressed size ceiling")
    f.add_argument("--per-family", type=int, default=2)
    f.add_argument("--jobs", type=int, default=8)
    f.set_defaults(func=cmd_fetch)

    v = sub.add_parser("verify", help="verify complete published-track coverage")
    v.add_argument("--dir", type=Path, default=DEFAULT_DIR)
    v.add_argument(
        "--deep",
        action="store_true",
        help="also stream every token and verify complete DIMACS counts/ranges",
    )
    v.set_defaults(func=cmd_verify)

    r = sub.add_parser("run", help="run a solver, emit competition-format rows")
    r.add_argument("--dir", type=Path, default=DEFAULT_DIR)
    r.add_argument("--solver", nargs="+", default=[str(Path(__file__).resolve().parents[1] / "bin" / "wassat")])
    r.add_argument("--solver-args", nargs="*", default=["--fast"])
    r.add_argument("--solverid", default="tungsten_wassat[local]")
    r.add_argument("--timeout", type=float, default=60.0)
    r.add_argument("--verdict", choices=("any", "sat", "unsat", "unknown"), default="any",
                   help="run only rows with this published verdict")
    r.add_argument("--max-file-bytes", type=int, default=0,
                   help="run only materialized CNFs at or below this size")
    r.add_argument("--min-field-seconds", type=float, default=0.0,
                   help="lower bound on the fastest published solve")
    r.add_argument("--max-field-seconds", type=float,
                   help="upper bound on the fastest published solve")
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
