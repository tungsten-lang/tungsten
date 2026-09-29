"""Natural running: the RunNaturalSkill (lib/robolab/skills/run_natural.w) on the
v2 anatomy (toes, biarticular rectus femoris / hamstrings / gastrocnemius,
human-calibrated joint speeds, strength 1.0), planar root, from a standing
start (or `start = "flying"`: already running at the design speed).

The practice score rewards NATURALNESS first (low joint-angle error to a human
running reference over the normalised gait cycle and at the six gait events)
AND sustained running without falls, with speed secondary (target 3-4 m/s).

Human reference (sagittal plane, ~3.5 m/s; APPROXIMATE values read off the
published mean curves, not a single subject):
  Novacheck TF (1998) The biomechanics of running. Gait Posture 7:77-95
  Hamner SR, Delp SL (2013) Muscle contributions to fore-aft and vertical body
    mass center accelerations over a range of running speeds. J Biomech 46:780-7
  Fukuchi RK, Fukuchi CA, Duarte M (2017) A public dataset of running
    biomechanics ... PeerJ 5:e3298 (2.5 / 3.5 / 4.5 m/s)
  Schache AG et al. (1999) Intra-subject repeatability of the three
    dimensional angular kinematics within the lumbo-pelvic-hip complex during
    running. Gait Posture 15:136 (pelvis tilt, trunk)
  Pontzer H et al. (2009) Control and function of arm swing in human walking
    and running. J Exp Biol 212:523-34 (arm swing)
  Cavanagh PR, Kram R (1989), Weyand PG et al. (2000), Cavagna GA et al.
    (1988): cadence ~2.7-3.0 steps/s, contact 0.2-0.3 s, vertical COM
    excursion ~6-10 cm at 3-4 m/s.
Angles are re-zeroed on quiet standing (the model's zero): hip = thigh
relative to the pelvis (+ flexion), knee + flexion, ankle + PLANTARflexion,
toe - extension, shoulder + flexion, elbow + flexion, trunk = world pitch of
the torso (+ forward). The cycle is the right leg's, 0 % = right touchdown;
the left leg is the same curve shifted by 50 %. Events: TD 0 %, MS 18 %
(half of stance), TO 36 % (stance ~36 % of the stride, contact ~0.25 s at a
0.7 s stride).

Metrics added to the run task's (see tasks/run.py), over the last `tail_s`
seconds (steady running):
  kin_rms            mean over joint groups of the RMS error (deg) between the
                     stride-averaged cycle and the reference: hip, knee, ankle,
                     trunk, shoulder, elbow (kin_<group> each)
  event_rms          RMS error (deg) of every joint at the six gait events
                     (keyframes: R_TD R_MS R_TO L_TD L_MS L_TO)
  cadence, step_len, contact_time, flight_time, duty_factor, v_osc (pelvis
  vertical excursion per step, m), trunk_lean / pelvis_tilt (mean, deg),
  arm_swing (shoulder peak-to-peak, deg), arm_phase (deg; 0 = the arm moves
  with the contralateral thigh, as in humans), speed (m/s), in_band (speed
  within speed_band, 3-4 m/s)
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # run as a script too
import mujoco  # noqa: E402
import numpy as np  # noqa: E402

from body import HumanoidV2Builder  # noqa: E402
from bridge import ROOT  # noqa: E402
from tasks.run import RunTask  # noqa: E402

# ---- human reference -------------------------------------------------------------

EVENTS = {"TD": 0.0, "MS": 18.0, "TO": 36.0}
# (phase %, degrees) knots of the right leg's cycle at 3.5 m/s
HIP = [(0, 30), (9, 22), (18, 12), (27, 0), (36, -12), (43, -14), (50, -8), (59, 6), (68, 20), (77, 42),
       (86, 55), (93, 44)]
KNEE = [(0, 18), (9, 33), (18, 40), (27, 30), (36, 15), (43, 32), (50, 55), (59, 88), (68, 110), (77, 108),
        (86, 90), (93, 55)]
ANKLE = [(0, 0), (9, -14), (18, -20), (27, -8), (32, 6), (36, 25), (43, 22), (50, 12), (59, 2), (68, -5),
         (77, -6), (86, -2), (93, 0)]
TOE = [(0, 0), (18, 0), (27, -10), (36, -30), (43, -10), (50, 0), (86, 0)]
TRUNK_DEG = 7.0     # torso forward of vertical (mean; +-2 deg twice per stride)
PELVIS_DEG = 3.0    # pelvis forward pitch relative to standing
GROUPS = ("hip", "knee", "ankle", "trunk", "shoulder", "elbow")
LEG_JOINTS = ("hip_flex", "knee", "ankle", "toe")
JOINTS = ("spine_flex", "l_shoulder_flex", "l_elbow", "r_shoulder_flex", "r_elbow", "l_hip_flex", "l_knee",
          "l_ankle", "l_toe", "r_hip_flex", "r_knee", "r_ankle", "r_toe")


def _pchip_periodic(knots, period=100.0):
    """Shape-preserving (Fritsch-Butland) periodic cubic through the knots."""
    x = np.array([k[0] for k in knots], float)
    y = np.array([k[1] for k in knots], float)
    n = len(x)
    h = np.diff(np.append(x, x[0] + period))
    delta = (np.append(y[1:], y[0]) - y) / h
    d = np.zeros(n)
    for k in range(n):
        dp, dk, hp, hk = delta[k - 1], delta[k], h[k - 1], h[k]
        if dp * dk > 0:
            w1, w2 = 2 * hk + hp, hk + 2 * hp
            d[k] = (w1 + w2) / (w1 / dp + w2 / dk)

    def f(phase):
        p = np.mod(np.asarray(phase, float), period)
        k = np.searchsorted(x, p, side="right") - 1
        k = np.where(k < 0, n - 1, k)
        x0 = x[k]
        t = np.mod(p - x0, period) / h[k]
        y0, y1 = y[k], y[(k + 1) % n]
        d0, d1 = d[k], d[(k + 1) % n]
        t2, t3 = t * t, t * t * t
        return ((2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * h[k] * d0 + (-2 * t3 + 3 * t2) * y1
                + (t3 - t2) * h[k] * d1)
    return f


# Keyframe overrides (opt-in; the Keyframe Bench's "Copy params" output,
# e.g. params/keyframes_erik.txt): ref_<td|ms|to>_<key> in degrees, right
# stance (the left step is the mirror), key one of KF_KEYS. They are the
# RunNaturalSkill's targets (lib/robolab/skills/run_natural.w) and, given to
# Reference(keyframes=...), the naturalness metric's reference.
KF_EVENTS = (("td", 0.0), ("ms", 18.0), ("to", 36.0))
KF_KEYS = ("st_hip", "st_knee", "st_ankle", "st_toe", "sw_hip", "sw_knee", "sw_ankle", "sw_toe", "st_shoulder",
           "st_elbow", "sw_shoulder", "sw_elbow", "spine", "pelvis")
LEG_KEY = {"hip_flex": "hip", "knee": "knee", "ankle": "ankle", "toe": "toe"}
LEG_KNOTS = {"hip_flex": HIP, "knee": KNEE, "ankle": ANKLE, "toe": TOE}


def split_keyframe_name(name):
    """ref_<id>_<key> -> (id, key); ids may contain underscores, keys are
    KF_KEYS or 'phase'. (None, None) if the name is not a keyframe value."""
    if not name.startswith("ref_"):
        return None, None
    rest = name[4:]
    for key in sorted(KF_KEYS + ("phase",), key=len, reverse=True):
        if rest.endswith("_" + key) and len(rest) > len(key) + 1:
            return rest[:-len(key) - 1], key
    return None, None


DEFAULT_PHASE = {"td": 0.0, "ms": 18.0, "to": 36.0, "hr": 30.0, "kl": 38.0}


def keyframe_params(params):
    """The ref_<kf>_<key> entries of a params dict (None if it has none)."""
    kf = {k: float(v) for k, v in (params or {}).items() if k.startswith("ref_")}
    return kf or None


def read_keyframes(path):
    """ref_* keyframe targets from a params-style file (None if it has none)."""
    out = {}
    for line in open(path):
        t = line.split()
        if len(t) >= 2 and not line.startswith("#"):
            out[t[0]] = float(t[1])
    return keyframe_params(out)


class Reference:
    """The human running reference at a design speed (m/s). Curves take the
    phase in % of the right-leg cycle (0 = right touchdown) and return degrees.

    `keyframes` (opt-in, {ref_<kf>_<key>: deg}) moves the reference through
    those keyframe values: every curve (legs, shoulders, elbows, trunk,
    pelvis) gets the literature curve plus a periodic piecewise-linear offset
    that is zero where no value is given and makes the curve pass exactly
    through each given value at its gait event (TD 0 %, MS 18 %, TO 36 %; the
    left step's events 50 % later carry the mirrored values: at 50-86 % the
    right leg and arm are the swing side). Trunk = pelvis + spine."""

    def __init__(self, speed=3.5, keyframes=None):
        self.speed = speed
        dv = speed - 3.5
        hip = [(p, v + (2 * dv if p == 0 else 4 * dv if p == 77 else 6 * dv if p == 86 else 0)) for p, v in HIP]
        knee = [(p, v + (8 * dv if p == 68 else 7 * dv if p == 77 else 5 * dv if p == 86 else 0)) for p, v in KNEE]
        self.leg = {"hip_flex": _pchip_periodic(hip), "knee": _pchip_periodic(knee),
                    "ankle": _pchip_periodic(ANKLE), "toe": _pchip_periodic(TOE)}
        self.arm = 40.0 * (1.0 + 0.12 * dv)
        self.trunk_mean = TRUNK_DEG + 0.2 * dv
        self.kf = dict(keyframes) if keyframes else {}
        self.events = [(k, p) for k, p in KF_EVENTS]
        if self.kf:
            self.events = self._keyframe_events()
            self._through_keyframes({"hip_flex": hip, "knee": knee, "ankle": ANKLE, "toe": TOE})

    def _keyframe_events(self):
        """[(id, phase)] of the keyframes, by phase: td, ms, to (0 / 18 / 36
        unless ref_<id>_phase says otherwise) plus every other id the
        keyframes name (its ref_<id>_phase, or hr 30 / kl 38), inside the
        right step (phase < td + 50)."""
        ids = {"td", "ms", "to"}
        for name in self.kf:
            kid, _ = split_keyframe_name(name)
            if kid:
                ids.add(kid)
        out = []
        for kid in ids:
            p = self.kf.get(f"ref_{kid}_phase", DEFAULT_PHASE.get(kid))
            if p is not None:
                out.append((kid, float(p)))
        top = dict(out).get("td", 0.0) + 50.0
        return sorted([(k, p) for k, p in out if 0.0 <= p < top], key=lambda e: e[1])

    def phase_of(self, event):
        """Phase (% of the right cycle) of a keyframe of the right step."""
        return dict(self.events).get(event.lower(), EVENTS.get(event.upper(), 0.0))

    def extra_events(self):
        """[(ID, phase)] of the keyframes besides TD / MS / TO (none without overrides)."""
        return [(k.upper(), p) for k, p in self.events if k not in ("td", "ms", "to")]

    def cycle_phase(self, phase):
        """The measured cycle's phase of a reference phase (FastReference warps it)."""
        return phase

    # ---- keyframe overrides -------------------------------------------------------

    def _events(self, key, lit, sided=True):
        """(phase, offset) at the six gait events: the given value minus the
        literature curve `lit` there (0 where no value is given). Sided keys
        (st_/sw_ + key) read st_ at the right step's events and sw_ at the left
        step's; unsided keys (spine, pelvis, trunk) the same value at both."""
        pts = []
        for kf, ph in self.events:
            for role, off in (("st_", 0.0), ("sw_", 50.0)):
                name = f"ref_{kf}_{role if sided else ''}{key}"
                v = lit(ph + off, kf) if name in self.kf else None
                pts.append((ph + off, 0.0 if v is None else self.kf[name] - v))
        return sorted(pts)

    @staticmethod
    def _offset(pts):
        xs, ys = [p for p, _ in pts], [d for _, d in pts]
        return lambda phase: np.interp(np.mod(np.asarray(phase, float), 100.0), xs, ys, period=100.0)

    def _through_keyframes(self, knots):
        for j, kn in knots.items():
            lit = self.leg[j]
            off = self._offset(self._events(LEG_KEY[j], lambda p, kf, f=lit: float(f(p))))
            phases = sorted({float(p) for p, _ in kn} | {p for _, p in self.events} | {p + 50.0 for _, p in self.events})
            self.leg[j] = _pchip_periodic([(p, float(lit(p)) + float(off(p))) for p in phases])
        self.sh_off = self._offset(self._events("shoulder", lambda p, kf: float(self.shoulder("r", p))))
        self.el_off = self._offset(self._events("elbow", lambda p, kf: float(self._elbow_lit("r", p))))
        self.pv_off = self._offset(self._events("pelvis", lambda p, kf: PELVIS_DEG, sided=False))

        def trunk_at(p, kf):
            pel = self.kf.get(f"ref_{kf}_pelvis", PELVIS_DEG)
            return pel + self.kf.get(f"ref_{kf}_spine", self._trunk_lit(p) - PELVIS_DEG)
        pts = []
        for kf, ph in self.events:
            for p in (ph, ph + 50.0):
                given = f"ref_{kf}_pelvis" in self.kf or f"ref_{kf}_spine" in self.kf
                pts.append((p, trunk_at(p, kf) - self._trunk_lit(p) if given else 0.0))
        self.tr_off = self._offset(sorted(pts))

    # ---- curves -------------------------------------------------------------------

    def joint(self, name, phase):
        """Reference angle (deg) of a model joint at a right-cycle phase (%)."""
        phase = np.asarray(phase, float)
        if name == "spine_flex":
            return self.trunk(phase) - self.pelvis(phase)
        side, j = name[:1], name[2:]
        if j in self.leg:
            return self.leg[j](phase if side == "r" else phase - 50.0)
        sh = self.shoulder(side, phase)
        if j == "shoulder_flex":
            return sh
        return self._elbow_lit(side, phase)  # elbow

    def _elbow_lit(self, side, phase):
        el = 85.0 + 5.0 * (self.shoulder(side, phase) - 5.0) / 40.0
        if not self.kf or not hasattr(self, "el_off"):
            return el
        return el + self.el_off(np.asarray(phase, float) - (0.0 if side == "r" else 50.0))

    def shoulder(self, side, phase):
        # each arm swings with the contralateral thigh: the right arm is most
        # forward near right toe-off (the left knee up), most back at 85 %
        peak_back = 85.0 if side == "r" else 35.0
        sh = 5.0 - self.arm * np.cos(2 * np.pi * (np.asarray(phase, float) - peak_back) / 100.0)
        if not self.kf or not hasattr(self, "sh_off"):
            return sh
        return sh + self.sh_off(np.asarray(phase, float) - (0.0 if side == "r" else 50.0))

    def _trunk_lit(self, phase):
        return self.trunk_mean + 2.0 * np.cos(4 * np.pi * (np.asarray(phase, float) - 20.0) / 100.0)

    def trunk(self, phase):
        if not self.kf:
            return self._trunk_lit(phase)
        return self._trunk_lit(phase) + self.tr_off(phase)

    def pelvis(self, phase):
        """Pelvis pitch (deg): PELVIS_DEG, or through the keyframes' values."""
        if not self.kf:
            return PELVIS_DEG
        return PELVIS_DEG + self.pv_off(phase)

    def keyframe(self, stance, event):
        """{joint: deg} of the posture at `event` (TD / MS / TO) of `stance`'s step,
        plus 'trunk' and 'pelvis'."""
        phase = (EVENTS[event] if not self.kf else self.cycle_phase(self.phase_of(event))) + (0.0 if stance == "r" else 50.0)
        out = {j: float(self.joint(j, phase)) for j in JOINTS}
        out["trunk"] = float(self.trunk(phase))
        out["pelvis"] = float(self.pelvis(phase))
        return out


