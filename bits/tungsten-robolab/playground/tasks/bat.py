"""Bat: a left-handed batter on the pivot body hits pitched baseballs.

The batter stands in the left-handed batter's box: the body faces +x (the
plate), the pitcher is down -y, and a pitch travels +y. The right hand is
the bottom hand and holds the bat rigidly (the bat is a child body of the
right hand, as if the fist never opens); the left, top hand holds it through
an equality `connect` between the left hand's grip site and the bat's
top-hand site. The controller releases the top hand after contact with the
command `grip:l:0` and re-grips with `grip:l:1` (the task only closes the
grip when the hand is within GRIP_CLOSE of the handle, like fingers closing).

The pitcher delivers when the batter signals `ready`, or on a fallback
schedule: a 0.9 s delivery (the ball rises out of the glove, back behind the
head and forward to the release point, visible in the pitcher's hand) that
the batter sees through the `pitch_windup` sensor and times his leg lift
and stride on. Pitches are fired from the release point with a
velocity solved so that the ball (gravity plus quadratic air drag, no spin)
crosses the front of the plate at the pitch's target location.

Body (BatBuilder; BAT_BODY selects it, see below). The default `human` body
is body.py's HumanoidV2Builder, the human-calibrated anatomy (per-joint
muscle speeds matching typical human unloaded joint velocities, human-scale
passive damping, toes, biarticular leg muscles) at strength 1.0. The batter
adds: the pelvis held at a fixed PELVIS_H (0.84 m, an athletic crouch) on
the muscle-driven yaw hinge plus a muscle-driven slide toward the mound
(SHIFT_RANGE, SHIFT_FORCE, SHIFT_SPEED), standing in for the legs'
horizontal push when the batter strides and shifts his weight; shoulder
adduction to -0.8 rad (the shoulder complex's cross-body reach; body.py
stops at -0.3) and wrist deviation -0.35..0.75 rad (radial 20 deg, ulnar 43
deg; body.py +-0.5), both with the joints' calibrated speeds kept (vmax
scales with the range). There is no whole-body balance (pivot root).
BAT_BODY=athlete is the earlier body (base HumanoidBuilder, strength 1.5,
every muscle's vmax 3.0 L0/s, damping 1.5): params/bat.txt and out/bat.*
(flow 0), params/bat_smooth.txt and out/bat_smooth.* (flow 1, the load
flowing into one velocity-continuous swing; see skills/bat.w).
BAT_BODY=v1 is the first version (athlete muscles, 0.90 m, no shift).

Physics honesty: the body and the bat move only by muscles. The task sets
the initial posture in reset(), holds the ball kinematically in the
pitcher's hand between pitches, applies air drag to the ball, and toggles
the top-hand grip constraint on command. Bat-ball contact is resolved by
MuJoCo (0.1 ms steps; contact softness calibrated to a coefficient of
restitution of about 0.5, a wood bat on a baseball).

Sensors (beyond the standard block): what a batter sees and feels.
  ball_pos, ball_vel   the baseball (eyes)
  bat_head_pos/vel     the bat-speed point, 6 in (0.152 m) from the tip
  bat_tip_pos          the barrel end
  bat_knob_pos         the knob
  grip_err             left grip site -> bat top-hand site (m)
  grip_l               1 while the top hand holds the bat (touch)
  bat_contact          bat-ball contact force / body weight (the jolt)
  pitch_no             index of the pitch in flight or next to come
  plate                plate centre x, front edge y (the batter knows the plate)

Commands from the controller: `ready` (deliver the pitch), `grip:l:0|1`,
`swing` (the hips fired: timing marker), `aim:tau:x:z` / `aim_lock:...`
(the batter's predicted crossing, drawn as a yellow disc at the plate).

Metrics per pitch: bat head speed at contact (or at closest approach for a
miss), exit velocity, launch and spray angle, fair/foul, carry (drag-only
flight, so it underestimates a real backspinning ball), impact point on the
bat, miss distance, intercept error (ball to bat-speed point), when the
top hand let go relative to contact, hips-fire-to-contact time, when the
aim correction engaged and locked before contact; the swing's geometry at
contact (attack angle of the bat head, the pitch's vertical approach angle,
the swing plane's tilt from horizontal) and time in the zone (bat head
within 5 cm of the pitch's path); and the stride (leg lift height, stride
length of the front foot toward the mound, plant time relative to the
release, to the swing and to contact, pelvis translation, all measured from
the body); and the swing's smoothness from the plant to contact (per muscle
group, arms and trunk: the commanded contraction speed's peak, its largest
tick-to-tick velocity change `cmd_step_*`, the longest hold below 0.1/s
`cmd_hold_ms_*`, and the same from the plant through the follow and let-go,
`cmd_*_full_*`; per run `hitch` / `hitch_full` = the worst over pitches and
groups of max(step / peak, hold / 100 ms), and `power` = mean sweet-spot bat
speed at contact, 0 for a miss; playground/bat_trace.py prints the per-tick
trace), and `flow` (the arena's bat_flow, see flow_terms): the motion as SEEN,
the MEASURED contraction speed's valleys from the leg lift to contact + 0.8 s
per phase plus the command's holds and steps, and `flow_ok` (every pitch's
bat_flow score at most CLEAN_FLOW: the arena's bat_power_clean guard).
BAT_SEEDED_PITCH=1 makes a rollout's seed pick one pitch of the sweep
grid (the arena's bat_smooth* and bat_power trials); BAT_FRESH_PITCH=1 makes
it draw one from a continuous distribution over the sweep's box (FRESH_*; the
held-out bat_power_fresh trials). With ROBOLAB_PROFILE the athlete body's
muscle speed and pelvis-shift force scale with the profile too. `python
playground/tasks/bat.py --params params/bat.txt` writes the full report
(demo, correction-off ablation, speed/location sweep) to out/bat_metrics.json.
"""

import math
import os
import sys

import mujoco
import numpy as np

_PLAYGROUND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PLAYGROUND not in sys.path:  # run as a script (the evaluation report)
    sys.path.insert(0, _PLAYGROUND)

from body import HumanoidBuilder, HumanoidV2Builder, Muscle  # noqa: E402
from bridge import Task  # noqa: E402

# ---- geometry ---------------------------------------------------------------

# BAT_BODY selects the batter's body:
#   human    (default) body.py's HumanoidV2Builder, the human-calibrated
#            anatomy: per-joint muscle speeds set so each joint's unloaded peak
#            angular velocity is a typical human value, human-scale passive
#            damping, toes and biarticular leg muscles; strength 1.0.
#   athlete  the base HumanoidBuilder with strength 1.5 and every muscle's vmax
#            raised to 3.0 L0/s (body.py's damping 1.5 everywhere): the body
#            behind params/bat.txt and out/bat.* (flow 0) and params/bat_smooth.txt and
#            out/bat_smooth.* (flow 1).
#   v1       the first version: athlete muscles, pivot at 0.90 m, no pelvis
#            shift, 0.7 s windup (out/bat_metrics_v1.json).
BODY = os.environ.get("BAT_BODY", "human")
assert BODY in ("human", "athlete", "v1"), f"BAT_BODY={BODY}: expected human, athlete or v1"
V1 = BODY == "v1"
HUMAN = BODY == "human"
PELVIS_H = 0.90 if V1 else 0.84   # pivot height of the pelvis (hip joints): an athletic
                            # crouch (0.88 x standing hip height), low enough for a 0.3 m stride
# The pelvis translates toward the pitcher on a muscle-driven slide joint
# (+ = toward the mound), standing in for the legs' push on the ground when
# the batter shifts his weight into the stride. Height stays fixed.
SHIFT_RANGE = (-0.12, 0.35)  # m
SHIFT_FORCE = 600.0          # N per muscle before the strength scale (~0.9 body weights; athlete 1.5x -> 900 N)
# Unloaded speed of the shift (human body), calibrated like body.py's V2 joints:
# the weight shift is the back hip's abductors pushing through the leg, and
# their calibrated 10 rad/s over a 0.6-0.9 m lever is 6-9 m/s at the pelvis.
SHIFT_SPEED = 6.0            # m/s
PLATE_X = 0.80              # plate centre, in front of the batter (+x), m
PLATE_FRONT_Y = -0.215      # front edge of the plate (toward the pitcher)
PLATE_HALF = 0.2159         # 17 in wide
RUBBER_Y = PLATE_FRONT_Y - 18.01   # 60 ft 6 in from the rubber to the back point
RELEASE = np.array([PLATE_X + 0.45, RUBBER_Y + 1.75, 1.78])  # RHP, 1.75 m extension
PITCHER_O = np.array([PLATE_X + 0.25, RUBBER_Y + 0.9, 0.25])  # the static pitcher figure's origin

BAT_LEN = 0.86              # 34 in
BAT_MASS = 0.90             # 32 oz
GRIP_S = 0.05               # bottom-hand centre, from the knob
TOP_S = 0.14                # top-hand centre, from the knob
SWEET_S = BAT_LEN - 0.152   # bat-speed point: 6 in from the tip (Statcast convention)

BALL_R = 0.0369
BALL_M = 0.145
RHO_AIR = 1.2
CD = 0.35
DRAG_K = 0.5 * RHO_AIR * CD * math.pi * BALL_R ** 2   # F = -DRAG_K |v| v
GRIP_TILT = -0.35           # bat axis tilted from perpendicular toward the fingers (finger grip)
SHOULDER_ADDUCT = -0.8      # cross-body reach of the shoulder complex (body.py: -0.3)
WRIST_DEV = (-0.35, 0.75)   # radial 20 deg, ulnar 43 deg (body.py: +-0.5)
# Muscle shortening speed (L0/s at which force reaches zero). body.py uses
# MuJoCo's default 1.5 with each joint's range spanning 0.3 L0 of the
# muscle, so a joint's zero-load speed is 5x its range per second. Human
# fibres shorten at about 10 optimal lengths per second over roughly 0.6 of
# an optimal length across a joint's range, i.e. 10-17x the range per
# second; 3.0 (10x) is the batter's fast-twitch swing muscles, disclosed.
MUSCLE_VMAX = None if HUMAN else float(os.environ.get("BAT_VMAX", "3.0"))   # human body: body.py's per-joint calibration instead
GRIP_CLOSE = 0.035
ZONE_R = 0.05               # time in the zone: bat head within this of the pitch's path          # the top hand closes on the handle within this distance
CONTACT_SOLREF = "0.001 0.25"

# (speed m/s at release, crossing offset from plate centre in x (+ = away
# from the batter), crossing height at the front of the plate)
PITCHES = [
    (37.0, 0.00, 0.80),     # 83 mph, middle-middle
    (40.0, -0.14, 1.00),    # 89 mph, up and in
    (34.0, 0.15, 0.62),     # 76 mph, down and away
    (38.5, -0.06, 0.68),    # 86 mph, low, inner half
]

