"""Sprint from starting blocks on the v3 anatomy (elastic Achilles and
quadriceps tendons, planar root, strength 1.0, 1 ms physics).

The body starts in the SET position of Usain Bolt's block start (the joint
angles of playground/refs/bolt/bolt_keyframes.json, event `set`, taken from
video; see playground/refs/bolt/SOURCES.md): hands on the track just behind
the start line, the front (left) foot on the front pad, the rear (right) foot
on the rear pad. The two pads are angled plates placed under the soles of
that posture (the athlete sets his blocks to his body), each only under its
own foot's line. The whole body is rotated about the pitch axis and lifted
so that both hands and the front foot's toes touch the track (joint angles
as Bolt's; the trunk angle that results is reported). A seed perturbs the
set posture (legs, spine, shoulders N(0, 0.02) rad, pitch N(0, 0.01) rad).

The gun fires at T_GUN (fixed, 1.4 s; "set" is called at T_SET 0.8 s, after
the body has settled). The controller hears it through the `gun` sensor (time
since the gun, 0 before) and feels its blocks through `blocks` (normal force
on the front and rear pad, body weights).

Rules (World Athletics Technical Rules 16 and 18, as far as a planar body
needs them):
  false start  from T_SET until T_GUN + 0.100 s (TR 16.6: a reaction faster
               than 0.100 s is a false start): a hand leaving the track, a
               foot moving more than 3 cm from where it was at T_SET, the pelvis
               moving more than 3 cm, or a reaction under 0.100 s:
               reaction = the start information system's force onset (the
               summed pad force departing from its level over the 0.2 s
               before the gun by more than 0.2 body weights for 10 ms) - T_GUN.
  fall         any body part other than the feet touching the track (the
               hands until they first leave it after the gun), the pelvis
               below 0.35 m or the torso pitched past 2.3 rad during the start
               (until the chest passes 10 m), below 0.6 m / past 1.1 rad
               after it. `fell_race` = a fall before the finish.
  finish       time from the gun until the chest (the torso's `chest` site)
               crosses the line: t10, t20, ..., t100 (the gun-to-line times
               of the published 10 m splits; the chest starts ~0.1 m behind
               the start line). The finish of this rollout is
               SPRINT_DISTANCE (30 or 100, env; default 100).
Lanes are not an issue for a planar body.

Metrics (besides tasks/run.py's): false_start, reaction, rear_block_time and
block_time (gun to the rear / front foot leaving its pad), t10..t100,
t_finish, v10..v100 (mean speed over each 10 m), peak_v, fell_race, steps
(touchdowns to the finish), step_len / step_freq / contact / flight over the
max-velocity window, first-step contact and flight times, and the Bolt form
error:

  form_err     joint-angle RMS error (deg) between the body and Bolt's
               max-velocity keyframes (maxv_td, maxv_ms, maxv_to, maxv_mkl)
               at every such gait event whose chest position lies in the
               max-velocity window (40 m to the finish); the angles are the
               video's own definitions measured on the model's keypoints
               (trunk = hip->shoulder line, hip = thigh relative to that line,
               knee, ankle = shank vs heel->toe - 90; stance and swing leg).
               The arms are not scored (the video's arm angles are
               low-confidence); form_arms reports them. v_maxv is the mean
               speed over that window and `fast` its guard (v_maxv >=
               FORM_SPEED_FLOOR).
  acc_form     the same against Bolt's first two steps (steps 1-2 TD/TO).

ROBOLAB_V3_TIMESTEP / ROBOLAB_V3_TENDON_SCALE as in tasks/run_v3.py; SPRINT_BODY=v2
builds the rigid v2 body instead (tasks/sprint_blocks_v2.py sets it).

CLI (.venv/bin/python playground/tasks/sprint_blocks.py -h):
  eval     one rollout, JSON summary
  render   video / gif / keyframe sheet (our runner vs Bolt's stick figures)
  editor   write playground/refs/bolt/editor/<event>.json (the keyframe editor's schema)
  refw     regenerate lib/robolab/skills/sprint_ref.w (the skill's built-in Bolt table)
"""

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # run as a script too
import mujoco  # noqa: E402
import numpy as np  # noqa: E402

from body import HumanoidV2Builder, HumanoidV3Builder, scene_xml, settle_fibers  # noqa: E402
from bridge import ROOT  # noqa: E402
from tasks.run import RunTask  # noqa: E402

# SPRINT_REF: another reference file, or "provisional" for the literature table
REF_JSON = os.environ.get("SPRINT_REF") or os.path.join(ROOT, "playground", "refs", "bolt", "bolt_keyframes.json")
TIMESTEP = float(os.environ.get("ROBOLAB_V3_TIMESTEP", "0.001"))
TENDON_SCALE = float(os.environ.get("ROBOLAB_V3_TENDON_SCALE", "1.0"))
T_SET = 0.8
T_GUN = 1.4
REACTION_MIN = 0.100
FORM_FROM = 40.0          # the max-velocity window starts when the chest passes 40 m
FORM_SPEED_FLOOR = 4.0    # m/s over that window (the `fast` guard)
DEG = 180.0 / math.pi
RAD = math.pi / 180.0

EVENTS = ["set", "rear_exit", "block_exit", "s1_td", "s1_to", "s2_td", "s2_to", "s3_td", "s3_to",
          "drive_td", "drive_to", "maxv_td", "maxv_ms", "maxv_to", "maxv_mkl"]
LABELS = {"set": "Set position", "rear_exit": "Rear foot leaves the block", "block_exit": "Block exit (front foot leaves)",
          "s1_td": "Step 1 touchdown", "s1_to": "Step 1 toe-off", "s2_td": "Step 2 touchdown", "s2_to": "Step 2 toe-off",
          "s3_td": "Step 3 touchdown", "s3_to": "Step 3 toe-off", "drive_td": "Drive-phase touchdown",
          "drive_to": "Drive-phase toe-off", "maxv_td": "Max-velocity touchdown", "maxv_ms": "Max-velocity mid-stance",
          "maxv_to": "Max-velocity toe-off", "maxv_mkl": "Max-velocity max knee lift"}
# the video's roles (running events; block events use front_ / rear_, read as st_ / sw_)
ROLES = ["trunk", "st_hip", "st_knee", "st_ankle", "sw_hip", "sw_knee", "sw_ankle", "st_shoulder", "sw_shoulder",
         "st_elbow", "sw_elbow"]
# the model / keyframe-editor keys (degrees): hip = thigh relative to the pelvis,
# spine = torso relative to the pelvis, pelvis = world pitch of the pelvis
MODEL_KEYS = ["st_hip", "st_knee", "st_ankle", "st_toe", "sw_hip", "sw_knee", "sw_ankle", "sw_toe", "st_shoulder",
              "st_elbow", "sw_shoulder", "sw_elbow", "spine", "pelvis"]
# The video cannot separate the pelvis from the lumbar spine; the model's split
# (spine flexion, deg) per event: a rounded back in the blocks, rising to
# run_natural's 4 deg at speed.
SPINE = {"set": 20.0, "rear_exit": 14.0, "block_exit": 10.0, "s1_td": 8.0, "s1_to": 8.0, "s2_td": 7.0, "s2_to": 7.0,
         "s3_td": 6.0, "s3_to": 6.0, "drive_td": 5.0, "drive_to": 5.0}
# toe joint (the video has no toe): extended over the ball at every toe-off
TOE_TO = -25.0

