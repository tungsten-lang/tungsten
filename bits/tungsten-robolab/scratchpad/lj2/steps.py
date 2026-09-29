"""Mean step length / speed in the last 10 m before the check mark for param overrides (approach only), L2 scratch.
usage: steps.py <params> <controller> <task> <board_m> <seeds> "<k=v,...>" ["<k=v,...>" ...]"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import phase3, phase
import multiprocessing as mp


def main():
    import numpy as np
    params_path, ctl, task_name, board, seeds = sys.argv[1:6]
    cfgs = sys.argv[6:]
    seeds = phase.parse_seeds(seeds)
    for cfg in cfgs:
        extra = dict(kv.split("=") for kv in cfg.split(",") if kv)
        jobs = [(params_path, ctl, task_name, float(board), s, extra) for s in seeds]
        with mp.get_context("spawn").Pool(2) as pool:
            rows = pool.map(phase3.job, jobs)
        stp, fl, spd = [], [], 0
        nfell = 0
        for r in rows:
            if r["fell"]:
                nfell += 1
                continue
            tds = []
            for t in r["tds"]:
                if tds and tds[-1][0] == t[0] and t[1] - tds[-1][1] < 0.12:
                    continue
                tds.append(t)
            sel = [t for t in tds if float(board) - 10.0 < t[2] < float(board) - 0.5]
            if len(sel) < 4:
                continue
            xs = np.array([t[2] for t in sel]); ts = np.array([t[1] for t in sel])
            stp.append(np.diff(xs).mean()); spd += 0
            fl.append((xs[-1] - xs[0]) / (ts[-1] - ts[0]))
        print("%-40s n %d fell %d step %.3f (sd %.3f) speed %.3f" % (cfg, len(stp), nfell, np.mean(stp), np.std(stp), np.mean(fl)))


if __name__ == "__main__":
    main()
