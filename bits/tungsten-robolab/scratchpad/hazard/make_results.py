"""make_results.py: write scratchpad/hazard/RESULTS.md, the per-start tables of the round-11 runs, from the rows under out/hazard/ and the arena's per-seed file.

Sections: the OFFICIAL trial (per seed: bal1_raw, stand), the practice screen (per arm), the fresh 20 s check, the fresh 310 s scan (per start), the exposure table.
Everything here is regenerated from the raw rows (out/hazard/rows_*.jsonl, git-ignored) and scratchpad/soccer4/evals/ (tracked)."""
import collections
import glob
import json
import os

import numpy as np

H = "/Users/erik/tungsten/bits/tungsten-robolab/"


def rows_of(*paths):
    d = {}
    for p in paths:
        p = H + p
        if not os.path.exists(p):
            continue
        for l in open(p):
            try:
                r = json.loads(l)
            except Exception:
                continue
            d[r["tag"]] = r
    return d


out = ["# Round 11 (agent Z): per-start tables\n", "Written by `scratchpad/hazard/make_results.py`; entries: **brake** = `params/myo_soccer_single_leg_310_shc.txt` (`bin/challengers/soccer6-p`), **H2b** = `params/hazard/myo_soccer_310_shc_h2b.txt` "
       "(`bin/challengers/soccer7-bh1`: the brake + `bhold 1`, `bh_dknee -0.2`).\n"]

# 1. official trial
ev = sorted(glob.glob(H + "scratchpad/soccer4/evals/bal1_300-soccer7-bh1-*.json"))
if ev:
    d = json.load(open(ev[-1]))
    out.append("## OFFICIAL `soccer_single_leg_310_40` (unmodified `myo_soccer`, unguarded, 310 s, seeds 89100-89139): H2b\n")
    ok = sum(1 for r in d["rows"] if r.get("bal1_300") == 1.0)
    out.append(f"**{ok} / {len(d['rows'])}** hold 300 s (`{os.path.basename(ev[-1])}`); per seed `bal1_raw` (longest one-leg stretch, s) and `stand_time`:\n")
    out.append("| seeds | bal1_raw / stand_time |\n| --- | --- |")
    for i in range(0, len(d["seeds"]), 5):
        out.append("| " + " ".join(str(s) for s in d["seeds"][i:i + 5]) + " | " + "; ".join(f"{r.get('bal1_raw'):.2f} / {r.get('stand_time'):.2f}" for r in d["rows"][i:i + 5]) + " |")
    out.append("")

# 2. practice screen
pr = rows_of("out/hazard/rows_scr1.jsonl", "out/hazard/rows_scr2.jsonl", "out/hazard/rows_scr3.jsonl")
arms = collections.OrderedDict()
for t, r in pr.items():
    arms.setdefault(t.split("|")[0], []).append(r)
out.append("## Practice screen: 20 s, starts 97100-97159, guarded task in count-only mode\n")
out.append("| arm | starts | stand 20 s | falls (seed @ s) | recfem_r within 1e-4 / 1e-3 / 1e-2 of its tangent (substeps) | margin (late median) |\n| --- | --- | --- | --- | --- | --- |")
for a, rs in arms.items():
    if len(rs) < 20:
        continue
    fl = sorted((r["seed"], r.get("stand_time") or 0) for r in rs if (r.get("stand_time") or 0) < r["seconds"] - 0.11)
    e4 = np.mean([r["e4"] for r in rs if r.get("e4") is not None]) * 100
    e3 = np.mean([r["e3"] for r in rs if r.get("e3") is not None]) * 100
    e2 = np.mean([r["e2"] for r in rs if r.get("e2") is not None]) * 100
    mg = np.median([r["pr_mg_late_mean"] for r in rs if r.get("pr_mg_late_mean") is not None and (r.get("stand_time") or 0) >= r["seconds"] - 0.11])
    out.append(f"| {a} | {len(rs)} | {len(rs) - len(fl)} | {'; '.join(f'{s} @ {t:.1f}' for s, t in fl) or '-'} | {e4:.2f} / {e3:.2f} / {e2:.2f} % | {mg:+.3f} |")
out.append("")

# 3. fresh 20 s
va = rows_of("out/hazard/rows_valA.jsonl", "out/hazard/rows_valB0.jsonl")
for arm in ("H2b", "B0"):
    rs = [r for t, r in va.items() if t.startswith(arm + "|")]
    if rs:
        ok = sum(1 for r in rs if r.get("hold20") == 1.0)
        out.append(f"## Fresh 20 s check, seeds 97400-97519 ({arm}): hold20 = 1 in **{ok} / {len(rs)}** starts; NaN events {int(sum(r.get('nan_events') or 0 for r in rs))}\n")

# 4. fresh 310 s scan
fr = rows_of("out/hazard/rows_fresh310.jsonl")
if fr:
    rs = sorted(fr.values(), key=lambda r: r["seed"])
    ok = [r for r in rs if r.get("bal1_300") == 1.0]
    out.append(f"## Fresh 310 s scan (H2b, seeds 97700-97819, count-only guarded task = the official behaviour): {len(ok)} / {len(rs)} hold 300 s so far; NaN events {int(sum(r.get('nan_events') or 0 for r in rs))}\n")
    out.append("| seed | bal1_raw | stand_time | NaN events | recfem_r substeps < 1e-3 | other segments' worst dwell (fraction of steps < 1e-3) |\n| --- | --- | --- | --- | --- | --- |")
    for r in rs:
        out.append(f"| {r['seed']} | {r.get('bal1_raw'):.2f} | {r.get('stand_time'):.2f} | {int(r.get('nan_events') or 0)} | {int(round((r.get('e3') or 0) * (r.get('wrap_r_substeps') or 0)))} | {r.get('seg_oth_near3', 0):.4f} ({r.get('seg_oth_name', '')}) |")
    out.append("")

open(H + "scratchpad/hazard/RESULTS.md", "w").write("\n".join(out) + "\n")
print("scratchpad/hazard/RESULTS.md written,", len(out), "lines")
