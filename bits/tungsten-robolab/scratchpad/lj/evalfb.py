"""Per-start harness scores of a take-off program file (with feedback) on the captured starts (scratch, mine)."""
import sys, json, os, glob
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
import long_jump_limits as L
prog_file = sys.argv[1]; prefix = sys.argv[2]; stride = int(sys.argv[3]); delta = float(sys.argv[4])
names = sorted(os.path.basename(p)[:-len("_capture.npz")] for p in glob.glob(f"out/long_jump_limits/{prefix}_s*_capture.npz"))[::stride]
caps = [L.load_capture(n) for n in names]
body = L.Body(caps[0]["task"], caps[0]["board_x"], json.loads(caps[0]["env"]))
mus = body.muscles
kp, kd = L.reflex_gains(mus, json.loads(caps[0]["params"]))
p, _ = L.read_ik(prog_file, mus, "r")
rows = []
for name, cap in zip(names, caps):
    pf, tab = L.read_ik(prog_file, mus, cap["plant"])
    prog = L.IKProgram(tab, pf["ik_h"], pf["ik_td"], pf["j_ik_g"], pf.get("j_ik_kdc", 1.0), kp, kd, pf["ik_gap0"], pf["ik_end"])
    r = L.simulate_prog(body, cap, prog)
    if r["valid"]:
        over = r["toe_max"] - (cap["board_x"] + delta)
        rows.append((name, cap["plant"], r["vz"], r["vx"], r["L"], r["torso_pitch"], r["D"] - (cap["board_x"] + delta - r["toe_max"]), over))
    else:
        rows.append((name, cap["plant"], None, None, None, None, None, r.get("why")))
bad = [r for r in rows if r[2] is None or r[7] > 0 if not isinstance(r[7], str) or True]
print("n", len(rows))
for r in rows:
    if r[2] is None or (not isinstance(r[7], str) and r[7] > 0) or (r[2] is not None and (r[4] > -1.0 or r[2] < 2.4)):
        print(r)
v = [r for r in rows if r[2] is not None]
print("valid", len(v), "vz mean %.2f min %.2f; L mean %.1f max %.1f; pitch mean %.2f max %.2f; D mean %.3f min %.2f" % (
    np.mean([r[2] for r in v]), min(r[2] for r in v), np.mean([r[4] for r in v]), max(r[4] for r in v),
    np.mean([r[5] for r in v]), max(r[5] for r in v), np.mean([r[6] for r in v]), min(r[6] for r in v)))
