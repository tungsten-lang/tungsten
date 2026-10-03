#!/usr/bin/env python3
"""Replay checks of the sprint controller (run_gearx) built from a landing commit, run from a clean worktree.

    BIT_HOME=<worktree>/bits <worktree>/bits/tungsten-robolab/.venv/bin/python replay_sprint.py <worktree>

The first 2 seeds of sprint_top_speed_v4_beyond (params/run_gearx_v4_beyond_c.txt) and sprint_top_speed_v4_p95 (params/run_gearx_v4_p95_x5a.txt)
must reproduce the champions.json scores of the same seeds to 1e-9. A file with a __main__ guard: arena.evaluate uses multiprocessing 'spawn'.
"""
import json
import os
import sys

W = os.path.abspath(sys.argv[1]) + "/bits/tungsten-robolab" if len(sys.argv) > 1 else "/Users/erik/rl-verify-0930/bits/tungsten-robolab"
MB = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, W + "/playground")


def main():
    import arena
    assert arena.ROOT == W, (arena.ROOT, W)
    trials = json.load(open(W + "/playground/arena/trials.json"))
    champs = json.load(open(MB + "/playground/arena/champions.json"))
    ctl = W + "/bin/robolab_run_gearx"
    bad = 0
    for name, pfile in (("sprint_top_speed_v4_beyond", "params/run_gearx_v4_beyond_c.txt"), ("sprint_top_speed_v4_p95", "params/run_gearx_v4_p95_x5a.txt")):
        t = dict(trials[name])
        t["seeds"] = t["seeds"][:2]
        rows, scores = arena.evaluate(t, arena.read_params(W + "/" + pfile), ctl, t.get("task", "run_v4"), 2)
        rec = champs[name]["scores"][:2]
        ok = all(abs(a - b) < 1e-9 for a, b in zip(scores, rec))
        print(name, "scores", [round(x, 4) for x in scores], "recorded", [round(x, 4) for x in rec], "->", "same" if ok else "DIFFERENT", [r.get("error") for r in rows if "error" in r], flush=True)
        bad += 0 if ok else 1
    print("SPRINT IDENTITY:", "PASS" if bad == 0 else "FAIL", flush=True)
    return bad == 0


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
