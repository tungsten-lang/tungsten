"""Write scratchpad/blowup/RESULTS.md: per-start results of the three entries (lift, ramp, shc = brake) on the two nanguard trials, with the official
(unguarded) result beside the guarded one for the 310 s trial, plus the pairwise tests. Reads scratchpad/blowup/evals/*.json (newest per entry)."""
import glob
import json
import os
import sys

HERE = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, os.path.join(HERE, "playground"))
import arena  # noqa: E402

TR = arena.load_json(arena.TRIALS, {})
ARMS = [("lift", "soccer5-lift"), ("ramp", "soccer6-i"), ("brake", "soccer6-p")]


def newest(metric, tag, n_seeds=None):
    """newest arena rows file of the entry; n_seeds tells the 40-start 310 s trial from the 120-start one (same metric and controller names)"""
    files = sorted(glob.glob(os.path.join(HERE, "scratchpad", "blowup", "evals", f"{metric}-{tag}-*.json")))
    for f in reversed(files):
        d = json.load(open(f))
        if n_seeds is None or len(d["seeds"]) == n_seeds:
            return d
    return None


def official(tag):
    files = sorted(glob.glob(os.path.join(HERE, "scratchpad", "soccer4", "evals", f"bal1_300-{tag}-*.json")))
    return json.load(open(files[-1])) if files else None


out = []
P = out.append
P("# Nanguard trials: per-start results\n")
P("Written by `scratchpad/blowup/make_tables.py` from the arena rows in `scratchpad/blowup/evals/`. Entries: **lift** = round-5 lift (`bin/challengers/soccer5-lift`, "
  "`params/myo_soccer_single_leg_310_lift.txt`), **ramp** = round-6 set ramp (`soccer6-i`, `..._ramp.txt`), **brake** = ramp + shift capture-point brake (`soccer6-p`, `..._shc.txt`).\n")

# ---- 310_40_ng
name = "soccer_single_leg_310_40_ng"
t = TR[name]
rows = {arm: newest("bal1_300", tag, 40) for arm, tag in ARMS}
off = {arm: official(tag) for arm, tag in ARMS}
if all(rows.values()):
    P(f"## {name}: 40 starts (seeds 89100-89139), 310 s, bal1_300 (1 = the longest one-leg stretch reaches 300 s)\n")
    P("| entry | official (unguarded) | guarded | NaN events (guarded re-runs) |")
    P("| --- | --- | --- | --- |")
    for arm, tag in ARMS:
        o = sum(1 for r in off[arm]["rows"] if r.get("bal1_300") == 1.0)
        g = sum(1 for r in rows[arm]["rows"] if r.get("bal1_300") == 1.0)
        ev = sum(int(r.get("nan_events") or 0) for r in rows[arm]["rows"])
        P(f"| {arm} | {o} / 40 | {g} / 40 | {ev} |")
    P("")
    P("Starts where any entry differs between the official and the guarded run, or fails (seed: official -> guarded; `fall` = seconds standing before the fall; `nan` = events, first at t, tendon):\n")
    P("| seed | " + " | ".join(arm for arm, _ in ARMS) + " |")
    P("| --- | " + " | ".join("---" for _ in ARMS) + " |")
    for i, s in enumerate(t["seeds"]):
        cells, interesting = [], False
        for arm, _ in ARMS:
            o, g = off[arm]["rows"][i], rows[arm]["rows"][i]
            po, pg = o.get("bal1_300") == 1.0, g.get("bal1_300") == 1.0
            txt = ("pass" if po else f"FAIL (fall {o.get('stand_time')})") + " -> " + ("pass" if pg else f"FAIL (fall {g.get('stand_time')})")
            if (g.get("nan_events") or 0) > 0:
                txt += f"; nan {int(g['nan_events'])} @ {g.get('nan_first_t')} {g.get('nan_tendons')}"
            if po != pg or not pg or (g.get("nan_events") or 0) > 0:
                interesting = True
            cells.append(txt)
        if interesting:
            P(f"| {s} | " + " | ".join(cells) + " |")
    P("")

