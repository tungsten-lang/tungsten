"""results_table: print the v4 sprint arena history and champions as markdown rows."""
import json
ceil = {"sprint_top_speed_v4": 8.2, "sprint_top_speed_v4_p95": 10.45, "sprint_top_speed_v4_elite2": 9.28}
rows = []
for l in open("playground/arena/history.jsonl"):
    r = json.loads(l)
    if r.get("trial") in ceil:
        rows.append(r)
c = json.load(open("playground/arena/champions.json"))
print("| time | trial | controller / params | survivors | peak 1 s (survivors) | share | verdict |")
for r in rows:
    tr = r["trial"]; sc = None
    # scores are only kept in the history entry for promoted/lost ones as 'summary'; recompute from the note if absent
    s = r["summary"]; mean = s["mean"]
    vc = r.get("vs_champion", {})
    print(f"| {r['time'][5:16]} | {tr} | {r.get('params','')} | mean {mean:.4g} | p {vc.get('p')} | {r['result']} |")
print()
for tr in ceil:
    ch = c[tr]; sc = ch["scores"]; ok = [x for x in sc if x > -1e8]
    m = sum(ok) / len(ok)
    print(f"CHAMPION {tr}: {ch['params']} {ch['frozen_controller']} survivors {len(ok)}/12 mean {m:.3f} share {100 * m / ceil[tr]:.1f} %")
