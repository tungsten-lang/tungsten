"""stepscan (L7): the approach of an approach-params file (planner on, j_ik 0, j_il 0: the chunk jump) on a list of seeds, WITHOUT state captures:
per seed the planner's debug lines at every running touchdown (side, time, gap = line - toe as the planner sees it, step, running stride, n, planned
step, pen side), the runway touchdowns of the task (foot, time, toe - line, COM vx, COM x), whether a plant (a `*_board` chunk) happened, and the
take-off toe offset. LABELLED beyond-human body, unlimited run-up (task long_jump_v4_beyond_a, check mark 151.025 m).
usage: stepscan.py <params> <controller> <seeds> <out.json> [k=v,...] [workers]
  seeds: comma list / ranges.  Needs the env of scratchpad/lj7/env7.sh (the profile) and spawn workers (script file + main guard)."""
import json
import multiprocessing as mp
import os
import sys

os.environ.setdefault("MUJOCO_GL", "cgl")
HERE = "/Users/erik/tungsten/bits/tungsten-robolab/playground"
sys.path.insert(0, HERE)


def parse_seeds(spec):
    out = []
    for tok in spec.split(","):
        tok = tok.strip()
        if "-" in tok[1:]:
            a, b = tok.split("-")
            out += list(range(int(a), int(b) + 1))
        else:
            out.append(int(tok))
    return out


def parse_dbg(t, cmd):
    # dbg:td:<side>:t=<t>:gap=<d>:step=<s>:stride=<stride>:n=<n>:plan=<plan>:pen=<side or empty>
    tok = cmd.split(":")
    if len(tok) < 10 or tok[1] != "td":
        return None
    kv = {}
    for x in tok[3:]:
        if "=" in x:
            k, v = x.split("=", 1)
            kv[k] = v
    try:
        return {"side": tok[2], "t": float(kv["t"]), "gap": float(kv["gap"]), "step": float(kv["step"]), "stride": float(kv["stride"]),
                "n": int(float(kv["n"])), "plan": float(kv["plan"]), "pen": kv.get("pen", "")}
    except (KeyError, ValueError):
        return None


def job(args):
    import arena
    from bridge import Sim
    import importlib
    params_path, ctl, seed, extra = args
    env = {"ROBOLAB_CALIB": "v4", "ROBOLAB_PROFILE": "beyond", "ROBOLAB_PROFILE_PARTS": "strength,speed,tendon,activation"}
    for k, v in env.items():
        os.environ[k] = v
    task = importlib.import_module("tasks.long_jump_v4_beyond_a").TASK()
    task.seed = seed
    params = arena.read_params(params_path)
    params["j_ik"] = 0.0
    params["j_il"] = 0.0
    params["j_debug"] = 1.0
    for k, v in extra.items():
        params[k] = float(v)
    dbg = []
    orig = task.on_command

    def on_cmd(m, d, cmd):
        if cmd.startswith("dbg:"):
            r = parse_dbg(d.time, cmd)
            if r is not None:
                dbg.append(r)
        return orig(m, d, cmd)

    task.on_command = on_cmd
    sim = Sim(task, params=params, controller=os.path.abspath(ctl))
    m = sim.run(task.seconds)
    plant = any(row[1].endswith("_board") or row[1].endswith("_ik") for row in sim.log)
    pen = None
    for r in dbg:
        if r["pen"]:
            pen = r
            break
    tds = [(k[0], k[1], k[2], k[3], k[4]) for k in task.touchdowns if k[4] > task.board_x - 40.0]
    return {"seed": seed, "fell": bool(m.get("fell_approach")), "plant": bool(plant), "pen": pen, "dbg": [r for r in dbg if r["gap"] < 40.0],
            "tds": tds, "takeoff_off": m.get("board_offset_m"), "foul": bool(m.get("foul")), "official": m.get("official_m"),
            "vx_board": m.get("speed_at_board"), "t_board": m.get("t_at_board")}


def main():
    params_path, ctl, seeds, out = sys.argv[1:5]
    extra = dict(kv.split("=") for kv in (sys.argv[5] if len(sys.argv) > 5 else "").split(",") if kv)
    workers = int(sys.argv[6]) if len(sys.argv) > 6 else 2
    seeds = parse_seeds(seeds)
    jobs = [(params_path, ctl, s, extra) for s in seeds]
    with mp.get_context("spawn").Pool(workers) as pool:
        rows = pool.map(job, jobs)
    json.dump({"params": params_path, "controller": ctl, "extra": extra, "rows": rows}, open(out, "w"))
    gaps = [r["pen"]["gap"] for r in rows if r["pen"] and r["plant"]]
    import numpy as np
    g = np.array(gaps)
    print("stepscan %s seeds %d: with pen+plant %d, no plant %d, no pen %d; gap mean %.3f sd %.3f (min %.2f max %.2f)" % (
        os.path.basename(params_path), len(rows), len(gaps), sum(1 for r in rows if not r["plant"]), sum(1 for r in rows if not r["pen"]),
        g.mean() if len(g) else float("nan"), g.std() if len(g) else float("nan"), g.min() if len(g) else float("nan"), g.max() if len(g) else float("nan")))


if __name__ == "__main__":
    main()
