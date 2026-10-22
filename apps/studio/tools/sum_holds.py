#!/usr/bin/env python3
"""Sum /usr/bin/time -l blocks of a render log: frames, wall, CPU, peak RSS (largest single process)."""
import re, sys
for p in sys.argv[1:]:
    t = open(p).read()
    real = [float(x) for x in re.findall(r"([\d.]+) real", t)]
    user = [float(x) for x in re.findall(r"([\d.]+) user", t)]
    sys_ = [float(x) for x in re.findall(r"([\d.]+) sys", t)]
    rss = [int(x) for x in re.findall(r"(\d+)  maximum resident set size", t)]
    fr = sum(int(m) for m in re.findall(r"render: (\d+) frames", t))
    seg = re.findall(r"segments_kb (\d+)", t)
    print(f"{p.split('/')[-1]}: {fr} frames in {len(real)} holds, wall {sum(real):.1f} s, CPU {sum(user) + sum(sys_):.1f} s, "
          f"peak RSS {max(rss) / 2**20 if rss else 0:.0f} MB (largest process), {fr / max(sum(real), 1e-9):.1f} fps"
          + (f", segments {int(seg[0]) / 1024:.0f} MB" if seg else ""))
