import sys, time
sys.path.insert(0, "scratchpad/btl2")
import numpy as np
from common import load
import oracle_lib as O
p = load("params/dribble_btl_a4.txt")
t0 = time.time()
rec = O.record(716, p, "bin/challengers/btl2-b1", 2.0, 2.9)
print("recorded", rec["acts"].shape, "k0", rec["k0"], f"{time.time()-t0:.1f}s")
rp = O.Replay(rec)
t0 = time.time()
out = rp.run()
print(f"replay {time.time()-t0:.2f}s for {len(out['pos'])} ticks")
k0 = rec["k0"]
diff = np.abs(out["pos"] - rec["ball"][k0:k0 + len(out["pos"])]).max(axis=1)
print("max ball position difference vs the recording:", diff.max(), "at tick", int(diff.argmax()))
i = int(np.argmax(out["cf"][:, 0] > 0.3))
print("left touch starts at tick", i, "t", round(out["t0"] + (i + 1) * 0.005, 3))