G = 9.81


def mph(v):
    return float(v) * 2.23694


# Smoothness of the commanded contraction vector (the controller's targets,
# corrections included) from the plant (no stride: the release) to contact,
# per muscle group: its peak speed (L2 norm of d(target)/dt, 1/s), the largest
# change of that velocity vector between consecutive control ticks (a velocity
# jump at a chunk boundary shows up here), and the longest hold (ms) below
# SMOOTH_STILL.
ARM_MUSCLES = ("l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_wrist", "r_wrist")
TRUNK_MUSCLES = ("spine", "pelvis_yaw")
SMOOTH_STILL = 0.1
SMOOTH_FULL_AFTER = 0.45   # the full window runs on past contact through the let-go


def cmd_smoothness(t, tg, idx, t0, t1, dt):
    k0, k1 = int(np.searchsorted(t, t0)), int(np.searchsorted(t, t1))
    if k0 < 1 or k1 - k0 < 3:
        return None
    v = np.diff(tg[k0 - 1:k1][:, idx], axis=0) / dt
    sp = np.linalg.norm(v, axis=1)
    dv = np.linalg.norm(np.diff(v, axis=0), axis=1)
    run = best = 0
    for still in sp < SMOOTH_STILL:
        run = run + 1 if still else 0
        best = max(best, run)
    return round(float(sp.max()), 2), round(float(dv.max()), 3), round(1000.0 * best * dt, 0)


# Flow of the whole motion as it is SEEN, leg lift -> finish (the arena's
# bat_flow). The hitch measures above read the command only; a command can
# run without a hold while the body still brakes to a stop (a small load
# command after a hard plant: the legs settle, then the swing fires; a
# follow keyframe the arms slow down at, then speed up again into the
# let-go). Per pitch and per muscle group (legs, trunk, arms, and all of
# them together), on the MEASURED contraction speed (the L2 norm over the
# group of d(c)/dt, smoothed over FLOW_SMOOTH s), each tick from the start
# of the leg lift to contact + FLOW_AFTER is compared with the lesser of the
# group's peaks over the FLOW_WINDOW s before and after it (both inside that
# window; flanks slower than FLOW_REST of the group's peak speed over the
# window, or than FLOW_FLOOR, are rest, not motion, and score no valley: a
# settling wobble at the finish is not a hitch). In each of three phases, lift -> plant, plant -> contact and
# contact -> contact + FLOW_AFTER, the phase's valley is the worst over the
# groups of max(dip, stall / 100 ms), where dip = 1 - the lowest ratio (how
# far the body slows between two movements) and stall = the longest run
# below FLOW_STALL of the flanks (how long it stays stopped). A motion that
# speeds up, turns and slows down only at the finish has no valley; a stop
# and go has one near 1. Plus, on the COMMAND, the hitch terms over the
# same stretch (per group, the longest hold below SMOOTH_STILL in units of
# 100 ms and the largest tick-to-tick velocity step over the group's peak
# command speed; legs from the leg lift to contact, since they rightly stop
# in the finish stance, trunk and arms to contact + SMOOTH_FULL_AFTER or the
# finish, whichever comes first: the finish is where the motion ends).
# flow = valley(lift) + valley(pre-swing) + valley(post-contact) + the
# worst command term; lower is smoother.
LEG_MUSCLES = ("l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle", "l_toe", "r_toe",
               "l_rf", "r_rf", "l_ham", "r_ham", "l_gas", "r_gas", "pelvis_shift")
FLOW_SMOOTH = 0.025
FLOW_STALL = 0.25
FLOW_WINDOW = 0.3
FLOW_FLOOR = 1.0
FLOW_REST = 0.2
FLOW_AFTER = 0.8
# The arena's bat_power_clean guard (metric `flow_ok`): a swing counts as
# hitch-free when its bat_flow score is at most this (the v5 swings score
# 1.7-2.4 per pitch; the old flow-1 swing with its pre-swing stall ~7)
CLEAN_FLOW = 3.0


def _run_ms(mask, dt):
    run = best = 0
    for m in mask:
        run = run + 1 if m else 0
        best = max(best, run)
    return 1000.0 * best * dt


def _valley_ratio(s, ka, kb, kw):
    """Per tick of [ka, kb): speed over the lesser of the flanking peaks."""
    out = np.ones(kb - ka)
    floor = max(FLOW_FLOOR, FLOW_REST * float(s[ka:kb].max()))
    for j in range(ka, kb):
        flank = min(s[max(ka, j - kw):j + 1].max(), s[j:min(kb, j + kw + 1)].max())
        if flank >= floor:
            out[j - ka] = s[j] / flank
    return out


def flow_terms(t, labels, c, tg, groups, r, dt):
    """The flow terms of one pitch (see above), or None without a
    contact/closest-approach time."""
    t1 = r.get("t_contact", r.get("t_closest"))
    ts = r.get("t_windup", r.get("t_release"))
    if t1 is None or ts is None:
        return None
    k = int(np.searchsorted(t, ts))
    while k < len(t) and "hips:leglift" not in labels[k]:
        k += 1
    if k >= len(t) or t[k] >= t1:
        k = int(np.searchsorted(t, r.get("t_plant", r.get("t_release"))))
    ka, kc = max(k, 1), int(np.searchsorted(t, t1))
    kf = min(int(np.searchsorted(t, t1 + SMOOTH_FULL_AFTER)), len(t) - 1)
    kf = next((j for j in range(int(np.searchsorted(t, t1)), kf) if "arms:finish" in labels[j]), kf)
    kb = min(int(np.searchsorted(t, t1 + FLOW_AFTER)), len(t) - 1)
    if kc - ka < 5:
        return None
    kp = int(np.searchsorted(t, r["t_plant"])) if r.get("t_plant") is not None and r["t_plant"] < t1 else ka
    kp = min(max(kp, ka), kc)
    w = max(1, int(round(FLOW_SMOOTH / dt)))
    kw = int(round(FLOW_WINDOW / dt))
    out = {}
    valley = {"lift": 0.0, "pre": 0.0, "post": 0.0}
    every = sorted({i for idx in groups.values() for i in idx})
    for g, idx in list(groups.items()) + [("all", every)]:
        vm = np.linalg.norm(np.diff(c[:, idx], axis=0), axis=1) / dt     # row j: tick j -> j+1
        sm = np.convolve(vm, np.ones(w) / w, mode="same")
        ratio = _valley_ratio(sm, ka, kb, kw)
        for ph, (j0, j1) in (("lift", (ka, kp)), ("pre", (kp, kc)), ("post", (kc, kb))):
            seg = ratio[j0 - ka:j1 - ka]
            if len(seg) == 0:
                continue
            dip = 1.0 - float(seg.min())
            stall = _run_ms(seg < FLOW_STALL, dt)
            out["dip_" + ph] = round(max(out.get("dip_" + ph, 0.0), dip), 3)
            out["stall_ms_" + ph] = round(max(out.get("stall_ms_" + ph, 0.0), stall), 0)
            valley[ph] = max(valley[ph], dip, stall / 100.0)
    cmd = 0.0
    for g, idx in groups.items():
        k1 = kc if g == "legs" else kf
        v = np.diff(tg[ka - 1:k1][:, idx], axis=0) / dt
        sp = np.linalg.norm(v, axis=1)
        dv = np.linalg.norm(np.diff(v, axis=0), axis=1)
        hold = _run_ms(sp < SMOOTH_STILL, dt)
        step = float(dv.max()) / max(float(sp.max()), 1e-6)
        out["cmd_hold_ms_" + g] = round(hold, 0)
        out["cmd_step_" + g] = round(step, 3)
        cmd = max(cmd, hold / 100.0, step)
    out.update({"valley_" + k: round(v, 3) for k, v in valley.items()})
    out["cmd"] = round(cmd, 3)
    out["flow"] = round(sum(valley.values()) + cmd, 4)
    return out


def fly(p, v, dt=0.001, until_y=None, max_t=3.0):
    """Ballistic flight with quadratic drag; returns the trajectory as (t, p, v)."""
    p = np.array(p, float)
    v = np.array(v, float)
    t = 0.0
    out = [(t, p.copy(), v.copy())]
    k = DRAG_K / BALL_M
    while t < max_t:
        def acc(vv):
            return np.array([0.0, 0.0, -G]) - k * np.linalg.norm(vv) * vv
        # RK2 midpoint
        a1 = acc(v)
        vm = v + 0.5 * dt * a1
        pm = p + 0.5 * dt * v
        a2 = acc(vm)
        p = p + dt * vm
        v = v + dt * a2
        t += dt
        del pm
        out.append((t, p.copy(), v.copy()))
        if until_y is not None and p[1] >= until_y:
            break
        if until_y is None and p[2] <= BALL_R:
            break
    return out


def aim(speed, target):
    """Initial velocity from RELEASE, of the given speed, that crosses the
    front of the plate at target (x, z)."""
    d = np.array(target) - RELEASE
    ax = math.atan2(d[0], d[1])
    el = math.atan2(d[2], math.hypot(d[0], d[1]))
    for _ in range(30):
        v = speed * np.array([math.cos(el) * math.sin(ax), math.cos(el) * math.cos(ax), math.sin(el)])
        tr = fly(RELEASE, v, until_y=target[1])
        p = tr[-1][1]
        ex, ez = target[0] - p[0], target[2] - p[2]
        if abs(ex) < 1e-4 and abs(ez) < 1e-4:
            break
        dist = abs(target[1] - RELEASE[1])
        ax += ex / dist
        el += ez / dist
    return v


# Opt-in body sensitivity (batting round 2; every default leaves the body exactly as it was): BAT_STRENGTH and BAT_VMAX
# replace the athlete's 1.5 and 3.0; BAT_GROUP_STRENGTH / BAT_GROUP_VMAX ("pelvis_yaw=1.5,spine_=1.5") multiply the
# peak force / vmax of every muscle whose name starts with a prefix (pelvis_yaw, spine_, l_shoulder, r_elbow, ...).
# Used only by the ideal-control ceiling studies of a changed body (playground/bat_ceiling.py); no arena trial sets them.
def _group_env(name):
    out = {}
    for kv in os.environ.get(name, "").split(","):
        if kv.strip():
            k, v = kv.split("=")
            out[k.strip()] = float(v)
    return out


GROUP_STRENGTH = _group_env("BAT_GROUP_STRENGTH")
GROUP_VMAX = _group_env("BAT_GROUP_VMAX")


