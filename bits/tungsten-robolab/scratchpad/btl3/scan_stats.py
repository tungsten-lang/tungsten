"""Like scan_chain.py but runs stage_stats.py: per config the streak mean and, per pass, ok count and arrival mean / sd.

    OMP_NUM_THREADS=1 nohup nice -n 10 .venv/bin/python scratchpad/btl3/scan_stats.py ctl params s0 s1 secs workers tag "ov1;ov2;..." > out/btl3/scanst_<tag>.log &
"""
import re
import subprocess
import sys

import numpy as np

sys.path.insert(0, "scratchpad/btl2")
from common import load, parse_over, write_params  # noqa: E402


def main():
    ctl, params, s0, s1, secs, workers, tag, ovs = sys.argv[1:9]
    base = load(params)
    for i, ov in enumerate(ovs.split(";")):
        p = dict(base)
        p.update(parse_over(ov))
        fn = f"out/btl3/tmp_params_{tag}_{i}.txt"
        write_params(fn, p, f"{params} + {ov}")
        out = subprocess.run([sys.executable, "scratchpad/btl2/stage_stats.py", ctl, fn, s0, s1, secs, workers], capture_output=True, text=True).stdout
        m = re.search(r"mean ([\d.]+)", out)
        rows = re.findall(r"^pass (\d): n (\d+) gate (\d+) body0 (\d+) ok\(task\) (\d+) \| bgd [\d.]+ apex [\d.]+ \| arrival mean \(([+-][\d.]+),([+-][\d.]+)\) sd \(([\d.]+),([\d.]+)\)", out, flags=re.M)
        s = "  ".join(f"p{k}: ok {ok}/{n} arr ({mx},{my}) sd ({sx},{sy})" for k, n, g, b, ok, mx, my, sx, sy in rows[:3])
        print(f"{tag} | {ov or '-'} | mean {m.group(1) if m else '?'} | {s}", flush=True)


if __name__ == "__main__":
    main()
