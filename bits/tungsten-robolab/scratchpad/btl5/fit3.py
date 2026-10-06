"""Replay fit of a gain-scheduled muscle table for one stage (round 5; stage 3 = the left hand's second stroke, ORACLE-class).

    scratchpad/btl5/py scratchpad/btl5/fit3.py --data out/btl5/c3.pkl --stage 3 --init-params scratchpad/btl4/params/final_f.txt --init-stage 1 \
        --out out/btl5/fit3_a.npz --gens 300 --workers 6 > out/btl5/fit3_a.log

The table is the skill's own (pg_gs 1 with pg_nz posture features): knots every 25 ms (17 knots, 0.4 s) of the 16 arm muscles,
X = T0 + sum_i u_i clip(T_i, +-gmax) bounded to [0, 1] at the knots, linear in time, u = clip((feature - nominal) / spread, +-2.5) with the features
(predicted rising crossing x, y; the stroking arm's wrist flexion, shoulder abduction, elbow at the trigger); the clock is pg_align'ed
(shift = lead - 0.0025 - predicted time to the crossing). The replay overrides the stroking arm's 16 muscles from the trigger tick of a recorded
closed-loop start (rlib / oracle_lib.Replay), every other muscle replays the recording; the score is oracle_search.evaluate (J, lower is better).
Modes: --eval-only evaluates the init (or the recorded reflex stroke with --reflex) on the active set and exits.
"""
import argparse
import math
import pickle
import random
import sys
import time

import numpy as np

sys.path.insert(0, "scratchpad/btl2")
sys.path.insert(0, "scratchpad/btl4")
sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")
from multiprocessing import get_context  # noqa: E402

import oracle_lib as O  # noqa: E402
import oracle_search as S  # noqa: E402
from common import load, write_params  # noqa: E402

NK, DK, TICK = 17, 0.025, 0.005
JOINTS = O.POSTURE_JOINTS
_W = {}


class SepCMA:
    """Separable CMA-ES (diagonal covariance), maximising (as scratchpad/btl2/oracle_gs.py)."""

    def __init__(self, x0, sigma0, seed=1, popsize=None):
        n = len(x0)
        self.n = n
        self.rng = np.random.default_rng(seed)
        self.lam = popsize or 4 + int(3 * math.log(n))
        self.mu = self.lam // 2
        w = np.log(self.mu + 0.5) - np.log(np.arange(1, self.mu + 1))
        self.w = w / w.sum()
        self.mueff = 1.0 / np.sum(self.w ** 2)
        self.cc = (4 + self.mueff / n) / (n + 4 + 2 * self.mueff / n)
        self.cs = (self.mueff + 2) / (n + self.mueff + 5)
        c1 = 2 / ((n + 1.3) ** 2 + self.mueff)
        cmu = min(1 - c1, 2 * (self.mueff - 2 + 1 / self.mueff) / ((n + 2) ** 2 + self.mueff))
        scale = (n + 2) / 3.0
        self.c1 = min(1.0, c1 * scale)
        self.cmu = min(1.0 - self.c1, cmu * scale)
        self.damps = 1 + 2 * max(0, math.sqrt((self.mueff - 1) / (n + 1)) - 1) + self.cs
        self.chin = math.sqrt(n) * (1 - 1 / (4 * n) + 1 / (21 * n * n))
        self.mean = np.array(x0, float)
        self.sigma = sigma0
        self.C = np.ones(n)
        self.pc = np.zeros(n)
        self.ps = np.zeros(n)
        self.gen = 0

    def ask(self):
        z = self.rng.standard_normal((self.lam, self.n))
        return self.mean + self.sigma * z * np.sqrt(self.C)

    def tell(self, X, f):
        order = np.argsort(-np.asarray(f, float))
        X = np.asarray(X)[order]
        old = self.mean.copy()
        ys = (X[:self.mu] - old) / self.sigma
        yw = self.w @ ys
        self.mean = old + self.sigma * yw
        self.ps = (1 - self.cs) * self.ps + math.sqrt(self.cs * (2 - self.cs) * self.mueff) * yw / np.sqrt(self.C)
        hs = np.linalg.norm(self.ps) / math.sqrt(1 - (1 - self.cs) ** (2 * (self.gen + 1))) < (1.4 + 2 / (self.n + 1)) * self.chin
        self.pc = (1 - self.cc) * self.pc + hs * math.sqrt(self.cc * (2 - self.cc) * self.mueff) * yw
        self.C = ((1 - self.c1 - self.cmu) * self.C + self.c1 * (self.pc ** 2 + (1 - hs) * self.cc * (2 - self.cc) * self.C)
                  + self.cmu * (self.w @ (ys ** 2)))
        self.C = np.maximum(self.C, 1e-20)
        self.sigma *= math.exp((self.cs / self.damps) * (np.linalg.norm(self.ps) / self.chin - 1))
        self.gen += 1


