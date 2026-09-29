import sys, numpy as np, itertools
sys.path.insert(0, "scratchpad/btl")
from reachmap import ik_real, SEEDS
from armik import tilt
SEEDS2 = SEEDS + ([0.0, 0.3, 0.8, 0.3, 0.0, 0.0], [0.3, 0.3, 1.0, 0.5, 0.3, 0.0], [-0.2, 0.2, 1.2, 0.4, -0.3, 0.0], [0.2, 0.1, -1.0, 0.3, 0.3, 0.0])
side = "l"
for zc in (0.7, 0.8, 0.9):
    for a in (0.9, 1.2, 1.4):
        print(f"ball centre z {zc}, palm tilt {a} rad from down toward -y (inward): error cm [forearm z]; rows y, cols x -0.1..0.4")
        for y in (0.3, 0.38, 0.46):
            row = []
            for x in (-0.1, 0.0, 0.1, 0.2, 0.3, 0.4):
                n = tilt(np.array([0.0, -1.0]), a)
                target = np.array([x - 0.12 * n[0], y - 0.12 * n[1], zc - 0.12 * n[2]])
                best = min((ik_real(side, target, n, s, 0.55, 0.0) for s in SEEDS2), key=lambda r: r[0] + 0.1 * r[1])
                row.append(f"{100 * best[0]:4.1f}[{best[2]:.2f}]")
            print("  y", y, " ".join(row))
