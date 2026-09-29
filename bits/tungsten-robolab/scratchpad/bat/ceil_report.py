"""Summarise the body-ceiling runs (out/bat_ceiling/r2_*.json): sweet-spot speed at contact, score, peak joint rates to contact.

    .venv/bin/python scratchpad/bat/ceil_report.py [pattern]
"""
import glob, json, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
pat = sys.argv[1] if len(sys.argv) > 1 else "r2_*"
rows = []
for p in sorted(glob.glob(os.path.join(ROOT, "out", "bat_ceiling", pat + ".json"))):
    d = json.load(open(p))
    r = d["result"]
    pk = d["joint_peak_radps_to_contact"]
    rows.append((os.path.basename(p)[:-5], r.get("speed"), round(d["score"], 2), r.get("t"), r.get("fair"), d.get("practised_bat_speed"), pk))
print(f"{'run':<16}{'speed m/s':>10}{'score':>8}{'t contact s':>12}{'fair':>6}{'practised':>10}   pelvis_yaw  spine_rot  l_elbow r_elbow r_wrist_dev (peak rad/s to contact)")
for name, sp, sc, t, fair, pr, pk in rows:
    print(f"{name:<16}{sp:>10}{sc:>8}{t:>12}{str(fair):>6}{pr:>10}   {pk['pelvis_yaw']:>9.1f} {pk['spine_rot']:>10.1f} {pk['l_elbow']:>8.1f} {pk['r_elbow']:>7.1f} {pk['r_wrist_dev']:>11.1f}")
