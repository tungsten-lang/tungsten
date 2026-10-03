"""Plant-touchdown geometry vs outcome for a robust program over captured states (L3 scratch).
usage: tdfeat.py <prog.txt> <names-file>"""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj3")
import numpy as np
import long_jump_limits as L
import ljx, ljx_robust
import long_jump_mine as M
from search import read_params


def main():
    prog_path, names = sys.argv[1], open(sys.argv[2]).read().split(",")
    caps = [L.load_capture(n) for n in names]
    body = L.Body(caps[0]["task"], caps[0]["board_x"], json.loads(caps[0]["env"]))
    kp, kd = L.reflex_gains(body.muscles, json.loads(caps[0]["params"]))
    pf = read_params(prog_path)
    nk = int(round(pf["ik_n"]))
    rows = []
    for nm, cap in zip(names, caps):
        _, tab = L.read_ik(prog_path, body.muscles, cap["plant"], nk=nk)
        prog = L.IKProgram(tab, pf["ik_h"], pf["ik_td"], pf["j_ik_g"], pf.get("j_ik_kdc", 1.0), kp, kd, pf["ik_gap0"], pf["ik_end"])
        r = ljx_robust.simulate_prog2(body, cap, prog)
        f = M.features(body, cap)
        if r["valid"]:
            td = r["td"]
            rows.append((nm, f["gap"], f["vx"], f["com_z"], f["torso"], f["swing_ahead"], td["t"], td["leg_angle_deg"], td["foot_ahead_m"], td["knee"], td["vz"], r["vz"], r["vx"], r["D"] - (cap["board_x"] - r["toe_max"]), r["contact_s"]))
    A = np.array([r[1:] for r in rows], float)
    cols = ["gap", "pen_vx", "pen_z", "pen_torso", "swing_ahead", "td_t", "td_leg_deg", "td_foot_ahead", "td_knee", "td_vz", "to_vz", "to_vx", "D_board", "contact"]
    print("%d valid states; correlations with the take-off vz and D_board:" % len(rows))
    for i, c in enumerate(cols[:10]):
        print("  %-14s mean %7.3f sd %6.3f  corr(vz) %+.2f  corr(D_board) %+.2f" % (c, A[:, i].mean(), A[:, i].std(), np.corrcoef(A[:, i], A[:, 10])[0, 1], np.corrcoef(A[:, i], A[:, 12])[0, 1]))
    order = np.argsort(A[:, 12])
    print("worst 8 by D_board:")
    for k in order[:8]:
        r = rows[k]
        print("  %-10s gap %.2f pen_vx %.2f td_t %.3f leg %.1f ahead %+.2f knee %+.2f td_vz %+.2f -> vz %+.2f vx %.2f D_board %.2f contact %.3f" % (r[0], r[1], r[2], r[6], r[7], r[8], r[9], r[10], r[11], r[12], r[13], r[14]))


main()