MOCAP_CURVES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "refs", "fukuchi2017",
                            "running_curves.json")


class MocapReference(Reference):
    """Measured reference (opt-in): the hip, knee and ankle mean curves of
    Fukuchi et al. 2017 (PeerJ 5:e3298, CC BY 4.0; 31-39 treadmill runners at
    2.5 / 3.5 / 4.5 m/s, playground/refs/fukuchi2017/running_curves.json),
    linearly interpolated to `speed` (clamped to 2.5-4.5). The dataset has no
    trunk, arms or toes, so those stay run_natural's literature curves (the
    toe curve time-warped to the measured toe-off).

    Events. The processed files carry no GRF, so toe-off is kinematic: the
    late-stance minimum of knee flexion (terminal knee extension; 38 / 36 / 34
    % at 2.5 / 3.5 / 4.5 m/s, 3-7 % before the ankle's peak plantarflexion).
    MS = TO / 2; HR = 30 % of the cycle scaled by TO / 36 (the Keyframe
    Bench's heel-rise phase); KL = the swing thigh's peak (the hip's maximum
    flexion, 50 % earlier on the contralateral leg: 32-34 %)."""

    def __init__(self, speed=3.5, keyframes=None, path=MOCAP_CURVES):
        super().__init__(speed)  # literature trunk, arms and toes (speed trends)
        import json
        with open(path) as f:
            data = json.load(f)["speeds"]
        table = sorted((float(v["m_s"]), v) for v in data.values())
        v = float(np.clip(speed, table[0][0], table[-1][0]))
        k = max(i for i, (s, _) in enumerate(table) if s <= v)
        k = min(k, len(table) - 2)
        (s0, a), (s1, b) = table[k], table[k + 1]
        w = (v - s0) / (s1 - s0)
        self.mocap_speed = v
        self.mocap = {j: (1 - w) * np.array(a[key], float) + w * np.array(b[key], float)
                      for j, key in (("hip_flex", "hip"), ("knee", "knee"), ("ankle", "ankle"))}
        knee = self.mocap["knee"]
        self.to_pct = float(20 + np.argmin(knee[20:51]))
        kl = float(np.argmax(self.mocap["hip_flex"])) - 50.0
        self.events = sorted([("td", 0.0), ("ms", self.to_pct / 2.0), ("hr", 30.0 * self.to_pct / 36.0),
                              ("to", self.to_pct), ("kl", kl)], key=lambda e: e[1])
        lit_toe = self.leg["toe"]
        to = self.to_pct

        def toe(phase):
            p = np.mod(np.asarray(phase, float), 100.0)
            return lit_toe(np.where(p < to, p * 36.0 / to, 36.0 + (p - to) * 64.0 / (100.0 - to)))
        ph = np.arange(101.0)
        for j, c in self.mocap.items():
            self.leg[j] = (lambda cc: (lambda phase: np.interp(np.mod(np.asarray(phase, float), 100.0), ph, cc)))(c)
        self.leg["toe"] = toe
        self.kf = {}

    def phase_of(self, event):
        return dict(self.events).get(event.lower(), 0.0)

    def extra_events(self):
        return [(k.upper(), p) for k, p in self.events if k not in ("td", "ms", "to")]

    def keyframe(self, stance, event):
        phase = self.phase_of(event) + (0.0 if stance == "r" else 50.0)
        out = {j: float(self.joint(j, phase)) for j in JOINTS}
        out["trunk"] = float(self.trunk(phase))
        out["pelvis"] = float(self.pelvis(phase))
        return out


