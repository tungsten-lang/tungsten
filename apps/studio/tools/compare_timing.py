#!/usr/bin/env python3
"""Timing diff: the resolved timeline (integer frames) against the shipped film's float timeline.

    python3 apps/studio/tools/compare_timing.py <episode dir> [resolved.json]

The legacy renderer (tools/render.py) showed shot i from the first frame fi with fi / 24 >= start_i (float), i.e. it
rounded every cut UP to the next frame; the resolver snaps to the NEAREST frame (round half up). Lists every cut
whose frame changes, the narration placements (ms), and writes studio/reports/timing.json."""
import json, math, pathlib, sys

EP = pathlib.Path(sys.argv[1]).expanduser()
R = json.load(open(sys.argv[2] if len(sys.argv) > 2 else EP / "studio/build/full/timeline.resolved.json"))
T = json.load(open(EP / "render/timeline.json"))
FPS = 24


def legacy_frame(start):
    f = int(math.floor(start * FPS))
    while f / FPS < start:
        f += 1
    while f > 0 and (f - 1) / FPS >= start:
        f -= 1
    return f


v1 = R["tracks"][0]["items"]
assert [i["id"] for i in v1] == [s["id"] for s in T["shots"]], "shot order differs"
rows, moved = [], []
for it, sh in zip(v1, T["shots"]):
    lf = legacy_frame(sh["start"])
    exact_ms = it["t0_ms"]
    d_ms = exact_ms - round(sh["start"] * 1000)
    row = {"id": it["id"], "legacy_start_s": sh["start"], "exact_ms": exact_ms, "anchor_drift_ms": d_ms,
           "legacy_frame": lf, "frame": it["f0"], "delta": it["f0"] - lf, "exact_frame": exact_ms * FPS / 1000}
    rows.append(row)
    if row["delta"]:
        moved.append(row)
nf_legacy = int(round(T["total"] * FPS))
vo = R["tracks"][2]["items"]
vo_rows = []
for a, v in zip(vo, T["vo"]):
    vo_rows.append({"id": a["id"], "file": v["file"], "legacy_at_ms": round(v["at"] * 1000), "s0_ms": a["s0"] / 48,
                    "delta_ms": a["s0"] / 48 - round(v["at"] * 1000)})
bad_vo = [r for r in vo_rows if abs(r["delta_ms"]) > 1]
out = {"frames": R["frames"], "legacy_frames": nf_legacy, "cuts": rows, "moved": moved, "vo": vo_rows}
(EP / "studio/reports").mkdir(parents=True, exist_ok=True)
json.dump(out, open(EP / "studio/reports/timing.json", "w"), indent=1)
print(f"frames: resolved {R['frames']}, legacy {nf_legacy}")
print(f"anchor drift (resolved exact ms - legacy ms): max |{max(abs(r['anchor_drift_ms']) for r in rows)}| ms")
print(f"narration placements: {len(vo_rows)} lines, {len(bad_vo)} differ by > 1 ms "
      f"(max |{max(abs(r['delta_ms']) for r in vo_rows)}| ms)")
print(f"{len(moved)} of {len(rows)} cuts move under round-half-up snapping (legacy rounded up):")
for r in moved:
    print(f"  {r['id']:>16}  {r['legacy_start_s']:9.3f}s  exact frame {r['exact_frame']:10.3f}  "
          f"legacy {r['legacy_frame']:6d} -> {r['frame']:6d}  ({r['delta']:+d})")
