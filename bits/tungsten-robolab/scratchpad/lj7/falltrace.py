"""falltrace (L7): whole-run time series (every 4th control tick) of COM vx, pelvis pitch and its rate, chunk label, for a list of seeds (approach params file, j_ik 0, j_il 0).
usage: falltrace.py <params> <controller> <seeds comma list or file.json> <out.json> [workers]"""
import json, math, multiprocessing as mp, os, sys
os.environ.setdefault("MUJOCO_GL", "cgl")
HERE = "/Users/erik/tungsten/bits/tungsten-robolab/playground"
sys.path.insert(0, HERE)


def job(args):
    import importlib
    import numpy as np
    import mujoco
    import arena
    from bridge import Sim
    params_path, ctl, seed = args
    for k, v in {"ROBOLAB_CALIB": "v4", "ROBOLAB_PROFILE": "beyond", "ROBOLAB_PROFILE_PARTS": "strength,speed,tendon,activation"}.items():
        os.environ[k] = v
    task = importlib.import_module("tasks.long_jump_v4_beyond_a").TASK()
    task.seed = seed
    params = arena.read_params(params_path)
    params["j_ik"] = 0.0
    params["j_il"] = 0.0
    sim = Sim(task, params=params, controller=os.path.abspath(ctl))
    m, d = sim.m, sim.d
    task.reset(m, d)
    mujoco.mj_forward(m, d)
    sim.start_controller()
    substeps = max(1, round(task.control_dt / m.opt.timestep))
    pel = d.body("pelvis").id
    rows = []
    k = 0
    fell = False
    try:
        while d.time < task.seconds:
            act, c = sim.tick()
            for _ in range(substeps):
                task.before_step(m, d)
                mujoco.mj_step(m, d)
            k += 1
            if k % 4 == 0:
                mujoco.mj_subtreeVel(m, d)
                up = d.body("pelvis").xmat.reshape(3, 3)[:, 2]
                rows.append((round(d.time, 3), sim.label, float(d.subtree_com[pel][0]), float(d.subtree_linvel[pel][0]), float(d.subtree_linvel[pel][2]), float(math.atan2(up[0], up[2])), float(d.subtree_com[pel][2])))
            if task.done(m, d):
                fell = True
                break
    finally:
        sim.stop_controller()
    return {"seed": seed, "fell": fell, "rows": rows}


def main():
    params_path, ctl, seeds, out = sys.argv[1:5]
    workers = int(sys.argv[5]) if len(sys.argv) > 5 else 2
    if seeds.endswith(".json"):
        j = json.load(open(seeds)); seeds = j["fall"] + j["ok"]
    else:
        seeds = [int(x) for x in seeds.split(",")]
    with mp.get_context("spawn").Pool(workers) as pool:
        res = pool.map(job, [(params_path, ctl, s) for s in seeds])
    json.dump(res, open(out, "w"))
    print("falltrace", len(res), "->", out)


if __name__ == "__main__":
    main()
