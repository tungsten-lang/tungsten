#!/usr/bin/env python3
"""Summary of the per-position orientation x speed wall sweep (scratchpad/tt5/wall_sweep.py): for every serve and every slice of the ball's free path, which pad orientations (pitch, yaw) and speeds
return the ball legally with the real physics, and where the champion's OWN pad (orientation, velocity at that tick of its log) sits against that region; plus the agreement with the impact model.
    .venv-myo/bin/python scratchpad/tt5/wall_summary.py [out/tt5/wall.jsonl]      from bits/tungsten-robolab"""
import collections
import json
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(ROOT)
sys.path.insert(0, os.path.join(ROOT, "playground"))
sys.path.insert(0, os.path.join(ROOT, "scratchpad", "tt5"))
import tt_impact as ti  # noqa: E402
from slice_model import margin, E, MU, ALPHA  # noqa: E402

PITCH = [-30, -20, -10, 0, 10, 20, 30, 40]
YAW = [-30, -20, -10, 0, 10, 20, 30]
path = sys.argv[1] if len(sys.argv) > 1 else "out/tt5/wall.jsonl"
rows = [json.loads(l) for l in open(path)]
rows = [r for r in rows if not r.get("error")]
by = collections.defaultdict(lambda: collections.defaultdict(dict))
for r in rows:
    by[r["seed"]][r["j"]][(r["pitch"], r["yaw"], r["speed"])] = r
meta = {}
for s in ("A", "B"):
    for l in open(f"out/tt3/o0_{s}.jsonl"):
        r = json.loads(l)
        meta[r["seed"]] = r
tot = collections.Counter()
for sd in sorted(by):
    z = np.load(f"out/tt3/logs_o0/{sd}.npz", allow_pickle=True)
    L, k = z["L"], int(z["contact"])
    cls = "solved" if meta[sd].get("solved", 0) > 0 else ("touched" if k >= 0 else "MISS")
    pad = L[:, 7:10]
    n = L[:, 13:16] / np.linalg.norm(L[:, 13:16], axis=1, keepdims=True)
    n = np.where(n[:, :1] < 0, -n, n)
    vp = np.gradient(pad, L[:, 0], axis=0)
    print(f"\n=== serve {sd}: the champion's own result: {cls} (contact tick {k}), side {meta[sd].get('side')}")
    print("  tick  t     ball x    y    z   |  physics: legal cells of 56 pitch x yaw at pad speed 0 / 1 / 2 m/s (retreat) | best cell v=0 | champion's pad at that tick: pitch yaw  speed(x) | dist to the nearest legal cell (deg) | the champion's pad against the ball at that tick")
    for j in sorted(by[sd]):
        cells = by[sd][j]
        cnt = [sum(1 for (p, y, s_), r in cells.items() if s_ == sp and (r["solved"] or 0) > 0) for sp in (0.0, 1.0, 2.0)]
        legal0 = [(p, y) for (p, y, s_), r in cells.items() if s_ == 0.0 and (r["solved"] or 0) > 0]
        anyl = [(p, y, s_) for (p, y, s_), r in cells.items() if (r["solved"] or 0) > 0]
        pp = float(np.degrees(np.arcsin(np.clip(n[j, 2], -1, 1))))
        yy = float(np.degrees(np.arctan2(n[j, 1], n[j, 0])))
        d = min((np.hypot(p - pp, y - yy) for p, y, s_ in anyl), default=None)
        best = ""
        if legal0:
            best = f"centre ({np.mean([p for p, y in legal0]):+.0f}, {np.mean([y for p, y in legal0]):+.0f})"
        ball = L[j, 1:4]
        dd = ball - pad[j]
        dn_ = float(dd @ n[j])
        dp_ = float(np.linalg.norm(dd - dn_ * n[j]))
        print(f"  {j:4d} {L[j, 0]:.2f}  {ball[0]:.2f} {ball[1]:+.2f} {ball[2]:.2f} |  {cnt[0]:3d} / {cnt[1]:3d} / {cnt[2]:3d}                    | {best:16s} |  {pp:+5.0f} {yy:+5.0f}   {vp[j, 0]:+5.1f}      | {('%.0f' % d) if d is not None else '-':>4s}   | pad-to-ball in-plane {100 * dp_:5.1f} cm, normal {100 * dn_:+5.1f} cm")
        # agreement with the model on this slice
        for (p, y, s_), r in cells.items():
            nm = ti.normal_from_angles(np.radians(p), np.radians(y))
            v = ti.impact(np.array(r["vball"]), ALPHA * np.array([s_, 0, 0]), nm, E, MU)
            mm = float(margin(np.array(r["ball"]), v)) > 0
            tot[(mm, (r["solved"] or 0) > 0)] += 1
print("\nAGREEMENT of the impact model (E 0.95, MU 0.012, ALPHA 0.9) with the physics over all cells: (model legal, physics solved): count")
for k_ in ((True, True), (True, False), (False, True), (False, False)):
    print(f"   model {'legal  ' if k_[0] else 'illegal'}  physics {'solved' if k_[1] else 'failed'}: {tot[k_]}")
tp, fp, fn = tot[(True, True)], tot[(True, False)], tot[(False, True)]
print(f"   precision of the model's 'legal' {100 * tp / max(tp + fp, 1):.0f} %, recall of the physics-solved cells {100 * tp / max(tp + fn, 1):.0f} %")