# PROVISIONAL literature values (video conventions), used only until the video
# reference exists: set position after Slawinski et al. 2010 / Bezodis et al.
# 2015 (interior angles converted), the rest rough sprint-start and
# max-velocity kinematics (Mann & Herman 1985; Mero et al. 1992).
PROVISIONAL = {
    "set": {"trunk": 100, "st_hip": 138, "st_knee": 88, "st_ankle": -5, "sw_hip": 100, "sw_knee": 60, "sw_ankle": -5,
            "st_shoulder": 95, "sw_shoulder": 95, "st_elbow": 5, "sw_elbow": 5},
    "rear_exit": {"trunk": 80, "st_hip": 120, "st_knee": 70, "st_ankle": 5, "sw_hip": 75, "sw_knee": 55, "sw_ankle": 20,
                  "st_shoulder": 60, "sw_shoulder": 20, "st_elbow": 70, "sw_elbow": 50},
    "block_exit": {"trunk": 48, "st_hip": 25, "st_knee": 15, "st_ankle": 25, "sw_hip": 110, "sw_knee": 100,
                   "sw_ankle": 0, "st_shoulder": 80, "sw_shoulder": -30, "st_elbow": 90, "sw_elbow": 90},
    "s1_td": {"trunk": 45, "st_hip": 42, "st_knee": 55, "st_ankle": -5, "sw_hip": 25, "sw_knee": 85, "sw_ankle": 20,
              "st_shoulder": -30, "sw_shoulder": 65, "st_elbow": 90, "sw_elbow": 90},
    "s1_to": {"trunk": 44, "st_hip": 15, "st_knee": 15, "st_ankle": 28, "sw_hip": 105, "sw_knee": 105, "sw_ankle": 0,
              "st_shoulder": 75, "sw_shoulder": -35, "st_elbow": 90, "sw_elbow": 90},
    "s2_td": {"trunk": 40, "st_hip": 45, "st_knee": 45, "st_ankle": -5, "sw_hip": 25, "sw_knee": 95, "sw_ankle": 20,
              "st_shoulder": -30, "sw_shoulder": 65, "st_elbow": 90, "sw_elbow": 90},
    "s2_to": {"trunk": 38, "st_hip": 10, "st_knee": 15, "st_ankle": 30, "sw_hip": 100, "sw_knee": 110, "sw_ankle": 0,
              "st_shoulder": 75, "sw_shoulder": -35, "st_elbow": 90, "sw_elbow": 90},
    "s3_td": {"trunk": 35, "st_hip": 45, "st_knee": 40, "st_ankle": -3, "sw_hip": 20, "sw_knee": 105, "sw_ankle": 15,
              "st_shoulder": -30, "sw_shoulder": 65, "st_elbow": 90, "sw_elbow": 90},
    "s3_to": {"trunk": 33, "st_hip": 5, "st_knee": 15, "st_ankle": 30, "sw_hip": 95, "sw_knee": 115, "sw_ankle": 0,
              "st_shoulder": 75, "sw_shoulder": -35, "st_elbow": 90, "sw_elbow": 90},
    "drive_td": {"trunk": 22, "st_hip": 45, "st_knee": 30, "st_ankle": 0, "sw_hip": 25, "sw_knee": 115, "sw_ankle": 10,
                 "st_shoulder": -35, "sw_shoulder": 60, "st_elbow": 90, "sw_elbow": 90},
    "drive_to": {"trunk": 20, "st_hip": -5, "st_knee": 18, "st_ankle": 30, "sw_hip": 85, "sw_knee": 120, "sw_ankle": 0,
                 "st_shoulder": 70, "sw_shoulder": -40, "st_elbow": 90, "sw_elbow": 90},
    "maxv_td": {"trunk": 8, "st_hip": 35, "st_knee": 20, "st_ankle": 5, "sw_hip": 15, "sw_knee": 120, "sw_ankle": 10,
                "st_shoulder": -40, "sw_shoulder": 55, "st_elbow": 90, "sw_elbow": 90},
    "maxv_ms": {"trunk": 8, "st_hip": 12, "st_knee": 40, "st_ankle": -18, "sw_hip": 45, "sw_knee": 130, "sw_ankle": 0,
                "st_shoulder": 10, "sw_shoulder": 10, "st_elbow": 90, "sw_elbow": 90},
    "maxv_to": {"trunk": 8, "st_hip": -15, "st_knee": 20, "st_ankle": 32, "sw_hip": 78, "sw_knee": 110, "sw_ankle": 0,
                "st_shoulder": 60, "sw_shoulder": -45, "st_elbow": 90, "sw_elbow": 90},
    "maxv_mkl": {"trunk": 8, "st_hip": -10, "st_knee": 45, "st_ankle": 25, "sw_hip": 85, "sw_knee": 100, "sw_ankle": 0,
                 "st_shoulder": 60, "sw_shoulder": -40, "st_elbow": 90, "sw_elbow": 90},
}


# ---- the reference -----------------------------------------------------------------

def _pitch_for_trunk(trunk, spine):
    """Pelvis pitch (deg) that puts the model's hip->shoulder line at `trunk`
    (deg) with the spine flexed `spine` deg: the pelvis carries the torso's base
    0.10 m up its axis, the shoulders sit 0.42 m up the torso's."""
    s = spine * RAD
    p = trunk * RAD - 0.8 * s
    for _ in range(30):
        vx = 0.10 * math.sin(p) + 0.42 * math.sin(p + s)
        vz = 0.10 * math.cos(p) + 0.42 * math.cos(p + s)
        p += trunk * RAD - math.atan2(vx, vz)
    return p * DEG


ARM_ROLES = ("st_shoulder", "sw_shoulder", "st_elbow", "sw_elbow")
LEG_ROLES = [r for r in ROLES if r not in ARM_ROLES]
# the not-measured anchors are interpolated between step 2 and the
# max-velocity cycle at these step indices (the skill's default anchors)
INTERP = {"s3": 3, "drive": 6}
MAXV_STEP = 13


class BoltRef:
    """Bolt's keyframes: video-convention angles per event (mean, sd) and the
    model / editor posture that realises them.

    From bolt_keyframes.json: the trunk and both legs as measured, except
      set          the video pose is unreliable (quality "poor"): the JSON's
                   `literature` set (2018 World Indoor 60 m finalists) for the
                   trunk, hips and knees, the ankles provisional, the arms
                   hanging 5 deg behind the trunk line
      s3, drive    not measured: legs interpolated between step 2 and the
                   max-velocity cycle by step index (INTERP), trunk from the
                   JSON's trunk_by_step model
      arms         every video arm angle is low-confidence (the near arm only,
                   forward swing underestimated): the keyframes and ghost use
                   the provisional literature arm swing, and form_err scores
                   the trunk and legs only (form_arms reports the arms)
    """

    def __init__(self, path=REF_JSON):
        self.path = path
        self.provisional = path == "provisional" or not os.path.exists(path)
        self.mean, self.sd, self.src, self.video_arms = {}, {}, {}, {}
        if self.provisional:
            for ev, a in PROVISIONAL.items():
                self.mean[ev] = {k: float(v) for k, v in a.items()}
                self.sd[ev] = {}
                self.src[ev] = "provisional literature values (no video reference)"
            return
        with open(path) as f:
            js = json.load(f)
        self.json = js

        def roles(d):
            out = {}
            for role, v in (d or {}).items():
                r = role.replace("front_", "st_").replace("rear_", "sw_")
                if isinstance(v, dict) and v.get("mean") is not None:
                    out[r] = (float(v["mean"]), v.get("sd"))
                elif isinstance(v, (int, float)):
                    out[r] = (float(v), None)
            return out
        events = js.get("events", {})
        for ev in EVENTS:
            e = events.get(ev, {})
            got = roles(e.get("angles"))
            mean, sd = {}, {}
            if e.get("quality") == "poor" and e.get("literature"):
                got = roles(e["literature"])
                self.src[ev] = "literature: " + str(e["literature"].get("source", ""))
            else:
                n = len(e.get("sources") or [])
                self.src[ev] = f"video, {n} instances ({e.get('quality', '')})" if got else ""
            for r in LEG_ROLES:
                if r in got:
                    mean[r], sd[r] = got[r][0], got[r][1]
            self.video_arms[ev] = {r: got[r][0] for r in ARM_ROLES if r in got}
            self.mean[ev], self.sd[ev] = mean, {k: v for k, v in sd.items() if v is not None}
        # not-measured anchors: interpolate the legs, trunk from the lean model
        tbs = {int(row[0]): row for row in js.get("trunk_by_step", [])}
        for pre, k in INTERP.items():
            w = (k - 2) / (MAXV_STEP - 2)
            for kind, col in (("td", 1), ("to", 2)):
                ev = f"{pre}_{kind}"
                if self.mean.get(ev):
                    continue
                a, b = self.mean[f"s2_{kind}"], self.mean[f"maxv_{kind}"]
                self.mean[ev] = {r: a[r] + w * (b[r] - a[r]) for r in LEG_ROLES if r in a and r in b}
                if k in tbs and tbs[k][col] is not None:
                    self.mean[ev]["trunk"] = float(tbs[k][col])
                self.sd[ev] = {}
                self.src[ev] = f"not measured: legs interpolated step 2 -> max velocity ({w:.2f}), trunk_by_step model"
        # every missing role (set ankles, all arms) from the provisional table
        for ev in EVENTS:
            for r, v in PROVISIONAL[ev].items():
                if r in ARM_ROLES or r not in self.mean[ev]:
                    self.mean[ev][r] = float(v)
        t = self.mean["set"]["trunk"]
        for r in ("st_shoulder", "sw_shoulder"):
            self.mean["set"][r] = t - 5.0

    def video(self, ev):
        return dict(self.mean[ev])

    def model(self, ev):
        """The model posture (degrees, editor keys) that shows the event's
        video angles: pelvis pitch solved so the hip->shoulder line is at the
        trunk angle with SPINE[ev] of spine flexion; hip = thigh vs pelvis."""
        a = self.mean[ev]
        spine = SPINE.get(ev, 4.0)
        trunk = a["trunk"]
        p = _pitch_for_trunk(trunk, spine)
        out = {"spine": spine, "pelvis": p}
        for r in ("st", "sw"):
            out[r + "_hip"] = a[r + "_hip"] - trunk + p
            out[r + "_knee"] = a[r + "_knee"]
            out[r + "_ankle"] = a[r + "_ankle"]
            out[r + "_toe"] = TOE_TO if (r == "st" and (ev.endswith("_to") or ev == "block_exit")) else 0.0
            # the arm's world angle from straight down is shoulder - trunk; the
            # model shoulder is measured from the torso's downward axis
            out[r + "_shoulder"] = a[r + "_shoulder"] - trunk + p + spine
            out[r + "_elbow"] = a[r + "_elbow"]
        return {k: round(float(out[k]), 2) for k in MODEL_KEYS}