# ---- hold20
name = "soccer_hold20_120_ng"
t = TR[name]
rows = {arm: newest("hold20", tag, 120) for arm, tag in ARMS}
if any(rows.values()):
    have = [arm for arm, _ in ARMS if rows[arm]]
    P(f"## {name}: 120 fresh starts (seeds 96000-96119), 20 s, hold20 (1 = standing since the start and on one leg for the last 15 s)\n")
    P("| entry | hold20 | falls | NaN events (nudged) | mean bal1_raw of the passes |")
    P("| --- | --- | --- | --- | --- |")
    for arm in have:
        R = rows[arm]["rows"]
        ok = [r for r in R if r.get("hold20") == 1.0]
        P(f"| {arm} | {len(ok)} / {len(R)} | {sum(1 for r in R if r.get('fallen'))} | {sum(int(r.get('nan_events') or 0) for r in R)} | {sum(r['bal1_raw'] for r in ok) / max(len(ok), 1):.2f} |")
    P("")
    pairs = [("ramp", "lift"), ("brake", "lift"), ("brake", "ramp")]
    for a, b in pairs:
        if a in have and b in have:
            sa = [float(r.get("hold20") or 0) for r in rows[a]["rows"]]
            sb = [float(r.get("hold20") or 0) for r in rows[b]["rows"]]
            cmp = arena.compare(t, sb, sa)
            fixed = [s for s, x, y in zip(t["seeds"], sa, sb) if x > y]
            broke = [s for s, x, y in zip(t["seeds"], sa, sb) if x < y]
            P(f"- {a} vs {b}: mean paired diff {cmp['mean_diff']:+.4f}, p = {cmp['p']:.4f}; fixed {len(fixed)}, broke {len(broke)}" + (f" (broke {broke})" if broke and len(broke) < 8 else ""))
    P("")
    P("Per start (`ok` = hold20; a fall shows the seconds standing before it; `nan` = guard events):\n")
    P("| seed | " + " | ".join(have) + " |")
    P("| --- | " + " | ".join("---" for _ in have) + " |")
    for i, s in enumerate(t["seeds"]):
        cells = []
        for arm in have:
            r = rows[arm]["rows"][i]
            if r.get("hold20") == 1.0:
                c = f"ok ({r['bal1_raw']:.1f})"
            else:
                c = f"FAIL (fall at {r.get('stand_time')} s standing)" if r.get("fallen") else f"FAIL (bal1 {r.get('bal1_raw')})"
            if (r.get("nan_events") or 0) > 0:
                c += f" nan {int(r['nan_events'])} @ {r.get('nan_first_t')} {r.get('nan_tendons')}"
            cells.append(c)
        P(f"| {s} | " + " | ".join(cells) + " |")
    P("")
# ---- 310_120
name = "soccer_single_leg_310_120_ng"
if name in TR:
    t = TR[name]
    rows = {arm: newest("bal1_300", tag, 120) for arm, tag in ARMS}
    have = [arm for arm, _ in ARMS if rows[arm]]
    if have:
        P(f"## {name}: the five-minute hold on the 120 fresh starts (seeds 96000-96119), 310 s, bal1_300\n")
        P("| entry | holds 300 s | falls | NaN events (nudged) |")
        P("| --- | --- | --- | --- |")
        for arm in have:
            R = rows[arm]["rows"]
            P(f"| {arm} | {sum(1 for r in R if r.get('bal1_300') == 1.0)} / {len(R)} | {sum(1 for r in R if r.get('fallen'))} | {sum(int(r.get('nan_events') or 0) for r in R)} |")
        P("")
        P("Starts that do not hold 300 s or had NaN events:\n")
        P("| seed | " + " | ".join(have) + " |")
        P("| --- | " + " | ".join("---" for _ in have) + " |")
        for i, s_ in enumerate(t["seeds"]):
            cells, show = [], False
            for arm in have:
                r = rows[arm]["rows"][i]
                ok = r.get("bal1_300") == 1.0
                c = "ok" if ok else f"FAIL (fall at {r.get('stand_time')} s standing, bal1 {r.get('bal1_raw')})"
                if (r.get("nan_events") or 0) > 0:
                    c += f" nan {int(r['nan_events'])} @ {r.get('nan_first_t')} {r.get('nan_tendons')}"
                if not ok or (r.get("nan_events") or 0) > 0:
                    show = True
                cells.append(c)
            if show:
                P(f"| {s_} | " + " | ".join(cells) + " |")
        P("")
open(os.path.join(HERE, "scratchpad", "blowup", "RESULTS.md"), "w").write("\n".join(out))
print("wrote scratchpad/blowup/RESULTS.md", len(out), "lines")
