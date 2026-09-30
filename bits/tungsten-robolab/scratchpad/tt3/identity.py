"""Identity check of the oracle task with its switch OFF (agent T3): the OFFICIAL task (tasks/myo_tt.py MyoTTTask, standard path myo_bridge.MyoSim) against tasks/myo_tt_oracle.py
with MYO_TT_ORACLE unset, on the standard path and on tt_fast's fast path (TT_TASK=myo_tt_oracle): every metric of every serve must be identical.
Optionally (--rec) also with MYO_TT_ORACLE=rec in a subprocess-free way is NOT possible (the switch is read at import), so run this script twice: MYO_TT_ORACLE unset, then MYO_TT_ORACLE=rec.

    TT_ENV=P2 [MYO_TT_ORACLE=rec] .venv-myo/bin/python scratchpad/tt3/identity.py --params params/myo_tt_p2_r10_c3.txt --controller bin/challengers/myo_tt_r10-n --seeds 98000,...
"""
import argparse
import os
import sys
import time

HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(HERE, "playground"))
os.environ.setdefault("TT_ENV", "P2")
os.environ["TT_TASK"] = "myo_tt_oracle"

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
    from tasks import myo_tt_oracle as mto
    print(f"MYO_TT_ORACLE={sorted(mto.MODES)} TT_ENV={os.environ['TT_ENV']} oracle task env id {mto.TASK.env_id} official env id {MyoTTTask.env_id}", flush=True)
    t0 = time.time()
    off = [standard(MyoTTTask, params, ctl, s) for s in seeds]
    t1 = time.time()
    orc = [standard(mto.TASK, params, ctl, s) for s in seeds]
    t2 = time.time()
    fast = [tt_fast.episode((params, s, None, ctl)) for s in seeds]
    t3 = time.time()
    extra = {"orc", "o1_tc", "o1_qc", "o2_tau_peak", "o4_t_hit", "fit_res_median"}
    n_bad = 0
    for i, s in enumerate(seeds):
        bad = tt_fast._cmp(off[i], {k: v for k, v in orc[i].items() if k not in extra})
        bad2 = tt_fast._cmp(orc[i], fast[i])
        n_bad += bool(bad) + bool(bad2)
        print(f"{s} solved {orc[i].get('solved')} | official vs oracle-task (standard): " + ("IDENTICAL" if not bad else f"DIFFERENT {bad[:6]}")
              + " | oracle-task standard vs fast: " + ("IDENTICAL" if not bad2 else f"DIFFERENT {bad2[:6]}"), flush=True)
    print(f"official standard {t1 - t0:.1f}s, oracle standard {t2 - t1:.1f}s, oracle fast {t3 - t2:.1f}s for {len(seeds)} serves; {n_bad} differ", flush=True)
    sys.exit(1 if n_bad else 0)


if __name__ == "__main__":
    main()
