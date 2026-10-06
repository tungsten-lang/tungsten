"""Which mined starts still fail with F_ham pitch feedback + plant latch? (scratch, mine)"""
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
meta = {"nk": nk, "h": pfile["ik_h"], "td": pfile["ik_td"], "g": pfile["j_ik_g"], "kdc": 1.0, "kp": kp, "kd": kd, "gap0": pfile["ik_gap0"], "end": pfile["ik_end"]}
pr = L.nominal_pitch(body, caps[:60], base, meta)
tab = dict(base); tab["pr"] = pr; tab["fbclip"] = 1; tab["fmin"] = 1.5
fkp = np.zeros(n)
for i, nm in enumerate(mus):
    if L.role_of(nm, caps[0]["plant"]) == "F_ham": fkp[i] = 8.0
tab["fkp"], tab["fkd"] = fkp, np.zeros(n)
for label, dl in (("delta 0", 0.0), ("delta 0.05", 0.05)):
    bad = []
    for name, cap in zip(names, caps):
        prog = L.IKProgram(tab, meta["h"], meta["td"], meta["g"], meta["kdc"], kp, kd, meta["gap0"], meta["end"])
        r = L.simulate_prog(body, cap, prog)
        if not r["valid"]:
            bad.append((name, "invalid", r.get("why")))
        else:
            over = r["toe_max"] - (cap["board_x"] + dl)
            if over > 0: bad.append((name, "foul %.3f" % over))
            elif r["vz"] < 2.4: bad.append((name, "weak vz %.2f" % r["vz"]))
    print(label, len(bad), bad, flush=True)
