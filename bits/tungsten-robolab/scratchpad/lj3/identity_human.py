#!/usr/bin/env python3
"""Identity check (main session, 30 Sep): the human-body one-start long-jump champion's params through L3's NEW frozen controller (bin/challengers/long_jump_run_x-l3b) must still give the
recorded 5.209 m of trial long_jump_v4_p95, i.e. adding LongJumpRunXSkill changed nothing for the human-body jump. Read-only (arena.evaluate does not write). A file with a __main__ guard
(multiprocessing spawn).   .venv/bin/python scratchpad/lj3/identity_human.py   from bits/tungsten-robolab"""
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
    name = "long_jump_v4_p95"
    t = dict(trials[name])
    rec = champs[name]["scores"]
    c = champs[name]
    # the arena evaluates a champion with ITS OWN task (c["task"], here long_jump_v4_p95b, check mark 44 m), its frozen params and frozen controller (arena.py recheck), not the trial's task field
    print("champion task:", c["task"], "| frozen controller:", c["frozen_controller"], "| frozen params:", c["frozen_params"], flush=True)
    for label, ctl in (("stock frozen champion controller", os.path.join(W, c["frozen_controller"])), ("new controller long_jump_run_x-l3b", os.path.join(W, "bin/challengers/long_jump_run_x-l3b"))):
        params = arena.read_params(os.path.join(W, c["frozen_params"]))
        rows, scores = arena.evaluate(t, params, ctl, c["task"], 1)
        print(f"{label:38s} official {scores}   recorded {rec}   -> {'SAME' if all(abs(a - b) < 1e-9 for a, b in zip(scores, rec)) else 'DIFFERENT'}", flush=True)


if __name__ == "__main__":
    main()
