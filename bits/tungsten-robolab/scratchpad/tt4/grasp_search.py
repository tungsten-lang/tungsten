#!/usr/bin/env python3
"""The grasp search (rules fixed in scratchpad/tt4/GRASP_SEARCH.md before any run; 2 Oct 2026). Separable CMA-ES over the champion's twelve grip parameters, each candidate scored under
T3's decelerating ideal pad-space servo (myo_tt_oracle mode o5, cfg o5_togo) on 30 training serves. A LABELLED DIAGNOSTIC ORACLE.

    .venv-myo/bin/python scratchpad/tt4/grasp_search.py search            # the search (about 90 minutes); state in scratchpad/tt4/gs_state.json, every candidate in gs_log.jsonl
    .venv-myo/bin/python scratchpad/tt4/grasp_search.py baseline          # the champion's grip on the training serves (calibrates the objective)
    .venv-myo/bin/python scratchpad/tt4/grasp_search.py final             # the best candidate and the champion grip on 70 validation serves and T3's set B (run ONCE)

Run from bits/tungsten-robolab. A file with a __main__ guard.
"""
import json
import math
import os
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

import numpy as np

W = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(W)
PY = ".venv-myo/bin/python"
PARAMS = ["g_fpl", "g_op", "g_text", "g_idx", "g_idx_int", "g_mid", "g_ring", "g_fext", "grip_drive", "grip_ramp", "bh_grip", "bh_grip_drive"]
LO = np.array([-0.2, -0.2, -0.5, -0.2, -0.2, -0.2, -0.2, -0.5, 0.0, 0.01, -0.2, 0.0])
HI = np.array([0.6, 0.6, 0.3, 0.6, 0.6, 0.6, 0.6, 0.3, 2.0, 0.3, 0.4, 0.8])
BASE_PARAMS = "params/myo_tt_p2_r10_c3.txt"
CONTROLLER = "bin/challengers/myo_tt_r10-n"
PLAN = "scratchpad/tt3/results/plan_bn0.1.json"
CFG = {"o5_togo": 1, "o5_tact": 0.30, "o5_hold": 0.03, "o5_wrot": 0.30}
TRAIN = (98000, 98030)
VALID = (98030, 98100)
SETB = (830000, 830100)
OUT = "out/tt4/gs"
STATE = "scratchpad/tt4/gs_state.json"
LOGF = "scratchpad/tt4/gs_log.jsonl"
MAX_GEN, MAX_SECONDS, LAM = 30, 90 * 60, 12


def champion_x():
    p = {}
    for line in open(BASE_PARAMS):
        t = line.split()
        if len(t) >= 2 and not line.startswith("#"):
            p[t[0]] = float(t[1])
    return np.array([p.get(n, {"bh_grip": 0.0, "bh_grip_drive": 0.0}.get(n)) for n in PARAMS], float)


