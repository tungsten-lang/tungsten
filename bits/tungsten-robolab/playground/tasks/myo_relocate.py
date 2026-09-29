"""MyoChallenge 2023 Relocate, phase 2 (myoArm: 63 muscles, 27 DoF).

Pick the randomised object (sphere / capsule / ellipsoid / cylinder / box,
1.5-2.5 cm half-sizes, 50-200 g, random friction) off the table and put it
in the receptacle within the 1.5 s episode (150 steps of 10 ms).

Official scoring (relocate_v0.RelocateEnvV0): a step is `solved` when the
object is within pos_th = 0.1 m of the receptacle centre (rot_th = inf in
phase 2, so orientation is ignored) and the palm is within 0.5 m of the
object (drop_th; farther terminates the episode). An episode succeeds when
more than 5 steps are solved (get_metrics, successful_steps=5); the score is
the success rate. Effort is reported as MyoSuite's act_reg (|act| / na) and
as the mean squared muscle activation.

Note (MyoSuite 2.12.2): the receptacle body is `mocap="true"`, so in the
observed and scored MjData (`env.mj_data`) reset()'s `body_pos` write is a
no-op and the goal always sits at (0, -0.25, 0.9). But the MjData that
mj_step advances (`env.robot.mj_data`) takes its mocap pose from that write:
the physical receptacle stands, invisible, at the randomised target pose
(P2: x 0..0.3, y -0.45..-0.1; see tasks/myo_relocate_v6.py), and the
visible one has no walls in the physics.

Sensors added for the skill (all read from the body's own state):
  palm_jac  3 x 7 palm-site Jacobian for ARM_JOINTS (row per joint, x y z),
            with the shoulder-girdle joint couplings folded in
  touch     hand-object contact normal force (N) per group
            [thumb, index, middle, ring, little, palm]
  touch_pos force-weighted centroid of the hand-object contacts (world, m;
            zeros when nothing touches): where the hand feels the object
  obj_vel   object linear velocity (m/s)
  tips      thumb-, index- and middle-tip positions (9)
"""

import numpy as np
import mujoco

from myo_bridge import MyoTask

LIFT_Z = 1.08  # object site height that counts as lifted to the rim (1.10 m)
RIM_Z = 1.10  # top of the receptacle's walls
RIM_HALF = 0.09  # receptacle footprint half-width (wall mid-lines at +-0.091 from its centre)
ARM_JOINTS = ["elv_angle", "shoulder_elv", "shoulder_rot", "elbow_flexion", "pro_sup", "deviation", "flexion"]
TOUCH_GROUPS = [
    ("thumb", ["firstmc", "proximal_thumb", "distal_thumb"]),
    ("index", ["proxph2", "midph2", "distph2"]),
    ("middle", ["proxph3", "midph3", "distph3"]),
    ("ring", ["proxph4", "midph4", "distph4"]),
    ("little", ["proxph5", "midph5", "distph5"]),
    ("palm", ["secondmc", "thirdmc", "fourthmc", "fifthmc", "lunate", "scaphoid", "pisiform",
              "triquetrum", "capitate", "trapezium", "trapezoid", "hamate"]),
]


class RelocateCache:
    """Model ids the sensors need, built once per MyoSim."""

    def __init__(self, sim):
        m = sim.m
        self.palm = m.site("S_grasp").id
        self.obj_body = m.body("Object").id
        self.tips = [m.site("THtip").id, m.site("IFtip").id, m.site("MFtip").id]
        self.dof = [m.jnt_dofadr[m.joint(n).id] for n in ARM_JOINTS]
        # joint-equality couplings: dependent dof follows c1 * independent dof
        self.follow = {}
        for i in range(m.neq):
            if m.eq_type[i] == mujoco.mjtEq.mjEQ_JOINT and m.eq_active0[i] and m.eq_obj2id[i] >= 0:
                a = m.jnt_dofadr[m.eq_obj1id[i]]
                b = m.jnt_dofadr[m.eq_obj2id[i]]
                self.follow.setdefault(b, []).append((a, float(m.eq_data[i][1])))
        self.group = {}
        for k, (_, names) in enumerate(TOUCH_GROUPS):
            for n in names:
                self.group[m.body(n).id] = k
        self.obj_dofs = [m.jnt_dofadr[m.joint(n).id] for n in ("OBJTx", "OBJTy", "OBJTz")]
        self.jac = np.zeros((3, m.nv))
        self.jr = np.zeros((3, m.nv))
        self.force = np.zeros(6)


