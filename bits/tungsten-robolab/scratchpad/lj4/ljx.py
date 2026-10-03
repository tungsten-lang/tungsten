"""ljx: an ideal-control search for the LABELLED BEYOND-HUMAN body's take-off with explicit plausibility terms (agent L3).

It drives playground/long_jump_limits.py's harness (Body, capture, excitation knots, simulate's physics) but with its own
objective and its own copy of the stance loop, which also records the plant foot's vertical ground force per tick:

  score = D (from the take-off foot), or with --board the distance from the line (a foot past line - margin is a graded foul)
          - 0.1 per tick the free foot touches the runway in the stance
          - 0.2 per unit of forward angular momentum above --lmax (kg m2/s), as the harness
          - 0.2 per unit of BACKWARD angular momentum below --lmin (new: a beyond-body take-off can rotate backward)
          - --grfw per body weight of the plant foot's 12 ms-averaged vertical force above --grfcap (new)
          - 2 per rad of torso pitch at take-off outside [-0.5, 0.8], as the harness
          - a fixed plant-touchdown time with --td / --tdw, as the harness

The output json has the harness's own format (long_jump_limits.save_result), so `distil`, `handover` and `landing` read it.

    ljx.py opt <capture> --tag T --evals N [--workers 6 --sigma 0.04 --pop 200 --seed 1 --init a.json --board --margin 0.03
                --lmax -1.5 --lmin -99 --grfcap 99 --grfw 0.2 --td 0 --tdw 20 --restarts K]
    ljx.py eval <capture> <ideal.json> [same objective flags]      (one evaluation, every number)
"""

import argparse
import json
import math
import multiprocessing as mp
import os
import sys
import time

os.environ.setdefault("MUJOCO_GL", "cgl")
HERE = "/Users/erik/tungsten/bits/tungsten-robolab/playground"
sys.path.insert(0, HERE)
import mujoco  # noqa: E402
import numpy as np  # noqa: E402

import long_jump_limits as L  # noqa: E402

G = L.G
_W = {}


