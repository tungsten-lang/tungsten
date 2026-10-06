"""avgprog: the key-wise average of take-off program files (same keys; numeric values averaged, other lines from the first file). usage: avgprog.py <out> <prog1> <prog2> ... (agent L6)"""
import sys
out, files = sys.argv[1], sys.argv[2:]
tabs = []
for p in files:
    d = {}
    order = []
    for line in open(p):
        t = line.split()
        if line.startswith("#") or len(t) < 2:
            continue
        if t[0] not in d:
            order.append(t[0])
        d[t[0]] = t[1]
    tabs.append((d, order))
d0, order = tabs[0]
with open(out, "w") as f:
    f.write("# average of " + " ".join(files) + "\n")
    for k in order:
        try:
            vals = [float(t[0][k]) for t in tabs]
            f.write("%s %r\n" % (k, sum(vals) / len(vals)))
        except (ValueError, KeyError):
            f.write("%s %s\n" % (k, d0[k]))
print("wrote", out, "from", len(files), "programs,", len(order), "keys")
