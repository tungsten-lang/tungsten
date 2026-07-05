"""Relay coordinator: watches all CPU-walker dump files and the GPU relay's
own dump file, and keeps a single canonical "current best" file up to date
with whichever source has found the deepest rank so far. This is the only
writer of the canonical file, so there's no write-write race between CPU
walkers (each writes its own file) and the GPU relay (reads the canonical
file read-only, writes its own separate gpu_best file).

Usage: python3 relay_coordinator.py <canonical_path> <naive_rank> <poll_glob> [poll_glob...]
"""
import sys
import time
import glob


def read_scheme(path):
    try:
        with open(path) as f:
            lines = f.read().splitlines()
        rank = int(lines[0])
        return rank, lines[1:1 + rank]
    except Exception:
        return None, None


def main():
    canonical = sys.argv[1]
    naive_rank = int(sys.argv[2])
    globs = sys.argv[3:]

    best_rank = naive_rank
    best_terms = None
    last_written = None

    print(f"coordinator watching {globs} -> {canonical}", flush=True)
    while True:
        for g in globs:
            for path in glob.glob(g):
                rank, terms = read_scheme(path)
                if rank is not None and rank < best_rank:
                    best_rank = rank
                    best_terms = terms
                    print(f"NEW GLOBAL BEST rank={rank} from {path}", flush=True)
        if best_terms is not None and best_rank != last_written:
            with open(canonical, "w") as f:
                f.write(str(best_rank) + "\n")
                f.write("\n".join(best_terms) + "\n")
            last_written = best_rank
            print(f"canonical updated -> rank={best_rank}", flush=True)
        time.sleep(2)


if __name__ == "__main__":
    main()
