"""Closed-loop feature check: what the skill computes at a program's trigger (pg_dbg 1) vs the replay's prediction.

    OMP_NUM_THREADS=1 .venv/bin/python scratchpad/btl2/dbg_pg.py ctl params seed [secs]
"""
import sys

sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")
sys.path.insert(0, "scratchpad/btl2")
from common import load  # noqa: E402
from bridge import Sim  # noqa: E402
from dribble_btl import DribbleBtlTask  # noqa: E402


def main():
    ctl, pfile, seed = sys.argv[1], sys.argv[2], int(sys.argv[3])
    secs = float(sys.argv[4]) if len(sys.argv) > 4 else 2.6
    params = load(pfile)
    params["pg_dbg"] = 1.0
    t = DribbleBtlTask()
    t.body_kind = "v3"
    t.seed = seed
    sim = Sim(t, params=params, controller=ctl)
    orig = t.on_command
    lines = []

    def hook(m, d, cmd):
        if cmd.startswith("dbg:"):
            lines.append((round(d.time, 4), cmd))
        return orig(m, d, cmd)

    t.on_command = hook
    r = sim.run(secs)
    for tm, c in lines:
        if c.startswith("dbg:pgu"):
            print(tm, c)
    print({k: r.get(k) for k in ("btl_ok", "btl_tried", "btl_streak")})


if __name__ == "__main__":
    main()
