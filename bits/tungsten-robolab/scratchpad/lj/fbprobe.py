"""Hand-set pitch feedback probes on weak and normal captured starts (scratch, mine)."""
import sys, json, os
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
import long_jump_limits as L
prefix = "p95mn"
names = ["p95mn_s8144", "p95mn_s8137", "p95mn_s8039", "p95mn_s8011", "p95mn_s8081", "p95mn_s8001", "p95mn_s8004", "p95mn_s8013"]
caps = [L.load_capture(n) for n in names]
body = L.Body(caps[0]["task"], caps[0]["board_x"], json.loads(caps[0]["env"]))
mus = body.muscles
n = len(mus)
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
        row.append("inv" if not r["valid"] else "%.2f/%.2f" % (r["vz"], r["D"] - (cap["board_x"] - r["toe_max"])))
    print("%-34s" % label, " ".join("%9s" % x for x in row))
def mk(groups, kpv=0.0, kdv=0.0, fmin=1.5):
    tab = dict(base)
    tab["pr"] = pr
    fkp = np.zeros(n); fkd = np.zeros(n)
    for i, nm in enumerate(mus):
        role = L.role_of(nm, caps[0]["plant"])
        for g_, v in groups.items():
            if role == g_:
                fkp[i] = v * kpv; fkd[i] = v * kdv
    tab["fkp"], tab["fkd"], tab["fmin"] = fkp, fkd, fmin
    return tab
print("weak: s8144 s8137 s8039 s8011 | s8081 (0.17) | normal: s8001 s8004 s8013   (vz/Dboard)")
run(dict(base, fmin=1.5), "base + fmin")
for role in ("spine_flex_neg", "F_hip_flex_neg", "T_hip_flex_neg", "F_ham", "T_hip_flex_pos", "F_hip_flex_pos", "l_shoulder_flex_neg", "r_shoulder_flex_neg", "l_shoulder_flex_pos"):
    for kpv in (6.0, -6.0):
        run(mk({role: 1.0}, kpv), f"kp {kpv:+.0f} on {role}")