def _intervals(on, t, bridge=0.02, min_len=0.03):
    """(start, end) times of the runs where `on` holds, merging runs separated
    by gaps shorter than `bridge` (contact flicker), keeping runs >= min_len."""
    out = []
    k = 0
    n = len(on)
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


class RunNaturalTask(RunTask):
    name = "run_natural"
    controller = None
    seconds = 20.0
    # "standing" or "flying" (already running at ref_speed, mid-flight after a
    # left toe-off); RUN_NATURAL_START overrides it (search workers inherit it)
    start = os.environ.get("RUN_NATURAL_START", "standing")
    ref_speed = 3.5         # the reference's design speed; the skill announces its own (ref_speed:<v>)
    speed_band = (3.0, 4.0)
    tail_s = 10.0           # steady-state window for the naturalness metrics
    ghost = True            # render the target keyframe as a translucent ghost
    keyframes = None        # opt-in {ref_<kf>_<key>: deg}: the reference passes through these keyframes
    body_note = "v2 anatomy, planar root, strength 1.0"  # the eval report's body line
    keep_qpos = False       # record every step's qpos (the keyframe contact sheet)

    def builder(self):
        return HumanoidV2Builder(self.mode, strength=self.strength, wrists=self.wrists)

    def reference(self):
        return Reference(self.ref_speed, self.keyframes)

    # ---- reset -------------------------------------------------------------------

    def reset(self, m, d):
        super().reset(m, d)  # standing pose at x = -50 (seeded perturbation if seed is set)
        self.qadr = {j: m.joint(j).qposadr[0] for j in JOINTS}
        self.pitch_adr = m.joint("root_pitch").qposadr[0]
        self.jrec = []
        self.qrec = []
        if self.start == "flying":
            self._flying_start(m, d)

    def _flying_start(self, m, d):
        """Mid-flight just after a left toe-off, moving at ref_speed (the
        reference pose; a seed perturbs joints, pitch and speed)."""
        ref = self.reference().keyframe("l", "TO")
        rng = np.random.default_rng(self.seed) if self.seed is not None else None
        for j in JOINTS:
            q = math.radians(ref[j])
            if rng is not None and j.split("_", 1)[-1] in ("hip_flex", "knee", "ankle", "flex"):
                q += rng.normal(0.0, 0.04)
            lo, hi = m.jnt_range[m.joint(j).id]
            d.qpos[self.qadr[j]] = float(np.clip(q, lo, hi))
        d.qpos[self.pitch_adr] = math.radians(ref["pelvis"]) + (rng.normal(0.0, 0.02) if rng is not None else 0.0)
        mujoco.mj_forward(m, d)
        low = min(float(d.geom_xpos[g][2]) - 0.03 for g in (m.geom("l_foot").id, m.geom("r_foot").id,
                                                           m.geom("l_toes").id, m.geom("r_toes").id))
        d.qpos[m.joint("root_z").qposadr[0]] += 0.01 - low
        v = self.ref_speed + (rng.normal(0.0, 0.2) if rng is not None else 0.0)
        d.qvel[m.joint("root_x").dofadr[0]] = v
        d.qvel[m.joint("root_z").dofadr[0]] = 0.2
        mujoco.mj_forward(m, d)

    def on_command(self, m, d, cmd):
        if cmd.startswith("ref_speed:"):
            self.ref_speed = float(cmd.split(":", 1)[1])

    def extra_sensors(self, m, d):
        """Heel contact per foot (the foot box without the toe segment, body
        weights): the RunNaturalSkill's heel-rise latch (keyframe hr)."""
        if not hasattr(self, "_heel_geoms"):
            self._heel_geoms = {m.geom("l_foot").id: 0, m.geom("r_foot").id: 1}
            self._heel_f = np.zeros(6)
        out = [0.0, 0.0]
        for i in range(d.ncon):
            con = d.contact[i]
            for g in (con.geom1, con.geom2):
                k = self._heel_geoms.get(g)
                if k is not None:
                    mujoco.mj_contactForce(m, d, i, self._heel_f)
                    out[k] += abs(self._heel_f[0]) / self.weight
        return [("l_heel_contact", [out[0]]), ("r_heel_contact", [out[1]])]

    # ---- recording ------------------------------------------------------------------

    def before_step(self, m, d):
        super().before_step(m, d)
        r = self.rec[-1]
        tor = d.xmat[self.torso].reshape(3, 3)[:, 2]
        self.jrec.append((d.time, r[3], r[4], math.atan2(tor[0], tor[2]), float(d.qpos[self.pitch_adr]),
                          float(d.xpos[self.pelvis][2]), float(d.xpos[self.pelvis][0]),
                          *[float(d.qpos[self.qadr[j]]) for j in JOINTS]))
        if self.keep_qpos:
            self.qrec.append(d.qpos.copy())

    # ---- presentation -----------------------------------------------------------------

    # the keyframe each chunk eases toward: (stance side, event)
    TARGETS = {"r_load": ("r", "MS"), "r_drive": ("r", "TO"), "r_flight": ("l", "TD"), "l_load": ("l", "MS"),
               "l_drive": ("l", "TO"), "l_flight": ("r", "TD"), "l_push0": ("l", "TO")}
    GHOST_RGBA = (0.25, 0.55, 1.0, 0.33)

    def target_keyframe(self, label):
        lab = label.split(":")[-1]
        if lab not in self.TARGETS and self.keyframes and len(lab) > 2 and lab[1] == "_":
            if not hasattr(self, "_extra_ids"):
                self._extra_ids = {e for e, _ in self.reference().extra_events()}
            if lab[2:].upper() in self._extra_ids:  # an ordered-stride chunk (r_hr, r_kl, ...)
                return lab[0], lab[2:].upper()
        return self.TARGETS.get(lab)

    def ref_qpos(self, m, qpos, side, event):
        """A copy of qpos with the joints at the human reference keyframe and the
        pelvis at the reference pitch (root x / z kept)."""
        q = np.array(qpos, float).copy()
        kf = self.reference().keyframe(side, event)
        for j in JOINTS:
            q[self.qadr[j]] = math.radians(kf[j])
        q[self.pitch_adr] = math.radians(kf["pelvis"])
        return q

    def ghost_pose(self, sim):
        """render.Recorder hook: the human reference keyframe the active chunk
        is heading for, drawn as a translucent ghost over the body."""
        self.hud_label = sim.label
        tk = self.target_keyframe(sim.label) if self.ghost else None
        if tk is None:
            return None
        return self.ref_qpos(sim.m, sim.d.qpos, *tk), self.GHOST_RGBA

    def hud_text(self, m, d):
        base = super().hud_text(m, d)
        tk = self.target_keyframe(getattr(self, "hud_label", ""))
        if tk is None:
            return base
        return f"{base}   ghost: human keyframe {tk[0].upper()}_{tk[1]}"

    def title(self):
        return "robolab: natural run (human keyframes, v2 anatomy)"

    # ---- metrics --------------------------------------------------------------------

    def metrics(self, m, d, log):
        out = super().metrics(m, d, log)
        out.update(naturalness(self.jrec, self.reference(), self.tail_s))
        lo, hi = self.speed_band
        out["in_band"] = bool(lo <= out.get("speed", 0.0) <= hi)  # arena guard: running at 3-4 m/s
        return out

    def score(self, metrics):
        """Naturalness first, sustained running essential, speed secondary.

        Sustained running: 2 per second survived (a 20 s practice run: 40),
        -40 for a fall. Naturalness: -1 per degree of cycle RMS error (kin_rms,
        mean over hip/knee/ankle/trunk/shoulder/elbow) and -0.5 per degree at
        the six keyframes (event_rms); 60 deg each when no steady stride was
        measured; the legs' mean cycle error (hip, knee, ankle) counts 0.5
        more. Peak ground force: -3 per body weight above 4. Gait timing: cadence 2.7-3.0 steps/s, contact 0.2-0.3 s
        (-150 per s outside), duty factor 0.30-0.42, pelvis excursion 6-10 cm, trunk lean 3-12 deg (penalties outside).
        Speed is a requirement, not a prize: -20 per m/s below the band
        (3-4 m/s), -10 per m/s above it."""
        if "distance" not in metrics:
            return -1e6
        T = metrics.get("time", 0.0)
        s = 2.0 * T - (40.0 if metrics.get("fell") else 0.0)
        s -= 1.0 * metrics.get("kin_rms", 60.0) + 0.5 * metrics.get("event_rms", 60.0)
        # the legs carry the look: their cycle error counts again
        s -= 0.5 * np.mean([metrics.get("kin_" + g, 60.0) for g in ("hip", "knee", "ankle")])
        # impacts: human running peaks at ~2.5-3 body weights
        s -= 3.0 * max(0.0, metrics.get("peak_grf", 0.0) - 4.0)
        lo, hi = self.speed_band
        v = metrics.get("speed", 0.0)
        s -= 20.0 * max(0.0, lo - v) + 10.0 * max(0.0, v - hi)
        cad = metrics.get("cadence", 0.0)
        s -= 20.0 * (max(0.0, 2.7 - cad) + max(0.0, cad - 3.0))
        ct = metrics.get("contact_time", 0.0)
        s -= 150.0 * (max(0.0, 0.2 - ct) + max(0.0, ct - 0.3))
        df = metrics.get("duty_factor", 0.0)
        s -= 100.0 * (max(0.0, 0.3 - df) + max(0.0, df - 0.42))
        vo = metrics.get("v_osc", 0.0)
        s -= 100.0 * (max(0.0, 0.06 - vo) + max(0.0, vo - 0.10))
        lean = metrics.get("trunk_lean", 0.0)
        s -= 0.5 * (max(0.0, 3.0 - lean) + max(0.0, lean - 12.0))
        s -= 10.0 * metrics.get("effort", 0.0) + 1.0 * metrics.get("scuffs_per_s", 0.0)
        return s


