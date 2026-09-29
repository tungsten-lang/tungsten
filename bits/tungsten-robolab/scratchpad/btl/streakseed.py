import sys
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks"); sys.path.insert(0, "scratchpad/btl")
from multiprocessing import Pool
from evalfp import run
from grid import load
if __name__ == "__main__":
    params = load(sys.argv[2])
    with Pool(2) as p:
        res = p.map(run, [(sys.argv[1], params, s, float(sys.argv[5])) for s in range(int(sys.argv[3]), int(sys.argv[4]))])
    for r in sorted(res, key=lambda r: -r[2])[:5]: print("seed", r[0], "btl streak", r[2], "pass streak", r[3], "ok", r[4], "/", r[5])
