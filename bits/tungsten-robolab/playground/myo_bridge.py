"""robolab <-> MyoSuite: drive MyoChallenge bodies with a robolab controller.

MyoSuite (github.com/MyoHub/myosuite) ships the MyoChallenge environments:
full musculoskeletal models (80-290 MuJoCo muscles on wrapped tendons) with
the official task logic and scoring. This bridge wraps one of those
environments and speaks the same robolab line protocol as bridge.py, so a
Tungsten skill drives a MyoSuite body exactly as it drives the robolab
humanoid. Run it with the MyoSuite venv (numpy < 2, mujoco 3.6):

    .venv-myo/bin/python playground/myo_bridge.py myo_tabletennis --video out/tt.mp4

Protocol additions (all backward compatible):

    JOINT <j> <name> <qmin> <qmax> <qref> <k>
        a body joint; <k> length samples per muscle are taken at k evenly
        spaced angles over [qmin, qmax], all other joints at the reference
        posture qref
    MLEN <i> <j> <L_0> ... <L_{k-1}>
        muscle i's length as joint j sweeps its range (only for joints the
        muscle crosses); length is additive over joints, which is how the
        controller turns a posture (an equilibrium point) into contractions
    MRANGE <i> <Lmin> <Lmax> <Lref>
        muscle i's length range and its length at the reference posture
    MPAIR <i> <a> <b> <s> <v_00> ... <v_(s-1)(s-1)>
        optional (task.geometry_pairs): muscle i's length residual over joints
        a and b on an s x s grid spanning both ranges (row-major, a first),
        beyond the additive model; sent only for muscles it measurably helps
    MFORCE <i> <F>
        muscle i's peak isometric force (N); with the `bias` sensor block (gravity
        and Coriolis torque per joint) it lets the controller add an internal-model
        feed-forward (Controller#enable_feedforward)
    MOTOR <k> <name> <lo> <hi>
        a non-muscle actuator; the controller sets it with the command
        `motor:<name>:<value>` in env action units (it holds until changed)

Each MUSCLE line names the muscle's primary joint (largest moment arm at the
reference posture) and the direction it pulls it, so simple pos/neg tools
still work.
"""

import argparse
import importlib
import json
import math
import os
import subprocess
import sys
import time

os.environ.setdefault("MUJOCO_GL", "cgl")

import mujoco  # noqa: E402
import numpy as np  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SAMPLES = 9
FORWARD_KEYS_EXCLUDE = {"time", "act", "internal_qpos", "internal_qvel", "muscle_length",
                        "muscle_velocity", "muscle_force", "body_qpos", "body_qvel", "hfield"}


class MyoMuscle:
    def __init__(self, name, act_id, joint, sign, qmin, qmax, peak, group):
        self.name, self.act_id, self.joint, self.sign = name, act_id, joint, sign
        self.qmin, self.qmax, self.peak, self.group = qmin, qmax, peak, group


class MyoTask:
    """Base MyoChallenge task. Subclasses set env_id and add metrics/score."""

    name = "myo"
    env_id = None
    env_kwargs = {}
    controller = None
    seconds = None  # None = the environment's own horizon
    seed = 0
    forward_keys = None  # obs_dict entries to forward (None = every small entry)
    coupled_geometry = False  # sample muscle lengths with joint couplings applied (see muscle_geometry)
    geometry_pairs = False  # also send validated joint-pair length corrections (MPAIR)
    # inertial coupling (opt-in): joints whose acceleration loads the others
    # (e.g. the table-tennis pelvis slides). For each, the bridge sends
    # `mcol_<name>` (the mass matrix column: the generalised force at every
    # geometry joint, in the order of `bias`, per unit acceleration of that
    # joint) and `cacc` (their measured accelerations), so a controller can
    # add the inverse-dynamics term M[j, d] qacc_d to the bias feed-forward.
    coupling_joints = ()

    def extra_sensors(self, sim):
        return []

    def on_command(self, sim, cmd):
        pass

    def on_step(self, sim, obs, reward, info):
        pass

    def metrics(self, sim, log):
        return {}

    def score(self, metrics):
        return metrics.get("solved_frac", 0.0) + 0.001 * metrics.get("dense_sum", 0.0)

    def camera(self, m, d, cam):
        root = d.body(sim_root_body(m)).xpos
        cam.lookat[:] = [root[0], root[1], 1.0]
        cam.distance = 3.5
        cam.azimuth = 135
        cam.elevation = -12

    def title(self):
        return f"robolab on MyoSuite: {self.env_id}"

    def scene_option(self):
        opt = mujoco.MjvOption()
        opt.flags[mujoco.mjtVisFlag.mjVIS_ACTIVATION] = True
        opt.flags[mujoco.mjtVisFlag.mjVIS_TENDON] = True
        return opt


