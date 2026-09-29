import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np, mujoco
import long_jump_limits as L
from search import read_params

def main():
    prog_path = sys.argv[1]; cap_name = sys.argv[2]
    cap = L.load_capture(cap_name)
    body = L.Body(cap["task"], cap["board_x"], json.loads(cap["env"]))
    kp, kd = L.reflex_gains(body.muscles, json.loads(cap["params"]))
    pf = read_params(prog_path); nk = int(round(pf["ik_n"]))
    _, tab = L.read_ik(prog_path, body.muscles, cap["plant"], nk=nk)
    prog = L.IKProgram(tab, pf["ik_h"], pf["ik_td"], pf.get("j_ik_g", 0.0), pf.get("j_ik_kdc", 1.0), kp, kd, pf.get("ik_gap0", 0.0), pf.get("ik_end", pf["ik_td"] + 0.24))
    orig = L.runway_touch
    info = {}
    def rt(b):
        d = b.d
        for i in range(d.ncon):
            c = d.contact[i]
            for a, g in ((c.geom1, c.geom2), (c.geom2, c.geom1)):
                if g == b.runway and a in b.body_geoms:
                    info["geom"] = mujoco.mj_id2name(b.m, mujoco.mjtObj.mjOBJ_GEOM, a); info["t"] = float(d.time); info["x"] = float(c.pos[0])
                    return True
        return False
    L.runway_touch = rt
    r = L.simulate_prog(body, cap, prog)
    print(cap_name, r.get("valid"), r.get("why"), info, "prog.s", getattr(prog, "s", None), "td_seen", prog.td_seen)
if __name__ == "__main__":
    main()
