import sys, time
import numpy as np
sys.path.insert(0, "scratchpad/btl4")
import rlib

seeds = list(range(13001, 13013))
for st in (1, 2):
    print("=== stage", st)
    for sd in seeds[:6]:
        d = rlib.StartData(sd, f"out/btl4/rec/rec_{sd}.pkl")
        if st not in d.ks:
            print(sd, "no trigger"); continue
        t0 = time.time()
        out, s0 = d.run_stage(st)
        t1 = time.time() - t0
        ks = d.ks[st]
        # closed-loop ball path vs replay (post-step positions)
        n = len(out["pos"])
        ref = d.rec["ball"][ks:ks + n]
        dev = np.abs(out["pos"] - ref).max()
        y0 = rlib.outcome_vec(s0)
        print(sd, f"trigger tick {ks} t {ks*0.005:.3f} replay {t1:.3f}s ticks {n} max |ball replay - closed loop| {dev:.2e}",
              "v", None if y0 is None else np.round(y0[:3], 2).tolist(), "bounce", None if y0 is None else np.round(y0[6:8], 3).tolist(), "apex", None if y0 is None else round(y0[10], 3), "gate", s0.get("gate"), "body", s0.get("body"))
