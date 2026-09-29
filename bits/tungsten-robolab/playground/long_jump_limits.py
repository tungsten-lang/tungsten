"""long_jump_limits: how far could each body jump from its own run-up under
ideal control of the take-off?

No skill in the loop: the body starts from its champion's ACTUAL approach
state (captured from a real rollout at the start of the plant flight, the
moment the penultimate foot leaves the ground: position, velocities, muscle
activations, tendon fibre states, exactly) and all 32 muscles follow
open-loop, piecewise-linear excitations (knots every KNOT s, held per 4 ms
control tick as the bridge does) through the plant flight and the take-off
stance. CMA-ES (sep-CMA, search.py) chooses them to maximise the take-off's
jump, so the plant placement (touchdown leg angle), the strut, the drive,
the free-leg swing and the arm action are all free.

Objective: the ballistic jump D = (COM x - take-off foot front x) at take-off
+ vx x t_air, where t_air is the COM's fall from its take-off height to
LAND_Z (0.55 m, long_jump's `ballistic_m` convention; the landing reach is not
included), minus penalties:
  - no plant touchdown within 0.35 s, no take-off within 0.4 s of it, a
    second foot contact during the stance, or any other body part touching
    the ground: invalid (score -5 + progress);
  - forward angular momentum about the COM at take-off above --lmax (kg m^2/s;
    the champion's own value by default, i.e. a flight the current hang can
    manage; --lmax inf lifts it): -0.2 m per unit above;
  - trunk pitch at take-off outside [-0.5, 0.8] rad: -2 m per rad outside.

Validation (`replay`): the captured state plus the rollout's recorded
excitations reproduces the rollout's take-off (same code path as the
optimiser); the initial point of the search is those excitations sampled at
the knots.

    .venv/bin/python playground/long_jump_limits.py capture long_jump_p95b --params p.txt --controller bin/x --name p95
    .venv/bin/python playground/long_jump_limits.py replay p95
    .venv/bin/python playground/long_jump_limits.py optimise p95 --evals 20000 --workers 4 [--lmax inf] [--tag free]
    .venv/bin/python playground/long_jump_limits.py report p95,p50,elite

Files: out/long_jump_limits/<name>_capture.npz, <name>_<tag>.json (the
optimum: take-off table, per-muscle excitation knots, contraction traces).
"""

import argparse
import importlib
import json
import math
import multiprocessing as mp
import os
import sys
import time

os.environ.setdefault("MUJOCO_GL", "cgl")
import mujoco  # noqa: E402
import numpy as np  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

OUT = os.path.join(ROOT, "out", "long_jump_limits")
G = 9.81
LAND_Z = 0.55
KNOT = 0.03          # excitation knot spacing (s)
HORIZON = 0.48       # knots span [0, HORIZON] from the plant flight's start
HORIZON_PEN = 0.69   # ... or from the penultimate touchdown (capture --from pen)
TD_MAX = 0.35        # the plant must touch down by then
STANCE_MAX = 0.40    # and take off within this after touchdown
AIR_CONFIRM = 0.02   # airborne this long = taken off
MIN_STANCE = 0.04    # (after at least this much stance: a touchdown bounce is not a take-off)
PITCH_MARGIN = 1.85  # the landing score's torso-pitch margin (rad; the somersault rule fails at 2.1)
SPEC = mujoco.mjtState.mjSTATE_INTEGRATION
FOOT_GEOMS = ("l_foot", "l_toes", "r_foot", "r_toes")


# ---------------------------------------------------------------------------
# model

def load_task(name, board_x=None):
    task = importlib.import_module(f"tasks.{name}").TASK()
    if board_x is not None:
        task.board_x = board_x
    return task


def build(task):
    b = task.builder()
    m = mujoco.MjModel.from_xml_string(task.xml(b))
    return b, m


class Body:
    """Model + geometry lookups for the evaluator."""

    def __init__(self, task_name, board_x, env):
        for k, v in env.items():
            os.environ[k] = v
        self.task = load_task(task_name, board_x)
        self.b, self.m = build(self.task)
        self.d = mujoco.MjData(self.m)
        m = self.m
        self.muscles = [mu.name for mu in self.b.spec.muscles]
        self.act_ids = [mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_ACTUATOR, n) for n in self.muscles]
        self.ground = {m.geom(n).id for n in ("runway", "pit", "far_ground")}
        self.runway = m.geom("runway").id
        self.feet = {}
        for g in range(m.ngeom):
            n = mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_GEOM, g) or ""
            if n in FOOT_GEOMS:
                self.feet[g] = n[0]
        self.body_geoms = {g for g in range(m.ngeom) if m.geom_bodyid[g] != 0}
        self.pelvis = m.body("pelvis").id
        self.torso = m.body("torso").id
        self.substeps = max(1, round(self.task.control_dt / m.opt.timestep))
        self.dt_ctl = self.substeps * m.opt.timestep

    def contacts(self):
        feet, other = set(), False
        d = self.d
        for i in range(d.ncon):
            c = d.contact[i]
            for a, g in ((c.geom1, c.geom2), (c.geom2, c.geom1)):
                if g in self.ground and a in self.body_geoms:
                    if a in self.feet:
                        feet.add(self.feet[a])
                    else:
                        other = True
        return feet, other

    def foot_front(self, side):
        m, d = self.m, self.d
        best = -1e9
        for g, f in self.feet.items():
            if f != side or m.geom_type[g] != 6:
                continue
            R = d.geom_xmat[g].reshape(3, 3)
            h = m.geom_size[g]
            best = max(best, float(d.geom_xpos[g][0] + abs(R[0, 0]) * h[0] + abs(R[0, 1]) * h[1] + abs(R[0, 2]) * h[2]))
        return best

    def leg_angle(self, side):
        """Angle (deg) between the ground and the hip-to-ankle line, measured
        on the side the foot is on (90 = vertical; < 90 with the foot ahead of
        the hip, the human plant ~60)."""
        d = self.d
        hip = d.xpos[self.m.body(f"{side}_thigh").id]
        ank = d.xpos[self.m.body(f"{side}_foot").id]
        return math.degrees(math.atan2(hip[2] - ank[2], abs(ank[0] - hip[0])))

    def ahead(self, side):
        d = self.d
        return float(d.xpos[self.m.body(f"{side}_foot").id][0] - d.subtree_com[self.pelvis][0])

    def torso_pitch(self):
        up = self.d.xmat[self.torso].reshape(3, 3)[:, 2]
        return math.atan2(up[0], up[2])

    def knee(self, side):
        return float(self.d.joint(f"{side}_knee").qpos[0])


# ---------------------------------------------------------------------------
# capture: a real rollout, its state at the start of the plant flight

def capture(a):
    seeds = [a.seed] if not a.seeds else [None if v in ("None", "0") else int(v) for v in a.seeds.split(",")]
    for sd in seeds:
        a.seed = sd
        name = a.base if not a.seeds else f"{a.base}_s{0 if sd is None else sd}"
        try:
            capture_one(a, name)
        except StopIteration:
            print("no plant flight (no take-off chunk) for seed", sd)


def capture_one(a, name):
    from bridge import Sim
    from search import read_params
    env = {k: os.environ[k] for k in ("ROBOLAB_PROFILE", "ROBOLAB_PROFILE_PARTS") if k in os.environ}
    task = load_task(a.task)
    task.seed = a.seed
    params = {}
    for p in a.params:
        params.update(read_params(p))
    for kv in (a.set or "").split(","):
        if kv:
            k, v = kv.split("=")
            params[k] = float(v)
    params.pop("j_ik", None)
    sim = Sim(task, params=params, controller=a.controller)
    m, d = sim.m, sim.d
    size = mujoco.mj_stateSize(m, SPEC)
    states, labels, ctrls, times = [], [], [], []
    seconds = task.seconds
    task.reset(m, d)
    mujoco.mj_forward(m, d)
    sim.start_controller()
    substeps = max(1, round(task.control_dt / m.opt.timestep))
    try:
        while d.time < seconds:
            st = np.zeros(size)
            mujoco.mj_getState(m, d, st, SPEC)
            act, c = sim.tick()
            states.append(st)
            labels.append(sim.label)
            ctrls.append(d.ctrl[sim.act_ids].copy())
            times.append(d.time)
            for _ in range(substeps):
                task.before_step(m, d)
                mujoco.mj_step(m, d)
            sim.log.append((d.time, sim.label, act.copy(), c.copy(), sim.targets.copy()))
            if task.done(m, d):
                break
    finally:
        sim.stop_controller()
    mt = task.metrics(m, d, sim.log)
    # the plant: the first `<side>_board` chunk; the plant flight: the flight
    # chunk that precedes it
    k_board = next(i for i, lab in enumerate(labels) if lab.endswith("_board") or lab.endswith("_ik"))
    k0 = k_board
    while k0 > 0 and labels[k0 - 1].endswith("_flight"):
        k0 -= 1
    horizon = HORIZON
    if a.start == "pen":
        # back through the penultimate stance (push, land) to its touchdown
        while k0 > 0 and labels[k0 - 1].endswith("_push"):
            k0 -= 1
        while k0 > 0 and labels[k0 - 1].endswith("_land"):
            k0 -= 1
        horizon = HORIZON_PEN
    n = int(round((horizon + 0.1) / sim.task.control_dt)) + 1
    out = {
        "task": a.task, "board_x": float(task.board_x), "seed": -1 if a.seed is None else a.seed,
        "env": json.dumps(env), "params": json.dumps(params), "controller": a.controller,
        "state": states[k0], "t0": times[k0], "t_board": times[k_board], "horizon": horizon,
        "ctrl": np.array(ctrls[k0:k0 + n]), "labels": json.dumps(labels[k0:k0 + n]),
        "muscles": json.dumps([mu.name for mu in sim.muscles]),
        "metrics": json.dumps({k: v for k, v in mt.items() if isinstance(v, (int, float, bool, str)) or v is None},
                              default=float),
    }
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{name}_capture.npz")
    np.savez(path, **out)
    keys = ["official_m", "effective_m", "ballistic_m", "takeoff_vx", "takeoff_vz", "takeoff_angle_deg",
            "contact_time_s", "L_takeoff", "torso_pitch_takeoff"]
    print("captured", path, "plant flight starts", round(times[k0], 3), "board", round(times[k_board], 3),
          labels[k0], {k: mt.get(k) for k in keys})


def load_capture(name):
    z = np.load(os.path.join(OUT, f"{name}_capture.npz"), allow_pickle=False)
    cap = {k: z[k] for k in z.files}
    for k in ("task", "env", "params", "controller", "labels", "muscles", "metrics"):
        cap[k] = str(cap[k])
    cap["board_x"] = float(cap["board_x"])
    cap["horizon"] = float(cap["horizon"]) if "horizon" in cap else HORIZON
    # the plant foot: the one opposite the foot whose flight chunk this is
    first = json.loads(cap["labels"])[0].split(":")[-1]
    cap["plant"] = "r" if first.startswith("l_") else "l"
    return cap


# ---------------------------------------------------------------------------
# evaluation of one excitation program

_W = {}


def _worker(cap_name):
    cap = load_capture(cap_name)
    body = Body(cap["task"], cap["board_x"], json.loads(cap["env"]))
    _W["cap"], _W["body"] = cap, body


def knot_times(horizon=HORIZON):
    return np.arange(0.0, horizon + 1e-9, KNOT)


def excitation(x, t):
    """x: (n_muscles, n_knots) in [0, 1]; linear between knots, held after."""
    tk = KNOT * np.arange(x.shape[1])
    j = min(int(t / KNOT), len(tk) - 2)
    w = min(max((t - tk[j]) / KNOT, 0.0), 1.0)
    return (1 - w) * x[:, j] + w * x[:, j + 1]


