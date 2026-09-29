"""Render a high-school hurdles run: video, GIF (kept under a size cap), a
contact sheet of the whole run and one of a single clearance.

    ROBOLAB_HURDLE_HEIGHT=0.991 .venv/bin/python playground/hurdle_hs_render.py hurdle_hs_v3 \\
      --params params/hurdle_hs.txt --controller bin/champions/hurdle_hs-... --out out/hurdle_hs \\
      [--seed 0] [--hurdle 1]

writes <out>.mp4, <out>.gif, <out>_sheet.png (12 frames over the run),
<out>_clearance.png (take-off to landing of hurdle --hurdle, 1-based) and
<out>_metrics.json (the task's JSON record of the run).
"""

import argparse
import importlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bridge import Sim  # noqa: E402
from render import Recorder  # noqa: E402
from search import read_params  # noqa: E402
from PIL import Image  # noqa: E402


class LabelledRecorder(Recorder):
    """A Recorder that also keeps each frame's time and chunk label."""

    def __init__(self, sim, **k):
        super().__init__(sim, **k)
        self.meta = []

    def capture(self, sim):
        super().capture(sim)
        self.meta.append((sim.d.time, sim.label))


def write_gif_capped(rec, path, cap_mb):
    for every, scale in ((2, 0.5), (3, 0.5), (3, 0.45), (4, 0.42), (5, 0.4), (6, 0.36), (8, 0.33)):
        rec.write_gif(path, scale=scale, every=every)
        mb = os.path.getsize(path) / 1e6
        print(f"  gif every {every} scale {scale}: {mb:.2f} MB")
        if mb <= cap_mb:
            return
    print("  gif still above the cap")


def clearance_sheet(rec, path, hurdle, cols=4, scale=0.4):
    """Frames from the take-off plant of the given clearance to its landing."""
    k = 0
    start = end = None
    prev = ""
    for i, (_, label) in enumerate(rec.meta):
        name = label.split(":")[-1]
        if name.endswith("_plant") and not prev.endswith("_plant"):
            k += 1
            if k == hurdle:
                start = i
        if start is not None and end is None and name.endswith("_push") and prev.endswith("_land"):
            end = i
        prev = name
    if start is None:
        print("no clearance", hurdle, "in the run")
        return
    end = end if end is not None else min(len(rec.frames) - 1, start + 60)
    count = 8
    idx = [round(start + j * (end - start) / (count - 1)) for j in range(count)]
    w, h = int(rec.width * scale), int(rec.height * scale)
    rows = (count + cols - 1) // cols
    sheet = Image.new("RGB", (cols * w, rows * h), (255, 255, 255))
    for j, i in enumerate(idx):
        sheet.paste(Image.fromarray(rec.frames[i]).resize((w, h)), ((j % cols) * w, (j // cols) * h))
    sheet.save(path)
    print("wrote", path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("task")
    ap.add_argument("--params", required=True)
    ap.add_argument("--controller")
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--seconds", type=float)
    ap.add_argument("--hurdle", type=int, default=1)
    ap.add_argument("--gif_mb", type=float, default=5.8)
    a = ap.parse_args()
    task = importlib.import_module(f"tasks.{a.task}").TASK()
    task.seed = a.seed
    os.environ["ROBOLAB_HURDLE_METRICS"] = a.out + "_metrics.json"
    params = {}
    for path in a.params.split(","):
        params.update(read_params(path))
    sim = Sim(task, params=params, controller=a.controller)
    rec = LabelledRecorder(sim)
    m = sim.run(a.seconds, recorder=rec)
    print({k: m.get(k) for k in ("cleared", "clean", "knocked", "hs_time", "hs_score", "time_to_finish", "fell",
                                 "steps_between", "takeoff_dist", "landing_dist", "margin")})
    rec.write_mp4(a.out + ".mp4")
    rec.write_sheet(a.out + "_sheet.png")
    clearance_sheet(rec, a.out + "_clearance.png", a.hurdle)
    write_gif_capped(rec, a.out + ".gif", a.gif_mb)


if __name__ == "__main__":
    main()
