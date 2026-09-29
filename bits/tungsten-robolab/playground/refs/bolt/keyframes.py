"""Usain Bolt sprint keyframes from side-view video (block start + max velocity).

Reproducible pipeline for the robolab sprint reference:

  1. pose     MediaPipe Tasks PoseLandmarker (heavy) on a moving crop that
              follows Bolt; raw landmarks cached in keypoints_<clip>.npz
  2. analyze  near/far limb assignment, smoothing, gait/block events,
              sagittal joint angles, keyframe statistics -> bolt_keyframes.json
  3. figure   stick figures + angle table -> ../../../out/bolt_keyframes.png
              (drawn from keypoints only; no video pixels)

Environment (from bits/tungsten-robolab):
  uv venv .venv-pose --python 3.12
  uv pip install --python .venv-pose/bin/python yt-dlp "mediapipe==0.10.14" opencv-python-headless \
      numpy scipy matplotlib pillow
  (mediapipe 1.0.x aborts on macOS with "graph_service ... Service is unavailable" from its Metal
  helper even with the CPU delegate; 0.10.14 works.)

Usage (from bits/tungsten-robolab):
  .venv-pose/bin/python playground/refs/bolt/keyframes.py pose [clip ...]
  .venv-pose/bin/python playground/refs/bolt/keyframes.py analyze
  .venv-pose/bin/python playground/refs/bolt/keyframes.py all

The clips themselves live in clips/ (gitignored, see SOURCES.md); only the
derived keypoints, numbers and drawings are kept. The PoseLandmarker model
file is looked up in $BOLT_POSE_MODEL (default: pose_landmarker_heavy.task
next to this script or in the working directory); download it from
https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task
"""

import json
import os
import sys
from dataclasses import dataclass, field

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROBOLAB = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
CLIPDIR = os.path.join(HERE, "clips")
OUT_JSON = os.path.join(HERE, "bolt_keyframes.json")
OUT_PNG = os.path.join(ROBOLAB, "out", "bolt_keyframes.png")

# ---------------------------------------------------------------------------
# Clip registry
# ---------------------------------------------------------------------------


@dataclass
class Segment:
    name: str
    f0: int  # first frame analysed (clip-local)
    f1: int  # last frame analysed (inclusive)
    bbox0: tuple  # (x0, y0, x1, y1) of Bolt at f0, full-frame pixels
    # rectangles (x0, y0, x1, y1) in which strongly red pixels (the red-clad
    # official standing behind the blocks) are greyed out before pose
    # estimation, so the detector cannot lock onto him instead of Bolt
    suppress_red: tuple = ()
    # optional hand-placed crop track [(frame, cx, cy, extent), ...] for clips
    # where Bolt is small, blurred and overlapped by other runners; the crop
    # follows the interpolated track and the pose nearest to it is kept
    track: tuple = ()


@dataclass
class Clip:
    key: str
    url: str
    title: str
    t0: float  # downloaded section start (s, source video time)
    t1: float
    fps: float  # container frame rate
    kind: str  # "blocks" or "run"
    segments: list
    step: int = 1  # analyse every `step`-th frame (2 = drop duplicated frames)
    slow: float = None  # slow-motion factor = capture fps / playback fps (None = unknown)
    near: str = "right"  # body side facing the camera
    # how the near leg is identified: "visibility" (MediaPipe visibility of the
    # knee/ankle tracks) or "rear_block" (the leg in the rear block, which for
    # a right-side view with the right foot back is the near leg)
    near_rule: str = "visibility"
    direction: int = 1  # +1 runner moves left->right in the image, -1 mirrored
    num_poses: int = 1
    # Bolt's kit, used to reject other people the detector may pick:
    # "dark" (all-black training kit) or "yellow" (Jamaica vest)
    torso_color: str = None
    color_penalty: float = 2.0  # selection cost added when the torso colour does not match
    sg_window: int = 7  # Savitzky-Golay window (analysed frames)
    note: str = ""
    # background band (y0, y1) used to measure camera pan by phase correlation;
    # None = rail/tracking camera, no ground-fixed x available
    cam_band: tuple = None
    mains_hz: float = None  # local mains frequency, for the light-flicker clock
    event: str = ""  # competition / session


CLIPS = {
    "nitro2017_blocks": Clip(
        key="nitro2017_blocks",
        url="https://www.youtube.com/watch?v=y11ZM6389Hg",
        title="Usain Bolt Rare Slow Motion Start Practice Nitro Athletics Feb 11th 2017",
        t0=0.0, t1=26.0, fps=30.0, kind="blocks",
        segments=[
            # rep1 ends at f211: the phone re-frames at f213
            Segment("rep1", 0, 211, (560, 420, 960, 790), suppress_red=((500, 250, 760, 720),)),
            Segment("rep3", 440, 722, (620, 410, 930, 710), suppress_red=((380, 300, 640, 700),)),
        ],
        slow=8.0, near="right", direction=1, num_poses=3, sg_window=7, torso_color="dark", near_rule="rear_block",
        cam_band=(150, 380), mains_hz=50.0, event="Nitro Athletics, Melbourne, 11 Feb 2017 (practice starts)",
        note="spectator phone, side view from the stands (slightly elevated, slightly behind);"
             " practice block starts before the 150 m; 240 fps capture played at 30 fps (8x, measured from the"
             " 100 Hz light flicker, see flicker_clock)",
    ),
    "daegu2011_maxv": Clip(
        key="daegu2011_maxv",
        url="https://www.youtube.com/watch?v=kKtn0EvRe4E",
        title="Usain Bolt Running Technique: Slow Motion Analysis of the Fastest Sprinter (posetv)",
        t0=8.0, t1=31.0, fps=59.94, kind="run",
        # frames 40-240 are the only unique pass; 275-510 and 960-1170 replay it
        segments=[Segment("pass1", 56, 240, (480, 170, 1100, 910))],
        slow=None, near="right", direction=1, num_poses=1, sg_window=9,
        event="IAAF World Championships Daegu 2011, 200 m preliminary round (bend start; hip number 4)",
        note="broadcast high-speed side tracking camera, Daegu 2011 World Championships;"
             " slow motion of unknown factor",
    ),
    "osaka2007_maxv": Clip(
        key="osaka2007_maxv",
        url="https://www.youtube.com/watch?v=lRMWjOxVWEQ",
        title="Tyson Gay & Usain Bolt sideview slo-mo (Osaka WC 2007 200m Final)",
        t0=1.0, t1=10.0, fps=25.0, kind="run",
        segments=[Segment("straight", 20, 186, (120, 120, 580, 680))],
        slow=None, near="right", direction=1, num_poses=2, sg_window=5, torso_color="yellow",
        event="IAAF World Championships Osaka 2007, 200 m final (Bolt 2nd, 19.91)",
        note="broadcast slow-motion side tracking camera, 200 m final home straight",
    ),
}

# MediaPipe landmark indices
L_SH, R_SH, L_EL, R_EL, L_WR, R_WR = 11, 12, 13, 14, 15, 16
L_HIP, R_HIP, L_KNEE, R_KNEE, L_ANK, R_ANK = 23, 24, 25, 26, 27, 28
L_HEEL, R_HEEL, L_TOE, R_TOE = 29, 30, 31, 32
LEG = {"L": [L_HIP, L_KNEE, L_ANK, L_HEEL, L_TOE], "R": [R_HIP, R_KNEE, R_ANK, R_HEEL, R_TOE]}
ARM = {"L": [L_SH, L_EL, L_WR], "R": [R_SH, R_EL, R_WR]}


def model_path():
    for p in [os.environ.get("BOLT_POSE_MODEL"), os.path.join(HERE, "pose_landmarker_heavy.task"),
              os.path.join(os.getcwd(), "pose_landmarker_heavy.task")]:
        if p and os.path.exists(p):
            return p
    sys.exit("pose model not found: set BOLT_POSE_MODEL to pose_landmarker_heavy.task")


# ---------------------------------------------------------------------------
# Stage 1: pose
# ---------------------------------------------------------------------------


def _crop(frame, cx, cy, side):
    """Square crop centred on (cx, cy), padded with black outside the frame."""
    import cv2

    h, w = frame.shape[:2]
    x0, y0 = int(round(cx - side / 2)), int(round(cy - side / 2))
    s = int(round(side))
    pad = max(0, -x0, -y0, x0 + s - w, y0 + s - h)
    if pad:
        frame = cv2.copyMakeBorder(frame, pad, pad, pad, pad, cv2.BORDER_CONSTANT, value=(0, 0, 0))
    c = frame[y0 + pad:y0 + pad + s, x0 + pad:x0 + pad + s]
    return c, x0, y0, s


def _torso_matches(frame, a, color):
    """Sample the torso (shoulder-mid to hip-mid line) and test Bolt's kit colour."""
    import cv2

    sh, hp = a[[L_SH, R_SH], :2].mean(0), a[[L_HIP, R_HIP], :2].mean(0)
    pix = []
    for t in np.linspace(0.15, 0.7, 6):
        px, py = (sh + t * (hp - sh)).astype(int)
        if 3 <= px < frame.shape[1] - 3 and 3 <= py < frame.shape[0] - 3:
            pix.append(frame[py - 3:py + 4, px - 3:px + 4].reshape(-1, 3))
    if not pix:
        return False
    pix = np.concatenate(pix).astype(np.uint8)
    if color == "dark":
        return pix.mean() < 85
    hsv = cv2.cvtColor(pix[None], cv2.COLOR_BGR2HSV)[0]
    yellow = (hsv[:, 0] >= 15) & (hsv[:, 0] <= 40) & (hsv[:, 1] > 90) & (hsv[:, 2] > 90)
    return yellow.mean() > 0.3


def run_pose(clip, verbose=True):
    """MediaPipe PoseLandmarker on a crop that tracks Bolt; returns raw arrays."""
    import cv2
    import mediapipe as mp
    from mediapipe.tasks import python as mpt
    from mediapipe.tasks.python import vision

    cap = cv2.VideoCapture(os.path.join(CLIPDIR, clip.key + ".mp4"))
    out = {"frame": [], "lm": [], "world": [], "bbox": [], "seg": [], "cost": []}
    for si, seg in enumerate(clip.segments):
        opts = vision.PoseLandmarkerOptions(
            base_options=mpt.BaseOptions(model_asset_path=model_path(), delegate=mpt.BaseOptions.Delegate.CPU),
            running_mode=vision.RunningMode.VIDEO, num_poses=clip.num_poses,
            min_pose_detection_confidence=0.3, min_pose_presence_confidence=0.3,
            min_tracking_confidence=0.3)
        lmk = vision.PoseLandmarker.create_from_options(opts)
        x0, y0, x1, y1 = seg.bbox0
        cx, cy, ext = (x0 + x1) / 2, (y0 + y1) / 2, max(x1 - x0, y1 - y0)
        vx = vy = 0.0
        cap.set(cv2.CAP_PROP_POS_FRAMES, seg.f0)
        fi = seg.f0
        while fi <= seg.f1:
            ok, frame = cap.read()
            if not ok:
                break
            if (fi - seg.f0) % clip.step:
                fi += 1
                continue
            for rx0, ry0, rx1, ry1 in seg.suppress_red:
                roi = frame[ry0:ry1, rx0:rx1].astype(np.int32)
                red = (roi[..., 2] > 110) & (roi[..., 2] > 1.6 * roi[..., 1]) & (roi[..., 2] > 1.6 * roi[..., 0])
                roi[red] = (150, 150, 150)
                frame[ry0:ry1, rx0:rx1] = roi.astype(np.uint8)
            pcx, pcy = cx + vx, cy + vy
            if seg.track:
                tr = np.array(seg.track, float)
                pcx, pcy, ext = (np.interp(fi, tr[:, 0], tr[:, k]) for k in (1, 2, 3))
            side = 1.9 * ext
            crop, ox, oy, s = _crop(frame, pcx, pcy, side)
            crop = cv2.resize(crop, (512, 512), interpolation=cv2.INTER_AREA if s > 512 else cv2.INTER_CUBIC)
            img = mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(crop, cv2.COLOR_BGR2RGB))
            res = lmk.detect_for_video(img, int(round(fi * 1000.0 / clip.fps)))
            best, bcost = None, 1e9
            for k, pl in enumerate(res.pose_landmarks):
                a = np.array([[p.x * s + ox, p.y * s + oy, p.z * s, p.visibility, p.presence] for p in pl])
                core = a[[L_SH, R_SH, L_HIP, R_HIP], :2].mean(0)
                e = max(np.ptp(a[:, 0]), np.ptp(a[:, 1]))
                bb = np.array([a[:, 0].min(), a[:, 1].min(), a[:, 0].max(), a[:, 1].max()])
                cc = (bb[:2] + bb[2:]) / 2
                cost = np.hypot(*(cc - (pcx, pcy))) / ext + 0.7 * abs(np.log(max(e, 1) / ext))
                if clip.torso_color and not _torso_matches(frame, a, clip.torso_color):
                    cost += clip.color_penalty
                if cost < bcost:
                    w = np.array([[q.x, q.y, q.z] for q in res.pose_world_landmarks[k]])
                    best, bcost, bbest, wbest = a, cost, bb, w
            if best is not None and bcost < 1.2:
                ncx, ncy = (bbest[0] + bbest[2]) / 2, (bbest[1] + bbest[3]) / 2
                next_ = max(bbest[2] - bbest[0], bbest[3] - bbest[1])
                vx, vy = 0.5 * vx + 0.5 * (ncx - cx), 0.5 * vy + 0.5 * (ncy - cy)
                cx, cy = 0.3 * pcx + 0.7 * ncx, 0.3 * pcy + 0.7 * ncy
                ext = 0.7 * ext + 0.3 * next_
                out["lm"].append(best)
                out["world"].append(wbest)
                out["bbox"].append(bbest)
            else:
                cx, cy = pcx, pcy
                out["lm"].append(np.full((33, 5), np.nan))
                out["world"].append(np.full((33, 3), np.nan))
                out["bbox"].append(np.full(4, np.nan))
            out["frame"].append(fi)
            out["seg"].append(si)
            out["cost"].append(bcost)
            if verbose and (fi - seg.f0) % 50 == 0:
                print(f"  {clip.key}/{seg.name} f{fi} cost={bcost:.2f} ext={ext:.0f}", flush=True)
            fi += 1
        lmk.close()
    cap.release()
    return {k: np.array(v) for k, v in out.items()}


