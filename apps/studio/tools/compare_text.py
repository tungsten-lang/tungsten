#!/usr/bin/env python3
"""SRT and chapters regenerated from the resolved timeline, against the shipped render/Archimedes_Eratosthenes.srt and
youtube/youtube.md's chapter list.   python3 compare_text.py <episode dir>"""
import json, pathlib, re, sys

EP = pathlib.Path(sys.argv[1]).expanduser()
B = EP / "studio/build/full"


def srt(p):
    cues = []
    for blk in p.read_text().strip().split("\n\n"):
        ln = blk.strip().split("\n")
        m = re.match(r"(\d+):(\d+):(\d+),(\d+) --> (\d+):(\d+):(\d+),(\d+)", ln[1])
        g = [int(x) for x in m.groups()]
        a = ((g[0] * 60 + g[1]) * 60 + g[2]) * 1000 + g[3]
        b = ((g[4] * 60 + g[5]) * 60 + g[6]) * 1000 + g[7]
        cues.append((a, b, "\n".join(ln[2:])))
    return cues


old, new = srt(EP / "render/Archimedes_Eratosthenes.srt"), srt(B / "captions.srt")
print(f"SRT: shipped {len(old)} cues, regenerated {len(new)} cues")
dt = [(abs(n[0] - o[0]), abs(n[1] - o[1])) for o, n in zip(old, new)]
text_diff = [i for i, (o, n) in enumerate(zip(old, new)) if o[2] != n[2]]
hist = {}
for a, b in dt:
    for d in (a, b):
        hist[d] = hist.get(d, 0) + 1
print("  |time difference| ms -> count over all cue edges:", dict(sorted(hist.items())))
print(f"  cues with different text: {len(text_diff)}", [i + 1 for i in text_diff][:20])
for i in text_diff[:5]:
    print(f"   #{i + 1}: shipped {old[i][2]!r}\n         new     {new[i][2]!r}")
off = [(i + 1, o, n) for i, (o, n) in enumerate(zip(old, new)) if abs(n[0] - o[0]) > 1 or abs(n[1] - o[1]) > 1]
print(f"  cues off by more than 1 ms: {len(off)}")
for i, o, n in off[:8]:
    print(f"   #{i}: shipped {o[0]}-{o[1]}  new {n[0]}-{n[1]}")

yt = (EP / "youtube/youtube.md").read_text().split("Chapters:", 1)[1]
old_ch = []
for ln in yt.splitlines():
    m = re.match(r"^(\d+):(\d\d) (.+)$", ln.strip())
    if m:
        old_ch.append((int(m.group(1)) * 60 + int(m.group(2)), m.group(3)))
    elif old_ch and not ln.strip():
        break
new_ch = []
for ln in (B / "chapters.txt").read_text().splitlines():
    m = re.match(r"^(\d+):(\d\d) (.+)$", ln.strip())
    new_ch.append((int(m.group(1)) * 60 + int(m.group(2)), m.group(3)))
print(f"chapters: shipped {len(old_ch)}, regenerated {len(new_ch)}")
moved = [(o, n) for o, n in zip(old_ch, new_ch) if o != n]
print(f"  chapters that differ: {len(moved)}")
for o, n in moved:
    print(f"   {o[0] // 60}:{o[0] % 60:02d} {o[1]}  ->  {n[0] // 60}:{n[0] % 60:02d} {n[1]}")
json.dump({"srt_cues": [len(old), len(new)], "srt_time_hist_ms": hist, "srt_text_diff": len(text_diff),
           "srt_off_gt_1ms": len(off), "chapters": [len(old_ch), len(new_ch)], "chapters_moved": moved},
          open(EP / "studio/reports/text.json", "w"), indent=1)
