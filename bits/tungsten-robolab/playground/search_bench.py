"""search_bench: the benchmark behind playground/SEARCH.md.

Runs search methods (playground/search.py) on three problems at equal
rollout budgets, several seeds each, then scores every run's best solution
on held-out seeds:

  p1  standing broad jump, planar humanoid (tasks/search_jump.py), a
      deterministic clean start; variants are motion representations:
        rate   joint rate + duration (rep 1, 40 tunables; the main benchmark)
        goal   goal posture + duration (rep 0, 40)
        mrate  per-muscle contraction rate + duration (rep 2, 64)
        group  joint rates with per-group push-off onset and duration (rep 3, 47)
        ease<k> rate with every chunk's easing fixed to Easing k
                (0 min_jerk, 1 linear, 2 sine_in_out, 3 cubic_in, 4 cubic_out,
                5 quint_in, 6 expo_in, 7 step)
        ease_search  rate plus a searched easing per chunk (44)
        <variant>_robust  trained on the clean start plus perturbed starts
                1 and 2 (robust aggregate) instead of the clean start alone
      held out: 8 perturbed standing starts (seeds 101-108)
  p2  push-recovery balance on MyoSuite's chase-tag myoLeg
      (tasks/search_balance.py), trained on push seeds 1, 2 (robust
      aggregate); variants are midpoint representations, all with the same 11
      reflex / balance gains:
        a  hand-designed symmetric posture (5) + gains = 16
        b  joint-space posture: 14 per-joint offsets through Geometry + gains = 25
        c  contraction space: 80 per-muscle offsets + gains = 91
        d  synergies: k coefficients on a basis distilled from the best b / c
           contraction vectors (see `synergy`) + gains
        gains  the gains alone (posture at the default) = 11
        <variant>_k4  trained on push schedules 1-4 instead of 1-2
        <variant>_fresh  trained on 2 fresh push schedules per generation
                (seeds >= 1000, never the held-out ones)
      held out: 10 push schedules (seeds 101-110)
      keyframe variants (controller bin/frozen/robolab_search_jump_v2, task
      search_jump_v2): kf (rep 4: a 22-muscle contraction vector + a duration
      per chunk, 104 tunables), kf_linear / kf_ease (its easing linear /
      searched), kf_speed (rep 5: contraction vector + speed), kf_syn (4
      synergy coefficients per keyframe from `kf_synergy`), kf_init / goal_init
      (the best goal-posture jump as keyframes / as postures, refined at
      sigma0 0.05)
  p4  consecutive broad jumps (tasks/search_hops.py, 6 s, `loop` 1): goal,
      kf, kf_speed, kf_syn; held out on 8 starts perturbed 0.01 rad
  p3  the running skill, FROZEN (tasks/search_run.py, bin/frozen/robolab_run),
      its 73 practised tunables from params/search/run_frozen_init.txt,
      trained on the clean start and one perturbed start (20 s each)
      held out: the clean start plus 5 perturbed starts (seeds 101-105)
      variants: tunables (initial step sigma0 0.08 of each box, as
      robust_practice.py uses), tunables_small (sigma0 0.02)

usage (MyoSuite problems need .venv-myo/bin/python):
  python playground/search_bench.py run p1 rate --methods cma,sep_cma --seeds 1,2,3 --budget 1000
  python playground/search_bench.py synergy --k 6
  python playground/search_bench.py report p1
Results: out/search/<problem>/<variant>/<method>_s<seed>.{json,jsonl,npz,txt};
a finished run (its .json exists) is skipped, so a killed benchmark resumes.
"""

import argparse
import hashlib
import json
import math
import multiprocessing as mp
import os
import sys
import time

# One BLAS thread: the optimizers' linear algebra is small, and on a loaded machine
# a thread per core (OpenBLAS in the MyoSuite venv) made each GP fit take ~100 s.
for _v in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_v, "1")

import numpy as np  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import search  # noqa: E402
from practice import read_params  # noqa: E402

OUT = os.path.join(ROOT, "out", "search")
GAINS = ["stiff", "kp", "kd", "k_ap", "k_apv", "d_ap", "k_hp", "k_hpv", "k_ml", "k_mlv", "spring"]
SYMMETRIC = ["hip", "knee", "ankle", "add", "sub"]
SYNERGY_FILE = os.path.join(ROOT, "params", "search", "balance_synergies.npz")
RUN_INIT = os.path.join(ROOT, "params", "search", "run_frozen_init.txt")


def clip01(v):
    return float(min(max(v, 0.0), 1.0))


def first(ms, key, default=0.0):
    v = ms[0].get(key, default) if ms else default
    return default if v is None else float(v)


# ---------------------------------------------------------------------------
# problems


KEYFRAME_VARIANTS = {"kf": {"rep": 4}, "kf_linear": {"rep": 4, "ease": 1}, "kf_ease": {"rep": 4, "ease_search": 1},
                     "kf_speed": {"rep": 5}, "kf_syn": {"rep": 4}, "kf_init": {"rep": 4}, "goal_init": {"rep": 0}}
