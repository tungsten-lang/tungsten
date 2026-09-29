"""Arm comfort at a pass stroke: IK of the palm along a straight downward-across stroke, joint-limit margins.

    .venv/bin/python scratchpad/btl2/comfort.py

For a hand (l or r), trunk (spine flexion, twist), a ball meeting point (x, y, z centre) and a stroke direction
n (the palm normal, from the palm toward the ball; the palm moves along +n), solves the arm IK (model joint limits) at
the cock (0.20 m back along -n), the contact and the release (+0.10 m along n), all with the palm normal n.
Prints, per configuration, the worst position error and the smallest distance of any of the six arm joints to its
limits (radians) at the three points, plus the elbow angle at the cock and at the contact.
"""
import itertools
import sys

import mujoco
import numpy as np

sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")
sys.path.insert(0, "scratchpad/btl2")
import reach2 as R  # noqa: E402

m, d = R.m, R.d
ARM = R.ARM
R_BALL = 0.12


def solve_path(side, spine, rot, meet, n, back=0.20, fwd=0.10):
    n = np.array(n) / np.linalg.norm(n)
    pts = {"cock": meet - R_BALL * n - back * n, "contact": meet - R_BALL * n, "release": meet - R_BALL * n + fwd * n}
    out = {}
    seed = None
    for name in ("contact", "cock", "release"):
        best = None
        seeds = R.SEEDS if seed is None else [seed] + list(R.SEEDS)
        for s in seeds:
            e, oe, q = R.ik(side, pts[name], n, s, spine, rot)
            key = e + 0.1 * oe
            if best is None or key < best[0]:
                best = (key, e, oe, q)
        out[name] = best[1:]
        if name == "contact":
            seed = best[3]
    return out


def margin(side, q):
    rng = [m.jnt_range[m.joint(side + "_" + j).id] for j in ARM]
    return min(min(qi - lo, hi - qi) for qi, (lo, hi) in zip(q, rng))


def main():
    side = sys.argv[1] if len(sys.argv) > 1 else "l"
    ls = 1.0 if side == "l" else -1.0
    # left lead: the left hand's ball meets at (mx, ls*my, mz); stroke toward the other spot
    cases = []
    if side == "l":
        spots = ((-0.12, 0.38), (-0.05, 0.32), (0.05, 0.30), (0.15, 0.32))
    else:
        spots = ((0.45, 0.30), (0.40, 0.30), (0.35, 0.28), (0.50, 0.25))
    for spine, rot in ((0.55, 0.55), (0.3, 0.55), (0.3, 0.8), (0.15, 0.8), (0.0, 0.8), (0.15, 0.55), (0.0, 0.55)):
        for mx, my in spots:
            cases.append((spine, rot, mx, my))
    print(f"side {side}: stroke n = (0.42, -0.35*ls, -0.8) toward the other hand; ball centre z 0.64")
    print("spine  twist |  meet x     y  | worst err cm | min limit margin rad (cock/contact/release) | elbow cock/contact")
    for spine, rot, mx, my in cases:
        rr = rot if side == "l" else -rot
        # the model's spine_rot positive turns the LEFT shoulder back; the right side mirrors the sign of the twist
        meet = np.array([mx, ls * my, 0.64])
        if side == "l":
            n = [0.42, -0.35, -0.8]
        else:
            n = [-0.42, 0.35, -0.8]
        res = solve_path(side, spine, rot, meet, n)
        errs = [res[k][0] for k in ("cock", "contact", "release")]
        mg = [margin(side, res[k][2]) for k in ("cock", "contact", "release")]
        print(f"{spine:.2f}  {rot:.2f}  | {mx:+.2f} {my:+.2f} | {100 * max(errs):5.1f}        | "
              f"{mg[0]:+.2f} {mg[1]:+.2f} {mg[2]:+.2f}                         | {res['cock'][2][3]:.2f} {res['contact'][2][3]:.2f}")


if __name__ == "__main__":
    main()
