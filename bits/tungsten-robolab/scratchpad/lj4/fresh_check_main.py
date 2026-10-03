#!/usr/bin/env python3
"""Main-session out-of-sample check of agent L4's result (1 Oct 2026): L4's champion (params/long_jump_beyond_rob2.txt, controller long_jump_run_y-l4b, as frozen in the
arena record of trial long_jump_v4_beyond_robust96) against L3's robust program (params/long_jump_beyond_rob1.txt, controller long_jump_run_x-l3b) on 96 starts NO ONE has used
(seeds 21001-21096), same task (the champion record's own, long_jump_v4_beyond_a), same trial env. LABELLED beyond-human body, unlimited run-up. Read-only (arena.evaluate
writes nothing). A file with a __main__ guard (multiprocessing spawn).   .venv/bin/python scratchpad/lj4/fresh_check_main.py   from bits/tungsten-robolab"""
import json
import math
import os
import sys

W = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(W)
sys.path.insert(0, os.path.join(W, "playground"))


def main():
    import arena
    trials = json.load(open("playground/arena/trials.json"))
    champs = json.load(open("playground/arena/champions.json"))
    name = "long_jump_v4_beyond_robust96"
    c, t = champs[name], dict(trials[name])
    t["seeds"] = list(range(21001, 21097))
    runs = (("L4 champion (rob2, F1 runner)", os.path.join(W, c["frozen_params"]), os.path.join(W, c["frozen_controller"])),
            ("L3 robust program (rob1, chain D)", os.path.join(W, "params/long_jump_beyond_rob1.txt"), os.path.join(W, "bin/challengers/long_jump_run_x-l3b")))
    res = {}
    for label, params, ctl in runs:
        rows, scores = arena.evaluate(t, arena.read_params(params), ctl, c["task"], 6)
        off = [(r.get("official_m") if "error" not in r else 0.0) or 0.0 for r in rows]
        res[label] = off
        legal = [x for x in off if x > 0]
        print(f"{label:36s} fresh seeds 21001-21096: mean {sum(off) / len(off):.3f} m, legal {len(legal)}/96 ({100 * len(legal) / 96:.1f} %), mean of legal {sum(legal) / max(len(legal), 1):.2f}, "
              f"above 8.95 m: {sum(1 for x in off if x > 8.95)}, best {max(off):.2f}", flush=True)
    a, b = res[runs[0][0]], res[runs[1][0]]
    d = [x - y for x, y in zip(a, b)]
    m = sum(d) / len(d)
    se = math.sqrt(sum((x - m) ** 2 for x in d) / (len(d) - 1) / len(d))
    print(f"paired difference (L4 - L3): {m:+.3f} m, SE {se:.3f}", flush=True)


if __name__ == "__main__":
    main()
