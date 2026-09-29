"""Natural running scored against Erik's keyframes: run_natural (v2 body,
standing start, 3-4 m/s band, same metrics and practice score) with the
reference moved through the keyframe targets Erik sets in the Keyframe Bench
(https://claude.ai/artifact/HvFRzvSmo8esj7A2ELnxng, "Copy params": lines
ref_<td|ms|to>_<key> in degrees, right stance; see tasks/run_natural.py
Reference(keyframes=...)).

The keyframes come from ROBOLAB_RN_KEYFRAMES (default params/keyframes_erik.txt).
The arena trial `run_natural_erik` pins a frozen copy
(playground/arena/params/keyframes_erik-<stamp>.txt), because Erik keeps
editing the live file: a new keyframe set is a new trial, not a changed one.

The metric only moves the REFERENCE (at every keyframe: TD / MS / TO at the
measured gait events, extra keyframes such as hr / kl at their phase of the
stride-averaged cycle). For the skill to aim at the same
keyframes, the params file must carry the same ref_* lines (a build of
RunNaturalSkill with the override, round 2 on); a controller without them
runs the literature keyframes and is scored against Erik's.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # run as a script too
from bridge import ROOT  # noqa: E402
from tasks.run_natural import RunNaturalTask, read_keyframes  # noqa: E402


def pose_error(metrics, terms):
    """Sum over (event, role) terms of |achieved - target| (deg), each the
    mean of the right and left steps' keyframes; 40 per term when the run
    measured no keyframes (a fall), 0 for events the set does not have."""
    kfs = metrics.get("keyframes")
    total = 0.0
    for ev, role in terms:
        if not kfs:
            total += 40.0
            continue
        rows = [kfs.get(s + "_" + ev, {}).get(role) for s in ("R", "L")]
        rows = [r for r in rows if r]
        if rows:
            total += sum(abs(r[1] - r[0]) for r in rows) / len(rows)
    return total


def loading_rate(rec, tail_s=5.0, window=0.01, after=0.05):
    """Mean over the steps of the last `tail_s` seconds of each step's peak
    vertical loading rate (BW/s, `window` differences of the summed foot
    force) in the first `after` seconds after contact. The round-1 runner
    measures ~80, e2b's forefoot slam ~240."""
    import numpy as np
    if len(rec) < 50:
        return 0.0
    r = np.array([(row[0], row[7], float(row[3]), float(row[4])) for row in rec])
    t, g, lc, rc = r[:, 0], r[:, 1], r[:, 2] > 0.5, r[:, 3] > 0.5
    dt = float(t[1] - t[0])
    k = max(1, int(round(window / dt)))
    rates = []
    for c in (lc, rc):
        on = np.nonzero(c[1:] & ~c[:-1])[0] + 1
        for i in on:
            if t[i] < t[-1] - tail_s or i + k >= len(t):
                continue
            j = min(len(t) - 1, i + int(round(after / dt)))
            seg = g[i:j + 1]
            if len(seg) > k:
                rates.append(float(np.max(seg[k:] - seg[:-k])) / (k * dt))
    return round(float(np.mean(rates)), 1) if rates else 0.0


def keyframes_path():
    p = os.environ.get("ROBOLAB_RN_KEYFRAMES", os.path.join("params", "keyframes_erik.txt"))
    return p if os.path.isabs(p) else os.path.join(ROOT, p)


class PracticeExtras:
    """Practice-score terms shared by the keyframe-set tasks (mix in before
    RunNaturalTask): a speed margin, impact penalties, the defining poses and
    the upper body (trunk and shoulder cycle errors).
    They change only the practice score; the arena metric is kin_rms."""
    # practice only: the speed penalty starts at 3.2 m/s, a margin above the
    # arena guard's 3.0 (practice otherwise settles on the floor of the band)
    practice_v_lo = 3.2
    # practice only: impacts. Humans at 3-4 m/s peak at ~2.5-3 body weights
    # (sprinters ~4-5); a forefoot touchdown must not be bought with a slam.
    # run_natural's score charges 3 per BW above 4; this adds grf_k more, and
    # lr_k per BW/s of the mean per-step peak loading rate above lr_free.
    grf_k = 5.0
    # practice only: the poses that make a keyframe set what it is, charged
    # per degree of error at their keyframe (mean of both steps), so a search
    # cannot trade them for easier ones: the touchdown reach (stance hip) and
    # foot (stance ankle), the mid-stance knee yield, the knee drive (swing
    # hip and knee at kl, when the set has it). pose_k = 0 turns them off.
    pose_k = 0.3
    POSE_TERMS = (("TD", "st_hip_flex"), ("TD", "st_ankle"), ("MS", "st_knee"), ("KL", "sw_hip_flex"),
                  ("KL", "sw_knee"))
    lr_free = 100.0   # human vertical instantaneous loading rate ~70-100 BW/s at 3-4 m/s (rearfoot; forefoot lower)
    lr_k = 0.1
    # practice only: the upper body, so the leg pose terms are not bought
    # with a leaning trunk or flailing arms (set 2's f2 stage: trunk 13 deg,
    # shoulder 21 deg cycle error): upper_k per degree of kin_trunk and of
    # kin_shoulder (on top of their share of kin_rms)
    upper_k = 0.3

    def metrics(self, m, d, log):
        out = super().metrics(m, d, log)
        out["loading_rate"] = loading_rate(self.rec)
        return out

    def score(self, metrics):
        s = super().score(metrics)
        if s <= -1e5:
            return s
        v = metrics.get("speed", 0.0)
        s -= 20.0 * max(0.0, self.practice_v_lo - max(v, self.speed_band[0]))
        s -= self.grf_k * max(0.0, metrics.get("peak_grf", 0.0) - 4.0)
        s -= self.lr_k * max(0.0, metrics.get("loading_rate", 0.0) - self.lr_free)
        s -= self.upper_k * (metrics.get("kin_trunk", 40.0) + metrics.get("kin_shoulder", 40.0))
        return s - self.pose_k * pose_error(metrics, self.POSE_TERMS)


class RunNaturalErikTask(PracticeExtras, RunNaturalTask):
    name = "run_natural_erik"
    controller = os.path.join(ROOT, "bin", "robolab_run_natural")

    def __init__(self):
        path = keyframes_path()
        if not os.path.exists(path):
            raise FileNotFoundError(f"run_natural_erik needs Erik's keyframes at {path} (ROBOLAB_RN_KEYFRAMES)")
        self.keyframes = read_keyframes(path)
        self.keyframes_file = path

    def title(self):
        return "robolab: natural run against Erik's keyframes (v2 anatomy)"


TASK = RunNaturalErikTask


if __name__ == "__main__":
    import tasks.run_natural as rn
    rn.RunNaturalTask = RunNaturalErikTask
    rn.main()
