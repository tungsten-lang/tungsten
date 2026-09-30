"""Read-only probe 2 (agent T3): explicit contact pairs, exclusions, paddle/ball contact params, effective arm inertia at reset."""
import os, sys
os.environ.setdefault("TT_ENV", "P2")
HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(HERE, "playground"))
import numpy as np, mujoco
np.set_printoptions(precision=4, suppress=True, linewidth=200)
from myosuite.utils import gym
env = gym.make("myoChallengeTableTennisP2-v0")
u = env.unwrapped
m = u.mj_model
for i in range(m.npair):
    g1, g2 = int(m.pair_geom1[i]), int(m.pair_geom2[i])
    print("pair", i, m.geom(g1).name or g1, m.body(m.geom_bodyid[g1]).name, "|", m.geom(g2).name or g2, m.body(m.geom_bodyid[g2]).name, "condim", m.pair_dim[i], "margin", m.pair_margin[i], "gap", m.pair_gap[i], "solref", m.pair_solref[i], "friction", m.pair_friction[i])
print("excludes:", [(m.body(int(m.exclude_signature[i] >> 16)).name, m.body(int(m.exclude_signature[i] & 0xFFFF)).name) for i in range(m.nexclude)] if hasattr(m, "exclude_signature") else "n/a")
print("opt: o_solref", m.opt.o_solref, "o_margin", m.opt.o_margin, "noslip", m.opt.noslip_iterations, "cone", m.opt.cone, "iterations", m.opt.iterations, "tolerance", m.opt.tolerance, "impratio", m.opt.impratio)
print("paddle geom quats: pad", m.geom_quat[m.geom("pad").id], "handle", m.geom_quat[m.geom("handle").id], " paddle body ipos", m.body_ipos[m.body("paddle").id], "iquat", m.body_iquat[m.body("paddle").id])
print("table geoms:", [(g, m.geom(g).name, m.geom_contype[g], m.geom_conaffinity[g], m.geom_solref[g]) for g in (308, 309, 310)])
d = u.robot.mj_data
mujoco.mj_forward(m, d)
M = np.zeros((m.nv, m.nv)); mujoco.mj_fullM(m, M, d.qM)
for n in ["elv_angle","shoulder_elv","shoulder_rot","elbow_flexion","pro_sup","deviation","flexion","axial_rotation","pelvis_x","pelvis_y"]:
    a = m.jnt_dofadr[m.joint(n).id]
    print(f"M[{n}] = {M[a,a]:.4f}")
print("reset qpos of arm joints:", {n: round(float(d.qpos[m.jnt_qposadr[m.joint(n).id]]), 3) for n in ["elv_angle","shoulder_elv","shoulder_rot","elbow_flexion","pro_sup","deviation","flexion"]})
print("key_qpos[0] paddle qpos", m.key_qpos[0][58:65], "ball", m.key_qpos[0][65:72])