def arm_indices(names, side):
    return [names.index(f"{side}_{jn}_{sg}") for jn in JOINTS for sg in ("pos", "neg")]


def parse_stage(pfile, stage, nz=3):
    """(blocks (1 + 2 + nz, 16, NK), nominal (2 + nz), spread (2 + nz)) of a stage's table in a params file (the skill's keys)."""
    p = load(pfile)
    nb = 3 + nz
    B = np.zeros((nb, 16, NK))
    for m in range(16):
        for k in range(NK):
            B[0, m, k] = p.get(f"pg{stage}_{m}_{k}", 0.0)
            B[1, m, k] = p.get(f"pgx{stage}_{m}_{k}", 0.0)
            B[2, m, k] = p.get(f"pgy{stage}_{m}_{k}", 0.0)
            for i in range(nz):
                B[3 + i, m, k] = p.get(f"pgz{stage}_{i}_{m}_{k}", 0.0)
    nom = np.array([p[f"pgc{stage}x"], p[f"pgc{stage}y"]] + [p[f"pgzn{stage}_{i}"] for i in range(nz)])
    sc = np.array([p[f"pgs{stage}x"], p[f"pgs{stage}y"]] + [p[f"pgzs{stage}_{i}"] for i in range(nz)])
    return B, nom, sc


def write_stage(base, out, stage, B, nom, sc, note, extra=None, nz=3):
    """base params + the stage's table keys (blocks (1 + 2 + nz, 16, NK)); pg_n / pg_stages cover the stage."""
    p = load(base)
    for m in range(16):
        for k in range(NK):
            p[f"pg{stage}_{m}_{k}"] = float(B[0, m, k])
            p[f"pgx{stage}_{m}_{k}"] = float(B[1, m, k])
            p[f"pgy{stage}_{m}_{k}"] = float(B[2, m, k])
            for i in range(nz):
                p[f"pgz{stage}_{i}_{m}_{k}"] = float(B[3 + i, m, k])
    p[f"pgc{stage}x"], p[f"pgc{stage}y"] = float(nom[0]), float(nom[1])
    p[f"pgs{stage}x"], p[f"pgs{stage}y"] = float(sc[0]), float(sc[1])
    for i in range(nz):
        p[f"pgzn{stage}_{i}"], p[f"pgzs{stage}_{i}"] = float(nom[2 + i]), float(sc[2 + i])
    p["pg_n"] = float(max(p.get("pg_n", 0), stage + 1))
    p["pg_stages"] = float(max(p.get("pg_stages", 0), stage + 1))
    p[f"pg_fbs{stage}"] = 0.0     # no servo target for a stage without a nominal-contraction table
    if extra:
        p.update(extra)
    write_params(out, p, note)


def table_knots(B, u, gmax):
    X = B[0] + np.tensordot(u, np.clip(B[1:], -gmax, gmax), axes=(0, 0))
    return np.clip(X, 0.0, 1.0)


def table_knots_add(B, u, gmax, lim=0.35):
    """Additive-offset version of table_knots: T0 + sum_i u_i clip(T_i) bounded to +-lim (no [0, 1] clip: the offsets are added to the recorded activations)."""
    return np.clip(B[0] + np.tensordot(u, np.clip(B[1:], -gmax, gmax), axes=(0, 0)), -lim, lim)


