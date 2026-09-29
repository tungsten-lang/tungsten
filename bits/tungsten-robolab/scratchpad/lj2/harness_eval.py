"""Closed-loop take-off program on captured states (harness): per capture and a summary with the plant offset vs the penultimate gap (L2).
usage: harness_eval.py <program params file> <cap,cap,...> [--quiet]"""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
import long_jump_limits as L
import long_jump_mine as M
from search import read_params

def main():
    prog_path = sys.argv[1]; caps = sys.argv[2].split(","); quiet = "--quiet" in sys.argv
    c0 = L.load_capture(caps[0])
    body = L.Body(c0["task"], c0["board_x"], json.loads(c0["env"]))
    kp, kd = L.reflex_gains(body.muscles, json.loads(c0["params"]))
    pf = read_params(prog_path); nk = int(round(pf["ik_n"]))
    rows = []
    for nm in caps:
        cap = L.load_capture(nm)
        gap = M.features(body, cap)["gap"]
        _, tab = L.read_ik(prog_path, body.muscles, cap["plant"], nk=nk)
        prog = L.IKProgram(tab, pf["ik_h"], pf["ik_td"], pf.get("j_ik_g", 0.0), pf.get("j_ik_kdc", 1.0), kp, kd, pf.get("ik_gap0", 0.0), pf.get("ik_end", pf["ik_td"] + 0.24))
        r = L.simulate_prog(body, cap, prog)
        if r["valid"]:
            db = r["D"] - (cap["board_x"] - r["toe_max"]); off = r["toe_max"] - cap["board_x"]
            rows.append((nm, cap["plant"], gap, True, db, off, r["vx"], r["vz"], r["L"], r["contact_s"]))
            if not quiet:
                print("%-10s %s gap %.2f valid D_board %.3f off %+.3f vx %.2f vz %.2f L %5.1f contact %.3f%s" % (nm, cap["plant"], gap, db, off, r["vx"], r["vz"], r["L"], r["contact_s"], "  FOUL" if off > 0 else ""))
        else:
            rows.append((nm, cap["plant"], gap, False, 0, 0, 0, 0, 0, 0))
            if not quiet:
                print("%-10s %s gap %.2f INVALID %s" % (nm, cap["plant"], gap, r.get("why")))
    ok = [r for r in rows if r[3]]
    db = np.array([r[4] for r in ok]); off = np.array([r[5] for r in ok]); g = np.array([r[2] for r in ok])
    nf = int((off > 0).sum()) if len(ok) else 0
    print("SUMMARY %s: %d starts, valid %d, fouls %d, D_board mean %.3f min %.3f, legal mean (fouls 0) %.3f; foot offset mean %+.3f sd %.3f; gap sd %.3f" % (
        os.path.basename(prog_path), len(rows), len(ok), nf, db.mean() if len(ok) else 0, db.min() if len(ok) else 0,
        (np.where(off > 0, 0, db).sum() / len(rows)), off.mean() if len(ok) else 0, off.std() if len(ok) else 0, g.std() if len(ok) else 0))
    if len(ok) > 3:
        A = np.vstack([g, np.ones_like(g)]).T
        sl, ic = np.linalg.lstsq(A, off, rcond=None)[0]
        print("   plant offset vs pen gap: slope %.3f (a program that compensates fully: 0; none: -1) resid sd %.3f" % (sl, (off - (sl * g + ic)).std()))

if __name__ == "__main__":
    main()
