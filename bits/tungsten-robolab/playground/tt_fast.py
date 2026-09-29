"""Fast table-tennis rollouts (round 10): the same episodes as playground/tasks/myo_tt.py, cheaper.

The standard path builds a whole MyoSim per episode: gym.make (MjSpec compile, ~1 s of CPU),
env reset, and the muscle-length geometry sweep (~600 mj_forward calls, ~1.5 s of CPU under
load), against ~0.6 s for the 1.1 s of simulated time itself. Two changes, both checked to
give bit-identical episodes (`check`):

  * the geometry sweep only needs actuator lengths, so it runs MuJoCo's kinematics ->
    comPos -> tendon -> transmission instead of mj_forward (which also runs collision
    detection and the constraint solver);
  * a worker process builds the environment once and only re-seeds and resets it.

`run_jobs` is a persistent spawn pool (workers keep their env between jobs). The arena's own
evaluation still uses the standard path; `check` shows the two agree serve for serve.

    .venv-myo/bin/python playground/tt_fast.py check --params params/x.txt --controller bin/x --seeds 98000,98001
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
for _v in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_v, "1")

import numpy as np  # noqa: E402

_ENVS = {}


def _lengths(m, d, muscle_ids):
    import mujoco
    mujoco.mj_kinematics(m, d)
    mujoco.mj_comPos(m, d)
    mujoco.mj_tendon(m, d)
    mujoco.mj_transmission(m, d)
    return d.actuator_length[muscle_ids].copy()


def fast_muscle_geometry(m, muscle_ids, ref_qpos, samples=None, coupled=False):
    """myo_bridge.muscle_geometry with kinematics-only length evaluation (same tables, bit for bit)."""
    import math
    import mujoco
    import myo_bridge as mb
    samples = samples or mb.SAMPLES
    fix = (lambda q: mb.couple_joints(m, q)) if coupled else (lambda q: q)
    ref_qpos = fix(np.array(ref_qpos, dtype=float))
    d = mujoco.MjData(m)
    d.qpos[:] = ref_qpos
    base = _lengths(m, d, muscle_ids)
    cand = []
    for j in range(m.njnt):
        if int(m.jnt_type[j]) not in (int(mujoco.mjtJoint.mjJNT_HINGE), int(mujoco.mjtJoint.mjJNT_SLIDE)):
            continue
        adr = m.jnt_qposadr[j]
        lo, hi = (m.jnt_range[j] if m.jnt_limited[j] else (-math.pi, math.pi))
        span = hi - lo
        d.qpos[:] = ref_qpos
        d.qpos[adr] = min(hi, ref_qpos[adr] + 0.02 * span)
        fix(d.qpos)
        up = _lengths(m, d, muscle_ids)
        d.qpos[:] = ref_qpos
        d.qpos[adr] = max(lo, ref_qpos[adr] - 0.02 * span)
        fix(d.qpos)
        dn = _lengths(m, d, muscle_ids)
        if np.max(np.abs(up - dn)) > 1e-7:
            cand.append((j, m.joint(j).name, float(lo), float(hi), float(ref_qpos[adr]), adr))
    table = [dict() for _ in muscle_ids]
    for k, (j, name, lo, hi, qref, adr) in enumerate(cand):
        rows = []
        for q in np.linspace(lo, hi, samples):
            d.qpos[:] = ref_qpos
            d.qpos[adr] = q
            fix(d.qpos)
            rows.append(_lengths(m, d, muscle_ids))
        rows = np.array(rows)
        for i in range(len(muscle_ids)):
            if np.max(rows[:, i]) - np.min(rows[:, i]) > 1e-6:
                table[i][k] = rows[:, i].tolist()
    return cand, table, base


def make_sim(task, params, seed, controller=None, reuse=True, fast_geometry=True):
    """A MyoSim for one episode; with `reuse` the env comes from the process's cache."""
    import myo_bridge as mb
    if fast_geometry:
        mb.muscle_geometry = fast_muscle_geometry
    if not reuse:
        return mb.MyoSim(task, params=params, controller=controller, seed=seed)
    from myosuite.utils import gym
    key = (task.env_id, repr(sorted(task.env_kwargs.items())))
    if key not in _ENVS:
        _ENVS[key] = gym.make(task.env_id, **task.env_kwargs)

    def cached(env_id, **kw):
        return _ENVS[key]

    # MyoSim.__init__ calls `gym.make` imported inside the function, so patch the module it imports from
    import myosuite.utils as mu
    old = mu.gym.make
    mu.gym.make = cached
    try:
        return mb.MyoSim(task, params=params, controller=controller, seed=seed)
    finally:
        mu.gym.make = old


