"""One-screen summary of tt_eval.py runs (round 10): outcome rates and the contact mechanics, per side.

    .venv-myo/bin/python playground/tt_summ.py out/tt_r10/a.jsonl [b.jsonl ...] [--seeds a:b]

Per side: solved, hit, landing slack (tt_impact.margin, clipped), the pad's velocity along its normal at contact (+ = retreating), the
pad's pitch and its error to the aim law (deg), the ball-minus-pad z offset (cm), the ball's exit speed and elevation.
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tt_impact as ti  # noqa: E402


def orient(n):
    n = np.asarray(n, float)
    return n * np.sign(n[..., 0:1] + 1e-12)


def load(path, lo=None, hi=None):
    out = []
    for line in open(path):
        line = line.strip()
        if line:
            r = json.loads(line)
            if "error" not in r and (lo is None or lo <= r["seed"] < hi):
                out.append(r)
    return out


def summarize(rows, label):
    print(f"== {label}: n {len(rows)}, solved {sum(r['solved'] > 0 for r in rows)} ({np.mean([r['solved'] > 0 for r in rows]):.3f}), hit {np.mean([r['hit'] > 0 for r in rows]):.3f}")
    for side, nm in ((1, "forehand"), (2, "backhand")):
        D = [r for r in rows if r.get("side") == side]
        if not D:
            continue
        H = [r for r in D if r.get("hit") and r.get("paddle_vel") and r.get("pad_normal") and r.get("ball_out_exact")]
        sl = np.mean([float(np.clip(ti.margin(r["ball_pos_out"], r["ball_out_exact"]), -0.6, 0.3)) if r in H else -0.6 - r.get("miss_dist", 0.5) for r in D])
        s = f"  {nm}: n {len(D)} solved {np.mean([r['solved'] > 0 for r in D]):.3f} hit {len(H) / len(D):.3f} slack {sl:+.3f}"
        if H:
            n = orient(np.array([r["pad_normal"] for r in H]))
            vp = np.array([r["paddle_vel"] for r in H])
            vn = (vp * n).sum(1)
            pit = np.degrees(np.arcsin(n[:, 2]))
            zo = np.array([r["ball_pos_out"][2] - r["pad_at_contact"][2] for r in H]) * 100
            ex = np.array([np.linalg.norm(r["ball_out_exact"]) for r in H])
            el = np.array([np.degrees(np.arcsin(r["ball_out_exact"][2] / np.linalg.norm(r["ball_out_exact"]))) for r in H])
            s += f" | vpad.n {vn.mean():+.2f}+-{vn.std():.2f} | pitch {pit.mean():+.1f}+-{pit.std():.1f}"
            A = [r for r in H if r.get("aim_normal")]
            if A:
                pa = np.degrees(np.arcsin(orient(np.array([r["aim_normal"] for r in A]))[:, 2]))
                pt = np.degrees(np.arcsin(orient(np.array([r["pad_normal"] for r in A]))[:, 2]))
                s += f" (err {np.mean(pt - pa):+.1f}+-{np.std(pt - pa):.1f})"
            s += f" | z off {zo.mean():+.1f}+-{zo.std():.1f} cm | exit {ex.mean():.2f}+-{ex.std():.2f} m/s, elev {el.mean():.0f}+-{el.std():.0f}"
        print(s)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    lo = hi = None
    if "--seeds" in sys.argv:
        lo, hi = [int(x) for x in sys.argv[sys.argv.index("--seeds") + 1].split(":")]
        args = [a for a in args if ":" not in a or os.path.exists(a)]
    for p in args:
        if os.path.exists(p):
            summarize(load(p, lo, hi), os.path.basename(p))
