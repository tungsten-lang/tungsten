"""Approach-only rollouts (j_run 1) on the LABELLED BEYOND-HUMAN body, unlimited run-up (agent L3).
Per start: fell, v5 (mean COM speed over the last 5 m before the check mark), COM vx 1 m before the line (speed_at_board),
arrival time, the last touchdowns' toe positions relative to the line (foot placement) and the step lengths.
usage: runup.py <params> <controller> <task> <board_m> <seeds> [k=v,...] [workers]
  seeds: comma list / ranges ('None' = nominal), e.g. None,601-616"""
import os
import sys
import importlib
import multiprocessing as mp

os.environ.setdefault("MUJOCO_GL", "cgl")
HERE = "/Users/erik/tungsten/bits/tungsten-robolab/playground"
sys.path.insert(0, HERE)


def parse_seeds(spec):
    out = []
    for tok in spec.split(","):
        tok = tok.strip()
        if tok == "None":
            out.append(None)
        elif "-" in tok[1:]:
            a, b = tok.split("-")
            out += list(range(int(a), int(b) + 1))
        else:
            out.append(int(tok))
    return out


def job(args):
    import numpy as np
    import arena
    from bridge import Sim
    params_path, ctl, task_name, board, seed, extra = args
    os.environ["ROBOLAB_LJ_APPROACH"] = str(board)
    env = {"ROBOLAB_CALIB": "v4", "ROBOLAB_PROFILE": "beyond", "ROBOLAB_PROFILE_PARTS": "strength,speed,tendon,activation"}
    for k, v in env.items():
        os.environ[k] = v
    task = importlib.import_module(f"tasks.{task_name}").TASK()
    task.seed = seed
    params = arena.read_params(params_path)
    params["j_run"] = 1.0
    params.pop("j_ik", None)
    params.pop("j_il", None)
    for k, v in extra.items():
        params[k] = float(v)
    sim = Sim(task, params=params, controller=os.path.abspath(ctl))
    m = sim.run(task.seconds)
    tr = np.array(task.run_trace)
    x, t, vx = tr[:, 1], tr[:, 0], tr[:, 2]
    res = {"seed": seed, "fell": bool(m.get("fell_approach")), "max_x": float(x.max()) if len(x) else 0.0,
           "t_end": float(t[-1]) if len(t) else 0.0}
    if len(x) > 10 and x.max() > board:
        i1 = np.searchsorted(x, board)
        i0 = np.searchsorted(x, board - 5.0)
        res["v5"] = float((x[i1] - x[i0]) / (t[i1] - t[i0]))
        res["t_board"] = float(t[i1])
        ib = np.searchsorted(x, board - 1.0)
        res["vb"] = float(vx[ib])
        # the touchdowns before the line: (foot, toe x - line, COM vx)
        tds = [k for k in task.touchdowns if k[4] < board + 1.0]
        res["tds"] = [(k[0], round(k[2], 3), k[3]) for k in tds[-5:]]
        steps = [tds[i][2] - tds[i - 1][2] for i in range(max(1, len(tds) - 4), len(tds))]
        res["steps"] = [round(s, 3) for s in steps]
        res["vmax_1s"] = 0.0
        k = 100
        if len(x) > k:
            res["vmax_1s"] = float(((x[k:] - x[:-k]) / (t[k:] - t[:-k])).max())
    return res


def main():
    params_path, ctl, task_name, board, seeds = sys.argv[1:6]
    extra = dict(kv.split("=") for kv in (sys.argv[6] if len(sys.argv) > 6 else "").split(",") if kv)
    workers = int(sys.argv[7]) if len(sys.argv) > 7 else 2
    seeds = parse_seeds(seeds)
    jobs = [(params_path, ctl, task_name, float(board), s, extra) for s in seeds]
    with mp.get_context("spawn").Pool(workers) as pool:
        rows = pool.map(job, jobs)
    ok = [r for r in rows if "v5" in r and not r["fell"]]
    for r in rows:
        print("seed %-5s fell %-5s v5 %s vb %s t_board %s t_end %.1f steps %s tds %s" % (
            r["seed"], r["fell"], ("%.3f" % r["v5"]) if "v5" in r else "-", ("%.3f" % r["vb"]) if "vb" in r else "-",
            ("%.2f" % r["t_board"]) if "t_board" in r else "-", r["t_end"], r.get("steps", "-"), r.get("tds", "-")))
    if ok:
        v = [r["v5"] for r in ok]
        mean = sum(v) / len(v)
        sd = (sum((a - mean) ** 2 for a in v) / max(1, len(v) - 1)) ** 0.5
        n95 = sum(1 for a in v if a >= 9.5)
        print("SUMMARY %s params %s board %s %s: n %d fell %d v5 mean %.3f sd %.3f min %.3f max %.3f; v5>=9.5 on %d" % (
            os.path.basename(ctl), os.path.basename(params_path), board, extra, len(rows), sum(r["fell"] for r in rows),
            mean, sd, min(v), max(v), n95))
    else:
        print("SUMMARY no start reached the board: fell", sum(r["fell"] for r in rows), "of", len(rows))


if __name__ == "__main__":
    main()
