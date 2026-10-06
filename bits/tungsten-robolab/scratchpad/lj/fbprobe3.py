"""Clearance reflex probes on the invalid (scuff) mined starts, with the F_ham pitch feedback on (scratch, mine)."""
import sys, json, os
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
import long_jump_limits as L
inv = ["p95mn_s8045", "p95mn_s8130", "p95mn_s8161", "p95mn_s8162"]
normal = ["p95mn_s8001", "p95mn_s8002", "p95mn_s8003", "p95mn_s8004", "p95mn_s8005", "p95mn_s8007", "p95mn_s8008", "p95mn_s8010"]
caps = [L.load_capture(n) for n in inv + normal]
body = L.Body(caps[0]["task"], caps[0]["board_x"], json.loads(caps[0]["env"]))
mus = body.muscles; n = len(mus)
kp, kd = L.reflex_gains(mus, json.loads(caps[0]["params"]))
pfile, base = L.read_ik("out/long_jump_run/p95pn_ik.txt", mus, caps[0]["plant"])
nk = int(round(pfile["ik_n"]))
meta = {"nk": nk, "h": pfile["ik_h"], "td": pfile["ik_td"], "g": pfile["j_ik_g"], "kdc": 1.0, "kp": kp, "kd": kd,
        "gap0": pfile["ik_gap0"], "end": pfile["ik_end"]}
pr = L.nominal_pitch(body, [L.load_capture(f"p95mn_s{s}") for s in range(8001, 8041) if os.path.exists(f"out/long_jump_limits/p95mn_s{s}_capture.npz")], base, meta)
def run(tab, label):
    row = []
    for cap in caps:
        prog = L.IKProgram(tab, meta["h"], meta["td"], meta["g"], meta["kdc"], kp, kd, meta["gap0"], meta["end"])
        r = L.simulate_prog(body, cap, prog)
        row.append(("inv:" + str(r.get("why"))[:6]) if not r["valid"] else "%.2f/%.2f" % (r["vz"], r["D"] - (cap["board_x"] - r["toe_max"])))
    print("%-46s" % label, " ".join("%9s" % x for x in row), flush=True)
def mk(groups, clz=0.06, clt=0.04, fmin=1.5):
    tab = dict(base); tab["pr"] = pr; tab["fbclip"] = 1; tab["fmin"] = fmin
    fkp = np.zeros(n); fkd = np.zeros(n); ckc = np.zeros(n)
    for i, nm in enumerate(mus):
        role = L.role_of(nm, caps[0]["plant"])
        if role == "F_ham": fkp[i] = 8.0
        if role in groups: ckc[i] = groups[role]
    tab["fkp"], tab["fkd"], tab["ckc"], tab["clz"], tab["clt"] = fkp, fkd, ckc, clz, clt
    return tab
print("scuff starts s8045 s8130 s8161 s8162 | normal s8001 s8002 s8003 s8004 s8005 s8007 s8008 s8010   (vz/Dboard)")
run(mk({}), "F_ham 8 + latch (no clearance)")
G = {"T_hip_flex_pos": 25, "T_knee_pos": 25, "T_ankle_neg": 25}
run(mk(G), "clz .06 hip+knee+ankle 25")
run(mk(G, clz=0.04), "clz .04 ...")
run(mk(G, clz=0.10), "clz .10 ...")
run(mk({"T_hip_flex_pos": 60}), "hip 60 only")
run(mk({"T_knee_pos": 60}), "knee_pos 60 only")
run(mk({"T_ankle_neg": 60}), "ankle_neg 60 only")
run(mk({"T_hip_flex_pos": 25, "T_knee_pos": 25}), "hip+knee 25")
run(mk({"T_hip_flex_pos": 25, "T_ankle_neg": 25}), "hip+ankle 25")
run(mk({"T_toe_neg": 40, "T_ankle_neg": 40}), "toe_neg+ankle_neg 40")
run(mk({"T_rf": 40, "T_hip_flex_pos": 40}), "rf+hip 40")