def knot_acts(X, shift, n):
    """(16, n) activations at ticks i of a stage whose clock is `shift` s ahead of the trigger tick, and the mask of ticks the table is playing."""
    x = np.maximum((np.arange(n) * TICK + shift) / DK, 0.0)
    live = x < (NK - 1)
    i = np.minimum(np.floor(x).astype(int), NK - 2)
    w = x - i
    return X[:, i] * (1.0 - w) + X[:, i + 1] * w, live


def evaluate5(out, who="l"):
    """oracle_search.evaluate ('full' mode) with a configurable apex floor (ARR['apex_min'], default 0.68) and apex weight (ARR['w_apex'], default 5):
    the release's gate / bounce / arrival score of a replayed stroke. Lower is better."""
    if S.ARR.get("apex_min", 0.68) == 0.68 and S.ARR.get("w_apex", 5.0) == 5.0 and S.ARR.get("apex_tgt") is None and S.ARR.get("valfn") is None:
        return S.evaluate(out, "full", who)
    J, sm = S.evaluate(out, "full", who)
    if sm.get("bounced") and "apex" in sm:
        J += S.ARR.get("w_apex", 5.0) * max(0.0, S.ARR.get("apex_min", 0.68) - sm["apex"]) - 5.0 * max(0.0, 0.68 - sm["apex"])
        if S.ARR.get("apex_tgt") is not None:      # a two-sided apex term: the energy of the ball must be repeatable (the next stage's timing)
            J += S.ARR.get("w_apex2", 0.0) * max(0.0, abs(sm["apex"] - S.ARR["apex_tgt"]) - S.ARR.get("apex_dz", 0.03))
    vf = S.ARR.get("valfn")
    if vf is not None and sm.get("bounced") and sm.get("gate", 0) > 0 and sm.get("body", 0) == 0 and "arrive" in sm:
        # the next stage's acceptance of the delivered ball (a logistic value function fitted on closed-loop records, valfn4.py): J += lam * -log(p + 0.02)
        ax, ay = float(sm["arrive"][0]), float(sm["arrive"][1])
        vh = float(np.hypot(*sm["va"][:2]))
        ap = float(sm["apex"])
        z = (np.array([ap, ax, ay, vh, ax * ax, ay * ay, ax * ay, ap * vh]) - vf["mu"]) / vf["sd"]
        pr = 1.0 / (1.0 + np.exp(-(vf["w"][0] + vf["w"][1:] @ z)))
        J += S.ARR.get("val_lam", 2.0) * (-np.log(pr + 0.02))
    return J, sm


def init_worker(data, cfg):
    _W["cfg"] = cfg
    _W["data"] = data
    S.ARR.update(cfg["arr"])
    first = next(iter(data.values()))
    _W["rp"] = O.Replay(first["rec"])


