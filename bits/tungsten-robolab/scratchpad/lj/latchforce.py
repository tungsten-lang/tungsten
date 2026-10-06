"""First-contact forces of the plant foot in the harness, per start (scratch, mine)."""
import sys, json, os, glob
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
import long_jump_limits as L
names = sorted(os.path.basename(p)[:-len("_capture.npz")] for p in glob.glob("out/long_jump_limits/p95mn_s*_capture.npz"))
caps = [L.load_capture(n) for n in names]
body = L.Body(caps[0]["task"], caps[0]["board_x"], json.loads(caps[0]["env"]))
mus = body.muscles; n = len(mus)
kp, kd = L.reflex_gains(mus, json.loads(caps[0]["params"]))
pfile, base = L.read_ik("out/long_jump_run/p95pn_ik.txt", mus, caps[0]["plant"])
class Rec(L.IKProgram):
    def start(self, body, cap):
        super().start(body, cap); self.log = []
    def __call__(self, body, t, k):
        f = self.foot_force(body)
        self.log.append((t, f, self.td_seen))
        return super().__call__(body, t, k)
rows = []
for name, cap in zip(names, caps):
    prog = Rec(base, pfile["ik_h"], pfile["ik_td"], pfile["j_ik_g"], 1.0, kp, kd, pfile["ik_gap0"], pfile["ik_end"])   # fmin 0.05 (the base)
    r = L.simulate_prog(body, cap, prog)
    first = None; peak = 0
    for t, f, seen in prog.log:
        if f > 0.05 and t > 0.03 and first is None:
            first = (t, f)
        if first is not None and t < first[0] + 0.03: peak = max(peak, f)
    rows.append((name, r["valid"], first))
ff = np.array([r[2][1] for r in rows if r[2] is not None and r[1]])
print("valid starts: first-tick plant force (BW) min %.2f p5 %.2f median %.2f max %.2f" % (ff.min(), np.percentile(ff, 5), np.median(ff), ff.max()))
print("lowest 8:", sorted([(round(r[2][1], 2), r[0][-5:], round(r[2][0], 3)) for r in rows if r[2] is not None and r[1]])[:8])
print("invalid (fmin 0.05):", [(r[0][-5:], None if r[2] is None else (round(r[2][0], 3), round(r[2][1], 2))) for r in rows if not r[1]])
for nm in ("p95mn_s8045", "p95mn_s8130", "p95mn_s8161", "p95mn_s8162"):
    r = [x for x in rows if x[0] == nm][0]
    print(nm, "valid at fmin .05:", r[1], "first contact", r[2])