# ---- keypoints of the model (the video's angle definitions) --------------------------

def _ang_from_down(v):
    return math.degrees(math.atan2(v[0], -v[2]))


def _interior(a, b, c):
    u, w = a - b, c - b
    cs = float(np.dot(u, w) / (np.linalg.norm(u) * np.linalg.norm(w) + 1e-12))
    return math.degrees(math.acos(max(-1.0, min(1.0, cs))))


class Keypoints:
    """Body/site ids of the model's video keypoints."""

    def __init__(self, m):
        b = lambda n: m.body(n).id  # noqa: E731
        s = lambda n: m.site(n).id  # noqa: E731
        self.ids = {side: {"hip": b(f"{side}_thigh"), "knee": b(f"{side}_shin"), "ankle": b(f"{side}_foot"),
                           "heel": s(f"{side}_heel"), "toe": s(f"{side}_toe"), "shoulder": b(f"{side}_upper_arm"),
                           "elbow": b(f"{side}_forearm"), "wrist": b(f"{side}_hand")} for side in "lr"}

    def points(self, d, side):
        i = self.ids[side]
        out = {k: d.xpos[v].copy() for k, v in i.items() if k not in ("heel", "toe")}
        out["heel"] = d.site_xpos[i["heel"]].copy()
        out["toe"] = d.site_xpos[i["toe"]].copy()
        return out

    def angles(self, d, st):
        """Video-convention angles (deg) with `st` ("l" / "r") the stance side."""
        sw = "r" if st == "l" else "l"
        P = {s: self.points(d, s) for s in "lr"}
        hip = (P["l"]["hip"] + P["r"]["hip"]) / 2
        sh = (P["l"]["shoulder"] + P["r"]["shoulder"]) / 2
        v = sh - hip
        trunk = math.degrees(math.atan2(v[0], v[2]))
        out = {"trunk": trunk}
        for role, s in (("st", st), ("sw", sw)):
            p = P[s]
            thigh = _ang_from_down(p["knee"] - p["hip"])
            out[role + "_thigh"] = thigh
            out[role + "_hip"] = thigh + trunk
            out[role + "_knee"] = 180.0 - _interior(p["hip"], p["knee"], p["ankle"])
            sv, fv = p["knee"] - p["ankle"], p["toe"] - p["heel"]
            cs = float(np.dot(sv, fv) / (np.linalg.norm(sv) * np.linalg.norm(fv) + 1e-12))
            out[role + "_ankle"] = math.degrees(math.acos(max(-1.0, min(1.0, cs)))) - 90.0
            out[role + "_shoulder"] = _ang_from_down(p["elbow"] - p["shoulder"]) + trunk
            out[role + "_elbow"] = 180.0 - _interior(p["shoulder"], p["elbow"], p["wrist"])
        return out


def model_qpos(m, qpos, kf, st, adr):
    """A copy of qpos with the joints at a model keyframe (editor keys, deg;
    `st` the stance side) and the pelvis at its pitch (root x / z kept)."""
    q = np.array(qpos, float).copy()
    sw = "r" if st == "l" else "l"
    for role, s in (("st", st), ("sw", sw)):
        for j, key in (("hip_flex", "hip"), ("knee", "knee"), ("ankle", "ankle"), ("toe", "toe"),
                       ("shoulder_flex", "shoulder"), ("elbow", "elbow")):
            name = f"{s}_{j}"
            lo, hi = m.jnt_range[m.joint(name).id]
            q[adr[name]] = float(np.clip(kf[f"{role}_{key}"] * RAD, lo, hi))
    q[adr["spine_flex"]] = kf["spine"] * RAD
    q[adr["root_pitch"]] = kf["pelvis"] * RAD
    return q


# ---- the set position and the blocks ---------------------------------------------------

JOINTS = ("spine_flex", "l_shoulder_flex", "l_elbow", "r_shoulder_flex", "r_elbow", "l_hip_flex", "l_knee",
          "l_ankle", "l_toe", "r_hip_flex", "r_knee", "r_ankle", "r_toe", "root_x", "root_z", "root_pitch")
FRONT, REAR = "l", "r"
PAD_HALF = (0.15, 0.05, 0.015)   # along the sole, across, thickness (m)
SOLE = (0.07, -0.08)             # centre of the sole (heel -0.07 .. toe tip 0.21) in the foot body frame
TOE_GAP = 0.015                  # the front toes rest this far above the track (the feet load the pads, not the track)


def _box_corners(m, d, gid):
    c = d.geom_xpos[gid]
    R = d.geom_xmat[gid].reshape(3, 3)
    sz = m.geom_size[gid]
    return [c + R @ (np.array([a, b, e]) * sz) for a in (-1, 1) for b in (-1, 1) for e in (-1, 1)]


def _geom_low(m, d, gid):
    """Lowest world z of a box geom."""
    return min(float(p[2]) for p in _box_corners(m, d, gid))


def set_position(m, d, kf, start_x):
    """Pose the body in the set keyframe (editor keys, st = FRONT): rotate the
    whole body about the pitch axis until both hands are TOE_GAP below the
    front toes, then lower it onto the track with the hands' front edge at
    start_x. Returns the pelvis pitch used (deg). (The model's arms are ~0.1 m
    shorter than a human's shoulder-to-fingertip, so the rotation tilts them
    back from the keyframe's world angle.)"""
    adr = {j: m.joint(j).qposadr[0] for j in JOINTS}
    hands = [m.geom(f"{s}_hand").id for s in "lr"]
    front = [m.geom(f"{FRONT}_foot").id, m.geom(f"{FRONT}_toes").id]

    def place(pitch):
        kk = dict(kf)
        kk["pelvis"] = pitch
        d.qpos[:] = model_qpos(m, d.qpos, kk, FRONT, adr)
        d.qpos[adr["root_x"]] = 0.0
        d.qpos[adr["root_z"]] = 1.5
        mujoco.mj_kinematics(m, d)
        return min(_geom_low(m, d, g) for g in hands) - min(_geom_low(m, d, g) for g in front)

    # the front toes rest TOE_GAP above the track (on the pad, not the track)
    lo, hi = kf["pelvis"] - 45.0, kf["pelvis"] + 45.0
    flo, fhi = place(lo) + TOE_GAP, place(hi) + TOE_GAP
    if (flo > 0) == (fhi > 0):
        raise ValueError(f"set position: no pitch puts the hands and the front toes on the track ({flo:.3f}, {fhi:.3f})")
    for _ in range(40):  # bisection: hands TOE_GAP below the front toes
        mid = 0.5 * (lo + hi)
        fm = place(mid) + TOE_GAP
        if (fm > 0) == (flo > 0):
            lo, flo = mid, fm
        else:
            hi = mid
    pitch = 0.5 * (lo + hi)
    place(pitch)
    low = min(_geom_low(m, d, g) for g in hands)
    d.qpos[adr["root_z"]] -= low
    mujoco.mj_kinematics(m, d)
    front_x = max(float(p[0]) for g in hands for p in _box_corners(m, d, g))
    d.qpos[adr["root_x"]] += start_x - front_x - 0.005
    mujoco.mj_forward(m, d)
    return pitch


def pad_xml(m, d):
    """World geoms for the two pads (under each sole of the posed body), a
    visual stand under each, and the start line."""
    out = []
    for side, name in ((FRONT, "front"), (REAR, "rear")):
        fb = m.body(f"{side}_foot").id
        R = d.xmat[fb].reshape(3, 3)
        c = d.xpos[fb] + R @ np.array([SOLE[0], 0.0, SOLE[1] - PAD_HALF[2] - 0.0005])
        q = d.xquat[fb]
        out.append(f'<geom name="pad_{name}" type="box" pos="{c[0]:.5f} {c[1]:.5f} {c[2]:.5f}" '
                   f'quat="{q[0]:.6f} {q[1]:.6f} {q[2]:.6f} {q[3]:.6f}" size="{PAD_HALF[0]} {PAD_HALF[1]} {PAD_HALF[2]}" '
                   f'contype="1" conaffinity="2" friction="2.0 0.02 0.002" rgba="0.12 0.14 0.18 1"/>')
        # the stand: from the pad's lowest edge down to the track (visual only)
        ends = [c + R @ np.array([sx * PAD_HALF[0], 0.0, -PAD_HALF[2]]) for sx in (-1, 1)]
        low = min(ends, key=lambda e: e[2])
        h = max(float(low[2]), 0.0)
        if h > 0.004:
            out.append(f'<geom name="stand_{name}" type="box" pos="{low[0]:.5f} {c[1]:.5f} {h / 2:.5f}" '
                       f'size="0.012 {PAD_HALF[1]} {h / 2:.5f}" contype="0" conaffinity="0" rgba="0.45 0.47 0.52 1"/>')
    return out


