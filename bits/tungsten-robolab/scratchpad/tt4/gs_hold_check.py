#!/usr/bin/env python3
"""HELD-PLANE oracle with a DAMPED hold (3 Oct 2026): welded paddle (o6) + settled pelvis (o1) + the ideal arm servo (o5, decelerating) that arrives o5_lead seconds before the planned contact and then
holds the plane with the damped step o5_hold_alpha (the earlier hold, a full Newton step per tick, rang and parked the pad off the ball; gs_lead_check.py). The plan is a STILL pad (v = 0).
Usage: gs_hold_check.py LEAD:ALPHA[:TACT] [LEAD:ALPHA[:TACT] ...] [--champ-pelvis] [--hand] [--setb] [--smoke]. A LABELLED DIAGNOSTIC ORACLE. Run from bits/tungsten-robolab. A file with a __main__ guard."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grasp_search as gs  # noqa: E402
import gs_pelvis_check as pc  # noqa: E402


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    modes = ("o5,o6" if "--champ-pelvis" in flags else "o1,o5,o6") if "--hand" not in flags else ("o5" if "--champ-pelvis" in flags else "o1,o5")
    if "--trunk" in flags:
        modes += ",o7"
    sets = [("smoke", (98030, 98034))] if "--smoke" in flags else [("validation", gs.VALID)] + ([("setB", gs.SETB)] if "--setb" in flags else [])
    out = json.load(open("scratchpad/tt4/gs_hold_check.json")) if os.path.exists("scratchpad/tt4/gs_hold_check.json") else {}
    for la in args:
        f = [float(x) for x in la.split(":")]
        lead, alpha, tact = f[0], f[1], (f[2] if len(f) > 2 else 0.30)
        cfg = {"o5_togo": 1, "o5_tact": tact, "o5_hold": 0.03, "o5_wrot": 0.30, "o5_lead": lead, "o5_hold_alpha": alpha}
        if "--weld0" in flags:
            cfg["o6_ton"] = 0.0
        for fl in flags:
            if fl.startswith("--cfg="):                    # extra oracle options, a JSON dict: --cfg={"o5_wrot":0.6}
                cfg.update(json.loads(fl[len("--cfg="):]))
        if "o1" in modes:
            cfg["o1_margin"] = 0.15
        for sname, seeds in sets:
            extra = "".join(c if c.isalnum() else "" for fl in flags if fl.startswith("--cfg=") for c in fl[6:])
            d = pc.run(f"hold{'w0' if '--weld0' in flags else ''}{extra}_{modes.replace(',', '')}_{int(lead * 1000)}_{int(alpha * 100)}_{int(tact * 1000)}_{sname}", seeds, modes, cfg)
            m = pc.stats(d, seeds)
            key = f"{modes} lead {lead} alpha {alpha} tact {tact} {extra} / {sname}"
            out[key] = m
            print(f"{modes:8s} {extra[:24]:24s} tact {tact:.2f} lead {lead:.2f} s hold alpha {alpha:.2f}  {sname:10s} contact {m['contact']:3d}/{m['n']}  pad {m['pos_med']} cm {m['ori_med']} deg {m['pad_speed_med']} m/s  solved {m['solved']:3d}/{m['n']} ({100 * m['solved'] / m['n']:.0f} %)", flush=True)
            if "--smoke" not in flags:
                json.dump(out, open("scratchpad/tt4/gs_hold_check.json", "w"), indent=1)


if __name__ == "__main__":
    main()
