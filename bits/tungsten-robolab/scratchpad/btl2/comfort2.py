"""Tilt scan of the stroke at a fixed layout: python comfort2.py side spine twist mx my [mz]"""
import sys
import numpy as np
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks"); sys.path.insert(0, "scratchpad/btl2")
import reach2 as R
from comfort import solve_path, margin
side, spine, rot, mx, my = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
mz = float(sys.argv[6]) if len(sys.argv) > 6 else 0.64
ls = 1.0 if side == "l" else -1.0
u = np.array([0.65, -0.76]) if side == "l" else np.array([-0.65, 0.76])
print(f"{side} spine {spine} twist {rot} meet ({mx},{ls*my},{mz})")
print("tilt deg | worst err cm | margins cock/contact/release | elbow cock/contact/release | shoulder_rot at contact")
for tilt in (5, 15, 25, 35, 45, 60, 75, 85):
    a = np.radians(tilt)
    n = [u[0] * np.sin(a), u[1] * np.sin(a), -np.cos(a)]
    res = solve_path(side, spine, rot, np.array([mx, ls * my, mz]), n)
    errs = [res[k][0] for k in ("cock", "contact", "release")]
    mg = [margin(side, res[k][2]) for k in ("cock", "contact", "release")]
    print(f"{tilt:5d}    | {100*max(errs):5.1f}       | {mg[0]:+.2f} {mg[1]:+.2f} {mg[2]:+.2f}   | {res['cock'][2][3]:.2f} {res['contact'][2][3]:.2f} {res['release'][2][3]:.2f} | {res['contact'][2][2]:+.2f}")
