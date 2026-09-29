"""convkf_plot: P6 learning curves (needs matplotlib: run with .venv-pose).

    .venv-pose/bin/python playground/convkf_plot.py [out/search/p6] [playground/search_results/p6/curves.png]

Reads every <arm>_<method>_s<seed>/log.jsonl under the runs directory and
draws small multiples, one column per arm: the search centre's two score
components on 16 fixed probe starts at 0.003 rad, the mean legal mark of the
starts it landed and the number it fell on, against training rollouts, for
ES and sep-CMA-ES, with the untrained start (the arena champion) as a
reference; a run continued past the equal budget (<run>_cont) extends its
line, past a dotted mark at 3200 rollouts.
Also writes curves.csv beside the figure.
"""

import json
import os
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ARMS = [("champ", "champion's 126 tunables"), ("knots", "quintic knots (220)"),
        ("knots_tcn", "knots + TCN (1522)"), ("tcn", "TCN alone (1302)")]
METHODS = [("es", "ES", "#2a78d6"), ("sep_cma", "sep-CMA-ES", "#eb6834")]
INK, MUTED, GRID, SURFACE = "#0b0b0b", "#52514e", "#e4e3df", "#fcfcfb"


def probes(path):
    rows = [json.loads(line) for line in open(path)]
    out, seen = [], set()
    for r in rows:
        if "probe" in r and r["rollouts"] not in seen:
            seen.add(r["rollouts"])
            out.append((r["rollouts"], r["probe"]["mean"], r["probe"]["falls"], r["probe"]["legal_mark"]))
    return out


def main():
    runs = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "out", "search", "p6")
    png = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "search_results", "p6", "curves.png")
    os.makedirs(os.path.dirname(png), exist_ok=True)
    plt.rcParams.update({"font.size": 9, "axes.edgecolor": MUTED, "axes.labelcolor": MUTED,
                         "xtick.color": MUTED, "ytick.color": MUTED, "text.color": INK})
    fig, axes = plt.subplots(2, 4, figsize=(13, 5.2), sharex="col", sharey="row", facecolor=SURFACE,
                             gridspec_kw={"height_ratios": [2, 1]})
    csv = ["arm,method,rollouts,probe_mean,probe_falls,probe_legal_mark"]
    base = None
    for col, (arm, title) in enumerate(ARMS):
        top, bot = axes[0][col], axes[1][col]
        for ax in (top, bot):
            ax.set_facecolor(SURFACE)
            ax.grid(True, color=GRID, linewidth=0.8)
            ax.spines[["top", "right"]].set_visible(False)
        top.set_title(title, fontsize=10, color=INK)
        for meth, label, color in METHODS:
            path = os.path.join(runs, f"{arm}_{meth}_s1", "log.jsonl")
            if not os.path.exists(path):
                continue
            pr = probes(path)
            cont = os.path.join(runs, f"{arm}_{meth}_s1_cont", "log.jsonl")
            if os.path.exists(cont):  # a continued run (same centre, counted on)
                pr += [p for p in probes(cont) if p[0] > pr[-1][0]]
                for ax in (top, bot):
                    ax.axvline(3200, color=MUTED, linewidth=1, linestyle=":")
                top.annotate("equal budget", xy=(3200, 0), xycoords=("data", "axes fraction"), xytext=(4, 4),
                             textcoords="offset points", color=MUTED, fontsize=8)
            base = pr[0][3] if base is None else base
            xs = [p[0] for p in pr]
            top.plot(xs, [p[3] for p in pr], color=color, linewidth=2, marker="o", markersize=4, label=label)
            bot.plot(xs, [p[2] for p in pr], color=color, linewidth=2, marker="o", markersize=4, label=label)
            for p in pr:
                csv.append(f"{arm},{meth},{p[0]},{p[1]:.4f},{p[2]},{'' if p[3] is None else f'{p[3]:.4f}'}")
        if base is not None:
            top.axhline(base, color=MUTED, linewidth=1, linestyle="--")
        bot.set_xlabel("training rollouts")
    axes[0][0].set_ylabel("legal mark of the landings (m)")
    axes[1][0].set_ylabel("falls / 16")
    if base is not None:
        axes[0][0].annotate("start = champion", xy=(0, base), xytext=(250, base + 0.012), color=MUTED, fontsize=8)
    handles, labels = axes[0][0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper right", frameon=False, ncol=2)
    fig.suptitle("P6: the search centre on 16 fixed probe starts (0.003 rad): distance and falls vs training rollouts", x=0.01,
                 ha="left", fontsize=11, color=INK)
    fig.tight_layout(rect=(0, 0, 1, 0.95))
    fig.savefig(png, dpi=130, facecolor=SURFACE)
    open(os.path.splitext(png)[0] + ".csv", "w").write("\n".join(csv) + "\n")
    print(f"wrote {png}")


if __name__ == "__main__":
    main()
