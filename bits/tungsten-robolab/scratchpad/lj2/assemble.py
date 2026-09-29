"""Assemble a full long-jump params file for the gear runner (L2).
usage: assemble.py <out> <approach.txt> [<ik.txt> [<il.txt>]] [k=v ...]
  approach.txt  runner keys + planner / chunk j_* keys (e.g. scratchpad/lj2/A2_m250.txt: j_ik 0, j_il 0)
  ik.txt        a robust take-off program (long_jump_limits.py robust output: j_ik 1, ik_*, ik_gap0, ik_end, j_ik_g, ik_from)
  il.txt        a landing program (long_jump_limits.py landing output: j_il 1, il_*)
  k=v           overrides written last (il_tg, il_zl, j_board_shift, ik_gap0, ik_fmin, ...)
Later lines win (arena.read_params keeps the last value of a key); the result lists its sources in the header."""
import sys


def keys(path):
    return [l.split()[0] for l in open(path) if l.strip() and not l.startswith("#") and len(l.split()) >= 2]


def main():
    out = sys.argv[1]
    files = [a for a in sys.argv[2:] if "=" not in a]
    over = [a.split("=", 1) for a in sys.argv[2:] if "=" in a]
    with open(out, "w") as f:
        f.write("# assembled by scratchpad/lj2/assemble.py: " + " + ".join(files) + (" + overrides " + " ".join(f"{k}={v}" for k, v in over) if over else "") + "\n")
        for p in files:
            f.write(f"# ---- {p}\n")
            for line in open(p):
                if line.startswith("#") or len(line.split()) < 2:
                    continue
                f.write(line if line.endswith("\n") else line + "\n")
        if over:
            f.write("# ---- overrides\n")
            for k, v in over:
                f.write(f"{k} {v}\n")
    print("wrote", out, "from", files, "overrides", over)


if __name__ == "__main__":
    main()
