"""bat_ceiling: how fast could the batter swing under ideal (open-loop) control?

No skill: from the moment a practised swing's hips fire, the upper body's
muscles (pelvis yaw, spine, both shoulders, elbows and wrists: 16 joints) are
driven open loop by CMA-ES. Each joint gets a net excitation u(t) in [-1, 1]
(piecewise linear, knots every `--knot` s): u > 0 excites the joint's pos
muscle, u < 0 its neg muscle, so there is no co-contraction; MuJoCo's own
activation dynamics, force-length-velocity curves and the top hand's grip
constraint apply. The legs and the pelvis shift replay the practised swing's
excitations. The start state (every joint angle, velocity and muscle
activation, the stride already planted) is the practised swing's at the
moment its hips fire. The ball is moved out of the way.

Score: the sweet-spot speed (6 in from the tip) at its closest approach to the
practised swing's contact point P, with stiff penalties for missing P by more
than `--tol` m, for a sweet-spot velocity more than 25 deg off the practised
contact's (the ball must still go forward), a bat axis more than 20 deg off
the practised contact's, and a top-hand grip error above 3 cm. Contact time is
free (the real swing re-times its trigger), so this is an upper bound on the
bat speed this body can bring to that contact.

    .venv/bin/python playground/bat_ceiling.py --params params/bat_v5_load.txt \
        --controller bin/challengers/bat_v5-20260927 --seed 0 --gens 300 --workers 4 --target sweet --name v5_s0

`--ball` scores the real pitch instead: the ball keeps flying from the
captured state (with the task's drag) and the score is the sweet-spot speed
at the first bat-ball contact, plus `--fair_bonus` for a fair ball and minus
`--launch_w` per 30 deg of launch away from 20 deg; a miss scores -20 - 100 x
the closest bat-ball gap. With `--lead 0` and a capture from the v6
controller running a program (skills/bat_power.w `prog`, quiet: its reflex
gain and chunk bursts off), the result is that controller's next program
(playground/bat_program_export.py), i.e. one iteration of learning the
swing's feed-forward on the body in the loop.

Writes out/bat_ceiling/<name>.json (the best controls, per-joint peak speeds,
the timeline of segment speeds and joint angles) every 50 generations and
prints progress. BAT_BODY (default athlete) and ROBOLAB_PROFILE pass through
to the body.
"""

import argparse
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
OUT = os.path.join(ROOT, "out", "bat_ceiling")
UPPER = ["pelvis_yaw", "spine_flex", "spine_lat", "spine_rot",
         "l_shoulder_flex", "l_shoulder_abd", "l_shoulder_rot", "l_elbow", "l_wrist_flex", "l_wrist_dev",
         "r_shoulder_flex", "r_shoulder_abd", "r_shoulder_rot", "r_elbow", "r_wrist_flex", "r_wrist_dev"]


def load_params(path):
    prm = {}
    if path:
        for line in open(path):
            parts = line.split()
            if len(parts) >= 2 and not line.startswith("#"):
                prm[parts[0]] = float(parts[1])
    return prm


def _task(seed, pitch=None):
    os.environ.setdefault("BAT_BODY", "athlete")
    os.environ["BAT_SEEDED_PITCH"] = "0" if pitch else "1"
    sys.path.insert(0, HERE)
    sys.path.insert(0, os.path.join(HERE, "tasks"))
    import bat as battask
    task = battask.BatTask()
    if pitch:   # (release speed m/s, crossing x from the plate centre, height)
        task.seeded_pitch = False
        task.pitches = [tuple(pitch)]
    else:
        task.seed = seed
    return task


