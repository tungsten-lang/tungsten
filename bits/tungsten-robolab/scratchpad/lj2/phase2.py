"""Left/right foot touchdown positions in the last strides before the check mark, double contacts merged (L2 scratch).
usage: phase2.py <params> <controller> <task> <board_m> <seeds> [k=v,...] [workers]"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import phase


def main():
    import numpy as np, multiprocessing as mp
    params_path, ctl, task_name, board, seeds = sys.argv[1:6]
    extra = dict(kv.split("=") for kv in (sys.argv[6] if len(sys.argv) > 6 else "").split(",") if kv)
    workers = int(sys.argv[7]) if len(sys.argv) > 7 else 2
    seeds = phase.parse_seeds(seeds)
    jobs = [(params_path, ctl, task_name, float(board), s, extra) for s in seeds]
    with mp.get_context("spawn").Pool(workers) as pool:
        rows = pool.map(phase.job, jobs)
    L, R = [], []
    for r in rows:
        if r["fell"]:
            continue
        tds = []
        for t in r["tds"]:
            if tds and tds[-1][0] == t[0] and t[1] - tds[-1][1] < 0.12:
                continue   # a second contact of the same foot within 0.12 s: one touchdown
            tds.append(t)
        l = [t for t in tds if t[0] == "l" and t[2] < -0.2]
        rr = [t for t in tds if t[0] == "r" and t[2] < -0.2]
        L.append(l[-1][2]); R.append(rr[-1][2])
        print("seed %-5s last l %.2f last r %.2f | all %s" % (r["seed"], l[-1][2], rr[-1][2], [(t[0], round(t[2], 2)) for t in tds[-5:]]))
    L, R = np.array(L), np.array(R)
    print("last l-touchdown before the line: mean %.2f sd %.2f min %.2f max %.2f" % (L.mean(), L.std(), L.min(), L.max()))
    print("last r-touchdown before the line: mean %.2f sd %.2f min %.2f max %.2f" % (R.mean(), R.std(), R.min(), R.max()))


if __name__ == "__main__":
    main()
