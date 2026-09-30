"""Identity checks of the labelled beyond-human arm task (agent T2).

    TT_ENV=P2 [MYO_TT_BEYOND=r] .venv-myo/bin/python scratchpad/tt2/identity.py --params P --controller C --seeds 98000,98001,...

With MYO_TT_BEYOND unset or 0: the OFFICIAL task (tasks/myo_tt.py MyoTTTask) against tasks/myo_tt_beyond.py at rung 0, on the standard path
(myo_bridge.MyoSim), and the beyond task on tt_fast's fast path (TT_TASK=myo_tt_beyond): every metric of every serve must be identical.
With MYO_TT_BEYOND=r (1-3): the beyond task's standard path against its fast path (the env is cached per worker process on the fast path),
and, printed beside them, the audit of the scaled model (beyond_rung, f0/vmax/tau ratios).
"""

import argparse
import os
import sys
import time

HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(HERE, "playground"))
os.environ.setdefault("TT_ENV", "P2")
os.environ["TT_TASK"] = "myo_tt_beyond"

import tt_fast  # noqa: E402


def standard(task_cls, params, ctl, seed):
    import myo_bridge as mb
    task = task_cls()
    sim = mb.MyoSim(task, params=params, controller=ctl, seed=seed)
    r = sim.run()
    r["seed"] = seed
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--params", required=True)
    ap.add_argument("--controller", required=True)
    ap.add_argument("--seeds", default="98000,98001,98002,98003,98004,98005")
    a = ap.parse_args()
    params = tt_fast.read_params(a.params)
    ctl = os.path.abspath(a.controller)
    seeds = [int(s) for s in a.seeds.split(",")]
    from tasks.myo_tt import MyoTTTask
    from tasks import myo_tt_beyond as mtb
    rung = mtb.RUNG
    print(f"MYO_TT_BEYOND={rung} TT_ENV={os.environ['TT_ENV']} beyond task env id {mtb.TASK.env_id} official env id {MyoTTTask.env_id}", flush=True)
    t0 = time.time()
    unit = rung == 9 and os.environ.get("MYO_TT_BEYOND_DIAG") == "1,1,1"   # post-verdict code-path check: the env subclass with unit multipliers
    off = [standard(MyoTTTask, params, ctl, s) for s in seeds] if (rung == 0 or unit) else None
    t1 = time.time()
    bey = [standard(mtb.TASK, params, ctl, s) for s in seeds]
    t2 = time.time()
    fast = [tt_fast.episode((params, s, None, ctl)) for s in seeds]
    t3 = time.time()
    n_bad = 0
    for i, s in enumerate(seeds):
        line = f"{s} solved {bey[i].get('solved')}"
        if off is not None:
            bad = tt_fast._cmp(off[i], {k: v for k, v in bey[i].items() if not k.startswith("beyond_")})
            n_bad += bool(bad)
            line += " | official vs beyond-0 (standard): " + ("IDENTICAL" if not bad else f"DIFFERENT {bad[:6]}")
        bad = tt_fast._cmp(bey[i], fast[i])
        n_bad += bool(bad)
        line += " | beyond standard vs fast: " + ("IDENTICAL" if not bad else f"DIFFERENT {bad[:6]}")
        if rung and not unit:
            line += f" | audit {[bey[i].get(k) for k in ('beyond_rung', 'beyond_f0_ratio', 'beyond_vmax_ratio', 'beyond_tau_ratio')]}"
        print(line, flush=True)
    print(f"official standard {t1 - t0:.1f}s, beyond standard {t2 - t1:.1f}s, beyond fast {t3 - t2:.1f}s for {len(seeds)} serves; {n_bad} differ", flush=True)
    sys.exit(1 if n_bad else 0)


if __name__ == "__main__":
    main()
