"""ffcoef (L7): regression of the harness toe offset (legal states) on the penultimate-touchdown state; prints FF_* environment settings for ffeval.py.
usage: ffcoef.py rows.json [authority=0.69]"""
import json, os, sys
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
import long_jump_limits as L
import long_jump_mine as M
rows = json.load(open(sys.argv[1])); auth = float(sys.argv[2]) if len(sys.argv) > 2 else 0.69
body = None; feat = []
for r in rows:
    if not r["valid"] or r["s"] <= 0 or r.get("foul"): continue
    cap = L.load_capture(r["name"])
    if body is None: body = L.Body(cap["task"], cap["board_x"], json.loads(cap["env"]))
    f = M.features(body, cap)
    feat.append((r["off"], f["gap"], f["vx"], f["vz"], f["torso"]))
A = np.array(feat)
X = np.column_stack([A[:, 1:], np.ones(len(A))])
c = np.linalg.lstsq(X, A[:, 0], rcond=None)[0]
res = A[:, 0] - X @ c
m = A[:, 1:].mean(axis=0)
print("n %d, off sd %.4f, resid sd %.4f; coef gap %.3f vx %.3f vz %.3f torso %.3f; means gap %.4f vx %.4f vz %.4f torso %.4f" % (len(A), A[:, 0].std(), res.std(), c[0], c[1], c[2], c[3], m[0], m[1], m[2], m[3]), file=sys.stderr)
print("export FF_B0=%.5f FF_BG=%.5f FF_BV=%.5f FF_BZ=%.5f FF_BT=%.5f" % (c[4], c[0], c[1], c[2], c[3]))
print("export FF_CG=%.4f FF_CV=%.4f FF_CZ=%.4f FF_CT=%.4f FF_GM=%.5f FF_VM=%.5f FF_ZM=%.5f FF_TM=%.5f" % (-c[0] / auth, -c[1] / auth, -c[2] / auth, -c[3] / auth, m[0], m[1], m[2], m[3]))