def simulate(body, cap, program, record=False, restore=True, until=None):
    """Run from the captured state. `program(t)` returns the 32 excitations for
    control tick t (s since the capture). Returns the take-off summary."""
    m, d = body.m, body.d
    if restore:
        mujoco.mj_setState(m, d, cap["state"], SPEC)
        mujoco.mj_forward(m, d)
    t0 = d.time
    ids = body.act_ids
    td_t = None
    plant = None
    last_contact = None
    snap = None
    rec = []
    rec_c = []
    peak_f = 0.0
    other_foot = 0
    toe_max = -1e9
    knee_max = 0.0   # the plant knee's largest flexion in the stance (rad)
    lifted = set()   # a foot counts for the plant only once it has been off the ground
    weight = float(sum(m.body_mass[1:])) * G
    f6 = np.zeros(6)
    k = 0
    lr = m.actuator_lengthrange[ids]
    span = lr[:, 1] - lr[:, 0]
    while True:
        t = d.time - t0
        if record:
            # the controller's view at the tick start: contraction and its rate
            L = d.actuator_length[ids]
            body_c = (lr[:, 1] - L) / span
            body_cd = -d.actuator_velocity[ids] / span
            rec_c.append((t, body_c.copy(), body_cd.copy()))
        d.ctrl[ids] = np.clip(program(t, k), 0.0, 1.0)
        for _ in range(body.substeps):
            mujoco.mj_step(m, d)
        k += 1
        t = d.time - t0
        feet, other = body.contacts()
        if other:
            return {"valid": False, "why": "body contact", "t": t, "progress": 0.0}
        if record:
            mujoco.mj_subtreeVel(m, d)
            rec.append((t, d.ctrl[ids].copy(), body.torso_pitch(), float(d.subtree_com[body.pelvis][0]),
                        float(d.subtree_com[body.pelvis][2]), float(d.subtree_linvel[body.pelvis][0]),
                        float(d.subtree_linvel[body.pelvis][2])))
        if td_t is None:
            lifted |= {f for f in ("l", "r") if f not in feet}
            down = feet & lifted & {cap["plant"]}
            if down:
                plant = cap["plant"]
                last_contact = t
                td_t = t
                mujoco.mj_subtreeVel(m, d)
                td = {"t": t, "leg_angle_deg": body.leg_angle(plant), "foot_ahead_m": body.ahead(plant),
                      "knee": body.knee(plant), "vx": float(d.subtree_linvel[body.pelvis][0]),
                      "vz": float(d.subtree_linvel[body.pelvis][2]), "com_z": float(d.subtree_com[body.pelvis][2]),
                      "torso_pitch": body.torso_pitch()}
            elif t > cap.get("horizon", HORIZON) - 0.13:
                return {"valid": False, "why": "no touchdown", "t": t, "progress": 0.0}
            continue
        if feet - {plant}:
            other_foot += 1
        feet = feet & {plant}
        if feet:
            last_contact = t
            # vertical ground force on the plant foot
            fz = 0.0
            for i in range(d.ncon):
                c = d.contact[i]
                if (c.geom1 in body.feet or c.geom2 in body.feet) and (c.geom1 == body.runway or c.geom2 == body.runway):
                    mujoco.mj_contactForce(m, d, i, f6)
                    fz += abs(f6[0])
            peak_f = max(peak_f, fz / weight)
            mujoco.mj_subtreeVel(m, d)
            toe_max = max(toe_max, body.foot_front(plant))
            knee_max = max(knee_max, body.knee(plant))
            snap = {"t": t, "com_x": float(d.subtree_com[body.pelvis][0]), "com_z": float(d.subtree_com[body.pelvis][2]),
                    "vx": float(d.subtree_linvel[body.pelvis][0]), "vz": float(d.subtree_linvel[body.pelvis][2]),
                    "L": float(d.subtree_angmom[body.pelvis][1]), "toe": body.foot_front(plant),
                    "torso_pitch": body.torso_pitch(), "knee": body.knee(plant)}
            if t - td_t > STANCE_MAX:
                mujoco.mj_subtreeVel(m, d)
                return {"valid": False, "why": "no take-off", "t": t,
                        "progress": max(0.0, float(d.subtree_linvel[body.pelvis][2]))}
        elif t - last_contact >= AIR_CONFIRM and last_contact - td_t >= MIN_STANCE:
            if until is None:
                break
            # keep running the program into the flight (the skill hands over at
            # the same program time): nothing may touch the runway again
            while not until(d.time - t0):
                d.ctrl[ids] = np.clip(program(d.time - t0, k), 0.0, 1.0)
                for _ in range(body.substeps):
                    mujoco.mj_step(m, d)
                k += 1
                if runway_touch(body):
                    return {"valid": False, "why": "runway after take-off", "t": d.time - t0, "progress": 1.0}
                if d.time - t0 > snap["t"] + 0.5:
                    break
            break
    s = snap
    vx, vz, h = s["vx"], s["vz"], s["com_z"] - LAND_Z
    t_air = (vz + math.sqrt(max(0.0, vz * vz + 2 * G * h))) / G if h > 0 else 0.0
    D = (s["com_x"] - s["toe"]) + vx * t_air
    out = {"valid": True, "D": D, "vx": vx, "vz": vz, "angle_deg": math.degrees(math.atan2(vz, vx)),
           "speed": math.hypot(vx, vz), "contact_s": s["t"] - td_t, "td": td, "L": s["L"],
           "torso_pitch": s["torso_pitch"], "com_z": s["com_z"], "takeoff_dist": s["com_x"] - s["toe"],
           "t_air": t_air, "peak_grf_bw": peak_f, "other_foot": other_foot, "plant": plant,
           "knee_to": s["knee"], "t_to": s["t"], "toe_max": toe_max, "knee_max": knee_max}
    if record:
        out["trace"] = rec
        out["trace_c"] = rec_c
    return out


def runway_touch(body):
    d = body.d
    for i in range(d.ncon):
        c = d.contact[i]
        if (c.geom1 == body.runway and c.geom2 in body.body_geoms) or (c.geom2 == body.runway and c.geom1 in body.body_geoms):
            return True
    return False


def score(r, lmax):
    if not r["valid"]:
        return -5.0 + r.get("t", 0.0) + 0.5 * r.get("progress", 0.0)
    s = r["D"]
    # the free foot touching the runway during the stance (ticks)
    s -= 0.1 * r["other_foot"]
    if r["L"] > lmax:
        s -= 0.2 * (r["L"] - lmax)
    p = r["torso_pitch"]
    s -= 2.0 * (max(0.0, p - 0.8) + max(0.0, -0.5 - p))
    return s


def _eval(job):
    x, lmax = job
    body, cap = _W["body"], _W["cap"]
    X = np.asarray(x).reshape(len(body.muscles), -1)
    r = simulate(body, cap, lambda t, k: excitation(X, t))
    return score(r, lmax), {k: v for k, v in r.items() if k != "trace"}


def recorded_program(cap):
    ctrl = cap["ctrl"]
    return lambda t, k: ctrl[min(k, len(ctrl) - 1)]


def x_from_recorded(cap, n_mus):
    """The recorded excitations averaged around each knot (the search's x0)."""
    ctrl = cap["ctrl"]
    dt = 0.004
    tk = knot_times(cap["horizon"])
    X = np.zeros((n_mus, len(tk)))
    for j, t in enumerate(tk):
        lo, hi = int(max(0.0, t - KNOT / 2) / dt), int((t + KNOT / 2) / dt) + 1
        X[:, j] = ctrl[lo:max(hi, lo + 1)].mean(axis=0) if lo < len(ctrl) else ctrl[-1]
    return X


# ---------------------------------------------------------------------------
# commands

def replay(a):
    cap = load_capture(a.name)
    body = Body(cap["task"], cap["board_x"], json.loads(cap["env"]))
    mt = json.loads(cap["metrics"])
    r = simulate(body, cap, recorded_program(cap))
    X = x_from_recorded(cap, len(body.muscles))
    rk = simulate(body, cap, lambda t, k: excitation(X, t))
    print("rollout  vx %.3f vz %.3f contact %s ballistic %s L %s" % (mt.get("takeoff_vx"), mt.get("takeoff_vz"),
          mt.get("contact_time_s"), mt.get("ballistic_m"), mt.get("L_takeoff")))
    for lab, rr in (("replay", r), ("knots", rk)):
        if rr["valid"]:
            print("%-8s vx %.3f vz %.3f contact %.3f D %.3f L %.2f leg %.1f deg torso %.2f" % (
                lab, rr["vx"], rr["vz"], rr["contact_s"], rr["D"], rr["L"], rr["td"]["leg_angle_deg"], rr["torso_pitch"]))
        else:
            print(lab, rr)


