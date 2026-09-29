"""The excitation knots a linear-in-gap take-off program plays on one captured start, as an `optimise --init` json (L2).
usage: prog_to_knots.py <program.txt> <capture> <out.json>"""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
import long_jump_limits as L
from search import read_params

def main():
    prog_path, cap_name, out = sys.argv[1:4]
    cap = L.load_capture(cap_name)
    body = L.Body(cap["task"], cap["board_x"], json.loads(cap["env"]))
    pf = read_params(prog_path); nk = int(round(pf["ik_n"]))
    _, tab = L.read_ik(prog_path, body.muscles, cap["plant"], nk=nk)
    import mujoco
    mujoco.mj_setState(body.m, body.d, cap["state"], L.SPEC); mujoco.mj_forward(body.m, body.d)
    pen = "l" if cap["plant"] == "r" else "r"
    gap_err = (cap["board_x"] - L.seen_site_x(body, f"{pen}_toe")) - pf.get("ik_gap0", 0.0)
    E = tab["e"] + gap_err * tab["e1"]          # nk x muscles
    n_knots = int(round(cap["horizon"] / L.KNOT)) + 1
    K = np.vstack([np.clip(E, 0.0, 1.0)] + [np.clip(E[-1:], 0.0, 1.0)] * max(0, n_knots - nk))[:n_knots]
    json.dump({"name": cap_name, "plant": cap["plant"], "knots": {n: [float(v) for v in K[:, i]] for i, n in enumerate(body.muscles)}}, open(out, "w"))
    print("wrote", out, "gap_err %.3f" % gap_err, "knots", K.shape)

if __name__ == "__main__":
    main()