def naturalness(jrec, ref, tail_s=10.0):
    """Kinematic and gait-timing naturalness over the steady tail of a run.
    jrec rows: (t, l_contact, r_contact, torso_pitch, pelvis_pitch, pelvis_z,
    pelvis_x, *JOINTS angles), per physics step."""
    out = {"kin_rms": 60.0, "event_rms": 60.0}
    if len(jrec) < 100:
        return out
    r = np.array([[float(v) for v in row] for row in jrec])
    t = r[:, 0]
    T = t[-1]
    t0 = max(T - tail_s, T * 0.5)
    lc, rc = r[:, 1] > 0.5, r[:, 2] > 0.5
    sig = {j: np.degrees(r[:, 7 + k]) for k, j in enumerate(JOINTS)}
    sig["trunk"] = np.degrees(r[:, 3])
    sig["pelvis"] = np.degrees(r[:, 4])
    pz, px = r[:, 5], r[:, 6]
    stances = {"l": _intervals(lc, t), "r": _intervals(rc, t)}
    tail = {s: [(a, b) for a, b in iv if a >= t0 and b < T - 0.01] for s, iv in stances.items()}
    tds = {s: [a for a, _ in iv] for s, iv in tail.items()}
    n_steps = len(tds["l"]) + len(tds["r"])
    span = T - t0
    out["tail_s"] = round(span, 2)
    out["speed"] = round(float((px[-1] - np.interp(t0, t, px)) / max(span, 1e-6)), 3)
    if n_steps < 4:
        return out
    # gait timing
    out["cadence"] = round(n_steps / span, 3)
    out["step_len"] = round(out["speed"] / out["cadence"], 3)
    ct = [b - a for iv in tail.values() for a, b in iv]
    out["contact_time"] = round(float(np.mean(ct)), 3)
    air = ~lc & ~rc
    fl = [b - a for a, b in _intervals(air, t, bridge=0.0, min_len=0.01) if a >= t0]
    out["flight_time"] = round(float(np.mean(fl)), 3) if fl else 0.0
    out["duty_factor"] = round(out["contact_time"] * out["cadence"] / 2.0, 3)
    all_td = sorted(tds["l"] + tds["r"])
    osc = []
    for a, b in zip(all_td, all_td[1:]):
        w = (t >= a) & (t < b)
        if np.any(w):
            osc.append(float(np.max(pz[w]) - np.min(pz[w])))
    out["v_osc"] = round(float(np.mean(osc)), 4) if osc else 0.0
    tw = t >= t0
    out["trunk_lean"] = round(float(np.mean(sig["trunk"][tw])), 2)
    out["pelvis_tilt"] = round(float(np.mean(sig["pelvis"][tw])), 2)
    # the normalised cycle: right touchdown to right touchdown
    strides = [(a, b) for a, b in zip(tds["r"], tds["r"][1:]) if 0.4 <= b - a <= 1.2]
    if len(strides) < 2:
        return out
    ph = np.linspace(0.0, 100.0, 101)
    cyc = {k: np.mean([np.interp(a + (b - a) * ph / 100.0, t, v) for a, b in strides], axis=0)
           for k, v in sig.items()}
    rms = {}
    for g in GROUPS:
        if g == "trunk":
            err = cyc["trunk"] - ref.trunk(ph)
        else:
            names = [j for j in JOINTS if j.endswith(g if g in ("knee", "ankle", "elbow") else g + "_flex")]
            err = np.concatenate([cyc[j] - ref.joint(j, ph) for j in names])
        rms[g] = float(np.sqrt(np.mean(err ** 2)))
        out["kin_" + g] = round(rms[g], 2)
    out["kin_rms"] = round(float(np.mean(list(rms.values()))), 2)
    out["cycle"] = {k: [round(float(x), 2) for x in v] for k, v in cyc.items()}
    # stance fraction of the right cycle (toe-off phase)
    tos = [np.interp(b, [a0, b0], [0.0, 100.0]) for a0, b0 in strides for a, b in tail["r"] if a0 <= a < b0 and b < b0]
    out["toe_off_pct"] = round(float(np.mean(tos)), 1) if tos else 0.0
    # arms: peak-to-peak swing, and the phase of each arm against the
    # contralateral thigh (first harmonic over the cycle; 0 = moving together)
    out["arm_swing"] = round(float(np.mean([np.ptp(cyc["l_shoulder_flex"]), np.ptp(cyc["r_shoulder_flex"])])), 1)
    out["elbow_mean"] = round(float(np.mean([cyc["l_elbow"], cyc["r_elbow"]])), 1)

    def h1(v):
        return np.angle(np.sum(v[:100] * np.exp(-2j * np.pi * ph[:100] / 100.0)))

    lag = [math.degrees(h1(cyc["r_shoulder_flex"]) - h1(cyc["l_hip_flex"])),
           math.degrees(h1(cyc["l_shoulder_flex"]) - h1(cyc["r_hip_flex"]))]
    out["arm_phase"] = round(float(np.mean([(x + 180.0) % 360.0 - 180.0 for x in lag])), 1)
    # the six keyframes: every joint at each gait event, averaged over the tail
    events = {}
    for s in ("r", "l"):
        o = "l" if s == "r" else "r"
        for ev, times in (("TD", tds[s]), ("MS", [(a + b) / 2 for a, b in tail[s]]), ("TO", [b for _, b in tail[s]])):
            if not times:
                continue
            ach = {k: float(np.mean(np.interp(times, t, v))) for k, v in sig.items()}
            kf = ref.keyframe(s, ev)
            rows = {}
            for j in list(JOINTS) + ["trunk", "pelvis"]:
                role = j
                if j[:2] in ("l_", "r_"):
                    role = ("st_" if j[0] == s else "sw_") + j[2:]
                rows[role] = (round(kf[j], 1), round(ach[j], 1))
            events[s.upper() + "_" + ev] = rows
    # keyframes besides TD / MS / TO (ordered overrides): the stride-averaged
    # cycle at the keyframe's phase
    for ev, p in (ref.extra_events() if hasattr(ref, "extra_events") else []):
        for s in ("r", "l"):
            pc = (ref.cycle_phase(p) + (0.0 if s == "r" else 50.0)) % 100.0
            ach = {k: float(np.interp(pc, ph, v)) for k, v in cyc.items()}
            kf = ref.keyframe(s, ev)
            rows = {}
            for j in list(JOINTS) + ["trunk", "pelvis"]:
                role = j
                if j[:2] in ("l_", "r_"):
                    role = ("st_" if j[0] == s else "sw_") + j[2:]
                rows[role] = (round(kf[j], 1), round(ach[j], 1))
            events[s.upper() + "_" + ev] = rows
    del o
    errs = [a - b for rows in events.values() for k, (b, a) in rows.items()
            if not k.endswith("toe") and k != "pelvis" and k != "spine_flex"]
    out["event_rms"] = round(float(np.sqrt(np.mean(np.square(errs)))), 2) if errs else 60.0
    out["keyframes"] = events
    return out


