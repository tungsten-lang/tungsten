"""Debug (agent T3): backhand emitted targets vs the controller's posture map at the params' backhand ready posture."""
import os, sys
os.environ.setdefault("TT_ENV", "P2"); os.environ["TT_TASK"] = "myo_tt_oracle"; os.environ["MYO_TT_ORACLE"] = "rec"
HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(HERE, "playground"))
import numpy as np
np.set_printoptions(precision=3, suppress=True, linewidth=220)
import tt_fast
from tasks import myo_tt_oracle as mto
params = tt_fast.read_params("params/myo_tt_p2_r10_c3.txt")
ctl = os.path.abspath("bin/challengers/myo_tt_r10-n")
seed = int(sys.argv[1]) if len(sys.argv) > 1 else 98000
task = mto.TASK(); task.env_id = "myoChallengeTableTennisP2-v0"
sim = tt_fast.make_sim(task, params, seed, controller=ctl)
snap = {}
orig = sim.tick
def tick():
    r = orig()
    t = sim.d.time
    for tt in (0.10, 0.27, 0.40, 0.50, 0.60):
        if abs(t - tt) < 0.005 and tt not in snap:
            snap[tt] = (np.array(sim.targets).copy(), getattr(sim, "tt_side", 0))
    return r
sim.tick = tick
res = sim.run()
print("solved", res.get("solved"), "side", res.get("side"))
o = sim._orc
names = [mu.name for mu in sim.muscles]
fit = o.fit_bh if res.get("side") == 2 else o.fit
p = params
q_bh = np.array([p[k] for k in ("bh_elv", "bh_sh_elv", "bh_sh_rot", "bh_elbow", "bh_pro_sup", "bh_dev", "bh_wflex")])
q_fh = np.array([p[k] for k in ("elv", "sh_elv", "sh_rot", "elbow", "pro_sup", "dev", "wflex")])
cbh, _ = fit.model(q_bh); cfh, _ = fit.model(q_fh)
arm = fit.arm
print("stiff", p.get("stiff"), "bh_stiff", p.get("bh_stiff"))
for tt, (tg, sd) in sorted(snap.items()):
    c = tg[arm]
    print(f"t {tt}: rms(target - c_model(bh params) - stiff/2) {np.sqrt(np.mean((c - cbh - 0.5*p.get('bh_stiff', p['stiff']))**2)):.3f} | vs c_model(fh params) {np.sqrt(np.mean((c - cfh - 0.5*p['stiff'])**2)):.3f}")
tg = snap[0.60][0][arm]
print("muscle: target(0.6) c_model(bh)+stiff/2  c_model(fh)+stiff/2")
for k, i in enumerate(arm):
    print(f"  {names[i]:8s} {tg[k]:+.3f} {cbh[k] + 0.5*p.get('bh_stiff', p['stiff']):+.3f} {cfh[k] + 0.5*p['stiff']:+.3f}")
