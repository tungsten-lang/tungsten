import os, sys, json, time
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
import long_jump_limits as L
from search import read_params
def main():
    prog_path = sys.argv[1]; caps = sys.argv[2].split(",")
    c0 = L.load_capture(caps[0])
    body = L.Body(c0["task"], c0["board_x"], json.loads(c0["env"]))
    kp, kd = L.reflex_gains(body.muscles, json.loads(c0["params"]))
    pf = read_params(prog_path)
    nk = int(round(pf["ik_n"]))
    for nm in caps:
        cap = L.load_capture(nm)
        _, tab = L.read_ik(prog_path, body.muscles, cap["plant"], nk=nk)
        prog = L.IKProgram(tab, pf["ik_h"], pf["ik_td"], pf.get("j_ik_g", 0.0), pf.get("j_ik_kdc", 1.0), kp, kd, pf.get("ik_gap0", 0.0), pf.get("ik_end", pf["ik_td"] + 0.24))
        t0 = time.time()
        r = L.simulate_prog(body, cap, prog)
        dt = time.time() - t0
        print(nm, "valid", r["valid"], "D_board %.3f" % (r["D"] - (cap["board_x"] - r["toe_max"])) if r["valid"] else r.get("why"), "vx %.2f vz %.2f L %.1f toe_max-board %.3f  (%.2f s)" % (r.get("vx", 0), r.get("vz", 0), r.get("L", 0), r.get("toe_max", 0) - cap["board_x"], dt))
if __name__ == "__main__":
    main()
