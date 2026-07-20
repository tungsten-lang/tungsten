# Compound assignment on index targets (`h[k] += v`, `a[i] -= v`) — the
# interpreter rejected the :call target ("Invalid compound assignment
# target"); compiled always supported it. The interpreter now reads through
# "[]", applies the operator, and writes back through "[]=". Missing keys get
# NO default: `{}[k] += 1` raises in both engines (nil + int).
h = {}
h["k"] = 1
h["k"] += 5
v1 = h["k"]
<< "h-plus=[v1]"
h["k"] -= 2
v2 = h["k"]
<< "h-minus=[v2]"
counts = {}
counts["x"] = 0
counts["x"] += 1
counts["x"] += 1
v3 = counts["x"]
<< "tally=[v3]"
a = [10, 20, 30]
a[1] += 7
a[2] *= 2
a[0] -= 5
v4 = a.join("-")
<< "arr=[v4]"
s = {}
s["msg"] = "ab"
s["msg"] += "cd"
v5 = s["msg"]
<< "str=[v5]"