def group_scale(xml):
    if not GROUP_STRENGTH and not GROUP_VMAX:
        return xml
    import re

    def one(m):
        line, name = m.group(0), m.group(1)
        for table, attr in ((GROUP_STRENGTH, "force"), (GROUP_VMAX, "vmax")):
            for prefix, mult in table.items():
                if name.startswith(prefix):
                    line = re.sub(r'(\s' + attr + r'=")([^"]*)(")', lambda q: q.group(1) + f"{float(q.group(2)) * mult:g}" + q.group(3),
                                  line, count=1)
        return line
    return re.sub(r'<muscle name="([^"]*)"[^>]*/>', one, xml)


_BASE = HumanoidV2Builder if HUMAN else HumanoidBuilder


class BatBuilder(_BASE):
    """Pivot humanoid whose right hand closes around a wood bat."""

    def __init__(self, **kw):
        super().__init__("pivot", wrists=True, **kw)

    def _root(self):
        if V1:
            return super()._root()
        name = "pelvis_shift"
        lo, hi = SHIFT_RANGE
        slide = (f'<joint name="{name}" type="slide" axis="0 -1 0" range="{lo} {hi}" damping="40" '
                 f'armature="0" limited="true"/>')
        f = SHIFT_FORCE * self.spec.strength
        if self.profile is not None:   # a population profile (ROBOLAB_PROFILE; opt-in)
            f *= self.profile.strength("pelvis")
        self.spec.joints.append((name, SHIFT_RANGE))
        self.spec.muscles.append(Muscle(f"{name}_pos", name, +1, f, lo, hi, "pelvis"))
        self.spec.muscles.append(Muscle(f"{name}_neg", name, -1, f, lo, hi, "pelvis"))
        if HUMAN:  # calibrated like body.py's V2 joints: vmax = speed * 0.3 / range
            for suffix in ("pos", "neg"):
                self.vmax[f"{name}_{suffix}"] = SHIFT_SPEED * 0.3 / (hi - lo)
        return slide + "\n" + super()._root()

    def _joints(self, side, table, group):
        # The shoulder complex (glenohumeral joint plus scapular protraction)
        # reaches about 45 deg across the chest; batting needs it for the lead
        # arm at contact and the bottom hand at the set position.
        if group == "shoulder" and "shoulder_abd" in table:
            table = dict(table)
            axl, axr, rng, pp, pn = table["shoulder_abd"]
            table["shoulder_abd"] = (axl, axr, (SHOULDER_ADDUCT, rng[1]), pp, pn)
        # Wrist deviation: + is ulnar on both sides (fingers toward the little
        # finger), which uncocks the bat; humans have about twice as much ulnar
        # as radial deviation.
        if group == "wrist" and "wrist_dev" in table:
            table = dict(table)
            axl, axr, rng, pp, pn = table["wrist_dev"]
            table["wrist_dev"] = (axl, axr, WRIST_DEV, pp, pn)
        return super()._joints(side, table, group)

    def actuators_xml(self):
        xml = super().actuators_xml()
        if HUMAN:
            return group_scale(xml)    # per-joint human calibration (body.py V2_OMEGA)
        assert 'vmax="1.5"' in xml, "BatBuilder: body.py muscle vmax changed"
        vmax = MUSCLE_VMAX
        # a population profile's muscle speed (body_profile.py `speed`: fibre
        # mix x fascicle length) scales the athlete's vmax too; opt-in, only
        # with ROBOLAB_PROFILE (body.py leaves the base body's 1.5 unscaled,
        # which this body replaces)
        if self.profile is not None and "speed" in self.profile.parts:
            vmax *= self.profile.speed("")
        return group_scale(xml.replace('vmax="1.5"', f'vmax="{vmax:g}"'))

    def _arm(self, side):
        xml = super()._arm(side)
        if side != "r":
            return xml
        anchor = '<site name="r_grip" pos="0 0 -0.06" size="0.01"/>'
        assert anchor in xml, "BatBuilder: r_grip site not found in the arm XML"
        return xml.replace(anchor, anchor + self.bat_xml())

    @staticmethod
    def bat_xml():
        # Bat frame = right hand frame shifted to the grip site; the bat runs
        # along +y (out of the thumb side of the fist), knob at -GRIP_S.
        def y(s):
            return s - GRIP_S
        # (s0, s1, radius): a turned profile, knob to barrel end
        prof = [(0.020, 0.300, 0.0125), (0.300, 0.420, 0.0165), (0.420, 0.520, 0.0230),
                (0.520, 0.600, 0.0290), (0.600, BAT_LEN - 0.033, 0.0330)]
        vol = sum(math.pi * r * r * (s1 - s0) + 4.0 / 3.0 * math.pi * r ** 3 for s0, s1, r in prof)
        vol += math.pi * 0.021 ** 2 * 0.012
        dens = BAT_MASS / vol
        c = f'contype="4" conaffinity="8" solref="{CONTACT_SOLREF}" friction="0.5 0.005 0.0001" rgba="0.76 0.56 0.33 1"'
        g = [f'<geom name="bat_knob" type="cylinder" fromto="0 {y(0.0):g} 0 0 {y(0.012):g} 0" size="0.021" density="{dens:.1f}" {c}/>']
        for i, (s0, s1, r) in enumerate(prof):
            g.append(f'<geom name="bat_{i}" type="capsule" fromto="0 {y(s0):g} 0 0 {y(s1):g} 0" size="{r}" density="{dens:.1f}" {c}/>')
        return f"""
              <body name="bat" pos="0 0 -0.06" quat="{math.cos(GRIP_TILT / 2):.6f} {math.sin(GRIP_TILT / 2):.6f} 0 0">
                {"".join(g)}
                <site name="bat_knob" pos="0 {y(0.0):g} 0" size="0.008"/>
                <site name="bat_top" pos="0 {y(TOP_S):g} 0" size="0.008"/>
                <site name="bat_sweet" pos="0 {y(SWEET_S):g} 0" size="0.012" rgba="1 0.8 0.2 1"/>
                <site name="bat_tip" pos="0 {y(BAT_LEN):g} 0" size="0.008"/>
              </body>"""


def plate_mesh():
    w = PLATE_HALF
    pts2 = [(-w, 0.0), (w, 0.0), (w, 0.2159), (0.0, 0.4318), (-w, 0.2159)]
    v = []
    for z in (0.0, 0.006):
        for x, yy in pts2:
            v += [x, yy, z]
    return " ".join(f"{a:g}" for a in v)


