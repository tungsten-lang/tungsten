#!/usr/bin/env python3
"""When and how does the hand-held paddle leave the hand under the backward-plan servo? One serve, the plan R2 picked in the weld sweep (out/tt5/bwd.jsonl), run hand-held (o1, o5, o7) in this
process with the per-tick log (TT_SAVE_LOG): palm-to-paddle distance over time, the pad's distance to the plan's pad centre, the pad speed. A diagnostic of the main session (3 Oct 2026).
    TT_ENV=P2 .venv-myo/bin/python scratchpad/tt5/hand_diag.py SEED          from bits/tungsten-robolab"""
import json
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(ROOT)
seed = int(sys.argv[1])
os.environ["MYO_TT_ORACLE"] = "o1,o5,o7"
_cfg = {"o5_togo": 1, "o5_tact": 0.15, "o5_hold": 0.03, "o5_wrot": 0.30, "o5_lead": 0.05, "o5_hold_alpha": 0.6, "o1_margin": 0.15, "o6_ton": 0.0, "o5_mus_off": 1}
_cfg.update(json.loads(os.environ.get("HD_EXTRA", "{}")))     # e.g. HD_EXTRA='{"o5_minjerk":1}'
os.environ["TT3_CFG"] = json.dumps(_cfg)
os.environ["TT_SAVE_LOG"] = "out/tt5/diag"
sys.path.insert(0, os.path.join(ROOT, "scratchpad", "tt5"))
import backward_plan as bp  # noqa: E402


def r2(rows, sd):
    c = []
    for r in rows:
        if r["seed"] != sd or r.get("error") or not r.get("perr"):
            continue
        pe = r["perr"]
        r["pos"], r["ang"] = 100 * float(np.linalg.norm(pe[:3])), float(pe[3])
        r["reached"] = r["pos"] <= 1.5 and r["ang"] <= 2.5
        r["err"] = r["pos"] / 1.5 + r["ang"] / 2.5
        c.append(r)
    return max([r for r in c if r["reached"]], key=lambda r: r["margin"]) if any(r["reached"] for r in c) else min(c, key=lambda r: r["err"])


def main():
    import tt_fast
    rows = [json.loads(l) for l in open("out/tt5/bwd.jsonl")]
    want = r2(rows, seed)
    plan = next(c["plan"] for c in bp.candidates(seed) if c["off"] == want["off"] and c["kind"] == want["kind"] and c["speed"] == want["speed"])
    params = tt_fast.read_params(bp.PARAMS)
    res = tt_fast.episode((params, seed, None, os.path.abspath(bp.CONTROLLER), {"orc_plan": plan}))
    print(f"serve {seed}: plan {want['kind']} offset {1000 * want['off']:+.0f} ms, pitch {want['pitch']:+.0f} yaw {want['yaw']:+.0f} speed {want['speed']:.0f}, t_hit {plan['t_hit']:.2f}; hand-held result: solved {res.get('solved')}, hit {res.get('hit')}, palm_err_max {res.get('palm_err_max')}; weld result: solved {want['solved']}")
    z = np.load(f"out/tt5/diag/{seed}.npz", allow_pickle=True)
    L, X = z["L"], z["X"]
    P = np.array(plan["P"])
    print("   t     palm-paddle (m)   pad - plan centre (cm)   pad speed   arm joint speeds |qd| (rad/s) shoulder_elv elbow")
    for i in range(0, len(L), 4):
        t = L[i, 0]
        if t < 0.1 or t > plan["t_hit"] + 0.15:
            continue
        sp = np.linalg.norm(L[i, 7:10] - L[max(i - 1, 0), 7:10]) / 0.01
        qd = X[i, 12:24] if X.shape[1] >= 24 else np.zeros(12)
        print(f"  {t:.2f}   {np.linalg.norm(L[i, 25:28]):8.3f}          {100 * np.linalg.norm(L[i, 7:10] - P):7.1f}                 {sp:5.1f}      {qd[1]:6.1f} {qd[3]:6.1f}")


if __name__ == "__main__":
    main()