KF_SYNERGY_FILE = os.path.join(ROOT, "params", "search", "jump_keyframe_synergies.npz")
BEST_GOAL = os.path.join(OUT, "p1", "goal", "bo_s1.json")  # the best jump (0.91 m), which kf_init / goal_init refine


def jump_descriptor(ms):  # take-off velocity: (vx in [-1, 3], vz in [-0.5, 2.5]) m/s
    return (clip01((first(ms, "takeoff_vx") + 1.0) / 4.0), clip01((first(ms, "takeoff_vz") + 0.5) / 3.0))


def keyframe_problem(task, variant, seeds, name, held):
    """P1 / P4 on the v2 controller: goal postures (rep 0) or keyframes."""
    fixed = dict(KEYFRAME_VARIANTS.get(variant, {"rep": 0}))
    tun = search.describe(task, fixed)
    init = None
    if variant in ("kf_init", "goal_init"):
        init = best_goal_params(fixed["rep"])
        held = dict(held, sigma0=0.05)
    rep = search.BoxRep.from_tunables(tun, init=init, fixed=fixed)
    if variant == "kf_syn":
        rep = keyframe_synergy_rep(tun, fixed)
    return search.Problem(task, rep, seeds, 0.0, 0.5, jump_descriptor, name=name), held


def p1(variant):
    seeds = [None]
    if variant.endswith("_robust"):  # train on the clean start plus two perturbed starts
        seeds = [None, 1, 2]
        variant = variant[:-len("_robust")]
    if variant in KEYFRAME_VARIANTS:
        return keyframe_problem("search_jump_v2", variant, seeds, f"p1/{variant}",
                                {"seeds": list(range(101, 109)), "seconds": 0.0, "sigma0": 0.15})
    fixed = {"rep": 1}
    if variant == "goal":
        fixed = {"rep": 0}
    elif variant == "mrate":
        fixed = {"rep": 2}
    elif variant == "group":
        fixed = {"rep": 3}
    elif variant.startswith("ease") and variant != "ease_search":
        fixed = {"rep": 1, "ease": int(variant[4:])}
    elif variant == "ease_search":
        fixed = {"rep": 1, "ease_search": 1}
    elif variant != "rate":
        raise SystemExit(f"p1 has no variant {variant}")
    tun = search.describe("search_jump", fixed)
    rep = search.BoxRep.from_tunables(tun, fixed=fixed)

    def descriptor(ms):  # take-off velocity: (vx in [-1, 3], vz in [-0.5, 2.5]) m/s
        return (clip01((first(ms, "takeoff_vx") + 1.0) / 4.0), clip01((first(ms, "takeoff_vz") + 0.5) / 3.0))

    name = f"p1/{variant}" + ("_robust" if len(seeds) > 1 else "")
    prob = search.Problem("search_jump", rep, seeds, 0.0, 0.5, descriptor, name=name)
    return prob, {"seeds": list(range(101, 109)), "seconds": 0.0, "sigma0": 0.15}


def p2(variant):
    seeds, fresh, suffix = [1, 2], 0, ""
    if variant.endswith("_k4"):  # train on four push schedules instead of two
        seeds, suffix = [1, 2, 3, 4], "_k4"
        variant = variant[:-len("_k4")]
    elif variant.endswith("_fresh"):  # two new push schedules every generation
        fresh, suffix = 2, "_fresh"
        variant = variant[:-len("_fresh")]
    tun = search.describe("search_balance")
    if variant == "a":
        only = GAINS + SYMMETRIC
    elif variant == "b":
        only = GAINS + ["dq_*"]
    elif variant in ("c", "d"):
        only = GAINS + ["dc_*"]
    elif variant == "gains":
        only = GAINS
    else:
        raise SystemExit(f"p2 has no variant {variant}")
    rep = search.BoxRep.from_tunables(tun, only=only)
    if variant == "d":
        rep = synergy_rep(tun)

    def descriptor(ms):  # (mean pelvis height in [0.75, 1.0] m, effort in [0, 0.15])
        z = float(np.mean([m.get("pelvis_z", 0.75) or 0.75 for m in ms]))
        e = float(np.mean([m.get("effort", 0.0) or 0.0 for m in ms]))
        return (clip01((z - 0.75) / 0.25), clip01(e / 0.15))

    prob = search.Problem("search_balance", rep, seeds, 0.0, 0.5, descriptor, name=f"p2/{variant}{suffix}", fresh=fresh)
    return prob, {"seeds": list(range(101, 111)), "seconds": 0.0, "sigma0": 0.15}


def synergy_rep(tun):
    if not os.path.exists(SYNERGY_FILE):
        raise SystemExit(f"no synergy basis: run `search_bench.py synergy` first ({SYNERGY_FILE})")
    z = np.load(SYNERGY_FILE, allow_pickle=False)
    base = search.BoxRep.from_tunables(tun, only=GAINS)
    names = [str(n) for n in z["names"]]
    box = {t[0]: (t[2], t[3]) for t in tun}
    return search.SynergyRep(base, names, z["basis"], z["zmax"], [box[n][0] for n in names], [box[n][1] for n in names])