class BatTask(Task):
    name = "bat"
    mode = "pivot"
    wrists = True
    timestep = 0.0001
    control_dt = 0.005
    seconds = 17.5
    pelvis_height = PELVIS_H
    strength = 1.0 if HUMAN else float(os.environ.get("BAT_STRENGTH", "1.5"))   # athlete / v1: 1.5x the body.py peak muscle forces
    pitches = PITCHES
    windup = 0.7 if V1 else 0.9   # s of pitcher's delivery, from the batter's `ready` to the release
    # practice: weight of bat speed (at contact, or at closest approach) in
    # the score; BAT_SPEED_WEIGHT=2 practises a harder swing once contact holds
    speed_weight = float(os.environ.get("BAT_SPEED_WEIGHT", "0.5"))
    expect_stride = os.environ.get("BAT_EXPECT_STRIDE", "1") == "1"
    # practice: weight of the kinetic-chain order (pelvis, torso, hands, bat
    # peaking in turn; out-of-order peaks cost weight per 100 ms); 0 = off
    chain_weight = float(os.environ.get("BAT_CHAIN_WEIGHT", "0"))
    # practice: weight of the swing's smoothness (command-velocity steps above
    # 15 % of the peak command speed, holds over 50 ms, from the plant through
    # the follow and let-go: contact + SMOOTH_FULL_AFTER); 0 = off
    smooth_weight = float(os.environ.get("BAT_SMOOTH_WEIGHT", "0"))
    # practice: weight of the flow of the motion as seen (flow_terms: the
    # measured valleys lift -> plant -> contact -> finish plus the command's
    # holds and steps, per pitch); 0 = off
    flow_weight = float(os.environ.get("BAT_FLOW_WEIGHT", "0"))
    fallback_gap = 4.0      # pitch anyway this long after the last one ended
    # arena: with BAT_SEEDED_PITCH=1 a rollout's `seed` picks ONE pitch of the
    # speed/location sweep grid (seed mod 18), so a trial has a sample per pitch
    seeded_pitch = os.environ.get("BAT_SEEDED_PITCH", "0") == "1"
    # arena (held out): with BAT_FRESH_PITCH=1 a rollout's `seed` draws ONE
    # pitch from a continuous distribution over the sweep's box (speed and
    # crossing uniform in FRESH_SPEED x FRESH_X x FRESH_Z), so held-out seeds
    # give pitches no grid-trained swing has seen (bat_power_fresh)
    fresh_pitch = os.environ.get("BAT_FRESH_PITCH", "0") == "1"
    seed = None
    # practice: BAT_PRACTICE_PITCHES=sweep practises on the 18-pitch
    # speed/location sweep instead of the 4 demo pitches (the 4 overfit);
    # pass practice.py --seconds 80
    if os.environ.get("BAT_PRACTICE_PITCHES") == "sweep":
        pitches = [(v, x, z) for v in (34.0, 37.0, 40.5)
                   for x, z in ((0.0, 0.80), (-0.14, 1.00), (0.15, 0.62), (-0.06, 0.68), (0.10, 0.95), (-0.12, 0.72))]

    def builder(self):
        return BatBuilder(strength=self.strength)

    # ---- scene ---------------------------------------------------------------

    def xml_extras(self):
        px, fy = PLATE_X, PLATE_FRONT_Y
        dirt = "0.60 0.45 0.33 1"
        chalk = 'rgba="0.97 0.97 0.95 1" contype="0" conaffinity="0"'
        vis = 'contype="0" conaffinity="0"'
        # batter's boxes: 4 ft x 6 ft, 6 in from the plate, centred on the plate middle
        mid = fy + 0.2159
        boxes = []
        for sgn in (-1, 1):
            cx = px + sgn * (PLATE_HALF + 0.1524 + 0.6096)
            for dx, dy, sx, sy in ((-0.6096, 0, 0.025, 0.9144), (0.6096, 0, 0.025, 0.9144),
                                   (0, -0.9144, 0.6346, 0.025), (0, 0.9144, 0.6346, 0.025)):
                boxes.append(f'<geom type="box" pos="{cx + dx:g} {mid + dy:g} 0.004" size="{sx} {sy} 0.002" {chalk}/>')
        rel = RELEASE
        # a static pitcher on the mound (world geoms: no mass, no collision)
        o = PITCHER_O
        navy, white = 'rgba="0.2 0.25 0.45 1"', 'rgba="0.92 0.92 0.95 1"'
        parts = [((0, -0.25, 0.02), (0.05, 0.25, 0.92), 0.07, navy), ((0.05, 0.25, 0.92), (0.12, 0.7, 0.5), 0.065, navy),
                 ((0.12, 0.7, 0.5), (0.12, 0.75, 0.05), 0.05, navy), ((0.05, 0.25, 0.95), (0.08, 0.32, 1.4), 0.13, white),
                 ((0.16, 0.34, 1.38), tuple(rel - o + np.array([0, 0, 0.05])), 0.04, white),
                 ((-0.02, 0.3, 1.38), (-0.3, 0.1, 1.0), 0.04, white)]
        pg = []
        for a, b, r, col in parts:
            a, b = o + np.array(a), o + np.array(b)
            pg.append(f'<geom type="capsule" fromto="{a[0]:g} {a[1]:g} {a[2]:g} {b[0]:g} {b[1]:g} {b[2]:g}" size="{r}" {col} {vis}/>')
        hp = o + np.array([0.08, 0.36, 1.62])
        pg.append(f'<geom type="sphere" pos="{hp[0]:g} {hp[1]:g} {hp[2]:g}" size="0.1" rgba="0.85 0.7 0.6 1" {vis}/>')
        pitcher = "\n    ".join(pg)
        world = f"""
    <geom name="grass" type="box" pos="{px} {fy - 9} 0.0005" size="30 30 0.0005" rgba="0.33 0.55 0.28 1" {vis}/>
    <geom name="home_dirt" type="cylinder" pos="{px} {mid} 0.001" size="4.0 0.001" rgba="{dirt}" {vis}/>
    <geom name="mound" type="cylinder" pos="{px} {RUBBER_Y + 0.3:g} 0.0" size="2.74 0.25" rgba="{dirt}" {vis}/>
    <geom name="rubber" type="box" pos="{px} {RUBBER_Y:g} 0.252" size="0.3048 0.0762 0.004" {chalk}/>
    <geom name="plate" type="mesh" mesh="plate" pos="{px} {fy} 0.001" {chalk}/>
    {"".join(boxes)}
    {pitcher}
    <body name="ball" pos="{rel[0]:g} {rel[1]:g} {rel[2]:g}">
      <freejoint name="ball"/>
      <geom name="ball" type="sphere" size="{BALL_R}" mass="{BALL_M}" contype="8" conaffinity="4"
            solref="{CONTACT_SOLREF}" friction="0.5 0.005 0.0001" rgba="0.98 0.98 0.96 1"/>
    </body>"""
        # the batter's predicted crossing point (display only: a mocap disc
        # moved by the task from the controller's `aim` reports)
        world += '''
    <body name="aim_marker" mocap="true" pos="0 0 -5">
      <geom type="cylinder" size="0.05 0.004" euler="1.5708 0 0" rgba="1 0.8 0.1 0.55" contype="0" conaffinity="0"/>
    </body>'''
        assets = f'<mesh name="plate" vertex="{plate_mesh()}"/>'
        eq = '<connect name="grip_l" site1="l_grip" site2="bat_top" solref="0.004 1"/>'
        return {"extra_world": world, "extra_assets": assets, "extra_equality": eq}

    # ---- posture at reset -------------------------------------------------------

    # Initial posture (joint -> angle): the bat held in both hands in front of
    # the body, barrel down. Solved offline so that the top hand sits on the
    # handle (see `python playground/tasks/bat.py --design`).
    # Initial posture (joint -> angle): the bat held out level over the plate
    # in both hands, athletic stance. Solved offline (inverse kinematics on
    # this MJCF) so that the top hand sits on the handle and the feet on the
    # floor.
    START = {
        "pelvis_shift": 0.000, "pelvis_yaw": 0.050, "spine_flex": 0.150, "spine_lat": 0.000,
        "spine_rot": 0.100, "l_shoulder_flex": 0.112, "l_shoulder_abd": -0.474, "l_shoulder_rot": 0.170,
        "l_elbow": 1.119, "l_wrist_flex": 0.804, "l_wrist_dev": 0.578, "r_shoulder_flex": -0.099,
        "r_shoulder_abd": -0.623, "r_shoulder_rot": -0.217, "r_elbow": 1.058, "r_wrist_flex": -0.966,
        "r_wrist_dev": 0.730, "l_hip_flex": 0.547, "l_hip_abd": 0.289, "l_hip_rot": -0.142,
        "l_knee": 0.930, "l_ankle": -0.346, "r_hip_flex": 0.512, "r_hip_abd": 0.295,
        "r_hip_rot": -0.124, "r_knee": 0.927, "r_ankle": -0.376,
    }
    START_V1 = {
        "pelvis_yaw": 0.0, "spine_flex": 0.15, "spine_lat": 0.0, "spine_rot": 0.1,
        "l_shoulder_flex": 0.112, "l_shoulder_abd": -0.474, "l_shoulder_rot": 0.170, "l_elbow": 1.119,
        "l_wrist_flex": 0.804, "l_wrist_dev": 0.578,
        "r_shoulder_flex": -0.099, "r_shoulder_abd": -0.623, "r_shoulder_rot": -0.217, "r_elbow": 1.058,
        "r_wrist_flex": -0.966, "r_wrist_dev": 0.730,
        "l_hip_flex": 0.25, "l_hip_abd": 0.22, "l_hip_rot": 0.0, "l_knee": 0.4, "l_ankle": -0.12,
        "r_hip_flex": 0.25, "r_hip_abd": 0.22, "r_hip_rot": 0.0, "r_knee": 0.4, "r_ankle": -0.12,
    }

    def reset(self, m, d):
        self.m = m
        if self.seeded_pitch and self.seed is not None:
            grid = [(v, x, z) for v in SWEEP_SPEEDS for x, z in SWEEP_LOCS]
            self.pitches = [grid[int(self.seed) % len(grid)]]
        if self.fresh_pitch and self.seed is not None:
            rng = np.random.default_rng(FRESH_SALT + int(self.seed))
            self.pitches = [(float(rng.uniform(*FRESH_SPEED)), float(rng.uniform(*FRESH_X)), float(rng.uniform(*FRESH_Z)))]
        for j, q in (self.START_V1 if V1 else self.START).items():
            d.qpos[m.joint(j).qposadr[0]] = q
        mujoco.mj_forward(m, d)
        self.ball_body = m.body("ball").id
        self.ball_q = m.joint("ball").qposadr[0]
        self.ball_v = m.joint("ball").dofadr[0]
        self.ball_geom = m.geom("ball").id
        self.bat_geoms = {i for i in range(m.ngeom) if m.geom(i).name.startswith("bat_")}
        self.grip_eq = m.equality("grip_l").id
        self.marker = m.body_mocapid[m.body("aim_marker").id]
        self.aim_view = None
        self.site = {n: m.site(n).id for n in ("bat_sweet", "bat_tip", "bat_knob", "bat_top", "l_grip")}
        # actuator i is muscle i (the bridge's order), so the log's targets index by these
        names = [m.actuator(i).name for i in range(m.nu)]
        self.smooth_idx = {"arms": [i for i, n in enumerate(names) if n.startswith(ARM_MUSCLES)],
                           "trunk": [i for i, n in enumerate(names) if n.startswith(TRUNK_MUSCLES)]}
        self.flow_idx = dict(self.smooth_idx, legs=[i for i, n in enumerate(names) if n.startswith(LEG_MUSCLES)])
        self.weight = float(m.body_subtreemass[m.body("pelvis").id]) * G
        self.state = "hold"          # hold | flight | done
        self.pitch_i = 0
        self.t_ready = None
        self.t_release = None
        self.t_end = 0.0
        self.results = []
        self.cur = None
        self.contact_force = 0.0
        self.grip_events = []
        self.prev_sweet_v = np.zeros(3)
        self.r_foot = m.geom("r_foot").id
        self.r_foot_geoms = {self.r_foot} | ({m.geom("r_toes").id} if HUMAN else set())
        self.floor = m.geom("floor").id
        self.foot_half = m.geom_size[self.r_foot].copy()
        self.pelvis = m.body("pelvis").id
        self.torso = m.body("torso").id
        self.bat_body = m.body("bat").id
        self.tl_k = 0
        self.r_grip = m.site("r_grip").id
        self.stride = None
        self.zone_path = None
        self.zone_k = 0
        self.hold_ball(d)

    # ---- ball handling ----------------------------------------------------------

    def hold_ball(self, d, pos=None):
        q, v = self.ball_q, self.ball_v
        d.qpos[q:q + 3] = RELEASE if pos is None else pos
        d.qpos[q + 3:q + 7] = [1, 0, 0, 0]
        d.qvel[v:v + 6] = 0.0

    def windup_phase(self, d):
        """Seconds into the pitcher's delivery, or None."""
        if self.state != "hold" or self.t_ready is None or self.pitch_i >= len(self.pitches):
            return None
        return d.time - self.t_ready

    @staticmethod
    def hand_path(e, windup):
        """The ball in the pitcher's hand during the delivery: out of the
        glove, up and back behind the head, then forward to the release."""
        glove = PITCHER_O + np.array([0.05, 0.45, 1.2])
        cocked = PITCHER_O + np.array([0.35, 0.0, 1.95])
        u = min(max(e / windup, 0.0), 1.0)
        def mj(t):
            return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
        if u < 0.6:
            return glove + (cocked - glove) * mj(u / 0.6)
        w = (u - 0.6) / 0.4
        return cocked + (RELEASE - cocked) * w * w     # accelerating arm


    def site_vel(self, m, d, sid):
        out = np.zeros(6)
        mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_SITE, sid, out, 0)
        return out[3:]

    def on_command(self, m, d, cmd):
        cur = self.cur
        if cmd == "swing":
            if cur is not None and cur.get("t_swing") is None:
                cur["t_swing"] = d.time
            return
        if cmd.startswith("aim:") or cmd.startswith("aim_lock:"):
            try:
                tau, x, z = (float(v) for v in cmd.split(":")[1:4])
                d.mocap_pos[self.marker] = [x, PLATE_FRONT_Y, z]
                self.aim_view = (x - PLATE_X, z, cmd.startswith("aim_lock:"))
            except ValueError:
                pass
            if cur is not None:
                key = "aim" if cmd.startswith("aim:") else "aim_lock"
                if cur.get("t_" + key) is None:
                    cur["t_" + key] = d.time
                    try:
                        vals = [float(v) for v in cmd.split(":")[1:]]
                        cur[key + "_pred"] = [round(vals[0], 3), round(vals[1] - PLATE_X, 3), round(vals[2], 3)]
                        if len(vals) > 3:
                            cur[key + "_attack_deg"] = round(math.degrees(vals[3]), 1)
                    except ValueError:
                        pass
            return
        if cmd == "ready":
            if self.t_ready is None and self.state == "hold":
                self.t_ready = d.time
        elif cmd.startswith("grip:l:"):
            want = cmd.endswith(":1")
            if want:
                err = np.linalg.norm(d.site_xpos[self.site["bat_top"]] - d.site_xpos[self.site["l_grip"]])
                if err > GRIP_CLOSE:
                    return  # the fingers close on air
            if bool(d.eq_active[self.grip_eq]) != want:
                d.eq_active[self.grip_eq] = 1 if want else 0
                self.grip_events.append((round(d.time, 4), int(want)))
                # the top hand lets go in the follow-through, often after the
                # pitch's record has closed: attach it to the latest pitch
                rec = self.cur if self.cur is not None else (self.results[-1] if self.results else None)
                if not want and rec is not None and rec.get("t_release_hand") is None:
                    rec["t_release_hand"] = round(d.time, 3)
                    tc = rec.get("t_contact", rec.get("t_closest"))
                    if tc is not None:
                        rec["hand_release_after_contact_ms"] = round(1000 * (d.time - tc), 0)

    def before_step(self, m, d):
        if self.stride is not None and self.stride.get("t_plant") is None:
            self.track_stride(m, d)
        if self.state == "hold":
            e = self.windup_phase(d)
            self.hold_ball(d, self.hand_path(e if e is not None else 0.0, self.windup))
            if e is not None and self.stride is None:
                self.start_stride(m, d)
            if self.pitch_i < len(self.pitches):
                due = self.t_ready + self.windup if self.t_ready is not None else self.t_end + self.fallback_gap
                if d.time >= due:
                    self.release(m, d)
            return
        q, v = self.ball_q, self.ball_v
        vel = d.qvel[v:v + 3]
        d.xfrc_applied[self.ball_body, :3] = -DRAG_K * np.linalg.norm(vel) * vel
        self.track(m, d)

    # ---- the batter's stride (measured, not controlled) -------------------------

    def foot_sole(self, d):
        low = 9.0
        for g in self.r_foot_geoms:
            R = d.geom_xmat[g].reshape(3, 3)
            low = min(low, d.geom_xpos[g][2] - float(np.abs(R[2, :]) @ self.m.geom_size[g]))
        return low

    def foot_down(self, d):
        for i in range(d.ncon):
            c = d.contact[i]
            if (c.geom1 in self.r_foot_geoms and c.geom2 == self.floor) or (c.geom2 in self.r_foot_geoms and c.geom1 == self.floor):
                return True
        return False

    def start_stride(self, m, d):
        self.stride = {"t_windup": d.time, "foot_y0": float(d.geom_xpos[self.r_foot][1]),
                       "pelvis_y0": float(d.xpos[self.pelvis][1]), "lift_h": 0.0,
                       "air_since": None, "t_lift": None, "t_plant": None}

    def track_stride(self, m, d):
        st = self.stride
        if d.time - st["t_windup"] > 2.0:
            st["t_plant"] = -1.0    # no plant: stop tracking
            return
        if not self.foot_down(d):
            if st["air_since"] is None:
                st["air_since"] = d.time
                if st["t_lift"] is None:
                    st["t_lift"] = d.time
            st["lift_h"] = max(st["lift_h"], self.foot_sole(d))
        elif st["air_since"] is not None:
            if d.time - st["air_since"] >= 0.05:
                st["t_plant"] = d.time
                st["foot_y_plant"] = float(d.geom_xpos[self.r_foot][1])
            st["air_since"] = None

    def release(self, m, d):
        speed, dx, z = self.pitches[self.pitch_i]
        target = (PLATE_X + dx, PLATE_FRONT_Y, z)
        vel = aim(speed, target)
        self.hold_ball(d)
        d.qvel[self.ball_v:self.ball_v + 3] = vel
        self.state = "flight"
        self.t_release = d.time
        if self.stride is None:
            self.start_stride(m, d)
        self.cur = {"pitch": self.pitch_i + 1, "speed_mph": round(mph(speed), 1),
                    "target_x": round(dx, 3), "target_z": round(z, 3),
                    "t_release": round(d.time, 3), "hit": False, "closest": 9.0,
                    "t_release_hand": None, "t_swing": None, "t_aim": None, "t_aim_lock": None}
        self.contact_steps = 0
        self.zone_path = np.array([p for _, p, _ in fly(RELEASE, vel, dt=0.0005, until_y=PLATE_FRONT_Y + 1.5)])
        self.zone_k = 0

    def track(self, m, d):
        cur = self.cur
        bp = d.qpos[self.ball_q:self.ball_q + 3]
        bv = d.qvel[self.ball_v:self.ball_v + 3].copy()
        sweet = d.site_xpos[self.site["bat_sweet"]]
        knob = d.site_xpos[self.site["bat_knob"]]
        tip = d.site_xpos[self.site["bat_tip"]]
        # plate crossing
        if "cross_x" not in cur and bp[1] >= PLATE_FRONT_Y and bv[1] > 0:
            cur["cross_x"] = round(float(bp[0] - PLATE_X), 3)
            cur["cross_z"] = round(float(bp[2]), 3)
        # bat-ball contact
        force = 0.0
        f6 = np.zeros(6)
        for i in range(d.ncon):
            con = d.contact[i]
            g1, g2 = con.geom1, con.geom2
            if (g1 == self.ball_geom and g2 in self.bat_geoms) or (g2 == self.ball_geom and g1 in self.bat_geoms):
                mujoco.mj_contactForce(m, d, i, f6)
                force += abs(f6[0])
        self.contact_force = force / self.weight
        if force > 0 and not cur["hit"]:
            cur["hit"] = True
            cur["t_contact"] = round(d.time, 4)
            sv = self.prev_sweet_v
            cur["bat_speed"] = round(float(np.linalg.norm(sv)), 2)
            cur["bat_speed_mph"] = round(mph(np.linalg.norm(sv)), 1)
            cur["pitch_at_contact"] = round(float(np.linalg.norm(self.prev_ball_v)), 2)
            axis = (tip - knob) / np.linalg.norm(tip - knob)
            s = float(np.dot(bp - knob, axis))
            cur["impact_from_end"] = round(BAT_LEN - s, 3)
            cur["contact_y"] = round(float(bp[1] - PLATE_FRONT_Y), 3)
            cur["intercept_err_cm"] = round(100 * float(np.linalg.norm(bp - sweet)), 1)
            cur["contact_z"] = round(float(bp[2]), 3)
            cur["pelvis_y_at_contact"] = float(d.xpos[self.pelvis][1])
            self.swing_geometry(cur, sv, self.prev_ball_v, knob, tip)
            cur["hand_speed_contact_mps"] = round(float(np.linalg.norm(self.site_vel(m, d, self.r_grip))), 2)
        if cur["hit"] and force == 0 and "exit_speed" not in cur and d.time - cur["t_contact"] > 0.002:
            ev = float(np.linalg.norm(bv))
            horiz = math.hypot(bv[0], bv[1])
            cur["exit_speed"] = round(ev, 2)
            cur["exit_mph"] = round(mph(ev), 1)
            cur["launch_deg"] = round(math.degrees(math.atan2(bv[2], horiz)), 1)
            # spray: 0 = straight back up the middle (-y), + toward the batter's pull side (-x for a LHB)
            cur["spray_deg"] = round(math.degrees(math.atan2(-bv[0], -bv[1])), 1)
            cur["fair"] = bool(bv[1] < 0 and abs(cur["spray_deg"]) <= 45.0)
            tr = fly(bp, bv, dt=0.002, max_t=8.0)
            cur["carry_m"] = round(float(np.linalg.norm(tr[-1][1][:2] - np.array([PLATE_X, PLATE_FRONT_Y + 0.2159]))), 1)
        # closest approach of the ball to the bat's barrel segment (for misses)
        if not cur["hit"]:
            ab = tip - knob
            tt = float(np.clip(np.dot(bp - knob, ab) / np.dot(ab, ab), 0.0, 1.0))
            dist = float(np.linalg.norm(bp - (knob + tt * ab))) - BALL_R - 0.03
            if dist < cur["closest"]:
                cur["closest"] = dist
                cur["intercept_err_cm"] = round(100 * float(np.linalg.norm(bp - sweet)), 1)
                cur["closest_s"] = round(tt * BAT_LEN, 3)
                cur["t_closest"] = d.time
                cur["pelvis_y_at_contact"] = float(d.xpos[self.pelvis][1])
                self.swing_geometry(cur, self.site_vel(m, d, self.site["bat_sweet"]), bv, knob, tip)
                sv = self.site_vel(m, d, self.site["bat_sweet"])
                cur["bat_speed"] = round(float(np.linalg.norm(sv)), 2)
                cur["bat_speed_mph"] = round(mph(np.linalg.norm(sv)), 1)
        self.prev_sweet_v = self.site_vel(m, d, self.site["bat_sweet"])
        self.prev_ball_v = bv
        self.zone_step(d, sweet)
        # end of the pitch
        el = d.time - self.t_release
        over = (not cur["hit"] and bp[1] > PLATE_FRONT_Y + 1.6) or el > 2.5 or \
            (cur["hit"] and "exit_speed" in cur and d.time - cur["t_contact"] > 0.6)
        if over:
            self.finish_pitch(d)

    @staticmethod
    def swing_geometry(cur, sv, bv, knob, tip):
        """Attack angle (bat head's climb), the pitch's vertical approach
        angle, and the tilt of the swing plane (spanned by the bat and its
        head's velocity) from horizontal, at contact or closest approach."""
        cur["attack_deg"] = round(math.degrees(math.atan2(sv[2], math.hypot(sv[0], sv[1]))), 1)
        cur["approach_deg"] = round(math.degrees(math.atan2(bv[2], math.hypot(bv[0], bv[1]))), 1)
        n = np.cross(tip - knob, sv)
        if np.linalg.norm(n) > 1e-9:
            cur["plane_tilt_deg"] = round(math.degrees(math.acos(min(1.0, abs(n[2]) / np.linalg.norm(n)))), 1)

    def zone_step(self, d, sweet):
        """Time in the zone: the bat head (6 in from the tip) within ZONE_R
        of the pitch's own path (its flight without the bat), sampled every
        0.5 ms from the release until the ball would be 1.5 m past the plate."""
        self.zone_k = (self.zone_k + 1) % 5
        if self.zone_k or self.zone_path is None:
            return
        P = self.zone_path
        dd = np.einsum("ij,ij->i", P - sweet, P - sweet)
        i = int(np.argmin(dd))
        best = math.sqrt(dd[i])
        for j in (i - 1, i):
            if 0 <= j < len(P) - 1:
                a, b = P[j], P[j + 1]
                t = float(np.clip(np.dot(sweet - a, b - a) / max(np.dot(b - a, b - a), 1e-12), 0.0, 1.0))
                best = min(best, float(np.linalg.norm(sweet - (a + t * (b - a)))))
        if best < ZONE_R:
            self.cur["time_in_zone_ms"] = self.cur.get("time_in_zone_ms", 0.0) + 0.5
        self.segment_peaks(d)
        self.cur["zone_min_cm"] = round(min(self.cur.get("zone_min_cm", 99.0), 100 * best), 1)

    SEGMENTS = ("pelvis", "torso", "hands", "bat_w", "head")

    def segment_peaks(self, d):
        """The kinetic chain through the swing, up to 30 ms after contact:
        peak pelvis and torso yaw rates (world vertical, rad/s), hand (bottom
        grip) speed (m/s), bat angular speed (rad/s) and bat-head speed (m/s),
        with the time of each peak, plus a 5 ms timeline from 30 ms before
        the hips fire."""
        cur = self.cur
        if cur["hit"] and d.time > cur["t_contact"] + 0.03:
            return
        if cur.get("t_swing") is None:
            return
        m = self.m
        v = np.zeros(6)
        vals = {}
        mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_BODY, self.pelvis, v, 0)
        vals["pelvis"] = abs(float(v[2]))
        mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_BODY, self.torso, v, 0)
        vals["torso"] = abs(float(v[2]))
        mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_SITE, self.r_grip, v, 0)
        vals["hands"] = float(np.linalg.norm(v[3:]))
        mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_BODY, self.bat_body, v, 0)
        vals["bat_w"] = float(np.linalg.norm(v[:3]))
        mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_SITE, self.site["bat_sweet"], v, 0)
        vals["head"] = float(np.linalg.norm(v[3:]))
        pk = cur.setdefault("_peaks", {})
        for k, x in vals.items():
            if x > pk.get(k, (0.0, 0.0))[0]:
                pk[k] = (x, d.time)
        cur["pelvis_peak_radps"] = round(pk["pelvis"][0], 2)
        cur["torso_peak_radps"] = round(pk["torso"][0], 2)
        cur["hand_peak_mps"] = round(pk["hands"][0], 2)
        ts = cur.get("t_swing")
        if ts is not None and d.time >= ts - 0.03:
            self.tl_k = (self.tl_k + 1) % 10
            if self.tl_k == 0:
                cur.setdefault("_timeline", []).append([round(d.time, 4)] + [round(vals[k], 2) for k in self.SEGMENTS])

    def finish_pitch(self, d):
        cur = self.cur
        cur["closest"] = round(float(cur["closest"]), 3)
        tc = cur.get("t_contact")
        if tc is None:
            tc = cur.get("t_closest")
        if tc is not None:
            if cur.get("t_swing") is not None:
                cur["swing_to_contact_ms"] = round(1000 * (tc - cur["t_swing"]), 0)
            if cur.get("t_aim") is not None:
                cur["aim_engaged_before_contact_ms"] = round(1000 * (tc - cur["t_aim"]), 0)
            if cur.get("t_aim_lock") is not None:
                cur["aim_locked_before_contact_ms"] = round(1000 * (tc - cur["t_aim_lock"]), 0)
        pk = cur.pop("_peaks", None)
        tl = cur.pop("_timeline", None)
        if pk and tc is not None:
            # peaks only count from the hips firing on (the coil and stride come earlier)
            cur["peak_ms_before_contact"] = {k: round(1000 * (tc - pk[k][1]), 0) for k in self.SEGMENTS if k in pk}
            order = [cur["peak_ms_before_contact"][k] for k in ("pelvis", "torso", "hands", "bat_w")]
            cur["chain_sequential"] = bool(all(order[i] >= order[i + 1] for i in range(len(order) - 1)))
            cur["bat_w_peak_radps"] = round(pk["bat_w"][0], 2)
        if tl and tc is not None:
            cur["timeline"] = {"fields": ["ms_to_contact"] + list(self.SEGMENTS),
                               "rows": [[round(1000 * (r[0] - tc), 0)] + r[1:] for r in tl if r[0] <= tc + 0.03]}
        st = self.stride
        if st is not None:
            cur["t_windup"] = round(st["t_windup"], 3)
            if st.get("t_lift") is not None:
                cur["t_lift"] = round(st["t_lift"], 3)
                cur["lift_before_release_ms"] = round(1000 * (cur["t_release"] - st["t_lift"]), 0)
                cur["lift_height_cm"] = round(100 * st["lift_h"], 1)
            if st.get("t_plant") not in (None, -1.0):
                cur["t_plant"] = round(st["t_plant"], 3)
                cur["stride_m"] = round(st["foot_y0"] - st["foot_y_plant"], 3)
                cur["plant_after_release_ms"] = round(1000 * (st["t_plant"] - cur["t_release"]), 0)
                if tc is not None:
                    cur["plant_to_contact_ms"] = round(1000 * (tc - st["t_plant"]), 0)
                if cur.get("t_swing") is not None:
                    cur["plant_to_swing_ms"] = round(1000 * (cur["t_swing"] - st["t_plant"]), 0)
            if "pelvis_y_at_contact" in cur:
                cur["pelvis_shift_m"] = round(st["pelvis_y0"] - cur.pop("pelvis_y_at_contact"), 3)
        self.stride = None
        for k in ("t_release_hand", "t_swing", "t_aim", "t_aim_lock", "t_closest"):
            if cur.get(k) is not None:
                cur[k] = round(cur[k], 3)
        self.results.append(cur)
        self.cur = None
        self.state = "hold"
        self.pitch_i += 1
        self.t_ready = None
        self.t_end = d.time
        d.xfrc_applied[self.ball_body, :] = 0.0
        d.mocap_pos[self.marker] = [0.0, 0.0, -5.0]
        self.aim_view = None
        self.hold_ball(d)

    # ---- sensors --------------------------------------------------------------

    def extra_sensors(self, m, d):
        e = self.windup_phase(d)
        bq, bv = self.ball_q, self.ball_v
        s = self.site
        return [
            ("ball_pos", d.qpos[bq:bq + 3]),
            ("ball_vel", d.qvel[bv:bv + 3]),
            ("bat_head_pos", d.site_xpos[s["bat_sweet"]]),
            ("bat_head_vel", self.site_vel(m, d, s["bat_sweet"])),
            ("bat_tip_pos", d.site_xpos[s["bat_tip"]]),
            ("bat_knob_pos", d.site_xpos[s["bat_knob"]]),
            ("grip_err", d.site_xpos[s["bat_top"]] - d.site_xpos[s["l_grip"]]),
            ("grip_l", [float(d.eq_active[self.grip_eq])]),
            ("bat_contact", [self.contact_force]),
            ("pitch_no", [float(self.pitch_i)]),
            ("plate", [PLATE_X, PLATE_FRONT_Y, 0.0]),
            # the pitcher's delivery as the batter sees it: [delivering, seconds into it]
            ("pitch_windup", [1.0, e] if e is not None else [0.0, 0.0]),
        ]

    # ---- metrics ----------------------------------------------------------------

    def metrics(self, m, d, log):
        res = list(self.results)
        if self.cur is not None:
            res.append(dict(self.cur, unfinished=True))
        hits = [r for r in res if r["hit"]]
        if log:
            t = np.array([e[0] for e in log])
            tg = np.array([e[4] for e in log])
            c = np.array([e[3] for e in log])
            labels = [e[1] for e in log]
            for r in res:
                t0 = r.get("t_plant", r.get("t_release"))
                t1 = r.get("t_contact", r.get("t_closest"))
                if t0 is None or t1 is None:
                    continue
                for g, idx in self.smooth_idx.items():
                    sm = cmd_smoothness(t, tg, idx, t0, t1, self.control_dt)
                    if sm:
                        r["cmd_peak_" + g], r["cmd_step_" + g], r["cmd_hold_ms_" + g] = sm
                    # the whole swing: plant -> contact + SMOOTH_FULL_AFTER (follow, let-go)
                    sm = cmd_smoothness(t, tg, idx, t0, t1 + SMOOTH_FULL_AFTER, self.control_dt)
                    if sm:
                        r["cmd_peak_full_" + g], r["cmd_step_full_" + g], r["cmd_hold_ms_full_" + g] = sm
                # the flow of the whole motion as seen, leg lift -> finish (bat_flow)
                fl = flow_terms(t, labels, c, tg, self.flow_idx, r, self.control_dt)
                if fl:
                    r["flow"] = fl.pop("flow")
                    r["flow_terms"] = fl
        # the worst hitch over the run's pitches: per muscle group, the larger of
        # the command-velocity step relative to the peak command speed and the
        # longest hold in units of 100 ms (so a 100 ms pause counts like a jump
        # of the full swing speed); lower is smoother
        def worst(sfx):
            h = [max(r["cmd_step_" + sfx + g] / max(r["cmd_peak_" + sfx + g], 1e-6), r["cmd_hold_ms_" + sfx + g] / 100.0)
                 for r in res for g in self.smooth_idx if r.get("cmd_peak_" + sfx + g) is not None]
            return round(max(h), 4) if h else None
        # power: the sweet-spot bat speed at contact, 0 for a miss (mean over pitches)
        power = [r.get("bat_speed", 0.0) if r["hit"] else 0.0 for r in res]
        # (the arena's bat_power_clean guard) the run is hitch-free: its bat_flow
        # score, the worst pitch's flow plus 1.0 per missed pitch, is at most CLEAN_FLOW
        flows = [r["flow"] for r in res if "flow" in r]
        flow_ok = bool(flows) and len(flows) == len(res) and \
            max(flows) + (len(res) - len(hits)) <= CLEAN_FLOW
        # quality: a fair ball launched at 20 deg scores 1, falling to 0 at 20 +- 30 deg; misses and fouls 0
        quality = [max(0.0, 1.0 - abs(r.get("launch_deg", -90.0) - 20.0) / 30.0) if r["hit"] and r.get("fair") else 0.0
                   for r in res]
        out = {
            "time": round(d.time, 3),
            "hitch": worst(""),
            "hitch_full": worst("full_"),
            # the worst flow over the run's pitches (leg lift -> finish, measured and commanded)
            "flow": round(max(r["flow"] for r in res if "flow" in r), 4) if any("flow" in r for r in res) else None,
            # (report) the worst over pitches of each phase's valley, stall and dip
            **{"flow_" + k: max((r["flow_terms"][k] for r in res if k in r.get("flow_terms", {})), default=None)
               for k in ("valley_lift", "valley_pre", "valley_post", "cmd", "stall_ms_pre", "stall_ms_post",
                         "dip_pre", "dip_post")},
            "power": round(float(np.mean(power)), 3) if power else None,
            "flow_ok": flow_ok,
            "quality": round(float(np.mean(quality)), 4) if quality else None,
            "pitches": res,
            "thrown": len(res),
            "hits": len(hits),
            "fair": sum(1 for r in hits if r.get("fair")),
            "grip_events": self.grip_events,
            "effort": round(float(np.mean([np.mean(np.square(e[2])) for e in log])), 4) if log else 0.0,
        }
        return out

    def score(self, metrics):
        """Practice objective: contact first (with a smooth pull toward the
        sweet spot for misses), then squaring the ball up (driven forward,
        fair, launch angle 10-30 deg, exit speed), an attack angle of +8..15
        deg, bat speed (weighted by BAT_SPEED_WEIGHT), and a stride that
        plants."""
        total = 0.0
        res = metrics.get("pitches", [])
        for r in res:
            total += self.speed_weight * min(r.get("bat_speed", 0.0), 40.0) / 15.0
            total -= min(r.get("intercept_err_cm", 100.0), 60.0) / 60.0
            att = r.get("attack_deg")
            if att is not None:
                total += 1.0 * max(0.0, 1.0 - abs(att - 11.5) / 12.0)
            if r["hit"]:
                ev = r.get("exit_speed", 0.0)
                la = r.get("launch_deg", -90.0)
                fwd = math.cos(math.radians(r.get("spray_deg", 180.0)))
                total += 1.0 + 0.75 * (fwd + 1.0) + (1.0 if r.get("fair") else 0.0)
                total += ev / 20.0 + 1.5 * max(0.0, 1.0 - abs(la - 20.0) / 25.0)
            else:
                total -= 3.0 * min(max(r.get("closest", 1.0), 0.0), 0.5)
            pk = r.get("peak_ms_before_contact")
            if self.chain_weight and pk:
                order = [pk[k] for k in ("pelvis", "torso", "hands", "bat_w")]
                late = sum(max(0.0, order[i + 1] - order[i]) for i in range(3))
                total -= self.chain_weight * late / 100.0
            if self.smooth_weight:
                for g in ("arms", "trunk"):
                    # the whole swing, plant -> contact + SMOOTH_FULL_AFTER
                    pk, st, hold = r.get("cmd_peak_full_" + g), r.get("cmd_step_full_" + g), r.get("cmd_hold_ms_full_" + g)
                    if pk:
                        total -= self.smooth_weight * max(0.0, st / pk - 0.15)
                    if hold:
                        total -= self.smooth_weight * max(0.0, hold - 50.0) / 50.0
            if self.flow_weight and r.get("flow") is not None:
                total -= self.flow_weight * r["flow"]
            if self.expect_stride:
                # the stride is part of the skill: 0.25 m or more toward the
                # mound, the front foot lifted 10 cm or more
                total -= 2.0 * max(0.0, 0.25 - r.get("stride_m", 0.0)) / 0.25
                total -= 1.0 * max(0.0, 0.10 - r.get("lift_height_cm", 0.0) / 100.0) / 0.10
        total -= 4.0 * (len(self.pitches) - len(res))
        return total

    # ---- presentation -------------------------------------------------------------

    def camera(self, m, d, cam):
        # Broadcast "high home" angle: behind the plate on the first-base
        # side, over the batter's back shoulder, looking out at the mound, so
        # the batter, the pitcher and the whole flight of the ball share the
        # frame.
        m.vis.global_.fovy = 40
        cam.lookat[:] = [0.35, -2.0, 0.62]
        cam.distance = 7.6
        cam.azimuth = -112
        cam.elevation = -11

    def title(self):
        return "robolab: baseball swing (left-handed batter, muscle-driven)"

    def hud_text(self, m, d):
        parts = []
        if self.cur is not None:
            parts.append(f"pitch {self.cur['pitch']}: {self.cur['speed_mph']} mph")
            if self.aim_view is not None:
                ax, az, locked = self.aim_view
                parts.append(f"batter's aim: {'in' if ax < 0 else 'out'} {abs(100 * ax):.0f} cm, {100 * az:.0f} cm high"
                             + (" (locked)" if locked else ""))
        elif self.pitch_i < len(self.pitches):
            parts.append(f"pitch {self.pitch_i + 1} coming")
        if self.results:
            r = self.results[-1]
            if r["hit"]:
                parts.append(f"last: bat {r.get('bat_speed_mph', 0)} mph  EV {r.get('exit_mph', 0)} mph  "
                             f"LA {r.get('launch_deg', 0)} deg  {'fair' if r.get('fair') else 'foul'}")
            else:
                parts.append(f"last: miss by {100 * r['closest']:.0f} cm, bat {r.get('bat_speed_mph', 0)} mph")
        return "   ".join(parts)


