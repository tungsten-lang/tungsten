"""Stance-limited ceiling (Weyand et al. 2000's framework): per speed, the best penalised stance budget
(capacity_score ~ tc + 2 taer less penalties) over every probe run of a label prefix; the ceiling is where that
best budget falls to a human swing time t_sw (0.35 s: Weyand 2000 0.373 +- 0.03, sprinters 0.33-0.36).
usage: budget_ceiling.py LABEL_PREFIX [LABEL_PREFIX ...]"""
import glob, json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
for pre in sys.argv[1:]:
    best = {}
    for f in glob.glob(os.path.join(ROOT, "out", "sprint_limits", f"probe_{pre}_s*_v*_speeds.json")):
        for r in json.load(open(f))["runs"]:
            w = r["weyand"]
            if w.get("taer_sym", 0) <= 0:
                continue
            cap = w.get("capacity_score", w.get("swing_budget"))
            if cap is None:
                continue
            v = r["v"]
            if v not in best or cap > best[v][0]:
                best[v] = (cap, w)
    vs = sorted(best)
    out = []
    for tsw in (0.33, 0.35, 0.37):
        ceil = None
        for a, b in zip(vs, vs[1:]):
            if best[a][0] >= tsw > best[b][0]:
                ceil = a + (b - a) * (best[a][0] - tsw) / (best[a][0] - best[b][0])
        if ceil is None and vs and best[vs[-1]][0] >= tsw:
            ceil = f">={vs[-1]}"
        out.append(f"t_sw {tsw}: {ceil if isinstance(ceil, str) else (round(ceil, 2) if ceil else None)}")
    near = [v for v in vs if best[v][0] >= 0.35]
    w = best[max(near)][1] if near else None
    extra = "" if w is None else f" | at {w['v']}: tc {w['tc']} aer {w['taer_sym']} step {round(w['v'] / w['f_step'], 2)} m f {w['f_step']} Favg {w['Favg_W_sym']} peak {w['peak_grf_W']}"
    print(f"{pre}: " + "; ".join(out) + "  | budgets " + " ".join(f"{v:g}:{best[v][0]:.3f}" for v in vs) + extra)
