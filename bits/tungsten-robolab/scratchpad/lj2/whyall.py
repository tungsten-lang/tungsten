import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np, mujoco
import long_jump_limits as L
from search import read_params

def main():
    prog_path = sys.argv[1]; caps = sys.argv[2].split(",")
    c0 = L.load_capture(caps[0])
    body = L.Body(c0["task"], c0["board_x"], json.loads(c0["env"]))
    kp, kd = L.reflex_gains(body.muscles, json.loads(c0["params"]))
    pf = read_params(prog_path); nk = int(round(pf["ik_n"]))
    orig = L.runway_touch
    info = {}
    def rt(b):
        d = b.d
        for i in range(d.ncon):
            c = d.contact[i]
            for a, g in ((c.geom1, c.geom2), (c.geom2, c.geom1)):
                if g == b.runway and a in b.body_geoms:
                    info["geom"] = mujoco.mj_id2name(b.m, mujoco.mjtObj.mjOBJ_GEOM, a); info["t"] = round(float(d.time), 3)
                    return True
        return False
    L.runway_touch = rt
    for nm in caps:
        cap = L.load_capture(nm)
        info.clear()
        _, tab = L.read_ik(prog_path, body.muscles, cap["plant"], nk=nk)
        prog = L.IKProgram(tab, pf["ik_h"], pf["ik_td"], pf.get("j_ik_g", 0.0), pf.get("j_ik_kdc", 1.0), kp, kd, pf.get("ik_gap0", 0.0), pf.get("ik_end", pf["ik_td"] + 0.24))
        r = L.simulate_prog(body, cap, prog)
        if r["valid"]:
            print("%-10s valid D_board %.3f vx %.2f vz %.2f L %.1f toe-board %+.3f contact %.3f" % (nm, r["D"] - (cap["board_x"] - r["toe_max"]), r["vx"], r["vz"], r["L"], r["toe_max"] - cap["board_x"], r["contact_s"]))
        else:
            print("%-10s INVALID %s t=%.3f prog.s %.3f td_seen %s %s" % (nm, r.get("why"), r.get("t", 0), getattr(prog, "s", -1), prog.td_seen, info))

if __name__ == "__main__":
    main()
