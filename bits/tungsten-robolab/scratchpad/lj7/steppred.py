"""steppred (L7): how well is the next step predictable at toe-off? usage: steppred.py trace.json"""
import json, sys
import numpy as np
d = json.load(open(sys.argv[1]))
st_max = st_up = 0.35
S = []
for r in d["rows"]:
    rows = r["rows"]; dbg = r["dbg"]
    if len(rows) < 100: continue
    T = np.array([x[0] for x in rows]); lab = [x[1] for x in rows]
    A = np.array([[x[k] for k in range(2, 16)] for x in rows], float)   # com_x com_z vx vz pel_x pel_z ltx ltz rtx rtz lhx lhz rhx rhz
    for i in range(1, len(dbg) - 1):
        a, b = dbg[i], dbg[i + 1]
        if a["pen"] or a["n"] < 2 or not (1.4 < b["step"] < 3.3): continue
        side = a["side"]            # "l_" or "r_": the foot that touched down at a (stance now), flight_i is side + "flight"
        # first tick after a["t"] with the flight chunk label
        k0 = None
        for k in range(len(T)):
            if T[k] >= a["t"] - 0.002 and lab[k] == "body:" + side + "flight":
                k0 = k; break
        if k0 is None or T[k0] > b["t"]: continue
        kt = k0
        # touchdown tick of the landing foot: b["t"]
        # previous toe x of the stance foot at its touchdown a: the toe x = b-step reference: toe_b - step_b
        com_x, com_z, vx, vz, pel_x, pel_z, ltx, ltz, rtx, rtz, lhx, lhz, rhx, rhz = A[k0]
        land = "r_" if side == "l_" else "l_"
        sw_x = rtx if land == "r_" else ltx; sw_z = rtz if land == "r_" else ltz
        st_x = ltx if side == "l_" else rtx
        # toe x at touchdown of b = last toe + step_b; the stance foot's toe at a: from the step bookkeeping, the controller's last_toe = toe_b - step_b
        # use the task touchdown list for toe_b
        tdb = [k for k in r["tds"] if abs(k[1] - b["t"]) < 0.03 and k[0] == land[0]]
        if not tdb: continue
        toe_b = tdb[0][2] + r["board_x"]
        last_toe = toe_b - b["step"]
        adj = min(max(a["plan"] - a["stride"], -st_max), st_up)
        t_stance = T[k0] - a["t"]
        S.append((b["step"], adj, a["stride"], vx, vz, com_z, com_x - last_toe, sw_x - com_x, sw_z, T[k0] - a["t"], st_x - last_toe, pel_z, b["t"] - T[k0], a["n"], r["seed"]))
S = np.array(S)
print("samples", len(S))
y = S[:, 0] - S[:, 1]            # step with the applied nudge removed (response gain 1)
names = ["stride", "vx", "vz", "com_z", "com_x-last_toe", "sw_x-com_x", "sw_z", "t_stance", "st_x-last_toe", "pel_z"]
cols = {n: S[:, 2 + k] for k, n in enumerate(names)}
def fit(use, tgt=y, label=""):
    X = np.column_stack([cols[n] for n in use] + [np.ones(len(S))])
    c = np.linalg.lstsq(X, tgt, rcond=None)[0]
    res = tgt - X @ c
    print("%-60s resid sd %.4f  MAD %.4f" % (label + "+".join(use), res.std(), 1.4826 * np.median(np.abs(res - np.median(res)))))
    return c
print("baseline: sd of (step - adj) = %.4f ; sd of (step - adj - stride) = %.4f" % (y.std(), (y - cols["stride"]).std()))
fit(["stride"])
fit(["stride", "vx"])
fit(["stride", "vx", "vz"])
fit(["stride", "vx", "vz", "com_z"])
fit(["stride", "vx", "vz", "com_z", "com_x-last_toe"])
fit(["stride", "vx", "vz", "com_z", "com_x-last_toe", "sw_x-com_x"])
fit(["stride", "vx", "vz", "com_z", "com_x-last_toe", "sw_x-com_x", "sw_z"])
c = fit(["stride", "vx", "vz", "com_z", "com_x-last_toe", "sw_x-com_x", "sw_z", "t_stance"])
fit(["vx", "vz", "com_z", "com_x-last_toe", "sw_x-com_x", "sw_z", "t_stance"])
fit(["vx", "vz", "com_x-last_toe"])
fit(["vz", "com_x-last_toe"])
# time of flight vs vz
tf = S[:, 12]
print("flight time sd %.4f mean %.4f; corr(tf, vz) %.2f" % (tf.std(), tf.mean(), np.corrcoef(tf, S[:, 4])[0, 1]))
X = np.column_stack([cols["vz"], cols["com_z"], np.ones(len(S))]); cc = np.linalg.lstsq(X, tf, rcond=None)[0]; print("tf ~ vz, com_z: resid sd %.4f" % (tf - X @ cc).std())
print("step noise attributable: vx*tf sd %.3f" % (cols["vx"] * tf).std())
