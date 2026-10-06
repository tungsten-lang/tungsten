"""Round-4 replay helpers: closed-loop records of the baseline (btl3-e + final_e, servo in the loop), the stage triggers, and replays of a stage
with ADDITIVE offsets on the recorded activations of the stroking arm (the recorded activations already contain the table AND the servo's
contribution, so the replay at zero offset is the closed loop, bit for bit; the servo's reaction to an offset is not modelled).

    import rlib
    sd = rlib.StartData(seed, rec_path)            # a recorded start (one record covers the triggers of stages 0-3)
    out, summ = sd.run_stage(stage, dA)            # dA: dict table-muscle m (0..15) -> array of offsets per tick from the trigger tick

Stage ordinals: 0 the launch pass (right hand), 1 the left return, 2 the right return, 3 the left hand's second stroke (A4's reflex).
Table muscle m = 2 * joint + (0 pos, 1 neg) over POSTURE_JOINTS (as the skill's pg_mus).
"""
import os
import pickle
import sys

import numpy as np

sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")
sys.path.insert(0, "scratchpad/btl2")
import oracle_lib as O  # noqa: E402
import oracle_multi as M  # noqa: E402
import oracle_search as S  # noqa: E402

POSTURE_JOINTS = O.POSTURE_JOINTS
# ordinal: (hand, bounce number of the ball the stage works on, eval ticks)
STAGES = {0: ("r", 1), 1: ("l", 2), 2: ("r", 3), 3: ("l", 4)}
T_LO, T_HI, T_END = 1.35, 3.45, 4.35
LEAD = 0.165
DK = 0.05      # pg_dtk
NDT = 6        # pg_dtn
NEVAL = 160    # ticks replayed (0.8 s)


def record_start(job):
    """job = (seed, params_file, ctl, out_dir, t_hi, t_end): run the closed loop once and keep the record (pickled)."""
    seed, pfile, ctl, out_dir = job[:4]
    t_hi = job[4] if len(job) > 4 else T_HI
    t_end = job[5] if len(job) > 5 else T_END
    fn = os.path.join(out_dir, f"rec_{seed}.pkl")
    if os.path.exists(fn):
        return seed
    from common import load
    rec = O.record(seed, load(pfile), ctl, T_LO, t_end, t_last=t_hi)
    os.makedirs(out_dir, exist_ok=True)
    tmp = fn + f".{os.getpid()}"
    with open(tmp, "wb") as f:
        pickle.dump(rec, f, protocol=4)
    os.replace(tmp, fn)
    return seed


def arm_indices(names, side):
    """Indices (into the record's muscle order) of the stroking arm's 16 table muscles m = 2 * joint + (pos, neg)."""
    return [names.index(f"{side}_{jn}_{sg}") for jn in POSTURE_JOINTS for sg in ("pos", "neg")]


def offset_curve(table, shift, nticks):
    """The skill's pg_offset for a (16, NDT) knot table at ticks i = 0.. (te = i * 0.005 + shift): linear between knots DK apart, falling
    to zero after the last knot; returns (16, nticks)."""
    t = np.arange(nticks) * 0.005 + shift
    x = t / DK
    i = np.floor(x).astype(int)
    w = x - i
    out = np.zeros((table.shape[0], nticks))
    for k in range(nticks):
        if i[k] >= NDT:
            continue
        ik = max(i[k], 0)
        wk = w[k] if i[k] >= 0 else 0.0
        if ik + 1 >= NDT:
            out[:, k] = table[:, ik] * (1.0 - wk)
        else:
            out[:, k] = table[:, ik] * (1.0 - wk) + table[:, ik + 1] * wk
    return out


