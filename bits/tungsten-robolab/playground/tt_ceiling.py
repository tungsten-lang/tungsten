"""Success ceiling of a return controller as a function of its execution noise (round 10).

For each hit of a tt_eval run (its contact conditions: the ball's velocity into the pad and its position) the best design is
searched: a planned pad velocity along the ball's travel (`retreat`, m/s), a pad pitch and a pad yaw, with the pad's
actual normal and velocity drawn around the plan (pitch sd, yaw sd, velocity sd per axis) and the return flown by the offline
model (tt_impact: e 0.95, alpha 0.9, mu 0.012; ballistic flight to the opponent's half, net at x = 0 to z 0.9475). The
result is P(return lands | contact in the sweet area) at that noise, and with the contact's in-plane position noise (sd per
axis, Rayleigh) the chance the ball meets the pad inside `r_ok` (0.085 m of its 0.093 m radius; hits nearer the rim fail).

    .venv-myo/bin/python playground/tt_ceiling.py out/tt_r10/champ_710000.jsonl [--n 60]

Prints a table of the ceiling P(success) = P(land | hit) x P(hit inside r_ok) over the noise grid.
"""

import argparse
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tt_impact as ti  # noqa: E402

E, ALPHA, MU = 0.95, 0.9, 0.012
DEL = np.arange(-0.25, 1.51, 0.25)
PHA = np.arange(-30, 41, 3.0)
YWA = np.arange(-24, 25, 4.0)


def best_design(vin, pos, sp, sy, sv, Z):
    """max over (retreat, pitch, yaw) of P(land) with normal / velocity noise (sp deg, sy deg, sv m/s)."""
    best = 0.0
    ret = np.array([1.0, 0.0, 0.0])
    for d in DEL:
        vp = (d * ret)[None, :] + sv * Z[:, 2:5]
        P = np.radians(PHA[:, None, None] + sp * Z[None, None, :, 0])
        Y = np.radians(YWA[None, :, None] + sy * Z[None, None, :, 1])
        n = np.stack([np.cos(P) * np.cos(Y), np.cos(P) * np.sin(Y), np.sin(P) + 0 * Y], axis=-1)
        n = n / np.linalg.norm(n, axis=-1, keepdims=True)
        v = ti.impact(vin, ALPHA * vp[None, None, :, :], n, E, MU)
        best = max(best, float(ti.landing_ok(pos, v).mean(axis=-1).max()))
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("runs", nargs="+")
    ap.add_argument("--n", type=int, default=60, help="hits used")
    ap.add_argument("--r_ok", type=float, default=0.085)
    a = ap.parse_args()
    rows = []
    for p in a.runs:
        rows += [json.loads(l) for l in open(p) if l.strip()]
    hits = [r for r in rows if "error" not in r and r.get("hit") and r.get("ball_in_exact") and r.get("ball_pos_out")]
    step = max(1, len(hits) // a.n)
    hits = hits[::step][:a.n]
    rng = np.random.default_rng(11)
    Z = rng.standard_normal((48, 5))
    print(f"{len(hits)} hits used (contact conditions of {', '.join(os.path.basename(p) for p in a.runs)})")
    print("P(land | hit) with the best plan (retreat, pitch, yaw) per serve:")
    print("pitch sd (deg) | vel sd (m/s) | yaw sd (deg) | P(land | hit)")
    table = {}
    for sp, sv, sy in [(10, 0.5, 2.5), (6, 0.35, 2.5), (4, 0.25, 2.0), (3, 0.2, 1.5), (2, 0.12, 1.0), (1, 0.05, 0.5)]:
        pl = np.mean([best_design(np.array(r["ball_in_exact"]), np.array(r["ball_pos_out"]), sp, sy, sv, Z) for r in hits])
        table[(sp, sv, sy)] = pl
        print(f"{sp:>14} | {sv:>12} | {sy:>12} | {pl:.3f}")
    print("P(ball meets the pad within r_ok = %.3f m) for an in-plane position sd per axis:" % a.r_ok)
    for sd in (0.06, 0.05, 0.04, 0.03, 0.02, 0.01):
        print(f"  sd {sd * 100:.0f} cm: {1 - np.exp(-a.r_ok ** 2 / (2 * sd ** 2)):.3f}")
    print("ceiling P(success) = P(land | hit) x P(inside r_ok):")
    for (sp, sv, sy), pl in table.items():
        print(f"  pitch {sp} deg, vel {sv} m/s, yaw {sy}: " + ", ".join(
            f"pos sd {sd * 100:.0f} cm: {pl * (1 - np.exp(-a.r_ok ** 2 / (2 * sd ** 2))):.2f}" for sd in (0.05, 0.03, 0.02)))


if __name__ == "__main__":
    main()