class SprintBlocksTask(RunTask):
    name = "sprint_blocks"
    controller = os.path.join(ROOT, "bin", "robolab_sprint_blocks")
    timestep = TIMESTEP
    seconds = 35.0
    distance = float(os.environ.get("SPRINT_DISTANCE", "100"))
    body = os.environ.get("SPRINT_BODY", "v3")
    body_note = "v3 anatomy (v2 + series-elastic Achilles and quadriceps tendons), planar root, strength 1.0, 1 ms physics"
    ghost = True
    keep_qpos = True

    def builder(self):
        if self.body == "v2":
            return HumanoidV2Builder(self.mode, strength=self.strength, wrists=self.wrists)
        return HumanoidV3Builder(self.mode, strength=self.strength, wrists=self.wrists, stiffness_scale=TENDON_SCALE)

    def reference(self):
        if not hasattr(self, "_ref"):
            self._ref = BoltRef()
        return self._ref

    # ---- scene ---------------------------------------------------------------------

    def xml_extras(self):
        extras = super().xml_extras()
        # pose a twin body in the set keyframe to place the pads under its soles
        twin_b = self.builder()
        m = mujoco.MjModel.from_xml_string(scene_xml(twin_b, timestep=self.timestep))
        d = mujoco.MjData(m)
        self.set_kf = self.reference().model("set")
        self.set_pitch = set_position(m, d, self.set_kf, self.start_x)
        lines = pad_xml(m, d)
        lines.append(f'<geom name="start_line" type="box" pos="{self.start_x + 0.025} 0 0.001" size="0.025 0.6 0.001" '
                     f'rgba="1 1 1 1" contype="0" conaffinity="0"/>')
        for dist in (30.0, 100.0):
            lines.append(f'<geom name="finish_{int(dist)}" type="box" pos="{self.start_x + dist + 0.025} 0 0.001" '
                         f'size="0.025 0.6 0.001" rgba="0.95 0.95 0.2 1" contype="0" conaffinity="0"/>')
        extras["extra_world"] = extras.get("extra_world", "") + "\n    " + "\n    ".join(lines)
        return extras

    # ---- reset -------------------------------------------------------------------------

    def reset(self, m, d):
        seed, self.seed = self.seed, None
        super().reset(m, d)
        self.seed = seed
        self.distance = float(os.environ.get("SPRINT_DISTANCE", self.distance))
        self._m, self._kd = m, mujoco.MjData(m)
        self.adr = {j: m.joint(j).qposadr[0] for j in JOINTS}
        set_position(m, d, self.set_kf, self.start_x)
        self.flying = os.environ.get("SPRINT_START", "blocks") == "flying"
        self._seed = seed
        if self.flying:
            self._flying_start(m, d)
        if seed is not None and not self.flying:
            rng = np.random.default_rng(seed)
            for j in ("l_hip_flex", "r_hip_flex", "l_knee", "r_knee", "l_ankle", "r_ankle", "spine_flex",
                      "l_shoulder_flex", "r_shoulder_flex"):
                lo, hi = m.jnt_range[m.joint(j).id]
                d.qpos[self.adr[j]] = float(np.clip(d.qpos[self.adr[j]] + rng.normal(0.0, 0.02), lo, hi))
            d.qpos[self.adr["root_pitch"]] += rng.normal(0.0, 0.01)
        mujoco.mj_forward(m, d)
        self._lift_out_of_contact(m, d)
        settle_fibers(m, d)
        self.pads = {"front": m.geom("pad_front").id, "rear": m.geom("pad_rear").id}
        self.hand_geoms = {m.geom("l_hand").id, m.geom("r_hand").id}
        self.chest = m.site("chest").id
        self.kp = Keypoints(m)
        self.line_x = self.start_x
        self.pelvis_z0 = float(d.xpos[self.pelvis][2])
        # run state
        self.fall_t = None
        self.fall_why = ""
        self.false = None          # (time, reason) of a false start
        self.onset = None          # block-force onset
        self.base_f = []           # block force samples in [T_SET, T_SET + 0.1)
        self.dev_since = None
        self.pelvis_set = None
        self.hands_down = True
        self.hands_off_since = None
        self.pad_off = {"front": None, "rear": None}
        self.pad_free = {"front": None, "rear": None}
        self.pad_gap = {"front": None, "rear": None}
        self.exit_state = {}       # COM z, vx, vz and torso pitch (deg) as each foot leaves its pad
        self.pad_feet = {k: m.body(f"{side}_foot").id for k, side in (("front", FRONT), ("rear", REAR))}
        self.srec = []             # per physics step: t, chest x, pelvis x, pelvis z, lc, rc, F front, F rear
        self.qrec = []             # per control tick: (t, qpos)
        self.kf_target = None
        self.cam_x = None
        if self.flying:
            self.hands_down = False

    def _flying_start(self, m, d):
        """Development: the body in flight just after a left toe-off, in Bolt's
        max-velocity toe-off keyframe, moving at SPRINT_V0 (m/s), well ahead of
        the blocks (the stride machinery without the start)."""
        kfs = os.environ.get("SPRINT_FLY_KF", "maxv_to").split(",")  # several: the seed picks one
        pick = kfs[self._seed % len(kfs)] if self._seed is not None else kfs[0]
        kf = self.reference().model(pick)
        d.qpos[:] = model_qpos(m, d.qpos, kf, "l", self.adr)
        d.qpos[self.adr["root_x"]] = self.start_x + 2.0
        d.qpos[self.adr["root_z"]] = 1.2
        mujoco.mj_forward(m, d)
        low = min(float(d.geom_xpos[m.geom(g).id][2]) for g in ("l_foot", "r_foot", "l_toes", "r_toes")) - 0.03
        d.qpos[self.adr["root_z"]] += 0.01 - low
        v0 = float(os.environ.get("SPRINT_V0", "4.0"))
        if self._seed is not None:
            rng = np.random.default_rng(self._seed)
            lo_hi = os.environ.get("SPRINT_V0_RANGE")  # e.g. "1.8,3.2": the seed draws the speed
            if lo_hi:
                lo, hi = (float(x) for x in lo_hi.split(","))
                v0 = float(rng.uniform(lo, hi))
            for j in ("l_hip_flex", "r_hip_flex", "l_knee", "r_knee", "l_ankle", "r_ankle", "spine_flex"):
                d.qpos[self.adr[j]] += rng.normal(0.0, 0.03)
            d.qpos[self.adr["root_pitch"]] += rng.normal(0.0, 0.02)
            v0 += rng.normal(0.0, 0.2)
        d.qvel[m.joint("root_x").dofadr[0]] = v0
        d.qvel[m.joint("root_z").dofadr[0]] = 0.3
        mujoco.mj_forward(m, d)

    def _lift_out_of_contact(self, m, d):
        """Raise the body until no geom penetrates the track or a pad (a
        perturbed set posture then settles onto its supports)."""
        for _ in range(20):
            mujoco.mj_forward(m, d)
            pen = min([d.contact[i].dist for i in range(d.ncon)] + [0.0])
            if pen >= -1e-5:
                return
            d.qpos[self.adr["root_z"]] += -pen + 0.0005

    # ---- sensors and commands -------------------------------------------------------------

    def _pad_forces(self, m, d):
        f = {"front": 0.0, "rear": 0.0}
        inv = {v: k for k, v in self.pads.items()}
        for i in range(d.ncon):
            con = d.contact[i]
            for g in (con.geom1, con.geom2):
                if g in inv:
                    mujoco.mj_contactForce(m, d, i, self.force)
                    f[inv[g]] += abs(self.force[0]) / self.weight
        return f

    def extra_sensors(self, m, d):
        if not hasattr(self, "pads"):  # handshake before reset
            return [("gun", [0.0]), ("blocks", [0.0, 0.0])]
        f = self._pad_forces(m, d)
        return [("gun", [max(0.0, d.time - T_GUN)]), ("blocks", [f["front"], f["rear"]])]

    def on_command(self, m, d, cmd):
        if cmd.startswith("kf:"):
            _, ev, side = cmd.split(":")
            self.kf_target = (ev, side)

    # ---- recording, rules, falls ----------------------------------------------------------

    def before_step(self, m, d):
        t = d.time
        lc = rc = False
        hand = False
        grf = 0.0
        fpad = {"front": 0.0, "rear": 0.0}
        inv = {v: k for k, v in self.pads.items()}
        for i in range(d.ncon):
            con = d.contact[i]
            g1, g2 = con.geom1, con.geom2
            if g1 in inv or g2 in inv:
                other = g2 if g1 in inv else g1
                if other in self.l_geoms or other in self.r_geoms:
                    mujoco.mj_contactForce(m, d, i, self.force)
                    fpad[inv[g1 if g1 in inv else g2]] += abs(self.force[0]) / self.weight
                continue
            if g1 != self.floor and g2 != self.floor:
                continue
            other = g2 if g1 == self.floor else g1
            if other in self.l_geoms or other in self.r_geoms:
                mujoco.mj_contactForce(m, d, i, self.force)
                grf += abs(self.force[0])
                if other in self.l_geoms:
                    lc = True
                else:
                    rc = True
            elif other in self.hand_geoms and self.hands_down:
                hand = True
            elif m.geom_bodyid[other] != 0:
                if not self.bad_contact:
                    self.fall_why = f"{m.geom(other).name} touched the track"
                self.bad_contact = True
        # the hands: on the track until they first leave it after the gun
        if self.hands_down and not hand:
            if self.hands_off_since is None:
                self.hands_off_since = t
            if t - self.hands_off_since > 0.02 and t >= T_SET:
                self.hands_down = False
                if t < T_GUN + REACTION_MIN:
                    self._false(t, "hand left the track")
        elif hand:
            self.hands_off_since = None
        # in the set a foot must stay still (within 3 cm of where it was at
        # T_SET, as the pelvis: a lightly loaded rear foot may carry no force at
        # moments, and MuJoCo's soft contacts let it creep slowly down its
        # inclined pad);
        # after the gun it has left its pad after 20 ms without force (the
        # block times)
        for k in ("front", "rear"):
            if T_SET <= t < T_GUN + REACTION_MIN:
                fx = d.xpos[self.pad_feet[k]].copy()
                if self.pad_gap[k] is None:
                    self.pad_gap[k] = fx
                elif np.linalg.norm(fx - self.pad_gap[k]) > 0.03:
                    self._false(t, f"{k} foot moved")
            if t < T_GUN or self.pad_off[k] is not None:
                continue
            if fpad[k] >= 0.005:
                self.pad_free[k] = None
            else:
                if self.pad_free[k] is None:
                    self.pad_free[k] = t
                    com = d.subtree_com[self.pelvis]
                    v = d.subtree_linvel[self.pelvis]
                    a = self.kp.angles(d, FRONT)
                    self.exit_state[k] = (float(com[2]), float(v[0]), float(v[2]), a["trunk"], a["sw_thigh"])
                if t - self.pad_free[k] >= 0.02:
                    self.pad_off[k] = self.pad_free[k]
        px = float(d.xpos[self.pelvis][0])
        if T_SET <= t:
            if self.pelvis_set is None:
                self.pelvis_set = px
            if t < T_GUN + REACTION_MIN and abs(px - self.pelvis_set) > 0.03:
                self._false(t, "pelvis moved in the set")
            ftot = fpad["front"] + fpad["rear"]
            if T_GUN - 0.2 <= t < T_GUN:
                self.base_f.append(ftot)
            elif t >= T_GUN and self.onset is None:
                base = float(np.mean(self.base_f)) if self.base_f else ftot
                if abs(ftot - base) > 0.2:
                    self.dev_since = t if self.dev_since is None else self.dev_since
                    if t - self.dev_since >= 0.01:
                        self.onset = self.dev_since
                        if self.onset < T_GUN + REACTION_MIN:
                            self._false(t, "block force onset before 0.100 s")
                else:
                    self.dev_since = None
        # run.py's record (its metrics read it), then ours
        tu = d.xmat[self.torso].reshape(3, 3)[:, 2]
        pitch = math.atan2(tu[0], tu[2])
        act = d.act[m.actuator_actadr[0]:] if m.na else d.ctrl
        pu = d.xmat[self.pelvis].reshape(3, 3)[:, 2]
        com_x = float(d.subtree_com[self.pelvis][0])
        feet_x = (float(d.geom_xpos[self.l_foot][0]), float(d.geom_xpos[self.r_foot][0]))
        legs = []
        for h, k in zip(self.hips, self.knees):
            v = d.xpos[k] - d.xpos[h]
            legs.append((math.atan2(v[0], -v[2]), float(d.xpos[k][2])))
        self.rec.append((t, px, float(d.xpos[self.pelvis][2]), lc, rc, pitch, float(np.mean(np.square(act))),
                         grf / self.weight, legs[0][0], legs[1][0], legs[0][1], legs[1][1],
                         math.atan2(pu[0], pu[2]), com_x, feet_x[0], feet_x[1]))
        self.srec.append((t, float(d.site_xpos[self.chest][0]) - self.line_x, px, float(d.xpos[self.pelvis][2]),
                          lc, rc, fpad["front"], fpad["rear"]))
        if not self.qrec or t - self.qrec[-1][0] >= 0.0039:
            self.qrec.append((t, d.qpos.copy()))

    def _false(self, t, why):
        if self.flying:  # development flying start: no set position, no start rules
            return
        if self.false is None:
            self.false = (round(t, 4), why)

    def done(self, m, d):
        tu = d.xmat[self.torso].reshape(3, 3)[:, 2]
        pitch = abs(math.atan2(tu[0], tu[2]))
        z = float(d.xpos[self.pelvis][2])
        start = (float(d.site_xpos[self.chest][0]) - self.line_x < 10.0) and d.time < T_GUN + 4.0
        zmin, pmax = (0.35, 2.3) if start else (self.fall_height, 1.1)
        if self.bad_contact or z < zmin or pitch > pmax:
            if self.fall_t is None:
                self.fall_t = d.time
                if not self.bad_contact:
                    self.fall_why = f"pelvis {z:.2f} m" if z < zmin else f"torso pitch {pitch:.2f} rad"
            return True
        return False

    # ---- metrics ----------------------------------------------------------------------------

    def metrics(self, m, d, log):
        out = super().metrics(m, d, log)
        if len(self.srec) < 10:
            return out
        r = np.array([row[:4] for row in self.srec], float)
        t, cx = r[:, 0], r[:, 1]
        lc = np.array([row[4] for row in self.srec], bool)
        rc = np.array([row[5] for row in self.srec], bool)
        ex = self.exit_state.get("front") if self.pad_off["front"] is not None else None
        out["exit_z"], out["exit_vx"], out["exit_vz"], out["exit_trunk"], out["exit_thigh"] = (
            (round(ex[0], 3), round(ex[1], 3), round(ex[2], 3), round(ex[3], 1), round(ex[4], 1)) if ex
            else (None, None, None, None, None))
        out["fall_why"] = self.fall_why
        out["fall_at"] = round(self.fall_t - T_GUN, 3) if self.fall_t is not None else None
        out["false_start"] = self.false is not None
        out["false_reason"] = self.false[1] if self.false else ""
        out["reaction"] = round(self.onset - T_GUN, 3) if self.onset is not None else None
        for k, key in (("rear", "rear_block_time"), ("front", "block_time")):
            out[key] = round(self.pad_off[k] - T_GUN, 3) if self.pad_off[k] is not None else None

        def cross(dist):
            k = np.nonzero(cx >= dist)[0]
            if not len(k) or k[0] == 0:
                return None
            i = k[0]
            return float(np.interp(dist, [cx[i - 1], cx[i]], [t[i - 1], t[i]]))
        splits = {}
        for dist in range(10, 101, 10):
            tc = cross(float(dist))
            splits[dist] = tc
            out[f"t{dist}"] = round(tc - T_GUN, 3) if tc is not None else None
        tf = cross(self.distance)
        out["t_finish"] = round(tf - T_GUN, 3) if tf is not None else None
        out["fell_race"] = bool(self.fall_t is not None and (tf is None or self.fall_t < tf))
        prev = T_GUN
        vs = []
        for dist in range(10, 101, 10):
            if splits[dist] is None:
                break
            v = 10.0 / (splits[dist] - prev)
            out[f"v{dist}"] = round(v, 3)
            vs.append(v)
            prev = splits[dist]
        out["peak_v"] = round(max(vs), 3) if vs else 0.0
        # the hurdles' first-hurdle distance (13.72 m) and 30 m: the split and
        # the chest's speed over the 2 m before the line
        for dist, key in ((13.72, "13_72"), (30.0, "30")):
            a, b = cross(dist - 2.0), cross(dist)
            if key != "30":
                out["t" + key] = round(b - T_GUN, 3) if b is not None else None
            out["v_at" + key] = round(2.0 / (b - a), 3) if a is not None and b is not None else None
        # steps on the track (touchdowns after each foot left its pad), with contact intervals
        left = {s: (self.pad_off["front" if s == FRONT else "rear"] or 0.0) for s in "lr"}
        iv = {"l": [(a, b) for a, b in _intervals(lc, t) if a >= left["l"]],
              "r": [(a, b) for a, b in _intervals(rc, t) if a >= left["r"]]}
        tds = sorted([(a, s) for s, ivs in iv.items() for a, _ in ivs])
        t_end = tf if tf is not None else t[-1]
        out["steps"] = sum(1 for a, _ in tds if a <= t_end)
        first = sorted([(a, b, s) for s, ivs in iv.items() for a, b in ivs])[:3]
        for k, (a, b, s) in enumerate(first):
            out[f"s{k + 1}_contact"] = round(b - a, 3)
            if k + 1 < len(first):
                out[f"s{k + 1}_flight"] = round(first[k + 1][0] - b, 3)
        # the max-velocity window
        w0 = cross(self.form_from) if self.form_from > 0 else float(t[0])
        if w0 is not None and t_end > w0 + 0.5:
            span = t_end - w0
            out["v_maxv"] = round((float(np.interp(t_end, t, cx)) - float(np.interp(w0, t, cx))) / span, 3)
            wt = [(a, b, s) for s, ivs in iv.items() for a, b in ivs if a >= w0 and b <= t_end]
            if wt:
                out["contact_maxv"] = round(float(np.mean([b - a for a, b, _ in wt])), 3)
                out["step_freq_maxv"] = round(len(wt) / span, 3)
                out["step_len_maxv"] = round(out["v_maxv"] / out["step_freq_maxv"], 3)
            air = ~lc & ~rc
            fl = [b - a for a, b in _intervals(air, t, bridge=0.0, min_len=0.01) if a >= w0 and b <= t_end]
            out["flight_maxv"] = round(float(np.mean(fl)), 3) if fl else 0.0
        else:
            out["v_maxv"] = 0.0
        out["fast"] = bool(out["v_maxv"] >= FORM_SPEED_FLOOR)
        # practice: the chest's distance at `horizon` s after the gun (or when it fell);
        # a flying start (development) counts from t = 0
        t0p = 0.0 if self.flying else T_GUN
        th = t0p + self.horizon
        out["dist_h"] = round(float(np.interp(min(th, t[-1]), t, cx)), 3)
        out["up_h"] = bool(t[-1] >= th - 0.01 and (self.fall_t is None or self.fall_t >= th))
        tu = min(th, self.fall_t if self.fall_t is not None else t[-1])
        out["t_up"] = round(max(0.0, tu - t0p), 3)
        w = (t >= t0p) & (t <= tu)
        out["z_mean_h"] = round(float(np.mean(r[w, 3])), 3) if np.any(w) else 0.0
        ev = self.gait_events(iv, t_end)
        form, per = self.form_error(m, ev, [e for e in ev if w0 is not None and e[0] >= w0 and e[0] <= t_end],
                                    {"td": "maxv_td", "ms": "maxv_ms", "to": "maxv_to", "mkl": "maxv_mkl"})
        out["form_err"] = form
        out["form_events"] = per
        out["form_arms"], _ = self.form_error(m, ev, [e for e in ev if w0 is not None and w0 <= e[0] <= t_end],
                                              {"td": "maxv_td", "ms": "maxv_ms", "to": "maxv_to", "mkl": "maxv_mkl"},
                                              arms=True)
        acc = [e for e in ev if e[3] < 2 and e[1] in ("td", "to")]
        out["acc_form"], _ = self.form_error(m, ev, acc, None)
        self.events = ev
        return out

    def gait_events(self, iv, t_end):
        """[(time, kind, stance side, step index)] for every touchdown, mid-stance,
        toe-off and max knee lift on the track (step index 0 = first touchdown)."""
        qt = np.array([q[0] for q in self.qrec])
        out = []
        steps = sorted([(a, b, s) for s, ivs in iv.items() for a, b in ivs])
        for k, (a, b, s) in enumerate(steps):
            if a > t_end:
                break
            out.append((a, "td", s, k))
            out.append(((a + b) / 2, "ms", s, k))
            out.append((b, "to", s, k))
            # max knee lift of this leg's following swing (to its next touchdown)
            nxt = [a2 for a2, _, s2 in steps if s2 == s and a2 > b]
            if nxt:
                w = (qt >= b) & (qt <= nxt[0])
                if np.any(w):
                    idx = np.nonzero(w)[0]
                    other = "r" if s == "l" else "l"
                    th = [self._thigh(self.qrec[i][1], s) for i in idx]
                    out.append((float(qt[idx[int(np.argmax(th))]]), "mkl", other, k))
        return sorted(out)

    def _thigh(self, qpos, side):
        self._kd.qpos[:] = qpos
        mujoco.mj_kinematics(self._m, self._kd)
        p = self.kp.points(self._kd, side)
        return _ang_from_down(p["knee"] - p["hip"])

    def angles_at(self, tq, st):
        qt = np.array([q[0] for q in self.qrec])
        i = int(np.clip(np.searchsorted(qt, tq), 0, len(qt) - 1))
        self._kd.qpos[:] = self.qrec[i][1]
        mujoco.mj_kinematics(self._m, self._kd)
        return self.kp.angles(self._kd, st)

    def form_error(self, m, ev, chosen, names, arms=False):
        """RMS (deg) over the chosen events and the trunk and leg roles (arms:
        the video's arm angles instead); names maps an event kind to the
        reference event (None: steps 1-2 by index)."""
        if not chosen:
            return 60.0, {}
        ref = self.reference()
        errs, per = [], {}
        for tq, kind, st, k in chosen:
            ev_name = names[kind] if names else f"s{k + 1}_{kind}"
            if ev_name not in ref.mean:
                continue
            a = self.angles_at(tq, st)
            want = ref.video_arms.get(ev_name, {}) if arms else ref.mean[ev_name]
            e = [a[r] - want[r] for r in (ARM_ROLES if arms else LEG_ROLES) if r in want]
            if not e:
                continue
            errs.extend(e)
            per.setdefault(ev_name, []).append(float(np.sqrt(np.mean(np.square(e)))))
        if not errs:
            return 60.0, {}
        return round(float(np.sqrt(np.mean(np.square(errs)))), 2), {k: round(float(np.mean(v)), 2) for k, v in per.items()}

    # ---- presentation ------------------------------------------------------------------------

    # practice (search.py / practice.py; the arena trials use the metrics)
    horizon = 2.5           # s after the gun
    fall_cost = 5.0         # m
    up_w = 2.0              # m per s upright after the gun (until the horizon)
    exit_w = 0.0            # > 0: score the block exit state instead (plus exit_w per s upright)
    ex_vz_w, ex_z_w = 3.0, 10.0   # the exit score's weights on vertical speed (per m/s, capped at 0.4) and COM height (per m)
    ex_trunk, ex_thigh = 50.0, 40.0   # ... and its trunk (at most) and rear-thigh (at least) targets, deg
    z_w = 0.0               # per m of mean pelvis height x s upright (a body that stays tall)
    form_w = 0.0            # m per degree of form_err (a form-weighted stage)
    form_from = FORM_FROM   # m: the max-velocity window's start (practice from a flying start: 0 = the whole run)
    acc_w = 0.0             # m per degree of acc_form

    def score(self, metrics):
        """Practice objective: the chest's distance at `horizon` s after the gun
        (m) plus up_w per second upright after the gun (so a later fall beats
        an early one); a fall before the horizon costs fall_cost more, a false
        start scores -50; optional form terms (form_w, acc_w per degree)."""
        if "dist_h" not in metrics:
            return -100.0
        if metrics.get("false_start"):
            return -50.0
        if self.exit_w > 0.0:
            # block-exit shaping: forward speed, no sinking, a raised trunk,
            # a high COM as the front foot leaves its pad
            # toward Bolt's exit (block_exit: trunk 46 deg, rear thigh +49 deg,
            # ~3.3 m/s scaled, rising): the swing thigh and the trunk count per 10 deg
            if metrics.get("exit_vx") is None:
                return -20.0
            return (metrics["exit_vx"] + self.ex_vz_w * min(metrics["exit_vz"], 0.4)
                    + self.ex_z_w * (metrics["exit_z"] - 0.62)
                    - 0.1 * max(0.0, metrics["exit_trunk"] - self.ex_trunk)
                    - 0.1 * max(0.0, self.ex_thigh - metrics["exit_thigh"])
                    + self.exit_w * metrics.get("t_up", 0.0))
        s = metrics["dist_h"] + self.up_w * metrics.get("t_up", 0.0)
        s += self.z_w * metrics.get("z_mean_h", 0.0) * metrics.get("t_up", 0.0)
        if not metrics.get("up_h"):
            s -= self.fall_cost
        s -= self.form_w * metrics.get("form_err", 60.0) + self.acc_w * metrics.get("acc_form", 60.0)
        return s

    GHOST_RGBA = (0.25, 0.55, 1.0, 0.33)

    def ghost_pose(self, sim):
        self.hud_label = sim.label
        if not self.ghost or self.kf_target is None:
            return None
        ev, side = self.kf_target
        if ev not in self.reference().mean:
            return None
        q = model_qpos(sim.m, sim.d.qpos, self.reference().model(ev), side, self.adr)
        return q, self.GHOST_RGBA

    def camera(self, m, d, cam):
        px = float(d.body("pelvis").xpos[0])
        self.cam_x = px if self.cam_x is None else self.cam_x + 0.15 * (px - self.cam_x)
        # close on the blocks, pulling back over the first second after the gun
        k = float(np.clip((d.time - T_GUN) / 1.0, 0.0, 1.0))
        cam.lookat[:] = [self.cam_x + 0.3 - 0.2 * (1 - k), 0.0, 0.75 - 0.2 * (1 - k)]
        cam.distance = 4.2 - 1.6 * (1 - k)
        cam.azimuth = 90
        cam.elevation = -6

    def hud_text(self, m, d):
        dist = float(d.site_xpos[self.chest][0]) - self.line_x
        tg = d.time - T_GUN
        k = max(0, len(self.srec) - 500)
        v = (self.srec[-1][1] - self.srec[k][1]) / max(self.srec[-1][0] - self.srec[k][0], 1e-6) if self.srec else 0.0
        clock = f"{tg:5.2f} s after the gun" if tg >= 0 else f"set ({-tg:4.2f} s to the gun)"
        ghost = f"   ghost: Bolt {self.kf_target[0]}" if self.kf_target else ""
        return f"{clock}   {dist:5.1f} m   {v:4.2f} m/s{ghost}"

    def title(self):
        return f"robolab: sprint from blocks ({'v2' if self.body == 'v2' else 'v3'} anatomy), Bolt keyframes"


