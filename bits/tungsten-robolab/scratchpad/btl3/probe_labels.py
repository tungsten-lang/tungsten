import sys
sys.path.insert(0, "scratchpad/btl2")
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from common import load
import oracle_lib as O
params = load("scratchpad/btl2/params/pgP0LRz2.txt")
rec = O.record(2001, params, "bin/challengers/btl2-b12", 0.0, 4.5, t_last=0.0)
labs = rec["labels"]
prev = None
for k, l in enumerate(labs):
    if l != prev:
        print(k, round(k * 0.005, 3), l)
        prev = l
print(rec["pass_log"])
