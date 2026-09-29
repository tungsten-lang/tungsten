"""search_report: tables, curves (CSV) and plots (PNG) for search_bench runs.

    python playground/search_bench.py report p1      # every variant of p1
    python playground/search_report.py p1 [variant ...]
    python playground/search_report.py export   # durable copy in playground/search_results

Reads out/search/<problem>/<variant>/<method>_s<seed>.json and writes, per
variant, out/search/<problem>/<variant>/table.md, curves.csv (median, min and
max best-so-far across seeds against rollouts used) and curves.png (small
multiples: one panel per method, its median in blue with the seeds' min-max
band as a wash, every other method's median in light gray for context), plus
out/search/<problem>/variants.png when a problem has several variants (one
panel per method, one line per variant). Plots are drawn with Pillow (the
robolab venvs have no matplotlib).
"""

import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "out", "search")
GROUPS = {"p1": {"representations": ["goal", "rate", "mrate", "group"],
                 "easing": ["rate", "ease1", "ease3", "ease4", "ease7", "ease_search"],
                 "keyframes": ["goal", "rate", "kf", "kf_syn", "kf_speed"],
                 "keyframe_easing": ["kf", "kf_linear", "kf_ease"],
                 "refine": ["goal_init", "kf_init"]},
          "p4": {"representations": ["goal", "kf", "kf_syn", "kf_speed"]},
          "p2": {"representations": ["a", "b", "c", "d", "gains"]},
          "p3": {"step_size": ["tunables", "tunables_small"]}}
YLABEL = {"p1": "score = jump mark (m) for a clean landing",
          "p4": "score = distance (m) of consecutive jumps before a fall, -1 for a fall",
          "p2": "score = robust aggregate over 2 push schedules (max ~12)",
          "p3": "score = run score, robust aggregate over 2 starts (20 s)"}

# reference palette (dataviz skill, light mode)
SURFACE = (252, 252, 251)
TEXT = (11, 11, 11)
TEXT2 = (82, 81, 78)
GRID = (230, 229, 225)
CONTEXT = (205, 204, 198)
SERIES = [(42, 120, 214), (235, 104, 52), (27, 175, 122), (237, 161, 0), (232, 123, 164), (0, 131, 0), (74, 58, 167),
          (227, 73, 72)]
METHOD_ORDER = ["cma", "sep_cma", "ipop", "ga", "oneplusone", "random", "cem", "de", "openai_es", "nelder_mead", "pattern",
                "bo", "map_elites"]


def load(problem, variant):
    d = os.path.join(OUT, problem, variant)
    runs = {}
    if not os.path.isdir(d):
        return runs
    for f in sorted(os.listdir(d)):
        if f.endswith(".json") and "_s" in f:
            r = json.load(open(os.path.join(d, f)))
            runs.setdefault(r["method"], []).append(r)
    return runs


def variants(problem):
    d = os.path.join(OUT, problem)
    return sorted(v for v in os.listdir(d) if os.path.isdir(os.path.join(d, v))) if os.path.isdir(d) else []


def resample(curve, grid):
    """Best-so-far step curve [(used, best)] sampled at the rollout counts in grid."""
    xs = np.array([c[0] for c in curve], float)
    ys = np.array([c[1] for c in curve], float)
    out = np.full(len(grid), np.nan)
    for i, g in enumerate(grid):
        k = np.searchsorted(xs, g, side="right") - 1
        if k >= 0:
            out[i] = ys[k]
    return out


def curves(runs, budget):
    grid = np.linspace(1, budget, 200)
    out = {}
    for m, rs in runs.items():
        Y = np.array([resample(r["curve"], grid) for r in rs])
        out[m] = (grid, np.nanmedian(Y, axis=0), np.nanmin(Y, axis=0), np.nanmax(Y, axis=0))
    return out


def order(methods):
    return sorted(methods, key=lambda m: METHOD_ORDER.index(m) if m in METHOD_ORDER else 99)


def at_fraction(r, frac):
    """Best-so-far after `frac` of the budget."""
    target = frac * r["budget"]
    best = None
    for used, b in r["curve"]:
        if used <= target:
            best = b
    return best if best is not None else float("nan")