def _intervals(on, t, bridge=0.02, min_len=0.03):
    """(start, end) of the runs where `on` holds, merged across gaps < bridge."""
    out = []
    k, n = 0, len(on)
    while k < n:
        if on[k]:
            a = k
            while k < n and on[k]:
                k += 1
            s, e = t[a], t[min(k, n - 1)]
            if out and s - out[-1][1] < bridge:
                out[-1] = (out[-1][0], e)
            else:
                out.append((s, e))
        k += 1
    return [(a, b) for a, b in out if b - a >= min_len]


TASK = SprintBlocksTask


# ---- reference exports ------------------------------------------------------------------------

REF_W = os.path.join(ROOT, "lib", "robolab", "skills", "sprint_ref.w")
EDITOR_DIR = os.path.join(ROOT, "playground", "refs", "bolt", "editor")
# phase (% of the stride from the stance leg's touchdown) of the max-velocity
# events: Bolt's contact is 0.411 of a step in the Daegu clip (the max knee
# lift's phase is not given)
MAXV_PHASE = {"maxv_td": 0.0, "maxv_ms": 10.3, "maxv_to": 20.6}


def write_ref_w(ref, path=REF_W):
    """lib/robolab/skills/sprint_ref.w: the skill's built-in Bolt table (model
    keyframes in degrees, MODEL_KEYS order, st = the stance / front leg)."""
    src = "provisional literature values" if ref.provisional else os.path.relpath(ref.path, ROOT)
    lines = ["# GENERATED by playground/tasks/sprint_blocks.py refw from " + src + ": do not edit.",
             "# Bolt's keyframes as model postures (degrees): per event the MODEL_KEYS",
             "#   " + " ".join(MODEL_KEYS),
             "# with st = the stance leg (the front leg in the blocks) and the arm on its side;",
             "# hip = thigh relative to the pelvis, spine = torso relative to the pelvis,",
             "# pelvis = world pitch (the video's hip->shoulder trunk line split as SPINE in",
             "# the task). SprintBlocksSkill reads params ref_<event>_<key> over these.",
             "", "+ SprintRef", "  -> new", "    @n = " + str(len(MODEL_KEYS)), "",
             "  -> keys", "    [" + ", ".join(f'"{k}"' for k in MODEL_KEYS) + "]", "",
             "  -> events", "    [" + ", ".join(f'"{e}"' for e in EVENTS) + "]", "",
             "  -> has?(ev)", "    events.include?(ev)", "",
             "  -> deg(ev)"]
    for ev in EVENTS:
        kf = ref.model(ev)
        vals = ", ".join(f"~{kf[k]:.2f}" for k in MODEL_KEYS)
        lines.append(f'    return [{vals}] if ev == "{ev}"')
    lines.append("    nil")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    return path