def sim_root_body(m):
    """Name of the body carrying the model's free root joint (or 'pelvis')."""
    for j in range(m.njnt):
        if m.jnt_type[j] == mujoco.mjtJoint.mjJNT_FREE and m.joint(j).name == "root":
            return m.body(m.jnt_bodyid[j]).name
    for name in ("pelvis", "root", "torso"):
        if mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_BODY, name) >= 0:
            return name
    return m.body(1).name


def couple_joints(m, qpos):
    """Apply the model's joint-equality couplings (e.g. the knee's patella and
    translation joints, which follow knee_angle through polynomials) to qpos."""
    for i in range(m.neq):
        if m.eq_type[i] == mujoco.mjtEq.mjEQ_JOINT and m.eq_active0[i] and m.eq_obj2id[i] >= 0:
            a = m.jnt_qposadr[m.eq_obj1id[i]]
            b = m.jnt_qposadr[m.eq_obj2id[i]]
            x = qpos[b] - m.qpos0[b]
            c = m.eq_data[i][:5]
            qpos[a] = m.qpos0[a] + c[0] + x * (c[1] + x * (c[2] + x * (c[3] + x * c[4])))
    return qpos


def muscle_geometry(m, muscle_ids, ref_qpos, samples=SAMPLES, coupled=False):
    """Joints crossed by each muscle and its length along each joint's range.

    Returns (joints, table): joints = [(jid, name, qmin, qmax, qref, qadr)],
    table[i] = {joint index: [lengths at `samples` angles]} for muscle i.
    With `coupled`, every sampled posture (and the reference) has the joint
    equality couplings applied, so sweeping a knee also moves its patella and
    the dependent joints drop out (the knee table then holds the true
    quadriceps length; independent sweeps are off by up to 0.12 of a range).
    """
    fix = (lambda q: couple_joints(m, q)) if coupled else (lambda q: q)
    ref_qpos = fix(np.array(ref_qpos, dtype=float))
    d = mujoco.MjData(m)
    d.qpos[:] = ref_qpos
    mujoco.mj_forward(m, d)
    base = d.actuator_length[muscle_ids].copy()
    cand = []
    for j in range(m.njnt):
        if int(m.jnt_type[j]) not in (int(mujoco.mjtJoint.mjJNT_HINGE), int(mujoco.mjtJoint.mjJNT_SLIDE)):
            continue
        adr = m.jnt_qposadr[j]
        lo, hi = (m.jnt_range[j] if m.jnt_limited[j] else (-math.pi, math.pi))
        span = hi - lo
        d.qpos[:] = ref_qpos
        d.qpos[adr] = min(hi, ref_qpos[adr] + 0.02 * span)
        fix(d.qpos)
        mujoco.mj_forward(m, d)
        up = d.actuator_length[muscle_ids].copy()
        d.qpos[:] = ref_qpos
        d.qpos[adr] = max(lo, ref_qpos[adr] - 0.02 * span)
        fix(d.qpos)
        mujoco.mj_forward(m, d)
        dn = d.actuator_length[muscle_ids].copy()
        if np.max(np.abs(up - dn)) > 1e-7:
            cand.append((j, m.joint(j).name, float(lo), float(hi), float(ref_qpos[adr]), adr))
    table = [dict() for _ in muscle_ids]
    for k, (j, name, lo, hi, qref, adr) in enumerate(cand):
        rows = []
        for q in np.linspace(lo, hi, samples):
            d.qpos[:] = ref_qpos
            d.qpos[adr] = q
            fix(d.qpos)
            mujoco.mj_forward(m, d)
            rows.append(d.actuator_length[muscle_ids].copy())
        rows = np.array(rows)  # samples x muscles
        for i in range(len(muscle_ids)):
            if np.max(rows[:, i]) - np.min(rows[:, i]) > 1e-6:
                table[i][k] = rows[:, i].tolist()
    return cand, table, base


