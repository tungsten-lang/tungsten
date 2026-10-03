"""Hand-overs of a take-off program WITH regime tails (agent L4): a copy of long_jump_limits.handover that runs RegimeIK (scratchpad/lj4/rgprog.py) so the landing search
sees the states the skill (long_jump_run_y-l4b with the ik_rg keys) hands over. Same output file format (out/long_jump_limits/<name>_handover.npz).
usage: ho_tail.py <program.txt> --captures a,b,c --name N [--variants 1] [--tails t1.npz,t2.npz --t1 0.20 --t2 0.26]"""
import argparse, json, os, sys
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj3")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj4")
import numpy as np
import mujoco
import long_jump_limits as L
import rgprog, ljx_tail
from search import read_params

ap = argparse.ArgumentParser()
ap.add_argument("program")
ap.add_argument("--captures", required=True)
ap.add_argument("--name", required=True)
ap.add_argument("--variants", type=int, default=0)
ap.add_argument("--tails", default="")
ap.add_argument("--t1", type=float, default=0.20)
ap.add_argument("--t2", type=float, default=0.26)
a = ap.parse_args()
names0 = [n for n in a.captures.split(",") if n]
caps = [L.load_capture(n) for n in names0]
body = L.Body(caps[0]["task"], caps[0]["board_x"], json.loads(caps[0]["env"]))
kp, kd = L.reflex_gains(body.muscles, json.loads(caps[0]["params"]))
pf = read_params(a.program)
nk = int(round(pf["ik_n"]))
size = mujoco.mj_stateSize(body.m, L.SPEC)
n = len(body.muscles)
nd = len(rgprog.TAU_KNOTS)
perm = L.side_perm(body.muscles)
p0 = None
rg = None
if a.tails:
    de, dc = {}, {}
    for pth in a.tails.split(","):
        z = np.load(pth)
        names_t = [str(x) for x in z["names"]]
        p0 = L.load_capture(names_t[0])["plant"]
        d1, c1 = ljx_tail.decode(z["x"], [int(z["regime"])], nd, n)
        de.update(d1); dc.update(c1)
    rg = {"t1": a.t1, "t2": a.t2, "knots": rgprog.TAU_KNOTS, "de": de, "dc": dc}
jobs = []
for nm, cap in zip(names0, caps):
    jobs.append((nm, cap, 0))
    for v in range(1, a.variants + 1):
        jobs.append((f"{nm}_v{v}", cap, v))
names = [j[0] for j in jobs]
out = {}
for nm, cap, v in jobs:
    _, tab = L.read_ik(a.program, body.muscles, cap["plant"], nk=nk)
    g = pf["j_ik_g"]
    if v:
        rng = np.random.default_rng(1000 * v + (abs(hash(nm)) % 997))
        tab = dict(tab)
        tab["e"] = tab["e"] * rng.normal(1.0, 0.03, tab["e"].shape[1])[None, :]
        g = g * float(rng.normal(1.0, 0.1))
    rgc = None
    if rg is not None:
        rgc = dict(rg)
        if cap["plant"] != p0:
            rgc["de"] = {r: arr[:, perm] for r, arr in rg["de"].items()}
            rgc["dc"] = {r: arr[:, perm] for r, arr in rg["dc"].items()}
    prog = rgprog.RegimeIK(tab, pf["ik_h"], pf["ik_td"], g, pf.get("j_ik_kdc", 1.0), kp, kd, pf["ik_gap0"], pf["ik_end"], rgc)
    r = L.simulate_prog(body, cap, prog)
    st = np.zeros(size)
    mujoco.mj_getState(body.m, body.d, st, L.SPEC)
    t_left = float(body.task.seconds) - float(body.d.time)
    foul = (not r["valid"]) or r["toe_max"] > cap["board_x"]
    out[nm] = {"state": st, "board_x": cap["board_x"], "foul": bool(foul), "valid": r["valid"], "t_left": t_left, "plant": cap["plant"],
               "D_board": (r["D"] - (cap["board_x"] - r["toe_max"])) if r["valid"] else None,
               "vx": r.get("vx"), "vz": r.get("vz"), "contact_s": r.get("contact_s"), "L": r.get("L"),
               "leg_angle_deg": r.get("td", {}).get("leg_angle_deg"), "toe_max": r.get("toe_max"),
               "torso_pitch": r.get("torso_pitch"), "why": r.get("why")}
    print(nm, {k: (round(x, 3) if isinstance(x, float) else x) for k, x in out[nm].items() if k != "state"}, "regime", getattr(prog, "regime", 0))
np.savez(os.path.join(L.OUT, f"{a.name}_handover.npz"), names=json.dumps(names),
         **{f"state_{i}": out[nm]["state"] for i, nm in enumerate(names)},
         meta=json.dumps({nm: {k: x for k, x in out[nm].items() if k != "state"} for nm in names}))
print("wrote", os.path.join(L.OUT, f"{a.name}_handover.npz"), len(names), "hand-overs")
