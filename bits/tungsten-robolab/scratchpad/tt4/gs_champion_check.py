#!/usr/bin/env python3
"""The champion's OWN grip under T3's decelerating ideal servo on the validation serves (98030-98099) and T3's set B (830000-830099), the pre-registered pass-rule measures of
scratchpad/tt4/GRASP_SEARCH.md, run before any search because the training baseline already looked open. Run from bits/tungsten-robolab. A file with a __main__ guard."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grasp_search as gs  # noqa: E402


def main():
    x = gs.champion_x()
    out = {}
    for sname, seeds in (("validation 98030-98099", gs.VALID), ("set B 830000-830099", gs.SETB)):
        d = gs.run_serves(x, "champgrip_" + sname.split()[0], seeds, workers=6)
        m = gs.metrics(d, seeds)
        out[sname] = m
        print(f"champion grip, decelerating ideal servo, {sname}: {m}", flush=True)
    json.dump(out, open("scratchpad/tt4/gs_champion_check.json", "w"), indent=1)


if __name__ == "__main__":
    main()