def eval_one(job):
    x, key, jit = job
    cfg, d = _W["cfg"], _W["data"][key]
    rp = _W["rp"]
    rec = d["rec"]
    rp.rec = rec
    rp.act_ids = rec["act_ids"]
    n = cfg["n"]
    base = rec["acts"]
    ov = None
    if x is not None:
        u = np.clip(d["u"] + jit, -2.5, 2.5)
        B = None if cfg.get("coarse") else x.reshape(cfg["nb"], 16, NK)
        ov = {}
        if cfg.get("coarse"):
            # the skill's static additive offset table (pg_dt: 16 muscles x 6 knots, 50 ms apart from the stage clock's start, linear, zero after the last knot)
            import rlib
            cur = rlib.offset_curve(x.reshape(16, 6), d["shift"], n)
            for m, mi in enumerate(cfg["idx"][d["hand"]]):
                ov[mi] = np.clip(base[:n, mi] + cur[m], 0.0, 1.0)
        elif cfg.get("additive"):
            A, live = knot_acts(table_knots_add(B, u, cfg["gmax"]), d["shift"], n)
            for m, mi in enumerate(cfg["idx"][d["hand"]]):
                arr = base[:n, mi].copy()
                arr[live] = np.clip(arr[live] + A[m][live], 0.0, 1.0)
                ov[mi] = arr
        else:
            A, live = knot_acts(table_knots(B, u, cfg["gmax"]), d["shift"], n)
            for m, mi in enumerate(cfg["idx"][d["hand"]]):
                arr = base[:n, mi].copy()
                arr[live] = A[m][live]
                ov[mi] = arr
    pc = 0 if d["hand"] == "l" else 1

    def stop(i, pos, vel, cf):
        # the evaluation ends when the ball rises through z 0.60 after the passer's touch AND the floor bounce that follows it (a trigger before
        # the bounce puts the previous bounce inside the window: it must not count)
        if i < 20 or vel[i, 2] <= 0 or pos[i, 2] < 0.60:
            return False
        t = np.nonzero(cf[:i + 1, pc] > 0.3)[0]
        if len(t) == 0:
            return False
        return bool(np.any(cf[t[0]:i + 1, 2] > 0.2))

    out = rp.run(ov, ticks=n, start=0, stop=stop, hand_col=pc)
    J, sm = evaluate5(out, d["hand"])
    keep = {k: sm[k] for k in ("touch", "bounced", "gate", "apex", "body", "bgd") if k in sm}
    if "arrive" in sm:
        keep["arrive"] = np.array(sm["arrive"])
        keep["va"] = np.array(sm["va"])
        keep["v"] = np.array(sm["v"])
        keep["bounce"] = np.array(sm["bounce"])
    return J, keep


GOOD = {"apex": 0.58, "rad": 0.14}


def is_good(sm, tgt, rad=None):
    rad = GOOD["rad"] if rad is None else rad
    return bool(sm.get("touch") and sm.get("bounced") and sm.get("gate", 0) > 0 and sm.get("apex", 0) >= GOOD["apex"] and sm.get("body", 9) == 0
                and float(np.hypot(*(np.array(sm["arrive"]) - tgt))) < rad)


