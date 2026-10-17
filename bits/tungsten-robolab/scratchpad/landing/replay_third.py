#!/usr/bin/env python3
"""Replays of the champions the THIRD landing commit adds or changes, from a clean worktree, using the worktree-built entries (landing verification, 6 Oct 2026).

    BIT_HOME=<worktree>/bits <worktree>/bits/tungsten-robolab/.venv/bin/python replay_third.py <worktree>

Each champion runs the arena's way (champion record's own task, trial env) with the WORKTREE's built binary instead of the frozen one, on its first few seeds, and its scores must equal
the recorded ones to 1e-9. A file with a __main__ guard: arena.evaluate uses multiprocessing 'spawn'."""
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
    # (trial, built entry, number of seeds, params record key)
    for name, entry, n, pkey in (("dribble_btl_streak_25", "dribble_btl", 8, "frozen_params"),
                                 ("long_jump_v4_beyond_record480", "long_jump_run_y", 24, "frozen_params"),
                                 ("long_jump_v4_beyond_robust96", "long_jump_run_y", 4, "frozen_params"),
                                 ("sprint_top_speed_v4_beyond_fresh512", "run_gearz", 3, "frozen_params"),
                                 ("long_jump_v4_p95", "long_jump_run_y", 1, "frozen_params")):
        c, t = champs[name], dict(trials[name])
        t["seeds"] = t["seeds"][:n]
        rec = c["scores"][:n]
        params = arena.read_params(os.path.join(W, c[pkey]))
        rows, scores = arena.evaluate(t, params, os.path.join(W, "bin", "robolab_" + entry), c["task"], min(n, 4))
        ok = all(abs(a - b) < 1e-9 for a, b in zip(scores, rec))
        print(f"{name:38s} via {entry:16s} seeds {t['seeds'][:3]}..: {[round(x, 3) for x in scores]} recorded {[round(x, 3) for x in rec]} -> {'SAME' if ok else 'DIFFERENT'}", flush=True)
        bad += 0 if ok else 1
    print("REPLAY THIRD:", "PASS" if bad == 0 else "FAIL", flush=True)
    return bad == 0


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
