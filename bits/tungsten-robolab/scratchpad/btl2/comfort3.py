"""Lateral-pass layout: python comfort3.py spine twist mx my mz  (left hand; stroke toward -y with a forward/back component ux)"""
import sys
import numpy as np
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks"); sys.path.insert(0, "scratchpad/btl2")
import reach2 as R
from comfort import solve_path, margin
spine, rot, mx, my = float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
mz = float(sys.argv[5]) if len(sys.argv) > 5 else 0.64
print(f"left spine {spine} twist {rot} meet ({mx},{my},{mz})")
print("ux  tilt deg | worst err cm | margins cock/contact/release | elbow cock/contact/release | shoulder_rot contact")
for ux in (0.0, 0.5):
    u = np.array([ux, -1.0]); u = u / np.linalg.norm(u)
    for tilt in (10, 20, 30, 40, 50, 65):
        a = np.radians(tilt)
        n = [u[0] * np.sin(a), u[1] * np.sin(a), -np.cos(a)]
        res = solve_path("l", spine, rot, np.array([mx, my, mz]), n)
        errs = [res[k][0] for k in ("cock", "contact", "release")]
        mg = [margin("l", res[k][2]) for k in ("cock", "contact", "release")]
        print(f"{ux:.1f} {tilt:4d}     | {100*max(errs):5.1f}       | {mg[0]:+.2f} {mg[1]:+.2f} {mg[2]:+.2f}   | {res['cock'][2][3]:.2f} {res['contact'][2][3]:.2f} {res['release'][2][3]:.2f} | {res['contact'][2][2]:+.2f}")
