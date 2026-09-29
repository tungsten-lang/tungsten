"""Tables for the nanguard trials from the per-seed rows of the three entries (lift, ramp, shc).

usage: analyse_arms.py 310 | hold20 [--table]
Reads the newest scratchpad/blowup/evals/<metric>-<tag>-*.json of each entry (tags soccer5-lift, soccer6-i, soccer6-p).
310: pass counts, NaN events / nudges / other resets, event rate per 1000 start-seconds, the wrap-tangent straddle statistics per start,
     paired comparisons (arena.compare), and the bit-identity check against O's official (unguarded) rows for every start without a NaN event.
hold20: pass counts, paired comparisons, events, per-start table (--table)."""
import glob
import json
import math
import os
import sys

HERE = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, os.path.join(HERE, "playground"))
import arena  # noqa: E402

which = sys.argv[1]
show_table = "--table" in sys.argv
metric = "bal1_300" if which == "310" else "hold20"
trial_name = "soccer_single_leg_310_40_ng" if which == "310" else "soccer_hold20_120_ng"
trial = arena.load_json(arena.TRIALS, {})[trial_name]
ARMS = [("lift", "soccer5-lift"), ("ramp", "soccer6-i"), ("shc", "soccer6-p")]
rows = {}
for arm, tag in ARMS:
    files = sorted(glob.glob(os.path.join(HERE, "scratchpad", "blowup", "evals", f"{metric}-{tag}-*.json")))
    if not files:
        continue
    d = json.load(open(files[-1]))
    rows[arm] = d["rows"]
    assert d["seeds"] == trial["seeds"]
seeds = trial["seeds"]
print(f"trial {trial_name}: {len(seeds)} starts, metric {metric}, {trial['seconds']} s; entries with rows: {list(rows)}")


def score(r):
    return float(r.get(metric) or 0.0) if "error" not in r else 0.0


for arm in rows:
    R = rows[arm]
    sc = [score(r) for r in R]
    ev = sum(r.get("nan_events") or 0 for r in R)
    nud = sum(r.get("nan_nudged") or 0 for r in R)
    oth = sum(r.get("nan_other") or 0 for r in R)
    mir = sum(r.get("nan_mirror") or 0 for r in R)
    secs = sum(float(r.get("time") or 0) for r in R)
    starts_ev = sum(1 for r in R if (r.get("nan_events") or 0) > 0)
    print(f"{arm:5s} pass {int(sum(sc)):3d}/{len(sc)}  NaN events {ev:.0f} (nudged {nud:.0f}, mirror-first {mir:.0f}, other resets {oth:.0f}) in {starts_ev} starts; "
          f"{secs:.0f} start-seconds -> {1000 * ev / secs:.2f} events per 1000 start-seconds; falls {sum(1 for r in R if r.get('fallen'))}")
print()
pairs = [("ramp", "lift"), ("shc", "lift"), ("shc", "ramp")]
for a, b in pairs:
    if a in rows and b in rows:
        sa, sb = [score(r) for r in rows[a]], [score(r) for r in rows[b]]
        cmp = arena.compare(trial, sb, sa)
        fixed = [s for s, x, y in zip(seeds, sa, sb) if x > y]
        broke = [s for s, x, y in zip(seeds, sa, sb) if x < y]
        both_bad = [s for s, x, y in zip(seeds, sa, sb) if x == y == 0]
        print(f"{a} vs {b}: mean paired diff {cmp['mean_diff']:+.4f} p = {cmp['p']:.4f} wins {cmp['wins']}; fixed {len(fixed)} {fixed}; broke {len(broke)} {broke}; both fail {len(both_bad)} {both_bad}")
print()

if which == "310":
    # straddle statistics per start
    for arm in rows:
        R = rows[arm]
        near = [(s, r.get("wrap_r_near3"), r.get("wrap_r_flips"), r.get("nan_events") or 0) for s, r in zip(seeds, R)]
        strad = [x for x in near if x[1] is not None and x[1] > 0.02]
        print(f"{arm:5s} starts with the right rectus femoris within 1e-3 of its wrap tangent in > 2 % of the control steps: {len(strad)} of {len(near)}; "
              f"of them with NaN events: {sum(1 for x in strad if x[3] > 0)}; starts with events that are not among them: {sum(1 for x in near if x[3] > 0 and x not in strad)}")
        print("      " + " ".join(f"{s}:{(n or 0):.2f}/{int(f or 0)}f/{int(e)}ev" for s, n, f, e in sorted(strad, key=lambda x: -x[1])[:14]))
    # bit identity with the official rows
    off = {"lift": "soccer5-lift", "ramp": "soccer6-i", "shc": "soccer6-p"}
    print()
    for arm in rows:
        files = sorted(glob.glob(os.path.join(HERE, "scratchpad", "soccer4", "evals", f"bal1_300-{off[arm]}-*.json")))
        O = json.load(open(files[-1]))["rows"]
        same = diff = 0
        diffs = []
        for s, r, o in zip(seeds, rows[arm], O):
            if "primed_from" in r or (r.get("nan_events") or 0) > 0:
                continue   # primed rows ARE the official rows; starts with events differ by construction
            keys = ("bal1_raw", "bal1_300", "stand_time", "fallen", "t_fall", "bal_l_tot", "bal_r_tot", "pelvis_min", "act_reg", "pain_sum")
            if all(r.get(k) == o.get(k) for k in keys):
                same += 1
            else:
                diff += 1
                diffs.append((s, [(k, r.get(k), o.get(k)) for k in keys if r.get(k) != o.get(k)][:3]))
        nprimed = sum(1 for r in rows[arm] if "primed_from" in r)
        print(f"{arm:5s} {nprimed} rows primed from the official run; of the {len(seeds) - nprimed} real guarded runs, without a NaN event: {same + diff}, identical to the official run in {same}, different in {diff} {diffs[:3]}")

if which == "hold20" or show_table:
    print()
    print("per start: " + "  ".join(arm for arm in rows))
    for i, s in enumerate(seeds):
        cells = []
        for arm in rows:
            r = rows[arm][i]
            ok = score(r) == 1.0
            cells.append(("ok  " if ok else "FAIL") + f" {r.get('t_fall') if r.get('fallen') else '-'} bal1 {r.get('bal1_raw'):.1f} ev {int(r.get('nan_events') or 0)}")
        print(s, " | ".join(cells))
