"""robolab MuJoCo bridge: runs the physics, talks to a Tungsten controller.

The controller is a separate process (the compiled robolab bit) speaking a
line protocol on stdin/stdout, the way a robot's brain talks to its body
over a bus. Every control tick (default 5 ms) the bridge sends one sensor
line and reads back one activation line.

Handshake (bridge -> controller):
    ROBOLAB 1
    TASK <name>
    DT <control dt seconds>
    MUSCLE <index> <name> <joint> <sign> <qmin> <qmax> <group>   (one per muscle)
    SENSOR <name> <width>                                        (extra sensors, in order)
    PARAM <name> <value>                                         (optimizer overrides)
    BEGIN
controller -> bridge:
    READY <n_muscles>

Tick (bridge -> controller):
    S <t> <c_1..c_n> <cdot_1..cdot_n> <force_1..force_n> <extra sensor values...>
controller -> bridge:
    A <a_1..a_n> <target_1..target_n> <chunk-label> [<cmd>...]

c is contraction in [0,1] (fraction of the muscle's length range), cdot its
rate (1/s), force the active+passive muscle force over peak force. Targets
are the controller's commanded contractions (logged for the HUD). Commands
are task specific tokens such as `grip:l:0` (release the left hand).
"""

import math
import os
import subprocess
import sys
import time

os.environ.setdefault("MUJOCO_GL", "cgl")

import mujoco  # noqa: E402
import numpy as np  # noqa: E402

from body import HumanoidBuilder, scene_xml  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONTROLLER = os.path.join(ROOT, "bin", "robolab")


def quat_to_mat(q):
    m = np.zeros(9)
    mujoco.mju_quat2Mat(m, q)
    return m.reshape(3, 3)


class Task:
    """Base task: a standing humanoid. Subclasses add props, sensors, metrics."""

    name = "stand"
    controller = None  # path to the controller binary; default bin/robolab_<name>
    mode = "planar"
    strength = 1.0
    wrists = None
    timestep = 0.002
    control_dt = 0.005
    seconds = 6.0
    fall_height = 0.55
    pelvis_height = 0.955  # initial (planar/free) or fixed (pivot) pelvis height

    def builder(self):
        return HumanoidBuilder(self.mode, strength=self.strength, wrists=self.wrists)

    def xml(self, builder):
        return scene_xml(builder, **self.xml_extras(), timestep=self.timestep, pelvis_height=self.pelvis_height)

    def xml_extras(self):
        return {}

    def reset(self, m, d):
        pass

    def extra_sensors(self, m, d):
        return []

    def on_command(self, m, d, cmd):
        pass

    def before_step(self, m, d):
        pass

    def done(self, m, d):
        return d.body("pelvis").xpos[2] < self.fall_height and self.mode != "pivot"

    def metrics(self, m, d, log):
        return {"time": round(d.time, 3), "x": round(float(d.body("pelvis").xpos[0]), 3)}

    def camera(self, m, d, cam):
        p = d.body("pelvis").xpos
        cam.lookat[:] = [p[0], 0.0, 0.9]
        cam.distance = 4.2
        cam.azimuth = 90
        cam.elevation = -8

    def title(self):
        return self.name

    def score(self, metrics):
        """Practice objective (higher is better)."""
        return metrics.get("time", 0.0) - (5.0 if metrics.get("fell") else 0.0)


