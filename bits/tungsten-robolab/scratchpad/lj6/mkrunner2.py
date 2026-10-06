"""mkrunner2: like mkrunner.py but with a separate alpha per gear group (agent L6): keys g3_* (the top gear), g2_* (gear 2: the handover), every other runner key (gear 1, the stand / lean
chunks and the global keys: the START). 0 = F1 (scratchpad/lj4/A2.txt = F1 + SB2), 1 = chain D (scratchpad/lj6/A2D.txt = chain D + SB2); keys only F1 names are scaled by (1 - alpha_group).
usage: mkrunner2.py <out> <alpha_base> <alpha_g2> <alpha_g3>   (j_* planner / jump keys are identical in both files and are copied)"""
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

out = sys.argv[1]
ab, a2, a3 = (float(x) for x in sys.argv[2:5])
f1, o1 = rd("scratchpad/lj4/A2.txt")
dd, od = rd("scratchpad/lj6/A2D.txt")
def grp(k):
    if k.startswith("g3_"): return a3
    if k.startswith("g2_"): return a2
    return ab
res = []
for k in o1 + [k for k in od if k not in f1]:
    a = grp(k)
    if k in f1 and k in dd:
        try:
            x, y = float(f1[k]), float(dd[k])
            v = repr((1 - a) * x + a * y) if x != y else f1[k]
        except ValueError:
            v = f1[k]
    elif k in f1:
        try:
            v = repr((1 - a) * float(f1[k]))
        except ValueError:
            v = f1[k]
    else:
        v = repr(a * float(dd[k]))
    res.append((k, v))
with open(out, "w") as f:
    f.write("# approach: runner group-wise F1 (0) -> chain D (1): base %.2f g2 %.2f g3 %.2f, SB2 steering (agent L6)\n" % (ab, a2, a3))
    for k, v in res:
        f.write("%s %s\n" % (k, v))
print("wrote", out, "alphas base/g2/g3", ab, a2, a3)