def episode_store(sim):
    """Per-episode scratch on the sim (reset by myo_manip.ReuseSim)."""
    ep = getattr(sim, "_ep", None)
    if ep is None:
        ep = sim._ep = {}
    return ep


def cache(sim):
    c = getattr(sim, "_relocate_cache", None)
    if c is None:
        c = sim._relocate_cache = RelocateCache(sim)
    return c


def palm_jacobian(sim, c):
    m, d = sim.m, sim.d
    mujoco.mj_jacSite(m, d, c.jac, c.jr, c.palm)
    out = []
    for dof in c.dof:
        col = c.jac[:, dof].copy()
        for dep, k in c.follow.get(dof, []):
            col += k * c.jac[:, dep]
        out.extend(col)
    return out


def hand_touch(sim, c, where=None):
    """Hand-object contact normal force per touch group; with `where` (a
    length-3 array) also the force-weighted contact centroid (world frame,
    zeros when nothing touches): where on the hand the object is felt."""
    m, d = sim.m, sim.d
    out = np.zeros(len(TOUCH_GROUPS))
    acc, wsum = np.zeros(3), 0.0
    for i in range(d.ncon):
        con = d.contact[i]
        b1, b2 = m.geom_bodyid[con.geom1], m.geom_bodyid[con.geom2]
        if b1 == c.obj_body:
            other = b2
        elif b2 == c.obj_body:
            other = b1
        else:
            continue
        k = c.group.get(other)
        if k is None:
            continue
        mujoco.mj_contactForce(m, d, i, c.force)
        f = abs(c.force[0])
        out[k] += f
        acc += f * con.pos
        wsum += f
    if where is not None:
        where[:] = acc / wsum if wsum > 1e-9 else 0.0
    return out


