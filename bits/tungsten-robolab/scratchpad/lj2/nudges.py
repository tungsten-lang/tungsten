"""The planner's last nudges before the penultimate touchdown, per start, next to the harness validity of that start (L2).
usage: nudges.py <params> <controller> <seeds>"""
import os, sys, importlib, re
import multiprocessing as mp
os.environ.setdefault("MUJOCO_GL", "cgl")
HERE = "/Users/erik/tungsten/bits/tungsten-robolab/playground"
sys.path.insert(0, HERE)

def parse_seeds(spec):
    out = []
    for tok in spec.split(","):
        if "-" in tok[1:]:
            a, b = tok.split("-"); out += list(range(int(a), int(b) + 1))
        else:
            out.append(int(tok))
    return out

def job(args):
    import arena
    from bridge import Sim
    params_path, ctl, seed = args
    for k, v in {"ROBOLAB_CALIB": "v4", "ROBOLAB_PROFILE": "p95", "ROBOLAB_PROFILE_PARTS": "strength,speed,tendon,activation", "ROBOLAB_LJ_APPROACH": "44"}.items():
        os.environ.setdefault(k, v)
    task = importlib.import_module("tasks.long_jump_v4_p95b").TASK()
    task.seed = seed
    params = arena.read_params(params_path)
    params["j_debug"] = 1.0
    params["j_ik"] = 0.0; params["j_il"] = 0.0
    sim = Sim(task, params=params, controller=os.path.abspath(ctl))
    cmds = []
    orig = task.on_command
    def oc(m, d, cmd):
        if cmd.startswith("dbg:td"): cmds.append(cmd)
        return orig(m, d, cmd)
    task.on_command = oc
    sim.run(task.seconds)
    rows = []
    for c in cmds:
        mm = re.search(r"td:(\w_):t=([\d.]+):gap=([-\d.]+):step=([-\d.]+):stride=([-\d.]+):n=(\d+):plan=([-\d.]+):pen=(\w*)", c)
        if mm:
            rows.append((mm.group(1), float(mm.group(2)), float(mm.group(3)), float(mm.group(4)), float(mm.group(5)), int(mm.group(6)), float(mm.group(7)), mm.group(8)))
    return seed, rows

def main():
    params_path, ctl, seeds = sys.argv[1:4]
    seeds = parse_seeds(seeds)
    with mp.get_context("spawn").Pool(4) as pool:
        res = pool.map(job, [(params_path, ctl, s) for s in seeds])
    import json
    json.dump({str(s): r for s, r in res}, open("/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj2/nudges.json", "w"))
    print("saved", len(res))

if __name__ == "__main__":
    main()
