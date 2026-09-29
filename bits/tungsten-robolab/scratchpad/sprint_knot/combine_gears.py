"""combine_gears: write a two-gear params file. Gear 1 = the first file (all keys as they are), gear 2 = the second file's stride tunables as g2_<name>
(start-phase tunables and fly_entry are not twinned), plus g2 1 and g2_v_on.
usage: combine_gears.py GEAR1.txt GEAR2.txt V_ON OUT.txt"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
from practice import read_params
from search import write_params
g1, g2, v_on, out = sys.argv[1:5]
p1, p2 = read_params(g1), read_params(g2)
SKIP = {"v0", "drv_floor", "accel", "d_go", "drv0_knee", "drv0_ankle", "drv0_hip", "psi0", "k0", "t0_max", "v_tau", "lean_acc", "fly_entry",
        "g2", "g2_v_on", "gait", "ri", "tcn"}
p = dict(p1)
n = 0
for k, v in p2.items():
    if k in SKIP or k.startswith("g2") or k.startswith("tcn"):
        continue
    if k not in p1 or abs(p1[k] - v) > 1e-12:
        p["g2_" + k] = v; n += 1
p["g2"] = 1.0; p["g2_v_on"] = float(v_on); p.pop("fly_entry", None)
write_params(out, f"two gears: gear 1 {os.path.basename(g1)}, gear 2 {os.path.basename(g2)} (v_on {v_on})", p, 0.0, [{}])
print("wrote", out, "gear-2 twins that differ:", n)