# variants whose x0 is the same motion scored on the same training seeds, so
# one baseline serves them all (a fixed easing changes x0; a different
# training set changes its training score)
SAME_X0 = {"p1": ["rate", "goal", "mrate", "group", "ease_search"], "p2": ["a", "b", "c", "d", "gains"],
           "p3": ["tunables", "tunables_small"]}


def baseline(problem, variant):
    """x0's scores (search_bench.py baseline): the variant's own, else one
    from a variant with the same x0 and training seeds."""
    same = SAME_X0.get(problem, [])
    for v in [variant] + (same if variant in same else []):
        f = os.path.join(OUT, problem, v, "baseline.json")
        if os.path.exists(f):
            return json.load(open(f))
    return None


def table(problem, variant, runs):
    rows = []
    for m in order(runs):
        rs = runs[m]
        fin = np.array([r["best"] for r in rs])
        half = np.array([at_fraction(r, 0.25) for r in rs])
        ho = np.array([r["heldout"]["mean"] for r in rs])
        fails = sum(r["heldout"]["fails"] for r in rs)
        nho = sum(len(r["heldout"]["scores"]) for r in rs)
        wall = np.median([r["group_wall"] / r["group_size"] for r in rs])
        rs_s = np.median([r["rollout_s"] for r in rs])
        opt_s = np.median([r.get("opt_s", 0.0) for r in rs])
        rows.append((m, len(rs), rs[0]["dims"], rs[0]["budget"], float(np.median(half)), float(np.median(fin)),
                     float(fin.min()), float(fin.max()), float(np.median(ho)), fails, nho, float(wall), float(rs_s),
                     float(opt_s)))
    rows.sort(key=lambda r: -r[5])
    lines = [f"| method | seeds | dims | budget | best @25% (median) | final best: median [min, max] | held-out mean (median) "
             f"| held-out fails | wall/run s | rollout-s/run | optimizer s/run |",
             "| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |"]
    bl = baseline(problem, variant)
    if bl:
        lines.append(f"| x0 (start) | - | - | - | {bl['train']:.3f} | {bl['train']:.3f} | {bl['heldout']['mean']:.3f} "
                     f"| {bl['heldout']['fails']}/{len(bl['heldout']['scores'])} | - | - | - |")
    for m, n, dims, b, h, med, lo, hi, ho, fails, nho, wall, rs_s, opt_s in rows:
        lines.append(f"| {m} | {n} | {dims} | {b} | {h:.3f} | {med:.3f} [{lo:.3f}, {hi:.3f}] | {ho:.3f} | {fails}/{nho} "
                     f"| {wall:.0f} | {rs_s:.0f} | {opt_s:.1f} |")
    return "\n".join(lines), rows


# ---------------------------------------------------------------------------
# drawing


def _font(size, bold=False):
    from PIL import ImageFont
    for path in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc",
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                pass
    return ImageFont.load_default(size=size)


def nice_ticks(lo, hi, n=5):
    if not math.isfinite(lo) or not math.isfinite(hi) or hi <= lo:
        return [lo]
    step = 10 ** math.floor(math.log10((hi - lo) / n))
    for m in (1, 2, 2.5, 5, 10):
        if (hi - lo) / (step * m) <= n:
            step *= m
            break
    t = math.ceil(lo / step) * step
    out = []
    while t <= hi + 1e-9:
        out.append(round(t, 10))
        t += step
    return out


def fmt(v):
    if abs(v) >= 100:
        return f"{v:,.0f}"
    if abs(v) >= 10:
        return f"{v:.0f}" if float(v).is_integer() else f"{v:.1f}"
    return f"{v:g}"


