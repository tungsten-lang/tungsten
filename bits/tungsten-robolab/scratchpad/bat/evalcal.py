"""Evaluate params with the calibrated-aim objective (playground/bat_search.py analyse) on a pitch set, one line per setting.

    .venv/bin/python scratchpad/bat/evalcal.py --params P --controller C --seeds 3008,... [--sets "a=1;b=2,c=3;..."] [--name x]

`--sets` is a ';'-separated list of comma-separated overrides, each evaluated in turn (a scan); '' or 'base' is the params as they are.
"""
import argparse, json, os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
import bat_rep
import bat_search

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--params", required=True)
    ap.add_argument("--controller", required=True)
    ap.add_argument("--seeds", required=True)
    ap.add_argument("--sets", default="base")
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--seconds", type=float, default=4.3)
    ap.add_argument("--risk", type=float, default=0.25)
    ap.add_argument("--name")
    a = ap.parse_args()
    base = bat_rep.read_params(a.params)
    seeds = bat_rep.parse_seeds(a.seeds)
    out = []
    for spec in a.sets.split(";"):
        over = {} if spec in ("", "base") else bat_rep.parse_set(spec)
        params = {**base, **over}
        rows = bat_rep.run_many([bat_rep.job(params, a.controller, s, a.seconds) for s in seeds], a.workers)
        recs = []
        for r in rows:
            if r["rec"].get("aim_n_cm") is None or r["rec"].get("flow") is None:
                recs = None
                break
            recs.append(r["rec"])
        sm = bat_rep.summarise(rows)
        if recs is None:
            print(f"{spec or 'base':<40} crashed/no record", flush=True)
            continue
        an = bat_search.analyse(recs)
        per = an["per"]
        obj = float(np.mean(per) - a.risk * (np.mean(per) - np.min(per)))
        line = (f"{spec or 'base':<40} calibrated obj {obj:7.3f} speed {an['speed'].mean():.3f} (as run: hits {sm['hits']}/{sm['n']} power {sm['power']:.3f}) "
                f"flow {an['flow'].mean():.3f} max {an['flow'].max():.3f} | aim a0 {an['coef'][0]:+.1f} az {an['coef'][1]:+.0f} ax {an['coef'][2]:+.0f} "
                f"resid rms {np.sqrt(np.mean(an['aim_res'] ** 2)):.2f} max {np.abs(an['aim_res']).max():.1f} | "
            f"contact s mean {np.mean([r['aim_s'] for r in recs]):.3f} [{min(r['aim_s'] for r in recs):.2f}, {max(r['aim_s'] for r in recs):.2f}]")
        print(line, flush=True)
        out.append({"spec": spec, "summary": sm, "line": line, "rows": rows})
    if a.name:
        os.makedirs(os.path.join(ROOT, "out", "bat_r2"), exist_ok=True)
        json.dump(out, open(os.path.join(ROOT, "out", "bat_r2", a.name + ".json"), "w"), indent=1)


if __name__ == "__main__":
    main()
