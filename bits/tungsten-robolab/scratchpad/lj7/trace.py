"""trace (L7): per-control-tick kinematics of the last <metres> of the approach (planner on, j_ik 0, j_il 0: the chunk jump), LABELLED beyond-human body, unlimited run-up
(task long_jump_v4_beyond_a). Per tick: t, chunk label, COM x z vx vz, pelvis x z, both toes (x, z), both heels (x, z), contact flags; plus the planner's debug lines and the
task's runway touchdowns. Used to learn how well a step is predictable at toe-off (the start of the flight chunk).
usage: trace.py <params> <controller> <seeds> <out.json> [k=v,...] [workers] [metres=40]"""
import json
import multiprocessing as mp
import os
import sys

os.environ.setdefault("MUJOCO_GL", "cgl")
HERE = "/Users/erik/tungsten/bits/tungsten-robolab/playground"
sys.path.insert(0, HERE)
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj7")


def job(args):
    import importlib
    import numpy as np
    import mujoco
    import arena
    from bridge import Sim
    from stepscan import parse_dbg, parse_seeds  # noqa: F401
    params_path, ctl, seed, extra, metres = args
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
    m, d = sim.m, sim.d
    task.reset(m, d)
    mujoco.mj_forward(m, d)
    sim.start_controller()
    substeps = max(1, round(task.control_dt / m.opt.timestep))
    ids = {n: d.site(n).id for n in ("l_toe", "r_toe", "l_heel", "r_heel")}
    pel = d.body("pelvis").id
    rows = []
    fell = False
    try:
        while d.time < task.seconds:
            act, c = sim.tick()
            for _ in range(substeps):
                task.before_step(m, d)
                mujoco.mj_step(m, d)
            com = d.subtree_com[pel]
            if com[0] > task.board_x - metres:
                mujoco.mj_subtreeVel(m, d)
                v = d.subtree_linvel[pel]
                lt, rt, lh, rh = (d.site_xpos[ids[n]] for n in ("l_toe", "r_toe", "l_heel", "r_heel"))
                px = d.xpos[pel]
                rows.append((round(d.time, 4), sim.label, float(com[0]), float(com[2]), float(v[0]), float(v[2]), float(px[0]), float(px[2]),
                             float(lt[0]), float(lt[2]), float(rt[0]), float(rt[2]), float(lh[0]), float(lh[2]), float(rh[0]), float(rh[2])))
            sim.log.append((d.time, sim.label, act.copy(), c.copy(), sim.targets.copy()))
            if task.done(m, d):
                fell = True
                break
    finally:
        sim.stop_controller()
    plant = any(r[1].endswith("_board") for r in rows)
    return {"seed": seed, "fell": fell, "plant": plant, "dbg": [r for r in dbg if r["gap"] < 45.0], "rows": rows,
            "tds": [(k[0], k[1], k[2], k[3], k[4]) for k in task.touchdowns if k[4] > task.board_x - metres - 3.0], "board_x": task.board_x}


def main():
    params_path, ctl, seeds, out = sys.argv[1:5]
    extra = dict(kv.split("=") for kv in (sys.argv[5] if len(sys.argv) > 5 else "").split(",") if kv)
    workers = int(sys.argv[6]) if len(sys.argv) > 6 else 2
    metres = float(sys.argv[7]) if len(sys.argv) > 7 else 40.0
    seeds = parse_seeds(seeds)
    jobs = [(params_path, ctl, s, extra, metres) for s in seeds]
    with mp.get_context("spawn").Pool(workers) as pool:
        res = pool.map(job, jobs)
    json.dump({"params": params_path, "extra": extra, "rows": res}, open(out, "w"))
    print("trace %d seeds -> %s" % (len(res), out))


if __name__ == "__main__":
    from stepscan import parse_seeds
    main()
