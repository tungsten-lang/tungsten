"""summ.py ROWS.jsonl [--seeds] : per config (tag before the last '|') over its starts: falls, late margin mean/sd/max, e4, e3, posture means"""
import json, sys, collections
import numpy as np
rows = {}
for l in open(sys.argv[1]):
    try:
        r = json.loads(l)
    except Exception:
        continue
    rows[r["tag"]] = r   # a tag run twice keeps the last row
rows = list(rows.values())
g = collections.OrderedDict()
for r in rows:
    if "error" in r:
        print("ERROR", r["tag"], r["error"][:100]); continue
    g.setdefault(r["tag"].rsplit("|", 1)[0], []).append(r)
print(f"{'config':26s} n fall | mg_late_mean  mg_sd  mg_max(med) mg_min(med) | e4%   e3%  | hf_r    ha_r    hr_r    kn_r    an_r  | stand")
for k, rs in g.items():
    ok = [r for r in rs if r.get("pr_n")]
    fall = sum(1 for r in rs if r.get("fallen") or (r.get("stand_time") or 0) < r["seconds"] - 0.1)
    if not ok:
        print(f"{k:26s} {len(rs)} {fall} | (no probe rows)"); continue
    f = lambda key: np.array([r[key] for r in ok])
    st = [r for r in ok if not (r.get("fallen") or (r.get("stand_time") or 0) < r["seconds"] - 0.1)]
    if not st:
        print(f"{k:26s} {len(rs):2d} {fall:2d} | all fell"); continue
    h = lambda key: np.array([r[key] for r in st])
    print(f"{k:26s} {len(rs):2d} {fall:2d}  | {np.median(h('pr_mg_late_mean')):+.2e} {np.median(h('pr_mg_late_std')):.1e} {np.median(h('pr_mg_late_max')):+.2e} {np.median(h('pr_mg_late_min')):+.2e} | "
          f"{100*h('e4').mean():5.2f} {100*h('e3').mean():5.2f} | {np.median(h('pr_hip_flexion_r_late')):+.3f} {np.median(h('pr_hip_adduction_r_late')):+.3f} {np.median(h('pr_hip_rotation_r_late')):+.3f} {np.median(h('pr_knee_angle_r_late')):+.4f} {np.median(h('pr_ankle_angle_r_late')):+.3f} | {np.mean([r['stand_time'] for r in rs]):.1f}")
