#!/usr/bin/env python3
"""Does S5's finding (the ES-tuned spine servo k_sp destabilises the top gears of the beyond-human runner) carry to the HUMAN-body (P95) sprinter? The arena champion
`sprint_top_speed_v4_p95` (RunGearXSkill chain params/run_gearx_v4_p95_x5a.txt, five gears; g3/g4/g5 k_sp 0.089 / 0.133 / 0.033) against copies with the k_sp (and k_spd) of gears 3-5 zeroed, on perturbed
standing starts (task run_v4, the champion record's own task and the trial's env), peak speed of the fastest 1 s window of 30 s and falls. Main session, 3 Oct 2026. Read-only except out/sprint7.
    .venv/bin/python scratchpad/sprint7/human_ksp_probe.py FIRST LAST        from bits/tungsten-robolab. A file with a __main__ guard (multiprocessing spawn)."""
import json
import os
import re
import sys

W = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(W)
sys.path.insert(0, os.path.join(W, "playground"))


def variant(src, edits):
    s = open(src).read()
    for key in edits:
        s, n = re.subn(rf"(?m)^{key} .*$", f"{key} 0.0", s)
        assert n == 1, (key, n)
    return s


def main():
    import arena
    lo, hi = int(sys.argv[1]), int(sys.argv[2])
    trials = json.load(open("playground/arena/trials.json"))
    champs = json.load(open("playground/arena/champions.json"))
    name = "sprint_top_speed_v4_p95"
    c, trial = champs[name], dict(trials[name])
    trial["seeds"] = list(range(lo, hi + 1))
    ctl = os.path.join(W, c["frozen_controller"])
    base_params = os.path.join(W, c["frozen_params"])
    variants = {"champion (x5a)": [], "g3-g5 k_sp = 0": ["g3_k_sp", "g4_k_sp", "g5_k_sp"],
                "g3-g5 k_sp = k_spd = 0": ["g3_k_sp", "g4_k_sp", "g5_k_sp", "g3_k_spd", "g4_k_spd", "g5_k_spd"], "g5 k_sp = k_spd = 0": ["g5_k_sp", "g5_k_spd"]}
    res = {}
    for label, edits in variants.items():
        p = f"out/sprint7/ksp_{abs(hash(label)) % 10 ** 6}.txt"
        open(p, "w").write(variant(base_params, edits))
        rows, _ = arena.evaluate(trial, arena.read_params(os.path.join(W, p)), ctl, c["task"], 6)
        fell = [bool(r.get("fell")) for r in rows]
        pk = [r["peak_speed_1s"] for r in rows if "error" not in r and not r.get("fell")]
        res[label] = (fell, pk)
        print(f"{label:26s} seeds {lo}-{hi}: falls {sum(fell)}/{len(fell)}  survivors' mean peak {sum(pk) / max(len(pk), 1):.3f} m/s (n {len(pk)}, min {min(pk):.2f}, max {max(pk):.2f})", flush=True)


if __name__ == "__main__":
    main()