def npz_path(key):
    return os.path.join(HERE, f"keypoints_{key}.npz")


def cmd_pose(keys):
    for key in keys or CLIPS:
        clip = CLIPS[key]
        print(f"pose {key}", flush=True)
        raw = run_pose(clip)
        np.savez_compressed(npz_path(key), raw_frame=raw["frame"], raw_lm=raw["lm"], raw_world=raw["world"],
                            raw_bbox=raw["bbox"], raw_seg=raw["seg"], raw_cost=raw["cost"],
                            fps=clip.fps, step=clip.step)
        ok = np.isfinite(raw["lm"][:, 0, 0]).mean()
        print(f"  {len(raw['frame'])} frames, pose found in {100 * ok:.0f}%", flush=True)


# ---------------------------------------------------------------------------
# Stage 2a: limb identity (near/far), cleaning, smoothing
# ---------------------------------------------------------------------------


def to_runner(p_img, direction, tilt_deg):
    """Image pixels (x right, y down) -> runner coordinates (x forward, y up, lane level)."""
    q = np.asarray(p_img, float).copy()
    q[..., 0] *= direction
    q[..., 1] *= -1.0
    c, s = np.cos(np.radians(-tilt_deg)), np.sin(np.radians(-tilt_deg))
    x, y = q[..., 0].copy(), q[..., 1].copy()
    q[..., 0], q[..., 1] = c * x - s * y, s * x + c * y
    return q


def from_runner(p, direction, tilt_deg):
    q = np.asarray(p, float).copy()
    c, s = np.cos(np.radians(tilt_deg)), np.sin(np.radians(tilt_deg))
    x, y = q[..., 0].copy(), q[..., 1].copy()
    q[..., 0], q[..., 1] = c * x - s * y, s * x + c * y
    q[..., 1] *= -1.0
    q[..., 0] *= direction
    return q


def ground_tilt(clip, seg, lm):
    """Slope of the lane lines at the athlete's feet (deg, after mirroring, y up).

    Long near-horizontal Hough lines in a band around the median foot height
    of the segment, sampled on 8 frames; the median slope is the image angle of
    the running direction, removed by rotating all coordinates.
    """
    import cv2

    cap = cv2.VideoCapture(os.path.join(CLIPDIR, clip.key + ".mp4"))
    H = cap.get(cv2.CAP_PROP_FRAME_HEIGHT)
    foot_y = np.nanmedian(np.nanmax(lm[:, [L_HEEL, R_HEEL, L_TOE, R_TOE], 1], axis=1))
    leg = np.nanmedian(np.linalg.norm(lm[:, R_HIP, :2] - lm[:, R_ANK, :2], axis=1))
    y0, y1 = int(max(0, foot_y - 0.3 * leg)), int(min(H - 4, foot_y + 0.4 * leg))
    angs = []
    for fi in np.linspace(seg.f0, seg.f1, 8).astype(int):
        cap.set(cv2.CAP_PROP_POS_FRAMES, fi)
        ok, img = cap.read()
        if not ok:
            continue
        g = cv2.cvtColor(img[y0:y1], cv2.COLOR_BGR2GRAY)
        lines = cv2.HoughLinesP(cv2.Canny(g, 60, 160), 1, np.pi / 720, 80, minLineLength=int(0.8 * leg), maxLineGap=20)
        for l in ([] if lines is None else lines.reshape(-1, 4)):
            xa, ya, xb, yb = (int(v) for v in l)
            a = np.degrees(np.arctan2(-(yb - ya), xb - xa)) * clip.direction
            if 0.05 < abs(a) < 8:
                angs.append(a)
    cap.release()
    return float(np.median(angs)) if angs else 0.0


def camera_shift(clip, seg, frames, tilt):
    """Cumulative camera pan at each analysed frame, in runner coordinates (px).

    Handheld clips only (clip.cam_band set): phase correlation of a background
    band between consecutive frames. A panning (rotating) phone shifts near and
    far background alike, so subtracting this shift gives ground-fixed
    coordinates. Returns zeros for tracking/rail cameras (cam_band None).
    """
    T = len(frames)
    if clip.cam_band is None:
        return np.zeros((T, 2))
    import cv2

    cap = cv2.VideoCapture(os.path.join(CLIPDIR, clip.key + ".mp4"))
    f0, f1 = int(frames[0]), int(frames[-1])
    cap.set(cv2.CAP_PROP_POS_FRAMES, f0)
    y0, y1 = clip.cam_band
    prev = win = None
    acc = np.zeros(2)
    shift = {}
    for f in range(f0, f1 + 1):
        ok, img = cap.read()
        if not ok:
            break
        g = cv2.cvtColor(img[y0:y1], cv2.COLOR_BGR2GRAY).astype(np.float32)
        if win is None:
            win = cv2.createHanningWindow((g.shape[1], g.shape[0]), cv2.CV_32F)
        if prev is not None:
            (sx, sy), _ = cv2.phaseCorrelate(prev, g, win)
            acc = acc + (sx, sy)
        shift[f] = acc.copy()
        prev = g
    cap.release()
    img = np.array([shift.get(int(f), (np.nan, np.nan)) for f in frames])
    return to_runner(img, clip.direction, tilt) - to_runner(np.zeros(2), clip.direction, tilt)


def _stance_anchors(xy, cam, leg_len, gap=0.15, near=0.06):
    """Label-free limb identity for block starts from ground contacts.

    Ground-fixed toe points (camera pan removed) that stay put for 3 frames are
    contact samples. They form clusters along the lane: rear block, front block,
    step 1, step 2, ... Each successive location belongs to the other leg
    (rear, front, rear, ...). Wherever a labelled toe sits on one of those
    locations during its occupation window, its MediaPipe label is pinned to
    that leg. Returns ({frame_index: swap}, clusters) with swap=False meaning
    the LEFT label is the rear-block leg.
    """
    T = len(xy)
    G = np.stack([xy[:, L_TOE] - cam, xy[:, R_TOE] - cam], 1)  # (T, 2 labels, 2)
    pts = []
    for t in range(1, T - 1):
        for k in (0, 1):
            p = G[t, k]
            if not np.isfinite(p).all():
                continue
            still = True
            for dt in (-1, 1):
                q = G[t + dt]
                dd = np.linalg.norm(q - p, axis=1)
                if not np.nanmin(np.where(np.isfinite(dd), dd, np.inf)) < 0.03 * leg_len:
                    still = False
            if still:
                pts.append((p[0], t))
    clusters = []
    if pts:
        pts.sort()
        cur = [pts[0]]
        for q in pts[1:]:
            if q[0] - cur[-1][0] > gap * leg_len:
                clusters.append(cur)
                cur = [q]
            else:
                cur.append(q)
        clusters.append(cur)
    clusters = [c for c in clusters if len(c) >= 6]
    cl = [{"x": float(np.median([q[0] for q in c])), "t0": min(q[1] for q in c), "t1": max(q[1] for q in c),
           "n": len(c)} for c in clusters]
    anchors = {}
    for j, c in enumerate(cl):
        rear = j % 2 == 0
        for t in range(c["t0"], c["t1"] + 1):
            d = np.abs(G[t, :, 0] - c["x"])
            hit = np.isfinite(d) & (d < near * leg_len)
            if hit.sum() != 1:
                continue
            k = int(np.argmax(hit))  # 0 = LEFT label on this location
            left_is_rear = (k == 0) == rear
            anchors[t] = not left_is_rear
    return anchors, cl


def _viterbi_swap(A, B, cap, lam, anchors=None):
    """Second-order Viterbi over a per-frame left/right swap flag.

    A, B: (T, P, 2) positions of the two MediaPipe-labelled limbs (NaN allowed).
    Each frame either keeps or swaps the labels; the cost is the distance of
    every point from its constant-velocity prediction (capped at `cap`), plus
    `lam` per label switch. Returns the swap flags (T,) bool; frames with
    missing data keep s=False.
    """
    T = len(A)
    ok = np.isfinite(A).all((1, 2)) & np.isfinite(B).all((1, 2))
    idx = np.where(ok)[0]
    s = np.zeros(T, bool)
    if len(idx) < 3:
        return s
    X = np.stack([np.stack([A[i], B[i]]) for i in idx])  # (K, 2, P, 2)
    Xs = X[:, ::-1]
    V = [X, Xs]

    def d(u, v):
        return np.minimum(np.linalg.norm(u - v, axis=-1), cap).sum()

    K = len(idx)
    D = np.full((K, 2, 2), np.inf)
    bp = np.zeros((K, 2, 2), int)
    pos = {int(t): k for k, t in enumerate(idx)}
    forced = {}
    for t, sw in (anchors or {}).items():
        if t in pos:
            forced[pos[t]] = int(sw)

    def bad(k, c):
        return k in forced and forced[k] != c

    for a in (0, 1):
        for b in (0, 1):
            D[1, a, b] = d(V[b][1], V[a][0]) + lam * (a != b) + (np.inf if bad(1, b) or bad(0, a) else 0)
    for k in range(2, K):
        r = (idx[k] - idx[k - 1]) / max(idx[k - 1] - idx[k - 2], 1)
        for b in (0, 1):
            for c in (0, 1):
                best, arg = np.inf, 0
                for a in (0, 1):
                    pred = V[b][k - 1] + r * (V[b][k - 1] - V[a][k - 2])
                    v = D[k - 1, a, b] + d(V[c][k], pred) + lam * (c != b) + (np.inf if bad(k, c) else 0)
                    if v < best:
                        best, arg = v, a
                D[k, b, c], bp[k, b, c] = best, arg
    b, c = np.unravel_index(np.argmin(D[K - 1]), (2, 2))
    st = np.zeros(K, int)
    st[K - 1], st[K - 2] = c, b
    for k in range(K - 1, 1, -1):
        a = bp[k, st[k - 1], st[k]]
        st[k - 2] = a
    s[idx] = st.astype(bool)
    return s


def _interp_smooth(x, window, poly, max_gap):
    """Fill NaN gaps up to max_gap samples, then Savitzky-Golay per contiguous run."""
    from scipy.signal import savgol_filter

    x = x.copy()
    n = len(x)
    good = np.isfinite(x)
    if good.sum() < 2:
        return x
    t = np.arange(n)
    gi = np.where(good)[0]
    filled = np.interp(t, gi, x[gi])
    # only fill short interior gaps
    gap_ok = np.zeros(n, bool)
    gap_ok[good] = True
    for a, b in zip(gi[:-1], gi[1:]):
        if 1 < b - a <= max_gap + 1:
            gap_ok[a + 1:b] = True
    x = np.where(gap_ok, filled, np.nan)
    out = np.full(n, np.nan)
    runs = np.split(np.arange(n), np.where(np.diff(np.isfinite(x)))[0] + 1)
    for r in runs:
        if not np.isfinite(x[r[0]]):
            continue
        if len(r) >= window:
            out[r] = savgol_filter(x[r], window, poly)
        else:
            out[r] = x[r]
    return out