def p3(variant):
    sigma0 = {"tunables": 0.08, "tunables_small": 0.02}.get(variant)
    if sigma0 is None:
        raise SystemExit("p3 variants: tunables (sigma0 0.08, as robust_practice.py), tunables_small (sigma0 0.02)")
    init = read_params(RUN_INIT)
    tun = search.describe("search_run", init)
    rep = search.BoxRep.from_tunables(tun, only=list(init), init=init)

    def descriptor(ms):  # (step frequency in [2, 4.5] /s, torso pitch in [-0.2, 0.4] rad)
        return (clip01((first(ms, "step_freq", 2.0) - 2.0) / 2.5), clip01((first(ms, "torso_pitch") + 0.2) / 0.6))

    prob = search.Problem("search_run", rep, [None, 1], 20.0, 0.5, descriptor, name=f"p3/{variant}")
    return prob, {"seeds": [None] + list(range(101, 106)), "seconds": 20.0, "sigma0": sigma0}


def p4(variant):
    """Consecutive broad jumps (tasks/search_hops.py, 6 s): goal postures or
    keyframes. Held out on 8 perturbed starts at a milder 0.01 rad (the
    single jump already falls from nearly every 0.04 rad start)."""
    if variant not in ("goal", "kf", "kf_speed", "kf_syn"):
        raise SystemExit("p4 variants: goal, kf, kf_speed, kf_syn")
    return keyframe_problem("search_hops", variant, [None], f"p4/{variant}",
                            {"seeds": list(range(101, 109)), "seconds": 0.0, "sigma0": 0.15,
                             "attrs": {"noise": 0.01, "pitch_noise": 0.005}})


# p5: the jump with feedback (bin/frozen/robolab_search_jump_v3), trained on
# perturbed starts. The arena trial `search_jump` scores the clean start and
# starts 101-107 perturbed by 0.001 rad; p5 never trains or validates on them:
# it trains on starts 1001-1004 at that perturbation size and holds out
# starts 2001-2024 (plus 4001-4024 at 0.003 rad with `recheck`; the arena
# trial `search_jump_robust` holds out 3001-3032 at 0.003 rad).
FB_TASK = "search_jump_v3"
FB_ATTRS = {"noise": 0.001, "pitch_noise": 0.0005}
FB_TRAIN = [1001, 1002, 1003, 1004]
FB_VALID = list(range(2001, 2025))
KF_BEST = os.path.join(OUT, "p1", "kf_init", "oneplusone_s2.json")  # the refined keyframe jump (1.522 m clean)
KF_BO = os.path.join(OUT, "p1", "kf_init", "bo_s1.json")  # the BO-refined keyframes (1.366 m clean)
FB_SWITCHES = {
    "land": {"fb_touch": 1, "fb_land": 1, "fb_stand": 1},
    "takeoff": {"fb_push": 1, "fb_takeoff": 1, "fb_touch": 1, "fb_land": 1, "fb_stand": 1},
    "latch": {"fb_takeoff": 1, "fb_touch": 1},
    # every feedback switch; a start that had fb_stand keeps it
    "all": {"fb_push": 1, "fb_takeoff": 1, "fb_touch": 1, "fb_flight": 1, "fb_land": 1},
}
# values that make a newly switched-on feedback a no-op (push-off on the clock
# as before, zero correction gains), so an "all" variant's x0 is its start's
# jump exactly; a start's own tuned values override them
FB_NEUTRAL = {"push_z": 0.45, "push_late": 0.0, "land_spring": 0.08, "k_la": 0.0, "k_lh": 0.0, "k_lk": 0.0,
              "k_ls": 0.0, "k_larm": 0.0, "k_lp": 0.0, "kd_lp": 0.0, "land_cc": 0.0}
# the feedback tunables (and the landing reflex gain), by name or prefix
FEEDBACK = ["push_*", "to_z", "td_z", "fl_pitch", "fl_vx", "k_f*", "kd_fp", "land_spring", "land_cc", "d_land", "k_l*",
            "p_land", "kd_lp", "stand_*", "g_land"]
# variant: (start, switches, searched tunables, sigma0); a start is "kf" (the
# refined keyframe jump), "goal" (the arena champion's posture jump), "kfbo"
# (the BO-refined keyframes), "goal_hand" (the posture jump with hand-set
# latches) or another p5 variant (its best run by training score)
P5_VARIANTS = {
    "kf_land": ("kf", "land", FEEDBACK, 0.15),          # (a) keyframes + landing correction
    "kf_takeoff": ("kf", "takeoff", FEEDBACK, 0.15),    # (b) + take-off latches
    "kf_all": ("kf_takeoff", "all", None, 0.03),        # (c) everything, from (b)'s best
    "goal_latch": ("goal", "latch", FEEDBACK, 0.15),    # (d) the posture jump + latches
    "goal_all": ("goal_hand", "all", None, 0.05),       # (d') everything, from the hand-set latch
    "kfbo_latch": ("kfbo", "latch", FEEDBACK, 0.15),    # the BO-refined keyframes + latches
    "kfbo_all": ("kfbo_latch_n3", "all", None, 0.03),   # everything, from its best
    "kfbo_polish": ("kfbo_all_n3", "all", None, 0.02),  # everything again, from kfbo_all_n3's best
    "kfbo_refine": ("kfbo_latch_n3", "all", None, 0.03),  # = kfbo_all, a separate name for the _legal reruns
    "kfbo_refine2": ("kfbo_refine_n3_legal", "all", None, 0.02),  # continue the legal refinement from its best
}
GOAL_HAND = os.path.join(ROOT, "params", "search", "jump_posture_latch.txt")  # the posture jump + hand-set latches


