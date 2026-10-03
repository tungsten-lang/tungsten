"""Plant-touchdown knee angle vs outcome for a take-off program over captured states (harness; agent L4).
usage: tdbins.py <prog.txt> <names-file> [fmin]"""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj3")
import numpy as np
import long_jump_limits as L
import ljx, ljx_robust
from search import read_params


def main():
    prog_path, names = sys.argv[1], open(sys.argv[2]).read().split(",")
    fmin = float(sys.argv[3]) if len(sys.argv) > 3 else None
    caps = [L.load_capture(n) for n in names]
    body = L.Body(caps[0]["task"], caps[0]["board_x"], json.loads(caps[0]["env"]))
    kp, kd = L.reflex_gains(body.muscles, json.loads(caps[0]["params"]))
    pf = read_params(prog_path)
    nk = int(round(pf["ik_n"]))
    cfg = {"board": True, "margin": 0.03, "lmax": -1.5, "lmin": -15.0, "grfcap": 20.0, "grfw": 0.3, "td": 0.0, "tdw": 20.0, "kneeload": 0.0, "kneew": 10.0}
    rows = []
    for nm, cap in zip(names, caps):
        _, tab = L.read_ik(prog_path, body.muscles, cap["plant"], nk=nk)
        if fmin is not None:
            tab["fmin"] = fmin
        prog = L.IKProgram(tab, pf["ik_h"], pf["ik_td"], pf["j_ik_g"], pf.get("j_ik_kdc", 1.0), kp, kd, pf["ik_gap0"], pf["ik_end"])
        r = ljx_robust.simulate_prog2(body, cap, prog)
        sc = ljx.score2(r, cap, cfg)
        if r["valid"]:
            td = r["td"]
            rows.append((td["knee"], td["t"], sc, r["D"] - (cap["board_x"] - r["toe_max"]), r["vz"], r["L"], nm))
        else:
            rows.append((9.0, 0.0, sc, 0.0, 0.0, 0.0, nm))
    A = np.array([r[:6] for r in rows], float)
    print("%d states" % len(rows))
    edges = [-9, 0.0, 0.2, 0.4, 0.6, 0.9, 1.2, 8.0, 99]
    for a, b in zip(edges[:-1], edges[1:]):
        m = (A[:, 0] >= a) & (A[:, 0] < b)
        if m.sum():
            print("knee at touchdown [%5.2f, %5.2f): n %3d  mean score %6.2f  mean D_board %5.2f  mean vz %5.2f  mean td_t %.3f  L %6.1f" % (
                a, b, m.sum(), A[m, 2].mean(), A[m, 3].mean(), A[m, 4].mean(), A[m, 1].mean(), A[m, 5].mean()))
    for a, b in zip((0.0, 0.1, 0.15, 0.2, 0.25), (0.1, 0.15, 0.2, 0.25, 0.4)):
        m = (A[:, 1] >= a) & (A[:, 1] < b) & (A[:, 0] < 8)
        if m.sum():
            print("touchdown time [%.2f, %.2f): n %3d  mean score %6.2f  mean knee %5.2f" % (a, b, m.sum(), A[m, 2].mean(), A[m, 0].mean()))


main()
