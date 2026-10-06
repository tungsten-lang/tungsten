#!/usr/bin/env python3
"""Replays of the champions the SECOND landing commit adds, from a clean worktree, using the worktree-built entries (landing verification, 2 Oct 2026).

    BIT_HOME=<worktree>/bits <worktree>/bits/tungsten-robolab/.venv/bin/python replay_beyond.py <worktree>

Each champion runs the arena's way (champion record's own task, trial env) with the WORKTREE's built binary instead of the frozen one, on its first few seeds, and its scores must equal the
recorded ones to 1e-9. A file with a __main__ guard: arena.evaluate uses multiprocessing 'spawn'."""
import json
import os
import sys

W = os.path.abspath(sys.argv[1]) + "/bits/tungsten-robolab"
sys.path.insert(0, W + "/playground")
os.chdir(W)


def main():
    import arena
    assert arena.ROOT == W, (arena.ROOT, W)
    trials = json.load(open("playground/arena/trials.json"))
    champs = json.load(open("playground/arena/champions.json"))
    bad = 0
    # (trial, built entry, number of seeds)
    for name, entry, n in (("long_jump_v4_beyond", "long_jump_run_x", 1), ("long_jump_v4_beyond_robust96", "long_jump_run_y", 4),
                           ("sprint_top_speed_v4_beyond_fresh128", "run_geary", 3), ("long_jump_v4_p95", "long_jump_run_x", 1), ("long_jump_v4_p95", "long_jump_run_y", 1)):
        c, t = champs[name], dict(trials[name])
        t["seeds"] = t["seeds"][:n]
        rec = c["scores"][:n]
        params = arena.read_params(os.path.join(W, c["params"] if name != "long_jump_v4_p95" else c["frozen_params"]))
        rows, scores = arena.evaluate(t, params, os.path.join(W, "bin", "robolab_" + entry), c["task"], min(n, 4))
        ok = all(abs(a - b) < 1e-9 for a, b in zip(scores, rec))
        print(f"{name:38s} via {entry:16s} seeds {t['seeds']}: {[round(x, 4) for x in scores]} recorded {[round(x, 4) for x in rec]} -> {'SAME' if ok else 'DIFFERENT'}", flush=True)
        bad += 0 if ok else 1
    print("REPLAY BEYOND:", "PASS" if bad == 0 else "FAIL", flush=True)
    return bad == 0


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
