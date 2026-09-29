import sys
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from multiprocessing import Pool
from grid import load, run
if __name__ == "__main__":
    ctl, pfile = sys.argv[1], sys.argv[2]
    params = load(pfile)
    seeds = list(range(int(sys.argv[3]), int(sys.argv[4])))
    with Pool(4) as p:
        res = p.map(run, [(ctl, params, s, 2.4, 0) for s in seeds])
    ok = [r[1] for r in res if r[2] and r[2]["outcome"] == "ok"]
    print(",".join(str(x) for x in ok), len(ok), "/", len(seeds))