def p5_start(name):
    if name == "kf":
        return {k: v for k, v in json.load(open(KF_BEST))["params"].items()}
    if name == "goal":
        return {k: v for k, v in json.load(open(BEST_GOAL))["params"].items()}
    if name == "goal_hand":
        return read_params(GOAL_HAND)
    if name == "kfbo":
        return {k: v for k, v in json.load(open(KF_BO))["params"].items()}
    d = os.path.join(OUT, "p5", name)
    runs = [json.load(open(os.path.join(d, f))) for f in sorted(os.listdir(d)) if f.endswith(".json") and "_s" in f]
    if not runs:
        raise SystemExit(f"p5 variant {name} has no finished run to start from")
    return dict(max(runs, key=lambda r: r["best"])["params"])


def p5(variant):
    # suffixes: _fresh = 4 new starts every generation instead of FB_TRAIN;
    # _n3 = 8 fixed starts (1001-1008) perturbed three times as much (0.003
    # rad): 4 starts at 0.001 rad cannot see a 10 % fall rate
    # _n5 = 16 fixed starts (1001-1016) at 0.005 rad, for polishing a jump
    # whose fall rate at 0.003 rad is already too small for 8 starts to see;
    # _legal (outermost) = strict scoring: a foul (a toe past the take-off
    # line before the take-off) or an inverted ending scores as a fall. The
    # lenient runs found both exploits (a 0.2-0.6 m step before the jump, a
    # head-down finish on the feet).
    base, fresh, hard, strict = variant, False, None, False
    if base.endswith("_legal"):
        base, strict = base[:-len("_legal")], True
    if base.endswith("_fresh"):
        base, fresh = base[:-len("_fresh")], True
    for suffix in ("_n3", "_n5"):
        if base.endswith(suffix):
            base, hard = base[:-len(suffix)], suffix
    if base not in P5_VARIANTS:
        raise SystemExit(f"p5 variants: {', '.join(P5_VARIANTS)} (optionally _n3 or _n5, and / or _fresh)")
    start, sw, only, sigma0 = P5_VARIANTS[base]
    init = {**p5_start(start), **FB_SWITCHES[sw]}
    if sw == "all":
        init = {**FB_NEUTRAL, **init}
    fixed = {k: v for k, v in init.items() if k in ("rep",) or k.startswith("fb_")}
    tun = search.describe(FB_TASK, init)
    rep = search.BoxRep.from_tunables(tun, only=only, exclude=None if only else ["rep"], init=init, fixed=fixed)
    train, attrs = FB_TRAIN, FB_ATTRS
    if hard == "_n3":
        train, attrs = list(range(1001, 1009)), {"noise": 0.003, "pitch_noise": 0.0015}
    elif hard == "_n5":
        train, attrs = list(range(1001, 1017)), {"noise": 0.005, "pitch_noise": 0.0025}
    held = dict(FB_ATTRS)
    if strict:
        attrs, held = {**attrs, "strict": True}, {**held, "strict": True}
    prob = search.Problem(FB_TASK, rep, train, 0.0, 0.5, jump_descriptor, name=f"p5/{variant}",
                          fresh=4 if fresh else 0, attrs=attrs)
    return prob, {"seeds": FB_VALID, "seconds": 0.0, "sigma0": sigma0, "attrs": held}


PROBLEMS = {"p1": p1, "p2": p2, "p3": p3, "p4": p4, "p5": p5}
TASKS = {"p1": "search_jump", "p2": "search_balance", "p3": "search_run", "p4": "search_hops", "p5": "search_jump_v3"}


def failed(problem, m):
    """Did a held-out rollout fail? (p1: no take-off or a fall on landing;
    p2: fell; p3: fell)."""
    if "error" in m:
        return True
    if problem == "p5":  # a foul or an inverted ending counts too (it would not pass a legal trial)
        return (not m.get("takeoff")) or bool(m.get("fallen")) or bool(m.get("foul")) or bool(m.get("inverted"))
    if problem == "p1":
        return (not m.get("takeoff")) or bool(m.get("fallen"))
    if problem == "p4":
        return bool(m.get("fallen"))
    if problem == "p2":
        return not m.get("survived")
    return bool(m.get("fell"))


