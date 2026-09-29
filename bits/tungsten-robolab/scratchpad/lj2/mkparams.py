"""Merge a runner params file with a jump params file: every line of the runner file, then the jump file's jump
keys only (j_*, ik_*, il_*; its own runner lines are dropped). Later `k=v` overrides replace/add keys.
usage: mkparams.py <runner.txt> <jump.txt> <out.txt> [k=v ...]"""
import sys


def read(path):
    out = {}
    order = []
    for line in open(path):
        t = line.split()
        if len(t) >= 2 and not line.startswith("#"):
            if t[0] not in out:
                order.append(t[0])
            out[t[0]] = t[1]
    return out, order


def main():
    runner, jump, out = sys.argv[1:4]
    over = dict(kv.split("=") for kv in sys.argv[4:])
    r, ro = read(runner)
    j, jo = read(jump)
    keep = [k for k in jo if k.startswith(("j_", "ik_", "il_"))]
    with open(out, "w") as f:
        f.write(f"# runner {runner}; jump keys of {jump}; overrides {over}\n")
        for k in ro:
            if k in over:
                continue
            f.write(f"{k} {r[k]}\n")
        for k in keep:
            if k in over:
                continue
            f.write(f"{k} {j[k]}\n")
        for k, v in over.items():
            f.write(f"{k} {v}\n")
    print("wrote", out, len(ro), "runner keys,", len(keep), "jump keys,", len(over), "overrides")


main()
