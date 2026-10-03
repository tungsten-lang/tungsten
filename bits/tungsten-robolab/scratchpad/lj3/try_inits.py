"""Score ideal-control optima of other starts / bodies, mapped by role, on this capture (L3 scratch).
usage: try_inits.py <capture> <init.json> [<init.json> ...]"""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
import long_jump_limits as L


def main():
    name = sys.argv[1]
    cap = L.load_capture(name)
    body = L.Body(cap["task"], cap["board_x"], json.loads(cap["env"]))
    for path in sys.argv[2:]:
        ji = json.load(open(path))
        iplant = ji.get("plant") or L.load_capture(ji["name"])["plant"]
        by_role = {L.role_of(n, iplant): v for n, v in ji["knots"].items()}
        Xi = np.array([by_role[L.role_of(n, cap["plant"])] for n in body.muscles])
        X = np.zeros((len(body.muscles), 24))
        X[:, :min(24, Xi.shape[1])] = Xi[:, :24]
        if Xi.shape[1] < 24:
            X[:, Xi.shape[1]:] = Xi[:, -1:]
        r = L.simulate(body, cap, lambda t, k: L.excitation(X, t))
        s = L.score(r, -1.5)
        print("%-50s nk %d valid %s score %.2f %s" % (os.path.basename(path), Xi.shape[1], r["valid"], s,
              {k: round(v, 3) for k, v in r.items() if k in ("D", "vx", "vz", "contact_s", "L", "t", "progress")} if r["valid"] else (r.get("why"), round(r.get("t", 0), 3))))


main()