def fingerprint(problem):
    files = [os.path.join(HERE, f) for f in ("search.py", "practice.py", "bridge.py", "myo_bridge.py", "body.py")]
    files.append(os.path.join(HERE, "tasks", TASKS[problem] + ".py"))
    ctl = {"p1": "bin/frozen/robolab_search_jump", "p2": "bin/frozen/robolab_search_balance",
           "p3": "bin/frozen/robolab_run", "p4": "bin/frozen/robolab_search_jump_v2",
           "p5": "bin/frozen/robolab_search_jump_v3"}[problem]
    files.append(os.path.join(ROOT, ctl))
    if problem in ("p1", "p4"):
        files.append(os.path.join(HERE, "tasks", "search_jump_v2.py"))
        files.append(os.path.join(ROOT, "bin", "frozen", "robolab_search_jump_v2"))
    out = {}
    for f in files:
        if os.path.exists(f):
            out[os.path.relpath(f, ROOT)] = hashlib.md5(open(f, "rb").read()).hexdigest()[:12]
    return out


# ---------------------------------------------------------------------------
# running


def run(problem, variant, methods, seeds, budget, workers, extra=None):
    prob, held = PROBLEMS[problem](variant)
    d = os.path.join(OUT, problem, variant)
    os.makedirs(d, exist_ok=True)
    fp_start = fingerprint(problem)  # the files the workers load (compared again when each group ends)
    print(f"{prob.name}: {prob.rep.n} dims, k={prob.k}, budget {budget}, methods {methods}, seeds {seeds}", flush=True)
    with mp.Pool(workers) as pool:
        for method in methods:
            todo = [s for s in seeds if not os.path.exists(os.path.join(d, f"{method}_s{s}.json"))]
            if not todo:
                continue
            ss = []
            for s in todo:
                stem = os.path.join(d, f"{method}_s{s}")
                ss.append(search.Search(prob, method, budget, seed=s, sigma0=held["sigma0"], out=stem + ".txt",
                                        log=stem + ".jsonl", archive=stem + ".npz", label=f"{prob.name}/{method}/s{s}",
                                        **(extra or {})))
            t0 = time.time()
            last = [0.0]

            def progress(s):
                if time.time() - last[0] > 60:
                    last[0] = time.time()
                    print(f"  {s.label} used {s.used} best {s.best[0]:.4f} ({time.time() - t0:.0f}s)", flush=True)

            search.run_searches(ss, pool, progress)
            wall = time.time() - t0
            for s in ss:
                sc, ms = search.evaluate_params(pool, prob.task, s.params(), held["seeds"], held["seconds"],
                                                held.get("attrs"))
                summ = s.summary()
                summ.update(problem=problem, variant=variant, dims=prob.rep.n, k=prob.k, group_wall=round(wall, 1),
                            group_size=len(ss), heldout={"seeds": held["seeds"], "scores": sc,
                                                         "mean": float(np.mean(sc)), "median": float(np.median(sc)),
                                                         "fails": int(sum(failed(problem, m) for m in ms)),
                                                         "metrics": ms},
                            fingerprint=fingerprint(problem), fingerprint_start=fp_start,
                            files_changed=sorted(k for k, v in fingerprint(problem).items() if fp_start.get(k) != v),
                            time=time.strftime("%Y-%m-%d %H:%M:%S"))
                with open(os.path.join(d, f"{method}_s{s.seed}.json"), "w") as f:
                    json.dump(search.jsonable(summ), f)
                print(f"{s.label}: best {s.best[0]:.4f} held-out mean {np.mean(sc):.4f} fails {summ['heldout']['fails']}"
                      f"/{len(sc)} (group wall {wall:.0f}s)", flush=True)


def baseline(problem, variant, workers):
    """Score the problem's x0 (the hand design or the practised params) on the
    training seeds and the held-out seeds: the reference row of each table."""
    prob, held = PROBLEMS[problem](variant)
    d = os.path.join(OUT, problem, variant)
    os.makedirs(d, exist_ok=True)
    x0 = prob.rep.x0
    with mp.Pool(workers) as pool:
        tr = pool.map(search.rollout, prob.jobs(x0), chunksize=1)
        sc, ms = search.evaluate_params(pool, prob.task, prob.rep.decode(x0), held["seeds"], held["seconds"],
                                        held.get("attrs"))
    out = {"problem": problem, "variant": variant, "train": prob.aggregate(tr), "heldout": {
        "seeds": held["seeds"], "scores": sc, "mean": float(np.mean(sc)), "median": float(np.median(sc)),
        "fails": int(sum(failed(problem, m) for m in ms)), "metrics": ms}, "fingerprint": fingerprint(problem)}
    with open(os.path.join(d, "baseline.json"), "w") as f:
        json.dump(search.jsonable(out), f)
    print(f"{prob.name} x0: train {out['train']:.4f} held-out mean {out['heldout']['mean']:.4f} "
          f"fails {out['heldout']['fails']}/{len(sc)}", flush=True)