class MyoRelocateTask(MyoTask):
    name = "myo_relocate"
    env_id = "myoChallengeRelocateP2-v0"
    coupled_geometry = True
    geometry_pairs = True  # joint-pair length corrections for the finger-crossing muscles
    forward_keys = ["obj_pos", "goal_pos", "palm_pos"]

    def extra_sensors(self, sim):
        c = cache(sim)
        d = sim.d
        where = np.zeros(3)
        return [
            ("palm_jac", palm_jacobian(sim, c)),
            ("touch", hand_touch(sim, c, where)),
            ("touch_pos", where),
            ("obj_vel", d.qvel[c.obj_dofs]),
            ("tips", np.concatenate([d.site_xpos[t] for t in c.tips])),
        ]

    def on_command(self, sim, cmd):
        if cmd.startswith("dbg:"):
            sim._dbg = cmd[4:]

    def on_step(self, sim, obs, reward, info):
        ep = episode_store(sim)
        ep.setdefault("act_sq", []).append(float(np.mean(sim.d.act ** 2)))
        # per-step object and palm positions, copied now: MyoSuite's obs_dict
        # entries obj_pos / palm_pos / goal_pos are views into mj_data, so the
        # copies kept in each step's info all read the final state
        od = sim.u.obs_dict
        ep.setdefault("obj", []).append(np.array(od["obj_pos"], dtype=float))
        ep.setdefault("palm", []).append(np.array(od["palm_pos"], dtype=float))
        if "goal" not in ep:
            ep["goal"] = [np.array(od["goal_pos"], dtype=float)]
        # grasp quality, for shaping the search: where the pinch point (thumb
        # tip halfway to the index and middle tips) is when the hand starts to
        # close, and how hard the hand then holds the object
        if "close" in sim.label or "lift" in sim.label:
            c = cache(sim)
            d = sim.d
            if "pinch_err" not in ep:
                pinch = 0.5 * d.site_xpos[c.tips[0]] + 0.25 * (d.site_xpos[c.tips[1]] + d.site_xpos[c.tips[2]])
                o = sim.u.obs_dict["obj_pos"]
                ep["pinch_err"] = float(np.linalg.norm(pinch[:2] - o[:2]))
                ep["pinch_z"] = float(pinch[2])
                # diagnostics only (never sensed by the controller): the
                # object's true centre, the volume-weighted mean of its geoms
                m = sim.m
                g0 = m.body_geomadr[c.obj_body]
                gs = range(g0, g0 + m.body_geomnum[c.obj_body])
                vol = np.array([np.prod(m.geom_size[g]) for g in gs])
                ctr = np.sum([v * d.geom_xpos[g] for v, g in zip(vol, gs)], axis=0) / vol.sum()
                ep["pinch_err_true"] = float(np.linalg.norm(pinch[:2] - ctr[:2]))
                ep["site_offset"] = float(np.linalg.norm(o[:2] - ctr[:2]))
            ep["touch_max"] = max(ep.get("touch_max", 0.0), float(np.sum(hand_touch(sim, c))))

    def trace_row(self, sim, info):
        od = sim.u.obs_dict
        t = hand_touch(sim, cache(sim))
        f = lambda v: " ".join(f"{x:6.3f}" for x in v)
        c = cache(sim)
        o = od["obj_pos"]
        th = sim.d.site_xpos[c.tips[0]] - o
        ix = sim.d.site_xpos[c.tips[1]] - o
        if getattr(self, "trace_joints", False):
            names = ["pro_sup", "deviation", "flexion", "mcp2_flexion", "pm2_flexion", "md2_flexion",
                     "cmc_abduction", "cmc_flexion", "mp_flexion", "ip_flexion"]
            q = [sim.d.qpos[sim.m.jnt_qposadr[sim.m.joint(n).id]] for n in names]
            return f"q[ps dev flex mcp pip dip | cabd cflex mp ip] {f(q)} touch {f(t)} th-obj {f(th)} if-obj {f(ix)}"
        return (f"palm-obj {f(od['palm_pos'] - o)} th-obj {f(th)} if-obj {f(ix)} obj {f(o)} touch {f(t)} "
                f"dist {float(np.linalg.norm(od['pos_err'])):.3f} ok {int(info['rwd_dict']['solved'])} {getattr(sim, '_dbg', '')}")

    def metrics(self, sim, log):
        infos = sim.infos
        solved = [float(i["rwd_dict"]["solved"]) for i in infos]
        pos = [-float(i["rwd_dict"]["pos_dist"]) for i in infos]
        act_reg = [-float(i["rwd_dict"]["act_reg"]) for i in infos]
        ep = episode_store(sim)
        obj = np.array(ep.get("obj", [np.zeros(3)]))
        palm = np.array(ep.get("palm", [np.zeros(3)]))
        objz = obj[30:, 2]  # after the drop
        # height the object reached while still in (or at) the hand: a throw
        # does not count as a lift
        near = np.linalg.norm(palm - obj, axis=1)[30:] < 0.1
        held_z = objz[near]
        n_solved = int(np.sum(solved))
        # genuine placement: solved steps only after the object has been
        # lifted to the rim (the receptacle's walls do not reliably collide
        # with the randomised object, so objects can also be slid into the
        # box at table height; the official test counts those too)
        lifted, n_lift, d_lift = False, 0, 1.0
        for k, i in enumerate(infos):
            lifted = lifted or (k < len(obj) and obj[k, 2] > LIFT_Z)
            n_lift += int(lifted and bool(i["rwd_dict"]["solved"]))
            if lifted:
                d_lift = min(d_lift, -float(i["rwd_dict"]["pos_dist"]))
        # strict placement: the object first crosses into the receptacle's
        # footprint with its centre above the rim (it came in over the wall,
        # not through it at table height and then up)
        goal = np.array(ep.get("goal", [np.array([0.0, -0.25, 0.9])])[0])
        inside = (np.abs(obj[:, 0] - goal[0]) < RIM_HALF) & (np.abs(obj[:, 1] - goal[1]) < RIM_HALF)
        entry_z = float(obj[int(np.argmax(inside)), 2]) if inside.any() else 0.0
        return {
            "success": float(n_solved > 5),
            "solved_steps": n_solved,
            "success_lift": float(n_lift > 5),
            "success_placed": float(n_solved > 5 and entry_z >= RIM_Z),
            "entry_z": round(entry_z, 4),
            "min_dist_lift": round(d_lift, 4),
            "min_dist": round(float(np.min(pos)), 4) if pos else 1.0,
            "final_dist": round(float(pos[-1]), 4) if pos else 1.0,
            "max_obj_z": round(float(np.max(objz)), 4) if len(objz) else 0.0,
            "max_held_z": round(float(np.max(held_z)), 4) if len(held_z) else 0.9,
            "effort_official": round(float(np.mean(act_reg)), 5) if act_reg else 0.0,
            "act_sq": round(float(np.mean(episode_store(sim).get("act_sq", [0.0]))), 5),
            "pinch_err": round(episode_store(sim).get("pinch_err", 0.2), 4),
            "pinch_z": round(episode_store(sim).get("pinch_z", 1.2), 4),
            "pinch_err_true": round(episode_store(sim).get("pinch_err_true", 0.2), 4),
            "site_offset": round(episode_store(sim).get("site_offset", 0.0), 4),
            "touch_max": round(episode_store(sim).get("touch_max", 0.0), 2),
        }

    def score(self, metrics):
        # genuine placement first, the official test second, then shaping:
        # the object lifted toward the rim, and (once lifted) brought close
        lift = min(1.0, max(0.0, (metrics.get("max_held_z", 0.9) - 0.91) / 0.2))
        near = max(0.0, 1.0 - metrics.get("min_dist_lift", 1.0) / 0.3)
        # grasp shaping: the pinch centred on the object and low when it closes,
        # and a firm hold
        aim = max(0.0, 1.0 - metrics.get("pinch_err", 0.2) / 0.05)
        low = max(0.0, 1.0 - max(0.0, metrics.get("pinch_z", 1.2) - 0.92) / 0.08)
        grip = min(1.0, metrics.get("touch_max", 0.0) / 10.0)
        return (metrics.get("success_lift", 0.0) + 0.05 * metrics.get("success", 0.0)
                + 0.5 * lift + 0.3 * near + 0.15 * aim + 0.1 * low + 0.1 * grip)

    zoom = False

    def camera(self, m, d, cam):
        # front-left of the table, looking over the object toward the box
        cam.lookat[:] = [-0.1, -0.27, 1.0]
        cam.distance = 0.85
        cam.azimuth = 60
        cam.elevation = -28
        if self.zoom:
            cam.lookat[:] = d.site_xpos[m.site("object_o").id]
            cam.distance = getattr(self, "zoom_dist", 0.35)
            cam.azimuth = getattr(self, "zoom_az", cam.azimuth)
            cam.elevation = getattr(self, "zoom_el", cam.elevation)

    def hud_text(self, m, d):
        o = d.site_xpos[m.site("object_o").id]
        g = d.site_xpos[m.site("target_o").id]
        return f"object-to-box {np.linalg.norm(g - o):.3f} m (solved < 0.100)   object z {o[2]:.3f}"

    def title(self):
        return f"robolab relocate on {self.env_id}"


TASK = MyoRelocateTask
