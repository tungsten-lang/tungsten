"""runknots: the natural run as a periodic quintic knot train (P7 in SEARCH.md).

The stride of RunKnotsSkill (lib/robolab/skills/run_knots.w) is a train of
quintic Hermite knots, one per gait event of the right step (td, ms, to, plus
ordered extras such as hr / kl), each a contraction vector c, a velocity
vector v and an acceleration vector a over the body's 32 muscles; the left
step's knots are their mirror images. A knot chunk runs from one gait event
to the next (its latch), timed in gait phase; over a segment of D seconds
from knot k to knot k+1, at s = elapsed / D,

    u(s) = c_k (1 - H5(s)) + c_k+1 H5(s) + D (v_k h1(s) + v_k+1 h4(s)) + D^2 (a_k h2(s) + a_k+1 h3(s))

(H5 = min_jerk, h1..h4 = Quintic.basis): linear in the knots. Sampled at S
points per segment it is u = B K. Signals are compared EVENT-LOCKED: every
segment of every steady stride is resampled from its start event to its end
event and averaged over the strides, so an error is charged to the knots of
the segment it happened in however the event timing varies (the arena metric
averages in stride phase instead, which blurs a command whose events move).

  fit    imitating a reference is least squares, min ||B K - c_target||^2 +
         ridge: c_target is the reference's joint-angle curves (Fukuchi 2017
         mocap, the literature curves, or Erik's keyframe sets) turned into
         the contraction every muscle has at that posture (MuJoCo's own
         actuator lengths: the quantity the reflexes servo), plus the
         co-contraction the runner holds; zero rollouts
  ilc    the reflex servo lags and sags, so the achieved contractions miss
         the command: iterative learning control, K <- K + alpha B+ e with e
         the event-locked error curves c_target - c_achieved (32 muscles x S
         samples per segment, the error read `lead` seconds ahead: the servo's
         lag), B rebuilt from the measured segment durations each iteration
  train  knots + a small residual causal TCN (per-joint outputs), jointly,
         by antithetic ES on the pairs' raw score differences at a tiny step
         (P6's recipe), on fresh perturbed standing starts
  eval / render

    runknots.py fit    --target mocap --out out/runknots/mocap/fit.txt
    runknots.py ilc    --target mocap --iters 20 --out out/runknots/mocap/ilc
    runknots.py train  --target mocap --base out/runknots/mocap/ilc/best.txt --budget 3200
    runknots.py eval   --target mocap --params <p> --seeds 6201-6212
    runknots.py render --target mocap --params <p> --video out/run_knots.mp4 --gif out/run_knots.gif

Targets: `mocap` (task run_natural_mocap: hip / knee / ankle the Fukuchi 2017
means at the measured speed, trunk, arms and toes the literature curves),
`lit` (run_natural: the literature curves at 3.5 m/s), `erik3` (run_natural_erik
with Erik's keyframe set 3, frozen for the arena). Seeds: ILC trains on the
clean start plus 7001-7005, ES on 300000+, probes 6201-6212, validation
6301-6324; none is an arena seed (401-412).
"""

import argparse
import json
import math
import multiprocessing as mp
import os
import sys
import time

for _v in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_v, "1")

import mujoco  # noqa: E402
import numpy as np  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from bridge import Sim  # noqa: E402
from practice import read_params  # noqa: E402

CONTROLLER = os.path.join(ROOT, "bin", "robolab_run_knots")
OUT = os.path.join(ROOT, "out", "runknots")
CHAMPION = os.path.join(HERE, "arena", "params", "run_natural-20260927-010053.txt")  # round 1, all three trials
ERIK3 = os.path.join(HERE, "arena", "params", "keyframes_erik3-20260927-162054.txt")
KFDROP = os.path.join(ROOT, "out", "runknots", "kfdrop")
TARGETS = {
    "mocap": {"task": "run_natural_mocap", "env": {}},
    "lit": {"task": "run_natural", "env": {}},
    "erik3": {"task": "run_natural_erik", "env": {"ROBOLAB_RN_KEYFRAMES": ERIK3}},
    # set 3 with one push-off keyframe removed from the reference (the
    # keyframe ablation; playground/kfdrop.py writes the files): the ILC
    # chases, and its rollouts are scored against, the reduced set
    "erik3_nohr": {"task": "run_natural_erik", "env": {"ROBOLAB_RN_KEYFRAMES": os.path.join(KFDROP, "keyframes_erik3_nohr.txt")}},
    "erik3_noto": {"task": "run_natural_erik", "env": {"ROBOLAB_RN_KEYFRAMES": os.path.join(KFDROP, "keyframes_erik3_noto.txt")}},
}
S = 24                    # samples per segment (event to event)
KINDS = ("c", "v", "a")
MAIN = {"td": 0.0, "ms": 18.0, "to": 36.0, "hr": 30.0, "kl": 38.0}
DT = 0.004                # the control tick (2 physics steps of 2 ms)
TAIL = 10.0
GROUP_JOINTS = (("hip", ("l_hip_flex", "r_hip_flex")), ("knee", ("l_knee", "r_knee")), ("ankle", ("l_ankle", "r_ankle")),
                ("spine", ("spine_flex",)), ("shoulder", ("l_shoulder_flex", "r_shoulder_flex")),
                ("elbow", ("l_elbow", "r_elbow")), ("toe", ("l_toe", "r_toe")))


def write_params(path, params, header=""):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        for line in header.splitlines():
            f.write(f"# {line}\n")
        for k in sorted(params):
            if not k.startswith("__"):
                f.write(f"{k} {float(params[k])!r}\n")


def load_task(target):
    import importlib
    for k, v in TARGETS[target]["env"].items():
        os.environ[k] = v
    return importlib.import_module(f"tasks.{TARGETS[target]['task']}").TASK()


# ---------------------------------------------------------------------------
# the body: muscles, mirror map, posture -> contraction


class Body:
    """The v2 body's muscles and joints, and each muscle's contraction at a
    posture exactly as the bridge measures it: (hi - L) / (hi - lo) from
    MuJoCo's actuator length at that posture."""

    def __init__(self, target="lit"):
        task = load_task(target)
        sim = Sim(task, params={}, controller="/usr/bin/true")
        self.m = sim.m
        self.d = mujoco.MjData(self.m)
        self.names = [mu.name for mu in sim.muscles]
        self.nm = len(self.names)
        self.act = sim.act_ids
        self.lr = sim.lr.copy()
        self.span = self.lr[:, 1] - self.lr[:, 0]
        idx = {n: i for i, n in enumerate(self.names)}

        def mirror(n):
            return ("r_" + n[2:]) if n.startswith("l_") else ("l_" + n[2:]) if n.startswith("r_") else n
        self.mirror = np.array([idx[mirror(n)] for n in self.names])
        self.group = [mu.group for mu in sim.muscles]
        from tasks.run_natural import JOINTS
        self.joints = list(JOINTS)
        self.qadr = {j: self.m.joint(j).qposadr[0] for j in self.joints}
        # the pos muscle of each joint (monoarticular, unit moment arm): its
        # contraction error times its span is the joint-angle error in rad
        self.pos = {j: next(i for i, mu in enumerate(sim.muscles) if mu.joint == j and mu.sign > 0) for j in self.joints}
        mujoco.mj_forward(self.m, self.d)
        self.q0 = self.d.qpos.copy()
        # d contraction / d spine angle (the spine target follows the measured pelvis)
        self.spine_slope = (self.contraction({"spine_flex": 0.05}) - self.contraction({"spine_flex": -0.05})) / 0.1

    def contraction(self, q):
        """{joint: rad} -> contraction per muscle."""
        self.d.qpos[:] = self.q0
        for j, v in q.items():
            self.d.qpos[self.qadr[j]] = v
        mujoco.mj_fwdPosition(self.m, self.d)
        L = self.d.actuator_length[self.act]
        return (self.lr[:, 1] - L) / self.span

    def curves(self, qcurves):
        """{joint: rad[n]} -> contraction [nm, n]."""
        n = len(next(iter(qcurves.values())))
        return np.stack([self.contraction({j: v[k] for j, v in qcurves.items()}) for k in range(n)], axis=1)

    def degrees(self, e):
        """Contraction errors [nm, ...] -> joint-angle errors (deg) of each joint's pos muscle."""
        return {j: np.degrees(e[self.pos[j]] * self.span[self.pos[j]]) for j in self.joints}


def group_rms_deg(body, e):
    """RMS (deg) per joint group of a contraction error [nm, ...]."""
    deg = body.degrees(np.asarray(e))
    return {g: round(float(np.sqrt(np.mean(np.concatenate([np.ravel(deg[j]) ** 2 for j in js])))), 3)
            for g, js in GROUP_JOINTS}


# ---------------------------------------------------------------------------
# references -> contraction targets


def reference(target, speed=3.5):
    """The trial's reference: mocap at `speed` (the arena scores it at the
    measured speed), the literature curves and Erik's set 3 at `speed` (the
    speed the skill announces, its `speed` param)."""
    from tasks.run_natural import MocapReference, Reference, read_keyframes
    if target == "mocap":
        return MocapReference(float(np.clip(speed, 2.5, 4.5)))
    kf = TARGETS[target]["env"].get("ROBOLAB_RN_KEYFRAMES")
    if kf:
        return Reference(speed, read_keyframes(kf))
    return Reference(speed)