def simulate2(body, cap, program, record=False, restore=True, until=None):
    """long_jump_limits.simulate (restore from the capture, run `program`, the stance loop) plus the plant foot's ground force per tick.
    `until(t)`: keep running the program into the flight until it is true (the skill hands over at the same program time), nothing may touch the runway."""
    m, d = body.m, body.d
    if restore:
        mujoco.mj_setState(m, d, cap["state"], L.SPEC)
        if L.DV:
            # what-if (ROBOLAB_LJ_DV, m/s): the captured approach state with the whole body moving DV faster, as the harness
            d.qvel[m.joint("root_x").dofadr[0]] += L.DV
        mujoco.mj_forward(m, d)
    t0 = d.time
    ids = body.act_ids
    td_t = None
    plant = None
    last_contact = None
    snap = None
    peak_f = 0.0
    other_foot = 0
    toe_max = -1e9
    knee_max = 0.0
    knee_load = -1.0   # the plant knee's largest flexion in the first 50 ms of the stance (the load phase), rad
    knee_pk = -1.0
    lifted = set()
    weight = float(sum(m.body_mass[1:])) * G
    f6 = np.zeros(6)
    fzs = []
    k = 0
    td = None
    while True:
        t = d.time - t0
        d.ctrl[ids] = np.clip(program(t, k), 0.0, 1.0)
        for _ in range(body.substeps):
            mujoco.mj_step(m, d)
        k += 1
        t = d.time - t0
        feet, other = body.contacts()
        if other:
            return {"valid": False, "why": "body contact", "t": t, "progress": 0.0}
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
            elif t > cap.get("horizon", L.HORIZON) - 0.13:
                return {"valid": False, "why": "no touchdown", "t": t, "progress": 0.0}
            continue
        if feet - {plant}:
            other_foot += 1
        feet = feet & {plant}
        if feet:
            last_contact = t
            fz = 0.0
            for i in range(d.ncon):
                c = d.contact[i]
                if (c.geom1 in body.feet or c.geom2 in body.feet) and (c.geom1 in body.ground or c.geom2 in body.ground):
                    mujoco.mj_contactForce(m, d, i, f6)
                    fz += abs(f6[0])
            fzs.append(fz / weight)
            if fz / weight > peak_f:
                knee_pk = body.knee(plant)   # the plant knee's flexion at the tick of the largest normal force
            peak_f = max(peak_f, fz / weight)
            mujoco.mj_subtreeVel(m, d)
            toe_max = max(toe_max, body.foot_front(plant))
            knee_max = max(knee_max, body.knee(plant))
            if t - td_t <= 0.05:
                knee_load = max(knee_load, body.knee(plant))
            snap = {"t": t, "com_x": float(d.subtree_com[body.pelvis][0]), "com_z": float(d.subtree_com[body.pelvis][2]),
                    "vx": float(d.subtree_linvel[body.pelvis][0]), "vz": float(d.subtree_linvel[body.pelvis][2]),
                    "L": float(d.subtree_angmom[body.pelvis][1]), "toe": body.foot_front(plant),
                    "torso_pitch": body.torso_pitch(), "knee": body.knee(plant)}
            if t - td_t > L.STANCE_MAX:
                mujoco.mj_subtreeVel(m, d)
                return {"valid": False, "why": "no take-off", "t": t,
                        "progress": max(0.0, float(d.subtree_linvel[body.pelvis][2]))}
        elif t - last_contact >= L.AIR_CONFIRM and last_contact - td_t >= L.MIN_STANCE:
            if until is None:
                break
            while not until(d.time - t0):
                d.ctrl[ids] = np.clip(program(d.time - t0, k), 0.0, 1.0)
                for _ in range(body.substeps):
                    mujoco.mj_step(m, d)
                k += 1
                if L.runway_touch(body):
                    return {"valid": False, "why": "runway after take-off", "t": d.time - t0, "progress": 1.0}
                if d.time - t0 > snap["t"] + 0.5:
                    break
            break
    s = snap
    vx, vz, h = s["vx"], s["vz"], s["com_z"] - L.LAND_Z
    t_air = (vz + math.sqrt(max(0.0, vz * vz + 2 * G * h))) / G if h > 0 else 0.0
    D = (s["com_x"] - s["toe"]) + vx * t_air
    f = np.array(fzs) if fzs else np.zeros(1)
    f12 = np.convolve(f, np.ones(3) / 3.0, mode="valid") if len(f) >= 3 else f
    return {"valid": True, "D": D, "vx": vx, "vz": vz, "angle_deg": math.degrees(math.atan2(vz, vx)),
            "speed": math.hypot(vx, vz), "contact_s": s["t"] - td_t, "td": td, "L": s["L"],
            "torso_pitch": s["torso_pitch"], "com_z": s["com_z"], "takeoff_dist": s["com_x"] - s["toe"],
            "t_air": t_air, "peak_grf_bw": peak_f, "grf12_bw": float(f12.max()), "grf_mean_bw": float(f.mean()),
            "other_foot": other_foot, "plant": plant, "knee_to": s["knee"], "t_to": s["t"], "toe_max": toe_max,
            "knee_max": knee_max, "knee_load": knee_load, "knee_pk": knee_pk}


