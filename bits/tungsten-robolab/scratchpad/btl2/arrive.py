"""Where pass k's ball arrives (rises through z 0.62) vs the spot it was aimed at, its apex, and the outcome.
   .venv/bin/python scratchpad/btl2/arrive.py ctl params s0 s1 secs [overrides] [workers]"""
import sys
sys.path.insert(0, "scratchpad/btl2")
from multiprocessing import Pool
import numpy as np
from common import load, parse_over, run_seed
from dribble_btl import spots_of
def main():
    ctl, pfile, s0, s1, secs = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5])
    over = sys.argv[6] if len(sys.argv) > 6 else ""
    workers = int(sys.argv[7]) if len(sys.argv) > 7 else 2
    params = load(pfile); params.update(parse_over(over))
    lead, back = spots_of(params)
    with Pool(workers) as p:
        res = p.map(run_seed, [(ctl, params, s, secs) for s in range(s0, s1)])
    print("lead spot", lead, "back spot", back)
    for r in res:
        row = []
        for k, pl in enumerate(r["pass_log"][:3]):
            spot = lead if k % 2 == 0 else back
            a = pl.get("arrive_xy")
            e = (a[0] - spot[0], a[1] - spot[1]) if a else None
            row.append(f"p{k+1} {'OK' if pl['ok'] else '--'} arr err {('%+.2f %+.2f' % e) if e else 'none':>12s} bounce_gd {pl.get('bounce_gd') and round(pl['bounce_gd'],2)} apex {pl.get('rise_apex') and round(pl['rise_apex'],2)} vh {pl.get('recv_vh') and round(pl['recv_vh'],2)} miss {pl.get('miss') and round(pl['miss'],3)} out {str(pl['outcome'])[:4]} gate {pl['gate']}")
        print(r["seed"], " | ".join(row))
if __name__ == "__main__":
    main()
