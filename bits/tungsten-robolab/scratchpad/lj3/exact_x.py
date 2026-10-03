"""Exactness of the new skill: RunGearX (bin/challengers/run_gearx-s4a) and LongJumpRunX with j_run 1 (neutral jump settings) on the
same task / seed / params must give the same tick log (labels and all 32 activations) for the first N seconds.
usage: exact_x.py <params> <jump_controller> <seed|None> <seconds>"""
import os
import sys
import importlib

os.environ.setdefault("MUJOCO_GL", "cgl")
HERE = "/Users/erik/tungsten/bits/tungsten-robolab/playground"
sys.path.insert(0, HERE)
ROOT = os.path.dirname(HERE)


def run(ctl, params_path, seed, seconds, extra):
    import arena
    from bridge import Sim
    os.environ.update({"ROBOLAB_CALIB": "v4", "ROBOLAB_PROFILE": "beyond", "ROBOLAB_PROFILE_PARTS": "strength,speed,tendon,activation"})
    task = importlib.import_module("tasks.long_jump_v4_beyond").TASK()
    task.seed = seed
    params = arena.read_params(params_path)
    params.update(extra)
    sim = Sim(task, params=params, controller=os.path.abspath(ctl))
    sim.run(seconds)
    return sim.log


def main():
    params, jump_ctl, seed, seconds = sys.argv[1:5]
    seed = None if seed == "None" else int(seed)
    seconds = float(seconds)
    a = run(os.path.join(ROOT, "bin/challengers/run_gearx-s4a"), params, seed, seconds, {})
    b = run(jump_ctl, params, seed, seconds, {"j_run": 1.0})
    print("ticks", len(a), len(b))
    n = min(len(a), len(b))
    bad = None
    for i in range(n):
        ta, la, acta = a[i][0], a[i][1], a[i][2]
        tb, lb, actb = b[i][0], b[i][1], b[i][2]
        if ta != tb or la != lb or (acta != actb).any():
            bad = i
            break
    if bad is None and len(a) == len(b):
        print("IDENTICAL: %d ticks, labels and activations equal (t %.3f .. %.3f)" % (n, a[0][0], a[n - 1][0]))
    else:
        i = bad if bad is not None else n
        print("DIFFER at tick", i, "t", a[i][0] if i < len(a) else None, a[i][1] if i < len(a) else None, b[i][1] if i < len(b) else None)
        if bad is not None:
            import numpy as np
            print("max |dact|", float(np.abs(a[i][2] - b[i][2]).max()))


if __name__ == "__main__":
    main()