TASK = RunNaturalTask


# ---- evaluation and rendering (python playground/tasks/run_natural.py -h) ---------------

def run_once(params, seconds, start=None, seed=None, controller=None, ref_speed=None, record=False, recorder=None):
    """One rollout; returns (task, sim, metrics with 'score')."""
    from bridge import Sim
    task = RunNaturalTask()
    if start:
        task.start = start
    task.seed = seed
    task.keep_qpos = record
    task.keyframes = keyframe_params(params) or task.keyframes
    sim = Sim(task, params=params, controller=controller)
    if ref_speed:
        task.on_command(sim.m, sim.d, f"ref_speed:{ref_speed}")
    res = sim.run(seconds, recorder=recorder)
    if ref_speed:  # a controller that announces no speed keeps the one given
        task.ref_speed = ref_speed
        res.update(naturalness(task.jrec, task.reference(), task.tail_s))
    res["score"] = round(float(task.score(res)), 3)
    return task, sim, res


def summary(res, keys=None):
    keys = keys or ["time", "fell", "speed", "cadence", "step_len", "contact_time", "flight_time", "duty_factor",
                    "v_osc", "trunk_lean", "pelvis_tilt", "arm_swing", "arm_phase", "elbow_mean", "toe_off_pct",
                    "kin_rms", *["kin_" + g for g in GROUPS], "event_rms", "peak_grf", "effort", "score"]
    return {k: (float(res[k]) if isinstance(res.get(k), (np.floating, np.integer)) else res.get(k)) for k in keys}


