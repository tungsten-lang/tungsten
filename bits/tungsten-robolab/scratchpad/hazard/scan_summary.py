"""scan_summary.py: numbers of the fresh 310 s scan (H2b, seeds 97700-97819, count-only guarded task = official behaviour) for the README and the report."""
import json
import numpy as np
H = "/Users/erik/tungsten/bits/tungsten-robolab/"
rows = {}
for l in open(H + "out/hazard/rows_fresh310.jsonl"):
    try:
        r = json.loads(l)
    except Exception:
        continue
    rows[r["tag"]] = r
rs = sorted(rows.values(), key=lambda r: r["seed"])
ok = [r for r in rs if r.get("bal1_300") == 1.0]
ss = sum(r["seconds"] for r in rs)
print(f"{len(rs)} starts ({rs[0]['seed']}..{rs[-1]['seed']}), {len(ok)} hold 300 s, {len(rs) - len(ok)} fall(s): {[ (r['seed'], r.get('stand_time')) for r in rs if r.get('bal1_300') != 1.0]}; NaN events {int(sum(r.get('nan_events') or 0 for r in rs))} in {ss:.0f} start-seconds")
print("bal1_raw min %.2f mean %.2f max %.2f" % (min(r['bal1_raw'] for r in rs), np.mean([r['bal1_raw'] for r in rs]), max(r['bal1_raw'] for r in rs)))
e4 = sum(round((r.get("e4") or 0) * (r.get("wrap_r_substeps") or 0)) for r in rs); e3 = sum(round((r.get("e3") or 0) * (r.get("wrap_r_substeps") or 0)) for r in rs)
print(f"recfem_r substeps within 1e-4 / 1e-3 of its tangent: {e4} / {e3} (of {sum(r.get('wrap_r_substeps') or 0 for r in rs):.0f}); tangent crossings of recfem_r {int(sum(r.get('seg_flips_rf') or 0 for r in rs))}")
new = [r for r in rs if r.get("sub_sliver_oth") is not None]
print(f"substep all-segment watch on {len(new)} starts ({sum(r['seconds'] - 3 for r in new):.0f} start-seconds): sliver states recfem_r {sum(r['sub_sliver_rf'] for r in new)}, other segments {sum(r['sub_sliver_oth'] for r in new)}; other segments' substeps within 1e-4 / 1e-3: {sum(r['sub_e4_oth'] for r in new)} / {sum(r['sub_e3_oth'] for r in new)}; expected NaN from crossings (lower bound) {sum(r['seg_xnan'] for r in new):.4f}")
d = sorted(((r.get('seg_oth_near3', 0), r['seed'], r.get('seg_oth_name', '')) for r in rs), reverse=True)[:5]
print("worst control-step dwell within 1e-3 of a non-recfem_r segment (fraction of steps, seed, segment):", [(round(a, 4), s, n.split('@')[0]) for a, s, n in d])
print("all-segment tangent crossings per start: mean %.1f (recfem_r %.1f)" % (np.mean([(r.get('seg_flips_rf') or 0) + (r.get('seg_flips_oth') or 0) for r in rs]), np.mean([r.get('seg_flips_rf') or 0 for r in rs])))
