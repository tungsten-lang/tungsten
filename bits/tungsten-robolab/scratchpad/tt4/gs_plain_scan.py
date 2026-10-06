#!/usr/bin/env python3
"""Does any part of the grip found under the ideal servo carry over to the PLAIN champion stroke (no oracle, the real muscle excitations)? Interpolates the twelve grip parameters between the
champion's grip (alpha 0) and the search's best candidate (alpha 1) and runs the plain stroke on the 70 validation serves (98030-98099), and, with --setb, on T3's set B (830000-830099).
Usage: .venv-myo/bin/python scratchpad/tt4/gs_plain_scan.py ALPHA [ALPHA ...] [--setb]   Run from bits/tungsten-robolab. A file with a __main__ guard."""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grasp_search as gs  # noqa: E402


def main():
    setb = "--setb" in sys.argv
    alphas = [float(a) for a in sys.argv[1:] if not a.startswith("--")]
    champ = gs.champion_x()
    best = np.array(json.load(open(gs.STATE))["best"]["x"])
    out = json.load(open("scratchpad/tt4/gs_plain_scan.json")) if os.path.exists("scratchpad/tt4/gs_plain_scan.json") else {}
    for a in alphas:
        x = champ + a * (best - champ)
        for sname, seeds in (("validation", gs.VALID),) + ((("set B", gs.SETB),) if setb else ()):
            d = gs.run_serves(x, f"plain_a{int(round(a * 100)):03d}_{sname.split()[0]}", seeds, workers=6, oracle=False)
            m = gs.metrics(d, seeds)
            out[f"alpha {a} / {sname}"] = {k: m[k] for k in ("n", "contact", "lost", "never", "solved")}
            print(f"plain stroke, grip alpha {a:4.2f}  {sname:10s} contact {m['contact']:3d}/{m['n']}  never {m['never']:3d}  solved {m['solved']:3d}/{m['n']}", flush=True)
            json.dump(out, open("scratchpad/tt4/gs_plain_scan.json", "w"), indent=1)


if __name__ == "__main__":
    main()