def keyframe_table(res):
    """{event: {role: [reference, achieved]}} for the report."""
    return {ev: {k: list(v) for k, v in rows.items()} for ev, rows in res.get("keyframes", {}).items()}


def event_times(task, stride_from_end=2):
    """The gait-event times of one steady right stride near the end of a run
    (TD / MS / TO of each step, plus any extra keyframes), in time order."""
    r = np.array([[float(v) for v in row[:3]] for row in task.jrec])
    t, lc, rc = r[:, 0], r[:, 1] > 0.5, r[:, 2] > 0.5
    st = {"l": _intervals(lc, t), "r": _intervals(rc, t)}
    rs = [iv for iv in st["r"] if iv[1] < t[-1] - 0.01]
    a, b = rs[-1 - stride_from_end]
    nxt = rs[-stride_from_end][0]
    ls = [iv for iv in st["l"] if a < iv[0] < nxt]
    if not ls:
        return None
    la, lb = ls[0]
    out = {"R_TD": a, "R_MS": (a + b) / 2, "R_TO": b, "L_TD": la, "L_MS": (la + lb) / 2, "L_TO": lb}
    # keyframes besides TD / MS / TO (ordered overrides) at their phase of the stride
    ref = task.reference()
    for ev, p in ref.extra_events():
        pc = ref.cycle_phase(p)
        out["R_" + ev] = a + (nxt - a) * pc / 100.0
        out["L_" + ev] = a + (nxt - a) * (pc + 50.0) / 100.0
    return dict(sorted(out.items(), key=lambda e: e[1]))