@dataclass
class Track:
    """Cleaned, smoothed sagittal keypoints of one segment, in runner coordinates.

    Coordinates: x forward (+ = running direction), y up, in pixels.
    Limb arrays are (T, k, 2); legs = [hip, knee, ankle, heel, toe],
    arms = [shoulder, elbow, wrist].
    """
    clip: str
    seg: str
    frame: np.ndarray
    near_leg: np.ndarray
    far_leg: np.ndarray
    near_arm: np.ndarray
    far_arm: np.ndarray
    hip_mid: np.ndarray
    sh_mid: np.ndarray
    vis_near_leg: np.ndarray
    vis_far_leg: np.ndarray
    leg_len: float  # hip-ankle length of the straight leg, px
    near_margin: float  # visibility margin that decided near vs far
    swaps_leg: int
    swaps_arm: int
    raw_near_leg: np.ndarray = None
    raw_far_leg: np.ndarray = None
    tilt: float = 0.0  # lane-line slope in the image (deg, y up) removed by rotation
    direction: int = 1
    cam: np.ndarray = None  # camera pan (runner coords, px) to subtract for ground-fixed positions
    contact_sites: list = field(default_factory=list)

    def to_image(self, p):
        """Runner coordinates -> image pixels (inverse of to_runner)."""
        return from_runner(p, self.direction, self.tilt)


def build_tracks(clip, raw):
    """Near/far limb assignment + cleaning + smoothing for each segment."""
    tracks = []
    for si, seg in enumerate(clip.segments):
        m = (raw["raw_seg"] == si) & (raw["raw_frame"] >= seg.f0) & (raw["raw_frame"] <= seg.f1)
        fr = raw["raw_frame"][m]
        lm = raw["raw_lm"][m].copy()  # (T, 33, 5): x, y, z, vis, presence
        T = len(fr)
        tilt = ground_tilt(clip, seg, lm)
        xy = to_runner(lm[:, :, :2], clip.direction, tilt)
        vis = lm[:, :, 3]
        # body scale: robust max of projected thigh+shank length
        segl = []
        for side in "LR":
            h, k, a = LEG[side][:3]
            segl.append(np.linalg.norm(xy[:, h] - xy[:, k], axis=1) + np.linalg.norm(xy[:, k] - xy[:, a], axis=1))
        leg_len = float(np.nanpercentile(np.concatenate(segl), 90))
        # Limb identity. MediaPipe's left/right labels flicker in side views and
        # sometimes put both labels on one physical limb. Frames where the two
        # labelled knees+ankles (elbows+wrists) coincide within 0.1 leg lengths
        # are dropped, then a Viterbi pass over the ankle/heel/toe (elbow/wrist)
        # trajectories picks the label swaps that make both limbs move smoothly.
        def collapsed(a_idx, b_idx):
            d = np.linalg.norm(xy[:, a_idx] - xy[:, b_idx], axis=2).max(1)
            return d < 0.1 * leg_len

        c_leg = collapsed([L_KNEE, L_ANK], [R_KNEE, R_ANK])
        c_arm = collapsed([L_EL, L_WR], [R_EL, R_WR])
        for idx in LEG["L"][1:] + LEG["R"][1:]:
            xy[c_leg, idx] = np.nan
        for idx in ARM["L"][1:] + ARM["R"][1:]:
            xy[c_arm, idx] = np.nan
        A, B = xy[:, LEG["L"][2:]], xy[:, LEG["R"][2:]]
        cam = camera_shift(clip, seg, fr, tilt)
        anchors, contact_sites = (_stance_anchors(xy, cam, leg_len) if clip.kind == "blocks" else (None, []))
        sl = _viterbi_swap(A, B, cap=0.4 * leg_len, lam=0.02 * leg_len, anchors=anchors)
        Aa, Ba = xy[:, ARM["L"][1:]], xy[:, ARM["R"][1:]]
        sa = _viterbi_swap(Aa, Ba, cap=0.4 * leg_len, lam=0.02 * leg_len)
        t0 = {"leg": xy[:, LEG["L"]].copy(), "arm": xy[:, ARM["L"]].copy()}
        t1 = {"leg": xy[:, LEG["R"]].copy(), "arm": xy[:, ARM["R"]].copy()}
        v0 = {"leg": vis[:, LEG["L"]].copy(), "arm": vis[:, ARM["L"]].copy()}
        v1 = {"leg": vis[:, LEG["R"]].copy(), "arm": vis[:, ARM["R"]].copy()}
        for part, sw in (("leg", sl), ("arm", sa)):
            a, b = t0[part][sw].copy(), t1[part][sw].copy()
            t0[part][sw], t1[part][sw] = b, a
            a, b = v0[part][sw].copy(), v1[part][sw].copy()
            v0[part][sw], v1[part][sw] = b, a
        # near = the track MediaPipe sees as more visible (knee/ankle; elbow/wrist),
        # or for block starts (near_rule="rear_block") the leg whose foot is
        # further back in the set position (the rear-block leg), see Clip.near_rule
        res = {}
        margin = {}
        for part, pts in (("leg", [1, 2]), ("arm", [1, 2])):
            m0, m1 = np.nanmean(v0[part][:, pts]), np.nanmean(v1[part][:, pts])
            near_is_1 = m1 >= m0
            margin[part] = float(abs(m1 - m0))
            res[part] = (t1[part], t0[part], v1[part], v0[part]) if near_is_1 else (t0[part], t1[part], v0[part], v1[part])
        if clip.near_rule == "rear_block":
            # the stance anchors made track 0 the rear-block leg
            res["leg"] = (t0["leg"], t1["leg"], v0["leg"], v1["leg"])
            margin["leg"] = float(len(anchors) / max(T, 1))  # fraction of frames pinned
        # outlier removal: points jumping away from a running median
        from scipy.ndimage import median_filter

        def clean(arr):
            arr = arr.copy()
            for j in range(arr.shape[1]):
                for c in range(2):
                    x = arr[:, j, c]
                    g = np.isfinite(x)
                    if g.sum() < 5:
                        continue
                    med = x.copy()
                    med[g] = median_filter(x[g], size=5, mode="nearest")
                    bad = g & (np.abs(x - med) > 0.12 * leg_len)
                    arr[bad, j, c] = np.nan
            return arr

        def smooth(arr):
            out = np.empty_like(arr)
            for j in range(arr.shape[1]):
                for c in range(2):
                    out[:, j, c] = _interp_smooth(arr[:, j, c], clip.sg_window, 3 if clip.sg_window >= 7 else 2, 6)
            return out

        nl, fl, vnl, vfl = res["leg"]
        na, fa, _, _ = res["arm"]
        raw_nl, raw_fl = nl.copy(), fl.copy()
        nl, fl, na, fa = (smooth(clean(q)) for q in (nl, fl, na, fa))
        hip_mid = smooth(clean(xy[:, [L_HIP, R_HIP]].mean(1, keepdims=True)))[:, 0]
        sh_mid = smooth(clean(xy[:, [L_SH, R_SH]].mean(1, keepdims=True)))[:, 0]
        tracks.append(Track(clip.key, seg.name, fr, nl, fl, na, fa, hip_mid, sh_mid, vnl, vfl, leg_len,
                            margin["leg"], int(np.sum(np.diff(sl.astype(int)) != 0)),
                            int(np.sum(np.diff(sa.astype(int)) != 0)), raw_nl, raw_fl, tilt, clip.direction,
                            cam, contact_sites))
    return tracks


# ---------------------------------------------------------------------------
# Stage 2b: angles (degrees, conventions in CONVENTIONS)
# ---------------------------------------------------------------------------

CONVENTIONS = {
    "frame": "2D sagittal image coordinates, x = running direction (clip mirrored if needed), y = up",
    "trunk": "pitch of hip-midpoint -> shoulder-midpoint line from vertical, + = forward lean (upright 0, horizontal 90)",
    "thigh": "hip->knee angle from straight down, + = knee forward of hip",
    "shank": "knee->ankle angle from straight down, + = ankle forward of knee",
    "hip": "thigh relative to trunk line = thigh + trunk (0 in line, + flexion, - extension)",
    "knee": "flexion = 180 - interior hip-knee-ankle angle (0 = straight)",
    "ankle": "angle(shank vector knee-ankle, foot vector heel->foot_index) - 90, + = plantarflexion, 0 = neutral standing foot",
    "shoulder": "upper arm (shoulder->elbow) relative to trunk downward direction (shoulder->hip), + = arm forward (flexion)",
    "elbow": "flexion = 180 - interior shoulder-elbow-wrist angle",
    "roles_run": "st_ = stance leg / leg whose event it is, sw_ = contralateral leg; st_shoulder/st_elbow = arm on the stance-leg side",
    "roles_mkl": "maxv_mkl: sw_ = leg at maximum thigh flexion (the knee-lift leg), st_ = contralateral leg at that instant",
    "roles_blocks": "front_ = leg in the front block, rear_ = leg in the rear block; front_shoulder = arm on the front-leg side",
    "foot_ahead": "(stance ankle x - hip-midpoint x) at touchdown / leg length (hip-ankle, straight leg)",
    "heights": "set-position hip / shoulder height above the hand line (wrists on the track) / leg length",
}


def _ang_from_down(v):
    """Angle of vector v from straight down, + = forward (x>0)."""
    return np.degrees(np.arctan2(v[..., 0], -v[..., 1]))


def _interior(a, b, c):
    u, w = a - b, c - b
    cosang = (u * w).sum(-1) / (np.linalg.norm(u, axis=-1) * np.linalg.norm(w, axis=-1))
    return np.degrees(np.arccos(np.clip(cosang, -1, 1)))


def _wrap(a):
    return (a + 180.0) % 360.0 - 180.0


def angles(tr):
    """Per-frame angle arrays for the near and far limbs of a Track."""
    trunk_v = tr.sh_mid - tr.hip_mid
    trunk = np.degrees(np.arctan2(trunk_v[:, 0], trunk_v[:, 1]))
    out = {"trunk": trunk}
    for side, leg, arm in (("near", tr.near_leg, tr.near_arm), ("far", tr.far_leg, tr.far_arm)):
        hip, knee, ank, heel, toe = (leg[:, i] for i in range(5))
        sh, el, wr = (arm[:, i] for i in range(3))
        thigh = _ang_from_down(knee - hip)
        shank = _ang_from_down(ank - knee)
        s_vec, f_vec = knee - ank, toe - heel
        cosang = (s_vec * f_vec).sum(-1) / (np.linalg.norm(s_vec, axis=-1) * np.linalg.norm(f_vec, axis=-1))
        out[side] = {
            "thigh": thigh,
            "shank": shank,
            "hip": thigh + trunk,
            "knee": 180.0 - _interior(hip, knee, ank),
            "ankle": np.degrees(np.arccos(np.clip(cosang, -1, 1))) - 90.0,
            "shoulder": _wrap(_ang_from_down(el - sh) - _ang_from_down(tr.hip_mid - sh)),
            "elbow": 180.0 - _interior(sh, el, wr),
        }
    return out


# ---------------------------------------------------------------------------
# Stage 2c: clock (light-flicker aliasing)
# ---------------------------------------------------------------------------

STANDARD_FPS = (24, 25, 30, 48, 50, 60, 90, 100, 120, 150, 180, 200, 240, 300, 360, 480, 500, 960, 1000)


def flicker_clock(clip, seg):
    """Capture frame rate of a slow-motion clip from mains light flicker.

    Lamps on AC mains flicker at twice the mains frequency (100 Hz for 50 Hz
    mains). A camera capturing at f_c sees it at the aliased rate
    |100 - n f_c|, so the per-frame brightness of a static background band
    oscillates at a/f_c cycles per frame. The FFT peak a (cycles/frame) gives
    f_c = 100 / (n +- a) for small n; the candidate closest to a standard
    capture rate is returned with the measured value.
    """
    import cv2

    if not clip.mains_hz:
        return None
    cap = cv2.VideoCapture(os.path.join(CLIPDIR, clip.key + ".mp4"))
    cap.set(cv2.CAP_PROP_POS_FRAMES, seg.f0)
    y0, y1 = clip.cam_band if clip.cam_band else (0, 200)
    b = []
    for _ in range(seg.f0, seg.f1 + 1):
        ok, img = cap.read()
        if not ok:
            break
        b.append(img[y0:y1].mean())
    cap.release()
    b = np.array(b)
    d = (b - np.convolve(b, np.ones(13) / 13, "same"))[8:-8]
    F = np.abs(np.fft.rfft(d * np.hanning(len(d))))
    fq = np.fft.rfftfreq(len(d))
    band = fq > 0.05
    k = np.argmax(np.where(band, F, 0))
    # parabolic peak interpolation
    if 0 < k < len(F) - 1:
        y_1, y0_, y1_ = F[k - 1], F[k], F[k + 1]
        a = fq[k] + 0.5 * (y_1 - y1_) / (y_1 - 2 * y0_ + y1_) * (fq[1] - fq[0])
    else:
        a = fq[k]
    snr = float(F[k] / np.median(F[band]))
    flick = 2.0 * clip.mains_hz
    cands = [flick / (n + sgn * a) for n in range(0, 4) for sgn in (1, -1) if n + sgn * a > 0]
    best = min(cands, key=lambda f: min(abs(f - s) / s for s in STANDARD_FPS))
    std = min(STANDARD_FPS, key=lambda s: abs(best - s) / s)
    return {"peak_cycles_per_frame": float(a), "snr": snr, "measured_capture_fps": float(best),
            "capture_fps": float(std), "flicker_hz": flick}


