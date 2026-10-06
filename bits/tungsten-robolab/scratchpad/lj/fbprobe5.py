"""Swing-foot lag feedback probes (hand-set gains) on mined starts; latch on; one-sided lag (scratch, mine)."""
import sys, json, os, glob
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
import long_jump_limits as L
names = sorted(os.path.basename(p)[:-len("_capture.npz")] for p in glob.glob("out/long_jump_limits/p95mn_s*_capture.npz"))[::2]
caps = [L.load_capture(n) for n in names]
body = L.Body(caps[0]["task"], caps[0]["board_x"], json.loads(caps[0]["env"]))
mus = body.muscles; n = len(mus)
kp, kd = L.reflex_gains(mus, json.loads(caps[0]["params"]))
pfile, bases = L.plant_bases("out/long_jump_run/p95pn_ik.txt", mus, caps)
nk = int(round(pfile["ik_n"]))
meta = {"nk": nk, "h": pfile["ik_h"], "td": pfile["ik_td"], "g": pfile["j_ik_g"], "kdc": 1.0, "kp": kp, "kd": kd, "gap0": pfile["ik_gap0"], "end": pfile["ik_end"]}
pr, fxr = L.nominal_pitch(body, caps[:60], bases, meta, with_foot=True)
print("nominal swing-foot-ahead by knot:", np.round(fxr, 2).tolist())
DELTA = 0.05
def run(gains, label, fxmax=0.3):
    sc = []; vz = []; Ls = []; ps = []
    for cap in caps:
        tab = dict(bases[cap["plant"]]); tab["fmin"] = 1.5
        tab["fxr"] = fxr; tab["fxmax"] = fxmax
        tab["fkf"] = L.role_vec(gains, mus, cap["plant"])
        prog = L.IKProgram(tab, meta["h"], meta["td"], meta["g"], 1.0, kp, kd, meta["gap0"], meta["end"])
        r = L.simulate_prog(body, cap, prog)
        sc.append(L.board_score2(r, cap, -1.5, DELTA, 2.55, 3.0, 0.3, 0.25, 3.0))
        if r["valid"]: vz.append(r["vz"]); Ls.append(r["L"]); ps.append(r["torso_pitch"])
    sc = np.array(sc); vz = np.array(vz); Ls = np.array(Ls); ps = np.array(ps)
    q = int(round(0.1 * len(sc)))
    print("%-42s mean %.3f worst10%% %.2f  bad(<0) %d  vz<2.4 %d  vz mean %.2f  L>-1.5 %d  pitch>0.25 %d" % (
        label, sc.mean(), np.sort(sc)[:q].mean(), int((sc < 0).sum()), int((vz < 2.4).sum()), vz.mean(), int((Ls > -1.5).sum()), int((ps > 0.25).sum())), flush=True)
run({}, "latch only")
for role in ("T_hip_flex_pos", "T_rf", "T_knee_pos", "F_ham", "T_hip_flex_neg", "F_hip_flex_neg", "F_knee_pos"):
    for g in (5.0, 15.0):
        run({role: g}, f"lag kf {g} on {role}")
run({"T_hip_flex_pos": 10, "T_rf": 10}, "lag hip flex + rf 10")
