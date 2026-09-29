"""Run table-tennis serves on the fast path and keep every episode's metrics (round 10).

    TT_ENV=P2 .venv-myo/bin/python playground/tt_eval.py --params params/x.txt --controller bin/x \
        --seeds 700000:700400 --out out/tt_r10/x.jsonl --workers 3 [--set k=v,...] [--env-var NAME=VALUE]

`--seeds a:b` is a range, `--seeds 1,2,3` a list. The output is JSON lines (one episode each, appended as
they finish, so an interrupted run resumes: finished seeds are skipped). The summary line at the end
reports solved / hit and the failure classes (tasks/myo_tt.py failure_class), by side.
"""

import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import tt_fast  # noqa: E402


def parse_seeds(s):
    if ":" in s and "," not in s:
        a, b = s.split(":")
        return list(range(int(a), int(b)))
    return [int(x) for x in s.split(",") if x.strip()]


def load_done(path):
    done = {}
    if path and os.path.exists(path):
        for line in open(path):
            line = line.strip()
            if line:
                r = json.loads(line)
                done[r["seed"]] = r
    return done


def summarize(rows):
    from tasks.myo_tt import failure_class
    n = len(rows)
    sol = sum(1 for r in rows if r.get("solved", 0) > 0)
    hit = sum(1 for r in rows if r.get("hit", 0) > 0)
    out = {"n": n, "solved": sol, "rate": round(sol / max(n, 1), 4), "hit": round(hit / max(n, 1), 4)}
    for side, nm in ((1, "forehand"), (2, "backhand")):
        rs = [r for r in rows if r.get("side") == side]
        if rs:
            out[nm] = {"n": len(rs), "solved": sum(1 for r in rs if r.get("solved", 0) > 0)}
    cls = {}
    for r in rows:
        c = failure_class(r)
        cls[c] = cls.get(c, 0) + 1
    out["classes"] = cls
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--params")
    ap.add_argument("--controller")
    ap.add_argument("--seeds", required=True)
    ap.add_argument("--out")
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--set", default="", help="extra params name=value,...")
    ap.add_argument("--env", help="P1 or P2 (default: TT_ENV, else P2)")
    ap.add_argument("--attr", default="", help="task attributes name=value,... (numbers)")
    a = ap.parse_args()
    os.environ.setdefault("TT_ENV", "P2")
    params = tt_fast.read_params(a.params) if a.params else {}
    for kv in filter(None, a.set.split(",")):
        k, v = kv.split("=")
        params[k] = float(v)
    attrs = {}
    for kv in filter(None, a.attr.split(",")):
        k, v = kv.split("=")
        attrs[k] = float(v)
    ctl = os.path.abspath(a.controller) if a.controller else None
    env_id = f"myoChallengeTableTennis{a.env}-v0" if a.env else None
    seeds = parse_seeds(a.seeds)
    done = load_done(a.out)
    todo = [s for s in seeds if s not in done]
    t0 = time.time()
    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    f = open(a.out, "a") if a.out else None
    if todo:
        pool = tt_fast.pool(a.workers)
        jobs = [(params, s, env_id, ctl, attrs) for s in todo]
        for r in pool.imap(tt_fast.episode, jobs, chunksize=1):
            done[r["seed"]] = r
            if f:
                f.write(json.dumps(r, default=float) + "\n")
                f.flush()
    rows = [done[s] for s in seeds if s in done]
    errs = [r for r in rows if "error" in r]
    summ = summarize([r for r in rows if "error" not in r])
    summ["errors"] = len(errs)
    summ["wall_s"] = round(time.time() - t0)
    print(json.dumps(summ))


if __name__ == "__main__":
    main()