def optimise(a):
    from search import make_optimizer
    cap = load_capture(a.name)
    body = Body(cap["task"], cap["board_x"], json.loads(cap["env"]))
    nm = len(body.muscles)
    X0 = x_from_recorded(cap, nm)
    if a.init:
        # resume from an earlier optimum's knots; an optimum from the plant
        # flight's start used on a capture from the penultimate touchdown is
        # shifted to start where this capture's plant flight starts
        ji = json.load(open(a.init))
        # by role: the init's take-off side may be the other foot
        iplant = ji.get("plant") or load_capture(ji["name"])["plant"]
        by_role = {role_of(n, iplant): v for n, v in ji["knots"].items()}
        Xi = np.array([by_role[role_of(n, cap["plant"])] for n in body.muscles])
        if Xi.shape[1] == X0.shape[1]:
            X0 = Xi
        else:
            labs = json.loads(cap["labels"])
            k_fl = next(i for i, lab in enumerate(labs) if lab.endswith("_flight"))
            t_fl = k_fl * 0.004
            for j, t in enumerate(KNOT * np.arange(X0.shape[1])):
                if t >= t_fl:
                    X0[:, j] = excitation(Xi, t - t_fl)
    x0 = X0.ravel()
    base = simulate(body, cap, recorded_program(cap))
    lmax = float(a.lmax) if a.lmax != "auto" else (base["L"] + 0.5 if base["valid"] else 20.0)
    opt = make_optimizer(a.method, x0, sigma0=a.sigma, seed=a.seed, **({"popsize": a.pop} if a.pop else {}))
    best = (score(simulate(body, cap, lambda t, k: excitation(X0, t)), lmax), x0.copy(), None)
    log = []
    t0 = time.time()
    used = 0
    with mp.Pool(a.workers, initializer=_worker, initargs=(a.name,)) as pool:
        while used < a.evals:
            X = np.clip(np.atleast_2d(opt.ask()), 0.0, 1.0)
            res = pool.map(_eval, [(x, lmax) for x in X], chunksize=max(1, len(X) // (a.workers * 2)))
            f = np.array([r[0] for r in res])
            opt.tell(X, f, [r[1] for r in res])
            used += len(X)
            i = int(np.argmax(f))
            if f[i] > best[0]:
                best = (float(f[i]), X[i].copy(), res[i][1])
            if len(log) % 10 == 0 or used >= a.evals:
                bm = best[2] or {}
                print(f"{a.name}/{a.tag} used {used} best {best[0]:.3f} D {bm.get('D', 0):.3f} vx {bm.get('vx', 0):.2f} "
                      f"vz {bm.get('vz', 0):.2f} contact {bm.get('contact_s', 0):.3f} L {bm.get('L', 0):.1f} "
                      f"({time.time() - t0:.0f}s)", flush=True)
            log.append((used, best[0]))
    Xb = best[1].reshape(nm, -1)
    r = simulate(body, cap, lambda t, k: excitation(Xb, t), record=True)
    save_result(a, cap, body, base, lmax, r, Xb, log)


def save_result(a, cap, body, base, lmax, r, Xb, log):
    tr = r.pop("trace", [])
    r.pop("trace_c", None)
    names = body.muscles
    stance = [row for row in tr if r["valid"] and r["td"]["t"] <= row[0] <= r["t_to"]]
    exc = {}
    if stance:
        E = np.array([row[1] for row in stance])
        for i, n in enumerate(names):
            exc[n] = {"mean": round(float(E[:, i].mean()), 3), "frac_full": round(float((E[:, i] > 0.95).mean()), 3)}
    out = {"name": a.name, "tag": a.tag, "task": cap["task"], "board_x": cap["board_x"], "env": json.loads(cap["env"]),
           "plant": cap["plant"],
           "lmax": lmax, "evals": a.evals, "method": a.method, "knot_s": KNOT, "horizon_s": cap["horizon"],
           "baseline_rollout": json.loads(cap["metrics"]),
           "baseline_replay": {k: v for k, v in base.items() if k != "trace"},
           "ideal": r, "stance_excitation": exc,
           "knots": {n: [float(v) for v in Xb[i]] for i, n in enumerate(names)},
           "curve": log[:: max(1, len(log) // 200)]}
    path = os.path.join(OUT, f"{a.name}_{a.tag}.json")
    with open(path, "w") as f:
        json.dump(out, f, indent=1, default=float)
    print("wrote", path)
    print(json.dumps({k: (round(v, 3) if isinstance(v, float) else v) for k, v in r.items() if k != "td"}))
    print("touchdown", json.dumps({k: round(v, 3) for k, v in r.get("td", {}).items()}))


def role_of(name, plant):
    """A muscle's role name: T_ (the take-off leg's side), F_ (the free side)
    or the muscle itself (unsided)."""
    free = "r" if plant == "l" else "l"
    if name.startswith(plant + "_"):
        return "T_" + name[2:]
    if name.startswith(free + "_"):
        return "F_" + name[2:]
    return name


def distil(a):
    """The ideal program as robolab knots: on the ideal's own knot grid (every
    KNOT s from the plant flight's start), per muscle role, the contraction c,
    its velocity v and acceleration a (quintic Hermite knots, from the ideal
    trajectory's contraction trace as the controller senses it) and the
    excitation e (the drive knots, linear between knots); plus the grid, the
    ideal plant touchdown time (the program's latch point) and take-off time.
    Written as a params file for LongJumpRunSkill's `j_ik` program."""
    cap = load_capture(a.name)
    body = Body(cap["task"], cap["board_x"], json.loads(cap["env"]))
    j = json.load(open(os.path.join(OUT, f"{a.name}_{a.tag}.json")))
    names = body.muscles
    X = np.array([j["knots"][n] for n in names])
    r = simulate(body, cap, lambda t, k: excitation(X, t), record=True)
    tc = r["trace_c"]
    T = np.array([row[0] for row in tc])
    C = np.array([row[1] for row in tc])
    tk = KNOT * np.arange(X.shape[1])
    # smooth velocity / acceleration of the sensed contraction at the knots
    dt = T[1] - T[0]
    V = np.gradient(C, dt, axis=0)
    A = np.gradient(V, dt, axis=0)
    w = max(1, int(round(0.012 / dt)))
    kern = np.ones(2 * w + 1) / (2 * w + 1)

    def smooth(Y):
        pad = np.pad(Y, ((w, w), (0, 0)), mode="edge")
        return np.array([np.convolve(pad[:, i], kern, mode="valid") for i in range(Y.shape[1])]).T

    Vs, As = smooth(V), smooth(smooth(A))
    lines = [f"# ideal take-off program {a.name}_{a.tag}: D {r['D']:.3f} m, vx {r['vx']:.3f}, vz {r['vz']:.3f}, "
             f"contact {r['contact_s']:.3f} s, touchdown at {r['td']['t']:.3f} s, take-off at {r['t_to']:.3f} s",
             "j_ik 1", f"ik_h {KNOT!r}", f"ik_n {len(tk)}", f"ik_td {r['td']['t']!r}", f"ik_to {r['t_to']!r}",
             f"ik_from {1 if cap['horizon'] > HORIZON + 1e-9 else 0}"]
    for kk, t in enumerate(tk):
        i = int(np.clip(np.searchsorted(T, t), 0, len(T) - 1))
        if i > 0 and abs(T[i - 1] - t) < abs(T[i] - t):
            i -= 1
        # linear interpolation of c between ticks; v, a from the smoothed traces
        if i + 1 < len(T) and T[i] <= t:
            u = (t - T[i]) / dt
            c = (1 - u) * C[i] + u * C[i + 1]
        else:
            c = C[i]
        for mi, n in enumerate(names):
            role = role_of(n, cap["plant"])
            lines.append(f"ik_c{kk}_{role} {float(c[mi])!r}")
            lines.append(f"ik_v{kk}_{role} {float(Vs[i, mi])!r}")
            lines.append(f"ik_a{kk}_{role} {float(As[i, mi])!r}")
            lines.append(f"ik_e{kk}_{role} {float(X[mi, kk])!r}")
    # how well the quintic through these knots follows the sensed contraction
    cq = np.zeros_like(C)
    kv = {}
    for kk, t in enumerate(tk):
        kv[kk] = [float(x.split()[1]) for x in lines if x.startswith((f"ik_c{kk}_", ))]
    err = []
    for ii, t in enumerate(T):
        jj = min(int(t / KNOT), len(tk) - 2)
        u = (t - tk[jj]) / KNOT
        h = [u - 6 * u ** 3 + 8 * u ** 4 - 3 * u ** 5, 0.5 * u ** 2 - 1.5 * u ** 3 + 1.5 * u ** 4 - 0.5 * u ** 5,
             0.5 * u ** 3 - u ** 4 + 0.5 * u ** 5, -4 * u ** 3 + 7 * u ** 4 - 3 * u ** 5]
        p = 10 * u ** 3 - 15 * u ** 4 + 6 * u ** 5
        c0, c1 = np.array(kv[jj]), np.array(kv[jj + 1])
        i0 = int(np.argmin(np.abs(T - tk[jj])))
        i1 = int(np.argmin(np.abs(T - tk[jj + 1])))
        q = c0 + (c1 - c0) * p + KNOT * h[0] * Vs[i0] + KNOT ** 2 * h[1] * As[i0] + KNOT ** 2 * h[2] * As[i1] + KNOT * h[3] * Vs[i1]
        if t <= r["t_to"]:
            err.append(np.abs(q - C[ii]))
    err = np.array(err)
    out = a.out or os.path.join(ROOT, "params", f"long_jump_ik_{a.name}.txt")
    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", out, len(lines), "lines; quintic vs sensed contraction to take-off: mean |err|",
          round(float(err.mean()), 4), "max", round(float(err.max()), 4), "plant", cap["plant"])


# ---------------------------------------------------------------------------
# the skill's program, closed loop, over many approach states (`robust`)
#
# LongJumpRunSkill#ik_apply in Python, tick for tick: from the frame at the
# tick start (contraction c and rate cdot as the bridge computes them, the
# plant foot's contact force / body weight as Sim.contacts does), every
# muscle's activation is clamp(e(s) + gap_err e1(s) + kdc g kd v*(s)
# + g (kp (c*(s) - c) - kd cdot), 0, 1), with c*(s), v*(s) the quintic through
# the (c, v, a) knots, e linear between drive knots, one reflex gain g for all
# muscles, the reflex's own kp / kd per muscle, and the program clock s
# latched to the plant touchdown as the skill latches it. gap_err is where
# the penultimate foot's toe is (board - toe x at the program's start) minus
# ik_gap0: the plant step's feedback on the board.

def reflex_gains(names, params):
    kp = np.full(len(names), 6.0)
    kd = np.full(len(names), 0.25)
    legs = ("l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle", "l_toe", "r_toe",
            "l_rf", "r_rf", "l_ham", "r_ham", "l_gas", "r_gas")
    biart = ("l_rf", "r_rf", "l_ham", "r_ham", "l_gas", "r_gas")
    lkp, lkd, bg = params.get("leg_kp", 6.0), params.get("leg_kd", 0.3), params.get("bi_gain", 1.0)
    for i, n in enumerate(names):
        if n.startswith(legs):
            kp[i], kd[i] = lkp, lkd
        if n.startswith(biart):
            kp[i], kd[i] = lkp * bg, lkd * bg
    return kp, kd


def read_ik(path, names, plant, nk=None):
    from search import read_params
    p = read_params(path)
    n = int(round(p["ik_n"])) if nk is None else nk
    tab = {q: np.zeros((n, len(names))) for q in ("c", "v", "a", "e", "e1")}
    key = {"c": "c", "v": "v", "a": "a", "e": "e", "e1": "g"}  # (the gap knots are ik_g<k>_<role>)
    for k in range(n):
        for i, nm in enumerate(names):
            role = role_of(nm, plant)
            for q in tab:
                tab[q][k, i] = p.get(f"ik_{key[q]}{k}_{role}", 0.0)
    tab["fmin"] = p.get("ik_fmin", 0.05)
    tab["fbclip"] = int(round(p.get("ik_fbclip", 0.0)))
    if "ik_pr0" in p:
        tab["pr"] = np.array([p.get(f"ik_pr{k}", 0.0) for k in range(n)])
        tab["fkp"] = np.array([p.get(f"ik_kp_{role_of(nm, plant)}", 0.0) for nm in names])
        tab["fkd"] = np.array([p.get(f"ik_kd_{role_of(nm, plant)}", 0.0) for nm in names])
    if "ik_clz" in p:
        tab["clz"], tab["clt"] = p["ik_clz"], p.get("ik_clt", 0.04)
        tab["ckc"] = np.array([p.get(f"ik_kc_{role_of(nm, plant)}", 0.0) for nm in names])
    return p, tab


def quintic_eval(tab, s, h, nk):
    j = min(max(int(s / h), 0), nk - 2)
    u = min(max((s - h * j) / h, 0.0), 1.0)
    u2, u3, u4, u5 = u * u, u ** 3, u ** 4, u ** 5
    b0 = u - 6 * u3 + 8 * u4 - 3 * u5
    b1 = 0.5 * u2 - 1.5 * u3 + 1.5 * u4 - 0.5 * u5
    b2 = 0.5 * u3 - u4 + 0.5 * u5
    b3 = -4 * u3 + 7 * u4 - 3 * u5
    p = 10 * u3 - 15 * u4 + 6 * u5
    dp = 30 * u2 - 60 * u3 + 30 * u4
    d1 = 1 - 18 * u2 + 32 * u3 - 15 * u4
    d2 = u - 4.5 * u2 + 6 * u3 - 2.5 * u4
    d3 = 1.5 * u2 - 4 * u3 + 2.5 * u4
    d4 = -12 * u2 + 28 * u3 - 15 * u4
    C, V, A = tab["c"], tab["v"], tab["a"]
    c = C[j] + (C[j + 1] - C[j]) * p + h * b0 * V[j] + h * h * b1 * A[j] + h * h * b2 * A[j + 1] + h * b3 * V[j + 1]
    v = ((C[j + 1] - C[j]) * dp + h * d1 * V[j] + h * h * d2 * A[j] + h * h * d3 * A[j + 1] + h * d4 * V[j + 1]) / h
    e = tab["e"][j] + (tab["e"][j + 1] - tab["e"][j]) * u
    e1 = tab["e1"][j] + (tab["e1"][j + 1] - tab["e1"][j]) * u
    return c, v, e, e1


def seen_site_x(body, site):
    """A site's x as the controller's frame sees it at a tick start: the
    bridge reads site positions after mj_step, i.e. the kinematics of the
    configuration at the START of the last physics step, qpos - dt qvel
    (MuJoCo's position update is qpos += dt qvel_new). Restores the state."""
    m, d = body.m, body.d
    q = d.qpos.copy()
    prev = q.copy()
    mujoco.mj_integratePos(m, prev, d.qvel, -m.opt.timestep)
    d.qpos[:] = prev
    mujoco.mj_kinematics(m, d)
    x = float(d.site(site).xpos[0])
    d.qpos[:] = q
    mujoco.mj_forward(m, d)
    return x


class IKProgram:
    """LongJumpRunSkill#ik_apply. Optional extras in `tab` (all off when absent):
    fmin  the plant foot's contact force (body weights) that counts as its
          touchdown (0.05: any touch; a scuff of the swing foot is < 1)
    pr / fkp / fkd  rotation feedback: torso pitch reference knots (rad, every
          h s) and per-muscle gains on the pitch error and the pitch rate
    ckc / clz / clt  swing-foot clearance reflex: before the plant, while the
          lower of the plant foot's toe and heel is below clz (m) and the
          program is more than clt s before the ideal touchdown, every muscle's
          drive gets ckc x (clz - height)"""

    def __init__(self, tab, h, td, g, kdc, kp, kd, gap0, end=None):
        self.tab, self.h, self.td, self.g, self.kdc, self.kp, self.kd, self.gap0 = tab, h, td, g, kdc, kp, kd, gap0
        self.nk = tab["c"].shape[0]
        self.end = end   # program time (s) at which the skill hands over to the hang
        self.fmin = tab.get("fmin", 0.05)

    def start(self, body, cap):
        m, d = body.m, body.d
        pen = "l" if cap["plant"] == "r" else "r"
        self.gap_err = (cap["board_x"] - seen_site_x(body, f"{pen}_toe")) - self.gap0
        self.shift, self.td_seen, self.lifted, self.t0 = 0.0, False, False, d.time
        lr = m.actuator_lengthrange[body.act_ids]
        self.lo, self.span = lr[:, 0], lr[:, 1] - lr[:, 0]
        self.hi = lr[:, 1]
        self.weight = float(sum(m.body_mass[1:])) * G
        self.plant_geoms = {g for g, f in body.feet.items() if f == cap["plant"]}
        self.f6 = np.zeros(6)
        self.site_toe = m.site(f"{cap['plant']}_toe").id
        self.site_heel = m.site(f"{cap['plant']}_heel").id

    def foot_force(self, body):
        m, d = body.m, body.d
        tot = 0.0
        for i in range(d.ncon):
            c = d.contact[i]
            if c.geom1 in self.plant_geoms or c.geom2 in self.plant_geoms:
                mujoco.mj_contactForce(m, d, i, self.f6)
                tot += abs(self.f6[0])
        return tot / self.weight

    def __call__(self, body, t, k):
        d = body.d
        s = t + self.shift
        if not self.td_seen:
            down = self.foot_force(body) > self.fmin
            if not down:
                self.lifted = True
            if down and self.lifted and s > 0.03:
                self.td_seen = True
                self.shift += self.td - s
                s = self.td
            elif s > self.td:
                self.shift -= s - self.td
                s = self.td
        self.s = s
        ids = body.act_ids
        c = (self.hi - d.actuator_length[ids]) / self.span
        cd = -d.actuator_velocity[ids] / self.span
        cs, vs, e, e1 = quintic_eval(self.tab, s, self.h, self.nk)
        g = self.g if k > 0 else 0.0  # (the skill's first program tick runs without feedback)
        out = e + self.gap_err * e1 + self.kdc * g * self.kd * vs + g * (self.kp * (cs - c) - self.kd * cd)
        tab = self.tab
        if "pr" in tab:
            # rotation feedback (LongJumpRunSkill#ik_feedback)
            j = min(max(int(s / self.h), 0), self.nk - 2)
            u = min(max((s - self.h * j) / self.h, 0.0), 1.0)
            pr = tab["pr"]
            err = body.torso_pitch() - (pr[j] + (pr[j + 1] - pr[j]) * u)
            fbc = tab.get("fbclip", 0)
            if fbc > 0:
                err = max(err, 0.0)   # leaning more forward than the program's own average only
            elif fbc < 0:
                err = min(err, 0.0)
            out = out + tab["fkp"] * err + tab["fkd"] * torso_rate(body)
        if "ckc" in tab and not self.td_seen and s < self.td - tab["clt"]:
            z = min(float(d.site_xpos[self.site_toe][2]), float(d.site_xpos[self.site_heel][2]))
            if z < tab["clz"]:
                out = out + tab["ckc"] * (tab["clz"] - z)
        return out


def simulate_prog(body, cap, prog):
    m, d = body.m, body.d
    mujoco.mj_setState(m, d, cap["state"], SPEC)
    mujoco.mj_forward(m, d)
    prog.start(body, cap)
    until = None
    if prog.end is not None:
        until = lambda t: prog.td_seen and t + prog.shift > prog.end
    return simulate(body, cap, lambda t, k: prog(body, t, k), restore=False, until=until)


def board_score(r, cap, lmax):
    """Official-like: the COM's ballistic landing point from the real board
    (com x + vx t_air - board); a take-off foot past the board is a graded foul."""
    if not r["valid"]:
        return -5.0 + r.get("t", 0.0) + 0.5 * r.get("progress", 0.0)
    D_board = r["D"] - (cap["board_x"] - r["toe_max"])
    s = D_board
    if r["toe_max"] > cap["board_x"]:
        s = -1.0 - 4.0 * (r["toe_max"] - cap["board_x"])
    s -= 0.1 * r["other_foot"]
    if r["L"] > lmax:
        s -= 0.2 * (r["L"] - lmax)
    p = r["torso_pitch"]
    s -= 2.0 * (max(0.0, p - 0.8) + max(0.0, -0.5 - p))
    return s


_R = {}


def _rworker(names):
    _R["caps"] = [load_capture(n) for n in names]
    c0 = _R["caps"][0]
    _R["body"] = Body(c0["task"], c0["board_x"], json.loads(c0["env"]))


def _decode(x, base, nk, n_mus):
    k = nk * n_mus
    E = np.clip(x[:k].reshape(nk, n_mus), 0.0, 1.0)
    dC = (x[k:2 * k].reshape(nk, n_mus) - 0.5) * 0.2
    E1 = (x[2 * k:3 * k].reshape(nk, n_mus) - 0.5) * 4.0
    g = float(np.clip(x[3 * k], 0.0, 1.0)) * 1.5
    tab = {"c": base["c"] + dC, "v": base["v"], "a": base["a"], "e": E, "e1": E1}
    return tab, g


def _reval(job):
    x, base, meta = job
    body, caps = _R["body"], _R["caps"]
    tab, g = _decode(np.asarray(x), base, meta["nk"], len(body.muscles))
    prog = IKProgram(tab, meta["h"], meta["td"], g, 1.0, meta["kp"], meta["kd"], meta["gap0"], meta.get("end"))
    scores, rows = [], []
    for cap in caps:
        r = simulate_prog(body, cap, prog)
        scores.append(board_score(r, cap, meta["lmax"]))
        rows.append({k: r.get(k) for k in ("D", "vx", "vz", "contact_s", "toe_max", "valid")})
    sc = np.array(scores)
    mean = float(sc.mean())
    return mean - meta["risk"] * (mean - float(sc.min())), {"mean": mean, "min": float(sc.min()), "scores": scores}


def robust(a):
    from search import make_optimizer, read_params
    names = [n for n in a.captures.split(",") if n]
    caps = [load_capture(n) for n in names]
    body = Body(caps[0]["task"], caps[0]["board_x"], json.loads(caps[0]["env"]))
    mus = body.muscles
    params = json.loads(caps[0]["params"])
    kp, kd = reflex_gains(mus, params)
    pfile, base = read_ik(a.ik, mus, caps[0]["plant"], nk=a.nk)
    # the board gap each start's program sees at its start (penultimate toe)
    gaps = []
    for cap in caps:
        mujoco.mj_setState(body.m, body.d, cap["state"], SPEC)
        mujoco.mj_forward(body.m, body.d)
        pen = "l" if cap["plant"] == "r" else "r"
        gaps.append(cap["board_x"] - seen_site_x(body, f"{pen}_toe"))
    gap0 = float(np.median(gaps))
    meta = {"nk": a.nk, "h": pfile["ik_h"], "td": pfile["ik_td"], "kp": kp, "kd": kd, "gap0": gap0,
            "lmax": float(a.lmax), "risk": a.risk, "end": pfile["ik_td"] + a.post}
    n = len(mus)
    x0 = np.concatenate([np.clip(base["e"], 0, 1).ravel(), np.full(a.nk * n, 0.5), np.full(a.nk * n, 0.5), [a.g0 / 1.5]])
    if a.init:
        # start from an earlier robust program (knots beyond its grid repeat its last)
        pi = read_params(a.init)
        ni = int(round(pi["ik_n"]))
        _, ti = read_ik(a.init, mus, caps[0]["plant"], nk=ni)
        ext = lambda A: np.vstack([A[:a.nk]] + [A[-1:]] * max(0, a.nk - ni))
        E0 = np.clip(ext(ti["e"]), 0, 1)
        dC0 = np.clip((ext(ti["c"]) - base["c"]) / 0.2 + 0.5, 0, 1)
        G0 = np.clip(ext(ti["e1"]) / 4.0 + 0.5, 0, 1)
        x0 = np.concatenate([E0.ravel(), dC0.ravel(), G0.ravel(), [pi.get("j_ik_g", a.g0) / 1.5]])
    print(f"robust: {len(caps)} starts, gaps {np.round(gaps, 2).tolist()} (gap0 {gap0:.3f}), {len(x0)} dims", flush=True)
    opt = make_optimizer(a.method, x0, sigma0=a.sigma, seed=a.seed, **({"popsize": a.pop} if a.pop else {}))
    t0 = time.time()
    used = 0
    best = (-1e9, x0, None)
    with mp.Pool(a.workers, initializer=_rworker, initargs=(names,)) as pool:
        f0, m0 = pool.apply(_reval, ((x0, base, meta),))
        best = (f0, x0.copy(), m0)
        print(f"x0 {f0:.3f} {json.dumps({k: round(v, 3) for k, v in m0.items() if k != 'scores'})} "
              f"{np.round(m0['scores'], 2).tolist()}", flush=True)
        gen = 0
        while used < a.evals:
            X = np.clip(np.atleast_2d(opt.ask()), 0.0, 1.0)
            res = pool.map(_reval, [(x, base, meta) for x in X], chunksize=1)
            f = np.array([r[0] for r in res])
            opt.tell(X, f, [r[1] for r in res])
            used += len(X) * len(caps)
            gen += 1
            i = int(np.argmax(f))
            if f[i] > best[0]:
                best = (float(f[i]), X[i].copy(), res[i][1])
            if gen % 10 == 0:
                bm = best[2]
                print(f"gen {gen} sims {used} best {best[0]:.3f} mean {bm['mean']:.3f} min {bm['min']:.3f} "
                      f"({time.time() - t0:.0f}s)", flush=True)
                write_program(a.out, best[1], base, meta, n, mus, caps[0]["plant"], pfile, best, gaps)
    write_program(a.out, best[1], base, meta, n, mus, caps[0]["plant"], pfile, best, gaps)
    print("best", best[0], json.dumps({k: v for k, v in best[2].items() if k != "scores"}),
          np.round(best[2]["scores"], 2).tolist())


def write_program(path, x, base, meta, n, mus, plant, pfile, best, gaps):
    tab, g = _decode(np.asarray(x), base, meta["nk"], n)
    lines = [f"# robust ik program: {len(gaps)} starts, score {best[0]:.3f} (mean {best[2]['mean']:.3f}, "
             f"min {best[2]['min']:.3f}); board-relative scores {np.round(best[2]['scores'], 2).tolist()}",
             "j_ik 1", f"ik_h {meta['h']!r}", f"ik_n {meta['nk']}", f"ik_td {meta['td']!r}",
             f"ik_gap0 {meta['gap0']!r}", f"ik_end {meta['end']!r}", f"j_ik_g {g!r}", "j_ik_kdc 1.0",
             f"ik_from {int(round(pfile.get('ik_from', 0)))}"]
    for k in range(meta["nk"]):
        for i, nm in enumerate(mus):
            role = role_of(nm, plant)
            for q, kq in (("c", "c"), ("v", "v"), ("a", "a"), ("e", "e"), ("e1", "g")):
                lines.append(f"ik_{kq}{k}_{role} {float(tab[q][k, i])!r}")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


# ---------------------------------------------------------------------------
# residuals learned around a fixed take-off program (`robustfb`)
#
# The program's knots stay as they are; on top of it (LongJumpRunSkill#ik_feedback)
# a zero-initialised feedback: per-muscle gains on the torso pitch's error against
# the program's own average pitch trajectory and on its rate (the approach's trunk
# lean sets how strong the take-off is: vz falls ~4 m/s per rad of pitch at the
# penultimate touchdown), and per-muscle gains on the swing foot's clearance
# deficit (a foot dragging along the runway before the plant scuffs the whole
# take-off). Trained on many captured approaches; the score is the board-relative
# ballistic distance (board_score) with the check-mark shift `delta`, tail-weighted.

KP_SCALE, KD_SCALE, KC_SCALE = 16.0, 2.0, 60.0   # x in [0, 1], 0.5 = zero gain


class RecProg(IKProgram):
    """IKProgram that records (program time, torso pitch) every tick."""

    def start(self, body, cap):
        super().start(body, cap)
        self.rec = []

    def __call__(self, body, t, k):
        out = super().__call__(body, t, k)
        self.rec.append((self.s, body.torso_pitch()))
        return out


def nominal_pitch(body, caps, base, meta):
    """The torso pitch at each program knot, averaged over the captured starts."""
    ks = meta["h"] * np.arange(meta["nk"])
    acc = []
    for cap in caps:
        prog = RecProg(base, meta["h"], meta["td"], meta["g"], meta["kdc"], meta["kp"], meta["kd"], meta["gap0"], meta["end"])
        r = simulate_prog(body, cap, prog)
        if not r["valid"]:
            continue
        s = np.array([x[0] for x in prog.rec])
        pt = np.array([x[1] for x in prog.rec])
        keep = np.r_[True, np.diff(s) > 1e-9]   # (the clock waits at the ideal touchdown: keep the first tick)
        acc.append(np.interp(ks, s[keep], pt[keep]))
    return np.mean(acc, axis=0)


def board_score2(r, cap, lmax, delta, vzmin=0.0, vzw=0.0):
    """board_score with the foul line `delta` m farther than the capture's (a
    check mark moved back: the program's own gap feedback is unchanged), and a
    penalty vzw per m/s of take-off vz below vzmin (a low, short flight lands
    with the legs still hanging: the landings that roll over are the weak
    take-offs)."""
    if not r["valid"]:
        return -5.0 + r.get("t", 0.0) + 0.5 * r.get("progress", 0.0)
    board = cap["board_x"] + delta
    s = r["D"] - (board - r["toe_max"])
    if r["toe_max"] > board:
        s = -1.0 - 4.0 * (r["toe_max"] - board)
    s -= 0.1 * r["other_foot"]
    if r["L"] > lmax:
        s -= 0.2 * (r["L"] - lmax)
    p = r["torso_pitch"]
    s -= 2.0 * (max(0.0, p - 0.8) + max(0.0, -0.5 - p))
    if vzw > 0.0:
        s -= vzw * max(0.0, vzmin - r["vz"])
    return s


def _fbdecode(x, base, pr, nk, n):
    tab = dict(base)
    tab["pr"] = pr
    tab["fkp"] = (x[:n] - 0.5) * KP_SCALE
    tab["fkd"] = (x[n:2 * n] - 0.5) * KD_SCALE
    tab["ckc"] = (x[2 * n:3 * n] - 0.5) * KC_SCALE
    tab["clz"] = 0.02 + 0.10 * float(x[3 * n])
    tab["clt"] = 0.04
    tab["fmin"] = 0.05 + 1.45 * float(np.round(x[3 * n + 1]))   # a switch: 0.05 (any touch) or 1.5 BW
    return tab


def _fbeval(job):
    x, base, pr, meta = job
    body, caps = _R["body"], _R["caps"]
    n = len(body.muscles)
    tab = _fbdecode(np.asarray(x), base, pr, meta["nk"], n)
    prog = IKProgram(tab, meta["h"], meta["td"], meta["g"], meta["kdc"], meta["kp"], meta["kd"], meta["gap0"], meta["end"])
    sc = np.array([board_score2(simulate_prog(body, cap, prog), cap, meta["lmax"], meta["delta"], meta["vzmin"], meta["vzw"])
                   for cap in caps])
    return tail_score(sc, meta), {"mean": float(sc.mean()), "min": float(sc.min()), "scores": sc.tolist()}


def tail_score(sc, meta):
    q = max(1, int(round(meta["tail_q"] * len(sc))))
    worst = np.sort(sc)[:q].mean()
    return float((1.0 - meta["tail_w"]) * sc.mean() + meta["tail_w"] * worst)


def _fbworker(names):
    _rworker(names)


def fb_capture_names(a):
    import glob
    names = sorted(os.path.basename(p)[:-len("_capture.npz")] for p in glob.glob(os.path.join(OUT, f"{a.prefix}_s*_capture.npz")))
    hold = [n for i, n in enumerate(names) if a.holdout and i % a.holdout == a.holdout - 1]
    train = [n for n in names if n not in hold]
    return train, hold


def write_fb(path, base_file, tab, pr, plant, mus):
    """base program file + the feedback lines."""
    keep = []
    for line in open(base_file):
        k = line.split()[0] if line.split() else ""
        if k.startswith(("ik_pr", "ik_kp_", "ik_kd_", "ik_kc_")) or k in ("ik_clz", "ik_clt", "ik_fmin", "ik_fbclip"):
            continue
        keep.append(line.rstrip("\n"))
    lines = keep + ["ik_fmin %r" % float(tab["fmin"]), "ik_clz %r" % float(tab["clz"]), "ik_clt %r" % float(tab["clt"]),
                    "ik_fbclip %r" % float(tab.get("fbclip", 0))]
    lines += [f"ik_pr{k} {float(v)!r}" for k, v in enumerate(pr)]
    for i, nm in enumerate(mus):
        role = role_of(nm, plant)
        lines += [f"ik_kp_{role} {float(tab['fkp'][i])!r}", f"ik_kd_{role} {float(tab['fkd'][i])!r}",
                  f"ik_kc_{role} {float(tab['ckc'][i])!r}"]
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def summarise(scores, label):
    sc = np.array(scores)
    return (f"{label}: n {len(sc)} mean {sc.mean():.3f} min {sc.min():.2f} invalid {int((sc < -3).sum())} "
            f"foul {int(((sc < 0) & (sc > -3)).sum())} weak(<4.2) {int(((sc >= 0) & (sc < 4.2)).sum())}")


def _gtab(g, base, pr, meta):
    tab = dict(base)
    tab["pr"] = pr
    tab["fbclip"] = meta["fbclip"]
    tab["fkp"], tab["fkd"], tab["ckc"] = g["kp"], g["kd"], g["kc"]
    tab["clz"], tab["clt"], tab["fmin"] = meta["clz"], meta["clt"], meta["fmin"]
    return tab


def _geval(job):
    g, base, pr, meta = job
    body, caps = _R["body"], _R["caps"]
    prog = IKProgram(_gtab(g, base, pr, meta), meta["h"], meta["td"], meta["g"], meta["kdc"], meta["kp"], meta["kd"],
                     meta["gap0"], meta["end"])
    sc = np.array([board_score2(simulate_prog(body, cap, prog), cap, meta["lmax"], meta["delta"], meta["vzmin"], meta["vzw"])
                   for cap in caps])
    return tail_score(sc, meta), {"mean": float(sc.mean()), "min": float(sc.min()), "scores": sc.tolist()}


def greedyfb(a):
    """Forward selection of feedback gains around the fixed take-off program: each round every single-channel move
    (a per-muscle pitch-feedback gain kp / kd, a per-muscle clearance-reflex gain kc) is tried on all the training
    starts and the best one kept; stops when no move improves the tail-weighted score by --eps."""
    from search import read_params
    train, hold = fb_capture_names(a)
    caps = [load_capture(n) for n in train]
    body = Body(caps[0]["task"], caps[0]["board_x"], json.loads(caps[0]["env"]))
    mus = body.muscles
    n = len(mus)
    plant = caps[0]["plant"]
    kp, kd = reflex_gains(mus, json.loads(caps[0]["params"]))
    pfile, base = read_ik(a.ik, mus, plant)
    nk = int(round(pfile["ik_n"]))
    meta = {"nk": nk, "h": pfile["ik_h"], "td": pfile["ik_td"], "g": pfile["j_ik_g"], "kdc": pfile.get("j_ik_kdc", 1.0),
            "kp": kp, "kd": kd, "gap0": pfile["ik_gap0"], "end": pfile["ik_end"], "lmax": float(a.lmax), "delta": a.delta,
            "tail_q": a.tail_q, "tail_w": a.tail_w, "vzmin": a.vzmin, "vzw": a.vzw, "fbclip": a.fbclip, "clz": a.clz,
            "clt": a.clt, "fmin": 1.5 if a.fmin_on else 0.05}
    pr = nominal_pitch(body, caps, base, meta)
    g = {"kp": np.zeros(n), "kd": np.zeros(n), "kc": np.zeros(n)}
    if a.init:
        pi = read_params(a.init)
        for key, pre in (("kp", "ik_kp_"), ("kd", "ik_kd_"), ("kc", "ik_kc_")):
            g[key] = np.array([pi.get(pre + role_of(m_, plant), 0.0) for m_ in mus])
    steps = {"kp": [float(x) for x in a.kp_steps.split(",")], "kd": [float(x) for x in a.kd_steps.split(",")],
             "kc": [float(x) for x in a.kc_steps.split(",")]}
    channels = [c for c in a.channels.split(",") if c]
    muscles = [i for i, m_ in enumerate(mus) if not a.only or any(sub in m_ for sub in a.only.split(","))]
    hold_caps = [load_capture(nm) for nm in hold]

    def hold_eval(gg):
        prog = IKProgram(_gtab(gg, base, pr, meta), meta["h"], meta["td"], meta["g"], meta["kdc"], kp, kd, meta["gap0"], meta["end"])
        return [board_score2(simulate_prog(body, cap, prog), cap, meta["lmax"], meta["delta"], meta["vzmin"], meta["vzw"])
                for cap in hold_caps]

    t0 = time.time()
    with mp.Pool(a.workers, initializer=_fbworker, initargs=(train,)) as pool:
        f_cur, m_cur = pool.apply(_geval, ((g, base, pr, meta),))
        print(f"start (no feedback, plant latch {meta['fmin']}): tail {f_cur:.3f} " + summarise(m_cur["scores"], "train"), flush=True)
        if hold_caps:
            print("   " + summarise(hold_eval(g), "held out"), flush=True)
        for rnd in range(a.rounds):
            cands, labels = [], []
            for ch in channels:
                for i in muscles:
                    for st in steps[ch]:
                        g2 = {k: v.copy() for k, v in g.items()}
                        g2[ch][i] += st
                        cands.append((g2, base, pr, meta))
                        labels.append((ch, mus[i], st))
            res = pool.map(_geval, cands, chunksize=1)
            f = np.array([r[0] for r in res])
            j = int(np.argmax(f))
            print(f"round {rnd + 1}: {len(cands)} moves ({time.time() - t0:.0f}s); best {labels[j]} -> tail {f[j]:.3f} "
                  f"(was {f_cur:.3f}); next best " + ", ".join(f"{labels[k]} {f[k]:.3f}" for k in np.argsort(-f)[1:4]), flush=True)
            if f[j] < f_cur + a.eps:
                print("no move improves the score; stopping")
                break
            g, f_cur, m_cur = cands[j][0], float(f[j]), res[j][1]
            print("   " + summarise(m_cur["scores"], "train"), flush=True)
            if hold_caps:
                print("   " + summarise(hold_eval(g), "held out"), flush=True)
            write_fb(a.out, a.ik, _gtab(g, base, pr, meta), pr, plant, mus)
    write_fb(a.out, a.ik, _gtab(g, base, pr, meta), pr, plant, mus)
    print("gains: " + ", ".join(f"{ch}[{mus[i]}]={g[ch][i]:+.1f}" for ch in ("kp", "kd", "kc") for i in range(n) if g[ch][i] != 0.0))


def robustfb(a):
    from search import make_optimizer, read_params
    train, hold = fb_capture_names(a)
    caps = [load_capture(n) for n in train]
    body = Body(caps[0]["task"], caps[0]["board_x"], json.loads(caps[0]["env"]))
    mus = body.muscles
    n = len(mus)
    params = json.loads(caps[0]["params"])
    kp, kd = reflex_gains(mus, params)
    pfile, base = read_ik(a.ik, mus, caps[0]["plant"])
    nk = int(round(pfile["ik_n"]))
    meta = {"nk": nk, "h": pfile["ik_h"], "td": pfile["ik_td"], "g": pfile["j_ik_g"], "kdc": pfile.get("j_ik_kdc", 1.0),
            "kp": kp, "kd": kd, "gap0": pfile["ik_gap0"], "end": pfile["ik_end"], "lmax": float(a.lmax), "delta": a.delta,
            "tail_q": a.tail_q, "tail_w": a.tail_w, "vzmin": a.vzmin, "vzw": a.vzw}
    pr = nominal_pitch(body, caps, base, meta)
    print(f"robustfb: {len(caps)} training starts, {len(hold)} held out; nominal pitch by knot {np.round(pr, 2).tolist()}", flush=True)
    x0 = np.concatenate([np.full(3 * n, 0.5), [0.3, 0.0]])
    if a.init:
        # resume: an earlier robustfb file's gains
        pi = read_params(a.init)
        x0[:n] = [pi.get(f"ik_kp_{role_of(m_, caps[0]['plant'])}", 0.0) / KP_SCALE + 0.5 for m_ in mus]
        x0[n:2 * n] = [pi.get(f"ik_kd_{role_of(m_, caps[0]['plant'])}", 0.0) / KD_SCALE + 0.5 for m_ in mus]
        x0[2 * n:3 * n] = [pi.get(f"ik_kc_{role_of(m_, caps[0]['plant'])}", 0.0) / KC_SCALE + 0.5 for m_ in mus]
        x0[3 * n] = (pi.get("ik_clz", 0.05) - 0.02) / 0.10
        x0[3 * n + 1] = 1.0 if pi.get("ik_fmin", 0.05) > 0.5 else 0.0
        x0 = np.clip(x0, 0.0, 1.0)
    if a.fmin_on:
        x0[3 * n + 1] = 1.0
    opt = make_optimizer(a.method, x0, sigma0=a.sigma, seed=a.seed, **({"popsize": a.pop} if a.pop else {}))
    t0 = time.time()
    used, gen = 0, 0
    hold_caps = [load_capture(nm) for nm in hold]

    def hold_eval(x):
        tab = _fbdecode(np.asarray(x), base, pr, nk, n)
        prog = IKProgram(tab, meta["h"], meta["td"], meta["g"], meta["kdc"], meta["kp"], meta["kd"], meta["gap0"], meta["end"])
        return [board_score2(simulate_prog(body, cap, prog), cap, meta["lmax"], meta["delta"], meta["vzmin"], meta["vzw"])
                for cap in hold_caps]

    with mp.Pool(a.workers, initializer=_fbworker, initargs=(train,)) as pool:
        f0, m0 = pool.apply(_fbeval, ((x0, base, pr, meta),))
        # the unmodified program on the same starts, for reference
        xz = np.concatenate([np.full(3 * n, 0.5), [0.3, 0.0]])
        fz, mz = pool.apply(_fbeval, ((xz, base, pr, meta),))
        print("base program  ", summarise(mz["scores"], "train"), f"tail-score {fz:.3f}", flush=True)
        if hold_caps:
            print("base program  ", summarise(hold_eval(xz), "held out"), flush=True)
        best = (f0, x0.copy(), m0)
        print("start         ", summarise(m0["scores"], "train"), f"tail-score {f0:.3f}", flush=True)
        while used < a.evals:
            X = np.clip(np.atleast_2d(opt.ask()), 0.0, 1.0)
            res = pool.map(_fbeval, [(x, base, pr, meta) for x in X], chunksize=1)
            f = np.array([r[0] for r in res])
            opt.tell(X, f, [r[1] for r in res])
            used += len(X) * len(caps)
            gen += 1
            i = int(np.argmax(f))
            if f[i] > best[0]:
                best = (float(f[i]), X[i].copy(), res[i][1])
            if gen % a.report == 0:
                print(f"gen {gen} sims {used} ({time.time() - t0:.0f}s) best {best[0]:.3f} " +
                      summarise(best[2]["scores"], "train"), flush=True)
                tabb = _fbdecode(best[1], base, pr, nk, n)
                write_fb(a.out, a.ik, tabb, pr, caps[0]["plant"], mus)
                if hold_caps and gen % (a.report * 3) == 0:
                    print("             ", summarise(hold_eval(best[1]), "held out"), flush=True)
    tabb = _fbdecode(best[1], base, pr, nk, n)
    write_fb(a.out, a.ik, tabb, pr, caps[0]["plant"], mus)
    print("done", summarise(best[2]["scores"], "train"))
    if hold_caps:
        print(summarise(hold_eval(best[1]), "held out"))


# ---------------------------------------------------------------------------
# the landing program (`landing`): from the take-off program's handover to
# the end of the landing, latched on the first sand contact
#
# LongJumpRunSkill's `il` program: knots every il_h s of LANDING program time
# sigma (0 at the handover tick, when the take-off program's clock passes
# ik_end); the clock waits at il_ld until the first sand contact (any body part
# on the pit), and is set to il_ld when the sand comes early. Activations as
# the take-off program (quintic c, v, a knots, linear drive knots, one reflex
# gain j_il_g with the velocity-damping compensation), no gap feedback.
# Scored by the official mark: the nearest break in the sand made by any part
# of the body from the landing to the end (TR 29.9) measured from the foul line;
# a runway contact after the take-off, a torso past 120 deg (TR 30.1.3) or a
# foul at the take-off fail.

def sand_touch(body):
    d = body.d
    for i in range(d.ncon):
        c = d.contact[i]
        for a, g in ((c.geom1, c.geom2), (c.geom2, c.geom1)):
            if a in body.body_geoms and g in body.ground and g != body.runway:
                return True
    return False


def torso_rate(body):
    v = np.zeros(6)
    mujoco.mj_objectVelocity(body.m, body.d, mujoco.mjtObj.mjOBJ_BODY, body.torso, v, 0)
    return float(v[1])


CKC_L = 20.0   # the landing's time-to-strike gains: (x - 0.5) x 20 drive per second of deficit


class LandingProgram:
    def __init__(self, tab, h, ld, g, kdc, kp, kd, lead=0.0, delay=0):
        self.tab, self.h, self.ld, self.g, self.kdc, self.kp, self.kd = tab, h, ld, g, kdc, kp, kd
        self.nk = tab["c"].shape[0]
        # timing jitter (training): the clock `lead` s ahead (an earlier
        # hand-over), and the sand seen `delay` ticks late (the controller's
        # contact sensor lags the physics by up to a tick)
        self.lead, self.delay = lead, delay
        self.lz = tab.get("lz", 9.0) if isinstance(tab, dict) else 9.0   # the latch's COM height (m)
        # the ballistic-time clock (il_tg > 0, LongJumpRunSkill#il_apply): until
        # the sand the program time is tg - (the COM's ballistic time to fall to
        # zl), so the legs' tuck and reach are locked to the predicted landing
        # instead of to the hand-over (a low or short flight lands earlier)
        self.tg = tab.get("tg", 0.0) if isinstance(tab, dict) else 0.0
        self.zl = tab.get("zl", LAND_Z) if isinstance(tab, dict) else LAND_Z
        # the time-to-strike reflex (il_ctau, il_clt, il_kc_*; LongJumpRunSkill#il_clearance)
        self.ck = tab.get("ckc") if isinstance(tab, dict) else None
        self.ctau = tab.get("ctau", 0.2) if isinstance(tab, dict) else 0.2
        self.clt = tab.get("clt", 0.10) if isinstance(tab, dict) else 0.10

    def start(self, body):
        m = body.m
        lr = m.actuator_lengthrange[body.act_ids]
        self.hi, self.span = lr[:, 1], lr[:, 1] - lr[:, 0]
        self.shift, self.landed = self.lead, False
        self.seen = 0
        self.s_prev = -1e9
        self.sites = [m.site(n).id for n in ("l_toe", "l_heel", "r_toe", "r_heel")]
        self.zf_prev = None

    def time_to_land(self, body):
        d = body.d
        mujoco.mj_subtreeVel(body.m, d)
        z = float(d.subtree_com[body.pelvis][2]) - self.zl
        vz = float(d.subtree_linvel[body.pelvis][2])
        if z <= 0.0:
            return 0.0
        return (vz + math.sqrt(vz * vz + 2.0 * G * z)) / G

    def __call__(self, body, t, k):
        d = body.d
        s = t + self.shift
        if not self.landed:
            if self.tg > 0.0:
                # never runs backward (a foot grazing the sand makes the ballistic estimate meaningless)
                s = max(self.s_prev, self.tg - self.time_to_land(body) + self.lead)
                self.s_prev = s
            if sand_touch(body) and float(d.subtree_com[body.pelvis][2]) < self.lz:
                self.seen += 1
            if self.seen > self.delay:   # (the skill reads the task's pit contact flag, set by the same contacts)
                self.landed = True
                if self.tg > 0.0:
                    self.shift = self.ld - t   # the real-time clock continues from il_ld
                else:
                    self.shift += self.ld - s
                s = self.ld
            elif s > self.ld:
                if self.tg <= 0.0:
                    self.shift -= s - self.ld
                s = self.ld
        ids = body.act_ids
        c = (self.hi - d.actuator_length[ids]) / self.span
        cd = -d.actuator_velocity[ids] / self.span
        cs, vs, e, _ = quintic_eval(self.tab, s, self.h, self.nk)
        g = self.g if k > 0 else 0.0
        out = e + self.kdc * g * self.kd * vs + g * (self.kp * (cs - c) - self.kd * cd)
        if "pr" in self.tab:
            # rotation feedback (LongJumpRunSkill#il_apply)
            j = min(max(int(s / self.h), 0), self.nk - 2)
            u = min(max((s - self.h * j) / self.h, 0.0), 1.0)
            pr = self.tab["pr"]
            err = body.torso_pitch() - (pr[j] + (pr[j + 1] - pr[j]) * u)
            out = out + self.tab["fkp"] * err + self.tab["fkd"] * torso_rate(body)
        if self.ck is not None:
            # time-to-strike reflex: before the designed landing (the program is more than clt s from il_ld) a foot
            # closing on the sand with less than ctau s to go (its lowest point's height over its fall speed, from
            # the last tick's height) adds gain x (ctau - time) to the drive: the feet come up in a short flight
            z = min(float(d.site_xpos[i][2]) for i in self.sites)
            zp = z if self.zf_prev is None else self.zf_prev
            self.zf_prev = z
            if not self.landed and s < self.ld - self.clt:
                vzf = (z - zp) / body.dt_ctl
                if vzf < -0.3:
                    tau = max(z, 0.0) / (-vzf)
                    if tau < self.ctau:
                        out = out + self.ck * (self.ctau - tau)
        return out


def run_landing(body, ho, prog, seconds):
    """From a handover state: returns the official mark and the failures."""
    m, d = body.m, body.d
    mujoco.mj_setState(m, d, ho["state"], SPEC)
    mujoco.mj_forward(m, d)
    prog.start(body)
    t0 = d.time
    ids = body.act_ids
    k = 0
    near = None
    landed = False
    max_pitch = 0.0
    while d.time - t0 < seconds:
        t = d.time - t0
        d.ctrl[ids] = np.clip(prog(body, t, k), 0.0, 1.0)
        for _ in range(body.substeps):
            mujoco.mj_step(m, d)
        k += 1
        for i in range(d.ncon):
            c = d.contact[i]
            for a, g in ((c.geom1, c.geom2), (c.geom2, c.geom1)):
                if a in body.body_geoms and g in body.ground:
                    if g == body.runway:
                        return {"valid": False, "why": "runway", "t": d.time - t0}
                    landed = True
                    x = float(c.pos[0])
                    near = x if near is None else min(near, x)
        if landed:
            max_pitch = max(max_pitch, abs(body.torso_pitch()))
    if near is None:
        return {"valid": False, "why": "no landing", "t": d.time - t0}
    return {"valid": True, "mark": near - ho["board_x"], "max_pitch": max_pitch,
            "somersault": max_pitch > 2.1, "pelvis_z": float(d.body("pelvis").xpos[2])}


def landing_score(r, ho):
    if not r["valid"]:
        return -2.0 + 0.2 * r.get("t", 0.0)
    if ho["foul"]:
        return -1.0
    s = r["mark"]
    if r["somersault"]:
        s = min(s, 0.0) - 1.0 - (r["max_pitch"] - 2.1)
    # a margin below the 120 deg failure line: a landing that pitches past
    # PITCH_MARGIN rad on a training start rolls over on an unseen one
    s -= 2.0 * max(0.0, r["max_pitch"] - PITCH_MARGIN)
    return s


def handover(a):
    """Run the robust take-off program on each start to its handover (the
    program clock passing ik_end) and save the states for the landing."""
    from search import read_params
    names = [n for n in a.captures.split(",") if n]
    caps = [load_capture(n) for n in names]
    body = Body(caps[0]["task"], caps[0]["board_x"], json.loads(caps[0]["env"]))
    kp, kd = reflex_gains(body.muscles, json.loads(caps[0]["params"]))
    pf = read_params(a.program)
    nk = int(round(pf["ik_n"]))
    size = mujoco.mj_stateSize(body.m, SPEC)
    out = {}
    jobs = []
    for nm, cap in zip(names, caps):
        jobs.append((nm, cap, 0))
        for v in range(1, a.variants + 1):
            jobs.append((f"{nm}_v{v}", cap, v))
    names = [j[0] for j in jobs]
    for nm, cap, v in jobs:
        _, tab = read_ik(a.program, body.muscles, cap["plant"], nk=nk)
        g = pf["j_ik_g"]
        if v:
            # execution noise: every muscle's drive knots scaled by N(1, 0.03),
            # the feedback gain by N(1, 0.1) (a different take-off each time)
            rng = np.random.default_rng(1000 * v + (abs(hash(nm)) % 997))
            tab = dict(tab)
            tab["e"] = tab["e"] * rng.normal(1.0, 0.03, tab["e"].shape[1])[None, :]
            g = g * float(rng.normal(1.0, 0.1))
        prog = IKProgram(tab, pf["ik_h"], pf["ik_td"], g, pf.get("j_ik_kdc", 1.0), kp, kd, pf["ik_gap0"],
                         pf["ik_end"])
        r = simulate_prog(body, cap, prog)
        st = np.zeros(size)
        mujoco.mj_getState(body.m, body.d, st, SPEC)
        # the rollout runs to the task's end: the landing is scored over all of it
        t_left = float(body.task.seconds) - float(body.d.time)
        foul = (not r["valid"]) or r["toe_max"] > cap["board_x"]
        out[nm] = {"state": st, "board_x": cap["board_x"], "foul": bool(foul), "valid": r["valid"], "t_left": t_left,
                   "D_board": (r["D"] - (cap["board_x"] - r["toe_max"])) if r["valid"] else None,
                   "vx": r.get("vx"), "vz": r.get("vz"), "contact_s": r.get("contact_s"), "L": r.get("L"),
                   "leg_angle_deg": r.get("td", {}).get("leg_angle_deg"), "toe_max": r.get("toe_max"),
                   "torso_pitch": r.get("torso_pitch"), "why": r.get("why")}
        print(nm, {k: (round(v, 3) if isinstance(v, float) else v) for k, v in out[nm].items() if k != "state"})
    np.savez(os.path.join(OUT, f"{a.name}_handover.npz"), names=json.dumps(names),
             **{f"state_{i}": out[n]["state"] for i, n in enumerate(names)},
             meta=json.dumps({n: {k: v for k, v in out[n].items() if k != "state"} for n in names}))
    print("wrote", os.path.join(OUT, f"{a.name}_handover.npz"))


def load_handover(name):
    z = np.load(os.path.join(OUT, f"{name}_handover.npz"))
    names = json.loads(str(z["names"]))
    meta = json.loads(str(z["meta"]))
    return [dict(meta[n], name=n, state=z[f"state_{i}"]) for i, n in enumerate(names)]


def record_landing(a):
    """The chunk landing's own excitations and sensed contraction after the
    handover, from a full controller rollout (the landing search's x0)."""
    from bridge import Sim
    from search import read_params
    task = load_task(a.task)
    task.seed = a.seed
    params = {}
    for p in a.params:
        params.update(read_params(p))
    sim = Sim(task, params=params, controller=a.controller)
    m, d = sim.m, sim.d
    task.reset(m, d)
    mujoco.mj_forward(m, d)
    sim.start_controller()
    ids = sim.act_ids
    lr = m.actuator_lengthrange[ids]
    rows, labels, t_ho, t_land = [], [], None, None
    try:
        while d.time < task.seconds:
            L = d.actuator_length[ids]
            c = (lr[:, 1] - L) / (lr[:, 1] - lr[:, 0])
            t = d.time
            sim.tick()
            if t_ho is None and labels and labels[-1].endswith("_ik") and not sim.label.endswith("_ik"):
                t_ho = t
            labels.append(sim.label)
            if t_ho is not None:
                rows.append((t - t_ho, d.ctrl[ids].copy(), c.copy()))
                if t_land is None and task.state == "landed":
                    t_land = t - t_ho
            for _ in range(max(1, round(task.control_dt / m.opt.timestep))):
                task.before_step(m, d)
                mujoco.mj_step(m, d)
    finally:
        sim.stop_controller()
    mt = task.metrics(m, d, sim.log)
    T = np.array([r[0] for r in rows])
    E = np.array([r[1] for r in rows])
    C = np.array([r[2] for r in rows])
    np.savez(os.path.join(OUT, f"{a.name}_landrec.npz"), T=T, E=E, C=C, t_land=t_land if t_land is not None else -1.0,
             muscles=json.dumps([mu.name for mu in sim.muscles]))
    print("recorded", len(T), "ticks after the handover; sand at", t_land, {k: mt.get(k) for k in
          ("official_m", "effective_m", "ballistic_m", "nearest_mark_by", "fell_back")})


def landing_base(rec, names, plant, h, nk, ld):
    """Knots on the landing grid from a recorded landing, re-timed so the
    recorded sand contact falls on il_ld."""
    T, E, C = rec["T"], rec["E"], rec["C"]
    shift = float(rec["t_land"]) - ld   # recorded time = grid time + shift after the latch
    dt = T[1] - T[0]
    V = np.gradient(C, dt, axis=0)
    tab = {q: np.zeros((nk, len(names))) for q in ("c", "v", "a", "e", "e1")}
    for k in range(nk):
        t = k * h
        tr = t if t < ld else t + shift   # before the latch the clock runs from the handover
        i = int(np.clip(np.argmin(np.abs(T - tr)), 0, len(T) - 1))
        lo, hi = max(0, i - 3), min(len(T), i + 4)
        tab["e"][k] = E[lo:hi].mean(axis=0)
        tab["c"][k] = C[i]
        tab["v"][k] = V[lo:hi].mean(axis=0)
    return tab


_L = {}


def keep_handovers(hos, ignore_foul):
    """The hand-overs a landing search trains on: a take-off that is invalid
    (a scuff, no take-off) has no flight to land; a foul is the take-off's
    business, its flight is a legal flight for the landing."""
    out = []
    for h in hos:
        if not h["valid"]:
            continue
        if ignore_foul:
            h = dict(h, foul=False)
        out.append(h)
    return out


def _lworker(ho_name, cap_name, ignore_foul=False):
    _L["hos"] = keep_handovers([h for nm in ho_name.split(",") for h in load_handover(nm)], ignore_foul)
    c0 = load_capture(cap_name)
    _L["body"] = Body(c0["task"], c0["board_x"], json.loads(c0["env"]))


def _ldecode(x, base, nk, n):
    k = nk * n
    E = np.clip(x[:k].reshape(nk, n), 0.0, 1.0)
    dC = (x[k:2 * k].reshape(nk, n) - 0.5) * 0.3
    g = float(np.clip(x[2 * k], 0.0, 1.0)) * 1.5
    tab = {"c": base["c"] + dC, "v": base["v"], "a": base["a"], "e": E, "e1": np.zeros_like(E), "lz": base.get("lz", 9.0),
           "tg": base.get("tg", 0.0), "zl": base.get("zl", LAND_Z)}
    cl = n + 1 if base.get("cl") else 0   # the time-to-strike reflex's dims come last: n gains and the time horizon
    if len(x) - cl > 2 * k + 1:
        # rotation feedback: pitch reference knots (rad), per-muscle gains
        o = 2 * k + 1
        tab["pr"] = (x[o:o + nk] - 0.5) * 4.0
        tab["fkp"] = (x[o + nk:o + nk + n] - 0.5) * 4.0
        tab["fkd"] = (x[o + nk + n:o + nk + 2 * n] - 0.5) * 1.0
    if cl:
        tab["ckc"] = (x[-n - 1:-1] - 0.5) * CKC_L
        tab["ctau"] = 0.05 + 0.25 * float(x[-1])
        tab["clt"] = base.get("clt", 0.10)
    return tab, g


def _leval(job):
    x, base, meta = job
    body, hos = _L["body"], _L["hos"]
    tab, g = _ldecode(np.asarray(x), base, meta["nk"], len(body.muscles))
    sc, marks = [], []
    for i, ho in enumerate(hos):
        lead, delay = 0.0, 0
        if meta.get("jitter"):
            lead, delay = 0.004 * (i % 3), (i // 3) % 2
        prog = LandingProgram(tab, meta["h"], meta["ld"], g, 1.0, meta["kp"], meta["kd"], lead, delay)
        # to the rollout's end (the metrics cover the whole motion); --seconds for old hand-overs
        r = run_landing(body, ho, prog, ho.get("t_left", meta["seconds"]))
        sc.append(landing_score(r, ho))
        marks.append(r.get("mark"))
    sc = np.array(sc)
    mean = float(sc.mean())
    if meta.get("tail_q", 0.0) > 0.0:
        # the mean of the worst tail_q of the starts instead of the single worst
        q = max(1, int(round(meta["tail_q"] * len(sc))))
        worst = float(np.sort(sc)[:q].mean())
    else:
        worst = float(sc.min())
    return mean - meta["risk"] * (mean - worst), {"mean": mean, "min": float(sc.min()), "scores": sc.tolist()}


def landing(a):
    from search import make_optimizer, read_params
    hos = keep_handovers([h for nm in a.handover.split(",") for h in load_handover(nm)], a.ignore_foul)
    c0 = load_capture(a.capture)
    body = Body(c0["task"], c0["board_x"], json.loads(c0["env"]))
    mus = body.muscles
    kp, kd = reflex_gains(mus, json.loads(c0["params"]))
    z = np.load(os.path.join(OUT, f"{a.rec}_landrec.npz"))
    rec = {k: z[k] for k in ("T", "E", "C", "t_land")}
    ld = float(rec["t_land"]) if a.ld is None else a.ld
    base = landing_base(rec, mus, c0["plant"], a.h, a.nk, ld)
    base["lz"] = a.lz
    base["cl"] = bool(a.clearance)
    base["clt"] = a.clt
    if a.tg:
        # the ballistic-time clock (il_tg): the time-to-land at the design's hand-over; the COM height it falls to is
        # the take-off program's j_land_z (the skill's time_to_land)
        base["tg"] = a.tg
        base["zl"] = float(json.loads(c0["params"]).get("j_land_z", LAND_Z))
    meta = {"nk": a.nk, "h": a.h, "ld": ld, "kp": kp, "kd": kd, "risk": a.risk, "seconds": a.seconds,
            "jitter": a.jitter, "tail_q": a.tail_q}
    n = len(mus)
    x0 = np.concatenate([np.clip(base["e"], 0, 1).ravel(), np.full(a.nk * n, 0.5), [a.g0 / 1.5]])
    if a.init:
        # an earlier landing program, resampled in time onto this grid (its
        # clock latch il_ld moved to this one's)
        pi = read_params(a.init)
        ni = int(round(pi["il_n"]))
        ti = read_il(a.init, mus, c0["plant"], ni)
        hi_, ldi = pi["il_h"], pi["il_ld"]

        def resample(A):
            out = np.zeros((a.nk, A.shape[1]))
            for k in range(a.nk):
                t = k * a.h
                t_old = t if t < ld else ldi + (t - ld)
                t_old = t_old * (ldi / ld) if t < ld else t_old
                j = min(int(t_old / hi_), ni - 2)
                u = min(max((t_old - hi_ * j) / hi_, 0.0), 1.0)
                out[k] = (1 - u) * A[j] + u * A[j + 1]
            return out
        x0 = np.concatenate([np.clip(resample(ti["e"]), 0, 1).ravel(),
                             np.clip((resample(ti["c"]) - base["c"]) / 0.3 + 0.5, 0, 1).ravel(),
                             [pi.get("j_il_g", a.g0) / 1.5]])
    if a.feedback:
        # the rotation feedback starts at zero (no effect); an init that has it keeps it
        fb = np.concatenate([np.full(a.nk, 0.5), np.full(n, 0.5), np.full(n, 0.5)])
        if a.init and "il_pr0" in read_params(a.init):
            pi = read_params(a.init)
            fb[:a.nk] = [pi.get(f"il_pr{k}", 0.0) / 4.0 + 0.5 for k in range(a.nk)]
            fb[a.nk:a.nk + n] = [pi.get(f"il_kp_{role_of(m_, c0['plant'])}", 0.0) / 4.0 + 0.5 for m_ in mus]
            fb[a.nk + n:] = [pi.get(f"il_kd_{role_of(m_, c0['plant'])}", 0.0) / 1.0 + 0.5 for m_ in mus]
        x0 = np.concatenate([x0, fb])
    if a.clearance:
        # the time-to-strike reflex starts at zero gain; an init that has it keeps it
        kc0 = np.full(n, 0.5)
        ct0 = 0.6
        if a.init and "il_ctau" in read_params(a.init):
            pi = read_params(a.init)
            kc0 = np.array([pi.get(f"il_kc_{role_of(m_, c0['plant'])}", 0.0) / CKC_L + 0.5 for m_ in mus])
            ct0 = (pi["il_ctau"] - 0.05) / 0.25
        x0 = np.concatenate([x0, np.clip(kc0, 0.0, 1.0), [float(np.clip(ct0, 0.0, 1.0))]])
    opt = make_optimizer(a.method, x0, sigma0=a.sigma, seed=a.seed, **({"popsize": a.pop} if a.pop else {}))
    t0 = time.time()
    used, gen = 0, 0
    with mp.Pool(a.workers, initializer=_lworker, initargs=(a.handover, a.capture, a.ignore_foul)) as pool:  # (_lworker splits the names)
        f0, m0 = pool.apply(_leval, ((x0, base, meta),))
        best = (f0, x0.copy(), m0)
        print(f"landing: {len(hos)} starts, sand at {ld:.3f} s after the handover, {len(x0)} dims; x0 {f0:.3f} "
              f"mean {m0['mean']:.3f} min {m0['min']:.3f} {np.round(m0['scores'], 2).tolist()}", flush=True)
        while used < a.evals:
            X = np.clip(np.atleast_2d(opt.ask()), 0.0, 1.0)
            res = pool.map(_leval, [(x, base, meta) for x in X], chunksize=1)
            f = np.array([r[0] for r in res])
            opt.tell(X, f, [r[1] for r in res])
            used += len(X) * len(hos)
            gen += 1
            i = int(np.argmax(f))
            if f[i] > best[0]:
                best = (float(f[i]), X[i].copy(), res[i][1])
            if gen % 10 == 0:
                print(f"gen {gen} sims {used} best {best[0]:.3f} mean {best[2]['mean']:.3f} min {best[2]['min']:.3f} "
                      f"({time.time() - t0:.0f}s)", flush=True)
                write_landing(a.out, best, base, meta, n, mus, c0["plant"])
    write_landing(a.out, best, base, meta, n, mus, c0["plant"])
    print("best", best[0], np.round(best[2]["scores"], 2).tolist())


def read_il(path, names, plant, nk):
    from search import read_params
    p = read_params(path)
    tab = {q: np.zeros((nk, len(names))) for q in ("c", "v", "a", "e", "e1")}
    for k in range(nk):
        for i, nm in enumerate(names):
            role = role_of(nm, plant)
            for q in ("c", "v", "a", "e"):
                tab[q][k, i] = p.get(f"il_{q}{k}_{role}", 0.0)
    tab["lz"] = p.get("il_lz", 9.0)
    tab["tg"] = p.get("il_tg", 0.0)
    tab["zl"] = p.get("il_zl", LAND_Z)
    if "il_ctau" in p:
        tab["ctau"], tab["clt"] = p["il_ctau"], p.get("il_clt", 0.10)
        tab["ckc"] = np.array([p.get(f"il_kc_{role_of(nm, plant)}", 0.0) for nm in names])
    if "il_pr0" in p:
        tab["pr"] = np.array([p.get(f"il_pr{k}", 0.0) for k in range(nk)])
        tab["fkp"] = np.array([p.get(f"il_kp_{role_of(nm, plant)}", 0.0) for nm in names])
        tab["fkd"] = np.array([p.get(f"il_kd_{role_of(nm, plant)}", 0.0) for nm in names])
    return tab


def write_landing(path, best, base, meta, n, mus, plant):
    tab, g = _ldecode(np.asarray(best[1]), base, meta["nk"], n)
    lines = [f"# landing program: {len(best[2]['scores'])} starts, score {best[0]:.3f} (mean {best[2]['mean']:.3f}, "
             f"min {best[2]['min']:.3f}); official marks {np.round(best[2]['scores'], 2).tolist()}",
             "j_il 1", f"il_h {meta['h']!r}", f"il_n {meta['nk']}", f"il_ld {meta['ld']!r}", f"j_il_g {g!r}",
             f"il_lz {float(tab.get('lz', 9.0))!r}",
             "j_il_kdc 1.0"]
    if tab.get("tg", 0.0) > 0.0:
        lines += [f"il_tg {float(tab['tg'])!r}", f"il_zl {float(tab['zl'])!r}"]
    for k in range(meta["nk"]):
        for i, nm in enumerate(mus):
            role = role_of(nm, plant)
            for q in ("c", "v", "a", "e"):
                lines.append(f"il_{q}{k}_{role} {float(tab[q][k, i])!r}")
    if "ckc" in tab:
        lines += [f"il_ctau {float(tab['ctau'])!r}", f"il_clt {float(tab['clt'])!r}"]
        lines += [f"il_kc_{role_of(nm, plant)} {float(tab['ckc'][i])!r}" for i, nm in enumerate(mus)]
    if "pr" in tab:
        lines += [f"il_pr{k} {float(tab['pr'][k])!r}" for k in range(meta["nk"])]
        for i, nm in enumerate(mus):
            role = role_of(nm, plant)
            lines.append(f"il_kp_{role} {float(tab['fkp'][i])!r}")
            lines.append(f"il_kd_{role} {float(tab['fkd'][i])!r}")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def report(a):
    rows = []
    for name in a.names.split(","):
        for tag in a.tags.split(","):
            p = os.path.join(OUT, f"{name}_{tag}.json")
            if not os.path.exists(p):
                continue
            j = json.load(open(p))
            for lab, r in (("champion", j["baseline_replay"]), (f"ideal {tag}", j["ideal"])):
                if not r.get("valid"):
                    continue
                if lab == "champion" and any(x[0] == name and x[1] == "champion" for x in rows):
                    continue
                rows.append((name, lab, r["D"], r["vx"], r["vz"], r["angle_deg"], r["contact_s"],
                             r["td"]["leg_angle_deg"], r["td"]["foot_ahead_m"], r["L"], r["peak_grf_bw"]))
    print("| body | take-off | ballistic D (m) | vx | vz | angle | contact (s) | plant leg angle | foot ahead of COM | L | peak GRF (BW) |")
    print("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for r in rows:
        print("| %s | %s | %.2f | %.2f | %.2f | %.1f | %.3f | %.0f deg | %.2f m | %.1f | %.1f |" % r)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("capture")
    c.add_argument("task")
    c.add_argument("--params", nargs="+", required=True)
    c.add_argument("--controller", required=True)
    c.add_argument("--seed", type=int, default=None)
    c.add_argument("--seeds", help="several seeds (None = the nominal start): captures <name>_s<seed>")
    c.add_argument("--set", help="extra params k=v,... (e.g. j_board_shift=1.15)")
    c.add_argument("--name", dest="base", required=True)
    c.add_argument("--from", dest="start", default="flight", choices=["flight", "pen"],
                   help="capture at the plant flight's start (default) or at the penultimate touchdown")
    r = sub.add_parser("replay")
    r.add_argument("name")
    o = sub.add_parser("optimise")
    o.add_argument("name")
    o.add_argument("--evals", type=int, default=20000)
    o.add_argument("--workers", type=int, default=4)
    o.add_argument("--method", default="sep_cma")
    o.add_argument("--sigma", type=float, default=0.12)
    o.add_argument("--pop", type=int, default=0)
    o.add_argument("--seed", type=int, default=1)
    o.add_argument("--lmax", default="auto")
    o.add_argument("--tag", default="ideal")
    o.add_argument("--init", help="an earlier optimum (<name>_<tag>.json) to start from")
    dd = sub.add_parser("distil")
    dd.add_argument("name")
    dd.add_argument("--tag", default="ideal")
    dd.add_argument("--out")
    rb = sub.add_parser("robust")
    rb.add_argument("ik", help="the base program (a distilled ik params file)")
    rb.add_argument("--captures", required=True)
    rb.add_argument("--nk", type=int, default=12)
    rb.add_argument("--evals", type=int, default=200000, help="simulations (candidates x starts)")
    rb.add_argument("--workers", type=int, default=4)
    rb.add_argument("--method", default="sep_cma")
    rb.add_argument("--sigma", type=float, default=0.05)
    rb.add_argument("--pop", type=int, default=0)
    rb.add_argument("--seed", type=int, default=1)
    rb.add_argument("--lmax", default="2")
    rb.add_argument("--risk", type=float, default=0.5)
    rb.add_argument("--g0", type=float, default=0.3)
    rb.add_argument("--post", type=float, default=0.24, help="program time after the ideal touchdown at which the "
                    "skill hands over to the hang (the program runs into the early flight until then)")
    rb.add_argument("--init", help="a robust program to start from (its e / c / g knots and gain)")
    rb.add_argument("--out", required=True)
    ho = sub.add_parser("handover")
    ho.add_argument("program")
    ho.add_argument("--captures", required=True)
    ho.add_argument("--name", required=True)
    ho.add_argument("--variants", type=int, default=0, help="extra hand-overs per start with execution noise")
    rl = sub.add_parser("record")
    rl.add_argument("task")
    rl.add_argument("--params", nargs="+", required=True)
    rl.add_argument("--controller", required=True)
    rl.add_argument("--seed", type=int, default=None)
    rl.add_argument("--name", required=True)
    la = sub.add_parser("landing")
    la.add_argument("--handover", required=True)
    la.add_argument("--capture", required=True, help="a capture of the same scene (model, params)")
    la.add_argument("--rec", required=True, help="a recorded chunk landing (record): the x0")
    la.add_argument("--h", type=float, default=0.06)
    la.add_argument("--nk", type=int, default=22)
    la.add_argument("--ld", type=float, default=None)
    la.add_argument("--seconds", type=float, default=1.5)
    la.add_argument("--evals", type=int, default=200000)
    la.add_argument("--workers", type=int, default=4)
    la.add_argument("--method", default="sep_cma")
    la.add_argument("--sigma", type=float, default=0.06)
    la.add_argument("--pop", type=int, default=0)
    la.add_argument("--seed", type=int, default=1)
    la.add_argument("--risk", type=float, default=0.5)
    la.add_argument("--g0", type=float, default=0.3)
    la.add_argument("--init")
    la.add_argument("--lz", type=float, default=9.0, help="the landing latch needs the COM below this (m)")
    la.add_argument("--tg", type=float, default=0.0, help="the ballistic-time clock: the design's time-to-land at the "
                    "hand-over (s); 0 = the clock runs from the hand-over")
    la.add_argument("--clearance", action="store_true", help="add the time-to-strike reflex (per-muscle gains, time horizon)")
    la.add_argument("--clt", type=float, default=0.10, help="the reflex is off within this many s of the designed sand contact")
    la.add_argument("--ignore-foul", dest="ignore_foul", action="store_true",
                    help="score a hand-over whose take-off fouled as a legal flight (invalid take-offs are always skipped)")
    la.add_argument("--tail-q", dest="tail_q", type=float, default=0.0,
                    help="risk term on the mean of the worst fraction of the starts instead of the single worst")
    la.add_argument("--feedback", action="store_true", help="add the rotation feedback (pitch reference knots, per-muscle pitch / rate gains)")
    la.add_argument("--jitter", action="store_true", help="timing jitter per hand-over (clock lead 0/4/8 ms, sand latch 0/1 tick late)")
    la.add_argument("--out", required=True)
    fb = sub.add_parser("robustfb", help="learn feedback residuals around a fixed take-off program")
    fb.add_argument("ik", help="the take-off program (a params file with the ik tables)")
    fb.add_argument("--prefix", required=True, help="capture name prefix (p95mn -> p95mn_s*_capture.npz)")
    fb.add_argument("--holdout", type=int, default=4, help="every k-th capture is held out (0 = none)")
    fb.add_argument("--evals", type=int, default=100000, help="simulations (candidates x starts)")
    fb.add_argument("--workers", type=int, default=4)
    fb.add_argument("--method", default="sep_cma")
    fb.add_argument("--sigma", type=float, default=0.06)
    fb.add_argument("--pop", type=int, default=0)
    fb.add_argument("--seed", type=int, default=1)
    fb.add_argument("--lmax", default="2")
    fb.add_argument("--delta", type=float, default=0.0, help="the foul line's shift (m): the check mark moved back")
    fb.add_argument("--vzmin", type=float, default=2.55, help="take-off vz (m/s) below which the score is penalised")
    fb.add_argument("--vzw", type=float, default=3.0, help="... by this per m/s")
    fb.add_argument("--tail-q", dest="tail_q", type=float, default=0.1)
    fb.add_argument("--tail-w", dest="tail_w", type=float, default=0.5)
    fb.add_argument("--fmin-on", dest="fmin_on", action="store_true", help="start with the plant-latch force switch on")
    fb.add_argument("--report", type=int, default=5)
    fb.add_argument("--init")
    fb.add_argument("--out", required=True)
    gf = sub.add_parser("greedyfb", help="forward selection of feedback gains around a fixed take-off program")
    gf.add_argument("ik")
    gf.add_argument("--prefix", required=True)
    gf.add_argument("--holdout", type=int, default=4)
    gf.add_argument("--workers", type=int, default=4)
    gf.add_argument("--rounds", type=int, default=8)
    gf.add_argument("--eps", type=float, default=0.005)
    gf.add_argument("--channels", default="kp", help="comma list of kp,kd,kc")
    gf.add_argument("--only", default="", help="comma list of muscle name prefixes to try (e.g. 'l_ham,r_ham,spine'), '' = all")
    gf.add_argument("--kp-steps", dest="kp_steps", default="-8,8")
    gf.add_argument("--kd-steps", dest="kd_steps", default="-1,1")
    gf.add_argument("--kc-steps", dest="kc_steps", default="15,40")
    gf.add_argument("--fbclip", type=int, default=1)
    gf.add_argument("--clz", type=float, default=0.06)
    gf.add_argument("--clt", type=float, default=0.04)
    gf.add_argument("--fmin-on", dest="fmin_on", action="store_true")
    gf.add_argument("--lmax", default="2")
    gf.add_argument("--delta", type=float, default=0.05)
    gf.add_argument("--vzmin", type=float, default=2.55)
    gf.add_argument("--vzw", type=float, default=3.0)
    gf.add_argument("--tail-q", dest="tail_q", type=float, default=0.1)
    gf.add_argument("--tail-w", dest="tail_w", type=float, default=0.3)
    gf.add_argument("--init")
    gf.add_argument("--out", required=True)
    p = sub.add_parser("report")
    p.add_argument("names")
    p.add_argument("--tags", default="ideal,free")
    a = ap.parse_args()
    {"capture": capture, "replay": replay, "optimise": optimise, "distil": distil, "robust": robust,
     "handover": handover, "record": record_landing, "landing": landing, "report": report,
     "robustfb": robustfb, "greedyfb": greedyfb}[a.cmd](a)


if __name__ == "__main__":
    main()
