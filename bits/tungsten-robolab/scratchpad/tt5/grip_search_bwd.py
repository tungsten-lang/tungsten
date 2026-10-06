#!/usr/bin/env python3
"""GRIP SEARCH UNDER THE BACKWARD-PLAN SERVO (3 Oct 2026; pre-registered below). The 2 Oct grasp search stressed the grip with a gentle servo (1.5-2 g) and found +10 points that vanished with an ideal body; the backward plans
ask for 10-36 g and the champion's grip loses the paddle in 56 % of them (34 % / 37 % solved hand-held against 76 % / 77 % welded). Question: does ANY grip hold them? Separable CMA-ES (scratchpad/tt4/grasp_search.py's)
over the twelve grip parameters, objective = the share of 60 TRAINING plans solved hand-held (o1 settled pelvis + o5 pad-space servo + o7 trunk lock, torque caps at the isometric capacities; the plans are the 170 R2
picked in the welded caps sweep, `out/tt5/rerun_qdry.json`), minus 0.25 x the share that at least touched the ball. The remaining 110 plans are HELD OUT for the final comparison, run once: champion grip against the best.
PASS RULE (fixed before the search): the best grip solves at least 55 % of the 110 held-out plans (champion grip about 35 %) AND the paddle stays in the hand (palm_err_max < 0.3) on at least 70 % of them.
STOP RULE: 20 generations or 75 minutes. A LABELLED DIAGNOSTIC ORACLE.
    TT_ENV=P2 .venv-myo/bin/python scratchpad/tt5/grip_search_bwd.py search|final       from bits/tungsten-robolab"""
import json
import os
import sys
import time

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(ROOT)
os.environ["MYO_TT_ORACLE"] = "o1,o5,o7"
os.environ["TT3_CFG"] = json.dumps({"o5_togo": 1, "o5_tact": 0.15, "o5_hold": 0.03, "o5_wrot": 0.30, "o5_lead": 0.05, "o5_hold_alpha": 0.6, "o1_margin": 0.15, "o6_ton": 0.0, "o5_mus_off": 1, "o2_taumax_j": [90, 90, 90, 60, 13, 20, 25]})
os.environ["TT_ENV"] = "P2"
sys.path.insert(0, os.path.join(ROOT, "scratchpad", "tt4"))
sys.path.insert(0, os.path.join(ROOT, "scratchpad", "tt5"))
import grasp_search as gs  # noqa: E402  (chdirs to the bit root, defines SepCMA, PARAMS, LO, HI, champion_x, to_x, to_u)
import backward_plan as bp  # noqa: E402

STATE = "scratchpad/tt5/gsb_state.json"
LOGF = "scratchpad/tt5/gsb_log.jsonl"
MAX_GEN, MAX_SECONDS, LAM = 20, 75 * 60, 12


def plans():
    src = json.load(open("out/tt5/rerun_qdry.json"))
    out = []
    for r in src:
        sd = r["seed"]
        sp = 1.0 if r["kind"] == "best_s1" else 0.0
        plan = next(c["plan"] for c in bp.candidates(sd) if c["off"] == r["off"] and c["kind"] == r["kind"] and c["speed"] == sp)
        out.append((sd, plan))
    return out


def evaluate(x, items, tt_fast, base_params, ctl):
    params = dict(base_params)
    for n, v in zip(gs.PARAMS, x):
        params[n] = float(v)
    jobs = [(params, sd, None, ctl, {"orc_plan": plan}) for sd, plan in items]
    res = tt_fast.pool(6).map(tt_fast.episode, jobs, chunksize=1)
    n = len(res)
    solved = sum(1 for r in res if (r.get("solved") or 0) > 0)
    touched = sum(1 for r in res if (r.get("hit") or 0) > 0)
    kept = sum(1 for r in res if (r.get("palm_err_max") or 9) < 0.3)
    return dict(n=n, solved=solved, touched=touched, kept=kept, J=-(solved / n) - 0.25 * (touched / n))


def main():
    import tt_fast
    mode = sys.argv[1]
    base = tt_fast.read_params(bp.PARAMS)
    ctl = os.path.abspath(bp.CONTROLLER)
    allp = plans()
    train, held = allp[::3] + allp[1::3][:0], [p for i, p in enumerate(allp) if i % 3 != 0]
    train = train[:60] if len(train) >= 60 else train
    if mode == "final":
        st = json.load(open(STATE))
        best = np.array(st["best"]["x"])
        champ = gs.champion_x()
        for label, x in (("champion grip", champ), ("best grip", best)):
            m = evaluate(x, held, tt_fast, base, ctl)
            print(f"{label:14s} held-out {m['n']} plans: solved {m['solved']} ({100 * m['solved'] / m['n']:.0f} %), touched {m['touched']}, paddle kept {m['kept']} ({100 * m['kept'] / m['n']:.0f} %)", flush=True)
        return
    x0 = gs.champion_x()
    es = gs.SepCMA(gs.to_u(x0), 0.15, LAM)
    rng = np.random.default_rng(3)
    best, t0, start = {"J": 1e9}, time.time(), 0
    if os.path.exists(STATE):
        st = json.load(open(STATE))
        es.m, es.sigma, es.C, es.ps, es.pc, es.gen = np.array(st["m"]), st["sigma"], np.array(st["C"]), np.array(st["ps"]), np.array(st["pc"]), st["gen"]
        best, start = st["best"], st["gen"]
        t0 -= st.get("elapsed", 0)
        rng = np.random.default_rng(3 + start)
    print(f"{len(train)} training plans, {len(held)} held out; resumed at generation {start}", flush=True)
    for g in range(start, MAX_GEN):
        if time.time() - t0 > MAX_SECONDS:
            print("time limit", flush=True)
            break
        U = es.ask(rng)
        if g == 0:
            U[0] = gs.to_u(x0)
        res = []
        for i in range(LAM):
            m = evaluate(gs.to_x(U[i]), train, tt_fast, base, ctl)
            res.append(m)
            with open(LOGF, "a") as f:
                f.write(json.dumps({"gen": g, "i": i, "x": gs.to_x(U[i]).tolist(), **m}) + "\n")
            if m["J"] < best["J"]:
                best = {"J": m["J"], "x": gs.to_x(U[i]).tolist(), "gen": g, "i": i, "solved": m["solved"], "touched": m["touched"], "kept": m["kept"]}
        es.tell(U, np.array([r["J"] for r in res]))
        print(f"gen {g}: best this gen solved {max(r['solved'] for r in res)}/{len(train)} (kept {max(r['kept'] for r in res)}); best overall J {best['J']:.3f} solved {best.get('solved')} kept {best.get('kept')}; champion grip (gen 0 cand 0): "
              f"{res[0]['solved'] if g == 0 else '-'}; sigma {es.sigma:.3f}, {int(time.time() - t0)} s", flush=True)
        json.dump({"m": es.m.tolist(), "sigma": es.sigma, "C": es.C.tolist(), "ps": es.ps.tolist(), "pc": es.pc.tolist(), "gen": es.gen, "best": best, "elapsed": time.time() - t0}, open(STATE, "w"))
    print("SEARCH DONE", json.dumps({k: v for k, v in best.items() if k != "x"}), flush=True)


if __name__ == "__main__":
    main()