class Sim:
    def __init__(self, task, params=None, controller=None, skill=None, verbose=False):
        self.task = task
        self.builder = task.builder()
        self.xml = task.xml(self.builder)
        self.m = mujoco.MjModel.from_xml_string(self.xml)
        self.d = mujoco.MjData(self.m)
        self.params = params or {}
        self.muscles = self.builder.spec.muscles
        self.n = len(self.muscles)
        self.act_ids = [mujoco.mj_name2id(self.m, mujoco.mjtObj.mjOBJ_ACTUATOR, mu.name) for mu in self.muscles]
        self.lr = self.m.actuator_lengthrange[self.act_ids].copy()
        self.peak = np.array([mu.peak for mu in self.muscles])
        self.skill = skill or task.name
        if controller is None:
            controller = os.environ.get("ROBOLAB_CONTROLLER") or task.controller or os.path.join(ROOT, "bin", f"robolab_{task.name}")
        self.controller_cmd = [controller, self.skill]
        self.verbose = verbose
        self.contact_geoms = {
            "l_foot": self.m.geom("l_foot").id, "r_foot": self.m.geom("r_foot").id,
            "l_hand": self.m.geom("l_hand").id, "r_hand": self.m.geom("r_hand").id,
        }
        self.weight = float(sum(self.m.body_mass[1:])) * 9.81
        self.label = ""
        self.targets = np.zeros(self.n)
        self.log = []
        # Bodies with multi-joint muscles (HumanoidV2Builder) also send the
        # muscle geometry and joint-angle sensors; the base body's handshake
        # and sensor layout stay exactly as before.
        self.geometry = None
        if getattr(self.builder, "send_geometry", False):
            from myo_bridge import muscle_geometry, SAMPLES  # noqa: F401
            mujoco.mj_forward(self.m, self.d)
            # a body may measure its muscles' path lengths itself (HumanoidV3Builder:
            # an elastic muscle's actuator length is its fibre, its geometry the MTU)
            geometry = getattr(self.builder, "muscle_geometry", None) or muscle_geometry
            self.geometry = geometry(self.m, self.act_ids, self.d.qpos.copy())

    # ---- sensors -------------------------------------------------------

    def contraction(self):
        L = self.d.actuator_length[self.act_ids]
        lo, hi = self.lr[:, 0], self.lr[:, 1]
        c = (hi - L) / (hi - lo)
        cd = -self.d.actuator_velocity[self.act_ids] / (hi - lo)
        f = -self.d.actuator_force[self.act_ids] / self.peak
        return c, cd, f

    def contacts(self):
        out = {k: 0.0 for k in self.contact_geoms}
        ids = {v: k for k, v in self.contact_geoms.items()}
        for side in ("l", "r"):  # the v2 anatomy's toe and finger segments
            toes = mujoco.mj_name2id(self.m, mujoco.mjtObj.mjOBJ_GEOM, f"{side}_toes")
            if toes >= 0:
                ids[toes] = f"{side}_foot"
            for seg in ("fingers1", "fingers2"):
                g = mujoco.mj_name2id(self.m, mujoco.mjtObj.mjOBJ_GEOM, f"{side}_{seg}")
                if g >= 0:
                    ids[g] = f"{side}_hand"
        force = np.zeros(6)
        for i in range(self.d.ncon):
            con = self.d.contact[i]
            for g in (con.geom1, con.geom2):
                if g in ids:
                    mujoco.mj_contactForce(self.m, self.d, i, force)
                    out[ids[g]] += abs(force[0]) / self.weight
        return out

    def standard_sensors(self):
        d, m = self.d, self.m
        pel = d.body("pelvis")
        tor = d.body("torso")
        pm = pel.xmat.reshape(3, 3)
        tm = tor.xmat.reshape(3, 3)
        vel = np.zeros(6)
        mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_BODY, pel.id, vel, 0)
        tvel = np.zeros(6)
        mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_BODY, tor.id, tvel, 0)
        mujoco.mj_subtreeVel(m, d)
        com = d.subtree_com[pel.id]
        comv = d.subtree_linvel[pel.id]
        ct = self.contacts()
        blocks = []
        if self.geometry is not None:
            joints = self.geometry[0]
            blocks += [("q", [d.qpos[j[5]] for j in joints]), ("qd", [d.qvel[m.jnt_dofadr[j[0]]] for j in joints])]
        return blocks + [
            ("pelvis_pos", pel.xpos), ("pelvis_vel", vel[3:]),
            ("pelvis_up", pm[:, 2]), ("pelvis_fwd", pm[:, 0]),
            ("torso_up", tm[:, 2]), ("torso_fwd", tm[:, 0]), ("torso_angvel", tvel[:3]),
            ("com_pos", com), ("com_vel", comv),
            ("l_foot_pos", d.body("l_foot").xpos), ("r_foot_pos", d.body("r_foot").xpos),
            ("l_hand_pos", d.site("l_palm").xpos), ("r_hand_pos", d.site("r_palm").xpos),
            ("l_foot_contact", [ct["l_foot"]]), ("r_foot_contact", [ct["r_foot"]]),
            ("l_hand_contact", [ct["l_hand"]]), ("r_hand_contact", [ct["r_hand"]]),
        ]

    def sensor_blocks(self):
        return self.standard_sensors() + list(self.task.extra_sensors(self.m, self.d))

    # ---- controller process -------------------------------------------

    def start_controller(self):
        self.proc = subprocess.Popen(self.controller_cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=None if self.verbose else subprocess.PIPE, text=True, bufsize=1)
        # The controller integrates its springs with DT, so send the time one
        # tick really advances (whole physics substeps), not the nominal rate.
        substeps = max(1, round(self.task.control_dt / self.m.opt.timestep))
        lines = ["ROBOLAB 1", f"TASK {self.task.name}", f"DT {substeps * self.m.opt.timestep:g}"]
        for i, mu in enumerate(self.muscles):
            lines.append(f"MUSCLE {i} {mu.name} {mu.joint} {mu.sign} {mu.qmin:g} {mu.qmax:g} {mu.group}")
        if self.geometry is not None:
            from myo_bridge import SAMPLES
            joints, table, lref = self.geometry
            for k, (j, name, lo, hi, qref, adr) in enumerate(joints):
                lines.append(f"JOINT {k} {name} {lo:.9g} {hi:.9g} {qref:.9g} {SAMPLES}")
            for i in range(self.n):
                lines.append(f"MRANGE {i} {self.lr[i, 0]:.9g} {self.lr[i, 1]:.9g} {lref[i]:.9g}")
                for k, row in table[i].items():
                    lines.append(f"MLEN {i} {k} " + " ".join(f"{x:.9g}" for x in row))
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

    def tick(self):
        c, cd, f = self.contraction()
        vals = [self.d.time, *c, *cd, *f]
        for _, v in self.sensor_blocks():
            vals.extend(v)
        self.proc.stdin.write("S " + " ".join(f"{x:.6g}" for x in vals) + "\n")
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
            self.task.on_command(self.m, self.d, cmd)
        self.d.ctrl[self.act_ids] = act
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
        self.task.reset(self.m, self.d)
        mujoco.mj_forward(self.m, self.d)
        self.start_controller()
        substeps = max(1, round(self.task.control_dt / self.m.opt.timestep))
        fell = False
        try:
            while self.d.time < seconds:
                act, c = self.tick()
                for _ in range(substeps):
                    self.task.before_step(self.m, self.d)
                    mujoco.mj_step(self.m, self.d)
                self.log.append((self.d.time, self.label, act.copy(), c.copy(), self.targets.copy()))
                if recorder is not None:
                    recorder.maybe_capture(self)
                if self.task.done(self.m, self.d):
                    fell = True
                    break
        finally:
            self.stop_controller()
        out = self.task.metrics(self.m, self.d, self.log)
        out["fell"] = fell
        return out


def main():
    import argparse
    import importlib
    ap = argparse.ArgumentParser(description="Run a robolab skill in MuJoCo")
    ap.add_argument("task")
    ap.add_argument("--params", help="file of `name value` lines")
    ap.add_argument("--seconds", type=float)
    ap.add_argument("--video", help="output .mp4 path")
    ap.add_argument("--gif", help="output .gif path")
    ap.add_argument("--sheet", help="output contact-sheet .png path")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    mod = importlib.import_module(f"tasks.{args.task}")
    task = mod.TASK()
    params = {}
    if args.params:
        for line in open(args.params):
            parts = line.split()
            if len(parts) >= 2 and not line.startswith("#"):
                params[parts[0]] = float(parts[1])
    sim = Sim(task, params=params, verbose=args.verbose)
    rec = None
    if args.video or args.gif or args.sheet:
        from render import Recorder
        rec = Recorder(sim)
    t0 = time.time()
    res = sim.run(args.seconds, recorder=rec)
    res["wall_s"] = round(time.time() - t0, 2)
    print(res)
    if rec is not None:
        if args.video:
            rec.write_mp4(args.video)
        if args.gif:
            rec.write_gif(args.gif)
        if args.sheet:
            rec.write_sheet(args.sheet)


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    main()