def capture(params, controller, seed, lead=0.02, target="sweet", pitch=None):
    """Run the practised swing once; return its state when the hips fire
    (minus `lead` s), its excitations from then on, and its contact."""
    from bridge import Sim
    task = _task(seed, pitch)
    sim = Sim(task, params=params, controller=controller)
    snaps = []
    orig = sim.log

    class Log(list):
        def append(inner, item):
            list.append(inner, item)
            d = sim.d
            snaps.append((d.time, d.qpos.copy(), d.qvel.copy(), d.act.copy(), d.eq_active.copy(),
                          d.site_xpos[task.site["bat_sweet"]].copy(), d.site_xpos[task.site["bat_tip"]].copy(),
                          d.site_xpos[task.site["bat_knob"]].copy()))
    sim.log = Log(orig)
    res = sim.run(7.8)
    p = res["pitches"][0]
    ts, tc = p["t_swing"], p.get("t_contact", p.get("t_closest"))
    t = np.array([s[0] for s in snaps])
    k0 = int(np.searchsorted(t, ts - lead))
    kc = int(np.searchsorted(t, tc)) - 1
    # the practised contact: sweet spot position, its velocity (finite difference), bat axis
    P = snaps[kc][5]
    if target == "ball":
        # the ball where the practised swing met it (its flight extrapolated
        # from the last tick before contact to the contact time)
        bq, bv = task.ball_q, task.ball_v
        P = snaps[kc][1][bq:bq + 3] + snaps[kc][2][bv:bv + 3] * (tc - t[kc])
    vP = (snaps[kc][5] - snaps[kc - 1][5]) / (t[kc] - t[kc - 1])
    axis = snaps[kc][6] - snaps[kc][7]
    acts = np.array([e[2] for e in sim.log])
    names = [mu.name for mu in sim.muscles]
    import bat as battask
    return {"drag_k": battask.DRAG_K / battask.BALL_M, "plate_front_y": battask.PLATE_FRONT_Y, "lead": lead,
            "pitch": [p.get("speed_mph"), p.get("target_x"), p.get("target_z")], "hit": p["hit"],
            "t0": float(t[k0]), "qpos": snaps[k0][1], "qvel": snaps[k0][2], "act": snaps[k0][3],
            "eq": snaps[k0][4], "P": P, "vP": vP, "axis": axis / np.linalg.norm(axis),
            "tc_rel": float(tc - t[k0]), "bat_speed": p.get("bat_speed"), "acts": acts[k0 + 1:],
            "names": names, "act_ids": list(sim.act_ids), "dt": float(np.median(np.diff(t))),
            "xml": sim.xml}