def recheck(problem, attrs, seeds, workers, name):
    """Re-evaluate every finished run's best params (and x0) of a problem on
    `seeds` with task attributes `attrs` (e.g. a milder start perturbation);
    writes out/search/<problem>/recheck_<name>.json."""
    out = {"attrs": attrs, "seeds": seeds, "runs": {}}
    with mp.Pool(workers) as pool:
        for v in sorted(os.listdir(os.path.join(OUT, problem))):
            d = os.path.join(OUT, problem, v)
            if not os.path.isdir(d):
                continue
            todo = [f for f in sorted(os.listdir(d)) if f.endswith(".json") and "_s" in f]
            prob, held = PROBLEMS[problem](v)
            if os.path.exists(os.path.join(d, "baseline.json")):
                todo.append(("x0", prob.rep.decode(prob.rep.x0), held["seconds"]))
            for f in todo:
                if isinstance(f, tuple):
                    key, params, seconds = f[0], f[1], f[2]
                else:
                    r = json.load(open(os.path.join(d, f)))
                    key, params, seconds = f[:-5], r["params"], {"p3": 20.0}.get(problem, 0.0)
                sc, ms = search.evaluate_params(pool, prob.task, params, seeds, seconds, attrs)
                out["runs"][f"{v}/{key}"] = {"mean": float(np.mean(sc)), "scores": sc,
                                             "fails": int(sum(failed(problem, m) for m in ms))}
                print(f"{v}/{key}: mean {np.mean(sc):.3f} fails {out['runs'][f'{v}/{key}']['fails']}/{len(sc)}", flush=True)
    with open(os.path.join(OUT, problem, f"recheck_{name}.json"), "w") as f:
        json.dump(search.jsonable(out), f)


# ---------------------------------------------------------------------------
# jump keyframes: the planar body's posture -> contraction map, in Python


JUMP_JOINTS = ["hip_flex", "knee", "ankle", "spine_flex", "shoulder_flex", "elbow"]
JUMP_STAND = [0.05, 0.12, -0.05, 0.08, 0.1, 0.4]
JUMP_DEFAULTS = {"crouch": [1.1, 1.5, -0.45, 0.45, -0.8, 0.2], "extend": [0.7, 0.0, 0.8, 0.4, 2.2, 0.2],
                 "flight": [1.5, 1.7, 0.0, 0.5, 1.2, 0.4], "land": [1.3, 1.5, -0.35, 0.7, 1.4, 0.4]}
JUMP_CHUNKS = ["crouch", "extend", "flight", "land"]
JUMP_DURS = {"crouch": 0.5, "extend": 0.22, "flight": 0.3, "land": 0.15}


def planar_muscles():
    from body import HumanoidBuilder
    b = HumanoidBuilder("planar")
    b.body_xml()
    return b.spec.muscles  # the handshake's muscle order


def jump_joint(mu):
    return mu.joint[2:] if mu.joint[:2] in ("l_", "r_") else mu.joint


def posture_c(muscles, q, stiff):
    """Contraction.set_joint for every muscle: the pair's contractions at the
    posture q (six jump-joint angles, left = right) plus stiff / 2."""
    out = np.zeros(len(muscles))
    for i, mu in enumerate(muscles):
        a = q[JUMP_JOINTS.index(jump_joint(mu))]
        span = mu.qmax - mu.qmin
        out[i] = ((a - mu.qmin) / span if mu.sign > 0 else (mu.qmax - a) / span) + stiff * 0.5
    return out


def jump_keyframes(p, rep):
    """The 4 chunk goals of a jump solution as contraction vectors (rep 0, 1,
    2 or 4 params) and the chunk durations."""
    mus = planar_muscles()
    stiff = p.get("stiff", 0.08)
    t = {nm: p.get(nm + "_t", JUMP_DURS[nm]) for nm in JUMP_CHUNKS}
    if "extend_t" not in p and rep == 3:
        raise ValueError("rep 3 is not converted")
    q_prev, c_prev = list(JUMP_STAND), posture_c(mus, JUMP_STAND, stiff)
    out = []
    for nm in JUMP_CHUNKS:
        if rep == 0:
            q = [p.get(f"{nm}_{j}", JUMP_DEFAULTS[nm][i]) for i, j in enumerate(JUMP_JOINTS)]
            c = posture_c(mus, q, stiff)
        elif rep == 1:
            q = [q_prev[i] + p[f"{nm}_w_{j}"] * t[nm] for i, j in enumerate(JUMP_JOINTS)]
            c = posture_c(mus, q, stiff)
            q_prev = q
        elif rep == 2:
            c = c_prev.copy()
            for i, mu in enumerate(mus):
                c[i] += p[f"{nm}_r_{jump_joint(mu)}_{'pos' if mu.sign > 0 else 'neg'}"] * t[nm]
        else:
            c = np.array([p[f"{nm}_c_{mu.name}"] for mu in mus])
        c_prev = c
        out.append(c)
    return out, t


def best_goal_params(rep):
    """kf_init / goal_init start: the best goal-posture jump, as rep 0 params
    or converted to rep 4 keyframes (same durations, drives and gains)."""
    p = {k: v for k, v in json.load(open(BEST_GOAL))["params"].items() if k != "rep"}
    if rep == 0:
        return p
    mus = planar_muscles()
    kfs, _ = jump_keyframes(p, 0)
    out = {k: v for k, v in p.items() if not any(k.startswith(nm + "_") and not k.endswith("_t") for nm in JUMP_CHUNKS)}
    for nm, c in zip(JUMP_CHUNKS, kfs):
        for mu, v in zip(mus, c):
            out[f"{nm}_c_{mu.name}"] = float(v)
    return out


