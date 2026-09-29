"""Per-pass catchability on seeds: rise apex and horizontal speed at the touch, by pass index."""
import sys, numpy as np
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks"); sys.path.insert(0, "scratchpad/btl")
from multiprocessing import Pool
from grid import load
from evalfp import run
if __name__ == "__main__":
    ctl, pfile, s0, s1, secs = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5])
    params = load(pfile); params.update({k: float(v) for k, v in (kv.split("=") for kv in (sys.argv[6] if len(sys.argv) > 6 else "").split(",") if kv)})
    with Pool(4) as p:
        res = p.map(run, [(ctl, params, s, secs) for s in range(s0, s1)])
    for k in range(3):
        pl = [r[1][k] for r in res if len(r[1]) > k]
        ap = [x["rise_apex"] for x in pl if x.get("rise_apex")]; vh = [x["recv_vh"] for x in pl if x.get("recv_vh")]
        ok = sum(1 for x in pl if x["ok"])
        print(f"pass {k+1}: n {len(pl)} ok {ok}  apex {np.mean(ap):.2f} (sd {np.std(ap):.2f})  vh at touch {np.mean(vh):.2f} (sd {np.std(vh):.2f})" if ap else f"pass {k+1}: n {len(pl)}")
    print("streaks", sorted([r[2] for r in res], reverse=True)[:8])
