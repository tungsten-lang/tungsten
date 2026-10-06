#!/usr/bin/env python3
"""The ceiling with the new grip: T3's settled-pelvis oracle (o1) + the decelerating ideal arm servo (o5) + the grasp search's BEST grip, on the 70 validation serves and T3's set B (the same
oracle with the champion grip gave 34 of 70 and 50 of 100, `gs_pelvis_check.py`). A LABELLED DIAGNOSTIC ORACLE. Run from bits/tungsten-robolab. A file with a __main__ guard."""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grasp_search as gs  # noqa: E402
import gs_pelvis_check as pc  # noqa: E402


def main():
    best = np.array(json.load(open(gs.STATE))["best"]["x"])
    setstr = ",".join(f"{n}={v:.6g}" for n, v in zip(gs.PARAMS, best))
    cfg = {"o5_togo": 1, "o5_tact": 0.30, "o5_hold": 0.03, "o5_wrot": 0.30, "o1_margin": 0.15}
    out = {}
    for sname, seeds in (("validation 98030-98099", gs.VALID), ("set B 830000-830099", gs.SETB)):
        d = pc.run("idealbest_" + sname.split()[0], seeds, "o1,o5", cfg, params_set=setstr)
        m = pc.stats(d, seeds)
        out[sname] = m
        print(f"settled pelvis + ideal arm + BEST grip {sname:24s} {m}", flush=True)
    json.dump(out, open("scratchpad/tt4/gs_ideal_best.json", "w"), indent=1)


if __name__ == "__main__":
    main()
