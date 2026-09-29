"""Render a LongJumpRunSkill jump: the whole rollout to an MP4 (the run-up at
normal speed, take-off to landing at 1/4 speed: long_jump's recorder), a
GIF of the jump alone under 6 MB, a contact sheet of the jump, and the
rollout's metrics as JSON beside the video.

    .venv/bin/python playground/long_jump_run_render.py long_jump_p95 --params p.txt \\
        --controller bin/challengers/long_jump_run-x --out out/long_jump_v4 [--seed 0] [--gif-from 2.5]

writes <out>.mp4, <out>.gif, <out>_sheet.png, <out>_metrics.json.
"""

import argparse
import importlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from bridge import Sim  # noqa: E402
from search import read_params  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("task")
    ap.add_argument("--params", nargs="+", required=True)
    ap.add_argument("--controller")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--out", required=True)
    ap.add_argument("--gif-from", type=float, default=1.2, help="seconds of sim time before the take-off where the GIF starts")
    ap.add_argument("--gif-mb", type=float, default=5.8)
    a = ap.parse_args()
    task = importlib.import_module(f"tasks.{a.task}").TASK()
    task.seed = a.seed
    params = {}
    for p in a.params:
        params.update(read_params(p))
    sim = Sim(task, params=params, controller=a.controller)
    import render  # long_jump's LongJumpRecorder is installed as render.Recorder by the task import
    rec = render.Recorder(sim)
    times = []
    orig = rec.capture

    def capture(s):
        times.append(s.d.time)
        orig(s)

    rec.capture = capture
    res = sim.run(recorder=rec)
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    rec.write_mp4(a.out + ".mp4")
    # the GIF: the jump alone (from gif_from s before the take-off to the end)
    t_to = task.takeoff["t"] if task.takeoff is not None else times[-1] - 3.0
    keep = [i for i, t in enumerate(times) if t >= t_to - a.gif_from]
    rec.frames = [rec.frames[i] for i in keep]
    rec.gif_limit = int(a.gif_mb * 1e6)
    rec.write_gif(a.out + ".gif")
    rec.write_sheet(a.out + "_sheet.png")
    res = {k: (v if not hasattr(v, "item") else v.item()) for k, v in res.items()}
    res["params_files"] = a.params
    res["controller"] = a.controller
    res["task"] = a.task
    res["seed"] = a.seed
    with open(a.out + "_metrics.json", "w") as f:
        json.dump(res, f, indent=1, default=str)
    keys = ["official_m", "effective_m", "board_offset_m", "foul_max_x", "speed_5m", "takeoff_vx", "takeoff_vz",
            "takeoff_angle_deg", "contact_time_s", "flight_s", "somersault", "nearest_mark_by"]
    print({k: res.get(k) for k in keys})
    print("gif", os.path.getsize(a.out + ".gif"), "bytes")


if __name__ == "__main__":
    main()
