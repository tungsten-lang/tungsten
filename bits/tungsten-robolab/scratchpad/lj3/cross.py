"""Cross-application of per-state ideals (by role) to other captured states (harness, pure-time excitations, board-mode score). L3 scratch."""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj3")
import numpy as np
import long_jump_limits as L
import ljx

names = sys.argv[1].split(",")          # states that have a per-state ideal <state>_ps.json
caps = {n: L.load_capture(n) for n in names}
body = L.Body(caps[names[0]]["task"], caps[names[0]]["board_x"], json.loads(caps[names[0]]["env"]))
cfg = {"board": True, "margin": 0.03, "lmax": -1.5, "lmin": -15.0, "grfcap": 20.0, "grfw": 0.3, "td": 0.0, "tdw": 20.0}
print("rows: program of state A; columns: applied to state B (board-mode score; own state on the diagonal)")
print("%-10s" % "" + "".join("%9s" % n[-4:] for n in names))
for a in names:
    path = f"/Users/erik/tungsten/bits/tungsten-robolab/out/long_jump_limits/{a}_ps.json"
    row = []
    for b in names:
        X = ljx.init_knots(caps[b], body, path)
        r = ljx.simulate2(body, caps[b], lambda t, k: L.excitation(X, t))
        row.append(ljx.score2(r, caps[b], cfg))
    print("%-10s" % a[-4:] + "".join("%9.2f" % s for s in row))
