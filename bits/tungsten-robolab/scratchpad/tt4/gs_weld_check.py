#!/usr/bin/env python3
"""WELDED-PADDLE diagnostic (oracle mode o6, 3 Oct 2026): the paddle is the ACTUAL palm's rigid extension from t_on to t_off, with the ideal arm servo (o5) and, in the second row, the settled
pelvis (o1). Separates the arm servo's residual pad error (pad speed 0.4-0.5 m/s, 2.3 deg) from the hand-held paddle's response at impact: if a rigidly welded paddle returns about what the
hand-held one does (24 / 70 and 30 / 100 with the champion's pelvis, 34 / 70 and 50 / 100 with the settled one), the servo's residual error is the limit; if it returns far more, the
hand-held response is. Usage: gs_weld_check.py [smoke]. A LABELLED DIAGNOSTIC ORACLE. Run from bits/tungsten-robolab. A file with a __main__ guard."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grasp_search as gs  # noqa: E402
import gs_pelvis_check as pc  # noqa: E402


def main():
    smoke = len(sys.argv) > 1 and sys.argv[1] == "smoke"
    base = {"o5_togo": 1, "o5_tact": 0.30, "o5_hold": 0.03, "o5_wrot": 0.30}
    out = {}
    sets = (("smoke 98030-98033", (98030, 98034)),) if smoke else (("validation 98030-98099", gs.VALID), ("set B 830000-830099", gs.SETB))
    for label, modes, cfg in (("welded paddle + ideal arm (champion's pelvis)", "o5,o6", base), ("welded paddle + ideal arm + settled pelvis", "o1,o5,o6", dict(base, o1_margin=0.15))):
        for sname, seeds in sets:
            d = pc.run("weld_" + str(len(out)), seeds, modes, cfg)
            m = pc.stats(d, seeds)
            out[f"{label} / {sname}"] = m
            print(f"{label:48s} {sname:24s} {m}", flush=True)
    if not smoke:
        json.dump(out, open("scratchpad/tt4/gs_weld_check.json", "w"), indent=1)


if __name__ == "__main__":
    main()
