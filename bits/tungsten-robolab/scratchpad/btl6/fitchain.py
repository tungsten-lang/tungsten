"""CHAIN fit (round 6): CMA of one stage table's smooth correction (+ aim / clock / lead knobs) in the chained replay with the END-TO-END objective.

    scratchpad/btl6/py scratchpad/btl6/fitchain.py --stage 2 --out out/btl6/fc_a --gens 150 > out/btl6/fc_a.log 2>&1 &

The table is G's (params file --params) plus a correction expanded from a small cosine basis over the 17 knots (J coefficients per block and muscle; block 0 = T0,
blocks 1-5 = the gain blocks of the 5 schedule features), bounded; the knobs (stage 2: aim shifts dnom of the 5 features and the clock offset dacd; stages 3 / 4 also
the trigger lead) are extra dimensions in physical units. The chain replay (chainrep.Chain) starts at the stage's trigger tick of recorded G starts and runs through
the stages after it with their tables in the loop; the objective is -V + eps * shaping (chainobj.chain_outcome). Training starts: the active ones of the records
with (seed index) % 10 < 7, validation the rest; every generation ranks the candidates on a random batch (common random numbers).
"""
import argparse
import math
import os
import pickle
import random
import sys
import time

import numpy as np

sys.path.insert(0, "scratchpad/btl6")
sys.path.insert(0, "scratchpad/btl5")
from multiprocessing import get_context  # noqa: E402

_W = {}
NK = 17
KNOB_SCALE = {"dacd": 0.001, "dx": 0.003, "dy": 0.003, "dz": 0.01, "dlead": 0.002}


def basis(J):
    k = np.arange(NK)
    if J == 0:
        return np.zeros((0, NK))
    Phi = np.zeros((J, NK))
    Phi[0] = 1.0
    for j in range(1, J):
        Phi[j] = np.cos(math.pi * j * (k + 0.5) / NK)
    return Phi


def knob_names(stage, energy=False):
    if energy and STRONG[0]:
        return ["dvk", "dvs"]
    if energy:
        return ["dvk", "dvs", "dkap"]
    return ["dacd", "dx", "dy", "dz0", "dz1", "dz2"] + (["dlead"] if stage > 2 else [])


KNOB_SCALE.update({"dvk": 0.15, "dvs": 0.1, "dkap": 0.01})


STRONG = [False]


def blocks_of(energy):
    if energy:
        return [7] if STRONG[0] else [6]
    return [0, 1, 2, 3, 4, 5]


def expand(x, J, stage, use_knobs, lim0, limg, energy=False):
    """(dB (8, 16, 17), knobs dict) of the CMA vector x"""
    bl = blocks_of(energy)
    nb = len(bl) * 16 * J
    c = x[:nb].reshape(len(bl), 16, J)
    part = np.tensordot(c, basis(J), axes=(2, 0))
    dB = np.zeros((8, 16, NK))
    for i, b in enumerate(bl):
        dB[b] = np.clip(part[i], -(lim0 if b == 0 else limg), lim0 if b == 0 else limg)
    kn = None
    if use_knobs:
        v = x[nb:]
        names = knob_names(stage, energy)
        d = dict(zip(names, v))
        if energy and STRONG[0]:
            kn = {stage: {"dwk": float(np.clip(d["dvk"] * KNOB_SCALE["dvk"], -0.1, 0.1)), "dws": float(np.clip(d["dvs"] * KNOB_SCALE["dvs"], -0.03, 0.3))}}
        elif energy:
            kn = {stage: {"dvk": float(np.clip(d["dvk"] * KNOB_SCALE["dvk"], -0.6, 0.6)), "dvs": float(np.clip(d["dvs"] * KNOB_SCALE["dvs"], -0.2, 0.6)),
                          "dkap": float(np.clip(d["dkap"] * KNOB_SCALE["dkap"], -0.06, 0.06))}}
        else:
            kn = {stage: {"dacd": float(np.clip(d["dacd"] * KNOB_SCALE["dacd"], -0.002, 0.002)),
                          "dnom": np.array([d["dx"] * KNOB_SCALE["dx"], d["dy"] * KNOB_SCALE["dy"]] + [d[f"dz{i}"] * KNOB_SCALE["dz"] for i in range(3)])}}
            if stage > 2:
                kn[stage]["dlead"] = float(np.clip(d["dlead"] * KNOB_SCALE["dlead"], -0.01, 0.01))
    return dB, kn


