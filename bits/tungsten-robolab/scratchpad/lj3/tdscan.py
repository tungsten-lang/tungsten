"""Touchdown sequence of the approach (planner neutral, j_run 1) for one start: every running touchdown's toe x (absolute, m) and
side from the skill's own debug (dbg:td), so a check mark can be chosen to put the penultimate touchdown at a wanted gap. (L3 scratch)
usage: tdscan.py <params> <controller> <seed|None> [k=v,...] [last_n]"""
import os
import sys
import importlib

os.environ.setdefault("MUJOCO_GL", "cgl")
HERE = "/Users/erik/tungsten/bits/tungsten-robolab/playground"
sys.path.insert(0, HERE)


def main():
    import arena
    from bridge import Sim
    params_path, ctl, seed = sys.argv[1:4]
    extra = dict(kv.split("=") for kv in (sys.argv[4] if len(sys.argv) > 4 else "").split(",") if kv)
    last_n = int(sys.argv[5]) if len(sys.argv) > 5 else 10
    seed = None if seed == "None" else int(seed)
    board = float(extra.pop("board", 150.0))
    os.environ.update({"ROBOLAB_CALIB": "v4", "ROBOLAB_PROFILE": "beyond", "ROBOLAB_PROFILE_PARTS": "strength,speed,tendon,activation",
                       "ROBOLAB_LJ_APPROACH": str(board)})
    task = importlib.import_module("tasks.long_jump_v4_beyond").TASK()
    task.seed = seed
    params = arena.read_params(params_path)
    params["j_run"] = float(extra.pop("j_run", 1.0))
    params["j_debug"] = 1.0
    params.pop("j_ik", None)
    params.pop("j_il", None)
    for k, v in extra.items():
        params[k] = float(v)
    sim = Sim(task, params=params, controller=os.path.abspath(ctl))
    cmds = []
    orig = task.on_command

    def oc(m, d, cmd):
        if cmd.startswith("dbg:td"):
            cmds.append(cmd)
        return orig(m, d, cmd)
    task.on_command = oc
    m = sim.run(task.seconds)
    rows = []
    for c in cmds:
        # dbg:td:<side>:t=..:gap=..:step=..:stride=..:n=..:plan=..:pen=..
        t = c.split(":")
        side = t[2]
        kv = dict(x.split("=") for x in t[3:] if "=" in x)
        gap = float(kv["gap"])
        rows.append((float(kv["t"]), side, board - gap, gap, float(kv["step"]), float(kv["stride"]), kv.get("n"), kv.get("plan"), kv.get("pen")))
    rows = [r for r in rows if r[3] > -3.0]
    print("seed", seed, "fell", m.get("fell_approach"), "touchdowns before the line (t, side, toe x, gap to the line, step, running stride):")
    for r in rows[-last_n:]:
        print("  t %.3f %s x %.3f gap %.3f step %.3f stride %.3f n %s plan %s pen %s" % r)


if __name__ == "__main__":
    main()