def write_editor(ref, achieved=None, out_dir=EDITOR_DIR, phases=MAXV_PHASE):
    """playground/refs/bolt/editor/<event>.json in the keyframe editor's schema."""
    os.makedirs(out_dir, exist_ok=True)
    paths = []
    for order, ev in enumerate(EVENTS):
        kf = ref.model(ev)
        doc = {"set": "bolt_sprint", "set_label": "Bolt sprint from blocks", "set_order": 1, "cycle": False,
               "event": ev, "label": LABELS[ev], "order": order + 1, "reference": kf, "angles": dict(kf),
               "source": ref.src.get(ev, "")}
        if phases and ev in phases:
            doc["phase_pct"] = phases[ev]
        if achieved and ev in achieved:
            doc["achieved"] = achieved[ev]
        p = os.path.join(out_dir, f"{ev}.json")
        with open(p, "w") as f:
            json.dump(doc, f, indent=1)
        paths.append(p)
    return paths


def model_angles_of(m, d, st, adr):
    """Our body's posture in the editor's model keys (deg), st = stance side."""
    sw = "r" if st == "l" else "l"
    q = d.qpos
    out = {"spine": q[adr["spine_flex"]] * DEG, "pelvis": q[adr["root_pitch"]] * DEG}
    for role, s in (("st", st), ("sw", sw)):
        for j, key in (("hip_flex", "hip"), ("knee", "knee"), ("ankle", "ankle"), ("toe", "toe"),
                       ("shoulder_flex", "shoulder"), ("elbow", "elbow")):
            out[f"{role}_{key}"] = q[adr[f"{s}_{j}"]] * DEG
    return {k: round(float(out[k]), 2) for k in MODEL_KEYS}


