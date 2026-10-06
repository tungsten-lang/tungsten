"""com0_lj.py SEEDS OUT.json [TASK]: S6's com0.py (scratchpad/sprint6/com0.py) for any task (default run_v4): COM x minus the ankles' midpoint, pelvis pitch, trunk pitch of every perturbed start
(one model build, task.reset per seed), labelled beyond-human body. Main session, 3 Oct 2026 (L5): .venv/bin/python scratchpad/lj5/com0_lj.py 51001-51256 out/x.json long_jump_v4_beyond_a"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
os.environ["ROBOLAB_CALIB"] = "v4"
os.environ["ROBOLAB_PROFILE"] = "beyond"
os.environ["ROBOLAB_PROFILE_PARTS"] = "strength,speed,tendon,activation"
sys.path.insert(0, os.path.join(ROOT, "playground"))
import mujoco  # noqa: E402
from practice import load_task  # noqa: E402
from bridge import Sim  # noqa: E402


def parse_seeds(spec):
    out = []
    for tok in spec.split(","):
        tok = tok.strip()
        if "-" in tok:
            lo, hi = tok.split("-")
            out += list(range(int(lo), int(hi) + 1))
        elif tok:
            out.append(int(tok))
    return out


def main():
    seeds = parse_seeds(sys.argv[1])
    t = load_task(sys.argv[3] if len(sys.argv) > 3 else "run_v4")
    t.seed = seeds[0]
    sim = Sim(t, params={}, controller=os.path.abspath(os.path.join(ROOT, "bin", "challengers", "long_jump_run_y-l4b")))
    m, d = sim.m, sim.d
    pid, tid = m.body("pelvis").id, m.body("torso").id
    out = {}
    for s in seeds:
        mujoco.mj_resetData(m, d)
        t.seed = s
        t.reset(m, d)
        mujoco.mj_forward(m, d)
        mujoco.mj_subtreeVel(m, d)
        fx = 0.5 * (float(d.body("l_foot").xpos[0]) + float(d.body("r_foot").xpos[0]))
        com = float(d.subtree_com[pid][0])
        tu = d.xmat[tid].reshape(3, 3)[:, 2]
        pu = d.xmat[pid].reshape(3, 3)[:, 2]
        out[s] = {"com": com - fx, "torso_pitch": math.atan2(tu[0], tu[2]), "pelvis_pitch": math.atan2(pu[0], pu[2]),
                  "ankle_l": float(d.qpos[m.joint("l_ankle").qposadr[0]]), "ankle_r": float(d.qpos[m.joint("r_ankle").qposadr[0]]),
                  "pelvis_z": float(d.xpos[pid][2])}
    with open(sys.argv[2], "w") as f:
        json.dump(out, f)
    xs = sorted(v["com"] for v in out.values())
    print("n", len(xs), "COM-ankle at t=0: min %.3f p1 %.3f p5 %.3f median %.3f max %.3f" % (xs[0], xs[len(xs) // 100], xs[len(xs) // 20], xs[len(xs) // 2], xs[-1]))


if __name__ == "__main__":
    main()
