#!/usr/bin/env python3
"""The ideal WHOLE-BODY HELD-PLANE stroke (2 Oct 2026): settled pelvis (o1) + the decelerating ideal pad-space arm servo (o5) that arrives at rest o5_lead seconds BEFORE the planned contact and is then
held on the plan (a still pad: the plan's velocity is 0), the champion's own grip. Leads 0.05 / 0.10 / 0.15 s, validation serves 98030-98099 and T3's set B 830000-830099. Reports contacts, pad error at
contact, pad speed at contact, solved. A LABELLED DIAGNOSTIC ORACLE. Run from bits/tungsten-robolab. A file with a __main__ guard."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grasp_search as gs  # noqa: E402
import gs_pelvis_check as pc  # noqa: E402


def main():
    out = {}
    for lead in (0.05, 0.10, 0.15):
        cfg = {"o5_togo": 1, "o5_tact": 0.30, "o5_hold": 0.03, "o5_wrot": 0.30, "o1_margin": 0.15, "o5_lead": lead}
        for sname, seeds in (("validation 98030-98099", gs.VALID), ("set B 830000-830099", gs.SETB)):
            d = pc.run(f"lead_{int(lead * 100)}_{sname.split()[0]}", seeds, "o1,o5", cfg)
            m = pc.stats(d, seeds)
            out[f"lead {lead} / {sname}"] = m
            print(f"settled pelvis + held plane, lead {lead:.2f} s {sname:24s} {m}", flush=True)
    json.dump(out, open("scratchpad/tt4/gs_lead_check.json", "w"), indent=1)


if __name__ == "__main__":
    main()