def episode(job):
    """job = (params, seed, env_id or None, controller or None[, task attrs]) -> the episode's metrics."""
    params, seed, env_id, controller = job[:4]
    attrs = job[4] if len(job) > 4 else {}
    from tasks.myo_tt import MyoTTTask
    task = MyoTTTask()
    task.env_id = env_id or MyoTTTask.env_id
    for k, v in attrs.items():
        setattr(task, k, v)
    try:
        sim = make_sim(task, params, seed, controller=controller)
        res = sim.run()
    except Exception as e:  # a crashing rollout scores worst
        return {"seed": seed, "error": str(e)[:300]}
    res["seed"] = seed
    return res


_POOLS = {}


def pool(workers):
    import multiprocessing as mp
    if workers not in _POOLS:
        _POOLS[workers] = mp.get_context("spawn").Pool(workers, initializer=_init)
    return _POOLS[workers]


def _init():
    os.environ.setdefault("TT_ENV", "P2")
    if HERE not in sys.path:
        sys.path.insert(0, HERE)
    import warnings
    warnings.filterwarnings("ignore")


def run_jobs(jobs, workers=3, chunksize=1):
    """Run episode jobs on the persistent pool (order preserved)."""
    return pool(workers).map(episode, jobs, chunksize=chunksize)


def read_params(path):
    out = {}
    for line in open(path):
        t = line.split()
        if len(t) >= 2 and not line.startswith("#"):
            out[t[0]] = float(t[1])
    return out


def _cmp(a, b, path=""):
    if isinstance(a, dict) and isinstance(b, dict):
        bad = []
        for k in sorted(set(a) | set(b)):
            if k not in a or k not in b:
                bad.append(f"{path}{k}: missing")
            else:
                bad += _cmp(a[k], b[k], f"{path}{k}.")
        return bad
    if isinstance(a, (list, tuple)) and isinstance(b, (list, tuple)):
        if len(a) != len(b):
            return [f"{path}: len {len(a)} vs {len(b)}"]
        bad = []
        for i, (x, y) in enumerate(zip(a, b)):
            bad += _cmp(x, y, f"{path}{i}.")
        return bad
    if a != b:
        return [f"{path[:-1]}: {a!r} vs {b!r}"]
    return []


def check(argv):
    import argparse
    import time
    ap = argparse.ArgumentParser()
    ap.add_argument("--params")
    ap.add_argument("--controller")
    ap.add_argument("--seeds", default="98000,98001,98002,98003,98004,98005")
    a = ap.parse_args(argv)
    params = read_params(a.params) if a.params else {}
    seeds = [int(s) for s in a.seeds.split(",")]
    ctl = os.path.abspath(a.controller) if a.controller else None
    os.environ.setdefault("TT_ENV", "P2")
    from tasks.myo_tt import MyoTTTask
    slow, fast = [], []
    t0 = time.time()
    for s in seeds:
        task = MyoTTTask()
        import myo_bridge as mb
        sim = mb.MyoSim(task, params=params, controller=ctl, seed=s)
        r = sim.run()
        r["seed"] = s
        slow.append(r)
    t1 = time.time()
    for s in seeds:
        fast.append(episode((params, s, None, ctl)))
    t2 = time.time()
    n_bad = 0
    for x, y in zip(slow, fast):
        bad = _cmp(x, y)
        n_bad += bool(bad)
        print(x["seed"], "solved", x.get("solved"), "IDENTICAL" if not bad else f"DIFFERENT {bad[:6]}")
    print(f"standard {t1 - t0:.1f}s, fast {t2 - t1:.1f}s for {len(seeds)} episodes; {n_bad} differ")
    return n_bad


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "check":
        sys.exit(1 if check(sys.argv[2:]) else 0)
    print(__doc__)
