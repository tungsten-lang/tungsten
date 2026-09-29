"""MyoChallenge 2023 Relocate P2 for the round-5 skill (MyoRelocateV5Skill,
bin/robolab_myo_relocate_v5): the myo_relocate task (same environment,
metrics and search score) plus one sensor and grasp diagnostics.

Sensor (opt-in for the skill; the official observation has only the object's
site position and orientation, this is what a camera would add):

  obj_see   the object as seen: MyoSuite builds each object from three
            random primitives (sphere / capsule / ellipsoid / cylinder / box,
            each offset up to its own size from the body origin and turned at
            random), so the site the official observation reports can sit
            2-3 cm from the object's bulk. From a fixed point sample of the
            three primitives' volumes, posed at the current state:
              0-2  centroid (world, m)
              3    horizontal principal axis angle (rad, in [-pi/2, pi/2))
              4    half-extent along that axis (m, 95th percentile |proj|)
              5    half-extent across it (m)
              6    top z, 7 bottom z (m)
              8    elongation (along / across)

Search score: myo_relocate's, or with RELOC5_SCORE=placed the strict-placement
objective of myo_relocate_placed.

Diagnostics (metrics; never decide anything): the object's primitive types
(`shape`, e.g. "3,2,6"), its start position and seen centroid, the pinch
against the seen centroid at close (along / across the principal axis), the
pinch and palm speed at close, when each chunk started, and, for objects
lifted above the rim, where they were over the receptacle.
"""

import os

import numpy as np
import mujoco

from tasks.myo_relocate import MyoRelocateTask, cache, episode_store, hand_touch, RIM_Z, LIFT_Z

N_PTS = 160  # sample points per primitive


def _local_points(gtype, size, rng):
    """Uniform points inside one primitive, in its own frame."""
    if gtype == 2:  # sphere
        ext = np.array([size[0]] * 3)
    elif gtype == 3:  # capsule: radius, half-length of the cylinder part (z)
        ext = np.array([size[0], size[0], size[1] + size[0]])
    elif gtype == 4:  # ellipsoid
        ext = np.array(size[:3])
    elif gtype == 5:  # cylinder: radius, half-height
        ext = np.array([size[0], size[0], size[1]])
    else:  # box
        ext = np.array(size[:3])
    out = []
    while len(out) < N_PTS:
        p = rng.uniform(-ext, ext, size=(4 * N_PTS, 3))
        if gtype == 2:
            ok = np.sum(p ** 2, axis=1) <= size[0] ** 2
        elif gtype == 3:
            z = np.clip(p[:, 2], -size[1], size[1])
            ok = p[:, 0] ** 2 + p[:, 1] ** 2 + (p[:, 2] - z) ** 2 <= size[0] ** 2
        elif gtype == 4:
            ok = np.sum((p / ext) ** 2, axis=1) <= 1.0
        elif gtype == 5:
            ok = p[:, 0] ** 2 + p[:, 1] ** 2 <= size[0] ** 2
        else:
            ok = np.ones(len(p), bool)
        out.extend(p[ok])
    return np.array(out[:N_PTS])


def object_cloud(sim):
    """The object's sample points in the world at the current state."""
    ep = episode_store(sim)
    m, d = sim.m, sim.d
    c = cache(sim)
    g0 = m.body_geomadr[c.obj_body]
    gs = list(range(g0, g0 + m.body_geomnum[c.obj_body]))
    loc = ep.get("see_pts")
    if loc is None:
        rng = np.random.default_rng(12345)
        loc = ep["see_pts"] = [_local_points(int(m.geom_type[g]), m.geom_size[g], rng) for g in gs]
        ep["shape"] = ",".join(str(int(m.geom_type[g])) for g in gs)
    pts = [d.geom_xpos[g] + loc[i] @ d.geom_xmat[g].reshape(3, 3).T for i, g in enumerate(gs)]
    return np.concatenate(pts)


