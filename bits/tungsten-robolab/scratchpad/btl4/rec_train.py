"""Record closed-loop starts (baseline controller) for the replay tools.

    OMP_NUM_THREADS=1 nice -n 10 .venv/bin/python scratchpad/btl4/rec_train.py ctl params s0 s1 out_dir [workers]
"""
import sys
sys.path.insert(0, "scratchpad/btl4")
from multiprocessing import Pool
import rlib


def main():
    ctl, pfile, s0, s1, out_dir = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
    workers = int(sys.argv[6]) if len(sys.argv) > 6 else 6
    with Pool(workers) as p:
        for s in p.imap_unordered(rlib.record_start, [(sd, pfile, ctl, out_dir) for sd in range(s0, s1)]):
            print("done", s, flush=True)


if __name__ == "__main__":
    main()
