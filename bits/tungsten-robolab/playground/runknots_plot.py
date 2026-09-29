"""P7 figure: the runner's joint cycles against the reference (the champion and
the ILC-learnt knot residual) and the ILC learning curves.

    .venv-pose/bin/python playground/runknots_plot.py \
        --cycles playground/search_results/p7/cycles_mocap.json \
        --ilc mocap=playground/search_results/p7/ilc_mocap.jsonl ... \
        --out playground/search_results/p7/p7.png

(matplotlib lives in .venv-pose; the data come from runknots.py `cycles` and
the ILC logs.)
"""

import argparse
import json

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402

JOINTS = (("r_hip_flex", "hip"), ("r_knee", "knee"), ("r_ankle", "ankle"), ("r_shoulder_flex", "shoulder"))
COLORS = ("#1f5fbf", "#d0662c", "#2e9d62", "#8a4fbf", "#9a9a9a")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cycles", required=True)
    ap.add_argument("--ilc", nargs="*", default=[])
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    cyc = json.load(open(a.cycles))
    ph = np.linspace(0, 100, 101)
    n = len(JOINTS) + (1 if a.ilc else 0)
    fig, axes = plt.subplots(1, n, figsize=(4.2 * n, 3.6))
    for ax, (j, name) in zip(axes, JOINTS):
        ax.plot(ph, cyc["reference"][j], color="black", lw=2.2, label="reference")
        for (label, run), col in zip(cyc["runs"].items(), COLORS):
            if run["cycle"]:
                ax.plot(ph, run["cycle"][j], color=col, lw=1.5, label=label)
        ax.set_title(f"right {name} (deg)")
        ax.set_xlabel("% of stride (0 = right touchdown)")
        ax.grid(alpha=0.3)
    axes[0].legend(fontsize=8, loc="best")
    if a.ilc:
        ax = axes[-1]
        for spec, col in zip(a.ilc, COLORS):
            label, path = spec.split("=", 1)
            its, kin = [], []
            for line in open(path):
                r = json.loads(line)
                if isinstance(r.get("iter"), int) and "summary" in r and "rejected" not in r:
                    its.append(r["iter"])
                    kin.append(r["summary"].get("kin_rms"))
            ax.plot(its, kin, "o-", color=col, label=label)
        ax.set_title("ILC: training kin_rms (deg)")
        ax.set_xlabel("accepted iteration")
        ax.grid(alpha=0.3)
        ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(a.out, dpi=110)
    print("wrote", a.out)


if __name__ == "__main__":
    main()