def keyframe_sheet(task, sim, res, path, width=360, height=420):
    """2 x N contact sheet (N = 6 gait events, more with extra keyframes): the
    reference keyframe (top) and the body at
    the same gait event of a steady stride with the reference ghosted over it
    (bottom), each annotated with reference | achieved angles."""
    from PIL import Image, ImageDraw, ImageFont
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 13)
        big = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 17)
    except OSError:
        font = big = ImageFont.load_default()
    m = sim.m
    d = mujoco.MjData(m)
    times = event_times(task)
    if times is None:
        return None
    tq = np.array([row[0] for row in task.jrec])
    qrec = np.array(task.qrec)
    ren = mujoco.Renderer(m, height, width)
    cam = mujoco.MjvCamera()
    cam.type = mujoco.mjtCamera.mjCAMERA_FREE
    cam.distance, cam.azimuth, cam.elevation = 2.7, 90, -4
    opt, pert = mujoco.MjvOption(), mujoco.MjvPerturb()
    gd = mujoco.MjData(m)
    text_h = 92
    sheet = Image.new("RGB", (len(times) * width, 2 * height + 2 * text_h + 36), (250, 250, 252))
    dr = ImageDraw.Draw(sheet)
    which = "Erik's keyframes" if task.keyframes else "human reference keyframes"
    dr.text((10, 8), f"robolab natural run: {which} (top) vs achieved at the same gait event "
            "(bottom, reference ghosted in blue).  angles: reference | achieved (deg)", font=big, fill=(20, 24, 30))
    kfs = res.get("keyframes", {})
    for col, (ev, te) in enumerate(times.items()):
        k = int(np.searchsorted(tq, te))
        q_ach = qrec[min(k, len(qrec) - 1)]
        side, kind = ev[0].lower(), ev[2:]
        q_ref = task.ref_qpos(m, q_ach, side, kind)
        for row, (q, ghost) in enumerate(((q_ref, None), (q_ach, q_ref))):
            d.qpos[:] = q
            mujoco.mj_forward(m, d)
            cam.lookat[:] = [float(d.body("pelvis").xpos[0]), 0.0, 0.78]
            ren.update_scene(d, cam)
            if ghost is not None:
                gd.qpos[:] = ghost
                mujoco.mj_kinematics(m, gd)
                scn = ren.scene
                n0 = scn.ngeom
                mujoco.mjv_addGeoms(m, gd, opt, pert, int(mujoco.mjtCatBit.mjCAT_DYNAMIC), scn)
                for i in range(n0, scn.ngeom):
                    scn.geoms[i].rgba[:] = RunNaturalTask.GHOST_RGBA
            img = Image.fromarray(ren.render())
            y = 36 + row * (height + text_h)
            sheet.paste(img, (col * width, y))
            label = f"{ev} {'target' if task.keyframes else 'reference'}" if row == 0 else f"{ev} achieved"
            dr.text((col * width + 8, y + 6), label, font=big, fill=(20, 24, 30))
        rows = kfs.get(ev, {})

        def pair(role):
            v = rows.get(role)
            return f"{v[0]:.0f}|{v[1]:.0f}" if v else "-"
        lines = [f"stance hip {pair('st_hip_flex')} knee {pair('st_knee')}",
                 f"       ankle {pair('st_ankle')} toe {pair('st_toe')}",
                 f"swing  hip {pair('sw_hip_flex')} knee {pair('sw_knee')}",
                 f"shoulder st {pair('st_shoulder_flex')} sw {pair('sw_shoulder_flex')}",
                 f"elbow st {pair('st_elbow')} sw {pair('sw_elbow')}  trunk {pair('trunk')}"]
        ty = 36 + 2 * height + text_h + 4
        for i, ln in enumerate(lines):
            dr.text((col * width + 8, ty + 17 * i), ln, font=font, fill=(30, 34, 42))
    sheet.save(path)
    return path