# ---------------------------------------------------------------------------
# Stage 2d: gait / block events
# ---------------------------------------------------------------------------


@dataclass
class Ev:
    name: str  # td, to, ms, mkl, onset, rear_exit, block_exit
    leg: str  # "near" / "far" (the leg whose event it is)
    i: int  # index into the Track arrays (frame used for angles)
    t: float  # sub-frame event time, in analysed-frame index units
    step: int = 0  # step number for block starts (1 = first foot down after the blocks)


def _runs(mask):
    out, i, n = [], 0, len(mask)
    while i < n:
        if mask[i]:
            j = i
            while j + 1 < n and mask[j + 1]:
                j += 1
            out.append((i, j))
            i = j + 1
        else:
            i += 1
    return out


def _cross(d, i0, i1):
    """Sub-frame zero crossing of d between indices i0 and i1 (linear)."""
    a, b = d[i0], d[i1]
    if not (np.isfinite(a) and np.isfinite(b)) or a == b:
        return float(i1)
    return float(i0 + (i1 - i0) * a / (a - b))


def stride_frames(tr):
    """Stride period (analysed frames) from the autocorrelation of the near thigh angle."""
    th = angles(tr)["near"]["thigh"]
    x = th[np.isfinite(th)]
    x = x - x.mean()
    ac = np.correlate(x, x, "full")[len(x) - 1:]
    ac /= ac[0]
    lo = 8
    k = lo + int(np.argmax(ac[lo:len(x) // 2]))
    return float(k)


FOOT_TOL = 0.10  # contact when the foot's lowest point is within this many leg lengths of the ground


def contacts_vertical(tr, leg, tol=FOOT_TOL):
    """Contacts for tracking/rail cameras: the lowest of heel/toe is within
    `tol` leg lengths of the local ground level (running minimum over 1.5
    strides). Calibrated against hand-marked touchdowns/toe-offs in the Daegu
    clip (TD/TO within +-1 frame). Returns [(i_td, i_to, t_td, t_to)] for
    complete stances only.
    """
    from scipy.ndimage import minimum_filter1d

    L = tr.leg_len
    y = np.fmin(leg[:, 3, 1], leg[:, 4, 1])
    P = stride_frames(tr)
    g = minimum_filter1d(np.where(np.isfinite(y), y, np.inf), size=int(1.5 * P) | 1, mode="nearest")
    d = y - (g + tol * L)  # <= 0 in contact
    out = []
    for a, b in _runs(np.isfinite(d) & (d <= 0)):
        if a == 0 or b >= len(y) - 1 or b - a < 1:
            continue
        out.append((a, b, _cross(d, a - 1, a), _cross(d, b, b + 1)))
    return out


def contacts_ground(tr, leg, sites, rear, tol=0.06):
    """Contacts for handheld clips with camera-pan compensation.

    Each contact site (a cluster of stationary ground-fixed toe samples, see
    _stance_anchors) gets a toe position and a heel position (medians over the
    site's core window). The foot is in contact while its toe OR its heel sits
    within `tol` leg lengths of its site position (so a touchdown is caught
    whichever part of the foot lands first and a toe-off when the toe leaves)
    and the lower of the two is within 0.12 leg lengths of the lowest foot
    level there. Returns (site_index, i_first, i_last, t_first, t_last) for
    each site of this leg.
    """
    L = tr.leg_len
    toe = leg[:, 4] - tr.cam
    heel = leg[:, 3] - tr.cam
    low = np.fmin(toe[:, 1], heel[:, 1])
    out = []
    for j, c in enumerate(sites):
        if (j % 2 == 0) != rear:
            continue
        core = slice(c["t0"], c["t1"] + 1)
        hx = np.nanmedian(heel[core, 0])
        dx = np.fmin(np.abs(toe[:, 0] - c["x"]), np.abs(heel[:, 0] - hx))
        win = slice(max(0, c["t0"] - 5), min(len(low), c["t1"] + 6))
        ground = np.nanmin(low[win])
        d = np.fmax(dx - tol * L, low - (ground + 0.12 * L))
        runs = [(a, b) for a, b in _runs(np.isfinite(d) & (d <= 0)) if b >= c["t0"] - 3 and a <= c["t1"] + 3]
        if not runs:
            continue
        a = min(r[0] for r in runs)
        b = max(r[1] for r in runs)
        ta = _cross(d, a - 1, a) if a > 0 else float(a)
        tb = _cross(d, b, b + 1) if b < len(d) - 1 else float(b)
        out.append((j, a, b, ta, tb))
    return out


def run_events(tr):
    """TD/MS/TO/MKL events of both legs in a running segment.

    Contacts of both feet are merged in time order and a contact is dropped
    when it does not alternate with its neighbours (same leg twice in a row:
    an identity error) or follows its predecessor by less than 0.7 median
    steps. MS is the time midpoint of TD and TO; MKL is the frame of maximum
    thigh flexion between a leg's toe-off and its next touchdown.
    """
    th = angles(tr)
    cs = []
    for side, leg in (("near", tr.near_leg), ("far", tr.far_leg)):
        cs += [(ta, tb, side, a, b) for a, b, ta, tb in contacts_vertical(tr, leg)]
    cs.sort()
    alt = [cs[k + 1][0] - cs[k][0] for k in range(len(cs) - 1) if cs[k][2] != cs[k + 1][2]]
    S = float(np.median(alt)) if alt else np.nan
    keep = []
    for k, c in enumerate(cs):
        ok = True
        for nb in (k - 1, k + 1):
            if 0 <= nb < len(cs):
                if cs[nb][2] == c[2] or abs(cs[nb][0] - c[0]) < 0.7 * S:
                    ok = False
        if ok:
            keep.append(c)
    evs = []
    for ta, tb, side, a, b in keep:
        evs.append(Ev("td", side, a, ta))
        evs.append(Ev("to", side, b, tb))
        tm = 0.5 * (ta + tb)
        evs.append(Ev("ms", side, int(round(tm)), tm))
    for side in ("near", "far"):
        mine = [c for c in keep if c[2] == side]
        for c0, c1 in zip(mine[:-1], mine[1:]):
            if not 1.5 * S <= c1[0] - c0[0] <= 2.6 * S:
                continue
            seg = th[side]["thigh"][c0[4]:c1[3] + 1]
            if np.isfinite(seg).sum() < 3:
                continue
            k = c0[4] + int(np.nanargmax(seg))
            evs.append(Ev("mkl", side, k, float(k)))
    evs.sort(key=lambda e: e.t)
    return evs, {"step_frames": S, "contacts": keep}


def block_events(tr):
    """Onset, rear/front block exits and steps of a block-start segment."""
    L = tr.leg_len
    sites = tr.contact_sites
    evs = []
    rear_c = contacts_ground(tr, tr.near_leg, sites, rear=True)
    front_c = contacts_ground(tr, tr.far_leg, sites, rear=False)
    if not rear_c or not front_c or rear_c[0][0] != 0 or front_c[0][0] != 1:
        return evs, {}
    # block exits = end of the contact on the first two sites (the blocks)
    _, _, rb, _, trb = rear_c[0]
    _, _, fb, _, tfb = front_c[0]
    evs.append(Ev("rear_exit", "near", rb, trb))
    evs.append(Ev("block_exit", "far", fb, tfb))
    # set: the stillest 8-frame window of the trunk (hip + shoulder midpoints,
    # ground-fixed) in the 150 frames before the rear foot leaves.
    body = np.concatenate([tr.hip_mid - tr.cam, tr.sh_mid - tr.cam], axis=1)  # (T, 4)
    W = 8
    lo = max(0, rb - 150)
    best, bk = np.inf, lo
    for k in range(lo, rb - W - 4):
        w = body[k:k + W]
        if np.isfinite(w).all():
            v = np.sum(np.var(w, axis=0))
            if v < best:
                best, bk = v, k
    # onset (first movement): the body starts from rest with roughly constant
    # forward acceleration, so the forward position x = mean(hip x, shoulder x)
    # is fitted with x = c + a * max(0, t - k)^2 on [set window, rear exit];
    # the best breakpoint k is the onset.
    x = 0.5 * (body[:, 0] + body[:, 2])
    t = np.arange(len(x), dtype=float)
    f0 = max(lo, bk - 12)  # the push may start inside or just before the stillest window
    sl = slice(f0, rb + 1)
    ok = np.isfinite(x[sl])
    tt, xx = t[sl][ok], x[sl][ok]
    best, onset = np.inf, bk + W
    for k in np.arange(f0 + 2, rb - 2, 0.5):
        r = np.maximum(0.0, tt - k) ** 2
        Amat = np.stack([np.ones_like(r), r], 1)
        coef, res, *_ = np.linalg.lstsq(Amat, xx, rcond=None)
        sse = float(np.sum((Amat @ coef - xx) ** 2))
        if sse < best and coef[1] > 0:
            best, onset = sse, k
    oi = int(np.ceil(onset))
    evs.append(Ev("onset", "both", oi, float(onset)))
    # set window: the still frames from the stillest window to just before onset
    pose0 = body[bk:bk + W].mean(0)
    dev = np.max(np.abs(body - pose0).reshape(-1, 2, 2), axis=(1, 2)) / L
    set_idx = [k for k in range(bk, oi) if np.isfinite(dev[k]) and dev[k] <= 0.05]
    # steps after the blocks: alternate rear (near) and front (far) legs
    steps = sorted([(c[3], "near", c) for c in rear_c[1:]] + [(c[3], "far", c) for c in front_c[1:]])
    for n, (_, side, (j_, a, b, ta, tb)) in enumerate(steps, 1):
        evs.append(Ev("td", side, a, ta, n))
        if b < len(tr.frame) - 2:  # a contact still running at the segment end has no toe-off
            evs.append(Ev("to", side, b, tb, n))
    evs.sort(key=lambda e: e.t)
    return evs, {"set": set_idx}


# ---------------------------------------------------------------------------
# Stage 2e: keyframe statistics
# ---------------------------------------------------------------------------

LEG_ANGLES = ("hip", "knee", "ankle", "thigh", "shank")
ARM_ANGLES = ("shoulder", "elbow")
BOLT = {"height_m": 1.95, "mass_kg": 94.0, "hip_ankle_m": 0.957}  # hip-ankle = (0.245 + 0.246) H (Winter)
SIM = {"height_m": 1.75, "mass_kg": 67.5, "thigh_m": 0.43, "shank_m": 0.43, "ankle_sole_m": 0.08}


class Pool:
    """Collects samples per event and role; reports mean/sd/n and sources."""

    def __init__(self):
        self.v = {}  # event -> role -> [(value, clip)]
        self.src = {}
        self.cyc = {}

    def add(self, event, role, value, src=None):
        if value is None or not np.isfinite(value):
            return
        self.v.setdefault(event, {}).setdefault(role, []).append((float(value), src[0] if src else None))
        if src is not None:
            ss = self.src.setdefault(event, [])
            if src not in ss:
                ss.append(src)

    def add_limbs(self, event, prefix, A, side, i, src, legs=True, arms=True):
        for k in (LEG_ANGLES if legs else ()):
            self.add(event, prefix + k, A[side][k][i], src)
        for k in (ARM_ANGLES if arms else ()):
            self.add(event, prefix + k, A[side][k][i], src)

    def stats(self, event, clip=None):
        out = {}
        for role, vals in sorted(self.v.get(event, {}).items()):
            a = np.array([v for v, c in vals if clip is None or c == clip])
            if not len(a):
                continue
            out[role] = {"mean": round(float(a.mean()), 1), "sd": round(float(a.std(ddof=1)) if len(a) > 1 else 0.0, 1),
                         "n": int(len(a))}
        return out


def _src(tr, i):
    return [tr.clip, int(tr.frame[i])]


def analyze():
    """Run events/angles on all clips; returns the result dict for the JSON."""
    pool = Pool()  # primary numbers (near-limb rule)
    direct = Pool()  # far limbs measured directly (cross-check)
    timing = {"blocks": [], "run": []}
    trunk_steps = {}
    figure_poses = {}
    clock = {}
    for key, clip in CLIPS.items():
        raw = dict(np.load(npz_path(key)))
        trs = build_tracks(clip, raw)
        for si, tr in enumerate(trs):
            seg = clip.segments[si]
            A = angles(tr)
            L = tr.leg_len
            if clip.kind == "blocks":
                fl = flicker_clock(clip, seg)
                clock[f"{key}/{tr.seg}"] = fl
                fps = fl["capture_fps"] if fl else None
                evs, extra = block_events(tr)
                byname = {}
                for e in evs:
                    byname.setdefault(e.name + (str(e.step) if e.step else ""), e)
                # set position (still frames before onset)
                if extra.get("set"):
                    ground = _ground_level(tr, evs)
                    for i in extra["set"]:
                        src = _src(tr, i)
                        pool.add_limbs("set", "front_", A, "far", i, src)
                        pool.add_limbs("set", "rear_", A, "near", i, src)
                        pool.add("set", "trunk", A["trunk"][i], src)
                        if ground is not None:
                            pool.add("set", "hip_height", (tr.hip_mid[i, 1] - tr.cam[i, 1] - ground) / L, src)
                            pool.add("set", "shoulder_height", (tr.sh_mid[i, 1] - tr.cam[i, 1] - ground) / L, src)
                        figure_poses.setdefault("set", []).append((tr, i))
                    pool.cyc.setdefault("set", set()).add(f"{key}/{tr.seg}")
                for name, ev_key in (("rear_exit", "rear_exit"), ("block_exit", "block_exit")):
                    e = byname.get(ev_key)
                    if e is None:
                        continue
                    src = _src(tr, e.i)
                    pool.add_limbs(name, "front_", A, "far", e.i, src)
                    pool.add_limbs(name, "rear_", A, "near", e.i, src)
                    pool.add(name, "trunk", A["trunk"][e.i], src)
                    pool.cyc.setdefault(name, set()).add(f"{key}/{tr.seg}")
                    figure_poses.setdefault(name, []).append((tr, e.i))
                # steps: stance leg = the leg whose contact it is
                for e in evs:
                    if e.name not in ("td", "to") or e.step > 3:
                        continue
                    name = f"s{e.step}_{e.name}"
                    st, sw = e.leg, ("far" if e.leg == "near" else "near")
                    src = _src(tr, e.i)
                    pool.add_limbs(name, "st_", A, st, e.i, src)
                    pool.add_limbs(name, "sw_", A, sw, e.i, src)
                    pool.add(name, "trunk", A["trunk"][e.i], src)
                    if e.name == "td":
                        pool.add(name, "foot_ahead", (tr.near_leg if st == "near" else tr.far_leg)[e.i, 2, 0] / L
                                 - tr.hip_mid[e.i, 0] / L, src)
                    pool.cyc.setdefault(name, set()).add(f"{key}/{tr.seg}")
                    figure_poses.setdefault(name, []).append((tr, e.i))
                    trunk_steps.setdefault(e.step, {"td": [], "to": []})[e.name].append(float(A["trunk"][e.i]))
                # timing (frames -> s at the flicker-measured capture rate)
                row = {"clip": key, "segment": tr.seg, "capture_fps": fps,
                       "events_frame": {k: round(float(tr.frame[0]) + v.t * clip.step, 1) for k, v in byname.items()}}
                if fps:
                    ef = row["events_frame"]

                    def dt(a, b):
                        return round((ef[b] - ef[a]) / fps, 3) if a in ef and b in ef else None

                    row["onset_to_rear_exit_s"] = dt("onset", "rear_exit") if extra.get("set") else None
                    row["onset_to_block_exit_s"] = dt("onset", "block_exit") if extra.get("set") else None
                    row["rear_exit_to_block_exit_s"] = dt("rear_exit", "block_exit")
                    row["block_flight_s"] = dt("block_exit", "td1")
                    row["s1_contact_s"] = dt("td1", "to1")
                    row["s1_flight_s"] = dt("to1", "td2")
                    row["s2_contact_s"] = dt("td2", "to2")
                    row["s2_flight_s"] = dt("to2", "td3")
                    row["s3_contact_s"] = dt("td3", "to3")
                    # step lengths from the contact sites (toe positions), in leg lengths
                    xs = [c["x"] / L for c in tr.contact_sites]
                    row["site_x_over_L"] = [round(x, 3) for x in xs]
                    row["onset_reliable"] = bool(extra.get("set"))
                timing["blocks"].append(row)
            else:
                evs, extra = run_events(tr)
                S = extra["step_frames"]
                for e in evs:
                    name = "maxv_" + e.name
                    src = _src(tr, e.i)
                    other = "far" if e.leg == "near" else "near"
                    if e.name == "mkl":
                        # the MKL leg is the swing leg
                        if e.leg == "near":
                            pool.add_limbs(name, "sw_", A, "near", e.i, src)
                            direct.add_limbs(name, "st_", A, "far", e.i, src)
                        else:
                            pool.add_limbs(name, "st_", A, "near", e.i, src)
                            direct.add_limbs(name, "sw_", A, "far", e.i, src)
                    else:
                        if e.leg == "near":
                            pool.add_limbs(name, "st_", A, "near", e.i, src)
                            direct.add_limbs(name, "sw_", A, "far", e.i, src)
                            if e.name == "td":
                                pool.add(name, "foot_ahead", (tr.near_leg[e.i, 2, 0] - tr.hip_mid[e.i, 0]) / L, src)
                        else:
                            pool.add_limbs(name, "sw_", A, "near", e.i, src)
                            direct.add_limbs(name, "st_", A, "far", e.i, src)
                            if e.name == "td":
                                direct.add(name, "foot_ahead", (tr.far_leg[e.i, 2, 0] - tr.hip_mid[e.i, 0]) / L, src)
                    pool.add(name, "trunk", A["trunk"][e.i], src)
                    pool.cyc.setdefault(name, set()).add(f"{key}/{tr.seg}")
                    if e.leg == "near":
                        figure_poses.setdefault(name, []).append((tr, e.i))
                # timing in frames; speed from the stance foot moving back under the hip
                cts = extra["contacts"]
                cont = [c[1] - c[0] for c in cts]
                steps = [cts[k + 1][0] - cts[k][0] for k in range(len(cts) - 1) if cts[k + 1][2] != cts[k][2]
                         and cts[k + 1][0] - cts[k][0] < 1.4 * S]
                flights = [cts[k + 1][0] - cts[k][1] for k in range(len(cts) - 1) if cts[k + 1][2] != cts[k][2]
                           and cts[k + 1][0] - cts[k][0] < 1.4 * S]
                vv = []
                for ta, tb, side, a, b in cts:
                    leg = tr.near_leg if side == "near" else tr.far_leg
                    rel = leg[:, 4, 0] - tr.hip_mid[:, 0]  # toe relative to hip, moves back at running speed
                    if b - a >= 2 and np.isfinite(rel[a:b + 1]).all():
                        vv.append(-np.polyfit(np.arange(a, b + 1), rel[a:b + 1], 1)[0])
                v = float(np.median(vv)) if vv else np.nan
                timing["run"].append({
                    "clip": key, "segment": tr.seg, "playback_fps": clip.fps, "capture_fps": None,
                    "contacts": len(cont), "contact_frames": _msn(cont), "flight_frames": _msn(flights),
                    "step_frames": _msn(steps), "contact_over_step": round(float(np.mean(cont) / np.mean(steps)), 3),
                    "flight_over_step": round(float(np.mean(flights) / np.mean(steps)), 3),
                    "speed_leg_lengths_per_frame": round(v / L, 4),
                    "step_length_over_L": round(float(v * np.mean(steps) / L), 3),
                })
    return pool, direct, timing, trunk_steps, figure_poses, clock


def _msn(a):
    a = np.asarray(a, float)
    return {"mean": round(float(a.mean()), 2), "sd": round(float(a.std(ddof=1)) if len(a) > 1 else 0.0, 2),
            "n": int(len(a))} if len(a) else None


def _ground_level(tr, evs):
    """Track level (ground-fixed y) = lowest foot point during the first step's stance."""
    for e in evs:
        if e.name == "td" and e.step == 1:
            to = [f for f in evs if f.name == "to" and f.step == 1]
            b = to[0].i if to else min(len(tr.frame) - 1, e.i + 20)
            leg = tr.near_leg if e.leg == "near" else tr.far_leg
            low = np.fmin(leg[e.i:b + 1, 3, 1], leg[e.i:b + 1, 4, 1]) - tr.cam[e.i:b + 1, 1]
            return float(np.nanmedian(low))
    return None


# ---------------------------------------------------------------------------
# Stage 3: published reference data (verified sources, converted to our conventions)
# ---------------------------------------------------------------------------

SOURCES = {
    "DLV09": "German Athletics Federation (DLV) Scientific Research Project, Biomechanical analyses of selected events at "
             "the 12th IAAF World Championships Berlin 2009, Final Report Sprint Men (analysis R. Graubner; data behind "
             "Graubner & Nixdorf 2011, New Studies in Athletics 26(1/2)). "
             "https://worldathletics.org/download/download?filename=76ade5f9-75a0-4fda-b9bf-1b30be6f60d2.pdf",
    "MM13": "Mackala K., Mero A. (2013) A kinematics analysis of three best 100 m performances ever. J Hum Kinet "
            "36:149-160. doi:10.2478/hukin-2013-0015 (PMC3661886)",
    "L17": "Bissas A., Walker J., Tucker C., Paradisis G., Merlino S. Biomechanical Report for the IAAF World Championships "
           "London 2017: 100 m Men's. IAAF. https://worldathletics.org/download/download?filename="
           "51b04ff3-8549-4747-b066-5bd77aeaee38.pdf (includes P.-J. Vazel's commentary quoting JAAF 2010 Berlin data)",
    "W18": "Walker J., Tucker C.B., Paradisis G.P., Bezodis I., Bissas A., Merlino S. (2019) Biomechanical Report for the "
           "IAAF World Indoor Championships 2018: 60 Metres Men. IAAF. https://worldathletics.org/download/download?"
           "filename=031dbb8f-b50d-47cb-92bd-458f9f76feb7.pdf ; same data as Bezodis I.N. et al. (2019) Front Sports "
           "Act Living 1:23, doi:10.3389/fspor.2019.00023",
    "BZ19R": "Bezodis N.E., Willwacher S., Salo A.I.T. (2019) The biomechanics of the track and field sprint start: a "
             "narrative review. Sports Med 49:1345-1364. doi:10.1007/s40279-019-01138-1",
    "ST23": "Stuhec S., Planjsek P., Coh M., Mackala K. (2023) Multicomponent velocity measurement for linear sprinting: "
            "Usain Bolt's 100 m world-record analysis. Bioengineering 10(11):1254. doi:10.3390/bioengineering10111254",
    "NAG14": "Nagahara R. et al. (2014) Kinematics of transition during human accelerated sprinting. Biol Open "
             "3(8):689-699. doi:10.1242/bio.20148284",
    "SLA10": "Slawinski J. et al. (2010) Kinematic and kinetic comparisons of elite and well-trained sprinters during "
             "sprint start. J Strength Cond Res 24(4):896-905 (abstract only was accessible)",
}


def published():
    """Literature values (verified against the sources above), in this file's angle conventions."""
    return {
        "sources": SOURCES,
        "conversions": {
            "L17/W18 trunk alpha (to horizontal, 90 = upright)": "trunk = 90 - alpha",
            "L17/W18 knee beta (180 = straight)": "knee = 180 - beta",
            "L17/W18 hip gamma (shoulder-hip-knee / trunk-thigh, 180 = standing)": "hip = 180 - gamma",
            "L17 thigh epsilon/zeta (to vertical, + = in front)": "thigh = epsilon (same convention)",
            "L17 shank theta (to running surface, 90 = perpendicular)": "shank = theta - 90",
            "L17 ankle iota (90 = anatomical)": "ankle = iota - 90 (+ = plantarflexion)",
        },
        "berlin_2009_100m": {
            "source": "MM13 Table 3b (IAAF official 10-m sections), DLV09, L17 (Vazel), ST23",
            "reaction_s": 0.146,
            "splits_cumulative_s": {"10": 1.89, "20": 2.88, "30": 3.78, "40": 4.64, "50": 5.47, "60": 6.29, "70": 7.10,
                                    "80": 7.92, "90": 8.75, "100": 9.58},
            "note_60m": "DLV09 gives t60 = 6.31 (60-80 m 1.61 s) vs 6.29 in the IAAF 10-m data (60-80 m 1.63 s)",
            "steps": 40.92, "mean_step_length_m": 2.44, "whole_race_step_frequency_hz": 4.28,
            "section_step_length_m": {"0-20": 1.78, "20-40": 2.52, "40-60": 2.67, "60-80": 2.77, "80-100": 2.85},
            "section_step_frequency_hz": {"0-20": 3.89, "20-40": 4.54, "40-60": 4.49, "60-80": 4.49, "80-100": 4.23},
            "peak_speed_mps": {"fastest_10m_official_60_70": 12.35, "MM13_60_80_avg": 12.34, "DLV09_60_80_avg": 12.42,
                               "ST23_laser_point_peak_at_52m": 12.32},
            "contact_flight_47_55m_JAAF_via_L17": {"contact_s": [0.092, 0.098], "flight_s": [0.120, 0.132],
                                                   "step_length_m": 2.67, "step_rate_hz": 4.55, "speed_mps": 12.1},
            "corrections_to_brief": [
                "ground contact 0.08-0.09 s is not supported for Bolt: 0.092-0.098 s in Berlin (JAAF via L17), "
                "0.092-0.104 s in London 2017 (L17); ~0.077 s belongs to Tyson Gay",
                "step frequency 4.2-4.3 Hz is the whole-race mean (4.28 Hz); from 20-80 m it was 4.49-4.54 Hz (DLV09)",
                "Graubner & Nixdorf 2011 itself could not be opened; values trace to DLV09/MM13/L17/ST23",
                "'Krzysztof & Mero 2013' is Mackala K. & Mero A. 2013 (indexing error in PubMed)",
            ],
        },
        "london_2017_100m_final_bolt_47_55m": {
            "source": "L17 (Bolt 3rd, 9.95; two steps digitised at 150/250 Hz; left/right)",
            "contact_s": [0.104, 0.092], "flight_s": [0.136, 0.124], "step_length_m": 2.70, "step_rate_hz": 4.39,
            "speed_mps": 11.84, "finalists_mean_contact_s": 0.093, "finalists_mean_flight_s": 0.116,
            "td": {"trunk": [13.2, 17.3], "st_knee": [18.5, 22.9], "st_hip": [39.4, 37.3], "st_thigh": [28.8, 22.2],
                   "sw_thigh": [7.2, 26.8], "st_shank": [13.7, 5.4], "st_ankle": [32.5, 26.2],
                   "foot_tip_ahead_of_CM_m": [0.48, 0.32]},
            "to": {"trunk": [8.8, 10.4], "st_knee": [28.1, 20.4], "st_hip": [-14.1, -22.7], "sw_hip": [78.9, 73.7],
                   "st_thigh": [-23.5, -28.2], "sw_thigh": [70.6, 68.4], "st_shank": [-51.6, -48.6],
                   "st_ankle": [47.3, 47.7]},
            "stance_max_knee_flexion": [39.5, 41.3],
        },
        "world_class_block_start_W18": {
            "source": "W18 / Bezodis et al. 2019 (8 men, WIC 2018 60 m final)",
            "set": {"front_hip": 135.0, "rear_hip": 100.0, "front_knee": 87.0, "rear_knee": 59.0, "trunk": 109.0,
                    "sd": {"front_hip": 7, "rear_hip": 9, "front_knee": 5, "rear_knee": 10, "trunk": 4},
                    "CM_height_m": [0.50, 0.59]},
            "block_exit": {"trunk": 53.8, "front_hip": 9.2, "front_knee": 18.0, "trunk_range": [48, 61]},
            "times_s": {"onset_to_rear_exit": 0.194, "onset_to_rear_exit_sd": 0.018, "rear_exit_to_block_exit": 0.148,
                        "rear_exit_to_block_exit_sd": 0.018, "onset_to_block_exit": 0.342,
                        "gun_to_block_exit": 0.497, "block_flight": 0.067, "block_flight_range": [0.040, 0.107],
                        "contact_s": {"1": 0.175, "2": 0.171, "3": 0.138},
                        "flight_s": {"1": 0.044, "2": 0.058, "3": 0.062}},
            "step_length_m_td_to_td": {"1": 1.18, "2": 1.26, "3": 1.41}, "first_td_past_start_line_m": 0.54,
            "trunk_by_step": {"1": [51.2, 47.3], "2": [47.3, 45.4], "3": [44.3, 41.9]},
            "shank_to_ground_at_td_deg": {"1": 34.9, "2": 54.0, "3": 54.7},
        },
        "block_start_review_BZ19R": {
            "set_hips_fast_group_Mero1983": {"front_hip": 139.0, "rear_hip": 100.0},
            "set_hips_slow_group_Mero1983": {"front_hip": 128.0, "rear_hip": 91.0},
            "set_rear_knee_Slawinski2010_elite_vs_trained": [44.0, 63.0],
            "diamond_league_first_stance_s_Ciacci2017": 0.210, "diamond_league_first_flight_s": 0.045,
        },
        "acceleration_transitions_NAG14": {
            "first_transition_step": 4.4, "second_transition_step": 14.1, "min_support_time_s_step20": 0.090,
            "max_step_frequency_hz_step8": 4.87, "upper_trunk_lean_step25": 14.3,
            "note": "values read from the paper's text via summaries; no per-step trunk table",
        },
        "anthropometrics": {"height_m": [1.95, 1.96], "mass_kg": [94, 95],
                            "sources": "usainbolt.com/bio via Wikipedia (1.95 m, 94 kg); Olympedia (196 cm, 95 kg); "
                                       "ST23 (1.96 m, 94 kg); 86 kg not found"},
    }


# ---------------------------------------------------------------------------
# Stage 4: JSON + figure
# ---------------------------------------------------------------------------

EVENT_ORDER = ["set", "rear_exit", "block_exit", "s1_td", "s1_to", "s2_td", "s2_to", "s3_td", "s3_to",
               "drive_td", "drive_to", "maxv_td", "maxv_ms", "maxv_to", "maxv_mkl"]
MAXV_PRIMARY = "daegu2011_maxv"  # cleanest max-velocity clip; Osaka is reported as a cross-check

EVENT_NOTES = {
    "set": ("rep3 only (rep1 is a rolling start with no still set hold). LOW RELIABILITY: Bolt wears all-black in a "
            "compact crouch; overlays show MediaPipe placing both knees behind/below the hips and the shoulder line "
            "jumping between frames, so the knee and trunk values disagree strongly with every published set position "
            "(knees 87/59 deg, trunk ~109 deg). Use `literature` for the simulator's set pose; hip_height and "
            "shoulder_height are above the track level measured from step-1 stance."),
    "rear_exit": "last frame the rear (right, near) toe is on the rear block; front_ = far leg (partly occluded)",
    "block_exit": "last frame the front (left, far) toe is on the front block; front-leg values are far-limb 2D "
                  "measurements (less reliable), rear_ = near leg (driven forward)",
    "s1_td": "step 1 = first foot down after the blocks = the rear-block (right, near) leg; st_ = near leg",
    "s1_to": "st_ = rear-block (near) leg",
    "s2_td": "step 2 = front-block (left, far) leg: st_ values are FAR-limb measurements; sw_ = near leg",
    "s2_to": "rep3 only; st_ = far leg (less reliable), sw_ = near leg",
    "s3_td": "NOT MEASURED: both reps end before step 3 touchdown (phone re-frames / clip ends). See trunk_by_step.",
    "s3_to": "NOT MEASURED (see s3_td)",
    "drive_td": ("NOT MEASURED: no usable side view of Bolt's steps 4-10 was found (the Daegu 2011 uncut replay shows "
                 "them on the bend from an oblique front-side camera). Literature/model values only: see "
                 "trunk_by_step (model) and published.world_class_block_start_W18 / acceleration_transitions_NAG14."),
    "drive_to": "NOT MEASURED (see drive_td)",
    "maxv_td": ("primary = Daegu 2011 (4-5 cycles); roles from the NEAR leg only: st_ at near-leg touchdowns, sw_ at "
                "far-leg touchdowns (near leg then swinging). Near arm likewise. by_clip lists Daegu and Osaka."),
    "maxv_ms": "MS = time midpoint of TD and TO; near-leg rule as maxv_td",
    "maxv_to": "near-leg rule as maxv_td",
    "maxv_mkl": ("MKL = frame of maximum thigh flexion of the swing leg; sw_ = near leg at its own MKL, st_ = near leg at "
                 "the far leg's MKL"),
}


QUALITY = {
    "set": "poor", "rear_exit": "fair", "block_exit": "fair", "s1_td": "fair", "s1_to": "fair", "s2_td": "fair",
    "s2_to": "fair (n=1)", "maxv_td": "good (legs), fair (arms)", "maxv_ms": "good (legs), fair (arms)",
    "maxv_to": "good (legs), fair (arms)", "maxv_mkl": "good (legs), fair (arms)",
}
ARM_NOTE = ("Arm angles come from the near arm only and are the least reliable numbers here: the arm crossing in "
            "front of the torso is poorly localised (forward shoulder flexion is probably underestimated), and "
            "values with SD > 30 deg are moved to angles_low_confidence.")


def _event_block(pool, direct, name, primary_clip=None, per_clip=()):
    ang = pool.stats(name, primary_clip) if primary_clip else pool.stats(name)
    low = {r: v for r, v in ang.items() if r.endswith(("shoulder", "elbow")) and v["sd"] > 30}
    ang = {r: v for r, v in ang.items() if r not in low}
    src = [s for s in pool.src.get(name, []) if primary_clip is None or s[0] == primary_clip]
    blk = {"angles": ang, "sources": src,
           "cycles": len(pool.cyc.get(name, [])) if name == "set" else len(src),
           "quality": QUALITY.get(name, ""), "note": EVENT_NOTES.get(name, ""), "arms": ARM_NOTE}
    if low:
        blk["angles_low_confidence"] = low
    if per_clip:
        blk["by_clip"] = {c: pool.stats(name, c) for c in per_clip}
        blk["far_limb_direct"] = direct.stats(name, primary_clip)
    return blk


def trunk_model(td1, td2, upright, n_max=24):
    """Exponential blend of the TD trunk lean from step 1 to max-velocity upright:
    lean(n) = upright + (td1 - upright) * exp(-(n - 1) / tau), tau from steps 1-2."""
    r = (td2 - upright) / (td1 - upright)
    tau = -1.0 / np.log(r) if 0 < r < 1 else 10.0
    return tau, [(n, round(float(upright + (td1 - upright) * np.exp(-(n - 1) / tau)), 1)) for n in range(1, n_max + 1)]


def build_json(pool, direct, timing, trunk_steps, clock):
    pub = published()
    runs = [k for k, c in CLIPS.items() if c.kind == "run"]
    events = {}
    for name in EVENT_ORDER:
        if name.startswith("maxv"):
            events[name] = _event_block(pool, direct, name, MAXV_PRIMARY, runs)
        elif name in pool.v:
            events[name] = _event_block(pool, direct, name)
        else:
            events[name] = {"angles": {}, "sources": [], "cycles": 0, "quality": "not measured",
                            "note": EVENT_NOTES.get(name, "")}
    # literature to use where the video is poor / missing
    w = pub["world_class_block_start_W18"]
    events["set"]["literature"] = {k: {"mean": v, "sd": w["set"]["sd"].get(k)} for k, v in w["set"].items()
                                   if k not in ("sd", "CM_height_m")}
    events["set"]["literature"]["source"] = "W18 (world-class men, WIC 2018); Bolt-specific set angles not found"
    events["block_exit"]["literature"] = {"trunk": w["block_exit"]["trunk"], "front_hip": w["block_exit"]["front_hip"],
                                          "front_knee": w["block_exit"]["front_knee"], "source": "W18"}
    for n in ("3",):
        events["s3_td"]["literature"] = {"trunk": w["trunk_by_step"][n][0], "contact_s": w["times_s"]["contact_s"][n],
                                         "source": "W18 step 3 (world-class men)"}
        events["s3_to"]["literature"] = {"trunk": w["trunk_by_step"][n][1], "source": "W18 step 3"}
    l17 = pub["london_2017_100m_final_bolt_47_55m"]
    events["maxv_td"]["literature"] = {k: v for k, v in l17["td"].items()}
    events["maxv_to"]["literature"] = {k: v for k, v in l17["to"].items()}
    for k in ("maxv_td", "maxv_to"):
        events[k]["literature"]["source"] = "L17 Bolt London 2017 final, 47-55 m, [left, right]"
    # trunk by step: video steps 1-2, block exit, max velocity; model in between
    ts = []
    be = pool.stats("block_exit").get("trunk")
    if be:
        ts.append({"step": 0, "event": "block_exit", "trunk_td": None, "trunk_to": be["mean"], "source": "video"})
    for n in sorted(trunk_steps):
        td, to = trunk_steps[n]["td"], trunk_steps[n]["to"]
        ts.append({"step": n, "trunk_td": round(float(np.mean(td)), 1) if td else None,
                   "trunk_to": round(float(np.mean(to)), 1) if to else None, "n_td": len(td), "n_to": len(to),
                   "source": "video (Nitro 2017, 240 fps)"})
    up_td = pool.stats("maxv_td", MAXV_PRIMARY)["trunk"]["mean"]
    up_to = pool.stats("maxv_to", MAXV_PRIMARY)["trunk"]["mean"]
    td1 = float(np.mean(trunk_steps[1]["td"]))
    td2 = float(np.mean(trunk_steps[2]["td"]))
    tau, model = trunk_model(td1, td2, up_td)
    to_offset = float(np.mean([np.mean(trunk_steps[n]["to"]) - np.mean(trunk_steps[n]["td"])
                               for n in trunk_steps if trunk_steps[n]["to"] and trunk_steps[n]["td"]]))
    for n, v in model:
        if n <= max(trunk_steps):
            continue
        frac = np.exp(-(n - 1) / tau)
        ts.append({"step": n, "trunk_td": v, "trunk_to": round(float(v + to_offset * frac + (up_to - up_td) * (1 - frac)), 1),
                   "source": f"MODEL (not video): exponential blend, tau = {tau:.1f} steps"})
    ts.append({"step": "maxv", "trunk_td": up_td, "trunk_to": up_to, "source": "video (Daegu 2011)"})
    # timing
    tb = timing["blocks"]
    def m(key):
        a = [r[key] for r in tb if r.get(key) is not None]
        return {"mean": round(float(np.mean(a)), 3), "sd": round(float(np.std(a, ddof=1)), 3) if len(a) > 1 else 0.0,
                "n": len(a)} if a else None
    block_timing = {k: m(k) for k in ("onset_to_rear_exit_s", "onset_to_block_exit_s", "rear_exit_to_block_exit_s",
                                      "block_flight_s", "s1_contact_s", "s1_flight_s", "s2_contact_s")}
    sites = []
    for r in tb:
        x = r.get("site_x_over_L")
        if x and len(x) >= 4:
            sites.append({"segment": r["segment"], "rear_to_front_block_toe": round(x[1] - x[0], 3),
                          "front_block_to_step1_toe": round(x[2] - x[1], 3), "step1_to_step2_toe": round(x[3] - x[2], 3)})
    run_t = {r["clip"]: r for r in timing["run"]}
    dg = run_t.get(MAXV_PRIMARY)
    timing_out = {
        "blocks": {
            "clip": "nitro2017_blocks", "capture_fps": 240, "clock": clock,
            "clock_note": ("capture rate measured from the 100 Hz flicker of the stadium lights (50 Hz mains, "
                           "Melbourne) aliased to ~0.417 cycles/frame: 100/0.417 = 240 fps, i.e. an iPhone-style 240 fps "
                           "slow-motion played at 30 fps (8x). Frame resolution 4.2 ms; event uncertainty about +-2-5 "
                           "frames (+-8-20 ms), onset about +-10 frames."),
            "summary": block_timing, "per_rep": tb,
            "distances_over_L": sites,
            "note": ("onset = first forward movement of hips/shoulders (hinge fit), only for rep3 (rep1 has no still "
                     "set hold). Practice starts without a gun, so there is no reaction time; the literature 'block "
                     "time' (gun to front-foot exit) = reaction + onset_to_block_exit."),
        },
        "max_velocity": {
            "timebase": ("UNKNOWN for both running clips (broadcast slow-motion of unstated factor; no mains flicker "
                         "detectable). Durations are given in video frames and as ratios; absolute values need an "
                         "assumed clock."),
            "per_clip": timing["run"],
            "daegu_duty": {"contact_over_step": dg["contact_over_step"], "flight_over_step": dg["flight_over_step"],
                           "step_length_m_bolt": round(dg["step_length_over_L"] * BOLT["hip_ankle_m"], 2)} if dg else None,
            "if_daegu_were_realtime_59.94fps": {
                "contact_s": round(dg["contact_frames"]["mean"] / 59.94, 3), "flight_s": round(dg["flight_frames"]["mean"] / 59.94, 3),
                "step_frequency_hz": round(59.94 / dg["step_frames"]["mean"], 2),
                "speed_mps": round(dg["speed_leg_lengths_per_frame"] * BOLT["hip_ankle_m"] * 59.94, 2),
                "verdict": "implausible: a 2.7 m step at ~8.6 m/s and 3.2 Hz; the footage is slowed"} if dg else None,
            "if_step_frequency_4.4hz": {
                "implied_capture_fps": round(dg["step_frames"]["mean"] * 4.4, 1),
                "contact_s": round(dg["contact_frames"]["mean"] / (dg["step_frames"]["mean"] * 4.4), 3),
                "flight_s": round(dg["flight_frames"]["mean"] / (dg["step_frames"]["mean"] * 4.4), 3),
                "speed_mps": round(dg["speed_leg_lengths_per_frame"] * BOLT["hip_ankle_m"] * dg["step_frames"]["mean"] * 4.4, 2),
                "note": "calibrated to the published step rate, so NOT an independent timing measurement"} if dg else None,
            "use_for_timing": "published.london_2017_100m_final_bolt_47_55m and berlin_2009_100m",
        },
    }
    # agreement video vs literature
    P = lambda ev, role, clip=MAXV_PRIMARY: pool.stats(ev, clip).get(role, {}).get("mean")
    Q = lambda ev, role: pool.stats(ev).get(role, {}).get("mean")
    agreement = {
        "maxv_vs_L17_bolt_2017": {
            "td_trunk": [P("maxv_td", "trunk"), l17["td"]["trunk"]],
            "td_st_thigh": [P("maxv_td", "st_thigh"), l17["td"]["st_thigh"]],
            "td_st_knee": [P("maxv_td", "st_knee"), l17["td"]["st_knee"]],
            "td_st_hip": [P("maxv_td", "st_hip"), l17["td"]["st_hip"]],
            "td_st_shank": [P("maxv_td", "st_shank"), l17["td"]["st_shank"]],
            "td_sw_thigh": [P("maxv_td", "sw_thigh"), l17["td"]["sw_thigh"]],
            "to_trunk": [P("maxv_to", "trunk"), l17["to"]["trunk"]],
            "to_st_thigh": [P("maxv_to", "st_thigh"), l17["to"]["st_thigh"]],
            "to_st_knee": [P("maxv_to", "st_knee"), l17["to"]["st_knee"]],
            "to_st_hip": [P("maxv_to", "st_hip"), l17["to"]["st_hip"]],
            "to_sw_thigh": [P("maxv_to", "sw_thigh"), l17["to"]["sw_thigh"]],
            "to_sw_hip": [P("maxv_to", "sw_hip"), l17["to"]["sw_hip"]],
            "ms_st_knee_vs_stance_max_flexion": [P("maxv_ms", "st_knee"), l17["stance_max_knee_flexion"]],
            "contact_over_step": [dg["contact_over_step"] if dg else None,
                                  [round(0.104 / 0.240, 3), round(0.092 / 0.216, 3), round(0.092 / 0.212, 3), round(0.098 / 0.230, 3)]],
            "step_length_m": [round(dg["step_length_over_L"] * BOLT["hip_ankle_m"], 2) if dg else None, [2.70, 2.67, 2.77]],
            "summary": ("[video (Daegu), literature]. Thigh angles, knee at toe-off, contact fraction of the step and "
                        "step length agree. The video trunk is ~10-13 deg more upright and the stance knee straighter "
                        "at touchdown (by ~15 deg) and the stance thigh less extended at toe-off (by ~10-14 deg) than "
                        "Bolt's 2017 values. Likely causes: different task (Daegu = 200 m preliminary round, home "
                        "straight, not the 100 m at 50 m), MediaPipe's hip/shoulder centres vs. manual joint markers, "
                        "a +-2.5 deg lane-tilt correction, and event timing at an unknown frame rate (a 1-frame shift "
                        "changes thigh angles by ~5-8 deg)."),
        },
        "blocks_vs_W18": {
            "onset_to_rear_exit_s": [block_timing["onset_to_rear_exit_s"], 0.194],
            "onset_to_block_exit_s": [block_timing["onset_to_block_exit_s"], 0.342],
            "rear_exit_to_block_exit_s": [block_timing["rear_exit_to_block_exit_s"], 0.148],
            "block_flight_s": [block_timing["block_flight_s"], 0.067],
            "s1_contact_s": [block_timing["s1_contact_s"], 0.175],
            "s1_flight_s": [block_timing["s1_flight_s"], 0.044],
            "s2_contact_s": [block_timing["s2_contact_s"], 0.171],
            "block_exit_trunk": [Q("block_exit", "trunk"), 53.8],
            "block_exit_front_hip": [Q("block_exit", "front_hip"), 9.2],
            "block_exit_front_knee": [Q("block_exit", "front_knee"), 18.0],
            "s1_trunk_td_to": [[Q("s1_td", "trunk"), Q("s1_to", "trunk")], w["trunk_by_step"]["1"]],
            "s2_trunk_td_to": [[Q("s2_td", "trunk"), Q("s2_to", "trunk")], w["trunk_by_step"]["2"]],
            "set_front_rear_knee": [[Q("set", "front_knee"), Q("set", "rear_knee")], [87.0, 59.0]],
            "set_front_rear_hip": [[Q("set", "front_hip"), Q("set", "rear_hip")], [135.0, 100.0]],
            "set_trunk": [Q("set", "trunk"), 109.0],
            "summary": ("[video (Nitro 2017), literature]. Push-phase timing agrees within ~0.01-0.03 s (onset "
                        "uncertain by ~0.04 s). Bolt's first contact is ~0.05 s longer and the flights after block "
                        "exit and step 1 are ~0.03 s shorter than the 2018 world-indoor 60 m finalists (a practice "
                        "start; contact ends are the least certain events, +-2-5 frames). Bolt is ~7-8 deg more upright "
                        "than the 60 m finalists at block exit and steps 1-2. The set-position angles from this footage "
                        "are wrong (see events.set.note): use the literature set pose."),
        },
        "far_vs_near_limb_note": ("events.maxv_*.far_limb_direct gives the same roles measured on the far leg at its "
                                  "own events; the difference to the near-leg values is the far-limb 2D error"),
        "fps_resolution": {"nitro_240fps_frame_ms": 4.2, "daegu_video_frame_fraction_of_contact": round(1 / dg["contact_frames"]["mean"], 3) if dg else None},
    }
    Lr = (SIM["thigh_m"] + SIM["shank_m"]) / BOLT["hip_ankle_m"]
    fr = float(np.sqrt(Lr))
    scaling = {
        "bolt_leg_hip_ankle_m": BOLT["hip_ankle_m"], "sim_leg_hip_ankle_m": SIM["thigh_m"] + SIM["shank_m"],
        "leg_length_ratio_sim_over_bolt": round(Lr, 3),
        "rule": "Froude similarity with L = hip-ankle length: v ~ sqrt(g L), t ~ sqrt(L / g), f ~ sqrt(g / L), "
                "distances ~ L; angles unchanged",
        "speed_factor": round(fr, 3), "time_factor": round(fr, 3), "frequency_factor": round(1 / fr, 3),
        "distance_factor": round(Lr, 3),
        "examples_for_sim": {
            "max_speed_mps": round(12.35 * fr, 2), "maxv_contact_s": [round(0.092 * fr, 3), round(0.104 * fr, 3)],
            "maxv_flight_s": [round(0.124 * fr, 3), round(0.136 * fr, 3)],
            "maxv_step_rate_hz": [round(4.39 / fr, 2), round(4.55 / fr, 2)],
            "maxv_step_length_m": round(2.70 * Lr, 2),
            "onset_to_block_exit_s": round(block_timing["onset_to_block_exit_s"]["mean"] * fr, 3) if block_timing["onset_to_block_exit_s"] else None,
            "s1_contact_s": round(block_timing["s1_contact_s"]["mean"] * fr, 3),
        },
        "distances": "foot_ahead, hip_height, shoulder_height and step lengths are already in leg lengths (hip-ankle)",
    }
    clips = []
    for key, c in CLIPS.items():
        clips.append({
            "key": key, "file": f"clips/{key}.mp4", "url": c.url, "title": c.title, "event": c.event,
            "section_s": [c.t0, c.t1], "playback_fps": c.fps, "analysed_every_nth_frame": c.step,
            "capture_fps": c.fps * c.slow if c.slow else None,
            "slow_motion_factor": c.slow,
            "segments": [{"name": sg.name, "frames": [sg.f0, sg.f1]} for sg in c.segments],
            "near_side": "right (runner moves left to right)", "note": c.note,
        })
    return {
        "subject": "Usain Bolt", "height_m": 1.95, "mass_kg": 94.0,
        "generated_by": "playground/refs/bolt/keyframes.py",
        "footage_policy": "clips kept locally (gitignored) for analysis only; no pixels in any output",
        "clips": clips,
        "conventions": CONVENTIONS,
        "method": METHOD,
        "events": events,
        "trunk_by_step": [[r["step"], r["trunk_td"], r["trunk_to"]] for r in ts if r["step"] != "maxv"],
        "trunk_by_step_meta": {
            "columns": ["step (0 = block exit)", "trunk at TD (deg)", "trunk at TO (deg)"],
            "video_steps": [r["step"] for r in ts if str(r["source"]).startswith("video") and r["step"] != "maxv"],
            "model_steps": [r["step"] for r in ts if str(r["source"]).startswith("MODEL")],
            "model": next((r["source"] for r in ts if str(r["source"]).startswith("MODEL")), None),
            "maxv_td_to": [next(r for r in ts if r["step"] == "maxv")["trunk_td"],
                           next(r for r in ts if r["step"] == "maxv")["trunk_to"]],
            "note": ("steps 1-2 and block exit are Bolt video (Nitro 2017, n=2 reps); steps 3+ are an exponential blend "
                     "from the video step-1/2 lean to the Daegu max-velocity lean (NOT measured). For comparison the "
                     "2018 world-indoor 60 m finalists (W18) lean 51/47, 47/45, 44/42 deg (TD/TO) at steps 1-3, about "
                     "7 deg more than Bolt here; NAG14 puts the end of the lean-to-upright transition near step 14 "
                     "and upper-trunk lean ~14 deg at step 25."),
        },
        "timing": timing_out,
        "published": pub,
        "agreement": agreement,
        "scaling": scaling,
    }


METHOD = {
    "pose": "MediaPipe Tasks PoseLandmarker, heavy model (mediapipe 0.10.14, CPU), VIDEO mode, on a 512x512 crop that "
            "follows Bolt (kit colour check to reject other people; red official masked in the Nitro clip)",
    "coordinates": "image -> runner frame (x forward, y up), rotated by the lane-line slope at the feet (Hough lines)",
    "identity": "left/right labels resolved per frame by a Viterbi pass over ankle/heel/toe continuity; frames where "
                "both labels sit on one limb are dropped; in the block clip the labels are pinned by the ground "
                "contact sites (rear block, front block, step 1, step 2 alternate legs), after removing the phone's "
                "pan measured by phase correlation of the background",
    "near_far": "near leg = right (visible side for left-to-right running); by MediaPipe visibility in the running "
                "clips, by rear-block assignment in the block clip (Bolt's right foot is in the rear block)",
    "smoothing": "median-filter outlier rejection (0.12 leg lengths), gap fill up to 6 frames, Savitzky-Golay "
                 "(window 7 frames/cubic at 240 fps; 9/cubic at 60 fps; 5/quadratic at 25 fps) - keeps the knee "
                 "swing peaks (window << 1/4 stride)",
    "events_run": "contact while the lowest of heel/toe is within 0.10 leg lengths of the local ground (running min "
                  "over 1.5 strides), checked against hand-marked frames (+-1 frame); contacts must alternate legs",
    "events_blocks": "contact while toe or heel stays on its ground-fixed contact site (within 0.06 leg lengths) "
                     "and low (0.12); block exits = end of contact on the blocks; onset = hinge fit of forward "
                     "trunk position",
    "roles": "running: both legs' roles from the near leg (st_ at its own events, sw_ at the far leg's events); "
             "blocks: front_ = far leg, rear_ = near leg; steps: st_ = the leg in contact",
}


def draw_figure(pool, figure_poses, path):
    """Stick figures (representative instance per event) + angle table. No video pixels."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    NEAR, FAR, INK, INK2, SURF = "#2a78d6", "#eb6834", "#0b0b0b", "#52514e", "#fcfcfb"
    names = [n for n in ["set", "rear_exit", "block_exit", "s1_td", "s1_to", "s2_td", "s2_to",
                         "maxv_td", "maxv_ms", "maxv_to", "maxv_mkl"] if figure_poses.get(n)]
    fig = plt.figure(figsize=(22, 14.5), facecolor=SURF)
    ncol = 6
    for k, name in enumerate(names):
        ax = fig.add_axes([0.01 + (k % ncol) * 0.165, 0.645 - (k // ncol) * 0.285, 0.155, 0.27], facecolor=SURF)
        ref = pool.stats(name, MAXV_PRIMARY if name.startswith("maxv") else None)
        best, bi = np.inf, None
        for tr, i in figure_poses[name]:
            if name.startswith("maxv") and tr.clip != MAXV_PRIMARY:
                continue
            A = angles(tr)
            err = 0.0
            for role, st in ref.items():
                side = None
                if role.startswith(("st_", "rear_")):
                    side = "near"
                if side and role.split("_", 1)[1] in LEG_ANGLES and np.isfinite(A[side][role.split("_", 1)[1]][i]):
                    err += ((A[side][role.split("_", 1)[1]][i] - st["mean"]) / max(st["sd"], 3.0)) ** 2
            if err < best:
                best, bi = err, (tr, i)
        tr, i = bi
        L = tr.leg_len
        o = tr.hip_mid[i]
        for leg, arm, col, ls, lab in ((tr.far_leg, tr.far_arm, FAR, (0, (4, 3)), "far"),
                                       (tr.near_leg, tr.near_arm, NEAR, "-", "near")):
            P = (leg[i] - o) / L
            Aa = (arm[i] - o) / L
            ax.plot(P[[0, 1, 2], 0], P[[0, 1, 2], 1], color=col, lw=2.5, ls=ls, solid_capstyle="round")
            ax.plot(P[[3, 4], 0], P[[3, 4], 1], color=col, lw=2.5, ls=ls)
            ax.plot(P[[2, 3], 0], P[[2, 3], 1], color=col, lw=1.5, ls=ls)
            ax.plot(Aa[:, 0], Aa[:, 1], color=col, lw=2.0, ls=ls)
        H = (tr.hip_mid[i] - o) / L
        S = (tr.sh_mid[i] - o) / L
        ax.plot([H[0], S[0]], [H[1], S[1]], color=INK, lw=3.2, solid_capstyle="round")
        u = (S - H) / (np.linalg.norm(S - H) + 1e-9)
        ax.add_patch(plt.Circle(S + 0.22 * u, 0.1, fill=False, color=INK, lw=1.8))
        foot_y = np.nanmin([np.nanmin(((leg[i] - o) / L)[:, 1]) for leg in (tr.near_leg, tr.far_leg)])
        if name in ("set", "rear_exit", "block_exit") or name.endswith(("_td", "_ms", "_to")):
            ax.axhline(foot_y - 0.02, color=INK2, lw=0.8, alpha=0.5)
        ax.set_xlim(-1.3, 1.5)
        ax.set_ylim(-1.45, 1.6)
        ax.set_aspect("equal")
        ax.axis("off")
        ttl = {"set": "set", "rear_exit": "rear foot exit", "block_exit": "block exit", "s1_td": "step 1 TD",
               "s1_to": "step 1 TO", "s2_td": "step 2 TD", "s2_to": "step 2 TO", "maxv_td": "max-v TD",
               "maxv_ms": "max-v mid-stance", "maxv_to": "max-v TO", "maxv_mkl": "max-v max knee lift"}[name]
        ax.text(0.0, 0.99, ttl, transform=ax.transAxes, fontsize=13, color=INK, weight="bold", va="top")
        ax.text(0.0, 0.905, f"{tr.clip.split('_')[0]} {tr.seg} f{int(tr.frame[i])}", transform=ax.transAxes,
                fontsize=9, color=INK2, va="top")
        if name == "set":
            ax.text(0.0, 0.835, "unreliable pose (see note)", transform=ax.transAxes, fontsize=9, color=INK2, va="top")
    # legend
    lax = fig.add_axes([0.01 + 5 * 0.165, 0.40, 0.155, 0.2], facecolor=SURF)
    lax.set_xlim(0, 1)
    lax.set_ylim(0, 1)
    lax.axis("off")
    lax.plot([0.02, 0.2], [0.8, 0.8], color=NEAR, lw=2.5)
    lax.text(0.25, 0.8, "near limbs (right side)", va="center", fontsize=11, color=INK)
    lax.plot([0.02, 0.2], [0.6, 0.6], color=FAR, lw=2.5, ls=(0, (4, 3)))
    lax.text(0.25, 0.6, "far limbs (left side)", va="center", fontsize=11, color=INK)
    lax.plot([0.02, 0.2], [0.4, 0.4], color=INK, lw=3.2)
    lax.text(0.25, 0.4, "trunk (hip - shoulder)", va="center", fontsize=11, color=INK)
    lax.text(0.02, 0.12, "drawn from smoothed keypoints,\nscaled to leg length, runner -> right", fontsize=9,
             color=INK2, va="center")
    # table
    tax = fig.add_axes([0.01, 0.0, 0.98, 0.345], facecolor=SURF)
    tax.axis("off")
    blocks_cols = [("trunk", "trunk"), ("front_hip", "F hip"), ("front_knee", "F knee"), ("front_ankle", "F ankle"),
                   ("rear_hip", "R hip"), ("rear_knee", "R knee"), ("rear_thigh", "R thigh")]
    run_cols = [("trunk", "trunk"), ("st_hip", "st hip"), ("st_knee", "st knee"), ("st_ankle", "st ankle"),
                ("st_thigh", "st thigh"), ("sw_hip", "sw hip"), ("sw_knee", "sw knee"), ("sw_thigh", "sw thigh"),
                ("foot_ahead", "foot ahead/L")]
    rows = []
    for name in names:
        st = pool.stats(name, MAXV_PRIMARY if name.startswith("maxv") else None)
        cols = blocks_cols if name in ("set", "rear_exit", "block_exit") else run_cols
        cells = []
        for key, lab in cols:
            if key in st:
                v = st[key]
                fmt = "{:.2f}" if key == "foot_ahead" else "{:.0f}"
                cells.append(f"{lab} {fmt.format(v['mean'])}±{fmt.format(v['sd'])}")
        main = "rear_thigh" if name in ("set", "rear_exit", "block_exit") else "st_thigh"
        n = st.get(main, {}).get("n", 0)
        rows.append((name, n, cells))
    tax.text(0.0, 0.97, "Mean ± SD (deg; foot ahead in leg lengths).  st = stance leg, sw = swing leg, F/R = front/rear "
             "block leg.  Blocks: Nitro 2017 practice starts (240 fps).  Max-v: Daegu 2011 200 m round.",
             fontsize=11, color=INK, va="top", transform=tax.transAxes)
    y = 0.87
    for name, n, cells in rows:
        tax.text(0.0, y, f"{name}  (n={n})", fontsize=10.5, color=INK, weight="bold", va="top",
                 transform=tax.transAxes, family="DejaVu Sans Mono")
        tax.text(0.13, y, "   ".join(cells), fontsize=10.5, color=INK2, va="top", transform=tax.transAxes,
                 family="DejaVu Sans Mono")
        y -= 0.075
    fig.text(0.01, 0.99, "Usain Bolt: block start and max-velocity keyframes from side-view video (2D, MediaPipe)",
             fontsize=17, color=INK, weight="bold", va="top")
    fig.text(0.01, 0.965, "Angles: trunk + forward of vertical; thigh/shank from straight down, + forward; hip = thigh + "
             "trunk (+ flexion); knee/elbow flexion 0 = straight; ankle + plantarflexion.  Set pose from this footage "
             "is unreliable; use the literature set pose in bolt_keyframes.json.", fontsize=10.5, color=INK2, va="top")
    fig.savefig(path, dpi=90, facecolor=SURF)
    plt.close(fig)


def cmd_analyze():
    pool, direct, timing, trunk_steps, figure_poses, clock = analyze()
    out = build_json(pool, direct, timing, trunk_steps, clock)
    with open(OUT_JSON, "w") as f:
        json.dump(out, f, indent=1, default=lambda o: float(o) if isinstance(o, np.floating) else int(o)
                  if isinstance(o, np.integer) else str(o))
    print("wrote", OUT_JSON)
    # smoothed keypoints (derived data, no pixels) next to the raw MediaPipe arrays
    for key, clip in CLIPS.items():
        raw = dict(np.load(npz_path(key)))
        trs = build_tracks(clip, raw)
        extra = {}
        for tr in trs:
            p = tr.seg + "_"
            extra.update({p + "frame": tr.frame, p + "near_leg": tr.near_leg, p + "far_leg": tr.far_leg,
                          p + "near_arm": tr.near_arm, p + "far_arm": tr.far_arm, p + "hip_mid": tr.hip_mid,
                          p + "sh_mid": tr.sh_mid, p + "cam": tr.cam, p + "leg_len": tr.leg_len, p + "tilt": tr.tilt})
        keep = {k: v for k, v in raw.items() if k.startswith("raw_") or k in ("fps", "step")}
        np.savez_compressed(npz_path(key), **keep, **extra,
                            layout="smoothed arrays are runner coords (x forward, y up, px); legs = [hip, knee, "
                                   "ankle, heel, toe]; arms = [shoulder, elbow, wrist]; subtract cam for ground-fixed")
    os.makedirs(os.path.dirname(OUT_PNG), exist_ok=True)
    draw_figure(pool, figure_poses, OUT_PNG)
    print("wrote", OUT_PNG)


if __name__ == "__main__":
    import warnings

    warnings.filterwarnings("ignore", category=RuntimeWarning)
    cmd = sys.argv[1] if len(sys.argv) > 1 else "all"
    if cmd in ("pose", "all"):
        cmd_pose(sys.argv[2:])
    if cmd in ("analyze", "all"):
        cmd_analyze()
