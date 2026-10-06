"""Write the incoming-energy blocks of fit_v.py results into a params file.

    .venv/bin/python scratchpad/btl4/mkv_params.py base.txt out.txt fit1.npz [fit2.npz ...] [scale=0.5]

Each npz carries x (16 x 17 block), stage, knee, scale; a `scale=` argument multiplies every block (a trust-region knob).
"""
import sys
import numpy as np
sys.path.insert(0, "scratchpad/btl2")
from common import load, write_params

base, out = sys.argv[1], sys.argv[2]
p = load(base)
mult = 1.0
files = []
for a in sys.argv[3:]:
    if a.startswith("scale="):
        mult = float(a.split("=")[1])
    else:
        files.append(a)
p["pg_vn"] = 1.0
note = f"{base} + incoming-energy blocks from {','.join(files)} x{mult}"
for fn in files:
    z = np.load(fn)
    st = int(z["stage"])
    x = z["x"].reshape(16, 17) * mult
    gm = float(z["gmax"]) if "gmax" in z.files else 1.0
    x = np.clip(x, -gm, gm)
    p[f"pgvk{st}"] = float(z["knee"])
    p[f"pgvs{st}"] = float(z["scale"])
    for m in range(16):
        for k in range(17):
            p[f"pgv{st}_{m}_{k}"] = float(x[m, k])
write_params(out, p, note)
print("wrote", out, "stages", [int(np.load(f)["stage"]) for f in files], "max |block|", max(float(np.abs(np.load(f)["x"]).max()) for f in files))
