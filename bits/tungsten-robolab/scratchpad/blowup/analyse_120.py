"""SUPPLEMENTARY SCAN: the five-minute hold of the brake (ramp + shift brake, soccer6-p) on the fresh hold20 starts (seeds 96000-96119) at 310 s under the guard, from the rollout cache
(prefill_310_120.py; 69 of the 120 starts finished, the trial soccer_single_leg_310_120_ng was not seeded): pass count, falls (early = already failing hold20, late = after 20 s), NaN events,
telemetry closure. usage: analyse_120.py"""
import glob, json, math, os, sys
HERE = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, os.path.join(HERE, "playground")); sys.path.insert(0, os.path.join(HERE, "scratchpad", "blowup"))
import arena, arena_ng

trial = dict(arena.load_json(arena.TRIALS, {})["soccer_single_leg_310_40_ng"])   # same env, seconds and python: the cache key does not depend on the trial name or its seeds
trial["seeds"] = list(range(96000, 96120))
params = arena.read_params(os.path.join(HERE, "params/myo_soccer_single_leg_310_shc.txt")); ctl = os.path.join(HERE, "bin/challengers/soccer6-p")
rows = {}
for s in trial["seeds"]:
    p = os.path.join(arena_ng.CACHE, arena_ng.rollout_key(trial, params, ctl, "myo_soccer_ng", s) + ".json")
    if os.path.exists(p):
        rows[s] = json.load(open(p))
h20 = json.load(open(sorted(glob.glob(os.path.join(HERE, "scratchpad", "blowup", "evals", "hold20-soccer6-p-*.json")))[-1]))
h20 = {s: r for s, r in zip(h20["seeds"], h20["rows"])}
n = len(rows)
ok = [s for s, r in rows.items() if r.get("bal1_300") == 1.0]
print(f"{n} of {len(trial['seeds'])} starts done (the scan was stopped: {sorted(rows)[0]}..{sorted(rows)[-1]}); hold 300 s: {len(ok)} / {n}")
for s, r in sorted(rows.items()):
    if r.get("bal1_300") != 1.0:
        print(f"  FAIL {s}: standing {r.get('stand_time')} s, bal1 {r.get('bal1_raw')}, fell {r.get('fallen')} (hold20 at 20 s: {'ok' if h20[s].get('hold20') == 1.0 else 'FAIL'}); events {r.get('nan_events')}")
late = [s for s, r in rows.items() if r.get("bal1_300") != 1.0 and h20[s].get("hold20") == 1.0]
print(f"late failures (hold20 ok, fail before 300 s): {len(late)} {late}")
secs = sum(float(r.get("time") or 0) for r in rows.values())
ev = sum(int(r.get("nan_events") or 0) for r in rows.values())
surv = sum(int(r.get("wrap_r_visits") or 0) for r in rows.values())
omd = [float(x) for r in rows.values() for x in (r.get("nan_omd") or "").split(";") if x]
exp = sum(float(r.get("nan_expected") or 0) for r in rows.values())
print(f"NaN events {ev} in {sum(1 for r in rows.values() if (r.get('nan_events') or 0) > 0)} starts, {secs:.0f} start-seconds = {1000 * ev / max(secs, 1):.2f} per 1000; tendons {sorted({t for r in rows.values() for t in (r.get('nan_tendons') or '').split(',') if t})}; other resets {sum(int(r.get('nan_other') or 0) for r in rows.values())}")
print(f"recfem_r sliver states: survived {surv} + NaN {len(omd)}; expected NaN from the table {exp:.2f}; exact 1-dot of the events {' '.join(f'{x:.1e}' for x in sorted(omd))}")
print("events by start:", "; ".join(f"{s} x{int(r['nan_events'])} @{r.get('nan_first_t')} {r.get('nan_tendons')}" for s, r in sorted(rows.items()) if (r.get('nan_events') or 0) > 0))
