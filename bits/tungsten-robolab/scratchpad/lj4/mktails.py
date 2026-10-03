"""Write the regime tails trained by ljx_tail.py as skill params (agent L4): ik_rg_t1 / t2 / nd / tau<k> and ik1_/ik2_ de<k> / dc<k> tables by muscle ROLE (relative to the plant side of the
first capture of the training list, as the harness's tables).
usage: mktails.py <out.txt> <tail_r1.npz> [<tail_r2.npz>]"""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj4")
import numpy as np
import long_jump_limits as L
import rgprog
import ljx_tail

out = sys.argv[1]
lines = []
t1 = t2 = None
for pth in sys.argv[2:]:
    z = np.load(pth)
    names = [str(n) for n in z["names"]]
    cap = L.load_capture(names[0])
    body = L.Body(cap["task"], cap["board_x"], json.loads(cap["env"]))
    p0 = cap["plant"]
    n = len(body.muscles)
    nd = int(z["nd"])
    reg = int(z["regime"])
    de, dc = ljx_tail.decode(z["x"], [reg], nd, n)
    t1, t2 = float(z["t1"]), float(z["t2"])
    for k in range(nd):
        for i, nm in enumerate(body.muscles):
            role = L.role_of(nm, p0)
            lines.append(f"ik{reg}_de{k}_{role} {float(de[reg][k, i])!r}")
            lines.append(f"ik{reg}_dc{k}_{role} {float(dc[reg][k, i])!r}")
head = ["# per-regime post-touchdown offsets (M3, agent L4): " + " ".join(sys.argv[2:]),
        f"ik_rg_t1 {t1!r}", f"ik_rg_t2 {t2!r}", f"ik_rg_nd {len(rgprog.TAU_KNOTS)}"]
head += [f"ik_rg_tau{k} {float(v)!r}" for k, v in enumerate(rgprog.TAU_KNOTS)]
open(out, "w").write("\n".join(head + lines) + "\n")
print("wrote", out, len(lines), "table lines, t1", t1, "t2", t2)
