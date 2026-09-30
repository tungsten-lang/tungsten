"""Read-only probe of the compiled official TT P2 model for the oracle harness (agent T3): paddle geoms, contacts, arm joints, inertia."""
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
print("robot.mj_data is env.mj_data:", u.robot.mj_data is u.mj_data, "| robot.mj_model is env.mj_model:", u.robot.mj_model is u.mj_model)
print("obsd_mj_data is mj_data:", u.obsd_mj_data is u.mj_data)
pb = m.body("paddle").id
print("paddle body", pb, "mass", m.body_mass[pb], "inertia", m.body_inertia[pb], "parent", m.body_parentid[pb], "dofadr", m.body_dofadr[pb], "jntnum", m.body_jntnum[pb])
for g in range(m.ngeom):
    if m.geom_bodyid[g] == pb:
        print("paddle geom", g, m.geom(g).name, "type", m.geom_type[g], "size", m.geom_size[g], "contype", m.geom_contype[g], "conaff", m.geom_conaffinity[g], "pos", m.geom_pos[g], "priority", m.geom_priority[g], "solref", m.geom_solref[g], "friction", m.geom_friction[g])
bb = m.body("pingpong").id
for g in range(m.ngeom):
    if m.geom_bodyid[g] == bb:
        print("ball geom", g, m.geom(g).name, "contype", m.geom_contype[g], "conaff", m.geom_conaffinity[g], "size", m.geom_size[g], "solref", m.geom_solref[g], "friction", m.geom_friction[g], "priority", m.geom_priority[g])
print("ball mass", m.body_mass[bb])
print("n contact pairs (explicit):", m.npair, "exclude:", m.nexclude)
# which geoms have contype/conaffinity that could touch the paddle geoms
pad = m.geom("pad").id
cands = []
for g in range(m.ngeom):
    if g == pad: continue
    if (m.geom_contype[g] & m.geom_conaffinity[pad]) or (m.geom_contype[pad] & m.geom_conaffinity[g]):
        cands.append((g, m.geom(g).name, m.body(m.geom_bodyid[g]).name))
print("geoms that can collide with the pad:", cands)
# joint list of the arm
names = ["elv_angle","shoulder_elv","shoulder_rot","elbow_flexion","pro_sup","deviation","flexion","axial_rotation","flex_extension","lat_bending","pelvis_x","pelvis_y","paddle_freejoint","pingpong_freejoint"]
for n in names:
    j = m.joint(n).id
    print(f"joint {n:20s} id {j:3d} type {m.jnt_type[j]} qadr {m.jnt_qposadr[j]:3d} dadr {m.jnt_dofadr[j]:3d} range {m.jnt_range[j]} damping {m.dof_damping[m.jnt_dofadr[j]]:.3f} armature {m.dof_armature[m.jnt_dofadr[j]]:.4f} stiff {m.jnt_stiffness[j]}")
print("nv", m.nv, "nq", m.nq, "nu", m.nu, "nbody", m.nbody, "opt.timestep", m.opt.timestep, "integrator", m.opt.integrator, "noslip", m.opt.noslip_iterations)
# equality couplings
for e in range(m.neq):
    if m.eq_type[e] == mujoco.mjtEq.mjEQ_JOINT:
        a = m.joint(int(m.eq_obj1id[e])).name; b = m.joint(int(m.eq_obj2id[e])).name if m.eq_obj2id[e] >= 0 else None
        print("eq joint", a, "<-", b, "active0", m.eq_active0[e], "solref", m.eq_solref[e], "data", m.eq_data[e][:5])
    elif m.eq_type[e] == mujoco.mjtEq.mjEQ_WELD:
        print("eq weld", m.eq_obj1id[e], m.eq_obj2id[e], m.eq_active0[e])
print("mocap bodies:", m.nmocap)
print("S_grasp site", m.site("S_grasp").id, "body", m.body(m.site_bodyid[m.site("S_grasp").id]).name)
print("paddle site", m.site("paddle").id, m.site_pos[m.site("paddle").id], "pad geom pos", m.geom_pos[pad], "size", m.geom_size[pad])