def keyframe_synergy(m=4, min_score=0.2, out=KF_SYNERGY_FILE):
    """Per-keyframe synergy bases for the jump: every candidate of the p1
    goal / rate / mrate runs that jumped at least `min_score` m cleanly
    becomes 4 keyframe contraction vectors; each keyframe's deviations from
    its default get an uncentred SVD, whose m leading directions (range: 3
    RMS of the projections) form that keyframe's basis."""
    mus = planar_muscles()
    defaults = [posture_c(mus, JUMP_DEFAULTS[nm], 0.08) for nm in JUMP_CHUNKS]
    rows = [[] for _ in JUMP_CHUNKS]
    used = 0
    for v, rep in (("goal", 0), ("rate", 1), ("mrate", 2)):
        d = os.path.join(OUT, "p1", v)
        prob, _ = p1(v)
        for f in sorted(os.listdir(d)):
            if not f.endswith(".npz"):
                continue
            z = np.load(os.path.join(d, f))
            for x, sc in zip(z["X"], z["F"]):
                if sc < min_score:
                    continue
                kfs, _ = jump_keyframes(prob.rep.decode(x), rep)
                for k in range(4):
                    rows[k].append(kfs[k] - defaults[k])
                used += 1
    names, blocks, zmax, info = [], [], [], []
    for k, nm in enumerate(JUMP_CHUNKS):
        A = np.array(rows[k])
        U, S, Vt = np.linalg.svd(A, full_matrices=False)
        B = Vt[:m].T
        proj = A @ B
        zmax += list(3.0 * np.sqrt(np.mean(proj ** 2, axis=0)))
        blocks.append(B)
        names += [f"{nm}_c_{mu.name}" for mu in mus]
        info.append(np.round(S[:m] ** 2 / np.sum(S ** 2), 3).tolist())
    n = len(mus)
    basis = np.zeros((4 * n, 4 * m))
    for k, B in enumerate(blocks):
        basis[k * n:(k + 1) * n, k * m:(k + 1) * m] = B
    os.makedirs(os.path.dirname(out), exist_ok=True)
    np.savez(out, basis=basis, zmax=np.array(zmax), names=np.array(names), explained=np.array(info))
    print(f"jump keyframe synergies: {used} clean jumps >= {min_score} m; {m} per keyframe; explained {info}")


def keyframe_synergy_rep(tun, fixed):
    if not os.path.exists(KF_SYNERGY_FILE):
        raise SystemExit(f"no keyframe synergy basis: run `search_bench.py kf_synergy` first ({KF_SYNERGY_FILE})")
    z = np.load(KF_SYNERGY_FILE, allow_pickle=False)
    names = [str(n) for n in z["names"]]
    others = [t[0] for t in tun if t[0] not in names]
    base = search.BoxRep.from_tunables(tun, only=others, fixed=fixed)
    box = {t[0]: t for t in tun}
    return search.SynergyRep(base, names, z["basis"], z["zmax"], [box[n][2] for n in names], [box[n][3] for n in names],
                             origin=[box[n][1] for n in names])


# ---------------------------------------------------------------------------
# synergies (the SAR idea): a basis for contraction offsets from good b / c solutions


def geometry_tables():
    """Joint and muscle-length tables of the balance task's body, as MyoSim
    builds them for the controller (so the Python port matches Geometry)."""
    from practice import Sim, load_task
    task = load_task("search_balance")
    sim = Sim(task, params={})
    return sim


def contraction_of(sim, q):
    """Geometry#contraction for every muscle at joint posture q (a dict of
    joint name -> angle; others at the reference), exactly as body.w computes
    it (piecewise-linear length tables, additive over joints)."""
    names = [j[1] for j in sim.joints]
    qv = np.array([j[4] for j in sim.joints], float)
    for k, v in q.items():
        qv[names.index(k)] = v
    out = np.zeros(sim.n)
    for i in range(sim.n):
        L = sim.lref[i]
        for k, row in sim.table[i].items():
            lo, hi = sim.joints[k][2], sim.joints[k][3]
            row = np.asarray(row)

            def tl(x):
                u = (x - lo) / (hi - lo) * (len(row) - 1)
                if u <= 0:
                    return row[0]
                if u >= len(row) - 1:
                    return row[-1]
                a = int(math.floor(u))
                return row[a] + (row[a + 1] - row[a]) * (u - a)
            L += tl(qv[k]) - tl(sim.joints[k][4])
        out[i] = (sim.lr[i, 1] - L) / (sim.lr[i, 1] - sim.lr[i, 0])
    return out


