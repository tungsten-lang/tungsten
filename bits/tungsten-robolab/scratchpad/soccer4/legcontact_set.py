import sys, os, subprocess
# thin wrapper: python legcontact_set.py params controller a:b T "k=v,k=v"
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
from search4 import read_params
import legcontact
if __name__ == "__main__":
    import multiprocessing as mp
    p = read_params(sys.argv[1]); ctl = os.path.abspath(sys.argv[2]); lo, hi = sys.argv[3].split(":"); T = float(sys.argv[4])
    for kv in sys.argv[5].split(","):
        if "=" in kv:
            k, v = kv.split("="); p[k] = float(v)
    with mp.Pool(4) as pool:
        res = pool.map(legcontact.run, [(p, s, ctl, T) for s in range(int(lo), int(hi))])
    import numpy as np
    f = [r[1][0] for r in res if r[1]]; b = [r[1][3] for r in res if r[1]]
    print(sys.argv[5], "mean leg force %.1f N, per seed %s, bal1 %s" % (np.mean(f), [round(x) for x in f], [round(x, 1) for x in b]))