TASK = BatTask


# ---- evaluation report ---------------------------------------------------------
#
#   .venv/bin/python playground/tasks/bat.py --params params/bat.txt --out out/bat_metrics.json --media out/bat
#
# runs the demo pitches with the real-time correction on (the video run) and
# off (g_z = g_x = k_in = 0: the swing no longer bends toward the predicted
# crossing nor re-times for inside/outside), then a sweep over pitch speeds
# and locations for contact rate and intercept error, again with the
# correction on and off.

SWEEP_SPEEDS = [34.0, 37.0, 40.5]
SWEEP_LOCS = [(0.0, 0.80), (-0.14, 1.00), (0.15, 0.62), (-0.06, 0.68), (0.10, 0.95), (-0.12, 0.72)]
# held-out pitches (BAT_FRESH_PITCH): the sweep's box, sampled continuously
FRESH_SPEED = (34.0, 40.5)     # m/s at release (76-91 mph)
FRESH_X = (-0.15, 0.15)        # crossing, from the plate centre (+ = away)
FRESH_Z = (0.62, 1.00)         # crossing height at the front of the plate
FRESH_SALT = 7_919_000


BODY_VARIANTS = {
    # passive joint viscosity nearer measured human values (N m s/rad; body.py: 1.5 everywhere)
    "damping_human": {"damping": {"l_wrist": 0.1, "r_wrist": 0.1, "l_elbow": 0.3, "r_elbow": 0.3,
                                  "l_shoulder": 0.5, "r_shoulder": 0.5, "spine": 1.0}},
    "strength_2.0": {"strength": 2.0},
    "vmax_4.5": {"vmax": 4.5},
}