def score2(r, cap, cfg):
    if not r["valid"]:
        return -5.0 + r.get("t", 0.0) + 0.5 * r.get("progress", 0.0)
    s = r["D"]
    if cfg["board"]:
        s = r["D"] - (cap["board_x"] - r["toe_max"])
        if r["toe_max"] > cap["board_x"] - cfg["margin"]:
            s = -1.0 - 4.0 * (r["toe_max"] - cap["board_x"] + cfg["margin"])
    s -= 0.1 * r["other_foot"]
    if r["L"] > cfg["lmax"]:
        s -= cfg.get("lw", 0.2) * (r["L"] - cfg["lmax"])   # L4: the weight is a parameter (default 0.2 = L3's)
    if r["L"] < cfg["lmin"]:
        s -= 0.2 * (cfg["lmin"] - r["L"])
    p = r["torso_pitch"]
    s -= 2.0 * (max(0.0, p - 0.8) + max(0.0, -0.5 - p))
    s -= cfg.get("pw", 0.0) * max(0.0, p - cfg.get("pthr", 0.65))   # L4: an extra penalty on a forward-pitched take-off (default 0 = L3's)
    if cfg["td"] > 0.0:
        s -= cfg["tdw"] * max(0.0, abs(r["td"]["t"] - cfg["td"]) - 0.004)
    if r["grf12_bw"] > cfg["grfcap"]:
        s -= cfg["grfw"] * (r["grf12_bw"] - cfg["grfcap"])
    if cfg.get("kneeload", 0.0) > 0.0 and r["knee_pk"] < cfg["kneeload"]:
        # a yielding knee under LOAD: the plant knee must be flexed at least this much (rad) at the instant of the largest plant-foot force
        s -= cfg.get("kneew", 10.0) * (cfg["kneeload"] - r["knee_pk"])
    if cfg.get("kneemin", 0.0) > 0.0 and r["knee_max"] < cfg["kneemin"]:
        # a yielding knee: the plant knee must flex at least this much (rad) in the stance (no pure joint-limit strut)
        s -= cfg.get("kneew", 10.0) * (cfg["kneemin"] - r["knee_max"])
    return s


def _worker(cap_name, cfg):
    cap = L.load_capture(cap_name)
    body = L.Body(cap["task"], cap["board_x"], json.loads(cap["env"]))
    _W["cap"], _W["body"], _W["cfg"] = cap, body, cfg


def _eval(x):
    body, cap, cfg = _W["body"], _W["cap"], _W["cfg"]
    X = np.asarray(x).reshape(len(body.muscles), -1)
    r = simulate2(body, cap, lambda t, k: L.excitation(X, t))
    return score2(r, cap, cfg), r


def cfg_of(a):
    return {"board": a.board, "margin": a.margin, "lmax": float(a.lmax), "lmin": float(a.lmin), "grfcap": float(a.grfcap),
            "grfw": float(a.grfw), "td": float(a.td), "tdw": float(a.tdw), "kneemin": float(a.kneemin), "kneeload": float(a.kneeload), "kneew": float(a.kneew)}


def init_knots(cap, body, path):
    """An earlier optimum's knots, by role (its plant side may be the other foot), on this capture's grid."""
    nk = len(L.knot_times(cap["horizon"]))
    ji = json.load(open(path))
    iplant = ji.get("plant") or L.load_capture(ji["name"])["plant"]
    by_role = {L.role_of(n, iplant): v for n, v in ji["knots"].items()}
    Xi = np.array([by_role[L.role_of(n, cap["plant"])] for n in body.muscles])
    X = np.zeros((len(body.muscles), nk))
    n = min(nk, Xi.shape[1])
    X[:, :n] = Xi[:, :n]
    if Xi.shape[1] < nk:
        X[:, n:] = Xi[:, -1:]
    return X


def fmt(r):
    if not r["valid"]:
        return "invalid: %s t %.3f" % (r.get("why"), r.get("t", 0))
    return ("D %.3f vx %.2f vz %.2f (%.1f deg) contact %.3f L %.1f pitch %.2f peakGRF %.1f grf12 %.1f mean %.1f knee_max %.2f knee_at_peak_force %.2f toe_max %.3f com_z %.3f other_foot %d" % (
        r["D"], r["vx"], r["vz"], r["angle_deg"], r["contact_s"], r["L"], r["torso_pitch"], r["peak_grf_bw"], r["grf12_bw"],
        r["grf_mean_bw"], r["knee_max"], r["knee_pk"], r["toe_max"], r["com_z"], r["other_foot"]))


