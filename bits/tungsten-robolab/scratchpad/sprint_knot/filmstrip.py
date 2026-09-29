"""filmstrip: DIAGNOSTIC. Run one rollout and write a contact sheet of `count` frames spaced 1/fps apart from
t0 (frames only inside the window are rendered, so it is cheap).

  ROBOLAB_CALIB=v4 [ROBOLAB_PROFILE=p95 ...] .venv/bin/python scratchpad/sprint_knot/filmstrip.py TASK PARAMS \
      --controller C --seed 221 --t0 12 --fps 24 --count 12 --cols 4 --out out/x_sheet.png
"""
import argparse, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
os.environ.setdefault("MUJOCO_GL", "cgl")
from practice import load_task, read_params
from bridge import Sim
from render import Recorder


class Window(Recorder):
    def __init__(self, sim, t0, fps, count, **kw):
        super().__init__(sim, fps=fps, **kw)
        self.t0, self.count = t0, count
        self.next_t = t0

    def maybe_capture(self, sim):
        if len(self.frames) >= self.count or sim.d.time + 1e-9 < self.next_t:
            return
        self.next_t += 1.0 / self.fps
        self.capture(sim)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("task"); ap.add_argument("params"); ap.add_argument("--controller"); ap.add_argument("--seed", default="221")
    ap.add_argument("--t0", type=float, default=12.0); ap.add_argument("--fps", type=float, default=24.0)
    ap.add_argument("--count", type=int, default=12); ap.add_argument("--cols", type=int, default=4)
    ap.add_argument("--scale", type=float, default=0.5); ap.add_argument("--out", required=True)
    ap.add_argument("--attr"); ap.add_argument("--start")
    a = ap.parse_args()
    p = read_params(a.params)
    task = load_task(a.task)
    for kv in (a.attr or "").split(","):
        if kv:
            setattr(task, kv.split("=")[0], float(kv.split("=")[1]))
    if a.start:
        task.start = a.start
    task.seed = None if a.seed in ("None", "none") else int(a.seed)
    sim = Sim(task, params=p, controller=a.controller)
    rec = Window(sim, a.t0, a.fps, a.count)
    res = sim.run(a.t0 + a.count / a.fps + 0.05, recorder=rec)
    print({k: res.get(k) for k in ("time", "fell", "steady_speed", "peak_speed_1s")})
    rec.write_sheet(a.out, count=len(rec.frames), cols=a.cols, scale=a.scale)


if __name__ == "__main__":
    main()