def init_worker(a_dict):
    import chainrep as C
    import chainobj as Ob
    a = argparse_ns(a_dict)
    recdir = a.recdir
    rec0 = pickle.load(open(os.path.join(recdir, "rec_%d.pkl" % a.seed0), "rb"))
    ch = C.Chain(a.params, rec0, gmax=a.gmax)
    if a.units != 1.0:
        ch.reexpress(a.stage, a.units)
    if a.energy and not a.strong:
        ch.vk[a.stage], ch.vs[a.stage] = a.vk0, a.vs0
        ch.vsel[a.stage] = a.vsel
    if a.energy and a.strong:
        ch.wk[a.stage], ch.ws[a.stage] = a.wk0, a.ws0
    act = None
    if a.active_from:
        act = pickle.load(open(a.active_from, "rb"))
    vf = None
    if a.valfn:
        z = np.load(a.valfn)
        vf = {k: z[k] for k in ("w", "mu", "sd")}
    sts = {}
    for sd in range(a.seed0, a.seed1):
        f = os.path.join(recdir, "rec_%d.pkl" % sd)
        if not os.path.exists(f):
            continue
        rec = pickle.load(open(f, "rb"))
        pl = rec["pass_log"]
        if len(pl) < a.require or not all(p["ok"] for p in pl[:a.require_ok]):
            continue
        if act is not None:
            r = act.get(sd)
            if r is None:
                continue
            fl = r["fl"]
            c2 = fl.get(2) and fl[2]["touch"] and fl[2]["bounced"] and fl[2]["gate"] and fl[2]["bfl"] == 0 and fl[2]["pre"] == 0
            c3 = fl.get(3) and fl[3]["touch"] and fl[3]["bounced"] and fl[3]["gate"] and fl[3]["bfl"] == 0
            if a.stage == 3 and not c2:
                continue
            if a.stage == 4 and not (c2 and c3 and r["v3"] > 0):
                continue
        st = ch.prep(rec, a.stage)
        if st is not None:
            if a.energy:
                v0 = ch.vzc0(st) if not a.strong else ch.apex0(st)
                if v0 is None or v0 >= a.vmax or v0 < a.vmin:
                    continue
            sts[sd] = st
    _W.update(ch=ch, Ob=Ob, vf=vf, sts=sts, a=a)


class argparse_ns:
    def __init__(self, d):
        self.__dict__.update(d)