# ---- evaluation and rendering -------------------------------------------------------------------

SUMMARY = ["time", "fell", "fell_race", "fall_why", "fall_at", "exit_z", "exit_vx", "exit_vz", "exit_trunk", "exit_thigh", "false_start", "false_reason", "reaction", "rear_block_time", "block_time",
           "t10", "t13_72", "v_at13_72", "t20", "t30", "v_at30", "t40", "t50", "t60", "t70", "t80", "t90", "t100", "t_finish", "v10", "v20", "v30",
           "v40", "v50", "v60", "v70", "v80", "v90", "v100", "peak_v", "v_maxv", "fast", "steps", "s1_contact",
           "s1_flight", "s2_contact", "s2_flight", "s3_contact", "contact_maxv", "flight_maxv", "step_freq_maxv",
           "step_len_maxv", "form_err", "form_events", "form_arms", "acc_form", "effort"]


def run_once(params, seconds=None, seed=None, controller=None, recorder=None, task_cls=None):
    from bridge import Sim
    task = (task_cls or SprintBlocksTask)()
    task.seed = seed
    sim = Sim(task, params=params, controller=controller)
    res = sim.run(seconds or task.seconds, recorder=recorder)
    return task, sim, res


def summary(res):
    out = {}
    for k in SUMMARY:
        v = res.get(k)
        out[k] = float(v) if isinstance(v, (np.floating, np.integer)) else v
    return out


def event_times(task):
    """One representative time per reference event: the block events from the
    pads and the controller's keyframe emits; the steps and the max-velocity
    cycle from the gait events (the last full cycle before the finish)."""
    out = {}
    if task.pad_off["rear"]:
        out["rear_exit"] = (task.pad_off["rear"], FRONT)
    if task.pad_off["front"]:
        out["block_exit"] = (task.pad_off["front"], FRONT)
    out["set"] = (T_GUN - 0.02, FRONT)
    ev = getattr(task, "events", [])
    for tq, kind, st, k in ev:
        if k < 3 and kind in ("td", "to"):
            out.setdefault(f"s{k + 1}_{kind}", (tq, st))
    done = [e for e in ev if e[0] <= (task.t_end if hasattr(task, "t_end") else 1e9)]
    for kind in ("td", "ms", "to", "mkl"):
        c = [e for e in done if e[1] == kind]
        if c:
            tq, _, st, _ = c[-3] if len(c) >= 3 else c[-1]
            out[f"maxv_{kind}"] = (tq, st)
    drive = [e for e in ev if 5 <= e[3] <= 8 and e[1] in ("td", "to")]
    for kind in ("td", "to"):
        c = [e for e in drive if e[1] == kind]
        if c:
            out[f"drive_{kind}"] = (c[0][0], c[0][2])
    return out


