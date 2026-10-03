"""Drive sep-CMA on the harness by hand and print per-generation stats (L3 scratch)."""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
import long_jump_limits as L
from search import make_optimizer


def main():
    name = sys.argv[1]
    sigma = float(sys.argv[2]); pop = int(sys.argv[3]); gens = int(sys.argv[4])
    lmax = -1.5
    cap = L.load_capture(name)
    body = L.Body(cap["task"], cap["board_x"], json.loads(cap["env"]))
    nm = len(body.muscles)
    X0 = L.x_from_recorded(cap, nm)
    x0 = X0.ravel()
    opt = make_optimizer("sep_cma", x0, sigma0=sigma, seed=1, **({"popsize": pop} if pop else {}))
    best = -1e9
    for g in range(gens):
        X = np.clip(np.atleast_2d(opt.ask()), 0, 1)
        f = []
        for x in X:
            r = L.simulate(body, cap, lambda t, k: L.excitation(x.reshape(nm, -1), t))
            f.append(L.score(r, lmax))
        f = np.array(f)
        opt.tell(X, f, None)
        best = max(best, f.max())
        if g % 5 == 0:
            print("gen %3d pop %d f mean %.2f med %.2f max %.2f best %.2f sigma %.4f" % (g, len(f), f.mean(), np.median(f), f.max(), best, opt.sigma), flush=True)


main()
