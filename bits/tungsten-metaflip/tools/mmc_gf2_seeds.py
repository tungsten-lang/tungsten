#!/usr/bin/env python3
"""matmulcatalog recipes -> exact GF(2) seeds, with attribution.

  targets  choose catalogue schemes worth replaying: stamped F2, not commutative, rank at most
           (best listed rank in the other sources) + SLACK, and nothing on our scoreboard at or
           below that rank
  replay   materialize targets over GF(2), verify each against the complete matrix-multiplication
           tensor, and write MFW1 seeds plus seeds.json

Each seed row carries the attribution its tensor depends on: the catalogue file (repository,
pinned revision, recorded source/year), every atomic catalogue scheme the recipe used
(Perminov, AlphaTensor, AlphaEvolve, Hopcroft-Kerr, ... as the catalogue records them), and
any local witnesses used as leaves. seeds.json rows are also valid input for
`screen_public_ternary_gf2.py walk`.

matmulcatalog: https://github.com/solven-eu/matmulcatalog (arXiv:2606.13408). Its F2 stamp can
over-claim (a recipe may need a Q/F3-only leaf); `replay` records such targets as failures with
the reason instead of emitting a tensor above the catalogue's rank.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import traceback
from types import SimpleNamespace

if not __debug__:
    raise RuntimeError("tensor verification relies on assert; do not run with -O")

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import mmc_gf2_replay as MR  # noqa: E402
import screen_top_two_projection_children as top  # noqa: E402

REPOSITORY = "https://github.com/solven-eu/matmulcatalog"
_STATE = {}


def board_leaves(path):
    """{sorted shape: (rank, witness path)} from a gf2_record_board.py --json scoreboard."""
    board = {}
    for row in json.loads(Path(path).read_text()):
        key = tuple(sorted(int(x) for x in row["shape"].split("x")))
        if os.path.exists(row["path"]):
            board[key] = (row["rank"], row["path"])
    return board


def select_targets(args):
    import gf2_record_board as grb
    source = MR.Source(args.clone, args.revision, args.cache_dir)
    _, other, _ = grb.public_tables(SimpleNamespace(
        lille=args.lille, matmulcatalog=None, fmm_repo=args.fmm_repo, fmm_revision=args.fmm_revision,
        extra_repo=args.extra_repo))
    ours = {k: v[0] for k, v in board_leaves(args.board).items()}
    best = {}
    for e in source.catalog:
        if e.get("commutative") or e.get("complex") or "F2" not in (e.get("fields") or []):
            continue
        key = tuple(sorted(e["format"]))
        if min(key) < args.min_dim or max(key) > 32 or e["rank"] > other.get(key, 10 ** 9) + args.slack:
            continue
        if key in ours and ours[key] <= e["rank"]:
            continue
        if key not in best or (e["rank"], e["file"]) < (best[key]["rank"], best[key]["file"]):
            best[key] = e
    targets = [dict(mmc_file=e["file"], canonical="x".join(map(str, key)), mmc_rank=e["rank"],
                    public=other.get(key), board=ours.get(key), atom=bool(e.get("atom")),
                    lineage_compact=e.get("lineage_compact"))
               for key, e in sorted(best.items(), key=lambda kv: (kv[1]["rank"], kv[0]))]
    Path(args.out).write_text(json.dumps(dict(repository=REPOSITORY, revision=source.revision,
                                              targets=targets), indent=1) + "\n")
    below = sum(1 for t in targets if t["public"] is not None and t["mmc_rank"] < t["public"])
    print(f"{len(targets)} targets at {source.revision[:12]} ({below} below the other sources' best rank)")
    return 0


def _replayer(args):
    if "rp" not in _STATE:
        source = MR.Source(args.clone, args.revision, args.cache_dir)
        board = board_leaves(args.board) if args.board else None
        _STATE["source"] = source
        _STATE["rp"] = MR.Replayer(source, board=board, allow_nonf2=args.allow_nonf2)
    return _STATE["source"], _STATE["rp"]


def replay_one(args, target):
    """One target -> result row; the tensor file is written only after the full gate."""
    t0 = time.time()
    source, rp = _replayer(args)
    f = target["mmc_file"]
    row = dict(mmc_file=f, mmc_rank=target["mmc_rank"], canonical=target["canonical"])
    try:
        rp.dep_stack = [set()]
        a = rp.materialize_file(f)
        deps = rp.deps_file.get(f, set())
        atoms = sorted(d[1] for d in deps if d[0] == "atom")
        leaves = sorted(d for d in deps if isinstance(d[0], int))
        nonf2 = sorted("x".join(map(str, d[1:])) for d in deps if d[0] == "nonf2")
        shape = tuple(source.load(f)["n"])
        assert a.shape == shape
        terms = sorted(a.terms)
        if len(terms) > target["mmc_rank"]:
            raise MR.ReplayError("GF(2) rank %d above catalogue rank %d" % (len(terms), target["mmc_rank"]))
        top.exact(shape, terms)
        raw = top.blob(shape, terms)
        assert top.read_blob(raw) == (shape, terms)
        digest = hashlib.sha256(raw).hexdigest()
        path = Path(args.out) / ("%dx%dx%d_r%d_mmc_%s.mfw" % (shape + (len(terms), digest[:8])))
        tmp = path.with_name(path.name + ".tmp%d" % os.getpid())
        tmp.write_bytes(raw)
        os.replace(tmp, path)
        entry = source.by_file.get(f, {})
        board_info = []
        for key in leaves:
            rank, witness = rp.board[tuple(key)]
            import gf2_record_board as grb
            board_info.append(dict(shape="x".join(map(str, key)), rank=rank,
                                   sha256=hashlib.sha256(grb.load(Path(witness))).hexdigest()))
        row.update(
            status="ok", shape="x".join(map(str, shape)), gf2_rank=len(terms), mfw=str(path), mfw_sha256=digest,
            lineage_compact=entry.get("lineage_compact"), nonf2_leaves=nonf2,
            leaf_mode="wide" if nonf2 else "board" if board_info else "pure",
            attribution=dict(
                catalogue=dict(repository=REPOSITORY, revision=source.revision, file=f,
                               source=entry.get("source"), year=entry.get("year"),
                               lineage=entry.get("lineage_compact")),
                atoms=[source.atom_info(p) for p in atoms], board_leaves=board_info))
    except Exception as e:  # noqa: BLE001 -- record every failure with its reason
        reason = "%s: %s" % (type(e).__name__, str(e)[:500])
        if not isinstance(e, (MR.ReplayError, AssertionError)):
            reason += " | " + " / ".join(traceback.format_exc().splitlines()[-4:])[:400]
        row.update(status="fail", reason=reason)
    row["secs"] = round(time.time() - t0, 2)
    return row


def _work(pair):
    return replay_one(*pair)


def replay(args):
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    doc = json.loads(Path(args.targets).read_text())
    targets = doc["targets"] if isinstance(doc, dict) else doc
    if args.only:
        wanted = set(args.only)
        targets = [t for t in targets if t["canonical"] in wanted or t["mmc_file"] in wanted]
    results = out / "results.jsonl"
    done = {}
    if results.exists():
        for line in results.read_text().splitlines():
            r = json.loads(line)
            done[r["mmc_file"]] = r
    todo = [t for t in targets if t["mmc_file"] not in done or
            (args.retry_failed and done[t["mmc_file"]]["status"] != "ok")]
    todo.sort(key=lambda t: (t["mmc_rank"], t["mmc_file"]))
    print(f"{len(todo)} targets to replay ({len(done)} already recorded)", flush=True)
    with open(results, "a") as log:
        if args.jobs > 1:
            pool = concurrent.futures.ProcessPoolExecutor(args.jobs)
            futures = [pool.submit(_work, (args, t)) for t in todo]
            stream = (f.result() for f in concurrent.futures.as_completed(futures))
        else:
            pool, stream = None, (replay_one(args, t) for t in todo)
        for row in stream:
            log.write(json.dumps(row) + "\n")
            log.flush()
            done[row["mmc_file"]] = row
            print(row["status"], row["canonical"], row.get("gf2_rank", ""), "catalogue", row["mmc_rank"],
                  row.get("reason", "")[:90], flush=True)
        if pool is not None:
            pool.shutdown()
    seeds = sorted((r for r in done.values() if r["status"] == "ok"),
                   key=lambda r: (r["mmc_rank"], r["mmc_file"]))
    seeds = [dict(shape=r["shape"], canonical=r["canonical"], gf2_rank=r["gf2_rank"], mfw=r["mfw"],
                  mfw_sha256=r["mfw_sha256"], mmc_file=r["mmc_file"], mmc_rank=r["mmc_rank"],
                  leaf_mode=r["leaf_mode"], attribution=r["attribution"]) for r in seeds]
    (out / "seeds.json").write_text(json.dumps(seeds, indent=1) + "\n")
    failed = sum(1 for r in done.values() if r["status"] != "ok")
    print(f"{len(seeds)} exact GF(2) seeds, {failed} failures -> {out / 'seeds.json'}")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)

    def common(p):
        p.add_argument("--clone", required=True, help="local matmulcatalog clone (a partial clone works)")
        p.add_argument("--revision", default="HEAD", help="pinned catalogue revision (recorded per seed)")
        p.add_argument("--cache-dir", default="mmc-cache")

    t = sub.add_parser("targets", help="select catalogue schemes worth replaying")
    common(t)
    t.add_argument("--lille", required=True, help="fmm_digest fmm_sota.json")
    t.add_argument("--fmm-repo", help="FastMatrixMultiplication clone")
    t.add_argument("--fmm-revision", default="HEAD")
    t.add_argument("--extra-repo", action="append", default=[])
    t.add_argument("--board", required=True, help="scoreboard JSON from gf2_record_board.py --json")
    t.add_argument("--slack", type=int, default=0, help="also accept ranks up to best listed + SLACK")
    t.add_argument("--min-dim", type=int, default=2)
    t.add_argument("--out", required=True)
    t.set_defaults(func=select_targets)
    r = sub.add_parser("replay", help="materialize targets over GF(2) into exact seeds")
    common(r)
    r.add_argument("--targets", required=True)
    r.add_argument("--out", required=True)
    r.add_argument("--board", help="scoreboard JSON: exact local witnesses may serve as leaves")
    r.add_argument("--allow-nonf2", action="store_true", help="diagnostics: also replay non-F2 schemes")
    r.add_argument("--retry-failed", action="store_true")
    r.add_argument("--only", nargs="*", help="canonical shapes or catalogue files to replay")
    r.add_argument("--jobs", type=int, default=1)
    r.set_defaults(func=replay)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
