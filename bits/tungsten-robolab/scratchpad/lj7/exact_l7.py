"""exact_l7 (L7): TICK-LEVEL identity of two jump controllers on the same params / task / seed: time, chunk labels and all 32 activations at every control tick of the whole rollout (LABELLED beyond-human body, unlimited run-up).
usage: exact_l7.py <params> <controllerA> <controllerB> <seed> [k=v,...]"""
import os, sys, importlib
os.environ.setdefault("MUJOCO_GL", "cgl")
HERE = "/Users/erik/tungsten/bits/tungsten-robolab/playground"
sys.path.insert(0, HERE)

def run(ctl, params_path, seed, extra):
    import arena
    from bridge import Sim
    os.environ.update({"ROBOLAB_CALIB": "v4", "ROBOLAB_PROFILE": "beyond", "ROBOLAB_PROFILE_PARTS": "strength,speed,tendon,activation"})
    task = importlib.import_module("tasks.long_jump_v4_beyond_a").TASK()
    task.seed = seed
    params = arena.read_params(params_path)
    for kv in extra.split(","):
        if kv:
            k, v = kv.split("="); params[k] = float(v)
    sim = Sim(task, params=params, controller=os.path.abspath(ctl))
    m = sim.run(task.seconds)
    return sim.log, m

def main():
    params, ca, cb, seed = sys.argv[1:5]
    extra = sys.argv[5] if len(sys.argv) > 5 else ""
    a, ma = run(ca, params, int(seed), extra)
    b, mb = run(cb, params, int(seed), extra)
    n = min(len(a), len(b))
    bad = None
    for i in range(n):
        if a[i][0] != b[i][0] or a[i][1] != b[i][1] or (a[i][2] != b[i][2]).any():
            bad = i; break
    if bad is None and len(a) == len(b):
        print("TICK-IDENTICAL seed %s: %d ticks (t %.3f .. %.3f), labels and all 32 activations equal; official_m %s / %s" % (seed, n, a[0][0], a[n - 1][0], ma.get("official_m"), mb.get("official_m")))
    else:
        print("DIFFER seed %s at tick %s (ticks %d / %d)" % (seed, bad, len(a), len(b)))

if __name__ == "__main__":
    main()
