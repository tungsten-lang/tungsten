"""Fit an incoming-energy gain block for a programmed stage in the replay (round 4).

The stage's table is unchanged; for starts whose incoming ball is slow (the predicted vertical speed at the crossing below `knee`), a hinge feature
uv = clip((knee - vz_c) / scale, 0, 2.5) multiplies a new (16 muscles x 17 knots) block Tv that is ADDED to the table's activations (the recorded closed-loop
activations already contain the table and the servo, so the replay of a candidate is a_rec + uv * Tv(t), clipped to [0, 1]; starts with uv = 0 replay the closed
loop exactly).  Sep-CMA over Tv on the training starts with the objective of oracle_search.evaluate (arrival targets from the closed-loop-successful starts).

    OMP_NUM_THREADS=1 nice -n 10 .venv/bin/python scratchpad/btl4/fit_v.py --stage 1 --seeds 13001:13841 --knee 1.6 --scale 0.15 --gens 150 --pop 32 --batch 48 --workers 3 --out scratchpad/btl4/runs/v1.npz
"""
import argparse
import os
import pickle
import random
import sys
import time

import numpy as np

sys.path.insert(0, "scratchpad/btl4")
sys.path.insert(0, "scratchpad/btl2")
import rlib  # noqa: E402
import oracle_lib as O  # noqa: E402
import oracle_search as S  # noqa: E402
from oracle_gs import SepCMA  # noqa: E402
from multiprocessing import get_context  # noqa: E402

NK = 17
DK = 0.025
_W = {}


def pred_cross_full(rp, k, height=0.62):
    """Replay.pred_cross plus the predicted vertical velocity at the crossing: (x, y, t, vz_c)."""
    rp.load(k)
    d, m = rp.d, rp.m
    g = 9.81
    r = None
    for name, vals in rp.t.extra_sensors(m, d):
        if name == "ball_rise":
            r = list(vals)
    if k >= 1:
        ps = rp.rec["ball"][k - 1]
        if r[5] > 0.0:
            r[0], r[1], r[2] = float(ps[0]), float(ps[1]), float(ps[2])
    vz = r[5]
    if vz <= 0.5:
        return None
    disc = vz * vz - 2.0 * g * (height - r[2])
    s = vz / g
    if disc > 0.0:
        s = (vz - np.sqrt(disc)) / g
    return (r[0] + r[3] * s, r[1] + r[4] * s, r[6] + s, vz - g * s)


def table_curve(T, shift, n):
    """The skill's table interpolation: knots DK apart, ticks i at te = i * 0.005 + shift (clamped at the ends); T (16, NK) -> (16, n)."""
    x = (np.arange(n) * 0.005 + shift) / DK
    x = np.clip(x, 0.0, NK - 1.0)
    i0 = np.minimum(np.floor(x).astype(int), NK - 2)
    w = x - i0
    return T[:, i0] * (1.0 - w) + T[:, i0 + 1] * w


def init_worker(cfg):
    _W["cfg"] = cfg
    _W["recs"] = {}
    _W["rp"] = None


def get_rec(seed):
    recs = _W["recs"]
    if seed not in recs:
        recs[seed] = pickle.load(open(f"out/btl4/rec/rec_{seed}.pkl", "rb"))
    rec = recs[seed]
    if _W["rp"] is None:
        _W["rp"] = O.Replay(rec)
    rp = _W["rp"]
    rp.rec = rec
    rp.act_ids = rec["act_ids"]
    return rec, rp