class Rig:
    ball = False

    def __init__(self, cap, window, knot):
        self.cap = cap
        self.m = mujoco.MjModel.from_xml_string(cap["xml"])
        self.d = mujoco.MjData(self.m)
        self.window = window
        self.kt = np.arange(0.0, window + 1e-9, knot)
        self.names = cap["names"]
        self.ids = cap["act_ids"]
        self.pos = [self.names.index(j + "_pos") for j in UPPER]
        self.neg = [self.names.index(j + "_neg") for j in UPPER]
        self.upper = set(self.pos) | set(self.neg)
        m = self.m
        self.sweet = m.site("bat_sweet").id
        self.tip = m.site("bat_tip").id
        self.knob = m.site("bat_knob").id
        self.lgrip = m.site("l_grip").id
        self.btop = m.site("bat_top").id
        self.bq = m.joint("ball").qposadr[0]
        self.bv = m.joint("ball").dofadr[0]
        self.substeps = max(1, round(cap["dt"] / m.opt.timestep))
        self.dofs = {j: m.jnt_dofadr[m.joint(j).id] for j in UPPER}
        self.qadr = {j: m.jnt_qposadr[m.joint(j).id] for j in UPPER}
        self.ball_body = m.body("ball").id
        self.ball_geom = m.geom("ball").id
        self.bat_geoms = {i for i in range(m.ngeom) if m.geom(i).name.startswith("bat_")}

    def start(self):
        m, d, cap = self.m, self.d, self.cap
        mujoco.mj_resetData(m, d)
        d.qpos[:] = cap["qpos"]
        d.qvel[:] = cap["qvel"]
        d.act[:] = cap["act"]
        d.eq_active[:] = cap["eq"]
        d.time = 0.0
        mujoco.mj_forward(m, d)

    def rollout_ball(self, x, record=False):
        """The real pitch (its flight from the capture, quadratic drag as the
        task applies it) against the program: sweet-spot speed at the first
        bat-ball contact, the batted ball's launch and spray 3 ms later."""
        m, d, cap = self.m, self.d, self.cap
        self.start()
        U = np.clip(np.asarray(x).reshape(len(UPPER), len(self.kt)), -1.0, 1.0)
        acts = cap["acts"]
        dt = cap["dt"]
        k_drag = cap["drag_k"] * self.m.body_mass[self.ball_body]
        n_ticks = int(round(self.window / dt))
        v6 = np.zeros(6)
        closest = (9.0, 0.0)
        hit = None
        rows = []
        prev_v = np.zeros(3)
        grip_worst = 0.0
        bq, bv = self.bq, self.bv
        for k in range(n_ticks):
            t = k * dt
            ctrl = np.array(acts[min(k, len(acts) - 1)])
            for j in range(len(UPPER)):
                u = float(np.interp(t, self.kt, U[j]))
                ctrl[self.pos[j]] = max(0.0, u)
                ctrl[self.neg[j]] = max(0.0, -u)
            d.ctrl[self.ids] = ctrl
            for _ in range(self.substeps):
                vel = d.qvel[bv:bv + 3]
                d.xfrc_applied[self.ball_body, :3] = -k_drag * np.linalg.norm(vel) * vel
                near = float(np.linalg.norm(d.qpos[bq:bq + 3] - d.site_xpos[self.sweet])) < 0.9
                if near and hit is None:
                    mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_SITE, self.sweet, v6, 0)
                    prev_v = v6[3:].copy()
                mujoco.mj_step(m, d)
                if near and hit is None:
                    for i in range(d.ncon):
                        c = d.contact[i]
                        if (c.geom1 == self.ball_geom and c.geom2 in self.bat_geoms) or \
                                (c.geom2 == self.ball_geom and c.geom1 in self.bat_geoms):
                            hit = {"t": d.time, "speed": float(np.linalg.norm(prev_v)), "t_exit": d.time + 0.003}
                            break
                    if hit is None:
                        kb = d.site_xpos[self.knob]
                        ab = d.site_xpos[self.tip] - kb
                        bp = d.qpos[bq:bq + 3]
                        tt = float(np.clip(np.dot(bp - kb, ab) / np.dot(ab, ab), 0.0, 1.0))
                        dist = float(np.linalg.norm(bp - (kb + tt * ab))) - 0.0369 - 0.03
                        if dist < closest[0]:
                            closest = (dist, d.time)
            g = float(np.linalg.norm(d.site_xpos[self.btop] - d.site_xpos[self.lgrip]))
            grip_worst = max(grip_worst, g)
            if record:
                mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_SITE, self.sweet, v6, 0)
                r = {"t": round(d.time, 4), "head": round(float(np.linalg.norm(v6[3:])), 2)}
                for j in UPPER:
                    r[j] = round(float(d.qvel[self.dofs[j]]), 2)
                    r["q_" + j] = round(float(d.qpos[self.qadr[j]]), 4)
                rows.append(r)
            if hit is not None and d.time >= hit["t_exit"] and "fair" not in hit:
                bvv = d.qvel[bv:bv + 3]
                horiz = math.hypot(bvv[0], bvv[1])
                hit["launch_deg"] = round(math.degrees(math.atan2(bvv[2], horiz)), 1)
                hit["spray_deg"] = round(math.degrees(math.atan2(-bvv[0], -bvv[1])), 1)
                hit["exit"] = round(float(np.linalg.norm(bvv)), 2)
                hit["fair"] = bool(bvv[1] < 0 and abs(hit["spray_deg"]) <= 45.0)
                if not record:
                    break
            if hit is None and d.qpos[bq + 1] > cap["plate_front_y"] + 0.6:
                if not record:
                    break
        if hit is not None and "fair" in hit:
            score = hit["speed"] + self.fair_bonus * (1.0 if hit["fair"] else 0.0) \
                - self.launch_w * abs(hit["launch_deg"] - 20.0) / 30.0 - 100.0 * max(0.0, grip_worst - 0.03)
            info = {"speed": round(hit["speed"], 2), "t": round(hit["t"], 4), "fair": hit["fair"],
                    "launch_deg": hit["launch_deg"], "spray_deg": hit["spray_deg"], "exit": hit["exit"],
                    "grip": round(grip_worst, 3)}
        else:
            score = -20.0 - 100.0 * max(0.0, closest[0])
            info = {"speed": 0.0, "miss_m": round(closest[0], 3), "t": round(closest[1], 4), "grip": round(grip_worst, 3)}
        if record:
            info["rows"] = rows
        return score, info

    def dim(self):
        return len(UPPER) * len(self.kt)

    def x0(self):
        """The practised swing's net excitations (pos - neg) at the knots."""
        acts = self.cap["acts"]
        dt = self.cap["dt"]
        x = np.zeros((len(UPPER), len(self.kt)))
        for k, tk in enumerate(self.kt):
            i = min(int(round(tk / dt)), len(acts) - 1)
            for j in range(len(UPPER)):
                x[j, k] = acts[i, self.pos[j]] - acts[i, self.neg[j]]
        return x.ravel()

    def rollout(self, x, record=False):
        if self.ball:
            return self.rollout_ball(x, record)
        m, d, cap = self.m, self.d, self.cap
        mujoco.mj_resetData(m, d)
        d.qpos[:] = cap["qpos"]
        d.qvel[:] = cap["qvel"]
        d.act[:] = cap["act"]
        d.eq_active[:] = cap["eq"]
        d.time = 0.0
        d.qpos[self.bq:self.bq + 3] = [0.0, 30.0, 60.0]   # the ball out of the way
        d.qvel[self.bv:self.bv + 6] = 0.0
        mujoco.mj_forward(m, d)
        U = np.clip(np.asarray(x).reshape(len(UPPER), len(self.kt)), -1.0, 1.0)
        acts = cap["acts"]
        dt = cap["dt"]
        n_ticks = int(round(self.window / dt))
        best = (9.0, 0.0, None)
        rows = []
        v6 = np.zeros(6)
        grip_worst = 0.0
        for k in range(n_ticks):
            t = k * dt
            ctrl = np.array(acts[min(k, len(acts) - 1)])
            u = np.array([np.interp(t, self.kt, U[j]) for j in range(len(UPPER))])
            for j in range(len(UPPER)):
                ctrl[self.pos[j]] = max(0.0, u[j])
                ctrl[self.neg[j]] = max(0.0, -u[j])
            d.ctrl[self.ids] = ctrl
            for _ in range(self.substeps):
                mujoco.mj_step(m, d)
            sp = d.site_xpos[self.sweet]
            dist = float(np.linalg.norm(sp - cap["P"]))
            mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_SITE, self.sweet, v6, 0)
            vel = v6[3:].copy()
            g = float(np.linalg.norm(d.site_xpos[self.btop] - d.site_xpos[self.lgrip]))
            grip_worst = max(grip_worst, g)
            if dist < best[0]:
                ax = d.site_xpos[self.tip] - d.site_xpos[self.knob]
                best = (dist, float(np.linalg.norm(vel)), (vel, ax / np.linalg.norm(ax), d.time, grip_worst))
            if record:
                r = {"t": round(d.time, 4), "head": round(float(np.linalg.norm(vel)), 2), "dist": round(dist, 3)}
                for j in UPPER:
                    r[j] = round(float(d.qvel[self.dofs[j]]), 2)
                    r["q_" + j] = round(float(d.qpos[self.qadr[j]]), 4)
                rows.append(r)
        dist, speed, (vel, ax, tbest, grip) = best
        ang_v = math.acos(np.clip(np.dot(vel, cap["vP"]) / max(np.linalg.norm(vel) * np.linalg.norm(cap["vP"]), 1e-9), -1, 1))
        ang_a = math.acos(np.clip(np.dot(ax, cap["axis"]), -1, 1))
        score = speed - 200.0 * max(0.0, dist - self.tol) - 20.0 * max(0.0, ang_v - math.radians(25)) \
            - 20.0 * max(0.0, ang_a - math.radians(20)) - 100.0 * max(0.0, grip - 0.03)
        info = {"speed": round(speed, 2), "dist": round(dist, 3), "t": round(tbest, 3),
                "ang_v_deg": round(math.degrees(ang_v), 1), "ang_axis_deg": round(math.degrees(ang_a), 1),
                "grip": round(grip, 3)}
        if record:
            info["rows"] = rows
        return score, info


