"""Landscape probe: valid fraction and score spread of x0 + sigma * N(0,1) for several sigma (L3 scratch).
usage: probe_sigma.py <capture> [lmax] [n]"""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
import long_jump_limits as L


def main():
    name = sys.argv[1]
    lmax = float(sys.argv[2]) if len(sys.argv) > 2 else -1.5
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 40
    cap = L.load_capture(name)
    body = L.Body(cap["task"], cap["board_x"], json.loads(cap["env"]))
    nm = len(body.muscles)
    X0 = L.x_from_recorded(cap, nm)
    rng = np.random.default_rng(1)
    for sig in (0.0, 0.005, 0.02, 0.05, 0.12):
        sc, why = [], {}
        for i in range(n if sig > 0 else 1):
            X = np.clip(X0 + sig * rng.standard_normal(X0.shape), 0, 1)
            r = L.simulate(body, cap, lambda t, k: L.excitation(X, t))
            s = L.score(r, lmax)
            sc.append(s)
            if not r["valid"]:
                why[r["why"]] = why.get(r["why"], 0) + 1
        sc = np.array(sc)
        print("sigma %.3f: n %d score mean %.2f min %.2f max %.2f; invalid reasons %s" % (sig, len(sc), sc.mean(), sc.min(), sc.max(), why))
        if sig == 0:
            print("   x0 result:", {k: (round(v, 3) if isinstance(v, float) else v) for k, v in r.items() if k in ("valid", "D", "vx", "vz", "contact_s", "L", "why", "t")})


main()