def replay(seed, x, uv, shift, ks, collect=False):
    cfg = _W["cfg"]
    rec, rp = get_rec(seed)
    hand = cfg["hand"]
    n = rlib.NEVAL
    base = rec["acts"][ks:ks + n + 1]
    idx = rlib.arm_indices(rec["names"], hand)
    ov = None
    if x is not None and uv > 0:
        T = np.clip(x.reshape(16, NK), -cfg["gmax"], cfg["gmax"])
        inc = uv * table_curve(T, shift, n)
        ov = {mi: np.clip(base[:n, mi] + inc[m], 0.0, 1.0) for m, mi in enumerate(idx)}
    pc = 0 if hand == "l" else 1

    def stop(i, pos, vel, cf):
        if i < 20 or vel[i, 2] <= 0 or pos[i, 2] < 0.60:
            return False
        return bool(np.any(cf[:i + 1, pc] > 0.3)) and bool(np.any(cf[:i + 1, 2] > 0.2))

    out = rp.run(ov, ticks=n, start=ks, stop=stop, hand_col=pc)
    S.ARR.update(cfg["arr"])
    J, summ = S.evaluate(out, "full", hand)
    return objective(J, summ, cfg), summ


def objective(J, summ, cfg):
    """Failure-aware objective recomputed from the replay summary: the gate, leg hits, the bounce near the ankle segment, a minimum apex, and the arrival
    inside the receiving hand's reach (no cost within `reach_dz` of the target); touch and bounce failures keep oracle_search's cost."""
    if not summ.get("bounced"):
        return J
    o = cfg["obj"]
    j = 3.0 * (0 if summ.get("gate", 0) > 0 else 1)
    j += 2.0 * max(0.0, summ.get("bgd", 0.0) - 0.10)
    j += o["w_apex"] * max(0.0, o["amin"] - summ.get("apex", 0.0))
    tg = np.array(cfg["arr"]["target"]) if cfg["arr"]["target"] is not None else np.zeros(2)
    j += o["w_pos"] * max(0.0, float(np.hypot(*(np.array(summ["arrive"]) - tg))) - o["pos_dz"])
    vt = np.array(cfg["arr"]["vt"]) if cfg["arr"]["vt"] is not None else np.zeros(2)
    j += o["w_vel"] * max(0.0, float(np.hypot(*(np.array(summ["va"])[:2] - vt))) - o["vel_dz"])
    if o.get("w_vz", 0.0) > 0.0:
        j += o["w_vz"] * max(0.0, o["vz_t"] - float(np.array(summ["va"])[2]))
    body = summ.get("body", 0)
    if body > 0:
        j += 3.0 + 0.5 * min(body, 5)
    return j


def base_job(seed):
    cfg = _W["cfg"]
    rec, rp = get_rec(seed)
    ks = M_trigger(rec, rp, cfg["bounce_no"])
    if ks is None:
        return seed, None
    pc = pred_cross_full(rp, ks)
    if pc is None:
        return seed, None
    pl = rec["pass_log"]
    ok = bool(pl[cfg["stage"]]["ok"]) if cfg["stage"] < len(pl) else False
    released = cfg["stage"] < len(pl)
    J, summ = replay(seed, None, 0.0, 0.0, ks)
    return seed, {"ks": ks, "pt": pc[2], "vzc": pc[3], "x": pc[0], "y": pc[1], "ok": ok, "released": released, "J": J,
                  "summ": {k: (np.array(v) if hasattr(v, "shape") else v) for k, v in summ.items() if k in ("touch", "bounced", "gate", "body", "apex", "arrive", "va", "bgd", "v", "p")}}


def M_trigger(rec, rp, bounce_no):
    import oracle_multi as M
    ks = M.trigger_tick(rec, rp, bounce_no, lead=rlib.LEAD)
    if ks is None or ks not in rec["snaps"]:
        return None
    return ks


def eval_job(job):
    x, seed, uv, shift, ks = job
    J, summ = replay(seed, x, uv, shift, ks)
    cfg = _W["cfg"]
    ok = proxy_ok(summ, cfg)
    return J, ok


