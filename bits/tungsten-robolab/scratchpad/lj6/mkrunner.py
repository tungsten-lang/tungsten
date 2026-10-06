"""mkrunner: approach params between F1 (scratchpad/lj4/A2.txt = F1 + SB2) and chain D (scratchpad/lj6/A2D.txt = chain D + SB2), agent L6.
usage: mkrunner.py <out> <alpha>   alpha 0 = F1 (+SB2), alpha 1 = chain D (+SB2): every numeric key both files name is interpolated linearly; a key only F1 names
(the RunGearY mechanisms, absent = neutral for chain D) is scaled by (1 - alpha) [its neutral value is 0 in F1's file, see the diff]; a key only chain D names is scaled by alpha
(none exist); the planner / jump keys j_* are identical in both files. LABELLED beyond-human body, unlimited run-up."""
import sys

def rd(p):
    d, order = {}, []
    for line in open(p):
        t = line.split()
        if line.startswith("#") or len(t) < 2:
            continue
        if t[0] not in d:
            order.append(t[0])
        d[t[0]] = t[1]
    return d, order

out, alpha = sys.argv[1], float(sys.argv[2])
f1, o1 = rd("scratchpad/lj4/A2.txt")
dd, od = rd("scratchpad/lj6/A2D.txt")
res, n_int, n_only1, n_onlyd = [], 0, 0, 0
for k in o1 + [k for k in od if k not in f1]:
    if k in f1 and k in dd:
        try:
            a, b = float(f1[k]), float(dd[k])
            v = repr((1 - alpha) * a + alpha * b) if a != b else f1[k]
            n_int += (a != b)
        except ValueError:
            v = f1[k]
    elif k in f1:
        try:
            v = repr((1 - alpha) * float(f1[k])); n_only1 += 1
        except ValueError:
            v = f1[k]
    else:
        v = repr(alpha * float(dd[k])); n_onlyd += 1
    res.append((k, v))
with open(out, "w") as f:
    f.write("# approach: runner interpolated alpha %.3f between F1 (lj4/A2.txt, 0) and chain D (lj6/A2D.txt, 1), SB2 steering (agent L6)\n" % alpha)
    for k, v in res:
        f.write("%s %s\n" % (k, v))
print("wrote", out, "alpha", alpha, "interpolated", n_int, "F1-only scaled", n_only1, "D-only", n_onlyd)
