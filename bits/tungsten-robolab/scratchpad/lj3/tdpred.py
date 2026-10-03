"""What predicts the plant touchdown time and the knee angle at touchdown from the penultimate-touchdown state? (L3 scratch)
usage: tdpred.py <prog.txt> <names-file>"""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj3")
import numpy as np
import long_jump_limits as L
import ljx_robust
import long_jump_mine as M
from search import read_params


def main():
    prog_path, names = sys.argv[1], open(sys.argv[2]).read().split(",")
    caps = [L.load_capture(n) for n in names]
    body = L.Body(caps[0]["task"], caps[0]["board_x"], json.loads(caps[0]["env"]))
    kp, kd = L.reflex_gains(body.muscles, json.loads(caps[0]["params"]))
    pf = read_params(prog_path)
    nk = int(round(pf["ik_n"]))
    X, Y, nm = [], [], []
    for n, cap in zip(names, caps):
        _, tab = L.read_ik(prog_path, body.muscles, cap["plant"], nk=nk)
        prog = L.IKProgram(tab, pf["ik_h"], pf["ik_td"], pf["j_ik_g"], pf.get("j_ik_kdc", 1.0), kp, kd, pf["ik_gap0"], pf["ik_end"])
        r = ljx_robust.simulate_prog2(body, cap, prog)
        if not r["valid"]:
            continue
        f = M.features(body, cap)
        X.append([f["gap"], f["vx"], f["vz"], f["com_z"], f["torso"], f["torso_rate"], f["swing_ahead"], f["swing_z"], f["pen_ahead"], f["Ly"]])
        Y.append([r["td"]["t"], r["td"]["knee"], r["vz"], r["D"] - (cap["board_x"] - r["toe_max"])])
        nm.append(n)
    X, Y = np.array(X), np.array(Y)
    fn = ["gap", "pen_vx", "pen_vz", "pen_z", "torso", "torso_rate", "swing_ahead", "swing_z", "pen_ahead", "Ly"]
    yn = ["td_t", "td_knee", "to_vz", "D_board"]
    print("%d valid states" % len(X))
    print("%-13s" % "corr" + "".join("%10s" % y for y in yn))
    for i, f in enumerate(fn):
        print("%-13s" % f + "".join("%+10.2f" % np.corrcoef(X[:, i], Y[:, j])[0, 1] for j in range(4)) + "   (sd %.3f)" % X[:, i].std())
    # linear fit of td_t and td_knee on the features
    A = np.hstack([X, np.ones((len(X), 1))])
    for j, y in enumerate(yn[:2]):
        w = np.linalg.lstsq(A, Y[:, j], rcond=None)[0]
        res = Y[:, j] - A @ w
        print("fit %-7s R2 %.2f  (resid sd %.3f of %.3f)" % (y, 1 - res.var() / Y[:, j].var(), res.std(), Y[:, j].std()))


main()
