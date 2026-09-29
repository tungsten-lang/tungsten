"""Shared helpers for the btl2 tools (run from bits/tungsten-robolab)."""
import os
import sys

sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")


def load(path):
    out = {}
    for line in open(path):
        tok = line.split()
        if len(tok) >= 2 and not line.startswith("#"):
            out[tok[0]] = float(tok[1])
    return out


def parse_over(s):
    return {k: float(v) for k, v in (kv.split("=") for kv in s.split(",") if kv)}


def write_params(path, params, note):
    with open(path, "w") as f:
        f.write(f"# {note}\n")
        for k in sorted(params):
            if not k.startswith("__"):
                f.write(f"{k} {float(params[k])!r}\n")


def run_seed(job):
    """One rollout: (controller, params dict, seed, seconds) -> result dict (the task's metrics)."""
    ctl, params, seed, secs = job[:4]
    from bridge import Sim
    from dribble_btl import DribbleBtlTask
    t = DribbleBtlTask()
    t.body_kind = "v3"
    t.seed = seed
    r = Sim(t, params=params, controller=ctl).run(secs)
    r["seed"] = seed
    return r
