#!/usr/bin/env python3
"""The ideal WHOLE-BODY 'settle and hold the plane' stroke (2 Oct 2026): T3's settled-pelvis oracle (o1: the two pelvis slides reach the pass-1 contact position at rest by t_contact - 0.15 s) together with the
decelerating ideal pad-space arm servo (o5, o5_togo: the pad arrives at rest on the plan), the champion's own grip, serves 98030-98099 (validation) and 830000-830099 (T3's set B). Measures how well the
HAND-HELD paddle returns the ball once the body and the arm are ideal (T3's kinematic paddle, a wall, returned 97 %). A LABELLED DIAGNOSTIC ORACLE. Run from bits/tungsten-robolab. A file with a __main__ guard."""
import json
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grasp_search as gs  # noqa: E402


def run(tag, seeds, modes, cfg, params_set=""):
    d = os.path.join(gs.OUT, tag)
    import shutil
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d, exist_ok=True)
    env = dict(os.environ, TT_ENV="P2", TT_SAVE_LOG=d + "/logs", MYO_TT_ORACLE=modes, TT_TASK="myo_tt_oracle", TT3_PLAN=gs.PLAN, TT3_CFG=json.dumps(cfg), TT3_LOG=d + "/orc", TT3_PASS1="out/tt3/logs_o0")
    cmd = ["nice", "-n", "10", gs.PY, "playground/tt_eval.py", "--params", gs.BASE_PARAMS, "--controller", gs.CONTROLLER, "--seeds", f"{seeds[0]}:{seeds[1]}", "--out", d + "/rows.jsonl", "--workers", "6"]
    if params_set:
        cmd += ["--set", params_set]
    with open(d + "/out.txt", "w") as fo:
        subprocess.run(cmd, env=env, stdout=fo, stderr=subprocess.STDOUT)
    return d


def stats(d, seeds):
    m = gs.metrics(d, seeds)
    sp = []
    for s in range(seeds[0], seeds[1]):
        f = os.path.join(d, "logs", f"{s}.npz")
        if os.path.exists(f):
            z = np.load(f, allow_pickle=True)
            L, k = z["L"], int(z["contact"])
            if k >= 3:
                sp.append(float(np.linalg.norm((L[k - 1, 7:10] - L[k - 2, 7:10]) / (L[k - 1, 0] - L[k - 2, 0]))))
    m["pad_speed_med"] = round(float(np.median(sp)), 2) if sp else None
    m["solved_of_contacts"] = round(m["solved"] / max(m["contact"], 1), 3)
    return m


def main():
    base = {"o5_togo": 1, "o5_tact": 0.30, "o5_hold": 0.03, "o5_wrot": 0.30}
    out = {}
    for label, modes, cfg in (("ideal arm only (champion's pelvis)", "o5", base), ("settled pelvis + ideal arm (margin 0.15 s)", "o1,o5", dict(base, o1_margin=0.15)),
                              ("settled pelvis + ideal arm (margin 0.25 s)", "o1,o5", dict(base, o1_margin=0.25, o5_tact=0.25))):
        for sname, seeds in (("validation 98030-98099", gs.VALID), ("set B 830000-830099", gs.SETB)):
            d = run("pel_" + str(len(out)), seeds, modes, cfg)
            m = stats(d, seeds)
            out[f"{label} / {sname}"] = m
            print(f"{label:46s} {sname:24s} {m}", flush=True)
    json.dump(out, open("scratchpad/tt4/gs_pelvis_check.json", "w"), indent=1)


if __name__ == "__main__":
    main()