_RIG = None


def make_rig(cap, a):
    rig = Rig(cap, a.window, a.knot)
    rig.tol = a.tol
    rig.ball = a.ball
    rig.fair_bonus = a.fair_bonus
    rig.launch_w = a.launch_w
    return rig


def _init(cap, a):
    global _RIG
    _RIG = make_rig(cap, a)


def _eval(x):
    return _RIG.rollout(x)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--params", required=True)
    ap.add_argument("--controller", required=True)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--window", type=float, default=0.34)
    ap.add_argument("--knot", type=float, default=0.04)
    ap.add_argument("--tol", type=float, default=0.03)
    ap.add_argument("--gens", type=int, default=300)
    ap.add_argument("--pop", type=int, default=0)
    ap.add_argument("--sigma", type=float, default=0.3)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--name", default="ceiling")
    ap.add_argument("--rng", type=int, default=1)
    ap.add_argument("--ball", action="store_true",
                    help="score on the real pitch: speed at the first bat-ball contact (+ fair bonus), misses by distance")
    ap.add_argument("--lead", type=float, default=0.02, help="capture this long before the hips fire")
    ap.add_argument("--fair_bonus", type=float, default=2.0)
    ap.add_argument("--launch_w", type=float, default=0.0)
    ap.add_argument("--target", default="ball", choices=["ball", "sweet"],
                    help="P: the ball where the practised swing met it (default), or its sweet spot then")
    ap.add_argument("--set", action="append", default=[], help="k=v param override for the captured swing")
    ap.add_argument("--pitch", help="v,x,z: this pitch (release speed m/s, crossing x from the plate centre, "
                    "height) instead of the seed's grid pitch")
    ap.add_argument("--init_json", help="warm start from out/bat_ceiling/<name>.json's controls")
    a = ap.parse_args()
    sys.path.insert(0, HERE)
    from practice import CMA
    prm = load_params(a.params)
    for kv in a.set:
        k, _, v = kv.partition("=")
        prm[k] = float(v)
    pitch = [float(v) for v in a.pitch.split(",")] if a.pitch else None
    cap = capture(prm, os.path.abspath(a.controller), a.seed, lead=a.lead, target=a.target, pitch=pitch)
    rig = make_rig(cap, a)
    x0 = rig.x0()
    if a.init_json:
        # warm start from another run's controls (same joints and knots)
        prev = json.load(open(a.init_json))
        x0 = np.array([prev["controls"][j] for j in UPPER], float).ravel()
        assert len(x0) == rig.dim(), "init_json: knots differ"
    s0, i0 = rig.rollout(x0)
    print(f"practised swing: bat speed {cap['bat_speed']} m/s, contact {cap['tc_rel'] * 1000:.0f} ms after the capture; "
          f"open-loop replay (no co-contraction) score {s0:.2f} {i0}", flush=True)
    es = CMA(x0, a.sigma, a.pop or None, seed=a.rng)
    best = (s0, x0.copy(), i0)
    t0 = time.time()
    os.makedirs(OUT, exist_ok=True)
    with mp.get_context("spawn").Pool(a.workers, initializer=_init, initargs=(cap, a)) as pool:
        for g in range(a.gens):
            xs = es.ask()
            res = pool.map(_eval, [np.clip(x, -1.0, 1.0) for x in xs])
            sc = [r[0] - 5.0 * float(np.sum(np.maximum(0, np.abs(x) - 1.0))) for r, x in zip(res, xs)]
            es.tell(xs, sc)
            k = int(np.argmax([r[0] for r in res]))
            if res[k][0] > best[0]:
                best = (res[k][0], np.clip(xs[k], -1, 1), res[k][1])
            if g % 10 == 0 or g == a.gens - 1:
                print(f"gen {g} best {best[0]:.2f} {best[2]} sigma {es.sigma:.3f} ({time.time() - t0:.0f}s)", flush=True)
            if g % 50 == 49:
                save(rig, best, a, cap)
    save(rig, best, a, cap)


