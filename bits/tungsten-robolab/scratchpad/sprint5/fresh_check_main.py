#!/usr/bin/env python3
"""Main-session out-of-sample check of agent S5's result (1 Oct 2026): fall rate and survivors' peak speed of the entered champion (chain C) and of S5's champion F1
on 128 perturbed standing starts NO ONE has used (seeds 15001-15128). Each champion runs the arena's way (arena.py recheck): its own task, frozen controller and frozen params,
the trial's env and guard. Read-only (arena.evaluate writes nothing). A file with a __main__ guard (multiprocessing spawn).
    .venv/bin/python scratchpad/sprint5/fresh_check_main.py        from bits/tungsten-robolab; labelled beyond-human body"""
import json
import os
import sys

W = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(W)
sys.path.insert(0, os.path.join(W, "playground"))


def main():
    import arena
    trials = json.load(open("playground/arena/trials.json"))
    champs = json.load(open("playground/arena/champions.json"))
    seeds = list(range(15001, 15129))
    for label, name in (("entered champion (chain C)", "sprint_top_speed_v4_beyond"), ("S5's champion F1", "sprint_top_speed_v4_beyond_fresh128")):
        c, t = champs[name], dict(trials[name])
        t["seeds"] = seeds
        rows, scores = arena.evaluate(t, arena.read_params(os.path.join(W, c["frozen_params"])), os.path.join(W, c["frozen_controller"]), c["task"], 6)
        err = [r for r in rows if "error" in r]
        fell = [r for r in rows if r.get("fell")]
        ok = [r for r in rows if "error" not in r and not r.get("fell")]
        pk = [r["peak_speed_1s"] for r in ok]
        print(f"{label:28s} fresh seeds 15001-15128: falls {len(fell)}/128 = {100 * len(fell) / 128:.1f} %  errors {len(err)}  survivors' mean peak {sum(pk) / max(len(pk), 1):.3f} m/s (min {min(pk):.2f}, max {max(pk):.2f})", flush=True)


if __name__ == "__main__":
    main()
