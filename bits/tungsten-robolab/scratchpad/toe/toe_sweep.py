#!/usr/bin/env python3
"""Does the runner's commanded toe matter? (30 Sep 2026: Erik's subset-keyframe example, "in the runner's toe-off keyframe all we care about is that the toe extends".)

    .venv/bin/python scratchpad/toe/toe_sweep.py            # from bits/tungsten-robolab; about 20 minutes with 6 workers

The runner champion of Erik's keyframe set 3 (trial run_natural_erik3_48: params/search/rn2_erik3_nohr.txt, frozen controller bin/challengers/rn2-kf3, 48 perturbed standing
starts 7301-7348, 30 s, metric kin_rms, guard no fall and in band) with ONLY the commanded stance-foot toe of a keyframe changed in a copy of the params (`ref_<kf>_st_toe`).
Nothing is written to the arena. The first variant is the champion itself and must reproduce champions.json's recorded 48 scores (identity check). kin_rms has no toe group and event_rms
excludes toes (tasks/run_natural.py), so a difference here is the toe acting through the dynamics (push-off, balance), not through the score's own joints.

A file with a __main__ guard: arena.evaluate uses multiprocessing 'spawn'.
"""
import json
import os
import random
import sys

W = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(W)
sys.path.insert(0, os.path.join(W, "playground"))

VARIANTS = [
    ("base: td -14, ms 0, to -30", {}),
    ("to_st_toe -60", {"ref_to_st_toe": -60.0}),
    ("to_st_toe -45", {"ref_to_st_toe": -45.0}),
    ("to_st_toe -15", {"ref_to_st_toe": -15.0}),
    ("to_st_toe 0", {"ref_to_st_toe": 0.0}),
    ("to_st_toe +10", {"ref_to_st_toe": 10.0}),
    ("td_st_toe 0 (was -14)", {"ref_td_st_toe": 0.0}),
    ("td_st_toe -30", {"ref_td_st_toe": -30.0}),
    ("all three st_toe 0", {"ref_td_st_toe": 0.0, "ref_ms_st_toe": 0.0, "ref_to_st_toe": 0.0}),
]


def signflip_p(diffs, reps=4000, seed=0):
    rng = random.Random(seed)
    n = len(diffs)
    mean = sum(diffs) / n
    extreme = sum(1 for _ in range(reps) if abs(sum(d if rng.random() < 0.5 else -d for d in diffs) / n) >= abs(mean) - 1e-12)
    return extreme / reps


def main():
    import arena
    trial = dict(json.load(open("playground/arena/trials.json"))["run_natural_erik3_48"])
    champ_scores = json.load(open("playground/arena/champions.json"))["run_natural_erik3_48"]["scores"]
    ctl = os.path.join(W, "bin/challengers/rn2-kf3")
    base = arena.read_params("params/search/rn2_erik3_nohr.txt")
    results, ref = [], None
    for label, over in VARIANTS:
        params = dict(base)
        params.update(over)
        rows, scores = arena.evaluate(trial, params, ctl, trial["task"], 6)
        if ref is None:
            same = all(abs(a - b) < 1e-9 for a, b in zip(scores, champ_scores))
            print(f"identity: the base variant reproduces champions.json's 48 scores: {'YES' if same else 'NO (!)'}", flush=True)
            ref = scores
        ok = [i for i, s in enumerate(scores) if abs(s) < 1e8]
        both = [i for i in ok if abs(ref[i]) < 1e8]
        mean = sum(scores[i] for i in ok) / max(len(ok), 1)
        diffs = [scores[i] - ref[i] for i in both]
        pm = sum(diffs) / len(diffs) if diffs else float("nan")
        p = signflip_p(diffs) if len(diffs) >= 5 else float("nan")
        ev = [rows[i].get("event_rms") for i in ok if rows[i].get("event_rms") is not None]
        sp = [rows[i].get("speed") for i in ok if rows[i].get("speed") is not None]
        line = (f"{label:28s} guard-passing {len(ok):2d}/48  kin_rms {mean:6.3f}  event_rms {sum(ev) / max(len(ev), 1):6.3f}  speed {sum(sp) / max(len(sp), 1):5.2f} m/s"
                f"  | paired vs base over {len(both)} starts: {pm:+.3f} (p {p:.3f})")
        print(line, flush=True)
        results.append({"label": label, "over": over, "scores": scores, "passing": len(ok), "kin_rms": mean, "paired_diff": pm, "p": p})
    json.dump(results, open("scratchpad/toe/toe_sweep.json", "w"))


if __name__ == "__main__":
    main()
