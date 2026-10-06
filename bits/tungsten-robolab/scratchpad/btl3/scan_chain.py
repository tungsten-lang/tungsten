"""Sequential scan of param overrides with chain.py, one summary line per config (appended to a result file).

    OMP_NUM_THREADS=1 nohup nice -n 10 .venv/bin/python scratchpad/btl3/scan_chain.py ctl params s0 s1 secs workers tag "ov1;ov2;..." > out/btl3/scan_<tag>.log &

Each override is a comma list k=v,k=v ("" = none). Prints  tag | override | mean | n>=1 >=2 >=3 >=4 | per-pass ok/n.
The per-start streaks are kept in out/btl3/scan_<tag>_<i>.streaks (one number per line, seed order) for paired tests.
"""
import re
import subprocess
import sys

import numpy as np


def main():
    ctl, params, s0, s1, secs, workers, tag, ovs = sys.argv[1:9]
    for i, ov in enumerate(ovs.split(";")):
        out = subprocess.run([sys.executable, "scratchpad/btl2/chain.py", ctl, params, s0, s1, secs, ov, workers],
                             capture_output=True, text=True).stdout
        starts = re.findall(r"^(\d+) streak (\d+)", out, flags=re.M)
        streaks = [int(b) for a, b in starts]
        with open(f"out/btl3/scan_{tag}_{i}.streaks", "w") as f:
            f.write("\n".join(f"{a} {b}" for a, b in starts) + "\n")
        passes = re.findall(r"^pass (\d): n (\d+) ok (\d+)", out, flags=re.M)
        s = "  ".join(f"p{k}:{ok}/{n}" for k, n, ok in passes[:4])
        arr = np.array(streaks)
        print(f"{tag} | {ov or '-'} | mean {arr.mean():.3f} | >=1 {int((arr >= 1).sum())} >=2 {int((arr >= 2).sum())} >=3 {int((arr >= 3).sum())} >=4 {int((arr >= 4).sum())} | {s}", flush=True)


if __name__ == "__main__":
    main()