def opt(a):
    from search import make_optimizer
    cap = L.load_capture(a.name)
    cfg = cfg_of(a)
    body = L.Body(cap["task"], cap["board_x"], json.loads(cap["env"]))
    nm = len(body.muscles)
    X0 = L.x_from_recorded(cap, nm)
    if a.init:
        X0 = init_knots(cap, body, a.init)
    x0 = X0.ravel()
    base = L.simulate(body, cap, L.recorded_program(cap))
    r0 = simulate2(body, cap, lambda t, k: L.excitation(X0, t))
    best = (score2(r0, cap, cfg), x0.copy(), r0)
    print(f"{a.name}/{a.tag} start score {best[0]:.3f}  {fmt(r0)}", flush=True)
    log = []
    t0 = time.time()
    used = 0
    per_restart = a.evals // max(1, a.restarts)
    with mp.Pool(a.workers, initializer=_worker, initargs=(a.name, cfg)) as pool:
        for rs in range(max(1, a.restarts)):
            center = best[1].copy() if rs > 0 else x0
            opt_ = make_optimizer("sep_cma", center, sigma0=a.sigma, seed=a.seed + rs, **({"popsize": a.pop} if a.pop else {}))
            u = 0
            gen = 0
            while u < per_restart:
                X = np.clip(np.atleast_2d(opt_.ask()), 0.0, 1.0)
                res = pool.map(_eval, list(X), chunksize=max(1, len(X) // (a.workers * 2)))
                f = np.array([r[0] for r in res])
                opt_.tell(X, f, None)
                u += len(X)
                used += len(X)
                gen += 1
                i = int(np.argmax(f))
                if f[i] > best[0]:
                    best = (float(f[i]), X[i].copy(), res[i][1])
                if gen % 20 == 0 or u >= per_restart:
                    print(f"{a.name}/{a.tag} r{rs} used {used} best {best[0]:.3f} {fmt(best[2])} gen-med {np.median(f):.2f} sigma {opt_.sigma:.4f} ({time.time() - t0:.0f}s)", flush=True)
                log.append((used, best[0]))
    Xb = best[1].reshape(nm, -1)
    r = L.simulate(body, cap, lambda t, k: L.excitation(Xb, t), record=True)
    ns = argparse.Namespace(name=a.name, tag=a.tag, evals=a.evals, method="sep_cma_ljx")
    lm = float(a.lmax)
    L.save_result(ns, cap, body, base, lm, r, Xb, log)
    r2 = simulate2(body, cap, lambda t, k: L.excitation(Xb, t))
    print("FINAL", fmt(r2), flush=True)


def evaluate(a):
    cap = L.load_capture(a.name)
    cfg = cfg_of(a)
    body = L.Body(cap["task"], cap["board_x"], json.loads(cap["env"]))
    X = init_knots(cap, body, a.ideal)
    r = simulate2(body, cap, lambda t, k: L.excitation(X, t))
    print("score %.3f  %s" % (score2(r, cap, cfg), fmt(r)))
    if r["valid"]:
        print("td", {k: round(v, 3) for k, v in r["td"].items()}, "foot front - line %.3f" % (r["toe_max"] - cap["board_x"]))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    for nm in ("opt", "eval"):
        p = sub.add_parser(nm)
        p.add_argument("name")
        if nm == "eval":
            p.add_argument("ideal")
        else:
            p.add_argument("--tag", required=True)
            p.add_argument("--evals", type=int, default=200000)
            p.add_argument("--workers", type=int, default=6)
            p.add_argument("--sigma", type=float, default=0.04)
            p.add_argument("--pop", type=int, default=200)
            p.add_argument("--seed", type=int, default=1)
            p.add_argument("--init")
            p.add_argument("--restarts", type=int, default=1)
        p.add_argument("--board", action="store_true")
        p.add_argument("--margin", type=float, default=0.03)
        p.add_argument("--lmax", default="-1.5")
        p.add_argument("--lmin", default="-1e9")
        p.add_argument("--grfcap", default="1e9")
        p.add_argument("--grfw", default="0.2")
        p.add_argument("--kneemin", type=float, default=0.0, help="require the plant knee to flex at least this much (rad) in the stance")
        p.add_argument("--kneeload", type=float, default=0.0, help="require the plant knee to flex at least this much (rad) in the first 50 ms of the stance")
        p.add_argument("--kneew", type=float, default=10.0, help="... penalty per rad short of it")
        p.add_argument("--td", type=float, default=0.0)
        p.add_argument("--tdw", type=float, default=20.0)
    a = ap.parse_args()
    opt(a) if a.cmd == "opt" else evaluate(a)


if __name__ == "__main__":
    main()
