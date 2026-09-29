"""Round 10: for the hits of a run, the exit velocity: measured vs the offline model with the pad's actual normal/velocity, and the landing."""
import json, sys
import numpy as np
sys.path.insert(0, "playground")
import tt_impact as ti
np.set_printoptions(precision=3, suppress=True, linewidth=200)
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
rows = [r for r in rows if "error" not in r and r.get("hit") and r.get("ball_in_exact") and r.get("ball_out_exact")]
E, A, MU = 0.95, 0.9, 0.012
res = []; land = []
for r in rows:
    vin = np.array(r["ball_in_exact"]); n = np.array(r["pad_normal"]); vp = np.array(r["paddle_vel"])
    vo = ti.impact(vin, A * vp, n, E, MU)
    vm = np.array(r["ball_out_exact"])
    res.append(vm - vo)
    lab = ti.flight(r["ball_pos_out"], vm)
    land.append((lab[0], lab[1], lab[2], r.get("landed"), r["solved"]))
res = np.array(res)
print("hits", len(rows), " measured-minus-model exit velocity: mean", res.mean(0), "sd", res.std(0))
vm = np.array([r["ball_out_exact"] for r in rows]); print("exit velocity mean", vm.mean(0), "sd", vm.std(0), " speed mean %.2f" % np.linalg.norm(vm, axis=1).mean())
import collections
print("model flight of the MEASURED exit:", collections.Counter(l[0] for l in land))
xs = np.array([l[1] for l in land if l[0] == "opp"]); print("opp landings x mean %.2f sd %.2f" % (xs.mean(), xs.std()) if len(xs) else "")
# where do the 'out' returns go? use the measured exit + ballistic to the table plane height
outs = [(r, np.array(r["ball_pos_out"]), np.array(r["ball_out_exact"])) for r in rows if r["solved"] <= 0]
lx = []; ly = []
for r, p, v in outs:
    disc = v[2] ** 2 + 2 * 9.81 * (p[2] - 0.816)
    t = (v[2] + np.sqrt(max(disc, 0))) / 9.81
    lx.append(p[0] + v[0] * t); ly.append(p[1] + v[1] * t)
lx = np.array(lx); ly = np.array(ly)
print("failed hits: table-plane crossing x: mean %.2f sd %.2f (opp half -1.37..0); y mean %.2f sd %.2f (-0.72..0.80)" % (lx.mean(), lx.std(), ly.mean(), ly.std()))
print("  long (x<-1.37): %.2f, short/net (x>-0.1): %.2f, wide (|y-0.04|>0.76): %.2f" % (np.mean(lx < -1.37), np.mean(lx > -0.1), np.mean(np.abs(ly - 0.04) > 0.76)))
