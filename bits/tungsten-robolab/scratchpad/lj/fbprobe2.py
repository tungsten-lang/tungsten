"""One-sided / two-sided pitch feedback on F_ham over all mined starts (scratch, mine)."""
import sys, json, os, glob
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
import long_jump_limits as L
names = sorted(os.path.basename(p)[:-len("_capture.npz")] for p in glob.glob("out/long_jump_limits/p95mn_s*_capture.npz"))
caps = [L.load_capture(n) for n in names]
body = L.Body(caps[0]["task"], caps[0]["board_x"], json.loads(caps[0]["env"]))
mus = body.muscles; n = len(mus)
kp, kd = L.reflex_gains(mus, json.loads(caps[0]["params"]))
pfile, base = L.read_ik("out/long_jump_run/p95pn_ik.txt", mus, caps[0]["plant"])
nk = int(round(pfile["ik_n"]))
meta = {"nk": nk, "h": pfile["ik_h"], "td": pfile["ik_td"], "g": pfile["j_ik_g"], "kdc": 1.0, "kp": kp, "kd": kd,
        "gap0": pfile["ik_gap0"], "end": pfile["ik_end"]}
pr = L.nominal_pitch(body, caps[:60], base, meta)
DELTA = 0.05
def run(tab, label):
    sc = []; vz = []
    for cap in caps:
        prog = L.IKProgram(tab, meta["h"], meta["td"], meta["g"], meta["kdc"], kp, kd, meta["gap0"], meta["end"])
        r = L.simulate_prog(body, cap, prog)
        sc.append(L.board_score2(r, cap, 2.0, DELTA, 2.55, 3.0)); vz.append(r["vz"] if r["valid"] else 0.0)
    sc = np.array(sc); vz = np.array(vz)
    bad = int((sc < -2).sum()); weak = int(((sc >= -2) & (vz < 2.4)).sum())
    q = int(round(0.1 * len(sc)))
    print("%-40s mean %.3f  worst10%% %.2f  invalid/foul %d  vz<2.4 %d  D>4.4 %d" % (label, sc.mean(), np.sort(sc)[:q].mean(), bad, weak, int((sc > 4.4).sum())), flush=True)
def mk(role, kpv, clip, fmin=1.5):
    tab = dict(base); tab["pr"] = pr; tab["fbclip"] = clip
    fkp = np.zeros(n); fkd = np.zeros(n)
    for i, nm in enumerate(mus):
        if L.role_of(nm, caps[0]["plant"]) == role:
            fkp[i] = kpv
    tab["fkp"], tab["fkd"], tab["fmin"] = fkp, fkd, fmin
    return tab
b = dict(base); b["fmin"] = 1.5
run(b, "base + fmin 1.5")
for kpv in (3.0, 6.0, 10.0, 16.0):
    run(mk("F_ham", kpv, 1), f"F_ham kp {kpv} one-sided (lean fwd)")
    run(mk("F_ham", kpv, 0), f"F_ham kp {kpv} two-sided")
