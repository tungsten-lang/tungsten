"""Gap (board - penultimate toe), plant side, COM speed and pitch of the captured penultimate-touchdown states.
usage: gapscan.py <prefix> <count>"""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import long_jump_limits as L
import long_jump_mine as M


def main():
    prefix, count = sys.argv[1], int(sys.argv[2])
    body = None
    for i in range(count):
        name = f"{prefix}{i}"
        try:
            cap = L.load_capture(name)
        except Exception:
            continue
        if body is None:
            body = L.Body(cap["task"], cap["board_x"], json.loads(cap["env"]))
        f = M.features(body, cap)
        print("%-8s board %.4f plant %s gap %.3f vx %.2f vz %.2f com_z %.3f torso %.2f swing_ahead %.2f t0 %.3f" % (
            name, cap["board_x"], cap["plant"], f["gap"], f["vx"], f["vz"], f["com_z"], f["torso"], f["swing_ahead"], float(cap["t0"])))


main()