def run_serves(x, tag, seeds, workers=3, oracle=True):
    d = os.path.join(OUT, tag)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d, exist_ok=True)
    env = dict(os.environ, TT_ENV="P2", TT_SAVE_LOG=d + "/logs", OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1", VECLIB_MAXIMUM_THREADS="1", MKL_NUM_THREADS="1")   # one thread per rollout worker
    if oracle:
        env.update(MYO_TT_ORACLE="o5", TT_TASK="myo_tt_oracle", TT3_PLAN=PLAN, TT3_CFG=json.dumps(CFG), TT3_LOG=d + "/orc")
    setstr = ",".join(f"{n}={v:.6g}" for n, v in zip(PARAMS, x))
    cmd = ["nice", "-n", "10", PY, "playground/tt_eval.py", "--params", BASE_PARAMS, "--controller", CONTROLLER, "--seeds", f"{seeds[0]}:{seeds[1]}", "--set", setstr,
           "--out", d + "/rows.jsonl", "--workers", str(workers)]
    with open(d + "/out.txt", "w") as fo:
        subprocess.run(cmd, env=env, stdout=fo, stderr=subprocess.STDOUT)
    return d


def metrics(d, seeds):
    n = seeds[1] - seeds[0]
    contact = lost = never = 0
    pos, ori = [], []
    rows = {}
    try:
        for line in open(os.path.join(d, "rows.jsonl")):
            r = json.loads(line)
            rows[r["seed"]] = r
    except FileNotFoundError:
        pass
    solved = sum(1 for r in rows.values() if r.get("solved", 0) > 0)
    for s in range(seeds[0], seeds[1]):
        f = os.path.join(d, "logs", f"{s}.npz")
        if not os.path.exists(f):
            never += 1
            continue
        z = np.load(f, allow_pickle=True)
        L, k = z["L"], int(z["contact"])
        if k < 3:
            never += 1
            continue
        contact += 1
        dist = np.linalg.norm(L[:, 25:28], axis=1)
        if (dist[:k] > 0.5).any():
            lost += 1
        o = os.path.join(d, "orc", f"{s}.npz")
        if os.path.exists(o):
            zo = np.load(o, allow_pickle=True)
            if "pad_err" in zo.files and len(zo["pad_err"]) > 2:
                t, pe = np.asarray(zo["t"], float), np.asarray(zo["pad_err"], float)
                j = int(np.argmin(np.abs(t - L[k - 1, 0])))
                pos.append(100 * float(np.linalg.norm(pe[j, :3])))
                ori.append(float(pe[j, 3]))
    pm = float(np.median(pos)) if pos else 30.0
    om = float(np.median(ori)) if ori else 60.0
    lost_frac = lost / max(contact, 1)
    J = 20 * lost_frac + 2 * never / n + pm / 2 + om / 3 + 4 * (1 - solved / n)   # the last term: amendment of 2 Oct, see GRASP_SEARCH.md
    return dict(n=n, contact=contact, lost=lost, lost_frac=round(lost_frac, 3), never=never, pos_med=round(pm, 2), ori_med=round(om, 2), solved=solved, J=round(J, 4))


class SepCMA:
    """Separable CMA-ES (Ros and Hansen 2008) in box-normalised coordinates, minimising."""

    def __init__(self, x0, sigma, lam):
        self.n = n = len(x0)
        self.m, self.sigma, self.lam = np.array(x0, float), sigma, lam
        self.mu = lam // 2
        w = np.log(self.mu + 0.5) - np.log(np.arange(1, self.mu + 1))
        self.w = w / w.sum()
        self.mueff = 1.0 / (self.w ** 2).sum()
        self.cs = (self.mueff + 2) / (n + self.mueff + 5)
        self.ds = 1 + 2 * max(0.0, math.sqrt((self.mueff - 1) / (n + 1)) - 1) + self.cs
        self.cc = (4 + self.mueff / n) / (n + 4 + 2 * self.mueff / n)
        sep = (n + 2) / 3.0
        self.c1 = sep * 2 / ((n + 1.3) ** 2 + self.mueff)
        self.cmu = min(1 - self.c1, sep * 2 * (self.mueff - 2 + 1 / self.mueff) / ((n + 2) ** 2 + self.mueff))
        self.C = np.ones(n)
        self.ps = np.zeros(n)
        self.pc = np.zeros(n)
        self.gen = 0
        self.chin = math.sqrt(n) * (1 - 1 / (4 * n) + 1 / (21 * n * n))

    def ask(self, rng):
        D = np.sqrt(self.C)
        Z = rng.standard_normal((self.lam, self.n))
        return np.clip(self.m + self.sigma * Z * D, 0.0, 1.0)

    def tell(self, X, F):
        self.gen += 1
        order = np.argsort(F)[: self.mu]
        D = np.sqrt(self.C)
        old = self.m.copy()
        self.m = (self.w[:, None] * X[order]).sum(0)
        y = (self.m - old) / self.sigma
        self.ps = (1 - self.cs) * self.ps + math.sqrt(self.cs * (2 - self.cs) * self.mueff) * y / D
        hs = 1.0 if np.linalg.norm(self.ps) / math.sqrt(1 - (1 - self.cs) ** (2 * self.gen)) / self.chin < 1.4 + 2 / (self.n + 1) else 0.0
        self.pc = (1 - self.cc) * self.pc + hs * math.sqrt(self.cc * (2 - self.cc) * self.mueff) * y
        Y = (X[order] - old) / self.sigma
        self.C = (1 - self.c1 - self.cmu) * self.C + self.c1 * (self.pc ** 2 + (1 - hs) * self.cc * (2 - self.cc) * self.C) + self.cmu * (self.w[:, None] * Y ** 2).sum(0)
        self.sigma *= math.exp((self.cs / self.ds) * (np.linalg.norm(self.ps) / self.chin - 1))
        self.sigma = min(self.sigma, 0.5)


def to_x(u):
    return LO + np.asarray(u) * (HI - LO)


def to_u(x):
    return (np.asarray(x) - LO) / (HI - LO)


def log(rec):
    with open(LOGF, "a") as f:
        f.write(json.dumps(rec) + "\n")


def cmd_baseline():
    x = champion_x()
    d = run_serves(x, "baseline_train", TRAIN)
    m = metrics(d, TRAIN)
    print("champion grip, training serves, decelerating ideal servo:", m, flush=True)
    log({"kind": "baseline_train", "x": x.tolist(), **m})


def cmd_search():
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.default_rng(1)
    x0 = champion_x()
    es = SepCMA(to_u(x0), 0.15, LAM)
    best = {"J": 1e9}
    t0 = time.time()
    start_gen = 0
    if os.path.exists(STATE):
        st = json.load(open(STATE))
        es.m, es.sigma, es.C, es.ps, es.pc, es.gen = np.array(st["m"]), st["sigma"], np.array(st["C"]), np.array(st["ps"]), np.array(st["pc"]), st["gen"]
        best = st["best"]
        start_gen = st["gen"]
        t0 -= st.get("elapsed", 0)
        rng = np.random.default_rng(1 + start_gen)
        print(f"resumed at generation {start_gen}, best J {best['J']}", flush=True)
    for g in range(start_gen, MAX_GEN):
        if time.time() - t0 > MAX_SECONDS:
            print("time limit reached", flush=True)
            break
        U = es.ask(rng)
        if g == 0:
            U[0] = to_u(x0)   # the champion's own grip is candidate 0 of generation 0
        with ThreadPoolExecutor(max_workers=2) as ex:
            futs = [ex.submit(lambda i=i: metrics(run_serves(to_x(U[i]), f"g{g}_c{i}", TRAIN), TRAIN)) for i in range(LAM)]
            res = [f.result() for f in futs]
        F = np.array([r["J"] for r in res])
        for i, r in enumerate(res):
            log({"kind": "cand", "gen": g, "i": i, "x": to_x(U[i]).tolist(), **r})
            if r["J"] < best["J"]:
                best = {"J": r["J"], "x": to_x(U[i]).tolist(), "gen": g, "i": i, **{k: r[k] for k in ("lost_frac", "never", "pos_med", "ori_med", "solved", "contact")}}
        es.tell(U, F)
        print(f"gen {g}: best this gen J {F.min():.3f} (lost {res[int(F.argmin())]['lost']}/{res[int(F.argmin())]['contact']}, pos {res[int(F.argmin())]['pos_med']} cm, ori {res[int(F.argmin())]['ori_med']} deg), "
              f"best overall J {best['J']:.3f}, sigma {es.sigma:.3f}, {int(time.time() - t0)} s", flush=True)
        json.dump({"m": es.m.tolist(), "sigma": es.sigma, "C": es.C.tolist(), "ps": es.ps.tolist(), "pc": es.pc.tolist(), "gen": es.gen, "best": best, "elapsed": time.time() - t0}, open(STATE, "w"))
        if g == 0:
            print(f"   (champion grip = candidate 0: J {res[0]['J']}, lost {res[0]['lost']}/{res[0]['contact']}, pos {res[0]['pos_med']} cm, ori {res[0]['ori_med']} deg)", flush=True)
    print("SEARCH DONE", json.dumps(best), flush=True)


def cmd_final():
    st = json.load(open(STATE))
    best = np.array(st["best"]["x"])
    champ = champion_x()
    out = {}
    for label, x in (("champion grip", champ), ("best candidate", best)):
        for sname, seeds in (("validation 98030-98099", VALID), ("set B 830000-830099", SETB)):
            tag = f"final_{label.split()[0]}_{sname.split()[0]}"
            d = run_serves(x, tag, seeds, workers=6)
            m = metrics(d, seeds)
            out[f"{label} / {sname}"] = m
            print(f"{label:15s} {sname:24s} {m}", flush=True)
            log({"kind": "final", "label": label, "set": sname, "x": x.tolist(), **m})
    # context: the plain champion stroke (no oracle) with the best grip, validation serves
    d = run_serves(best, "final_plain_best", VALID, workers=6, oracle=False)
    print("plain champion stroke with the best grip, validation serves (hit / solved / lost before contact):", metrics(d, VALID), flush=True)
    d = run_serves(champ, "final_plain_champ", VALID, workers=6, oracle=False)
    print("plain champion stroke with the champion grip, validation serves:", metrics(d, VALID), flush=True)
    json.dump(out, open("scratchpad/tt4/gs_final.json", "w"), indent=1)


if __name__ == "__main__":
    {"search": cmd_search, "baseline": cmd_baseline, "final": cmd_final}[sys.argv[1]]()