def active_set(D, args):
    out = []
    for r in D:
        pl = r["pass_log"]
        if len(pl) < args.require or not all(r["pass_ok"][:args.require_ok]):
            continue
        if not all(pl[i]["gate"] and pl[i]["body"] == 0 for i in range(args.require)):
            continue
        x, y = r["feat"][0], r["feat"][1]
        if not (args.xlo < x < args.xhi and args.ylo < y < args.yhi and r["vzc"] > args.vzmin):
            continue
        out.append(r)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--stage", type=int, default=3)
    ap.add_argument("--init-params", default="scratchpad/btl4/params/final_f.txt")
    ap.add_argument("--init-stage", type=int, default=1)
    ap.add_argument("--init-npz", default="")
    ap.add_argument("--fresh-gains", action="store_true")
    ap.add_argument("--init-reflex", type=float, default=-1.0, help="init from the recorded reflex stroke: ridge regression (this penalty) of the stroking arm's activations at the table knots on the schedule features")
    ap.add_argument("--additive", action="store_true", help="the table is an ADDITIVE offset on the recorded activations (zero init): the refit of a stage that has a servo in its closed loop")
    ap.add_argument("--coarse", action="store_true", help="with --additive: ONLY the static offset table T0 of the skill's pg_dt layout (16 x 6 knots, 50 ms): 96 numbers, deployable as pgdt<stage>_<m>_<k>")
    ap.add_argument("--init-shift", type=int, default=0, help="delay the init table by this many knots (25 ms each; the first knot is held)")
    ap.add_argument("--out", default="")
    ap.add_argument("--base-params", default="scratchpad/btl4/params/final_f.txt")
    ap.add_argument("--write-params", default="")
    ap.add_argument("--require", type=int, default=3, help="the first N passes crossed the gate without a body contact")
    ap.add_argument("--require-ok", type=int, default=2, help="the first N passes judged ok")
    ap.add_argument("--xlo", type=float, default=-0.40)
    ap.add_argument("--xhi", type=float, default=0.10)
    ap.add_argument("--ylo", type=float, default=0.15)
    ap.add_argument("--yhi", type=float, default=0.55)
    ap.add_argument("--vzmin", type=float, default=0.30)
    ap.add_argument("--val-mod", type=int, default=10, help="validation = starts with (seed index) % val_mod >= val_lo")
    ap.add_argument("--val-lo", type=int, default=7)
    ap.add_argument("--eval", type=int, default=200, help="replayed ticks")
    ap.add_argument("--gens", type=int, default=300)
    ap.add_argument("--pop", type=int, default=48)
    ap.add_argument("--batch", type=int, default=16)
    ap.add_argument("--sigma", type=float, default=0.04)
    ap.add_argument("--gsigma", type=float, default=0.02)
    ap.add_argument("--gmax", type=float, default=1.0)
    ap.add_argument("--ujit", type=float, default=0.10)
    ap.add_argument("--full", type=int, default=10)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--cma-seed", type=int, default=5)
    ap.add_argument("--target", default="0.44,-0.26")
    ap.add_argument("--vt", default="1.55,-1.55")
    ap.add_argument("--pos-dz", type=float, default=0.03)
    ap.add_argument("--vel-dz", type=float, default=0.15)
    ap.add_argument("--w-pos", type=float, default=6.0)
    ap.add_argument("--w-vel", type=float, default=1.0)
    ap.add_argument("--apex-min", type=float, default=0.68)
    ap.add_argument("--valfn", default="", help="npz of a stage value function (valfn4.py): adds val-lam * -log(p) for clean strokes")
    ap.add_argument("--val-lam", type=float, default=2.0)
    ap.add_argument("--apex-tgt", type=float, default=None)
    ap.add_argument("--apex-dz", type=float, default=0.03)
    ap.add_argument("--w-apex2", type=float, default=0.0)
    ap.add_argument("--good-apex", type=float, default=0.58)
    ap.add_argument("--good-rad", type=float, default=0.14)
    ap.add_argument("--w-apex", type=float, default=5.0)
    ap.add_argument("--nom-from", default="train", help="feature nominal / spread: train (active training starts) or init (the init's)")
    ap.add_argument("--zfloor", type=float, default=0.02)
    ap.add_argument("--sc-mult", type=float, default=1.0, help="multiply the feature spreads (wider design range; an init table is re-expressed so its function is unchanged inside the old range)")
    ap.add_argument("--eval-only", action="store_true")
    ap.add_argument("--reflex", action="store_true", help="eval-only: the recorded (reflex) stroke, no override")
    a = ap.parse_args()

    D = pickle.load(open(a.data, "rb"))
    act = active_set(D, a)
    seed0 = min(r["seed"] for r in D)
    tr = [r for r in act if (r["seed"] - seed0) % a.val_mod < a.val_lo]
    va = [r for r in act if (r["seed"] - seed0) % a.val_mod >= a.val_lo]
    print(f"{len(D)} starts, active {len(act)}: {len(tr)} training, {len(va)} validation", flush=True)
    data = {r["seed"]: r for r in act}
    nz = 3
    F = np.array([r["feat"] for r in tr])
    floors = np.array([0.02, 0.02] + [a.zfloor] * nz)
    if a.nom_from == "init":
        _, nom, sc = parse_stage(a.init_params, a.init_stage, nz)
    else:
        nom = F.mean(axis=0)
        sc = np.maximum(F.std(axis=0), floors)
    sc = sc * a.sc_mult
    print("feature nominal", np.round(nom, 3).tolist(), "spread", np.round(sc, 3).tolist(), flush=True)
    for r in act:
        r["u"] = np.clip((r["feat"] - nom) / sc, -2.5, 2.5)
    names = act[0]["rec"]["names"]
    idx = {s: arm_indices(names, s) for s in "lr"}
    tgt = np.array([float(v) for v in a.target.split(",")])
    GOOD["apex"], GOOD["rad"] = a.good_apex, a.good_rad
    arr = {"pos_dz": a.pos_dz, "vel_dz": a.vel_dz, "target": [float(v) for v in a.target.split(",")], "vt": [float(v) for v in a.vt.split(",")],
           "pre": a.stage > 0, "w_pos": a.w_pos, "w_vel": a.w_vel, "apex_min": a.apex_min, "w_apex": a.w_apex, "apex_tgt": a.apex_tgt, "apex_dz": a.apex_dz, "w_apex2": a.w_apex2,
           "valfn": ({k: np.load(a.valfn)[k] for k in ("w", "mu", "sd")} if a.valfn else None), "val_lam": a.val_lam}
    cfg = {"idx": idx, "n": a.eval, "nb": 3 + nz, "gmax": a.gmax, "arr": arr, "additive": a.additive, "coarse": a.coarse}
    # the init: another stage's table re-expressed in this stage's feature units, or a saved fit
    if a.init_npz:
        z = np.load(a.init_npz)
        B0 = z["x"].reshape(3 + nz, 16, NK)
        nom0, sc0 = z["nom"], z["sc"]
        dd = (nom - nom0) / sc0
        rr = sc / sc0
        T0 = B0[0].copy()
        for i in range(2 + nz):
            T0 = T0 + dd[i] * B0[1 + i]
        B = np.zeros_like(B0)
        B[0] = T0
        for i in range(2 + nz):
            B[1 + i] = B0[1 + i] * rr[i]
    else:
        Bi, nomi, sci = parse_stage(a.init_params, a.init_stage, nz)
        dd = (nom - nomi) / sci
        rr = sc / sci
        T0 = Bi[0].copy()
        for i in range(2 + nz):
            T0 = T0 + dd[i] * Bi[1 + i]
        B = np.zeros_like(Bi)
        B[0] = T0
        for i in range(2 + nz):
            B[1 + i] = Bi[1 + i] * rr[i]
        print("init shift", np.round(dd, 2).tolist(), "scale", np.round(rr, 2).tolist(), flush=True)
    if a.init_reflex >= 0:
        X = np.array([[1.0] + list(r["u"]) for r in tr])
        Y = []
        for r in tr:
            ids = arm_indices(r["rec"]["names"], r["hand"])
            tick = (np.arange(NK) * DK - r["shift"]) / TICK            # the (fractional) tick of each knot's time on the stage clock
            acts = r["rec"]["acts"][:, ids]                              # (ticks, 16)
            Y.append(np.array([[np.interp(tk, np.arange(len(acts)), acts[:, m]) for tk in tick] for m in range(16)]).reshape(-1))
        Y = np.array(Y)
        Rg = a.init_reflex * np.eye(X.shape[1])
        Rg[0, 0] = 0.0
        Bm = np.linalg.solve(X.T @ X + Rg, X.T @ Y).reshape(X.shape[1], 16, NK)
        B = np.clip(Bm, -a.gmax, a.gmax)
        B[0] = Bm[0]
        print("init from the reflex stroke: ridge", a.init_reflex, "residual rms", float(np.sqrt(np.mean((Y - X @ np.linalg.solve(X.T @ X + Rg, X.T @ Y)) ** 2))), flush=True)
    if a.init_shift > 0:
        k = a.init_shift
        Bs = B.copy()
        Bs[:, :, k:] = B[:, :, :NK - k]
        Bs[:, :, :k] = B[:, :, :1]
        B = Bs
    if a.fresh_gains:
        B[1:] = 0.0
    if a.additive:
        B = np.zeros_like(B)
    x0 = B.reshape(-1).copy()
    if a.coarse:
        x0 = np.zeros(16 * 6)
    nm, K = 16, NK

    def describe(rows):
        return sum(1 for sm in rows if is_good(sm, tgt))

    with get_context("spawn").Pool(a.workers, initializer=init_worker, initargs=(data, cfg)) as pool:
        def score(xs, keys, jit=0.0, rnd=None):
            nf = 2 + nz
            jv = {k: (np.array([rnd.gauss(0, jit) for _ in range(nf)]) if jit > 0 else np.zeros(nf)) for k in keys}
            jobs = [(x, k, jv[k]) for x in xs for k in keys]
            res = pool.map(eval_one, jobs, chunksize=max(1, len(jobs) // (4 * a.workers)))
            m = len(keys)
            return [(float(np.mean([r[0] for r in res[i * m:(i + 1) * m]])), [r[1] for r in res[i * m:(i + 1) * m]]) for i in range(len(xs))]

        trk = [r["seed"] for r in tr]
        vak = [r["seed"] for r in va]
        if a.eval_only:
            xe = None if a.reflex else x0
            for nmx, ks in (("train", trk), ("val", vak)):
                res = score([xe], ks)[0]
                rows = res[1]
                nt = sum(1 for s in rows if not s.get("touch"))
                nbn = sum(1 for s in rows if s.get("touch") and not s.get("bounced"))
                ng = sum(1 for s in rows if s.get("bounced") and s.get("gate", 0) == 0)
                nb_ = sum(1 for s in rows if s.get("bounced") and s.get("body", 0) > 0)
                ap = np.mean([s["apex"] for s in rows if s.get("bounced")])
                print(f"{nmx}: J {res[0]:.3f} good {describe(rows)}/{len(ks)} | no touch {nt}, no bounce {nbn}, no gate {ng}, body {nb_}, mean apex {ap:.3f}", flush=True)
            return
        rnd = random.Random(a.cma_seed)
        opt = SepCMA(x0, a.sigma, seed=a.cma_seed, popsize=a.pop)
        opt.C[nm * K:] = (a.gsigma / a.sigma) ** 2
        b0 = score([x0], trk)[0]
        best = (b0[0], x0.copy())
        print(f"start train J {b0[0]:.3f} good {describe(b0[1])}/{len(trk)}", flush=True)
        if vak:
            v0 = score([x0], vak)[0]
            print(f"start validation J {v0[0]:.3f} good {describe(v0[1])}/{len(vak)}", flush=True)
        t1 = time.time()
        for g in range(a.gens):
            xs = opt.ask()
            keys = trk if a.batch >= len(trk) else rnd.sample(trk, a.batch)
            res = score(xs, keys, a.ujit, rnd)
            sc_ = np.array([r[0] for r in res])
            opt.tell(xs, -sc_)
            if g % a.full == a.full - 1 or g == a.gens - 1:
                cand = opt.mean.copy()
                fs = score([cand], trk)[0]
                if fs[0] < best[0]:
                    best = (fs[0], cand)
                    if a.out:
                        np.savez(a.out, x=best[1], nom=nom, sc=sc, zj=np.array([4, 1, 3]), gmax=a.gmax, score=best[0], stage=a.stage)
                    if a.write_params and a.coarse:
                        pp_ = load(a.base_params)
                        for m_ in range(16):
                            for k_ in range(6):
                                pp_[f"pgdt{a.stage}_{m_}_{k_}"] = float(best[1][m_ * 6 + k_])
                        pp_["pg_dt"], pp_["pg_dtn"], pp_["pg_dtk"] = 1.0, 6.0, 0.05
                        write_params(a.write_params, pp_, f"fit3 coarse additive offsets of stage {a.stage} {a.out}")
                    elif a.write_params:
                        write_stage(a.base_params, a.write_params, a.stage, best[1].reshape(3 + nz, 16, NK), nom, sc, f"fit3 stage {a.stage} {a.out}",
                                    extra={f"pg_lead{a.stage}": float(act[0].get("lead", 0.165)), "pg_gmax": max(1.0, a.gmax)})
                msg = f"gen {g} mean-vector train J {fs[0]:.3f} good {describe(fs[1])}/{len(trk)} (best {best[0]:.3f})"
                if vak:
                    vs = score([best[1]], vak)[0]
                    msg += f" | validation J {vs[0]:.3f} good {describe(vs[1])}/{len(vak)}"
                print(msg + f" ({time.time() - t1:.0f}s)", flush=True)
            elif g % 2 == 0:
                print(f"gen {g} gen-best {sc_.min():.3f} sigma {opt.sigma:.4f} ({time.time() - t1:.0f}s)", flush=True)
    print("done")


if __name__ == "__main__":
    main()