def write_gif(frames, path, fps, t0_frame, n_frames, scale=0.5, every=2, limit_mb=6.0):
    """A GIF of frames[t0_frame : t0_frame + n_frames], shrunk until it fits limit_mb."""
    from PIL import Image
    while True:
        sub = frames[t0_frame:t0_frame + n_frames:every]
        ims = [Image.fromarray(f).resize((int(f.shape[1] * scale), int(f.shape[0] * scale))) for f in sub]
        ims = [im.convert("P", palette=Image.ADAPTIVE, colors=128) for im in ims]
        ims[0].save(path, save_all=True, append_images=ims[1:], loop=0, duration=int(1000 * every / fps),
                    optimize=True)
        mb = os.path.getsize(path) / 1e6
        if mb <= limit_mb or scale < 0.25:
            return mb
        scale *= 0.85


def main():
    import argparse
    import json
    import time
    ap = argparse.ArgumentParser(description="Evaluate / render the natural run")
    ap.add_argument("cmd", choices=["eval", "render"])
    ap.add_argument("--params", default=os.path.join(ROOT, "params", "run_natural.txt"))
    ap.add_argument("--seconds", type=float, default=40.0)
    ap.add_argument("--start", default=None)
    ap.add_argument("--robust", type=int, default=12, help="perturbed starts (eval)")
    ap.add_argument("--robust_seconds", type=float, default=30.0)
    ap.add_argument("--v2", action="store_true", help="also measure the v2 sprint (eval)")
    ap.add_argument("--json", default=os.path.join(ROOT, "out", "run_natural_metrics.json"))
    ap.add_argument("--video")
    ap.add_argument("--gif")
    ap.add_argument("--sheet")
    ap.add_argument("--keyframes")
    ap.add_argument("--controller")
    a = ap.parse_args()
    from practice import read_params
    params = read_params(a.params)
    if a.cmd == "render":
        from render import Recorder
        from bridge import Sim
        task = RunNaturalTask()
        if a.start:
            task.start = a.start
        task.keep_qpos = True
        task.keyframes = keyframe_params(params) or task.keyframes
        sim = Sim(task, params=params, controller=a.controller)
        rec = Recorder(sim)
        res = sim.run(a.seconds, recorder=rec)
        res["score"] = task.score(res)
        print(json.dumps(summary(res)))
        if a.video:
            rec.write_mp4(a.video)
        if a.sheet:
            rec.write_sheet(a.sheet)
        if a.gif:
            span = min(6.0, a.seconds)
            first = max(0, len(rec.frames) - int(span * rec.fps))
            mb = write_gif(rec.frames, a.gif, rec.fps, first, int(span * rec.fps))
            print("wrote", a.gif, f"{mb:.2f} MB")
        if a.keyframes:
            print("wrote", keyframe_sheet(task, sim, res, a.keyframes))
        return
    t0 = time.time()
    kfs = keyframe_params(params) or getattr(RunNaturalTask(), "keyframes", None)
    out = {"task": RunNaturalTask.name, "params": os.path.relpath(a.params, ROOT), "body": RunNaturalTask.body_note,
           "reference": {"speed_ms": RunNaturalTask.ref_speed, "events_pct": EVENTS, "hip": HIP, "knee": KNEE, "ankle": ANKLE, "toe": TOE,
                         "trunk_deg": TRUNK_DEG, "pelvis_deg": PELVIS_DEG,
                         "shoulder": "5 - 40 cos(2 pi (phase - peak_back) / 100), peak_back 85 % (right) / 35 % (left)",
                         "elbow": "85 + 5 (shoulder - 5) / 40",
                         "sources": "Novacheck 1998; Hamner & Delp 2013; Fukuchi et al. 2017; Schache et al. 1999; "
                                    "Pontzer et al. 2009; Cavanagh & Kram 1989 (approximate values)",
                         "keyframes": kfs}}
    task, sim, res = run_once(params, a.seconds, a.start, controller=a.controller)
    out["clean"] = summary(res)
    out["clean"]["distance"] = res.get("distance")
    out["clean"]["t_100m"] = res.get("t_100m")
    out["keyframes"] = keyframe_table(res)
    out["cycle_achieved"] = res.get("cycle")
    runs = []
    for k in range(a.robust):
        seed = 101 * (k + 1) if k < 9 else 111 * (k - 8)
        _, _, r = run_once(params, a.robust_seconds, a.start, seed=seed, controller=a.controller)
        runs.append({"seed": seed, **summary(r, ["time", "fell", "speed", "kin_rms", "event_rms", "score"])})
    if runs:
        out["robustness"] = {"what": f"{a.robust} starts with the initial pose perturbed (N(0, 0.04 rad) hips, knees, "
                                     f"ankles, spine; N(0, 0.02 rad) pelvis pitch), {a.robust_seconds:g} s each, "
                                     "seeds held out from practice",
                             "survived": f"{sum(not r['fell'] for r in runs)}/{len(runs)}", "runs": runs}
    if a.v2:
        v2p = read_params(os.path.join(ROOT, "params", "run_v2.txt"))
        ctl = os.path.join(ROOT, "bin", "robolab_run_v2")
        v2 = {}
        for vs in (3.5, 4.0):
            _, _, r = run_once(v2p, a.seconds, "standing", controller=ctl, ref_speed=vs)
            v2[f"ref_{vs}"] = summary(r)
            v2[f"ref_{vs}"]["keyframes"] = keyframe_table(r)
        out["v2_sprint"] = {"params": "params/run_v2.txt", "controller": "bin/robolab_run_v2", **v2}
    out["wall_s"] = round(time.time() - t0, 1)
    os.makedirs(os.path.dirname(a.json), exist_ok=True)
    with open(a.json, "w") as f:
        json.dump(out, f, indent=1)
    print(json.dumps(out["clean"]))
    print("wrote", a.json)


if __name__ == "__main__":
    main()
