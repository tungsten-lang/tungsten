"""Hand-set time-to-strike reflex on the weak (rolling-over) hand-overs (scratch, mine)."""
import sys, json, os
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
import long_jump_limits as L
from search import read_params
hset = "p95vfh"
hos = [h for h in L.load_handover(hset) if h["valid"]]
c0 = L.load_capture("p95pn_s0")
body = L.Body(c0["task"], c0["board_x"], json.loads(c0["env"]))
mus = body.muscles
kp, kd = L.reflex_gains(mus, json.loads(c0["params"]))
prog_file = "out/long_jump_limits/land_p95pn3.txt"
p = read_params(prog_file)
nk = int(round(p["il_n"]))
base_tab = L.read_il(prog_file, mus, c0["plant"], nk)
base_tab["tg"] = 0.61; base_tab["zl"] = 0.44387629375771404
def run(kc_roles, ctau, clt, label):
    tab = dict(base_tab)
    ckc = np.zeros(len(mus))
    for i, nm in enumerate(mus):
        r = L.role_of(nm, c0["plant"])
        if r in kc_roles: ckc[i] = kc_roles[r]
    if kc_roles:
        tab["ckc"], tab["ctau"], tab["clt"] = ckc, ctau, clt
    marks = []
    for i, ho in enumerate(hos):
        lead, delay = 0.004 * (i % 3), (i // 3) % 2
        prog = L.LandingProgram(tab, p["il_h"], p["il_ld"], p.get("j_il_g", 0.3), 1.0, kp, kd, lead, delay)
        r = L.run_landing(body, ho, prog, ho.get("t_left", 1.5))
        marks.append(L.landing_score(r, ho))
    print("%-44s" % label, " ".join("%6.2f" % m for m in marks), " names:", " ".join(h["name"][-4:] for h in hos) if label.startswith("none") else "", flush=True)
run({}, 0, 0, "none")
G = {"T_hip_flex_pos": 10, "F_hip_flex_pos": 10, "T_knee_pos": 10, "F_knee_pos": 10, "T_ankle_neg": 10, "F_ankle_neg": 10}
for ct in (0.15, 0.25):
    for k in (5, 10, 20):
        Gk = {r: v * k / 10 for r, v in G.items()}
        run(Gk, ct, 0.10, f"hip+knee+ankle x{k/10:.1f} ctau {ct}")
Gs = {"T_hip_flex_pos": 15, "F_hip_flex_pos": 15, "T_rf": 15, "F_rf": 15}
run(Gs, 0.2, 0.10, "hip flex + rf 15 ctau .2")
Gs = {"T_knee_pos": 15, "F_knee_pos": 15}
run(Gs, 0.2, 0.10, "knee flex 15 ctau .2")