def percept(pts):
    ctr = pts.mean(axis=0)
    xy = pts[:, :2] - ctr[:2]
    cov = xy.T @ xy / len(xy)
    w, v = np.linalg.eigh(cov)
    ax = v[:, 1]
    ang = float(np.arctan2(ax[1], ax[0]))
    if ang >= np.pi / 2:
        ang -= np.pi
    if ang < -np.pi / 2:
        ang += np.pi
    along = xy @ ax
    across = xy @ np.array([-ax[1], ax[0]])
    ha = float(np.percentile(np.abs(along), 95))
    hc = float(np.percentile(np.abs(across), 95))
    return [float(ctr[0]), float(ctr[1]), float(ctr[2]), ang, ha, hc,
            float(pts[:, 2].max()), float(pts[:, 2].min()), ha / max(hc, 1e-4)]


def pinch_point(sim):
    c = cache(sim)
    d = sim.d
    return 0.5 * d.site_xpos[c.tips[0]] + 0.25 * (d.site_xpos[c.tips[1]] + d.site_xpos[c.tips[2]])


class MyoRelocateV5Task(MyoRelocateTask):
    name = "myo_relocate_v5"

    def __init__(self):
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        self.controller = os.path.join(root, "bin", "robolab_myo_relocate_v5")

    def extra_sensors(self, sim):
        see = percept(object_cloud(sim))
        ep = episode_store(sim)
        if "see0" not in ep:
            ep["see0"] = see
            ep["obj0"] = np.array(sim.u.obs_dict["obj_pos"], dtype=float)
        ep["see"] = see
        return super().extra_sensors(sim) + [("obj_see", see)]

    def on_step(self, sim, obs, reward, info):
        ep = episode_store(sim)
        first_close = "pinch_err" not in ep
        super().on_step(sim, obs, reward, info)
        lab = sim.label or ""
        chunk = lab.split(":")[-1]
        t = float(sim.d.time)
        starts = ep.setdefault("starts", {})
        if chunk and chunk not in starts:
            starts[chunk] = t
        p = pinch_point(sim)
        prev = ep.get("pinch_prev")
        ep["pinch_prev"] = p
        palm = np.array(sim.u.obs_dict["palm_pos"], dtype=float)
        pprev = ep.get("palm_prev")
        ep["palm_prev"] = palm
        # forearm roll during the grasp: the lowest pro_sup (rad) before the close
        c = cache(sim)
        if chunk in ("reach", "descend", "settle"):
            ps = float(sim.d.qpos[sim.m.jnt_qposadr[sim.m.joint("pro_sup").id]])
            ep["ps_min"] = min(ep.get("ps_min", 9.0), ps)
        # speeds after lift starts, while the hand still holds the object
        if chunk in ("lift", "carry", "lower"):
            touch = float(np.sum(hand_touch(sim, c)))
            ov = float(np.linalg.norm(sim.d.qvel[c.obj_dofs]))
            if touch > 1.0:
                ep["fling_v"] = max(ep.get("fling_v", 0.0), ov)
            elif "t_drop" not in ep and sim.u.obs_dict["obj_pos"][2] > 0.99:
                ep["t_drop"] = t
            if pprev is not None:
                ep["lift_palm_v"] = max(ep.get("lift_palm_v", 0.0), float(np.linalg.norm(palm - pprev) / 0.01))
        if first_close and "pinch_err" in ep:
            see = ep.get("see")
            if see is not None:
                ang = see[3]
                a = np.array([np.cos(ang), np.sin(ang)])
                dxy = p[:2] - np.array(see[:2])
                ep["pe_see"] = float(np.linalg.norm(dxy))
                ep["pe_along"] = float(abs(dxy @ a))
                ep["pe_across"] = float(abs(dxy @ np.array([-a[1], a[0]])))
                ep["pz_see"] = float(p[2] - see[2])
                # closing direction (thumb tip -> index/middle tips) against
                # the across axis, folded to [0, 90] degrees
                c = cache(sim)
                d = sim.d
                cl = 0.5 * (d.site_xpos[c.tips[1]] + d.site_xpos[c.tips[2]]) - d.site_xpos[c.tips[0]]
                ca = float(np.arctan2(cl[1], cl[0]))
                dd = abs((ca - (ang + np.pi / 2) + np.pi / 2) % np.pi - np.pi / 2)
                ep["yaw_err"] = float(np.degrees(dd))
                ep["close_ang"] = float(np.degrees(ca))
            if prev is not None:
                ep["pinch_speed"] = float(np.linalg.norm(p - prev) / 0.01)
            if pprev is not None:
                ep["palm_speed"] = float(np.linalg.norm(palm - pprev) / 0.01)
            ep["close_t"] = t
        # over the receptacle while above the rim (placement diagnostics)
        o = np.array(sim.u.obs_dict["obj_pos"], dtype=float)
        g = ep["goal"][0]
        if o[2] > RIM_Z:
            dxy = float(np.linalg.norm(o[:2] - g[:2]))
            if dxy < ep.get("hi_dxy", 9.0):
                ep["hi_dxy"] = dxy
                ep["hi_dx"] = float(o[0] - g[0])
                ep["hi_dy"] = float(o[1] - g[1])

    def metrics(self, sim, log):
        out = super().metrics(sim, log)
        ep = episode_store(sim)
        see0 = ep.get("see0", [0.0] * 9)
        obj0 = ep.get("obj0", np.zeros(3))
        st = ep.get("starts", {})
        out.update({
            "shape": ep.get("shape", ""),
            "x0": round(float(obj0[0]), 4), "y0": round(float(obj0[1]), 4),
            "see_off": round(float(np.linalg.norm(np.array(see0[:2]) - obj0[:2])), 4),
            "elong": round(float(see0[8]), 3), "half_across": round(float(see0[5]), 4),
            "half_along": round(float(see0[4]), 4), "top_z": round(float(see0[6]), 4),
            "pe_see": round(ep.get("pe_see", 0.2), 4), "pe_along": round(ep.get("pe_along", 0.2), 4),
            "pe_across": round(ep.get("pe_across", 0.2), 4), "pz_see": round(ep.get("pz_see", 0.2), 4),
            "yaw_err": round(ep.get("yaw_err", -1.0), 1), "close_ang": round(ep.get("close_ang", 0.0), 1),
            "pinch_speed": round(ep.get("pinch_speed", -1.0), 4), "close_t": round(ep.get("close_t", -1.0), 3),
            "hi_dxy": round(ep.get("hi_dxy", 9.0), 4), "hi_dx": round(ep.get("hi_dx", 0.0), 4),
            "hi_dy": round(ep.get("hi_dy", 0.0), 4),
            "lifted_rim": float(out.get("max_held_z", 0.9) > LIFT_Z),
            "ps_min": round(ep.get("ps_min", 9.0), 3),
            "palm_speed": round(ep.get("palm_speed", -1.0), 4), "fling_v": round(ep.get("fling_v", 0.0), 3),
            "t_drop": round(ep.get("t_drop", -1.0), 3), "lift_palm_v": round(ep.get("lift_palm_v", 0.0), 3),
        })
        for k in ("reach", "descend", "settle", "close", "lift", "carry", "lower", "release"):
            out["t_" + k] = round(st.get(k, -1.0), 3)
        return out


    def score(self, metrics):
        # RELOC5_SCORE=placed: the strict-placement search objective
        # (myo_relocate_placed); otherwise myo_relocate's
        if os.environ.get("RELOC5_SCORE") == "placed":
            entry = metrics.get("entry_z", 0.0)
            over = min(1.0, max(0.0, (entry - 1.0) / 0.12)) if entry > 0.0 else 0.0
            held = min(1.0, max(0.0, (metrics.get("max_held_z", 0.9) - 0.91) / 0.25))
            return (metrics.get("success_placed", 0.0) + 0.3 * metrics.get("success_lift", 0.0)
                    + 0.05 * metrics.get("success", 0.0) + 0.3 * over + 0.3 * held
                    + 0.2 * super().score(metrics) / 2.2)
        return super().score(metrics)


TASK = MyoRelocateV5Task
