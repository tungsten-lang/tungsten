"""The parameter set of one run of a tt_rsm.py design (round 10): the params file + the design's --set overrides + that run's levels.

    .venv-myo/bin/python playground/tt_rsm_run_params.py --out out/tt_r10/rsm_bh3 --run 5 --write params/x.txt
    .venv-myo/bin/python playground/tt_rsm_run_params.py --out out/tt_r10/rsm_bh3 --top 3      # the best runs by score
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import tt_fast  # noqa: E402


def run_params(out, r):
    meta = json.load(open(os.path.join(out, "design.json")))
    params = tt_fast.read_params(meta["params"])
    for kv in filter(None, meta["set"].split(",")):
        k, v = kv.split("=")
        params[k] = float(v)
    if r >= 0:
        for (n, lo, hi), x in zip(meta["factors"], meta["design"][r]):
            params[n] = lo if x < 0 else hi
    return params


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--run", type=int)
    ap.add_argument("--top", type=int)
    ap.add_argument("--write")
    a = ap.parse_args()
    if a.top:
        runs = [json.loads(l) for l in open(os.path.join(a.out, "runs.jsonl")) if l.strip()]
        base = [x for x in runs if x["run"] < 0][0]
        best = sorted([x for x in runs if x["run"] >= 0], key=lambda x: -x["score"])[:a.top]
        print(f"baseline score {base['score']:.4f} solved {base['solved']:.2f} hit {base['hit']:.2f}")
        for x in best:
            print(f"run {x['run']}: score {x['score']:.4f} solved {x['solved']:.2f} hit {x['hit']:.2f}")
        return
    p = run_params(a.out, a.run)
    if a.write:
        with open(a.write, "w") as f:
            f.write(f"# tt_rsm design {a.out} run {a.run}\n")
            for k in sorted(p):
                f.write(f"{k} {float(p[k])!r}\n")
    else:
        print(json.dumps(p))


if __name__ == "__main__":
    main()