def eval_job(job):
    ci, dB, kn, sd = job
    ch, Ob, vf, st, a = _W["ch"], _W["Ob"], _W["vf"], _W["sts"][sd], _W["a"]
    over = None
    if dB is not None:
        B = ch.tab[a.stage][0] + dB
        over = {a.stage: B}
    run = ch.run(st, over=over, knobs=kn)
    if run is None:
        return ci, sd, 1.0, 0.0
    oc = Ob.chain_outcome(run, a.stage, vf, eps=a.eps)
    return ci, sd, oc["obj"], oc["V"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", type=int, default=2)
    ap.add_argument("--recdir", default="out/btl6/recG")
    ap.add_argument("--params", default="scratchpad/btl5/params/final_g.txt")
    ap.add_argument("--valfn", default="scratchpad/btl6/params/valfn4_G.npz")
    ap.add_argument("--seed0", type=int, default=84001)
    ap.add_argument("--seed1", type=int, default=84841)
    ap.add_argument("--require", type=int, default=2, help="the record's first N passes exist ...")
    ap.add_argument("--require-ok", type=int, default=2, help="... and the first N' are ok")
    ap.add_argument("--out", required=True)
    ap.add_argument("--init", default="")
    ap.add_argument("--basis", type=int, default=5)
    ap.add_argument("--sigma", type=float, default=0.01, help="sd of a T0 knot correction (activation units)")
    ap.add_argument("--gsigma", type=float, default=0.005, help="sd of a gain-block knot correction")
    ap.add_argument("--knob-sigma", type=float, default=1.0, help="knobs on (> 0) or off (0)")
    ap.add_argument("--knob-std", type=float, default=0.0, help="initial sd of the knob dimensions in standardized units (dacd 1 ms, aim 3 mm, posture 0.01, lead 2 ms, knee 0.15 m/s, scale 0.1, clock per uv 10 ms); 0: sigma-like")
    ap.add_argument("--lim0", type=float, default=0.15)
    ap.add_argument("--limg", type=float, default=0.10)
    ap.add_argument("--pop", type=int, default=48)
    ap.add_argument("--batch", type=int, default=32)
    ap.add_argument("--gens", type=int, default=150)
    ap.add_argument("--full", type=int, default=10)
    ap.add_argument("--eps", type=float, default=0.15)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--cma-seed", type=int, default=7)
    ap.add_argument("--val-mod", type=int, default=10)
    ap.add_argument("--val-lo", type=int, default=7)
    ap.add_argument("--gmax", type=float, default=None)
    ap.add_argument("--energy", action="store_true", help="fit ONLY the energy-hinge block (skill keys pg_vn, pgv<stage>_*, pgvk, pgvs) and its knee / scale: starts with a strong incoming ball are untouched")
    ap.add_argument("--vmax", type=float, default=1.3, help="with --energy: only starts whose vertical speed at the crossing is below this are simulated")
    ap.add_argument("--strong", action="store_true", help="with --energy: fit the STRONG-side apex block (the 8th block: uw = clip((apex - wk) / ws, 0, 2.5), keys pgw / pgwk / pgws) instead of the weak-side one")
    ap.add_argument("--wk0", type=float, default=0.7)
    ap.add_argument("--ws0", type=float, default=0.05)
    ap.add_argument("--vsel", type=int, default=0, help="with --energy: 1 = the hinge's argument is the incoming ball's apex (knee in metres), 0 = its vertical speed at the crossing")
    ap.add_argument("--vmin", type=float, default=-9.0, help="with --energy: only starts whose hinge argument is at least this are simulated")
    ap.add_argument("--vk0", type=float, default=1.0, help="with --energy: initial knee")
    ap.add_argument("--vs0", type=float, default=0.5, help="with --energy: initial scale")
    ap.add_argument("--units", type=float, default=1.0, help="re-express the stage's table in this many times wider feature units (function unchanged inside the old range)")
    ap.add_argument("--active-from", default="out/btl6/val_verdicts_G.pkl", help="pickle of the G chain flags (val_verdicts.py): stage 3 / 4 fits use the starts whose upstream delivery is clean")
    a = ap.parse_args()
    import fit3 as F
    use_knobs = a.knob_sigma > 0
    STRONG[0] = bool(a.strong)
    if a.energy and a.strong:
        KNOB_SCALE.update({"dvk": 0.02, "dvs": 0.01})
    if a.energy and a.vsel:
        KNOB_SCALE.update({"dvk": 0.02, "dvs": 0.01})       # the knee / scale of an APEX hinge are metres
    J = a.basis
    nb = len(blocks_of(a.energy)) * 16 * J
    nk = len(knob_names(a.stage, a.energy)) if use_knobs else 0
    dim = nb + nk
    ad = dict(vars(a))
    import chainrep as C0
    B0, nom0, sc0 = F.parse_stage(a.params, a.stage)
    from common import load as _load0
    _P = _load0(a.params)
    Bv0 = np.zeros((1, 16, NK))
    if _P.get("pg_vn", 0.0) > 0.5:
        for m_ in range(16):
            for k_ in range(NK):
                Bv0[0, m_, k_] = _P.get(f"pgv{a.stage}_{m_}_{k_}", 0.0)
    Bw0 = np.zeros((1, 16, NK))
    if _P.get("pg_vn", 0.0) > 0.5:
        for m_ in range(16):
            for k_ in range(NK):
                Bw0[0, m_, k_] = _P.get(f"pgw{a.stage}_{m_}_{k_}", 0.0)
    B0 = np.concatenate([B0, Bv0, Bw0], axis=0)
    if a.units != 1.0:
        B0 = B0.copy()
        B0[1:6] = B0[1:6] * a.units
        sc0 = sc0 * a.units
    from common import load as _load
    P0 = _load(a.params)
    acd0 = P0.get(f"pg_acd{a.stage}", P0.get("pg_acd", 0.0025))
    lead0 = P0.get(f"pg_lead{a.stage}", P0.get("pg_lead", 0.165))

    def absolute(m):
        dB, kn = expand(m, J, a.stage, use_knobs, a.lim0, a.limg, a.energy)
        B = B0 + dB
        nom = nom0.copy()
        acd, lead = acd0, lead0
        vk, vs = (a.vk0, a.vs0) if a.energy else (P0.get(f"pgvk{a.stage}", a.vk0), P0.get(f"pgvs{a.stage}", a.vs0))
        if kn:
            k = kn[a.stage]
            if "dnom" in k:
                nom = nom + k["dnom"]
                acd = acd0 + k["dacd"]
                lead = lead0 + k.get("dlead", 0.0)
            if "dvk" in k:
                vk, vs = a.vk0 + k["dvk"], a.vs0 + k["dvs"]
            if "dwk" in k:
                wk, ws = a.wk0 + k["dwk"], a.ws0 + k["dws"]
        wk, ws = (P0.get(f"pgwk{a.stage}", a.wk0), P0.get(f"pgws{a.stage}", a.ws0)) if not (a.energy and a.strong) else (a.wk0, a.ws0)
        if kn and "dwk" in kn[a.stage]:
            wk, ws = a.wk0 + kn[a.stage]["dwk"], a.ws0 + kn[a.stage]["dws"]
        kap = P0.get(f"pg_vts{a.stage}", 0.0) + (kn[a.stage].get("dkap", 0.0) if kn else 0.0)
        return dict(B=B, nom=nom, sc=sc0, acd=acd, lead=lead, vk=vk, vs=vs, wk=wk, ws=ws, strong=bool(a.strong), energy=a.energy or bool(P0.get("pg_vn", 0.0) > 0.5), vsel=a.vsel or int(P0.get(f"pg_vsel{a.stage}", 0)), kap=kap)

    t0 = time.time()
    with get_context("spawn").Pool(a.workers, initializer=init_worker, initargs=(ad,)) as pool:
        # which starts are active: ask a worker (they all hold the same set)
        keys = sorted(pool.apply(_keys))
        tr = [k for k in keys if (k - a.seed0) % a.val_mod < a.val_lo]
        va = [k for k in keys if (k - a.seed0) % a.val_mod >= a.val_lo]
        print(f"stage {a.stage}: active starts {len(keys)}: {len(tr)} training, {len(va)} validation; dims {dim} (basis {J}, knobs {nk}); load {time.time() - t0:.0f}s", flush=True)

        def score(cands, ks):
            jobs = [(ci, dB, kn, k) for ci, (dB, kn) in enumerate(cands) for k in ks]
            res = pool.map(eval_job, jobs, chunksize=max(1, len(jobs) // (6 * a.workers)))
            obj = np.zeros(len(cands))
            V = np.zeros(len(cands))
            for ci, sd, o, v in res:
                obj[ci] += o
                V[ci] += v
            return obj / len(ks), V / len(ks)

        x0 = np.zeros(dim)
        if a.init:
            xi = np.load(a.init)["x"]
            x0[:min(len(xi), dim)] = xi[:dim] if len(xi) >= dim else xi
        opt = F.SepCMA(x0, a.sigma, seed=a.cma_seed, popsize=a.pop)
        # per-dimension initial scale: T0 coefficients sigma, gain blocks gsigma, knobs knob_sigma (standardized units)
        sc = np.ones(dim) * a.sigma
        if not a.energy:
            sc[:16 * J] = a.sigma
            sc[16 * J:nb] = a.gsigma
        if nk:
            sc[nb:] = a.knob_sigma * a.sigma
            if a.knob_std > 0:                       # initial sd of the knob dimensions in STANDARDIZED knob units (scale: KNOB_SCALE per unit)
                sc[nb:] = a.knob_std
        opt.C = (sc / a.sigma) ** 2
        g0 = score([(None, None)], tr)
        v0 = score([(None, None)], va)
        print(f"G (replay): train obj {g0[0][0]:.4f} V {g0[1][0]:.4f} | validation obj {v0[0][0]:.4f} V {v0[1][0]:.4f}", flush=True)
        rnd = random.Random(a.cma_seed)
        best = (g0[0][0], x0.copy())
        hist = []
        t1 = time.time()
        for g in range(a.gens):
            xs = opt.ask()
            cands = [expand(x, J, a.stage, use_knobs, a.lim0, a.limg, a.energy) for x in xs]
            batch = rnd.sample(tr, min(a.batch, len(tr)))
            obj, V = score(cands, batch)
            opt.tell(xs, -obj)
            if g % a.full == a.full - 1 or g == a.gens - 1:
                m = opt.mean.copy()
                cm = [expand(m, J, a.stage, use_knobs, a.lim0, a.limg, a.energy)]
                ot, vt = score(cm, tr)
                ov, vv = score(cm, va)
                rms = float(np.sqrt(np.mean(m ** 2)))
                msg = (f"gen {g} mean-vector: train obj {ot[0]:.4f} V {vt[0]:.4f} | validation obj {ov[0]:.4f} V {vv[0]:.4f} | |x| rms {rms:.4f} sigma {opt.sigma:.4f} "
                       f"gen-best batch obj {obj.min():.4f} (batch mean {obj.mean():.4f}) ({time.time() - t1:.0f}s)")
                print(msg, flush=True)
                hist.append((g, ot[0], vt[0], ov[0], vv[0]))
                np.savez(f"{a.out}_g{g}.npz", x=m, J=J, stage=a.stage, knobs=use_knobs, lim0=a.lim0, limg=a.limg, train_obj=ot[0], val_obj=ov[0], train_V=vt[0], val_V=vv[0], gen=g, **absolute(m))
                if ot[0] < best[0]:
                    best = (ot[0], m.copy())
                    np.savez(f"{a.out}.npz", x=m, J=J, stage=a.stage, knobs=use_knobs, lim0=a.lim0, limg=a.limg, train_obj=ot[0], val_obj=ov[0], train_V=vt[0], val_V=vv[0], gen=g, **absolute(m))
            elif g % 2 == 0:
                print(f"gen {g} gen-best {obj.min():.4f} batch mean {obj.mean():.4f} sigma {opt.sigma:.4f} ({time.time() - t1:.0f}s)", flush=True)
    print("done", flush=True)


def _keys():
    return list(_W["sts"].keys())


if __name__ == "__main__":
    main()