PAIR_SAMPLES = 7


def _additive(joints, table, lref, i, q, qref):
    L = lref[i]
    for k, row in table[i].items():
        xs = np.linspace(joints[k][2], joints[k][3], len(row))
        L += np.interp(q[k], xs, row) - np.interp(qref[k], xs, row)
    return L


def _bilinear(ga, gb, res, qa, qb):
    ia = int(np.clip(np.searchsorted(ga, qa) - 1, 0, len(ga) - 2))
    ib = int(np.clip(np.searchsorted(gb, qb) - 1, 0, len(gb) - 2))
    ta = float(np.clip((qa - ga[ia]) / (ga[ia + 1] - ga[ia]), 0, 1))
    tb = float(np.clip((qb - gb[ib]) / (gb[ib + 1] - gb[ib]), 0, 1))
    return ((1 - ta) * (1 - tb) * res[ia, ib] + ta * (1 - tb) * res[ia + 1, ib]
            + (1 - ta) * tb * res[ia, ib + 1] + ta * tb * res[ia + 1, ib + 1])


def pair_geometry(m, muscle_ids, ref_qpos, joints, table, lref, samples=PAIR_SAMPLES, n_fit=150, seed=1,
                  coupled=False):
    """Second-order muscle-length corrections for coupled joints.

    For every muscle and every pair of joints it crosses, the residual
    L(q_a, q_b) - [f_a(q_a) + f_b(q_b)] (other joints at the reference) on a
    samples x samples grid. A muscle keeps its pair tables only if, on random
    postures (half-way from the reference to a uniform draw), they cut its
    mean length error by at least 20% against the additive model, so no
    muscle's model gets worse. Measured on held-out postures: mean
    contraction error chase-tag legs 0.019 -> 0.004, soccer 0.012 -> 0.006,
    relocate arm 0.032 -> 0.021, table tennis 0.015 -> 0.011.
    Returns {muscle: {(a, b): grid}}.
    """
    fix = (lambda q: couple_joints(m, q)) if coupled else (lambda q: q)
    ref_qpos = fix(np.array(ref_qpos, dtype=float))
    d = mujoco.MjData(m)
    grids = [np.linspace(j[2], j[3], samples) for j in joints]
    need = {}
    for i in range(len(muscle_ids)):
        ks = sorted(table[i].keys())
        for x in range(len(ks)):
            for y in range(x + 1, len(ks)):
                need.setdefault((ks[x], ks[y]), []).append(i)
    pairs = {}
    for (a, b), ms in need.items():
        grid = np.zeros((samples, samples, len(muscle_ids)))
        for ia, qa in enumerate(grids[a]):
            for ib, qb in enumerate(grids[b]):
                d.qpos[:] = ref_qpos
                d.qpos[joints[a][5]] = qa
                d.qpos[joints[b][5]] = qb
                fix(d.qpos)
                mujoco.mj_forward(m, d)
                grid[ia, ib] = d.actuator_length[muscle_ids]
        for i in ms:
            ra, rb = table[i][a], table[i][b]
            fa = np.interp(grids[a], np.linspace(joints[a][2], joints[a][3], len(ra)), ra)[:, None]
            fb = np.interp(grids[b], np.linspace(joints[b][2], joints[b][3], len(rb)), rb)[None, :]
            res = grid[:, :, i] - fa - fb + lref[i]
            if np.max(np.abs(res)) > 1e-6:
                pairs.setdefault(i, {})[(a, b)] = res
    qref = np.array([ref_qpos[j[5]] for j in joints])
    span = m.actuator_lengthrange[muscle_ids, 1] - m.actuator_lengthrange[muscle_ids, 0]
    rng = np.random.default_rng(seed)
    err_add = np.zeros(len(muscle_ids))
    err_pair = np.zeros(len(muscle_ids))
    for _ in range(n_fit):
        q = qref + 0.5 * (np.array([rng.uniform(j[2], j[3]) for j in joints]) - qref)
        d.qpos[:] = ref_qpos
        for k, j in enumerate(joints):
            d.qpos[j[5]] = q[k]
        fix(d.qpos)
        mujoco.mj_forward(m, d)
        q = np.array([d.qpos[j[5]] for j in joints])  # couplings may move dependent joints
        exact = d.actuator_length[muscle_ids]
        for i in pairs:
            add = _additive(joints, table, lref, i, q, qref)
            corr = sum(_bilinear(grids[a], grids[b], r, q[a], q[b]) - _bilinear(grids[a], grids[b], r, qref[a], qref[b])
                       for (a, b), r in pairs[i].items())
            err_add[i] += abs(exact[i] - add) / span[i]
            err_pair[i] += abs(exact[i] - add - corr) / span[i]
    return {i: pp for i, pp in pairs.items() if err_pair[i] < 0.8 * err_add[i]}


