"""compare_official.py NEW_EVALS_JSON: per-seed comparison of an OFFICIAL soccer_single_leg_310_40 evaluation with the earlier official entries (lift 34 / 40, ramp 38 / 40, brake 35 / 40).
Prints the failing seeds of every entry (bal1_300 = 0) with their standing seconds, and the paired fixed / broke counts of the new entry against each."""
import json
import sys

E = "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4/evals/"
old = {"lift": "bal1_300-soccer5-lift-20260929-040311.json", "ramp": "bal1_300-soccer6-i-20260929-044907.json", "brake": "bal1_300-soccer6-p-20260929-083736.json"}
new = json.load(open(sys.argv[1]))
seeds = new["seeds"]


def table(d):
    return {s: (int(bool(r.get("bal1_300"))), r.get("stand_time"), r.get("bal1_raw"), bool(r.get("fallen"))) for s, r in zip(d["seeds"], d["rows"]) if "error" not in r}


T = {"new": table(new)}
for k, f in old.items():
    T[k] = table(json.load(open(E + f)))
for k, t in T.items():
    ok = sum(v[0] for v in t.values())
    bad = sorted((s, round(v[1] or 0, 1)) for s, v in t.items() if not v[0])
    print(f"{k:6s} {ok:2d} / {len(t)}  failing (seed, stand s): {bad}")
for k in old:
    fixed = [s for s in seeds if T["new"][s][0] and not T[k][s][0]]
    broke = [s for s in seeds if not T["new"][s][0] and T[k][s][0]]
    print(f"new vs {k:6s}: fixed {len(fixed)} {fixed}  broke {len(broke)} {broke}")