def save(rig, best, a, cap):
    score, info = rig.rollout(best[1], record=True)
    U = best[1].reshape(len(UPPER), len(rig.kt))
    peaks = {j: max([abs(r[j]) for r in info["rows"] if r["t"] <= info["t"] + 1e-9] or [0.0]) for j in UPPER}
    doc = {"name": a.name, "body": os.environ.get("BAT_BODY"), "profile": os.environ.get("ROBOLAB_PROFILE"),
           "params": a.params, "controller": a.controller, "seed": a.seed, "practised_bat_speed": cap["bat_speed"],
           "target": "pitch" if a.ball else a.target, "P": [round(float(v), 4) for v in cap["P"]],
           "lead": cap["lead"], "pitch": cap["pitch"], "set": a.set,
           "pitch_def": [float(v) for v in a.pitch.split(",")] if a.pitch else None, "ball_state": [round(float(v), 5) for v in
                                             list(cap["qpos"][rig.bq:rig.bq + 3]) + list(cap["qvel"][rig.bv:rig.bv + 3])],
           "q_start": {j: round(float(cap["qpos"][rig.qadr[j]]), 5) for j in UPPER},
           "score": score, "result": {k: v for k, v in info.items() if k != "rows"},
           "knots_s": rig.kt.tolist(), "controls": {j: [round(float(v), 3) for v in U[i]] for i, j in enumerate(UPPER)},
           "joint_peak_radps_to_contact": {j: round(v, 2) for j, v in peaks.items()}, "timeline": info["rows"]}
    path = os.path.join(OUT, a.name + ".json")
    with open(path, "w") as f:
        json.dump(doc, f, indent=1)
    print("saved", round(score, 3), doc["result"], "->", path, flush=True)


if __name__ == "__main__":
    main()