def cached_pair_geometry(key, m, muscle_ids, ref_qpos, joints, table, lref, coupled=False):
    import hashlib
    import pickle
    h = hashlib.sha1(np.ascontiguousarray(ref_qpos).tobytes()
                     + np.ascontiguousarray(m.actuator_lengthrange[muscle_ids]).tobytes()
                     + bytes([int(coupled)])).hexdigest()[:12]
    path = os.path.join(HERE, "cache", f"pairs_{key}_{h}.pkl")
    if os.path.exists(path):
        with open(path, "rb") as f:
            return pickle.load(f)
    pairs = pair_geometry(m, muscle_ids, ref_qpos, joints, table, lref, coupled=coupled)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + f".{os.getpid()}"
    with open(tmp, "wb") as f:
        pickle.dump(pairs, f)
    os.replace(tmp, path)
    return pairs


class MyoSim:
    """Same interface as bridge.Sim, so practice.py and render.py work."""

    def __init__(self, task, params=None, controller=None, skill=None, verbose=False, seed=None):
        from myosuite.utils import gym  # imported here: only the MyoSuite venv has it
        self.task = task
        self.params = params or {}
        self.verbose = verbose
        self.env = gym.make(task.env_id, **task.env_kwargs)
        self.u = self.env.unwrapped
        self.seed = task.seed if seed is None else seed
        # MyoSuite's reset(seed=...) does not reseed the env's np_random (it is
        # drawn from OS entropy at construction), so episodes were random
        # whatever the seed; seed it explicitly so a seed names one episode.
        if hasattr(self.u, "seed"):
            self.u.seed(self.seed)
        self.obs, _ = self.env.reset(seed=self.seed)
        self.m, self.d = self.u.mj_model, self.u.mj_data
        m = self.m
        m.vis.global_.offwidth = max(m.vis.global_.offwidth, 1280)
        m.vis.global_.offheight = max(m.vis.global_.offheight, 720)
        self.muscle_ids = [i for i in range(m.nu) if m.actuator_dyntype[i] == mujoco.mjtDyn.mjDYN_MUSCLE]
        self.motor_ids = [i for i in range(m.nu) if i not in set(self.muscle_ids)]
        self.act_ids = self.muscle_ids
        self.n = len(self.muscle_ids)
        self.lr = m.actuator_lengthrange[self.muscle_ids].copy()
        self.peak = np.maximum(m.actuator_gainprm[self.muscle_ids, 2], 1e-6)
        ref = self.d.qpos.copy()
        # a task may fix the geometry's reference posture to a model key frame:
        # otherwise it is the reset posture, which a randomized reset (P2) changes
        # every episode (joint noise, and mirrored start keys swap the legs' maps)
        if getattr(task, "geometry_ref_key", None) is not None:
            ref = m.key_qpos[task.geometry_ref_key].copy()
        self.joints, self.table, self.lref = muscle_geometry(m, self.muscle_ids, ref,
                                                             coupled=getattr(task, "coupled_geometry", False))
        self.pairs = {}
        if getattr(task, "geometry_pairs", False):
            self.pairs = cached_pair_geometry(task.env_id, m, self.muscle_ids, ref, self.joints, self.table,
                                              self.lref, coupled=getattr(task, "coupled_geometry", False))
        self.muscles = []
        for i, aid in enumerate(self.muscle_ids):
            best, sign, name, lo, hi = 0.0, 1, "", -1.0, 1.0
            for k, row in self.table[i].items():
                slope = (row[-1] - row[0]) / (self.joints[k][3] - self.joints[k][2])
                if abs(slope) > best:
                    best, sign = abs(slope), (1 if slope < 0 else -1)
                    name, lo, hi = self.joints[k][1], self.joints[k][2], self.joints[k][3]
            if not name:  # crosses no hinge (should not happen); park it on the first joint
                name, lo, hi = self.joints[0][1], self.joints[0][2], self.joints[0][3]
            self.muscles.append(MyoMuscle(m.actuator(aid).name, aid, name, sign, lo, hi, float(self.peak[i]), name))
        self.motor_cmd = {m.actuator(a).name: 0.0 for a in self.motor_ids}
        self.skill = skill or task.name
        if controller is None:
            controller = (os.environ.get("ROBOLAB_CONTROLLER") or task.controller
                          or os.path.join(ROOT, "bin", f"robolab_{task.name}"))
        self.controller_cmd = [controller, self.skill]
        self.root = sim_root_body(m)
        # MyoSuite bodies are y-up in their own frames, so "up" and "forward"
        # are whichever local axes point along world z and world x at reset
        # (as signed axis indices); robolab's bodies come out as z and x.
        mujoco.mj_forward(m, self.d)
        self.root_up, self.root_fwd = self._body_axes(self.root)
        self.torso_name = next((n for n in ("torso", "thorax", "back")
                                if mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_BODY, n) >= 0), self.root)
        self.torso_up, self.torso_fwd = self._body_axes(self.torso_name)
        self.feet = self._find_feet()
        mass = m.body_subtreemass[m.body(self.root).id]
        self.weight = float(mass) * 9.81
        self.label = ""
        self.targets = np.zeros(self.n)
        self.log = []
        self.infos = []
        self.done = False

    # ---- sensors -------------------------------------------------------

    def _body_axes(self, name):
        R = self.d.body(name).xmat.reshape(3, 3)
        up = int(np.argmax(np.abs(R[2, :])))
        if up != 0:
            # forward is the body's own local +x in both conventions (MuJoCo
            # z-up and OpenSim y-up); it must not depend on the reset heading
            # (ChaseTag starts facing world -y, P2 and OSL at other headings)
            return (up, 1.0 if R[2, up] >= 0 else -1.0), (0, 1.0)
        fwd_candidates = [k for k in range(3) if k != up]
        fwd = max(fwd_candidates, key=lambda k: abs(R[0, k]))
        return (up, 1.0 if R[2, up] >= 0 else -1.0), (fwd, 1.0 if R[0, fwd] >= 0 else -1.0)

    @staticmethod
    def _axis(R, axis):
        k, sign = axis
        return R[:, k] * sign

    def _find_feet(self):
        feet = {}
        for side in ("l", "r"):
            ids = []
            for b in range(self.m.nbody):
                name = self.m.body(b).name
                if name.endswith("_" + side) and any(k in name for k in ("calcn", "toes", "foot")):
                    ids.append(b)
            if ids:
                feet[side] = ids
        return feet

    def contraction(self):
        L = self.d.actuator_length[self.muscle_ids]
        lo, hi = self.lr[:, 0], self.lr[:, 1]
        c = (hi - L) / (hi - lo)
        cd = -self.d.actuator_velocity[self.muscle_ids] / (hi - lo)
        f = -self.d.actuator_force[self.muscle_ids] / self.peak
        return c, cd, f

    def foot_contacts(self):
        out = {s: 0.0 for s in ("l", "r")}
        force = np.zeros(6)
        lookup = {b: s for s, ids in self.feet.items() for b in ids}
        for i in range(self.d.ncon):
            con = self.d.contact[i]
            for g in (con.geom1, con.geom2):
                b = self.m.geom_bodyid[g]
                if b in lookup:
                    mujoco.mj_contactForce(self.m, self.d, i, force)
                    out[lookup[b]] += abs(force[0]) / self.weight
        return out

    def standard_sensors(self):
        m, d = self.m, self.d
        root = d.body(self.root)
        rm = root.xmat.reshape(3, 3)
        vel = np.zeros(6)
        mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_BODY, root.id, vel, 0)
        tor = d.body(self.torso_name)
        tm = tor.xmat.reshape(3, 3)
        tvel = np.zeros(6)
        mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_BODY, tor.id, tvel, 0)
        mujoco.mj_subtreeVel(m, d)
        q = [d.qpos[j[5]] for j in self.joints]
        qd = [d.qvel[m.jnt_dofadr[j[0]]] for j in self.joints]
        ct = self.foot_contacts()
        blocks = [
            ("q", q), ("qd", qd),
            # gravity + Coriolis generalised force per joint (MuJoCo qfrc_bias): what
            # the muscles must supply to hold still; feeds the internal-model feed-forward
            ("bias", [d.qfrc_bias[m.jnt_dofadr[j[0]]] for j in self.joints]),
            ("pelvis_pos", root.xpos), ("pelvis_vel", vel[3:]),
            ("pelvis_up", self._axis(rm, self.root_up)), ("pelvis_fwd", self._axis(rm, self.root_fwd)),
            ("torso_up", self._axis(tm, self.torso_up)), ("torso_fwd", self._axis(tm, self.torso_fwd)),
            ("torso_angvel", tvel[:3]),
            ("com_pos", d.subtree_com[root.id]), ("com_vel", d.subtree_linvel[root.id]),
            ("l_foot_contact", [ct["l"]]), ("r_foot_contact", [ct["r"]]),
        ]
        for side in ("l", "r"):
            if side in self.feet:
                blocks.append((f"{side}_foot_pos", d.xpos[self.feet[side][0]]))
        blocks += self.coupling_sensors()
        return blocks

    def coupling_sensors(self):
        """Mass-matrix columns of the task's coupling joints over the geometry
        joints, and those joints' measured accelerations (opt-in, see
        MyoTask.coupling_joints); none unless the task names some."""
        names = getattr(self.task, "coupling_joints", ())
        if not names:
            return []
        m, d = self.m, self.d
        dofs = [m.jnt_dofadr[j[0]] for j in self.joints]
        out, vel = [], []
        for name in names:
            k = m.jnt_dofadr[m.joint(name).id]
            e = np.zeros(m.nv)
            e[k] = 1.0
            col = np.zeros(m.nv)
            mujoco.mj_mulM(m, d, col, e)
            out.append((f"mcol_{name}", col[dofs]))
            vel.append(d.qvel[k])
        # acceleration over the last control step, from the velocities (the
        # environment's d.qacc is not the step's acceleration: it misses the
        # implicit joint damping and the substeps)
        vel = np.array(vel)
        prev = getattr(self, "_coupling_prev", None)
        acc = np.zeros(len(vel))
        if prev is not None and d.time > prev[0]:
            acc = (vel - prev[1]) / (d.time - prev[0])
        if prev is None or d.time != prev[0]:
            self._coupling_prev = (d.time, vel)
        out.append(("cacc", acc))
        return out

    def env_sensors(self):
        out = []
        keys = self.task.forward_keys
        for k, v in self.u.obs_dict.items():
            if keys is not None and k not in keys:
                continue
            if keys is None and k in FORWARD_KEYS_EXCLUDE:
                continue
            arr = np.asarray(v, dtype=float).ravel()
            if keys is None and arr.size > 32:
                continue
            out.append(("env_" + k, arr))
        return out

    def sensor_blocks(self):
        return self.standard_sensors() + self.env_sensors() + list(self.task.extra_sensors(self))

    # ---- controller process -------------------------------------------

    def start_controller(self):
        self.proc = subprocess.Popen(self.controller_cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=None if self.verbose else subprocess.PIPE, text=True, bufsize=1)
        lines = ["ROBOLAB 1", f"TASK {self.task.name}", f"DT {self.u.dt:g}"]
        for i, mu in enumerate(self.muscles):
            lines.append(f"MUSCLE {i} {mu.name} {mu.joint} {mu.sign} {mu.qmin:g} {mu.qmax:g} {mu.group}")
        for k, (j, name, lo, hi, qref, adr) in enumerate(self.joints):
            lines.append(f"JOINT {k} {name} {lo:.9g} {hi:.9g} {qref:.9g} {SAMPLES}")
        for i in range(self.n):
            lines.append(f"MRANGE {i} {self.lr[i, 0]:.9g} {self.lr[i, 1]:.9g} {self.lref[i]:.9g}")
            lines.append(f"MFORCE {i} {self.peak[i]:.9g}")
            for k, row in self.table[i].items():
                lines.append(f"MLEN {i} {k} " + " ".join(f"{x:.9g}" for x in row))
        for i, pp in self.pairs.items():
            for (a, b), grid in pp.items():
                lines.append(f"MPAIR {i} {a} {b} {grid.shape[0]} " + " ".join(f"{x:.9g}" for x in grid.ravel()))
        for k, aid in enumerate(self.motor_ids):
            lo, hi = self.m.actuator_ctrlrange[aid]
            lines.append(f"MOTOR {k} {self.m.actuator(aid).name} {lo:g} {hi:g}")
        mujoco.mj_forward(self.m, self.d)
        for name, vals in self.sensor_blocks():
            lines.append(f"SENSOR {name} {len(vals)}")
        for k, v in self.params.items():
            lines.append(f"PARAM {k} {float(v)!r}")
        lines.append("BEGIN")
        self.proc.stdin.write("\n".join(lines) + "\n")
        self.proc.stdin.flush()
        ready = self.proc.stdout.readline()
        if not ready.startswith("READY"):
            err = self.proc.stderr.read() if self.proc.stderr else ""
            raise RuntimeError(f"controller handshake failed: {ready!r}\n{err}")

    def action_from(self, act):
        """robolab activations (and motor commands) -> MyoSuite action vector."""
        a = np.zeros(self.m.nu)
        u = np.clip(act, 1e-4, 1 - 1e-4)
        if getattr(self.u, "normalize_act", False):
            # MyoSuite maps action x to ctrl sigmoid(5 (x - 0.5)); invert it
            a[self.muscle_ids] = np.clip(0.5 + np.log(u / (1 - u)) / 5.0, -1.0, 1.0)
        else:
            a[self.muscle_ids] = u
        for aid in self.motor_ids:
            a[aid] = self.motor_cmd[self.m.actuator(aid).name]
        return a

    def tick(self):
        c, cd, f = self.contraction()
        vals = [self.d.time, *c, *cd, *f]
        for _, v in self.sensor_blocks():
            vals.extend(np.asarray(v, dtype=float).ravel())
        self.proc.stdin.write("S " + " ".join(f"{x:.7g}" for x in vals) + "\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        if not line.startswith("A "):
            err = self.proc.stderr.read() if self.proc.stderr else ""
            raise RuntimeError(f"controller reply {line!r}\n{err}")
        tok = line.split()
        n = self.n
        act = np.clip(np.array([float(x) for x in tok[1:1 + n]]), 0.0, 1.0)
        self.targets = np.array([float(x) for x in tok[1 + n:1 + 2 * n]])
        self.label = tok[1 + 2 * n] if len(tok) > 1 + 2 * n else ""
        for cmd in tok[2 + 2 * n:]:
            if cmd.startswith("motor:"):
                _, name, value = cmd.split(":")
                self.motor_cmd[name] = float(value)
            else:
                self.task.on_command(self, cmd)
        return act, c

    def stop_controller(self):
        try:
            self.proc.stdin.close()
            self.proc.wait(timeout=5)
        except Exception:
            self.proc.kill()

    # ---- main loop -------------------------------------------------------

    def run(self, seconds=None, recorder=None):
        seconds = seconds or self.task.seconds
        self.start_controller()
        solved = sparse = dense = 0.0
        steps = 0
        terminated = False
        try:
            while True:
                act, c = self.tick()
                obs, reward, term, trunc, info = self.env.step(self.action_from(act))
                steps += 1
                solved = max(solved, float(info.get("solved", 0.0)))
                sparse += float(info.get("rwd_sparse", 0.0))
                dense += float(info.get("rwd_dense", 0.0))
                self.infos.append(info)
                self.task.on_step(self, obs, reward, info)
                self.log.append((self.d.time, self.label, act.copy(), c.copy(), self.targets.copy()))
                if recorder is not None:
                    recorder.maybe_capture(self)
                if term or trunc:
                    terminated = bool(term)
                    break
                if seconds and self.d.time >= seconds:
                    break
        finally:
            self.stop_controller()
        out = {"steps": steps, "time": round(float(self.d.time), 3), "solved": solved,
               "solved_final": float(self.infos[-1].get("solved", 0.0)) if self.infos else 0.0,
               "sparse_sum": round(sparse, 4), "dense_sum": round(dense, 4), "terminated": terminated}
        acts = np.array([row[2] for row in self.log]) if self.log else np.zeros((1, self.n))
        out["effort"] = round(float(np.mean(acts ** 2)), 4)
        out.update(self.task.metrics(self, self.log))
        out["fell"] = False
        return out


def load_task(name):
    sys.path.insert(0, HERE)
    return importlib.import_module(f"tasks.{name}").TASK()


def main():
    ap = argparse.ArgumentParser(description="Run a robolab skill on a MyoSuite body")
    ap.add_argument("task")
    ap.add_argument("--params")
    ap.add_argument("--seconds", type=float)
    ap.add_argument("--seed", type=int)
    ap.add_argument("--episodes", type=int, default=1)
    ap.add_argument("--video")
    ap.add_argument("--gif")
    ap.add_argument("--sheet")
    ap.add_argument("--json")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    task = load_task(args.task)
    params = {}
    if args.params:
        for line in open(args.params):
            parts = line.split()
            if len(parts) >= 2 and not line.startswith("#"):
                params[parts[0]] = float(parts[1])
    results = []
    rec = None
    for ep in range(args.episodes):
        seed = (args.seed if args.seed is not None else task.seed) + ep
        sim = MyoSim(task, params=params, verbose=args.verbose, seed=seed)
        if ep == 0 and (args.video or args.gif or args.sheet):
            from render import Recorder
            rec = Recorder(sim, scene_option=task.scene_option())
        t0 = time.time()
        res = sim.run(args.seconds, recorder=rec if ep == 0 else None)
        res["seed"] = seed
        res["wall_s"] = round(time.time() - t0, 2)
        print(res, flush=True)
        results.append(res)
    if args.episodes > 1:
        keys = [k for k in results[0] if isinstance(results[0][k], (int, float)) and not isinstance(results[0][k], bool)]
        # a metric can be None in some episodes (e.g. no goal time): average the numbers
        num = lambda v: isinstance(v, (int, float)) and not isinstance(v, bool)
        print("mean", {k: round(float(np.mean([r[k] for r in results if num(r.get(k))])), 4) for k in keys})
    if args.json:
        json.dump(results, open(args.json, "w"), indent=1)
    if rec is not None:
        if args.video:
            rec.write_mp4(args.video)
        if args.gif:
            rec.write_gif(args.gif)
        if args.sheet:
            rec.write_sheet(args.sheet)


if __name__ == "__main__":
    sys.path.insert(0, HERE)
    main()
