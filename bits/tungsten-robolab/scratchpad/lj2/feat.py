"""Approach-state features at the penultimate touchdown of captures (L2 scratch).
usage: feat.py <capture> [<capture> ...]   (names without _capture.npz)"""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import long_jump_limits as L
import long_jump_mine as M

def main():
    names = sys.argv[1:]
    c0 = L.load_capture(names[0])
    body = L.Body(c0["task"], c0["board_x"], json.loads(c0["env"]))
    print("name             torso  rate   pel    z     vx    vz    Ly   gap   swing  sz  plant")
    for nm in names:
        c = L.load_capture(nm)
        f = M.features(body, c)
        print("%-16s %5.2f %5.2f %5.2f %5.2f %5.2f %5.2f %5.1f %5.2f %5.2f %4.2f  %s" % (
            nm, f["torso"], f["torso_rate"], f["pelvis"], f["com_z"], f["vx"], f["vz"], f["Ly"], f["gap"], f["swing_ahead"], f["swing_z"], c["plant"]))

if __name__ == "__main__":
    main()
