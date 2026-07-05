"""Harvest the best verified scheme from fleet walker logs.

Scans <outdir>/*.out for `R <u> <v> <w>` dump blocks (each preceded by a
`*** FOUND rank=` or `DONE best=` line), takes the lowest-rank block, exact-
validates it against the <n,m,p> matmul tensor (independent of the searcher's
own probe verify), and writes it as a seed block for the next round.

Usage: python3 harvest.py <outdir> <n> <m> <p> [seed_out.txt]
Exits 1 if no valid scheme found.
"""
import glob
import re
import sys

from metaflip_proto2 import T, recon


def blocks(path):
    """Yield (rank_claim, [(u,v,w)...]) for each dump block in a log."""
    cur, claim = None, None
    for line in open(path):
        if line.startswith("R "):
            _, u, v, w = line.split()
            if cur is not None:
                cur.append((int(u), int(v), int(w)))
        else:
            if cur:
                yield claim, cur
            cur, claim = None, None
            mm = re.search(r"(?:FOUND rank|DONE best)=(\d+)", line)
            if mm:
                cur, claim = [], int(mm.group(1))
    if cur:
        yield claim, cur


def main():
    outdir, n, m, p = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    seed_out = sys.argv[5] if len(sys.argv) > 5 else None
    best = None
    scanned = 0
    for path in sorted(glob.glob(f"{outdir}/*.out")):
        for claim, terms in blocks(path):
            scanned += 1
            if len(terms) != claim:
                print(f"  skip {path}: dump len {len(terms)} != claimed {claim}", file=sys.stderr)
                continue
            if best is None or len(terms) < len(best[0]):
                S = set()
                for t in terms:
                    S.discard(t) if t in S else S.add(t)
                if recon(S, n, m, p) == T(n, m, p):
                    best = (terms, path)
                else:
                    print(f"  INVALID block rank={claim} in {path}", file=sys.stderr)
    if best is None:
        print(f"no valid scheme among {scanned} blocks", file=sys.stderr)
        sys.exit(1)
    terms, path = best
    print(f"BEST rank={len(terms)} <{n},{m},{p}> exact-valid=True from {path}", file=sys.stderr)
    if seed_out:
        with open(seed_out, "w") as f:
            for k, (u, v, w) in enumerate(terms):
                f.write(f"us[{k}] = {u}\n")
            for k, (u, v, w) in enumerate(terms):
                f.write(f"vs[{k}] = {v}\n")
            for k, (u, v, w) in enumerate(terms):
                f.write(f"ws[{k}] = {w}\n")
        print(f"seed written: {seed_out}", file=sys.stderr)


if __name__ == "__main__":
    main()