def draw_panels(panels, path, title, subtitle, ylabel, ylim=None, cols=4, legend=None):
    """panels: [(panel title, [(label, xs, med, lo, hi, color, width, band)])]."""
    from PIL import Image, ImageDraw
    S = 2  # supersample
    pw, ph = 360 * S, 250 * S
    ml, mr, mt, mb = 58 * S, 14 * S, 34 * S, 40 * S
    rows = math.ceil(len(panels) / cols)
    head = 86 * S + (26 * S if legend else 0)
    W, H = cols * pw, head + rows * ph + 10 * S
    im = Image.new("RGB", (W, H), SURFACE)
    dr = ImageDraw.Draw(im, "RGBA")
    f_title, f_sub, f_ax, f_pt = _font(20 * S), _font(13 * S), _font(11 * S), _font(13 * S)
    dr.text((16 * S, 14 * S), title, fill=TEXT, font=f_title)
    dr.text((16 * S, 44 * S), subtitle, fill=TEXT2, font=f_sub)
    if legend:
        x = 16 * S
        y = 70 * S
        for lab, col in legend:
            dr.line([(x, y + 8 * S), (x + 22 * S, y + 8 * S)], fill=col, width=3 * S)
            dr.text((x + 28 * S, y), lab, fill=TEXT2, font=f_sub)
            x += 40 * S + int(dr.textlength(lab, font=f_sub))
    allx = [s[1] for p in panels for s in p[1]]
    xmax = max(float(np.max(x)) for x in allx)
    if ylim is None:
        vals = np.concatenate([np.concatenate([s[3], s[4], s[2]]) for p in panels for s in p[1]])
        vals = vals[np.isfinite(vals)]
        ylim = (float(np.min(vals)), float(np.max(vals)))
    y0, y1 = ylim
    pad = 0.05 * (y1 - y0 or 1.0)
    y0, y1 = y0 - pad, y1 + pad
    xt = nice_ticks(0, xmax, 4)
    yt = nice_ticks(y0, y1, 5)
    for i, (pt, series) in enumerate(panels):
        ox, oy = (i % cols) * pw, head + (i // cols) * ph
        L, R, T, B = ox + ml, ox + pw - mr, oy + mt, oy + ph - mb

        def X(v):
            return L + (R - L) * (v / xmax)

        def Y(v):
            return B - (B - T) * ((v - y0) / (y1 - y0))

        for t in yt:
            if y0 <= t <= y1:
                dr.line([(L, Y(t)), (R, Y(t))], fill=GRID, width=1 * S)
                dr.text((L - 6 * S, Y(t)), fmt(t), fill=TEXT2, font=f_ax, anchor="rm")
        for t in xt:
            dr.text((X(t), B + 6 * S), fmt(t), fill=TEXT2, font=f_ax, anchor="mt")
        dr.line([(L, B), (R, B)], fill=CONTEXT, width=1 * S)
        dr.text((L, oy + 10 * S), pt, fill=TEXT, font=f_pt)
        if i // cols == rows - 1:
            dr.text(((L + R) // 2, B + 22 * S), "rollouts used", fill=TEXT2, font=f_ax, anchor="mt")
        for lab, xs, med, lo, hi, col, width, band in series:
            ok = np.isfinite(med)
            xs_, med_, lo_, hi_ = xs[ok], med[ok], lo[ok], hi[ok]
            if len(xs_) < 2:
                continue
            clamp = lambda v: min(max(v, y0), y1)  # noqa: E731
            if band:
                poly = [(X(x), Y(clamp(h))) for x, h in zip(xs_, hi_)] + [(X(x), Y(clamp(l))) for x, l in
                                                                        zip(xs_[::-1], lo_[::-1])]
                dr.polygon(poly, fill=col + (38,))
            pts = [(X(x), Y(clamp(m))) for x, m in zip(xs_, med_)]
            dr.line(pts, fill=col, width=width * S, joint="curve")
        # final median of the highlighted series, labelled at the end
        hl = [s for s in series if s[7]]
        if hl:
            lab, xs, med, lo, hi, col, width, band = hl[0]
            ok = np.isfinite(med)
            if np.any(ok):
                v = float(med[ok][-1])
                cx, cy = X(float(xs[ok][-1])), Y(min(max(v, y0), y1))
                r = 4 * S
                dr.ellipse([cx - r - 2 * S, cy - r - 2 * S, cx + r + 2 * S, cy + r + 2 * S], fill=SURFACE)
                dr.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
                dr.text((cx - 8 * S, cy - 8 * S), f"{v:.3f}", fill=TEXT, font=f_ax, anchor="rb")
    im = im.resize((W // S, H // S), Image.LANCZOS)
    im.save(path)


def draw_heldout(runs, path, title, subtitle, ref=None, keep_order=False):
    """Dot strip: one row per method (best held-out median on top), one dot
    per seed at its held-out mean, the train score of that run as a hollow
    ring, and x0's held-out mean as a reference line."""
    from PIL import Image, ImageDraw
    S = 2
    ms = list(runs) if keep_order else sorted(runs, key=lambda m: -np.median([r["heldout"]["mean"] for r in runs[m]]))
    rowh, left, right, top = 34 * S, 190 * S, 40 * S, 96 * S
    W = 900 * S
    H = top + rowh * len(ms) + 50 * S
    im = Image.new("RGB", (W, H), SURFACE)
    dr = ImageDraw.Draw(im, "RGBA")
    f_title, f_sub, f_ax = _font(20 * S), _font(13 * S), _font(12 * S)
    dr.text((16 * S, 14 * S), title, fill=TEXT, font=f_title)
    dr.text((16 * S, 44 * S), subtitle, fill=TEXT2, font=f_sub)
    vals = [r["heldout"]["mean"] for m in ms for r in runs[m]] + [r["best"] for m in ms for r in runs[m]]
    if ref is not None:
        vals.append(ref)
    lo, hi = min(vals), max(vals)
    pad = 0.05 * (hi - lo or 1)
    lo, hi = lo - pad, hi + pad

    def X(v):
        return left + (W - left - right) * (v - lo) / (hi - lo)

    bottom = top + rowh * len(ms)
    for t in nice_ticks(lo, hi, 6):
        dr.line([(X(t), top - 6 * S), (X(t), bottom)], fill=GRID, width=S)
        dr.text((X(t), bottom + 6 * S), fmt(t), fill=TEXT2, font=f_ax, anchor="mt")
    if ref is not None:
        dr.line([(X(ref), top - 10 * S), (X(ref), bottom)], fill=TEXT2, width=S)
        dr.text((X(ref) + 4 * S, top - 22 * S), "x0 held-out", fill=TEXT2, font=f_ax)
    for i, m in enumerate(ms):
        y = top + rowh * i + rowh // 2
        dr.text((left - 12 * S, y), m, fill=TEXT, font=f_ax, anchor="rm")
        for r in runs[m]:
            x = X(r["best"])
            dr.ellipse([x - 5 * S, y - 5 * S, x + 5 * S, y + 5 * S], outline=CONTEXT, width=2 * S)
        for r in runs[m]:
            x = X(r["heldout"]["mean"])
            dr.ellipse([x - 7 * S, y - 7 * S, x + 7 * S, y + 7 * S], fill=SURFACE)
            dr.ellipse([x - 5 * S, y - 5 * S, x + 5 * S, y + 5 * S], fill=SERIES[0])
    dr.text((W // 2, bottom + 24 * S), "score", fill=TEXT2, font=f_ax, anchor="mt")
    im.resize((W // S, H // S), Image.LANCZOS).save(path)


HELDOUT_GROUPS = {"p1": {"training": ["rate", "rate_robust"]},
                  "p4": {"representations_heldout": ["goal", "kf", "kf_syn", "kf_speed"]},
                  "p2": {"training": ["a", "a_k4", "a_fresh"], "representations_heldout": ["a", "b", "c", "d", "gains"]}}


def compare_heldout(problem, vlist, name, methods=("cma", "sep_cma", "oneplusone", "bo")):
    """Held-out dot strip across variants: one row per (method, variant)."""
    runs = {}
    for v in vlist:
        for m, rs in load(problem, v).items():
            if m in methods:
                runs[f"{m} / {v}"] = rs
    if len({k.split(" / ")[1] for k in runs}) < 2:
        return
    bl = baseline(problem, vlist[0])
    keys = sorted(runs, key=lambda k: (methods.index(k.split(" / ")[0]), vlist.index(k.split(" / ")[1])))
    draw_heldout({k: runs[k] for k in keys}, os.path.join(OUT, problem, f"heldout_{name}.png"),
                 f"Held-out scores by {name.replace('_heldout', '')}: {problem}",
                 "each run's best: filled = held-out mean over unseen seeds, ring = training score", 
                 bl["heldout"]["mean"] if bl else None, keep_order=True)


def report(problem, only=None):
    vs = only or variants(problem)
    md_all = []
    per_var = {}
    for v in vs:
        runs = load(problem, v)
        if not runs:
            continue
        budget = max(r["budget"] for rs in runs.values() for r in rs)
        cv = curves(runs, budget)
        per_var[v] = (runs, cv)
        d = os.path.join(OUT, problem, v)
        tab, rows = table(problem, v, runs)
        open(os.path.join(d, "table.md"), "w").write(tab + "\n")
        md_all.append(f"### {problem}/{v}\n\n{tab}\n")
        with open(os.path.join(d, "curves.csv"), "w") as f:
            ms = order(cv)
            f.write("rollouts," + ",".join(f"{m}_median,{m}_min,{m}_max" for m in ms) + "\n")
            grid = cv[ms[0]][0]
            for i, g in enumerate(grid):
                f.write(f"{g:.0f}," + ",".join(f"{cv[m][1][i]:.6g},{cv[m][2][i]:.6g},{cv[m][3][i]:.6g}" for m in ms) + "\n")
        # small multiples, one panel per method
        ms = [r[0] for r in rows]
        panels = []
        for m in ms:
            ser = [(o, *cv[o], CONTEXT, 1, False) for o in ms if o != m]
            ser.append((m, *cv[m], SERIES[0], 2, True))
            panels.append((f"{m}  (n={len(runs[m])})", ser))
        allv = np.concatenate([np.concatenate(cv[m][1:]) for m in ms])
        allv = allv[np.isfinite(allv)]
        lo_y = float(np.percentile(allv, 2))
        draw_panels(panels, os.path.join(d, "curves.png"), f"Best-so-far vs rollouts: {problem}/{v}",
                    f"{YLABEL.get(problem, 'score')}; median of {max(len(r) for r in runs.values())} seeds (blue), "
                    "min-max across seeds (wash), other methods' medians (gray); ordered by final median", "best",
                    (lo_y, float(np.max(allv))))
        bl = baseline(problem, v)
        draw_heldout(runs, os.path.join(d, "heldout.png"), f"Held-out scores: {problem}/{v}",
                     "each run's best solution: filled = held-out mean (unseen seeds), ring = its training score",
                     bl["heldout"]["mean"] if bl else None)
        print(f"{problem}/{v}: wrote table.md, curves.csv, curves.png, heldout.png")
    for gname, group in GROUPS.get(problem, {}).items():
        # one panel per method present in >= 2 variants, one line per variant
        # (only variants that share an objective: robust-training variants
        # score something else and are compared on held-out seeds instead)
        vlist = [v for v in group if v in per_var]
        if len(vlist) < 2:
            continue
        methods = order({m for v in vlist for m in per_var[v][0]})
        colors = {v: SERIES[i % len(SERIES)] for i, v in enumerate(vlist)}
        panels = []
        for m in methods:
            ser = [(v, *per_var[v][1][m], colors[v], 2, False) for v in vlist if m in per_var[v][1]]
            if len(ser) >= 2:
                panels.append((m, ser))
        if panels:
            allv = np.concatenate([s[3] for p in panels for s in p[1]] + [s[2] for p in panels for s in p[1]])
            allv = allv[np.isfinite(allv)]
            draw_panels(panels, os.path.join(OUT, problem, f"{gname}.png"), f"{gname.capitalize()}: {problem}",
                        f"{YLABEL.get(problem, 'score')}; median best-so-far across seeds, one line per variant", "best",
                        (float(np.percentile(allv, 2)), float(np.max(allv))), cols=min(4, len(panels)),
                        legend=[(v, colors[v]) for v in vlist if any(v == s[0] for p in panels for s in p[1])])
    for name, vl in HELDOUT_GROUPS.get(problem, {}).items():
        compare_heldout(problem, vl, name)
    open(os.path.join(OUT, problem, "tables.md"), "w").write("\n".join(md_all))
    return md_all




def p2_midpoints():
    """Per p2 run: the midpoint actually held (q_stand, averaged over the
    held-out rollouts; rep a runs before the metric existed fall back to
    their posture params), the gains, and held-out survival. Returns markdown."""
    rows = []
    for v in variants("p2"):
        for m, rs in load("p2", v).items():
            for r in rs:
                qs = [h.get("q_stand") for h in r["heldout"]["metrics"] if h.get("q_stand")]
                p = r["params"]
                if qs:
                    q = {k: float(np.mean([x[k] for x in qs])) for k in qs[0]}
                    hip = (q["hip_flexion_r"] + q["hip_flexion_l"]) / 2
                    knee = (q["knee_angle_r"] + q["knee_angle_l"]) / 2
                    ankle = (q["ankle_angle_r"] + q["ankle_angle_l"]) / 2
                    add = (q["hip_adduction_r"] + q["hip_adduction_l"]) / 2
                    src = "held"
                else:
                    hip, knee, ankle, add = p.get("hip", np.nan), p.get("knee", np.nan), p.get("ankle", np.nan), p.get("add", np.nan)
                    src = "cmd"
                n = len(r["heldout"]["scores"])
                rows.append((v, m, r["seed"], hip, knee, ankle, add, src, p.get("kp"), p.get("kd"), p.get("stiff"),
                             p.get("k_ap"), p.get("k_ml"), n - r["heldout"]["fails"], n, r["heldout"]["mean"]))
    lines = ["| rep | method | seed | hip | knee | ankle | add | (from) | kp | kd | stiff | k_ap | k_ml | held-out survived | "
             "held-out mean |", "| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for v, m, s, hip, knee, ankle, add, src, kp, kd, st, kap, kml, ok, n, mean in sorted(rows, key=lambda r: -r[-1]):
        lines.append(f"| {v} | {m} | {s} | {hip:.2f} | {knee:.2f} | {ankle:.2f} | {add:.2f} | {src} | {kp:.1f} | {kd:.2f} | "
                     f"{st:.3f} | {kap:.2f} | {kml:.2f} | {ok}/{n} | {mean:.2f} |")
    return "\n".join(lines)


def export(dest=os.path.join(HERE, "search_results")):
    """Copy the durable results out of the (git-ignored) out/search into
    playground/search_results: every table.md, curves.csv and figure, the
    renders, and runs.json (per run: problem, variant, method, seed, dims,
    budget, best, best params, held-out summary, the best-so-far curve)."""
    import shutil
    runs = []
    for problem in ("p1", "p2", "p3", "p4"):
        root = os.path.join(OUT, problem)
        if not os.path.isdir(root):
            continue
        for f in os.listdir(root):
            if f.endswith((".png", ".md")) or f.startswith("recheck_"):
                os.makedirs(os.path.join(dest, problem), exist_ok=True)
                shutil.copy2(os.path.join(root, f), os.path.join(dest, problem, f))
        for v in variants(problem):
            d = os.path.join(root, v)
            out = os.path.join(dest, problem, v)
            os.makedirs(out, exist_ok=True)
            for f in os.listdir(d):
                if f in ("table.md", "curves.csv", "curves.png", "heldout.png", "baseline.json"):
                    shutil.copy2(os.path.join(d, f), os.path.join(out, f))
            for m, rs in load(problem, v).items():
                for r in rs:
                    runs.append({"problem": problem, "variant": v, "method": m, "seed": r["seed"], "dims": r["dims"],
                                 "budget": r["budget"], "k": r.get("k"), "best": r["best"], "params": r["params"],
                                 "heldout": {k: r["heldout"][k] for k in ("seeds", "scores", "mean", "fails")},
                                 "curve": r["curve"], "wall": r.get("group_wall"), "rollout_s": r.get("rollout_s"),
                                 "opt_s": r.get("opt_s"), "info": r.get("info"), "fingerprint": r.get("fingerprint")})
    json.dump(runs, open(os.path.join(dest, "runs.json"), "w"), separators=(",", ":"))
    print(f"exported {len(runs)} runs to {dest}")


if __name__ == "__main__":
    if sys.argv[1] == "export":
        export()
    else:
        report(sys.argv[1], sys.argv[2:] or None)
