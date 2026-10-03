"""One full rollout of a jump controller + params on the labelled beyond-human body, unlimited run-up; prints the metrics that matter (L3).
usage: roll.py <params> <controller> <task> <board_m> <seed|None> [k=v,...] [--json out.json]"""
import os
import sys
import json
import importlib

os.environ.setdefault("MUJOCO_GL", "cgl")
HERE = "/Users/erik/tungsten/bits/tungsten-robolab/playground"
sys.path.insert(0, HERE)

KEYS = ("official_m", "effective_m", "ballistic_m", "board_offset_m", "foul", "foul_max_x", "takeoff_vx", "takeoff_vz", "takeoff_angle_deg",
        "contact_time_s", "flight_s", "nearest_mark_by", "nearest_mark_x", "landed_short", "fell_back", "flipped", "max_pitch_after_landing",
        "somersault", "touched_runway_after_landing", "clean_landing", "rebound", "recovered", "fell_approach", "L_takeoff", "torso_pitch_takeoff",
        "speed_5m", "speed_at_board", "takeoff_com_z", "peak_com_z", "landing_com_vx", "failed", "time")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    out = None
    if "--json" in sys.argv:
        out = sys.argv[sys.argv.index("--json") + 1]
        args = [a for a in args if a != out]
    params_path, ctl, task_name, board, seed = args[:5]
    extra = dict(kv.split("=") for kv in (args[5] if len(args) > 5 else "").split(",") if kv)
    import arena
    from bridge import Sim
    os.environ.update({"ROBOLAB_CALIB": "v4", "ROBOLAB_PROFILE": "beyond", "ROBOLAB_PROFILE_PARTS": "strength,speed,tendon,activation"})
    if board != "-":
        os.environ["ROBOLAB_LJ_APPROACH"] = board
    task = importlib.import_module(f"tasks.{task_name}").TASK()
    task.seed = None if seed == "None" else int(seed)
    params = arena.read_params(params_path)
    for k, v in extra.items():
        params[k] = float(v)
    sim = Sim(task, params=params, controller=os.path.abspath(ctl))
    m = sim.run(task.seconds)
    print({k: m.get(k) for k in KEYS if k in m})
    if out:
        json.dump({k: v for k, v in m.items() if isinstance(v, (int, float, bool, str)) or v is None}, open(out, "w"), default=float)


if __name__ == "__main__":
    main()