class StartData:
    def __init__(self, seed, path):
        self.seed = seed
        self.rec = pickle.load(open(path, "rb"))
        self.rp = O.Replay(self.rec)
        self.names = self.rec["names"]
        self.idx = {s: arm_indices(self.names, s) for s in "lr"}
        self.ks = {}
        self.shift = {}
        self.feat = {}
        for st, (hand, bn) in STAGES.items():
            ks = M.trigger_tick(self.rec, self.rp, bn, lead=LEAD)
            if ks is None or ks not in self.rec["snaps"]:
                continue
            self.ks[st] = ks

    def stage_features(self, st):
        """pg_fk's 18 features at the trigger tick (the controller's frame): predicted crossing x, y, then c(pos) - c(neg) and the rates for the 8 joints,
        plus the predicted time to the crossing."""
        if st in self.feat:
            return self.feat[st]
        hand, _ = STAGES[st]
        ks = self.ks[st]
        pc = self.rp.pred_cross(ks)
        self.rp.load(ks)
        c, cd, _ = self.rp.sim.contraction()
        c = c - cd * O.DT          # the frame's values are one physics step stale
        px, py, pt = pc[0], pc[1], pc[2]
        x = [px, py]
        for j in range(8):
            jn = POSTURE_JOINTS[j]
            ip, ineg = self.names.index(f"{hand}_{jn}_pos"), self.names.index(f"{hand}_{jn}_neg")
            x.append(float(c[ip] - c[ineg]))
        for j in range(8):
            jn = POSTURE_JOINTS[j]
            ip, ineg = self.names.index(f"{hand}_{jn}_pos"), self.names.index(f"{hand}_{jn}_neg")
            x.append(float(cd[ip] - cd[ineg]))
        self.feat[st] = (np.array(x), float(pt))
        return self.feat[st]

    def run_stage(self, st, table=None, shift=None, n=NEVAL):
        """Replay stage `st` from its trigger tick with (16, NDT) additive offset knots `table` (pg_dt style, zero if None). Returns (out, summary)."""
        hand, _ = STAGES[st]
        ks = self.ks[st]
        base = self.rec["acts"][ks:ks + n + 1]
        ov = None
        if table is not None:
            if shift is None:
                shift = LEAD - 0.0025 - self.stage_features(st)[1]
            cur = offset_curve(np.asarray(table, float), shift, n)
            ov = {}
            for m, mi in enumerate(self.idx[hand]):
                ov[mi] = np.clip(base[:n, mi] + cur[m], 0.0, 1.0)
        pc = 0 if hand == "l" else 1

        def stop(i, pos, vel, cf):
            if i < 20 or vel[i, 2] <= 0 or pos[i, 2] < 0.60:
                return False
            return bool(np.any(cf[:i + 1, pc] > 0.3)) and bool(np.any(cf[:i + 1, 2] > 0.2))

        out = self.rp.run(ov, ticks=n, start=ks, stop=stop, hand_col=pc)
        S.ARR["pre"] = st > 0
        J, summ = S.evaluate(out, "full", hand)
        summ["J"] = J
        return out, summ


def outcome_vec(summ):
    """The stage's release velocity (3), release position (3), bounce (2), arrival (2), apex (1); None if the stroke did not release a bounced ball.
    (Quantised by the tick of the last hand contact: use `smooth_outcomes` for finite differences.)"""
    if not summ.get("bounced"):
        return None
    return np.concatenate([summ["v"], summ["p"], np.array(summ["bounce"]), np.array(summ["arrive"]), [summ["apex"]]])


G = 9.81
R_BALL = 0.12


def smooth_outcomes(out, hand):
    """Outcomes of a replayed stroke that are smooth functions of the release state (no tick quantisation): the ball's pre-bounce velocity
    (vx, vy, vz), its bounce position extrapolated ballistically to the ball centre at the floor contact height (bx, by), and from the state
    three ticks after the first floor contact the rise's apex and the predicted rising crossing (ax, ay) of z 0.62.
    Returns (y (8), info) or (None, info) when the hand never touched / the ball never bounced / the stroke is not a clean release."""
    pos, vel, cf = out["pos"], out["vel"], out["cf"]
    pc = 0 if hand == "l" else 1
    n = len(pos)
    touch = np.nonzero(cf[:, pc] > 0.3)[0]
    if len(touch) == 0:
        return None, {"why": "no_touch"}
    first = touch[0]
    fl = np.nonzero(cf[first:, 2] > 0.2)[0]
    if len(fl) == 0:
        return None, {"why": "no_bounce"}
    b = first + fl[0]
    if b + 4 >= n or b < 2:
        return None, {"why": "short"}
    pb, vb = pos[b - 1], vel[b - 1]
    # time to fall to the ball-centre height at the floor contact: z0 + vz t - g t^2 / 2 = R  (vz < 0): t = (vz + sqrt(vz^2 + 2 g (z0 - R))) / g
    t = max((vb[2] + np.sqrt(max(vb[2] ** 2 + 2 * G * (pb[2] - R_BALL), 0.0))) / G, 0.0)
    bx, by = pb[0] + vb[0] * t, pb[1] + vb[1] * t
    p3, v3 = pos[b + 3], vel[b + 3]
    apex = p3[2] + max(v3[2], 0.0) ** 2 / (2 * G)
    disc3 = v3[2] ** 2 - 2 * G * (0.62 - p3[2])
    s = v3[2] / G if disc3 <= 0 else (v3[2] - np.sqrt(disc3)) / G
    ax, ay = p3[0] + v3[0] * s, p3[1] + v3[1] * s
    return np.array([vb[0], vb[1], vb[2], bx, by, ax, ay, apex]), {"b": int(b), "first": int(first)}
