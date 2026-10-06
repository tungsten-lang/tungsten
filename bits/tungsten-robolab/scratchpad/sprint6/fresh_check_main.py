#!/usr/bin/env python3
"""Main-session out-of-sample check of agent S6's result (3 Oct 2026): fall rate by phase-agnostic count and survivors' peak speed of F1 (the arena champion of
`sprint_top_speed_v4_beyond_fresh128`) and of a CANDIDATE chain (frozen controller + params given on the command line) on perturbed standing starts NO ONE has used
(default seeds 50001-50256). Both run the arena's way (arena.py recheck): F1's own task, frozen controller and frozen params, the trial's env and guard. Read-only
(arena.evaluate writes nothing). A file with a __main__ guard (multiprocessing spawn). Labelled beyond-human body.

    .venv/bin/python scratchpad/sprint6/fresh_check_main.py CONTROLLER PARAMS [FIRST LAST]     from bits/tungsten-robolab
"""
import json
import os
import sys

W = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(W)
sys.path.insert(0, os.path.join(W, "playground"))


def run(label, trial, ctl, params, task, seeds):
    import arena
    t = dict(trial)
    t["seeds"] = seeds
    rows, _ = arena.evaluate(t, arena.read_params(os.path.join(W, params)), os.path.join(W, ctl), task, 6)
    err = [r for r in rows if "error" in r]
    fell = [r for r in rows if r.get("fell")]
    ok = [r for r in rows if "error" not in r and not r.get("fell")]
    pk = [r["peak_speed_1s"] for r in ok]
    n = len(seeds)
    print(f"{label:34s} seeds {seeds[0]}-{seeds[-1]}: falls {len(fell)}/{n} = {100 * len(fell) / n:.1f} %  errors {len(err)}  survivors' mean peak {sum(pk) / max(len(pk), 1):.3f} m/s "
          f"(min {min(pk):.3f}, max {max(pk):.3f})", flush=True)
    return {sd: bool(r.get("fell")) for sd, r in zip(seeds, rows)}   # pool.map keeps the seed order


def main():
    ctl, params = sys.argv[1], sys.argv[2]
    lo, hi = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) > 4 else (50001, 50256)
    trials = json.load(open("playground/arena/trials.json"))
    champs = json.load(open("playground/arena/champions.json"))
    name = "sprint_top_speed_v4_beyond_fresh128"
    c, trial = champs[name], trials[name]
    seeds = list(range(lo, hi + 1))
    f1 = run("F1 (arena champion)", trial, c["frozen_controller"], c["frozen_params"], c["task"], seeds)
    cand = run("candidate " + os.path.basename(ctl), trial, ctl, params, c["task"], seeds)
    both = sum(1 for s in f1 if f1[s] and cand.get(s))
    only_f1 = sum(1 for s in f1 if f1[s] and not cand.get(s))
    only_c = sum(1 for s in cand if cand[s] and not f1.get(s))
    print(f"paired: both fall {both}, only F1 falls {only_f1}, only the candidate falls {only_c} (sign test: candidate better when only_f1 > only_c)")


if __name__ == "__main__":
    main()