def _run(params, pitches, seconds=None, body=None):
    import re
    from bridge import Sim
    task = BatTask()
    task.pitches = pitches
    if body:
        if "strength" in body:
            task.strength = body["strength"]
        base = task.xml
        def xml(builder):
            out = base(builder)
            if "vmax" in body and MUSCLE_VMAX:
                out = out.replace(f'vmax="{MUSCLE_VMAX:g}"', f'vmax="{body["vmax"]:g}"')
            for pat, v in body.get("damping", {}).items():
                out = re.sub(r'(<joint name="' + pat + r'[^"]*" type="hinge"[^>]*damping=")1\.5(")',
                             lambda mm: mm.group(1) + str(v) + mm.group(2), out)
            return out
        task.xml = xml
    sim = Sim(task, params=params)
    return sim.run(seconds or 3.2 + 4.2 * len(pitches) + 0.4)


def _span(xs):
    xs = [x for x in xs if x is not None]
    return [min(xs), round(float(np.mean(xs)), 1), max(xs)] if xs else None


def _summary(res):
    ps = res["pitches"]
    hits = [p for p in ps if p["hit"]]
    def mean(xs):
        xs = [x for x in xs if x is not None]
        return round(float(np.mean(xs)), 2) if xs else None
    def get(k, rows=None):
        return [p.get(k) for p in (ps if rows is None else rows)]
    la = [p.get("launch_deg") for p in hits if p.get("launch_deg") is not None]
    return {
        "pitches": len(ps), "contacts": len(hits), "contact_rate": round(len(hits) / max(len(ps), 1), 3),
        "fair": sum(1 for p in hits if p.get("fair")), "fair_rate": round(sum(1 for p in hits if p.get("fair")) / max(len(ps), 1), 3),
        "mean_bat_speed_mps": mean(get("bat_speed")),
        "mean_bat_speed_at_contact_mps": mean(get("bat_speed", hits)),
        "max_bat_speed_mps": max([x for x in get("bat_speed") if x is not None], default=None),
        "mean_intercept_err_cm": mean(get("intercept_err_cm")),
        "mean_exit_mps": mean(get("exit_speed", hits)),
        "max_exit_mps": max([x for x in get("exit_speed", hits) if x is not None], default=None),
        "launch_deg": sorted(la), "launch_10_30": sum(1 for x in la if 10 <= x <= 30),
        "mean_attack_deg": mean(get("attack_deg")), "mean_approach_deg": mean(get("approach_deg")),
        "mean_plane_tilt_deg": mean(get("plane_tilt_deg")),
        "mean_time_in_zone_ms": mean([p.get("time_in_zone_ms", 0.0) for p in ps]),
        "mean_swing_to_contact_ms": mean(get("swing_to_contact_ms")),
        "mean_stride_m": mean(get("stride_m")), "mean_lift_height_cm": mean(get("lift_height_cm")),
        "mean_plant_to_contact_ms": mean(get("plant_to_contact_ms")),
        "mean_plant_after_release_ms": mean(get("plant_after_release_ms")),
        "mean_pelvis_shift_m": mean(get("pelvis_shift_m")),
        "mean_pelvis_peak_radps": mean(get("pelvis_peak_radps")),
        "mean_torso_peak_radps": mean(get("torso_peak_radps")),
        "mean_hand_peak_mps": mean(get("hand_peak_mps")),
        "mean_hand_speed_contact_mps": mean(get("hand_speed_contact_mps", hits)),
        "mean_bat_w_peak_radps": mean(get("bat_w_peak_radps")),
        "mean_peak_ms_before_contact": {k: mean([p["peak_ms_before_contact"][k] for p in ps if "peak_ms_before_contact" in p])
                                        for k in BatTask.SEGMENTS},
        "chain_sequential": sum(1 for p in ps if p.get("chain_sequential")),
        "plant_to_swing_ms": _span(get("plant_to_swing_ms")),
        "smoothness_plant_to_contact": {g: {"max_cmd_step": max([x for x in get("cmd_step_" + g) if x is not None], default=None),
                                            "mean_cmd_step": mean(get("cmd_step_" + g)),
                                            "mean_cmd_peak": mean(get("cmd_peak_" + g)),
                                            "max_hold_ms": max([x for x in get("cmd_hold_ms_" + g) if x is not None], default=None)}
                                        for g in ("arms", "trunk")},
        "smoothness_plant_to_finish": {g: {"max_cmd_step": max([x for x in get("cmd_step_full_" + g) if x is not None], default=None),
                                           "mean_cmd_step": mean(get("cmd_step_full_" + g)),
                                           "mean_cmd_peak": mean(get("cmd_peak_full_" + g)),
                                           "max_hold_ms": max([x for x in get("cmd_hold_ms_full_" + g) if x is not None], default=None)}
                                       for g in ("arms", "trunk")},
        "mean_power_mps": mean([p.get("bat_speed", 0.0) if p["hit"] else 0.0 for p in ps]),
        "mean_hand_release_after_contact_ms": mean(get("hand_release_after_contact_ms")),
        "effort": res.get("effort"),
    }