class Target:
    """The target contraction of every muscle at a stride phase (% of the
    right cycle, 0 = right touchdown): the reference posture through the
    body's geometry (the spine: reference trunk minus reference pelvis). With
    the measured pelvis pitch given, the spine can instead be aimed at the
    reference TRUNK on the body's own pelvis (follow_pelvis)."""

    def __init__(self, body, ref, n=400):
        from tasks.run_natural import JOINTS
        self.ph = np.linspace(0.0, 100.0, n, endpoint=False)
        q = {}
        for j in JOINTS:
            if j == "spine_flex":
                q[j] = np.radians(ref.trunk(self.ph) - ref.pelvis(self.ph))
            else:
                q[j] = np.radians(np.asarray(ref.joint(j, self.ph), float))
        self.C = body.curves(q)
        self.pelvis = np.broadcast_to(np.asarray(ref.pelvis(self.ph), float), self.ph.shape).copy()
        self.slope = body.spine_slope
        self.trunk_mean = float(np.mean(ref.trunk(self.ph)))
        # the spine aimed at the reference trunk on the measured pelvis
        # (instead of the reference spine angle); off by default: the torso
        # servo holds the trunk, so the spine then sets the pelvis
        self.follow_pelvis = False

    def at(self, phase, pelvis_deg=None):
        """[nm, len(phase)]."""
        p = np.mod(np.asarray(phase, float), 100.0)
        C = np.stack([np.interp(p, self.ph, row, period=100.0) for row in self.C])
        if pelvis_deg is not None:
            ref_pel = np.interp(p, self.ph, self.pelvis, period=100.0)
            C = C + self.slope[:, None] * np.radians(ref_pel - np.asarray(pelvis_deg, float))[None, :]
        return C


# ---------------------------------------------------------------------------
# the knot train: plan, event-locked basis, least squares


class Plan:
    """The right step's knot ids in phase order (td, ms, to and every
    ref_<id>_phase inside the step: RunNaturalSkill's ordered plan), the
    stride's cycle of knots (right step, then the mirrored left step) and the
    chunk that ends on each knot (RunNaturalSkill's chunk names)."""

    def __init__(self, params):
        ids = ["td", "ms", "to"]
        for k in params:
            if k.startswith("ref_") and k.endswith("_phase") and len(k) > 10:
                i = k[4:-6]
                if i not in ids:
                    ids.append(i)

        def ph(i):
            return float(params.get(f"ref_{i}_phase", MAIN.get(i, -1.0)))
        top = ph("td") + 50.0
        self.ids = sorted([i for i in ids if 0.0 <= ph(i) < top], key=ph)
        # two_knot (RunKnotsSkill): touchdown and toe-off only
        self.two = params.get("two_knot", 0.0) > 0.5
        if self.two:
            self.ids = ["td", "to"]
        self.phase = {i: ph(i) for i in self.ids}
        # knot_mid (the residual's knots between the events): h<id>, halfway
        # through the chunk that ends on <id>
        self.mid = params.get("knot_mid", 0.0) > 0.5
        self.knot_ids = self.ids + (["h" + i for i in self.ids] if self.mid else [])
        self.cycle = [(i, "R") for i in self.ids] + [(i, "L") for i in self.ids]
        self.K = len(self.cycle)
        self.pos = {k: n for n, k in enumerate(self.cycle)}
        self.chunk_goal = {}
        for st in ("r_", "l_"):
            side = "R" if st == "r_" else "L"
            other = "L" if side == "R" else "R"
            if self.two:  # the stance chunk ends on toe-off (a 3-chunk source's drive chunk does too)
                self.chunk_goal[st + "stance"] = ("to", side)
                self.chunk_goal[st + "drive"] = ("to", side)
            for i in self.ids:
                if i == "td":
                    self.chunk_goal[st + "flight"] = ("td", other)
                elif i == "ms":
                    self.chunk_goal[st + "load"] = ("ms", side)
                elif i == "to":
                    self.chunk_goal[st + "drive"] = ("to", side)
                else:
                    self.chunk_goal[st + i] = (i, side)

    def nominal_phases(self):
        """Each knot's phase in the stride (%): the right step's at their
        keyframe phase, the left step's 50 % later."""
        return [self.phase[i] + (0.0 if s == "R" else 50.0) for i, s in self.cycle]

    def slot(self, kind, kid):
        return KINDS.index(kind) * len(self.knot_ids) + self.knot_ids.index(kid)


def hermite(s):
    """[H0, H5, h1, h2, h3, h4] at s."""
    s2, s3 = s * s, s * s * s
    s4, s5 = s3 * s, s3 * s2
    h5 = s3 * (s * (s * 6.0 - 15.0) + 10.0)
    h1 = s - 6.0 * s3 + 8.0 * s4 - 3.0 * s5
    h2 = 0.5 * s2 - 1.5 * s3 + 1.5 * s4 - 0.5 * s5
    h3 = 0.5 * s3 - s4 + 0.5 * s5
    h4 = -4.0 * s3 + 7.0 * s4 - 3.0 * s5
    return 1.0 - h5, h5, h1, h2, h3, h4


SGRID = np.arange(S) / S


class EventBasis:
    """B: the knot vectors -> the command at S points of each segment (event
    to event, segment k from knot k to knot k+1 of the plan's cycle, lasting
    D[k] seconds). Unknowns x[slot, muscle], slot = kind * nid + id; the left
    step's knots read the mirror muscle. Rows (muscle, segment, sample)."""

    def __init__(self, plan, D):
        self.plan = plan
        self.D = np.asarray(D, float)
        K, nid = plan.K, len(plan.knot_ids)
        G = np.zeros((K, S, 3 * nid, 2))
        for k in range(K):
            k0, k1 = plan.cycle[k], plan.cycle[(k + 1) % K]
            parts = [(k0, k1, np.ones(S, bool), SGRID, self.D[k])]
            if plan.mid:  # two quintic segments per chunk, through the mid knot
                km = ("h" + k1[0], k1[1])
                first = SGRID < 0.5
                parts = [(k0, km, first, SGRID * 2.0, self.D[k] / 2.0),
                         (km, k1, ~first, SGRID * 2.0 - 1.0, self.D[k] / 2.0)]
            for ka, kb, mask, ls, d in parts:
                H0, H5, h1, h2, h3, h4 = hermite(ls[mask])
                for kind, (kid, side), w in (("c", ka, H0), ("c", kb, H5), ("v", ka, d * h1), ("v", kb, d * h4),
                                             ("a", ka, d * d * h2), ("a", kb, d * d * h3)):
                    G[k, mask, plan.slot(kind, kid), 0 if side == "R" else 1] += w
        self.G = G

    def matrix(self, mirror):
        nm = len(mirror)
        K = self.plan.K
        nslot = self.G.shape[2]
        A = np.zeros((nm * K * S, nslot * nm))
        cols = np.arange(nslot) * nm
        for m in range(nm):
            rows = slice(m * K * S, (m + 1) * K * S)
            A[rows, cols + m] += self.G[:, :, :, 0].reshape(K * S, nslot)
            A[rows, cols + mirror[m]] += self.G[:, :, :, 1].reshape(K * S, nslot)
        return A

    def scale(self, nm):
        """One unit moves the command about equally: a contraction by 1, a
        velocity by 1 / (0.19 D), an acceleration by 1 / (0.0173 D^2)."""
        d = float(np.mean(self.D)) / (2.0 if self.plan.mid else 1.0)
        nid = len(self.plan.knot_ids)
        per = np.concatenate([np.full(nid, 1.0), np.full(nid, 1.0 / (0.19 * d)), np.full(nid, 1.0 / (0.0173 * d * d))])
        return np.repeat(per, nm)


