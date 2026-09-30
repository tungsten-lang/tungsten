"""pushsum.py ROWS.jsonl: survival under the stress-test pushes. tag = arm|push|seed; survive = not fallen and stood to the end of the rollout."""
import collections, json, sys
g = collections.OrderedDict()
rows = {}
for l in open(sys.argv[1]):
    try:
        r = json.loads(l)
    except Exception:
        continue
    rows[r["tag"]] = r
for t, r in rows.items():
    arm, push, seed = t.split("|")
    g.setdefault((arm, push), []).append(r)
print(f"{'arm':6s} {'push':7s} starts survive  falls (seed@stand s)")
for (arm, push), rs in sorted(g.items()):
    ok = [r for r in rs if not r.get("fallen") and (r.get("stand_time") or 0) >= r["seconds"] - 0.11]
    bad = sorted((r["seed"], round(r.get("stand_time") or 0, 1)) for r in rs if r not in ok)
    print(f"{arm:6s} {push:7s} {len(rs):6d} {len(ok):7d}  {bad[:8]}")