def report(params, out, variants=False, baseline=None, quick=False, sensitivity=False):
    import json
    from multiprocessing import Pool
    off = dict(params, g_z=0.0, g_x=0.0, k_in=0.0, g_att=0.0)
    sweep_sets = [[(v, x, z) for x, z in SWEEP_LOCS] for v in SWEEP_SPEEDS]
    n = len(sweep_sets)
    jobs = [(params, PITCHES), (off, PITCHES)] + [(params, ps) for ps in sweep_sets]
    if not quick:
        jobs += [(off, ps) for ps in sweep_sets]
    var = {"stride0": {"stride": 0.0}, "uppercut0": {"uppercut": 0.0}, "stride0_uppercut0": {"stride": 0.0, "uppercut": 0.0}}
    if variants:
        for k, v in var.items():
            jobs += [(dict(params, **v), PITCHES)] + [(dict(params, **v), ps) for ps in sweep_sets]
    if sensitivity:
        jobs += [(params, PITCHES, None, b) for b in BODY_VARIANTS.values()]
    with Pool(int(os.environ.get("BAT_REPORT_WORKERS", "3"))) as pool:
        res = pool.starmap(_run, jobs)
    demo, abl, sweep = res[0], res[1], res[2:2 + n]
    k = 2 + n
    sweep_off = []
    if not quick:
        sweep_off, k = res[k:k + n], k + n
    allp = [p for r in sweep for p in r["pitches"]]
    allp_off = [p for r in sweep_off for p in r["pitches"]]
    comparisons = {}
    if variants:
        for name, v in var.items():
            d, sw = res[k], res[k + 1:k + 1 + n]
            k += 1 + n
            comparisons[name] = {"params": v, "demo": _summary(d),
                                 "sweep": _summary({"pitches": [p for r in sw for p in r["pitches"]],
                                                    "effort": round(float(np.mean([r["effort"] for r in sw])), 4)})}
    sens = {}
    if sensitivity:
        for name in BODY_VARIANTS:
            sens[name] = _summary(res[k])
            k += 1
    doc = {
        "setup": {
            "batter": ("left-handed; pivot root: pelvis at a fixed %.2f m on a muscle-driven yaw hinge"
                       "%s; legs stand on the floor" % (PELVIS_H, "" if V1 else
                       " and a muscle-driven slide toward the mound (range %s m, %.0f N per muscle)"
                       % (list(SHIFT_RANGE), SHIFT_FORCE * BatTask.strength))),
            "body": BODY,
            "body_tweaks": {"builder": _BASE.__name__, "strength": BatTask.strength,
                            "shoulder_adduction_limit_rad": SHOULDER_ADDUCT, "wrist_deviation_range_rad": list(WRIST_DEV),
                            "muscle_vmax_L0_per_s": MUSCLE_VMAX if MUSCLE_VMAX else "per-joint human calibration (body.py V2_OMEGA)",
                            "passive_damping": "body.py V2_DAMPING (human scale)" if HUMAN else "1.5 N m s/rad at every joint",
                            "pelvis_shift": {"range_m": list(SHIFT_RANGE), "force_N": SHIFT_FORCE * BatTask.strength,
                                             "unloaded_speed_mps": SHIFT_SPEED if HUMAN else "vmax %.1f L0/s" % MUSCLE_VMAX} if not V1 else None},
            "bat": {"length_m": BAT_LEN, "mass_kg": BAT_MASS, "bat_speed_point_from_tip_m": round(BAT_LEN - SWEET_S, 3)},
            "ball": {"mass_kg": BALL_M, "radius_m": BALL_R, "drag_cd": CD, "release_to_plate_front_m": round(PLATE_FRONT_Y - RELEASE[1], 2)},
            "physics": {"timestep_s": BatTask.timestep, "control_dt_s": BatTask.control_dt,
                        "bat_ball_contact_solref": CONTACT_SOLREF, "cor_calibrated": 0.5},
        },
        "demo": {"summary": _summary(demo), "pitches": demo["pitches"], "grip_events": demo["grip_events"]},
        "ablation_no_correction": {"summary": _summary(abl), "pitches": abl["pitches"]},
        "sweep": {"speeds_mps": SWEEP_SPEEDS, "locations_dx_z": SWEEP_LOCS,
                  "summary": _summary({"pitches": allp, "effort": round(float(np.mean([r["effort"] for r in sweep])), 4)}),
                  "pitches": allp},
    }
    if sweep_off:
        doc["sweep_no_correction"] = {"summary": _summary({"pitches": allp_off, "effort": round(float(np.mean([r["effort"] for r in sweep_off])), 4)}),
                                      "pitches": allp_off}
    if comparisons:
        doc["variants_same_body"] = comparisons
    if sens:
        doc["body_sensitivity_demo"] = {"variants": {k: str(v) for k, v in BODY_VARIANTS.items()}, "summaries": sens}
    for name, path in (baseline or []):
        with open(path) as f:
            b = json.load(f)
        doc["baseline_" + name] = {"source": os.path.basename(path), "setup": b.get("setup"), "demo": b["demo"]["summary"],
                                   "sweep": b["sweep"]["summary"], "demo_pitches": b["demo"]["pitches"]}
    with open(out, "w") as f:
        json.dump(doc, f, indent=1, default=float)
    print(json.dumps({k: doc[k]["summary"] for k in ("demo", "ablation_no_correction", "sweep", "sweep_no_correction") if k in doc}, indent=1))
    if comparisons:
        print(json.dumps({k: {"demo": v["demo"], "sweep": v["sweep"]} for k, v in comparisons.items()}, indent=1))
    if sens:
        print(json.dumps(sens, indent=1))
    return doc