def solve(A, y, scale, ridge):
    """argmin_x ||A x - y||^2 + ridge ||x_va / scale||^2 (the ridge on the
    derivative knots, in scaled units)."""
    As = A * scale[None, :]
    n = As.shape[1]
    reg = np.full(n, math.sqrt(ridge))
    reg[:n // 3] = 0.0
    M = np.vstack([As, np.diag(reg)])
    z = np.linalg.lstsq(M, np.concatenate([np.ravel(y), np.zeros(n)]), rcond=None)[0]
    return z * scale


def unpack(x, plan, body, prefix="k"):
    """x [slot, muscle] -> params {<prefix><kind>_<id>_<muscle>: value}
    (prefix k: the knot train's knots, r: the residual's)."""
    out = {}
    for kind in KINDS:
        for kid in plan.knot_ids:
            for m in range(body.nm):
                out[f"{prefix}{kind}_{kid}_{body.names[m]}"] = float(x[plan.slot(kind, kid) * body.nm + m])
    return out


def pack(params, plan, body, prefix="k"):
    x = np.zeros(3 * len(plan.knot_ids) * body.nm)
    for kind in KINDS:
        for kid in plan.knot_ids:
            for m in range(body.nm):
                x[plan.slot(kind, kid) * body.nm + m] = params.get(f"{prefix}{kind}_{kid}_{body.names[m]}", 0.0)
    return x


def kind_durations(plan, D):
    """kt_load / kt_drive / kt_fly from measured segment durations (the
    3-knot plan: the mean of each kind's two segments; ordered plans: the
    least-squares base over each kind's segments and their shares; the
    two-knot plan: kt_stance / kt_fly)."""
    if plan.two:
        st = [D[k] for k in range(plan.K) if plan.cycle[(k + 1) % plan.K][0] == "to"]
        fl = [D[k] for k in range(plan.K) if plan.cycle[(k + 1) % plan.K][0] == "td"]
        return {"kt_stance": float(np.mean(st)), "kt_fly": float(np.mean(fl))}
    ph = dict(plan.phase)
    top = ph["td"] + 50.0

    def kind(i):
        p = ph[i] if i != "td" else top
        return "load" if (i != "td" and p <= ph["ms"]) else "drive" if (i != "td" and p <= ph["to"]) else "flight"

    def share(p, k):
        a, b = (ph["td"], ph["ms"]) if k == "load" else (ph["ms"], ph["to"]) if k == "drive" else (ph["to"], top)
        return 1.0 if b <= a else (p - a) / (b - a)
    num, den = {}, {}
    for k in range(plan.K):
        i0, i1 = plan.cycle[k][0], plan.cycle[(k + 1) % plan.K][0]
        kd = kind(i1)
        p1 = ph[i1] if i1 != "td" else top
        sh = share(p1, kd) - share(ph[i0], kd)
        num[kd] = num.get(kd, 0.0) + sh * D[k]
        den[kd] = den.get(kd, 0.0) + sh * sh
    names = {"load": "kt_load", "drive": "kt_drive", "flight": "kt_fly"}
    return {names[k]: num[k] / den[k] for k in num if den[k] > 0}


def stiffness_knots(params, plan, body):
    """The co-contraction the runner holds, as knot contractions: at every
    right-stance knot the right leg's muscles +stiff_st / 2, the left leg's
    +stiff_sw / 2, spine and arms +stiff_up / 2 (RunNaturalSkill's keyframes)."""
    st, sw, up = (params.get(k, d) for k, d in (("stiff_st", 0.2), ("stiff_sw", 0.08), ("stiff_up", 0.1)))
    x = np.zeros(3 * len(plan.knot_ids) * body.nm)
    for kid in plan.ids:
        for m, n in enumerate(body.names):
            arm = body.group[m] in ("shoulder", "elbow")
            s = up if arm or n[:2] not in ("l_", "r_") else st if n.startswith("r_") else sw
            x[plan.slot("c", kid) * body.nm + m] = 0.5 * s
    return x


def nominal_segments(plan, target, period):
    """The target sampled event-locked at the nominal knot phases (the
    zero-rollout fit): ([K, nm, S], D[K])."""
    ph = plan.nominal_phases()
    K = plan.K
    Y, D = [], []
    for k in range(K):
        a, b = ph[k], ph[(k + 1) % K]
        span = (b - a) % 100.0
        Y.append(target.at(a + span * SGRID))
        D.append(span / 100.0 * period)
    return np.stack(Y), np.array(D)


def to_rows(Y):
    """[K, nm, S] -> the basis' row order (muscle, segment, sample)."""
    return np.transpose(Y, (1, 0, 2)).ravel()


def from_rows(y, K, nm):
    return np.transpose(np.reshape(y, (nm, K, S)), (1, 0, 2))


def seg_deg(body, Y):
    """Joint-group RMS (deg) of an event-locked contraction array [K, nm, S]."""
    return group_rms_deg(body, np.transpose(Y, (1, 0, 2)))


# ---------------------------------------------------------------------------
# rollouts: trace the command, measure the strides event-locked


class KnotSim(Sim):
    """A Sim that keeps the controller's `kcmd:` (the tracks' command) and
    `tcn:` tokens per tick."""

    def start_controller(self):
        super().start_controller()
        self.kcmd = []
        self.kres = []
        self.tcn_out = []
        base = self.task.on_command

        def on_command(m, d, cmd):
            if cmd.startswith("kcmd:"):
                self.kcmd.append((d.time, np.array([float(v) for v in cmd[5:].split(",")])))
            elif cmd.startswith("kres:"):
                self.kres.append((d.time, np.array([float(v) for v in cmd[5:].split(",")])))
            elif cmd.startswith("tcn:"):
                self.tcn_out.append((d.time, np.array([float(v) for v in cmd[4:].split(",")])))
            else:
                base(m, d, cmd)
        self.task.on_command = on_command


def event_analysis(sim, task, plan, target, lead=0.0, tail_s=TAIL):
    """The steady tail, event-locked: each segment of the plan's cycle (knot
    k's event to knot k+1's: the chunk transitions) resampled at S points and
    averaged over its instances inside the metric's strides (right touchdown
    to right touchdown). Returns per segment [K, nm, S]: achieved contraction
    c, command u (the kcmd trace, if any), target (at each sample's stride
    phase, the spine on the measured pelvis) and error read `lead` s ahead;
    mean durations D[K], counts, mean knot phases, stride count and period."""
    from tasks.run_natural import _intervals
    r = np.array([[float(v) for v in row[:5]] for row in task.jrec])
    tj, rc = r[:, 0], r[:, 2] > 0.5
    T = tj[-1]
    t0 = max(T - tail_s, T * 0.5)
    rs = [(a, b) for a, b in _intervals(rc, tj) if a >= t0 and b < T - 0.01]
    tds = [a for a, _ in rs]
    strides = [(a, b) for a, b in zip(tds, tds[1:]) if 0.4 <= b - a <= 1.2]
    if len(strides) < 2:
        return None
    lt = np.array([row[0] for row in sim.log]) - DT
    c = np.array([row[3] for row in sim.log])
    labels = [row[1].split(":")[-1] for row in sim.log]
    pel = np.interp(lt, tj, np.degrees(r[:, 4]))
    phi = np.full(len(lt), np.nan)
    for a, b in strides:
        w = (lt >= a) & (lt < b)
        phi[w] = (lt[w] - a) / (b - a) * 100.0
    valid = ~np.isnan(phi)
    tg = np.zeros_like(c)
    tg[valid] = target.at(phi[valid], pel[valid] if target.follow_pelvis else None).T
    err = tg - c
    u = None
    if getattr(sim, "kcmd", None):
        kt = np.array([k[0] for k in sim.kcmd])
        ku = np.stack([k[1] for k in sim.kcmd])
        if getattr(sim, "kres", None) and len(sim.kres) == len(sim.kcmd):
            ku = ku + np.stack([k[1] for k in sim.kres])   # the command the knots set: tracks + residual
        u = np.stack([np.interp(lt, kt, ku[:, m]) for m in range(ku.shape[1])], axis=1)
    trans = []
    for k in range(1, len(labels)):
        if labels[k] != labels[k - 1]:
            g = plan.chunk_goal.get(labels[k - 1])
            if g is not None:
                trans.append((lt[k], g))
    K, nm = plan.K, c.shape[1]
    acc = {key: np.zeros((K, nm, S)) for key in ("c", "u", "tgt", "e")}
    n = np.zeros(K)
    dur = [[] for _ in range(K)]
    kph = [[] for _ in range(K)]
    lo, hi = strides[0][0], strides[-1][1]
    for (ta, ga), (tb, gb) in zip(trans, trans[1:]):
        k = plan.pos[ga]
        if plan.pos[gb] != (k + 1) % K or ta < lo or tb + lead >= hi:
            continue
        ts = ta + (tb - ta) * SGRID
        if not np.all(valid[np.clip(np.searchsorted(lt, np.append(ts, ts + lead)), 0, len(lt) - 1)]):
            continue
        for key, sig, shift in (("c", c, 0.0), ("tgt", tg, 0.0), ("e", err, lead), ("u", u, 0.0)):
            if sig is None:
                continue
            acc[key][k] += np.stack([np.interp(ts + shift, lt, sig[:, m]) for m in range(nm)])
        n[k] += 1
        dur[k].append(tb - ta)
        kph[k].append(float(phi[np.searchsorted(lt, ta)]))
    if np.any(n == 0):
        return None
    out = {key: v / n[:, None, None] for key, v in acc.items()}
    if u is None:
        del out["u"]
    out["n"] = n
    out["D"] = np.array([np.mean(d) for d in dur])
    out["phase"] = np.array([np.mean(p) for p in kph])
    out["n_strides"] = len(strides)
    out["period"] = float(np.mean([b - a for a, b in strides]))
    return out


def merge(anas):
    """Instance-weighted mean of several rollouts' event analyses."""
    anas = [a for a in anas if a is not None]
    if not anas:
        return None
    out = {}
    n = sum(a["n"] for a in anas)
    for key in ("c", "u", "tgt", "e"):
        if all(key in a for a in anas):
            out[key] = sum(a[key] * a["n"][:, None, None] for a in anas) / n[:, None, None]
    for key in ("D", "phase"):
        out[key] = sum(a[key] * a["n"] for a in anas) / n
    out["n"] = n
    out["n_strides"] = int(sum(a["n_strides"] for a in anas))
    out["period"] = float(np.mean([a["period"] for a in anas]))
    return out


METRIC_KEYS = ("time", "fell", "speed", "kin_rms", "event_rms", "kin_hip", "kin_knee", "kin_ankle", "kin_trunk",
               "kin_shoulder", "kin_elbow", "cadence", "contact_time", "duty_factor", "toe_off_pct", "peak_grf",
               "loading_rate", "trunk_lean", "pelvis_tilt", "v_osc", "in_band", "ref_speed_scored")
_BODY = {}


def rollout(job):
    """job = (target, params, seed, seconds, analyse[, lead]). Returns
    (metrics, event analysis or None)."""
    target, params, seed, seconds, analyse = job[:5]
    lead = job[5] if len(job) > 5 else 0.0
    ref_speed = job[6] if len(job) > 6 else None
    task = load_task(target)
    task.seed = seed
    p = {k: v for k, v in params.items() if not k.startswith("__")}
    if analyse:
        p["knot_trace"] = 1.0
    sim = KnotSim(task, params=p, controller=params.get("__controller", CONTROLLER))
    try:
        m = sim.run(seconds)
    except Exception as e:  # noqa: BLE001
        return {"error": str(e)[:300], "fell": True}, None
    met = {k: (float(m[k]) if isinstance(m.get(k), (int, float, np.floating, np.integer)) and not isinstance(m.get(k), bool)
               else m.get(k)) for k in METRIC_KEYS if k in m}
    ana = None
    if analyse and not m.get("fell") and m.get("speed"):
        if target not in _BODY:
            _BODY[target] = Body(target)
        v = ref_speed if ref_speed else m.get("ref_speed_scored", m.get("speed", 3.5))
        if target != "mocap":  # the task's reference is at the speed the skill announces
            v = params.get("speed", 3.5)
        tgt = Target(_BODY[target], reference(target, v))
        ana = event_analysis(sim, task, Plan(params), tgt, lead)
    return met, ana


def failed(met):
    """The arena's guards: a fall, or a speed outside the 3-4 m/s band."""
    return bool(met.get("fell") or "error" in met or not (3.0 <= met.get("speed", 0.0) <= 4.0))


def fitness(met):
    """The ES / ILC acceptance score (higher is better): the arena metric
    (kin_rms) with its guards priced in: a failed guard (a fall, a speed
    outside 3-4 m/s) -60, a speed in the band's outer 0.1 m/s -20 per m/s, a
    quarter of event_rms."""
    if "error" in met or met.get("kin_rms") is None:
        return -200.0
    f = -met["kin_rms"] - 0.25 * met.get("event_rms", 60.0)
    if failed(met):
        f -= 60.0
    v = met.get("speed", 0.0)
    f -= 20.0 * (max(0.0, 3.1 - v) + max(0.0, v - 3.9))
    return float(f)


def pool(workers):
    return mp.get_context("spawn").Pool(workers)


def parse_seeds(s):
    out = []
    for part in s.split(","):
        if part in ("none", "None", "clean"):
            out.append(None)
        elif "-" in part:
            a, b = part.split("-")
            out += list(range(int(a), int(b) + 1))
        else:
            out.append(int(part))
    return out


def run_batch(pl, target, params, seeds, seconds=30.0, analyse=False, lead=0.0, ref_speed=None):
    return pl.map(rollout, [(target, params, s, seconds, analyse, lead, ref_speed) for s in seeds], chunksize=1)


def batch_summary(res):
    ms = [m for m, _ in res]
    ok = [m for m in ms if not m.get("fell") and m.get("kin_rms") is not None]
    out = {"n": len(ms), "falls": sum(1 for m in ms if m.get("fell")), "fails": sum(1 for m in ms if failed(m)),
           "fitness": round(float(np.mean([fitness(m) for m in ms])), 3)}
    for k in ("kin_rms", "event_rms", "kin_hip", "kin_knee", "kin_ankle", "kin_trunk", "kin_shoulder", "kin_elbow",
              "speed", "peak_grf", "cadence", "contact_time", "toe_off_pct", "trunk_lean", "pelvis_tilt"):
        v = [m[k] for m in ok if isinstance(m.get(k), (int, float))]
        if v:
            out[k] = round(float(np.mean(v)), 3)
    return out


# ---------------------------------------------------------------------------
# commands


def cmd_fit(args):
    """The zero-rollout least-squares fit at the nominal event phases."""
    body = Body(args.target)
    base = read_params(args.base)
    plan = Plan(base)
    tgt = Target(body, reference(args.target, args.speed))
    Y, D = nominal_segments(plan, tgt, args.period)
    B = EventBasis(plan, D)
    A = B.matrix(body.mirror)
    y = to_rows(Y)
    rows = []
    for ridge in [float(r) for r in args.ridges.split(",")]:
        x = solve(A, y, B.scale(body.nm), ridge)
        e = from_rows(y - A @ x, plan.K, body.nm)
        rows.append({"ridge": ridge, "rms_c": float(np.sqrt(np.mean(e ** 2))), "deg": seg_deg(body, e)})
        print(json.dumps(rows[-1]))
    x = solve(A, y, B.scale(body.nm), args.ridge)
    nc = len(x) // 3
    xc = np.linalg.lstsq(A[:, :nc], y, rcond=None)[0]
    e0 = from_rows(y - A[:, :nc] @ xc, plan.K, body.nm)
    minjerk = {"rms_c": float(np.sqrt(np.mean(e0 ** 2))), "deg": seg_deg(body, e0)}
    print("min-jerk keyframes (v = a = 0, c fitted):", json.dumps(minjerk))
    e1 = from_rows(y - A @ x, plan.K, body.nm)
    x = x + stiffness_knots(base, plan, body)
    p = dict(base)
    p.update(unpack(x, plan, body))
    p["knots"] = 1.0
    write_params(args.out, p, f"runknots fit: {args.target}, least squares (ridge {args.ridge}), period {args.period} s, "
                 f"knots {plan.ids} at their nominal phases")
    json.dump({"target": args.target, "knots": plan.ids, "period": args.period, "ridge": args.ridge, "ridges": rows,
               "quintic": {"rms_c": float(np.sqrt(np.mean(e1 ** 2))), "deg": seg_deg(body, e1)},
               "minjerk": minjerk, "n_unknowns": len(x), "n_rows": int(len(y))},
              open(os.path.splitext(args.out)[0] + ".json", "w"), indent=1)
    print("wrote", args.out)


def cmd_eval(args):
    p = read_params(args.params)
    if args.controller:
        p["__controller"] = os.path.abspath(args.controller)
    seeds = parse_seeds(args.seeds)
    with pool(args.workers) as pl:
        res = run_batch(pl, args.target, p, seeds, args.seconds)
    for s, (m, _) in zip(seeds, res):
        print(s, json.dumps({k: m.get(k) for k in ("error", "time", "fell", "speed", "kin_rms", "event_rms", "kin_hip",
                                                    "kin_knee", "kin_ankle", "kin_trunk", "kin_shoulder", "peak_grf")}))
    print(json.dumps(batch_summary(res)))


def knots_of_command(body, plan, params, ana, ridge):
    """A knots-off rollout's own command (event-locked mean of the tracks'
    command) as knots on the basis of its gait: knots 1 with these vectors
    replays about the same command."""
    B = EventBasis(plan, ana["D"])
    A = B.matrix(body.mirror)
    x = solve(A, to_rows(ana["u"]), B.scale(body.nm), ridge)
    p = dict(params)
    p.update(unpack(x, plan, body))
    p["knots"] = 1.0
    return p, x


# ---------------------------------------------------------------------------
# role vectors in signed joint coordinates (variant C: TD + TO knots)


LEG_PAIRS = (("r_hip_flex", "l_hip_flex"), ("r_knee", "l_knee"), ("r_ankle", "l_ankle"), ("r_toe", "l_toe"))
ARM_PAIRS = (("r_shoulder_flex", "l_shoulder_flex"), ("r_elbow", "l_elbow"))


class JointKnots:
    """The knots as role vectors in signed joint coordinates: at each
    right-stance knot (the left step is its mirror, so the r_ columns are the
    stance / "back" leg's slot and the l_ columns the swing / "front" leg's,
    the r_ arm the stance-side arm's), per joint a signed angle q (+ = the
    pos muscle's side: flexion at hip, knee, shoulder, elbow, spine;
    PLANTARflexion at the ankle), its rate qd and acceleration qdd, and a
    co-contraction s. Muscles follow through the body's geometry, which is
    exactly linear: c = c0 + G q + H s, cd = G qd, cdd = G qdd (G: each
    muscle's contraction per radian of each joint it crosses, biarticular
    ones included; H: half the co-contraction of the muscle's own joint).
    A positive q shortens the pos muscle and lengthens its antagonist: the
    pair is driven reciprocally; both only through s.

    tied: the swing slot's rate and acceleration are the stance slot's
    negated and scaled, plus a free residual: qd_sw = -g qd_st + r (Erik's
    alternating legs: the scissor at the hip; lead arm against trail arm),
    one g per joint pair (hip, knee, ankle, toe, shoulder, elbow) shared by
    both knots; the residuals are ridge-penalised."""

    def __init__(self, body, plan, tied=False, offset=False):
        self.body, self.plan, self.tied, self.offset = body, plan, tied, offset
        J = body.joints
        self.J = J
        nj = len(J)
        # a residual's knots are offsets: no rest contraction
        self.c0 = np.zeros(body.nm) if offset else body.contraction({})
        self.G = np.stack([(body.contraction({j: 0.05}) - body.contraction({j: -0.05})) / 0.1 for j in J], axis=1)
        prim = {"rf": "hip_flex", "ham": "hip_flex", "gas": "ankle"}
        self.H = np.zeros((body.nm, nj))
        for m, n in enumerate(body.names):
            grp = body.group[m]
            jn = None
            for j in J:
                if n.startswith(j + "_") or (grp in prim and n[:2] + prim[grp] == j):
                    jn = j
            self.H[m, J.index(jn)] = 0.5
        self.events = list(plan.knot_ids)
        self.pairs = [(J.index(a), J.index(b)) for a, b in LEG_PAIRS + ARM_PAIRS]
        self.swing = {b for _, b in self.pairs}
        names, kinds = [], []
        for e in self.events:
            for kind in ("q", "qd", "qdd", "s"):
                for k, j in enumerate(J):
                    if tied and kind in ("qd", "qdd") and k in self.swing:
                        names.append(f"jk_{e}_{kind}r_{j}")   # the free residual of a tied swing slot
                        kinds.append(kind + "r")
                    else:
                        names.append(f"jk_{e}_{kind}_{j}")
                        kinds.append(kind)
        if tied:
            for a, b in self.pairs:
                names.append(f"jk_g_{J[b][2:]}")
                kinds.append("g")
        self.names, self.kinds = names, np.array(kinds)
        self.n = len(names)
        self.index = {nm: i for i, nm in enumerate(names)}

    def full(self, th):
        """theta -> per event {kind: joint vector} with the tie applied."""
        th = np.asarray(th, float)
        out = {}
        J = self.J
        for e in self.events:
            d = {}
            for kind in ("q", "qd", "qdd", "s"):
                v = np.zeros(len(J))
                for k, j in enumerate(J):
                    nm = f"jk_{e}_{kind}_{j}"
                    if nm in self.index:
                        v[k] = th[self.index[nm]]
                if self.tied and kind in ("qd", "qdd"):
                    for (a, b) in self.pairs:
                        g = th[self.index[f"jk_g_{J[b][2:]}"]]
                        v[b] = -g * v[a] + th[self.index[f"jk_{e}_{kind}r_{J[b]}"]]
                d[kind] = v
            out[e] = d
        return out

    def decode(self, th):
        """theta -> muscle knots x [slot(kind, kid), muscle]."""
        nm = self.body.nm
        x = np.zeros(3 * len(self.plan.knot_ids) * nm)
        for e, d in self.full(th).items():
            x[self.plan.slot("c", e) * nm:(self.plan.slot("c", e) + 1) * nm] = self.c0 + self.G @ d["q"] + self.H @ d["s"]
            x[self.plan.slot("v", e) * nm:(self.plan.slot("v", e) + 1) * nm] = self.G @ d["qd"]
            x[self.plan.slot("a", e) * nm:(self.plan.slot("a", e) + 1) * nm] = self.G @ d["qdd"]
        return x

    def jacobian(self, th, eps=1e-6):
        """d x / d theta (exact for the free form, which is affine; the tied
        form is bilinear in g and the stance rates: central differences)."""
        th = np.asarray(th, float)
        cols = []
        for i in range(self.n):
            d = np.zeros(self.n)
            d[i] = eps
            cols.append((self.decode(th + d) - self.decode(th - d)) / (2 * eps))
        return np.stack(cols, axis=1)

    def scale(self, T):
        """One unit of each parameter: q 1 rad, qd 1 / (0.19 T), qdd
        1 / (0.0173 T^2) (their residuals the same), s 0.2, g 1."""
        per = {"q": 1.0, "qd": 1.0 / (0.19 * T), "qdd": 1.0 / (0.0173 * T * T), "s": 0.2, "g": 1.0}
        per["qdr"], per["qddr"] = per["qd"], per["qdd"]
        return np.array([per[k] for k in self.kinds])

    def from_free(self, free, th_free):
        """A tied theta equal to a free one (g from the stance / swing rates'
        least-squares ratio, the residuals the rest): both start as the same
        knots."""
        th = np.zeros(self.n)
        fd = free.full(th_free)
        J = self.J
        for i, nm in enumerate(self.names):
            if nm in free.index:
                th[i] = th_free[free.index[nm]]
        for a, b in self.pairs:
            num = sum(-fd[e][k][b] * fd[e][k][a] for e in self.events for k in ("qd", "qdd"))
            den = sum(fd[e][k][a] ** 2 for e in self.events for k in ("qd", "qdd")) + 1e-12
            g = max(0.0, num / den)
            th[self.index[f"jk_g_{J[b][2:]}"]] = g
            for e in self.events:
                for k in ("qd", "qdd"):
                    th[self.index[f"jk_{e}_{k}r_{J[b]}"]] = fd[e][k][b] + g * fd[e][k][a]
        return th

    def init_theta(self, g0=1.0):
        """Zero knots; a tied form's gains at g0 (Erik's prior: the swing slot
        mirrors the stance slot's rates)."""
        th = np.zeros(self.n)
        for i, k in enumerate(self.kinds):
            if k == "g":
                th[i] = g0
        return th

    def reg(self, ridge, tie_ridge):
        """Ridge per parameter kind (scaled units): none on positions, `ridge`
        on rates, accelerations and co-contraction, `tie_ridge` on a tied
        slot's free residuals (small by construction), a little on g."""
        per = {"q": 1e-9, "qd": ridge, "qdd": ridge, "s": ridge, "qdr": tie_ridge, "qddr": tie_ridge, "g": 1e-3}
        return np.array([per[k] for k in self.kinds])

    def role(self, g_stance, g_swing, g_upper, g_spine, toe_gain):
        """Learning gain per parameter: its slot's role (at a right-stance
        knot the r_ leg is the stance slot), toes times toe_gain; a pair's g
        follows its swing slot (legs) or the arms."""
        out = []
        for nm in self.names:
            j = nm.split("_", 3)[-1] if not nm.startswith("jk_g_") else nm[5:]
            if nm.startswith("jk_g_"):
                out.append(g_upper if j in ("shoulder_flex", "elbow") else g_swing)
                continue
            if j == "spine_flex":
                g = g_spine
            elif j.endswith(("shoulder_flex", "elbow")):
                g = g_upper
            else:
                g = g_stance if j.startswith("r_") else g_swing
            out.append(g * (toe_gain if j.endswith("toe") else 1.0))
        return np.array(out)

    def to_params(self, th):
        return {nm: float(v) for nm, v in zip(self.names, th)}

    def from_params(self, params):
        return np.array([params.get(nm, 0.0) for nm in self.names])


def solve_reg(M, y, scale, reg):
    """argmin_z ||M (scale z) - y||^2 + sum reg z^2; returns scale z."""
    Ms = M * scale[None, :]
    A = np.vstack([Ms, np.diag(np.sqrt(reg))])
    z = np.linalg.lstsq(A, np.concatenate([np.ravel(y), np.zeros(len(scale))]), rcond=None)[0]
    return z * scale


def joint_knots_of_command(body, plan, params, ana, ridge, tied):
    """A 3-chunk source's mean command as two-knot joint-space knots (the free
    fit; the tied form starts equal to it)."""
    B = EventBasis(plan, ana["D"])
    A = B.matrix(body.mirror)
    free = JointKnots(body, plan, False)
    T = float(np.mean(ana["D"]))
    M = A @ free.jacobian(np.zeros(free.n))
    x0 = free.decode(np.zeros(free.n))
    reg = np.where(np.isin(free.kinds, ["qd", "qdd"]), ridge, 1e-9)
    th = solve_reg(M, to_rows(ana["u"]) - A @ x0, free.scale(T), reg)
    jk = JointKnots(body, plan, True).from_free(free, th) if tied else th
    jko = JointKnots(body, plan, tied)
    p = dict(params)
    p.update(jko.to_params(jk))
    p.update(unpack(jko.decode(jk), plan, body))
    p["knots"] = 1.0
    p["knot_clock"] = 0.0
    p.update(kind_durations(plan, ana["D"]))
    return p, jko, jk


class JsonLog:
    def __init__(self, path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.f = open(path, "a")

    def write(self, rec):
        self.f.write(json.dumps(rec) + "\n")
        self.f.flush()


def cmd_ilc(args):
    """Iterative learning control of the knots (see the module docstring)."""
    if args.k_speed > 0 and args.speed_knob == "speed" and args.target != "mocap":
        # run_natural and run_natural_erik score against the reference at the
        # speed the skill ANNOUNCES (its `speed`), so moving it would move the
        # target itself; only the mocap trial scores at the measured speed
        raise SystemExit(f"--speed_knob speed moves the {args.target} reference: use --k_speed 0 or --speed_knob cv")
    body = Body(args.target)
    base = read_params(args.base)
    for kv in (args.set or "").split(","):
        if kv:
            k, v = kv.split("=")
            base[k] = float(v)
    if args.controller:
        base["__controller"] = os.path.abspath(args.controller)
    plan = Plan(base)
    seeds = parse_seeds(args.seeds)
    out = args.out
    os.makedirs(out, exist_ok=True)
    log = JsonLog(os.path.join(out, "ilc.jsonl"))
    gains = np.ones(body.nm)
    for m in range(body.nm):
        if body.group[m] == "toe":
            gains[m] = args.toe_gain
    # per-role learning gains on the unknowns: at a right-stance knot the r_
    # leg muscles are the stance leg, the l_ leg muscles the swing leg (the
    # left step reads them mirrored), the spine and arms the upper body
    role = np.array([args.g_spine if body.group[m] == "spine" else args.g_upper if body.group[m] in ("shoulder", "elbow") else
                     args.g_stance if body.names[m].startswith("r_") else args.g_swing for m in range(body.nm)])
    role_gain = np.tile(role, 3 * len(plan.knot_ids))
    t0 = time.time()
    residual = args.mode == "residual"
    prefix = "r" if residual else "k"
    with pool(args.workers) as pl:
        if residual and base.get("knot_residual", 0.0) < 0.5:
            # the residual knot train starts at zero: the source controller exactly
            res = run_batch(pl, args.target, base, seeds, args.seconds, True)
            ana0 = merge([a for _, a in res])
            params = dict(base)
            params.update({"knot_residual": 1.0, "knot_clock": 0.0, "res_from": args.res_from, "res_ramp": args.res_ramp})
            if args.mid:
                params["knot_mid"] = 1.0
                plan = Plan(params)
                role_gain = np.tile(role, 3 * len(plan.knot_ids))
            params.update(kind_durations(plan, ana0["D"]))
            x = np.zeros(3 * len(plan.knot_ids) * body.nm)
            params.update(unpack(x, plan, body, prefix))
            log.write({"iter": "source", "summary": batch_summary(res), "D": list(map(float, ana0["D"]))})
        elif not residual and base.get("knots", 0.0) < 0.5:
            res = run_batch(pl, args.target, base, seeds, args.seconds, True)
            ana = merge([a for _, a in res])
            params, x = knots_of_command(body, plan, base, ana, args.ridge)
            s = batch_summary(res)
            log.write({"iter": "source", "summary": s, "wall": round(time.time() - t0, 1)})
            print("source (knots off):", json.dumps(s), flush=True)
        else:
            params = dict(base)
            x = pack(params, plan, body, prefix)
        jk = None
        if args.space == "joint":
            # role vectors in signed joint coordinates (JointKnots), tied or free
            jk = JointKnots(body, plan, args.tie > 0, offset=residual)
            th = jk.from_params(params) if any(nm in params for nm in jk.names) else jk.init_theta(args.g0)
            x = jk.decode(th)
            params.update(unpack(x, plan, body, prefix))
            params.update(jk.to_params(th))
            role_th = jk.role(args.g_stance, args.g_swing, args.g_upper, args.g_spine, args.toe_gain)
            log.write({"space": "joint", "tied": bool(args.tie), "n": jk.n, "names": jk.names})
        alpha = args.alpha
        res = run_batch(pl, args.target, params, seeds, args.seconds, True, args.lead, args.ref_speed)
        cur = batch_summary(res)
        ana = merge([a for _, a in res])
        best = (-cur.get("kin_rms", 99.0), dict(params), 0)
        write_params(os.path.join(out, "iter0.txt"), params, f"runknots ilc {args.target}: start")
        write_params(os.path.join(out, "best.txt"), params, f"runknots ilc {args.target}: start")
        it, tries = 0, 0
        while it < args.iters and tries < args.iters * 3:
            tries += 1
            if ana is None:
                print("no steady strides measured: stop", flush=True)
                break
            B = EventBasis(plan, ana["D"])
            A = B.matrix(body.mirror)
            sc = B.scale(body.nm)
            if residual:
                # the residual that would make the mean command the target
                u_base = ana["u"] - from_rows(A @ x, plan.K, body.nm)
                x_ls = solve(A, to_rows(ana["tgt"] - u_base), sc, args.ridge)
            else:
                x_ls = solve(A, to_rows(ana["tgt"]), sc, args.ridge) + stiffness_knots(params, plan, body)
            e = ana["e"] * gains[None, :, None]
            if jk is not None:
                T = float(np.mean(ana["D"]))
                M = A @ jk.jacobian(th)
                dth = solve_reg(M, to_rows(e), jk.scale(T), jk.reg(args.ridge, args.tie_ridge)) * role_th
                dx = None
            else:
                dx = solve(A, to_rows(e), sc, args.ridge) * role_gain
            u_now = from_rows(A @ x, plan.K, body.nm)
            u_ls = from_rows(A @ x_ls, plan.K, body.nm)
            nc = len(x) // 3
            rec = {"iter": it, "alpha": alpha, "summary": cur, "err_deg": seg_deg(body, ana["tgt"] - ana["c"]),
                   "knot_rms_c": float(np.sqrt(np.mean(x[:len(x) // 3] ** 2))),
                   "D": [round(float(d), 4) for d in ana["D"]], "phase": [round(float(p), 2) for p in ana["phase"]],
                   "period": round(ana["period"], 4), "n_seg": [int(v) for v in ana["n"]],
                   "knots_minus_ls_c_rms": float(np.sqrt(np.mean((x - x_ls)[:nc] ** 2))),
                   "cmd_minus_ls_deg": seg_deg(body, u_now - u_ls),
                   "cmd_minus_achieved_deg": seg_deg(body, ana["u"] - ana["c"]) if "u" in ana else None,
                   "wall": round(time.time() - t0, 1)}
            log.write(rec)
            print(f"it {it} a={alpha:.2f}: fails {cur['fails']}/{cur['n']} (falls {cur['falls']}) kin {cur.get('kin_rms')} "
                  f"ev {cur.get('event_rms')} v {cur.get('speed')} trunk {cur.get('trunk_lean')} fit {cur['fitness']} | "
                  f"err {rec['err_deg']} | cmd-LS {rec['cmd_minus_ls_deg']} | |x_c| {rec['knot_rms_c']:.4f}", flush=True)
            p_new = dict(params)
            if jk is not None:
                th_new = th + alpha * dth
                x_new = jk.decode(th_new)
                p_new.update(jk.to_params(th_new))
                rec_g = {nm: round(float(v), 3) for nm, v in zip(jk.names, th) if nm.startswith("jk_g_")}
                if rec_g:
                    log.write({"iter": it, "g": rec_g})
            else:
                x_new = x + alpha * dx
            p_new.update(unpack(x_new, plan, body, prefix))
            # scalar loops: the speed through the placement gain cv, the mean
            # trunk lean through the torso servo's target (lean)
            # (stepped with the same alpha as the knots: a rejected step halves them too)
            if args.k_speed > 0 and cur.get("speed"):
                dv = args.v_target - cur["speed"]
                if args.speed_knob == "cv":
                    # Raibert's placement gain: the landing foot further back
                    # while the body runs below v_des
                    p_new["cv"] = float(np.clip(params.get("cv", 0.1) + alpha * args.k_speed * dv, 0.0, 0.8))
                else:
                    # the design speed v_des (the stride runs about 0.6 of a
                    # change of it); not scaled down with alpha
                    p_new["speed"] = float(np.clip(params.get("speed", 3.5) + args.k_speed * dv, 3.0, 4.5))
            if args.k_lean > 0 and cur.get("trunk_lean") is not None:
                rv = p_new.get("speed", 3.5) if args.target != "mocap" else cur.get("speed", 3.5)
                tm = reference(args.target, rv).trunk(np.arange(100.0)).mean()
                dl = tm - cur["trunk_lean"]
                p_new["lean"] = float(np.clip(params.get("lean", 0.0) + alpha * args.k_lean * dl, -8.0, 20.0))
            res_new = run_batch(pl, args.target, p_new, seeds, args.seconds, True, args.lead, args.ref_speed)
            new = batch_summary(res_new)
            # acceptance: the kinematics (over the runs that stayed up) did
            # not get worse, the speed stays inside the band's margin, and
            # the guard failures stay below a cap. Which of 12 perturbed starts
            # fall is close to a lottery at the runner's base rate (the
            # champion falls on 6 of 24 held-out starts), so fall counts on
            # the training starts only veto catastrophic steps.
            ok = (new["fails"] <= args.max_falls and new.get("kin_rms", 99.0) <= cur.get("kin_rms", 99.0) + args.tol
                  and 3.1 <= new.get("speed", 0.0) <= 3.9)
            if cur.get("speed", 0.0) < args.v_restore:
                # a speed-restoring step (the speed loop's knob moved) is
                # judged on the speed alone: the kinematics are then relearnt
                # at the new operating point
                ok = new["fails"] <= args.max_falls and args.v_restore <= new.get("speed", 0.0) <= 3.9
            if ok:
                params, x, cur = p_new, x_new, new
                if jk is not None:
                    th = th_new
                ana = merge([a for _, a in res_new]) or ana
                it += 1
                alpha = min(args.alpha_max, alpha * 1.25)
                write_params(os.path.join(out, f"iter{it}.txt"), params, f"runknots ilc {args.target}: iteration {it}")
                if -cur.get("kin_rms", 99.0) > best[0]:
                    best = (-cur.get("kin_rms", 99.0), dict(params), it)
                    write_params(os.path.join(out, "best.txt"), params,
                                 f"runknots ilc {args.target}: best training kin_rms {cur.get('kin_rms')} at iteration {it}")
            else:
                log.write({"iter": it, "rejected": new, "alpha": alpha})
                print(f"   rejected (fails {new['fails']}, fit {new['fitness']}, kin {new.get('kin_rms')}, v {new.get('speed')}): "
                      f"alpha {alpha:.2f} -> {alpha / 2:.2f}", flush=True)
                alpha /= 2
                if alpha < args.alpha_min:
                    print("alpha below minimum: stop", flush=True)
                    break
    print(f"best kin_rms {-best[0]} at iteration {best[2]} ({time.time() - t0:.0f}s)", flush=True)


# ---------------------------------------------------------------------------
# knots + residual TCN, jointly, by raw-difference ES (P6's recipe)


TCN_JOINTS = ("l_hip_flex", "l_knee", "l_ankle", "r_hip_flex", "r_knee", "r_ankle", "spine_flex")  # run_knots.w's
PROBE_SEEDS = list(range(6201, 6213))
VALID_SEEDS = list(range(6301, 6325))
HIDDEN_SCALE = 10.0


def _record_features(job):
    target, params, seed = job
    from convkf import Layout, TraceSim
    task = load_task(target)
    task.seed = seed
    sim = TraceSim(task, params={k: v for k, v in params.items() if not k.startswith("__")},
                   controller=params.get("__controller", CONTROLLER))
    sim.run(30.0)
    lay = Layout(sim)
    return [lay.features([float(t) for t in line.split()[1:]]) for line in sim.s_lines]


def tcn_setup(pl, target, params, seed=0, hidden=4, tmax=0.15, seeds=(None, 7001, 7002)):
    """The TCN's settings: input normalisation (mean and sd of each input over
    rollouts of `params`), architecture and initial weights (hidden layers
    N(0, 1 / fan_in), head zero: it adds nothing until trained)."""
    from convkf import Arch, init_weights
    feats = pl.map(_record_features, [(target, params, s) for s in seeds], chunksize=1)
    X = np.array([f for fs in feats for f in fs])
    mu, sd = X.mean(axis=0), X.std(axis=0)
    sd = np.where(sd < 1e-6, 1.0, sd)
    out = {"tcn": 1.0, "tcn_hidden": float(hidden), "tcn_max": tmax}
    for i in range(X.shape[1]):
        out[f"tcn_mu{i}"] = float(mu[i])
        out[f"tcn_sd{i}"] = float(sd[i])
    arch = Arch(out, X.shape[1], len(TCN_JOINTS))
    w = init_weights(arch, seed)
    out.update({f"tcn_w{k}": float(v) for k, v in enumerate(w)})
    return out, arch


class Rep:
    """theta -> params: x0 + scale * theta over the residual knots (a
    contraction by 1, a velocity by 1 / (0.19 T), an acceleration by
    1 / (0.0173 T^2), T the mean segment duration) and the TCN weights (a
    head weight by 1, a hidden weight by HIDDEN_SCALE)."""

    def __init__(self, base, plan, body, arch=None, knots=True, T=0.12):
        self.base = dict(base)
        names, x0, scale, group = [], [], [], []
        if knots:
            for kind, sc in (("c", 1.0), ("v", 1.0 / (0.19 * T)), ("a", 1.0 / (0.0173 * T * T))):
                for kid in plan.knot_ids:
                    for n in body.names:
                        k = f"r{kind}_{kid}_{n}"
                        names.append(k)
                        x0.append(base.get(k, 0.0))
                        scale.append(sc)
                        group.append("knot_" + kind)
        if arch is not None:
            head = arch.count() - (arch.hidden * arch.nout + arch.nout)
            for k in range(arch.count()):
                names.append(f"tcn_w{k}")
                x0.append(base[f"tcn_w{k}"])
                scale.append(1.0 if k >= head else HIDDEN_SCALE)
                group.append("tcn_head" if k >= head else "tcn_hidden")
        self.names, self.x0, self.scale, self.group = names, np.array(x0), np.array(scale), np.array(group)
        self.n = len(names)

    def decode(self, theta):
        p = dict(self.base)
        p.update({n: float(v) for n, v in zip(self.names, self.x0 + self.scale * np.asarray(theta))})
        return p

    def counts(self):
        return {g: int(np.sum(self.group == g)) for g in dict.fromkeys(self.group)}


def probe_summary(res):
    s = batch_summary(res)
    s["mean_fitness"] = s.pop("fitness")
    return s


def cmd_train(args):
    from convkf import ES
    body = Body(args.target)
    base = read_params(args.base)
    plan = Plan(base)
    out = args.out
    os.makedirs(out, exist_ok=True)
    log = JsonLog(os.path.join(out, "log.jsonl"))
    t0 = time.time()
    ckpt = os.path.join(out, "checkpoint.npz")
    resume = args.resume and os.path.exists(ckpt)
    with pool(args.workers) as pl:
        arch = None
        if args.tcn:
            if resume:  # the TCN settings of the run being continued
                from convkf import Arch
                tp = read_params(os.path.join(out, "tcn_init.txt"))
                arch = Arch(tp, sum(1 for k in tp if k.startswith("tcn_mu")), len(TCN_JOINTS))
            else:
                tp, arch = tcn_setup(pl, args.target, base, args.seed, args.hidden, args.tcn_max)
                write_params(os.path.join(out, "tcn_init.txt"), tp, "runknots train: TCN normalisation and initial weights")
            base.update(tp)
        T = float(np.mean([base.get(k, 0.12) for k in ("kt_load", "kt_drive", "kt_fly")]))
        rep = Rep(base, plan, body, arch, knots=args.knots, T=T)
        opt = ES(rep.n, args.seed, args.sigma, args.lr, args.pairs, "raw", 1)
        meta = {"target": args.target, "base": args.base, "n": rep.n, "groups": rep.counts(), "sigma": args.sigma,
                "lr": args.lr, "pairs": args.pairs, "budget": args.budget, "probe_seeds": PROBE_SEEDS}
        json.dump(meta, open(os.path.join(out, "meta.json"), "w"), indent=1)
        print(f"train {args.target}: {rep.n} dims {rep.counts()}", flush=True)
        used, next_probe, best = 0, 0, None
        if resume:  # continue in place: the ES state, the rollout count, the best probe so far
            z = np.load(ckpt)
            opt.theta, opt.mo, opt.v = z["theta"].copy(), z["mo"].copy(), z["v"].copy()
            opt.t, opt.gen = int(z["t"]), int(z["gen"])
            used, next_probe = int(z["used"]), int(z["next_probe"])
            best = (float(z["best_f"]), z["best_theta"].copy(), int(z["best_at"]))
            print(f"resumed at {used} rollouts, gen {opt.gen}, best probe {best[0]}", flush=True)

        def probe(tag):
            nonlocal best
            th = opt.centre().copy()
            res = run_batch(pl, args.target, rep.decode(th), PROBE_SEEDS, args.seconds)
            s = probe_summary(res)
            log.write({"probe": s, "rollouts": used, "gen": opt.gen, "tag": tag, "wall": round(time.time() - t0, 1)})
            if best is None or s["mean_fitness"] > best[0]:
                best = (s["mean_fitness"], th, used)
                np.save(os.path.join(out, "best_probe_theta.npy"), th)
                write_params(os.path.join(out, "best_probe.txt"), rep.decode(th),
                             f"runknots train {args.target}: best probe centre ({s['mean_fitness']}) at {used} rollouts")
            print(f"  probe @{used}: {json.dumps(s)}", flush=True)

        while True:
            if used >= next_probe:
                probe("periodic")
                next_probe += args.probe_every
            X, starts = opt.ask()
            if used + len(X) > args.budget:
                break
            seeds = [300000 + st[0] for st in starts]   # each pair's two members from one fresh start
            res = pl.map(rollout, [(args.target, rep.decode(x), sd, args.seconds, False) for x, sd in zip(X, seeds)],
                         chunksize=1)
            f = [fitness(m) for m, _ in res]
            opt.tell(f)
            used += len(X)
            th = opt.centre()
            rec = {"gen": opt.gen, "rollouts": used, "f_mean": float(np.mean(f)), "f_max": float(np.max(f)),
                   "falls": int(sum(1 for m, _ in res if m.get("fell"))), "wall": round(time.time() - t0, 1),
                   "step": {g: float(np.linalg.norm(th[rep.group == g])) for g in rep.counts()}}
            log.write(rec)
            np.savez(ckpt, theta=opt.theta, mo=opt.mo, v=opt.v, t=opt.t, gen=opt.gen, used=used, next_probe=next_probe,
                     best_f=best[0], best_theta=best[1], best_at=best[2])
            if opt.gen % 5 == 0:
                print(f"  gen {opt.gen} @{used}: f {rec['f_mean']:.3f} (max {rec['f_max']:.3f}), falls {rec['falls']}/{len(X)}, "
                      f"|theta| {json.dumps({k: round(v, 4) for k, v in rec['step'].items()})} ({rec['wall']:.0f}s)", flush=True)
        if args.final:
            probe("final")
    if not args.final:
        print(f"chunk done at {used} rollouts (gen {opt.gen}); continue with --resume 1", flush=True)
        return
    np.save(os.path.join(out, "final_theta.npy"), opt.centre())
    write_params(os.path.join(out, "final.txt"), rep.decode(opt.centre()), f"runknots train {args.target}: final centre, {used} rollouts")
    json.dump({**meta, "used": used, "best_probe": best[0], "best_probe_at": best[2], "wall": time.time() - t0},
              open(os.path.join(out, "summary.json"), "w"), indent=1)
    print(f"done: {used} rollouts, best probe {best[0]} at {best[2]}", flush=True)


# ---------------------------------------------------------------------------
# rendering: the run with the reference ghosted at the current stride phase


def cmd_render(args):
    from render import Recorder
    from tasks.run_natural import write_gif, JOINTS
    p = read_params(args.params)
    task = load_task(args.target)
    task.seed = args.seed
    ref = reference(args.target, args.speed)
    names = {"mocap": "Fukuchi 2017 mocap", "lit": "literature curves", "erik3": "Erik's keyframe set 3"}
    state = {"tds": [], "on": False}
    rgba = (0.25, 0.55, 1.0, 0.33)

    def ghost_pose(sim):
        d = sim.d
        on = task.jrec[-1][2] > 0.5 if task.jrec else False
        if on and not state["on"]:
            state["tds"].append(d.time)
        state["on"] = on
        tds = state["tds"]
        state["phase"] = None
        if len(tds) < 3:
            return None
        period = float(np.mean(np.diff(tds[-4:])))
        ph = ((d.time - tds[-1]) / period * 100.0) % 100.0
        state["phase"] = ph
        q = np.array(d.qpos, float).copy()
        for j in JOINTS:
            if j == "spine_flex":
                v = float(ref.trunk(ph) - ref.pelvis(ph))
            else:
                v = float(np.asarray(ref.joint(j, ph)))
            q[task.qadr[j]] = math.radians(v)
        q[task.pitch_adr] = math.radians(float(ref.pelvis(ph)))
        return q, rgba

    def hud_text(m, d):
        ph = state.get("phase")
        tail = f"   ghost: {names[args.target]} at {ph:4.0f} % of the stride" if ph is not None else ""
        return f"x = {d.body('pelvis').xpos[0] + 50:5.1f} m{tail}"

    task.ghost_pose = ghost_pose
    task.hud_text = hud_text
    task.title = lambda: args.title or f"robolab P7: knot-train runner vs {names[args.target]} (v2 anatomy)"
    sim = KnotSim(task, params={k: v for k, v in p.items() if not k.startswith("__")}, controller=args.controller or CONTROLLER)
    rec = Recorder(sim)
    res = sim.run(args.seconds, recorder=rec)
    print(json.dumps({k: res.get(k) for k in METRIC_KEYS if k in res}))
    if args.video:
        first = max(0, len(rec.frames) - int(args.clip * rec.fps))
        rec.frames = rec.frames[first:]
        rec.write_mp4(args.video)
    if args.gif:
        span = min(args.gif_s, args.seconds)
        first = max(0, len(rec.frames) - int(span * rec.fps))
        mb = write_gif(rec.frames, args.gif, rec.fps, first, int(span * rec.fps))
        print("wrote", args.gif, f"{mb:.2f} MB")


# ---------------------------------------------------------------------------
# report data: stride-averaged joint cycles against the reference


def _cycle_job(job):
    target, params, seed, seconds = job
    task = load_task(target)
    task.seed = seed
    sim = Sim(task, params={k: v for k, v in params.items() if not k.startswith("__")},
              controller=params.get("__controller", CONTROLLER))
    m = sim.run(seconds)
    return {k: m.get(k) for k in METRIC_KEYS if k in m}, (m.get("cycle") if not m.get("fell") else None)


def cmd_cycles(args):
    """Stride-averaged joint cycles (the metric's own, 101 samples) of several
    controllers over the same starts, with the reference: for the P7 figure."""
    from tasks.run_natural import JOINTS
    seeds = parse_seeds(args.seeds)
    out = {"target": args.target, "seeds": args.seeds, "runs": {}}
    with pool(args.workers) as pl:
        for spec in args.params:
            label, path = spec.split("=", 1)
            p = read_params(path)
            if ":" in label:
                label, ctl = label.split(":", 1)
                p["__controller"] = os.path.join(ROOT, ctl)
            res = pl.map(_cycle_job, [(args.target, p, s, args.seconds) for s in seeds], chunksize=1)
            cyc = [c for _, c in res if c]
            mean = {k: np.mean([c[k] for c in cyc], axis=0).tolist() for k in cyc[0]} if cyc else {}
            out["runs"][label] = {"params": path, "summary": batch_summary([(m, None) for m, _ in res]), "cycle": mean,
                                  "speed": float(np.mean([m.get("speed", 0.0) for m, _ in res]))}
            print(label, json.dumps(out["runs"][label]["summary"]), flush=True)
    v = float(np.mean([r["speed"] for r in out["runs"].values()]))
    speed = v if args.target == "mocap" else 3.5
    ref = reference(args.target, speed)
    ph = np.linspace(0.0, 100.0, 101)
    out["reference"] = {j: np.asarray(ref.joint(j, ph), float).tolist() for j in JOINTS}
    out["reference"]["trunk"] = np.asarray(ref.trunk(ph), float).tolist()
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    json.dump(out, open(args.out, "w"), indent=1)
    print("wrote", args.out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("fit")
    f.add_argument("--target", default="mocap", choices=sorted(TARGETS))
    f.add_argument("--base", default=CHAMPION)
    f.add_argument("--speed", type=float, default=3.5)
    f.add_argument("--period", type=float, default=0.714)
    f.add_argument("--ridge", type=float, default=1e-3)
    f.add_argument("--ridges", default="1e-6,1e-3,1e-1")
    f.add_argument("--out", required=True)
    e = sub.add_parser("eval")
    e.add_argument("--target", default="mocap", choices=sorted(TARGETS))
    e.add_argument("--params", required=True)
    e.add_argument("--controller")
    e.add_argument("--seeds", default="clean,7001-7005")
    e.add_argument("--seconds", type=float, default=30.0)
    e.add_argument("--workers", type=int, default=3)
    i = sub.add_parser("ilc")
    i.add_argument("--target", default="mocap", choices=sorted(TARGETS))
    i.add_argument("--mode", default="residual", choices=["residual", "knots"])
    i.add_argument("--base", default=CHAMPION)
    i.add_argument("--seeds", default="clean,7001-7005")
    i.add_argument("--seconds", type=float, default=30.0)
    i.add_argument("--iters", type=int, default=20)
    i.add_argument("--alpha", type=float, default=0.5)
    i.add_argument("--alpha_max", type=float, default=1.0)
    i.add_argument("--alpha_min", type=float, default=0.03)
    i.add_argument("--lead", type=float, default=0.05, help="read the error this many seconds ahead (the servo lag)")
    i.add_argument("--ridge", type=float, default=1e-3)
    i.add_argument("--toe_gain", type=float, default=0.5)
    i.add_argument("--g_stance", type=float, default=1.0)
    i.add_argument("--g_swing", type=float, default=1.0)
    i.add_argument("--g_upper", type=float, default=1.0)
    i.add_argument("--g_spine", type=float, default=1.0)
    i.add_argument("--k_speed", type=float, default=1.0, help="knob change per m/s of speed error")
    i.add_argument("--speed_knob", default="speed", choices=["speed", "cv"])
    i.add_argument("--v_restore", type=float, default=3.15, help="below this speed a step is judged on the speed alone")
    i.add_argument("--ref_speed", type=float, default=None, help="the reference's speed (default: each run's measured)")
    i.add_argument("--res_from", type=float, default=6.0, help="the residual fades in from this time (s)")
    i.add_argument("--res_ramp", type=float, default=4.0)
    i.add_argument("--mid", type=int, default=0, help="knots between the events too (knot_mid)")
    i.add_argument("--set", default="", help="extra fixed params for the start, k=v,k=v")
    i.add_argument("--controller", help="controller binary (default bin/robolab_run_knots)")
    i.add_argument("--space", default="muscle", choices=["muscle", "joint"], help="knots per muscle, or role vectors in signed joint coordinates")
    i.add_argument("--tie", type=int, default=0, help="joint space: swing slot rates = -g x stance slot's + a residual")
    i.add_argument("--tie_ridge", type=float, default=1.0)
    i.add_argument("--g0", type=float, default=1.0)
    i.add_argument("--v_target", type=float, default=3.45)
    i.add_argument("--k_lean", type=float, default=1.0, help="lean change per degree of mean trunk error (times alpha)")
    i.add_argument("--max_falls", type=int, default=4, help="most guard failures (of the training starts) a step may have")
    i.add_argument("--tol", type=float, default=0.05, help="kin_rms may rise this much in a step")
    i.add_argument("--workers", type=int, default=3)
    i.add_argument("--out", required=True)
    t = sub.add_parser("train")
    t.add_argument("--target", default="mocap", choices=sorted(TARGETS))
    t.add_argument("--base", required=True)
    t.add_argument("--tcn", type=int, default=1)
    t.add_argument("--knots", type=int, default=1)
    t.add_argument("--hidden", type=int, default=4)
    t.add_argument("--tcn_max", type=float, default=0.15)
    t.add_argument("--sigma", type=float, default=0.0015)
    t.add_argument("--lr", type=float, default=0.0002)
    t.add_argument("--pairs", type=int, default=16)
    t.add_argument("--budget", type=int, default=3200)
    t.add_argument("--probe_every", type=int, default=384)
    t.add_argument("--seconds", type=float, default=30.0)
    t.add_argument("--seed", type=int, default=1)
    t.add_argument("--workers", type=int, default=3)
    t.add_argument("--resume", type=int, default=0, help="continue the run in --out from its checkpoint (--budget: the total)")
    t.add_argument("--final", type=int, default=1, help="0: a chunk of a longer run (no final probe or summary)")
    t.add_argument("--out", required=True)
    r = sub.add_parser("render")
    r.add_argument("--target", default="mocap", choices=sorted(TARGETS))
    r.add_argument("--params", required=True)
    r.add_argument("--controller")
    r.add_argument("--seed", type=int, default=None)
    r.add_argument("--speed", type=float, default=3.5)
    r.add_argument("--seconds", type=float, default=30.0)
    r.add_argument("--clip", type=float, default=12.0, help="seconds of the end kept in the video")
    r.add_argument("--gif_s", type=float, default=5.0)
    r.add_argument("--title")
    r.add_argument("--video")
    r.add_argument("--gif")
    c = sub.add_parser("cycles")
    c.add_argument("--target", default="mocap", choices=sorted(TARGETS))
    c.add_argument("--params", nargs="+", required=True, help="label[:controller]=params.txt ...")
    c.add_argument("--seeds", default="clean,7101-7105")
    c.add_argument("--seconds", type=float, default=30.0)
    c.add_argument("--workers", type=int, default=3)
    c.add_argument("--out", required=True)
    a = ap.parse_args()
    {"fit": cmd_fit, "eval": cmd_eval, "ilc": cmd_ilc, "train": cmd_train, "render": cmd_render,
     "cycles": cmd_cycles}[a.cmd](a)


if __name__ == "__main__":
    main()