def body_points(task, d, st):
    """Our body's keypoints in the sagittal plane (x, z), stance side = near."""
    sw = "r" if st == "l" else "l"
    out = {}
    for side, s in (("near", st), ("far", sw)):
        p = task.kp.points(d, s)
        out[side] = {k: (float(v[0]), float(v[2])) for k, v in p.items()}
    tb = task._m.body("torso").id
    head = d.xpos[tb] + d.xmat[tb].reshape(3, 3) @ np.array([0, 0, 0.58])
    out["head"] = (float(head[0]), float(head[2]))
    return out


def draw_stick(dr, pts, box, color, scale=125.0):
    """A stick figure from sagittal keypoints into box (x0, y0, x1, y1),
    pelvis-centred, ground at the box's bottom; far limbs drawn thinner."""
    x0, y0, x1, y1 = box
    cx = (pts["near"]["hip"][0])
    ground = y1 - 8

    def P(q):
        return (x0 + (x1 - x0) / 2 + (q[0] - cx) * scale, ground - q[1] * scale)
    chain = [("shoulder", "elbow"), ("elbow", "wrist"), ("hip", "knee"), ("knee", "ankle"), ("ankle", "heel"),
             ("heel", "toe"), ("ankle", "toe")]
    for side, w, col in (("far", 3, tuple(int(c * 0.55 + 255 * 0.45) for c in color)), ("near", 5, color)):
        p = pts[side]
        for a, b in chain:
            dr.line([P(p[a]), P(p[b])], fill=col, width=w)
    n = pts["near"]
    dr.line([P(n["hip"]), P(n["shoulder"])], fill=(20, 20, 20), width=6)
    hx, hy = P(pts["head"])
    dr.ellipse([hx - 13, hy - 13, hx + 13, hy + 13], outline=(20, 20, 20), width=3)
    dr.line([(x0 + 6, ground), (x1 - 6, ground)], fill=(150, 150, 150), width=1)


def keyframe_sheet(task, sim, res, path, width=300, height=330):
    """Per reference event: our runner rendered at that event with Bolt's
    keyframe ghosted in blue (top), Bolt's keyframe as a stick figure (his
    video angles on our segment lengths; no video pixels) and ours as one
    (middle), and the video-convention angles Bolt | ours (bottom)."""
    from PIL import Image, ImageDraw, ImageFont
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 12)
        big = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 15)
    except OSError:
        font = big = ImageFont.load_default()
    m = sim.m
    d = mujoco.MjData(m)
    times = event_times(task)
    evs = [e for e in EVENTS if e in times]
    ref = task.reference()
    qt = np.array([q[0] for q in task.qrec])
    ren = mujoco.Renderer(m, height, width)
    cam = mujoco.MjvCamera()
    cam.type = mujoco.mjtCamera.mjCAMERA_FREE
    opt, pert = mujoco.MjvOption(), mujoco.MjvPerturb()
    gd = mujoco.MjData(m)
    stick_h, text_h, head_h = 250, 190, 40
    sheet = Image.new("RGB", (len(evs) * width, head_h + height + stick_h + text_h), (250, 250, 252))
    dr = ImageDraw.Draw(sheet)
    dr.text((10, 10), "robolab sprint from blocks: our runner (Bolt's keyframe ghosted in blue) | Bolt's keyframe "
            "(blue, his video angles on our segments) vs ours (red) | angles in the video's conventions, Bolt | ours (deg)",
            font=big, fill=(20, 24, 30))
    achieved = {}
    for col, ev in enumerate(evs):
        tq, st = times[ev]
        i = int(np.clip(np.searchsorted(qt, tq), 0, len(qt) - 1))
        d.qpos[:] = task.qrec[i][1]
        mujoco.mj_forward(m, d)
        ach = task.kp.angles(d, st)
        achieved[ev] = model_angles_of(m, d, st, task.adr)
        gq = model_qpos(m, d.qpos, ref.model(ev), st, task.adr)
        cam.lookat[:] = [float(d.body("pelvis").xpos[0]) + 0.1, 0.0, 0.6]
        cam.distance, cam.azimuth, cam.elevation = 2.5, 90, -4
        ren.update_scene(d, cam)
        gd.qpos[:] = gq
        mujoco.mj_forward(m, gd)
        scn = ren.scene
        n0 = scn.ngeom
        mujoco.mjv_addGeoms(m, gd, opt, pert, int(mujoco.mjtCatBit.mjCAT_DYNAMIC), scn)
        for k in range(n0, scn.ngeom):
            scn.geoms[k].rgba[:] = SprintBlocksTask.GHOST_RGBA
        x = col * width
        sheet.paste(Image.fromarray(ren.render()), (x, head_h))
        dr.text((x + 6, head_h + 4), f"{ev}  t={tq - T_GUN:+.2f} s", font=big, fill=(20, 24, 30))
        # stick figures: Bolt (ghost pose) and ours, both pelvis-centred
        y = head_h + height
        # the ghost pose's ground: lift it so its lowest foot point is at 0
        gp = body_points(task, gd, st)
        low = min(v[1] for side in ("near", "far") for v in gp[side].values())
        for side in ("near", "far"):
            gp[side] = {k: (v[0], v[1] - low) for k, v in gp[side].items()}
        gp["head"] = (gp["head"][0], gp["head"][1] - low)
        op = body_points(task, d, st)
        draw_stick(dr, gp, (x, y, x + width // 2, y + stick_h), (40, 90, 200))
        draw_stick(dr, op, (x + width // 2, y, x + width, y + stick_h), (200, 60, 50))
        dr.text((x + 6, y + 2), "Bolt", font=font, fill=(40, 90, 200))
        dr.text((x + width // 2 + 6, y + 2), "ours", font=font, fill=(200, 60, 50))
        want = ref.mean[ev]
        lines = ["            Bolt | ours"]
        for r in ROLES:
            if r in want:
                mark = "" if r in LEG_ROLES else " *"
                lines.append(f"{r.replace('_', ' '):<12}{want[r]:5.0f} |{ach[r]:5.0f}{mark}")
        ty = y + stick_h + 4
        for k, ln in enumerate(lines):
            dr.text((x + 8, ty + 14 * k), ln, font=font, fill=(30, 34, 42))
    dr.text((10, sheet.height - 16), "* arms: literature swing (the video's arm angles are low-confidence), not scored",
            font=font, fill=(90, 90, 90))
    sheet.save(path)
    return path, achieved


def main():
    import argparse
    import time
    ap = argparse.ArgumentParser(description="Evaluate / render the sprint from blocks")
    ap.add_argument("cmd", choices=["eval", "render", "editor", "refw"])
    ap.add_argument("--params", default=os.path.join(ROOT, "params", "sprint_blocks.txt"))
    ap.add_argument("--seconds", type=float)
    ap.add_argument("--seed", type=int)
    ap.add_argument("--controller")
    ap.add_argument("--json")
    ap.add_argument("--video")
    ap.add_argument("--gif")
    ap.add_argument("--keyframes")
    ap.add_argument("--achieved", action="store_true", help="editor: run the params and add our runner's angles")
    ap.add_argument("--task", default="sprint_blocks", help="task module (e.g. sprint_blocks_athlete)")
    a = ap.parse_args()
    import importlib
    task_cls = importlib.import_module(f"tasks.{a.task}").TASK
    if a.cmd == "refw":
        print("wrote", write_ref_w(BoltRef()))
        return
    from practice import read_params
    params = read_params(a.params) if a.params and os.path.exists(a.params) else {}
    if a.cmd == "editor" and not a.achieved:
        print("wrote", len(write_editor(BoltRef())), "files to", EDITOR_DIR)
        return
    rec = None
    t0 = time.time()
    if a.cmd == "render" or a.cmd == "editor":
        from bridge import Sim
        from render import Recorder
        task = task_cls()
        task.seed = a.seed
        sim = Sim(task, params=params, controller=a.controller)
        rec = Recorder(sim, fps=int(os.environ.get("SPRINT_FPS", "60"))) if a.video or a.gif else None
        res = sim.run(a.seconds or task.seconds, recorder=rec)
    else:
        task, sim, res = run_once(params, a.seconds, a.seed, a.controller, task_cls=task_cls)
    out = summary(res)
    out["wall_s"] = round(time.time() - t0, 1)
    print(json.dumps(out))
    if a.json:
        with open(a.json, "w") as f:
            json.dump({"params": a.params, "seed": a.seed, "reference": BoltRef().path, **out}, f, indent=1)
    if rec is not None and a.video:
        rec.write_mp4(a.video)
    if rec is not None and a.gif:
        from tasks.run_natural import write_gif
        n = len(rec.frames)
        mb = write_gif(rec.frames, a.gif, rec.fps, 0, min(n, int(7.0 * rec.fps)))
        print("wrote", a.gif, f"{mb:.2f} MB")
    if a.keyframes or a.cmd == "editor":
        path, achieved = keyframe_sheet(task, sim, res, a.keyframes or os.path.join(ROOT, "out", "sprint_blocks_keyframes.png"))
        print("wrote", path)
        if a.cmd == "editor":
            print("wrote", write_editor(task.reference(), achieved))


if __name__ == "__main__":
    main()