def media(stem, demo, fps=60):
    """From <stem>.mp4 (the bridge's video of the demo run): a contact sheet
    at the chunk transitions of pitch 1 and every pitch's contact (the
    bridge's sheet samples evenly and misses the swings), and a palette GIF
    re-encode when the bridge's GIF exceeds 6 MB."""
    import subprocess
    import imageio.v2 as imageio
    import imageio_ffmpeg
    from PIL import Image, ImageDraw, ImageFont
    ps = demo["pitches"]
    p1 = ps[0]
    tc = p1.get("t_contact", p1.get("t_closest"))
    mo = [(0.05, "start: bat out over the plate"), (0.7, "lift the bat"), (1.8, "set")]
    if p1.get("t_lift") is not None:
        mo.append((p1["t_lift"] + 0.12, "leg lift (pitcher's delivery)"))
    if p1.get("t_plant") is not None:
        mo.append((p1["t_plant"] - 0.06, "stride toward the mound"))
        mo.append((p1["t_plant"] + 0.01, "plant (front foot down)"))
    else:
        mo.append((p1["t_release"] + 0.10, "load (pitch released)"))
    mo += [(p1["t_swing"] + 0.03, "swing: hips fire"), (tc - 0.05, "slot / whip"), (tc, "contact"),
           (tc + 0.06, "follow")]
    if p1.get("t_release_hand"):
        mo.append((p1["t_release_hand"] + 0.08, "release top hand (grip:l:0)"))
    mo.append((mo[-1][0] + 0.45, "finish"))
    closes = [g for g in demo.get("grip_events", []) if g[1] == 1]
    if closes:
        mo.append((closes[0][0] - 0.25, "recover / regrip"))
    for r in ps[1:]:
        t = r.get("t_contact", r.get("t_closest"))
        if t:
            mo.append((t, f"pitch {r['pitch']} {'contact' if r['hit'] else 'closest'}"))
    mo = mo[:16]
    want = {max(0, int(round(t * fps))) for t, _ in mo}
    frames = {}
    for i, f in enumerate(imageio.get_reader(stem + ".mp4")):
        if i in want:
            frames[i] = f
    last = max(frames)
    w, h, cols = 480, 272, 4
    sheet = Image.new("RGB", (cols * w, ((len(mo) + cols - 1) // cols) * h), (255, 255, 255))
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 16)
    except OSError:
        font = ImageFont.load_default()
    for k, (t, label) in enumerate(mo):
        im = Image.fromarray(frames.get(max(0, int(round(t * fps))), frames[last])).resize((w, h))
        dr = ImageDraw.Draw(im, "RGBA")
        dr.rectangle([0, h - 26, w, h], fill=(10, 12, 18, 200))
        dr.text((8, h - 22), f"{t:5.2f}s  {label}", font=font, fill=(255, 230, 120, 255))
        sheet.paste(im, ((k % cols) * w, (k // cols) * h))
    sheet.save(stem + "_sheet.png")
    print("wrote", stem + "_sheet.png")
    gif = stem + ".gif"
    if not os.path.exists(gif) or os.path.getsize(gif) > 6_000_000:
        vf = ("fps=20,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];"
              "[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle")
        subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-i", stem + ".mp4",
                        "-vf", vf, gif], check=True)
        print("wrote", gif, os.path.getsize(gif), "bytes")


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--params")
    ap.add_argument("--out", default="out/bat_metrics.json")
    ap.add_argument("--media", help="stem of the bridge's outputs (e.g. out/bat): rebuild <stem>_sheet.png "
                    "at the key moments and fit <stem>.gif under 6 MB")
    ap.add_argument("--variants", action="store_true", help="also run stride 0 / uppercut 0 / both on this body")
    ap.add_argument("--sensitivity", action="store_true", help="also run the demo on body variants (BODY_VARIANTS)")
    ap.add_argument("--baseline", action="append", default=[],
                    help="name:path, embed another report's summaries as baseline_<name> (repeatable)")
    ap.add_argument("--quick", action="store_true", help="skip the correction-off sweep")
    a = ap.parse_args()
    prm = {}
    if a.params:
        for line in open(a.params):
            parts = line.split()
            if len(parts) >= 2 and not line.startswith("#"):
                prm[parts[0]] = float(parts[1])
    bases = []
    for item in a.baseline:
        name, _, path = item.partition(":")
        bases.append((name, path) if path else ("v1", name))
    rep = report(prm, a.out, variants=a.variants, baseline=bases, quick=a.quick, sensitivity=a.sensitivity)
    if a.media:
        media(a.media, rep["demo"])
