import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np, mujoco
import long_jump_limits as L
from search import read_params

def run(prog_path, cap_name, label):
    cap = L.load_capture(cap_name)
    body = L.Body(cap["task"], cap["board_x"], json.loads(cap["env"]))
    kp, kd = L.reflex_gains(body.muscles, json.loads(cap["params"]))
    pf = read_params(prog_path); nk = int(round(pf["ik_n"]))
    _, tab = L.read_ik(prog_path, body.muscles, cap["plant"], nk=nk)
    prog = L.IKProgram(tab, pf["ik_h"], pf["ik_td"], pf.get("j_ik_g", 0.0), pf.get("j_ik_kdc", 1.0), kp, kd, pf.get("ik_gap0", 0.0), pf.get("ik_end", pf["ik_td"] + 0.24))
    free = "r" if cap["plant"] == "l" else "l"
    m, d = body.m, body.d
    st = m.site(f"{free}_toe").id; sh = m.site(f"{free}_heel").id; pt = m.site(f"{cap['plant']}_toe").id
    trace = []
    orig = L.simulate
    # replicate simulate_prog with a per-tick hook via the program call
    inner = prog.__call__
    def hooked(b, t, k):
        out = inner(b, t, k)
        mujoco.mj_subtreeVel(m, d)
        trace.append((round(t, 3), float(d.site_xpos[st][2]), float(d.site_xpos[sh][2]), float(d.site_xpos[pt][2]), float(d.subtree_com[body.pelvis][2]), prog.td_seen))
        return out
    prog.__call__ = hooked
    class P:  # wrapper since simulate_prog calls prog(body, t, k)
        pass
    mujoco.mj_setState(m, d, cap["state"], L.SPEC); mujoco.mj_forward(m, d)
    prog.start(body, cap)
    until = (lambda t: prog.td_seen and t + prog.shift > prog.end)
    r = L.simulate(body, cap, lambda t, k: hooked(body, t, k), restore=False, until=until)
    print(label, cap_name, "valid", r["valid"], r.get("why"))
    for row in trace[::5][-14:]:
        print("   t %.3f free toe z %.3f heel z %.3f plant toe z %.3f com z %.3f td_seen %s" % row)

if __name__ == "__main__":
    run(sys.argv[1], sys.argv[2], sys.argv[3])
