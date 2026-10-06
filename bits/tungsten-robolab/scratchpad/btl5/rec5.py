"""Record closed-loop starts of a controller + params for the replay tools (round 5; snapshots from 1.35 s to t_hi, one pickle per start).

    OMP_NUM_THREADS=1 nohup nice -n 10 .venv/bin/python scratchpad/btl5/rec5.py ctl params s0 s1 out_dir [workers] [t_hi] [t_end] > out/btl5/rec_x.log 2>&1 &

Uses rlib.record_start (btl4): skips starts whose pickle exists.
"""
import sys

sys.path.insert(0, "scratchpad/btl4")
from multiprocessing import Pool  # noqa: E402

import rlib  # noqa: E402


def main():
    ctl, pfile, s0, s1, out_dir = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
    workers = int(sys.argv[6]) if len(sys.argv) > 6 else 6
    t_hi = float(sys.argv[7]) if len(sys.argv) > 7 else 3.95
    t_end = float(sys.argv[8]) if len(sys.argv) > 8 else 4.9
    with Pool(workers) as p:
        for s in p.imap_unordered(rlib.record_start, [(sd, pfile, ctl, out_dir, t_hi, t_end) for sd in range(s0, s1)]):
            print("done", s, flush=True)
    print("ALL DONE", flush=True)


if __name__ == "__main__":
    main()