def synergy(k=6, top=0.1, sources=("b", "c"), out=SYNERGY_FILE):
    """Distil a synergy basis from the best contraction vectors of the p2 b
    and c runs: each evaluated candidate in the top `top` fraction of its run
    becomes a contraction offset vector (c: its dc_ offsets; b: Geometry at
    its joint posture minus Geometry at the default posture, the same
    posture -> contraction map the controller uses); an uncentred SVD of the
    stack gives the k leading directions, and each coefficient's range is 3
    standard deviations of the elites' projections."""
    tun = search.describe("search_balance")
    dflt = {t[0]: t[1] for t in tun}
    dc_names = [t[0] for t in tun if t[0].startswith("dc_")]
    sim = geometry_tables()
    joints = ["hip_flexion", "hip_adduction", "hip_rotation", "knee_angle", "ankle_angle", "subtalar_angle", "mtp_angle"]
    base_sym = {"hip_flexion": dflt["hip"], "hip_adduction": dflt["add"], "knee_angle": dflt["knee"],
                "ankle_angle": dflt["ankle"], "subtalar_angle": dflt["sub"]}

    def posture(p):
        q = {}
        for side in ("_r", "_l"):
            for j in joints:
                name = j + side
                k = [jj[1] for jj in sim.joints].index(name)
                v = base_sym.get(j, sim.joints[k][4]) + p.get("dq_" + name, 0.0)
                q[name] = min(max(v, sim.joints[k][2]), sim.joints[k][3])
        return q

    c0 = contraction_of(sim, posture({}))
    rows, used = [], []
    for src in sources:
        d = os.path.join(OUT, "p2", src)
        if not os.path.isdir(d):
            continue
        prob, _ = p2(src)
        for f in sorted(os.listdir(d)):
            if not f.endswith(".npz"):
                continue
            z = np.load(os.path.join(d, f))
            X, F = z["X"], z["F"]
            keep = np.argsort(-F)[:max(3, int(top * len(F)))]
            for i in keep:
                p = prob.rep.decode(X[i])
                if src == "c":
                    rows.append([p.get(n, 0.0) for n in dc_names])
                else:
                    rows.append(contraction_of(sim, posture(p)) - c0)
            used.append(f"{src}/{f}")
    A = np.array(rows)
    U, S, Vt = np.linalg.svd(A, full_matrices=False)
    B = Vt[:k].T  # (80, k)
    proj = A @ B
    zmax = 3.0 * np.sqrt(np.mean(proj ** 2, axis=0))
    var = S ** 2 / np.sum(S ** 2)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    np.savez(out, basis=B, zmax=zmax, names=np.array(dc_names), explained=var[:k], sources=np.array(used))
    print(f"synergy basis: {len(rows)} elite vectors from {len(used)} runs; k={k}, explained "
          f"{np.round(var[:k], 3).tolist()} (cum {np.sum(var[:k]):.3f}); zmax {np.round(zmax, 3).tolist()}")
    for i in range(k):
        top_m = np.argsort(-np.abs(B[:, i]))[:6]
        print(f"  syn{i}: " + ", ".join(f"{dc_names[m][3:]} {B[m, i]:+.2f}" for m in top_m))


# ---------------------------------------------------------------------------


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("problem", choices=sorted(PROBLEMS))
    r.add_argument("variant")
    r.add_argument("--methods", required=True)
    r.add_argument("--seeds", default="1,2,3")
    r.add_argument("--budget", type=int, required=True)
    r.add_argument("--workers", type=int, default=2)
    s = sub.add_parser("synergy")
    s.add_argument("--k", type=int, default=6)
    s.add_argument("--top", type=float, default=0.1)
    s.add_argument("--sources", default="b,c")
    ks = sub.add_parser("kf_synergy")
    ks.add_argument("--m", type=int, default=4)
    ks.add_argument("--min-score", type=float, default=0.2)
    bl = sub.add_parser("baseline")
    bl.add_argument("problem", choices=sorted(PROBLEMS))
    bl.add_argument("variant")
    bl.add_argument("--workers", type=int, default=2)
    rc = sub.add_parser("recheck")
    rc.add_argument("problem", choices=sorted(PROBLEMS))
    rc.add_argument("name")
    rc.add_argument("--attrs", default="", help="task attributes name=value,...")
    rc.add_argument("--seeds", required=True)
    rc.add_argument("--workers", type=int, default=2)
    rp = sub.add_parser("report")
    rp.add_argument("problem", choices=sorted(PROBLEMS))
    a = ap.parse_args()
    if a.cmd == "run":
        run(a.problem, a.variant, a.methods.split(","), [int(x) for x in a.seeds.split(",")], a.budget, a.workers)
    elif a.cmd == "recheck":
        attrs = {kv.split("=")[0]: float(kv.split("=")[1]) for kv in a.attrs.split(",") if kv}
        recheck(a.problem, attrs, [int(x) for x in a.seeds.split(",")], a.workers, a.name)
    elif a.cmd == "baseline":
        baseline(a.problem, a.variant, a.workers)
    elif a.cmd == "kf_synergy":
        keyframe_synergy(a.m, a.min_score)
    elif a.cmd == "synergy":
        synergy(a.k, a.top, tuple(a.sources.split(",")))
    elif a.cmd == "report":
        import search_report
        search_report.report(a.problem)


if __name__ == "__main__":
    main()