def proxy_ok(summ, cfg):
    if not summ.get("bounced"):
        return False
    return bool(summ.get("gate", 0) > 0 and summ.get("body", 9) == 0 and summ.get("apex", 0) >= cfg["apex_min"]
                and float(np.hypot(*(np.array(summ["arrive"]) - np.array(cfg["arr"]["target"])))) < cfg["reach"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", type=int, required=True)
    ap.add_argument("--seeds", default="13001:13841")
    ap.add_argument("--knee", type=float, required=True, help="vertical speed at the predicted crossing below which the hinge feature is positive")
    ap.add_argument("--scale", type=float, default=0.15)
    ap.add_argument("--gens", type=int, default=150)
    ap.add_argument("--pop", type=int, default=32)
    ap.add_argument("--batch", type=int, default=48)
    ap.add_argument("--sigma", type=float, default=0.02)
    ap.add_argument("--gmax", type=float, default=0.15)
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--full", type=int, default=10)
    ap.add_argument("--val-frac", type=float, default=0.3)
    ap.add_argument("--pos-dz", type=float, default=0.10)
    ap.add_argument("--vel-dz", type=float, default=0.40)
    ap.add_argument("--w-pos", type=float, default=3.0)
    ap.add_argument("--w-vel", type=float, default=0.5)
    ap.add_argument("--w-apex", type=float, default=5.0)
    ap.add_argument("--amin", type=float, default=0.64)
    ap.add_argument("--w-vz", type=float, default=0.0, help="weight (per m/s) of the arrival's vertical speed below --vz-t")
    ap.add_argument("--vz-t", type=float, default=1.4)
    ap.add_argument("--reach", type=float, default=0.14)
    ap.add_argument("--apex-min", type=float, default=0.62)
    ap.add_argument("--cma-seed", type=int, default=3)
    ap.add_argument("--init", default="")
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    hand, bn = rlib.STAGES[a.stage]
    s0, s1 = [int(v) for v in a.seeds.split(":")]
    seeds = [s for s in range(s0, s1) if os.path.exists(f"out/btl4/rec/rec_{s}.pkl")]
    cfg = {"hand": hand, "bounce_no": bn, "stage": a.stage, "gmax": a.gmax, "arr": {"pos_dz": a.pos_dz, "vel_dz": a.vel_dz, "target": None, "vt": None, "pre": a.stage > 0,
                                                                                    "w_pos": a.w_pos, "w_vel": a.w_vel},
           "apex_min": a.apex_min, "reach": a.reach,
           "obj": {"w_apex": a.w_apex, "amin": a.amin, "w_pos": a.w_pos, "pos_dz": a.pos_dz, "w_vel": a.w_vel, "vel_dz": a.vel_dz, "w_vz": a.w_vz, "vz_t": a.vz_t}}
    t0 = time.time()
    with get_context("spawn").Pool(a.workers, initializer=init_worker, initargs=(cfg,)) as pool:
        base = dict(pool.map(base_job, seeds, chunksize=8))
        base = {k: v for k, v in base.items() if v is not None}
        print(f"{len(base)} of {len(seeds)} starts with a trigger and a stage-{a.stage} prediction ({time.time() - t0:.0f}s)", flush=True)
        okc = [b for b in base.values() if b["ok"] and b["summ"].get("bounced")]
        arr = np.array([b["summ"]["arrive"] for b in okc])
        vh = np.array([b["summ"]["va"][:2] for b in okc])
        target = arr.mean(0)
        vt = vh.mean(0)
        print(f"closed-loop-ok starts {len(okc)}: arrival mean {np.round(target, 3).tolist()} sd {np.round(arr.std(0), 3).tolist()}, arrival velocity mean {np.round(vt, 2).tolist()}")
        cfg["arr"]["target"] = [float(v) for v in target]
        cfg["arr"]["vt"] = [float(v) for v in vt]
        vz_all = np.array([b["vzc"] for b in base.values()])
        ok_all = np.array([b["ok"] for b in base.values()])
        released = np.array([b["released"] for b in base.values()])
        qs = np.quantile(vz_all, [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8])
        bins = np.digitize(vz_all, qs)
        print("vz at the crossing quantiles (10/20/30/40/50/60/80 %):", np.round(qs, 3).tolist())
        print("closed-loop pass ok by vz bin:", [f"{100 * ok_all[bins == i].mean():.0f}% (n {int((bins == i).sum())})" for i in range(len(qs) + 1)], flush=True)
        if a.dry:
            return
    with get_context("spawn").Pool(a.workers, initializer=init_worker, initargs=(cfg,)) as pool:
        # features
        uv = {s: float(np.clip((a.knee - b["vzc"]) / a.scale, 0.0, 2.5)) for s, b in base.items()}
        act = [s for s in base if uv[s] > 0]
        rnd = random.Random(a.cma_seed)
        rnd.shuffle(act)
        nval = int(len(act) * a.val_frac)
        val, tr = act[:nval], act[nval:]
        print(f"hinge knee {a.knee} scale {a.scale}: {len(act)} active starts ({len(act) / len(base):.0%}), {len(tr)} train, {len(val)} validation; "
              f"closed-loop ok among active {np.mean([base[s]['ok'] for s in act]):.2f} (all {np.mean([b['ok'] for b in base.values()]):.2f}); "
              f"base proxy ok among active {np.mean([proxy_ok_s(base[s], cfg) for s in act]):.2f}", flush=True)
        shift = {s: rlib.LEAD - 0.0025 - base[s]["pt"] for s in base}
        Jb = {s: objective(base[s]["J"], base[s]["summ"], cfg) for s in base}
        print(f"objective of the base replays: closed-loop ok {np.mean([Jb[s] for s in act if base[s]['ok']]):.2f}, not ok {np.mean([Jb[s] for s in act if not base[s]['ok']]):.2f} (active starts)", flush=True)

        def score(x, keys):
            jobs = [(x, s, uv[s], shift[s], base[s]["ks"]) for s in keys]
            res = pool.map(eval_job, jobs, chunksize=max(1, len(jobs) // (4 * a.workers)))
            return float(np.mean([r[0] for r in res])), int(sum(r[1] for r in res))

        def score_many(xs, keys):
            jobs = [(x, s, uv[s], shift[s], base[s]["ks"]) for x in xs for s in keys]
            res = pool.map(eval_job, jobs, chunksize=max(1, len(jobs) // (4 * a.workers)))
            m = len(keys)
            return [float(np.mean([r[0] for r in res[i * m:(i + 1) * m]])) for i in range(len(xs))]

        x0 = np.zeros(16 * NK)
        if a.init:
            x0 = np.load(a.init)["x"].copy()
        J0, ok0 = score(x0, tr)
        V0, vok0 = score(x0, val)
        print(f"start: train J {J0:.3f} proxy ok {ok0}/{len(tr)} | validation J {V0:.3f} proxy ok {vok0}/{len(val)}", flush=True)
        opt = SepCMA(x0, a.sigma, seed=a.cma_seed, popsize=a.pop)
        best = (J0, x0.copy())
        t1 = time.time()
        for g in range(a.gens):
            xs = opt.ask()
            keys = tr if a.batch >= len(tr) else rnd.sample(tr, a.batch)
            sc = np.array(score_many(xs, keys))
            opt.tell(xs, -sc)
            if g % a.full == a.full - 1 or g == a.gens - 1:
                cand = opt.mean.copy()
                J, ok = score(cand, tr)
                if J < best[0]:
                    best = (J, cand)
                    np.savez(a.out, x=best[1], knee=a.knee, scale=a.scale, stage=a.stage, gmax=a.gmax, score=J)
                Vj, vok = score(cand, val)
                print(f"gen {g} mean-vector train J {J:.3f} proxy ok {ok}/{len(tr)} (best {best[0]:.3f}) | validation J {Vj:.3f} proxy ok {vok}/{len(val)} | sigma {opt.sigma:.4f} ({time.time() - t1:.0f}s)", flush=True)
        # final: best vector
        Jb, okb = score(best[1], tr)
        Vb, vokb = score(best[1], val)
        print(f"final best: train J {Jb:.3f} proxy ok {okb}/{len(tr)} (start {J0:.3f}, {ok0}) | validation J {Vb:.3f} proxy ok {vokb}/{len(val)} (start {V0:.3f}, {vok0})")
    print("done")


def proxy_ok_s(b, cfg):
    return proxy_ok(b["summ"], cfg)


if __name__ == "__main__":
    main()
