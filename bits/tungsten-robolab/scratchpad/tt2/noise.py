"""Noise decomposition and go/no-go measures of a table-tennis run (agent T2).

    .venv-myo/bin/python scratchpad/tt2/noise.py TAG out/tt2/TAG.jsonl [out/tt2/logs_TAG] [--params params/myo_tt_p2_r10_c3.txt] [--json out/tt2/noise_TAG.json]

The measures are the ones defined in playground/profiles/myo_beyond_arm.json (fixed before any rung ran):
  pitch sigma      sd over hits of pitch(pad normal at contact) - pitch(aim law's last normal at or before contact), deg (scratchpad/tt/an8.py)
  pad-vel sigma    mean over x, y, z of the sd over hits of the pad centre's world velocity at contact (metric paddle_vel), m/s; along-normal beside it
  place error      from the TT_SAVE_LOG logs: in-plane offset of the ball centre from the pad centre at the first row with paddle contact,
                   sqrt(mean(d^2)/2) in cm (per-axis sigma of an isotropic Gaussian miss, bias included), median d beside it; row k-1 for information
plus the asked-versus-reached table of the arm's ready posture at contact (commanded parameters against the logged joint angles), by side.
"""

import argparse
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(HERE, "playground"))
import tt_impact as ti  # noqa: E402

JOINTS = ["elv_angle", "shoulder_elv", "shoulder_rot", "elbow_flexion", "pro_sup", "deviation", "flexion"]
FH = ["elv", "sh_elv", "sh_rot", "elbow", "pro_sup", "dev", "wflex"]
BH = ["bh_elv", "bh_sh_elv", "bh_sh_rot", "bh_elbow", "bh_pro_sup", "bh_dev", "bh_wflex"]


def orient(n):
    n = np.asarray(n, float)
    n = n / np.linalg.norm(n, axis=-1, keepdims=True)
    return n * np.where(n[..., :1] < 0, -1.0, 1.0)


def load_rows(path):
    return [json.loads(l) for l in open(path) if l.strip()]


def summarize_classes(rows):
    from tasks.myo_tt import failure_class
    cls = {}
    for r in rows:
        cls[failure_class(r)] = cls.get(failure_class(r), 0) + 1
    return cls


def pitch_yaw(rows):
    H = [r for r in rows if r.get("hit") and r.get("aim_normal") and r.get("pad_normal")]
    if not H:
        return {}
    na, nt = orient([r["aim_normal"] for r in H]), orient([r["pad_normal"] for r in H])
    side = np.array([r["side"] for r in H])
    pa, ya = ti.angles_from_normal(na)
    pt, yt = ti.angles_from_normal(nt)
    dp, dy = np.degrees(pt - pa), np.degrees(yt - ya)
    out = {"n": len(H), "pitch_sigma": float(dp.std()), "pitch_mean": float(dp.mean()), "yaw_sigma": float(dy.std()), "yaw_mean": float(dy.mean())}
    for s, nm in ((1, "fh"), (2, "bh")):
        m = side == s
        if m.sum() > 2:
            out[nm] = {"n": int(m.sum()), "pitch_sigma": float(dp[m].std()), "pitch_mean": float(dp[m].mean()),
                       "yaw_sigma": float(dy[m].std()), "yaw_mean": float(dy[m].mean())}
    return out


def pad_velocity(rows):
    H = [r for r in rows if r.get("hit") and r.get("paddle_vel") and r.get("pad_normal")]
    if not H:
        return {}
    v = np.array([r["paddle_vel"] for r in H])
    n = orient([r["pad_normal"] for r in H])
    vn = np.sum(v * n, axis=1)
    side = np.array([r["side"] for r in H])
    out = {"n": len(H), "comp_sd": [float(x) for x in v.std(axis=0)], "sigma": float(v.std(axis=0).mean()),
           "along_normal_mean": float(vn.mean()), "along_normal_sd": float(vn.std()), "speed_mean": float(np.linalg.norm(v, axis=1).mean())}
    for s, nm in ((1, "fh"), (2, "bh")):
        m = side == s
        if m.sum() > 2:
            out[nm] = {"n": int(m.sum()), "sigma": float(v[m].std(axis=0).mean()), "along_normal_mean": float(vn[m].mean()), "along_normal_sd": float(vn[m].std())}
    return out


def place_error(rows, logdir):
    """in-plane ball-pad offset at the first contact row (and the row before) from the episode logs"""
    d0, d1, side, sol = [], [], [], []
    z0 = []
    for r in rows:
        if not r.get("hit"):
            continue
        f = os.path.join(logdir, f"{r['seed']}.npz")
        if not os.path.exists(f):
            continue
        z = np.load(f)
        L, k = z["L"], int(z["contact"])
        if k < 1:
            continue
        for row, acc in ((k, d0), (k - 1, d1)):
            ball, pad, nrm = L[row, 1:4], L[row, 7:10], L[row, 13:16]
            nrm = nrm / np.linalg.norm(nrm)
            off = ball - pad
            inpl = off - (off @ nrm) * nrm
            acc.append(np.linalg.norm(inpl))
        z0.append((L[k, 1:4] - L[k, 7:10])[2])
        side.append(r["side"])
        sol.append(r.get("solved", 0) > 0)
    if not d0:
        return {}
    d0, d1, side, sol = np.array(d0), np.array(d1), np.array(side), np.array(sol)
    out = {"n": len(d0), "sigma_cm": float(100 * np.sqrt(np.mean(d0 ** 2) / 2)), "median_cm": float(100 * np.median(d0)),
           "sigma_cm_row_before": float(100 * np.sqrt(np.mean(d1 ** 2) / 2)), "median_cm_row_before": float(100 * np.median(d1)),
           "frac_ge_8p5cm": float(np.mean(d0 >= 0.085)), "z_offset_cm_mean_sd": [float(100 * np.mean(z0)), float(100 * np.std(z0))]}
    for s, nm in ((1, "fh"), (2, "bh")):
        m = side == s
        if m.sum() > 2:
            out[nm] = {"n": int(m.sum()), "sigma_cm": float(100 * np.sqrt(np.mean(d0[m] ** 2) / 2)), "median_cm": float(100 * np.median(d0[m]))}
    return out


def joint_ranges():
    try:
        import warnings
        warnings.filterwarnings("ignore")
        from myosuite.utils import gym
        import mujoco
        m = gym.make("myoChallengeTableTennisP2-v0").unwrapped.mj_model
        return {n: tuple(float(x) for x in m.jnt_range[m.joint(n).id]) for n in JOINTS}
    except Exception as e:  # pragma: no cover
        print("joint ranges unavailable:", e)
        return {}


def posture_table(rows, logdir, params):
    """commanded ready posture (params) against the logged joint angles at the first contact row, by side"""
    rng = joint_ranges()
    out = {}
    for s, nm, names in ((1, "fh", FH), (2, "bh", BH)):
        Q0, Qc = [], []
        for r in rows:
            if not r.get("hit") or r.get("side") != s:
                continue
            f = os.path.join(logdir, f"{r['seed']}.npz")
            if not os.path.exists(f):
                continue
            z = np.load(f)
            X, k = z["X"], int(z["contact"])
            if len(X) < 2 or k < 1:
                continue
            Q0.append(X[0, :7])
            Qc.append(X[k, :7])
        if not Qc:
            continue
        Q0, Qc = np.array(Q0), np.array(Qc)
        rows_j = []
        for j, (jn, pn) in enumerate(zip(JOINTS, names)):
            cmd = params.get(pn)
            lo, hi = rng.get(jn, (None, None))
            atlim = None if lo is None else float(np.mean((Qc[:, j] - lo < 0.02) | (hi - Qc[:, j] < 0.02)))
            rows_j.append({"joint": jn, "param": pn, "asked": cmd, "start": float(Q0[:, j].mean()), "reached_mean": float(Qc[:, j].mean()),
                           "reached_sd": float(Qc[:, j].std()),
                           "ratio_raw": None if not cmd else float(Qc[:, j].mean() / cmd),
                           "ratio_from_start": None if cmd is None or abs(cmd - Q0[:, j].mean()) < 1e-6 else float((Qc[:, j].mean() - Q0[:, j].mean()) / (cmd - Q0[:, j].mean())),
                           "frac_at_limit": atlim})
        out[nm] = {"n": len(Qc), "joints": rows_j}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tag")
    ap.add_argument("jsonl")
    ap.add_argument("logdir", nargs="?")
    ap.add_argument("--params")
    ap.add_argument("--json")
    a = ap.parse_args()
    rows = [r for r in load_rows(a.jsonl) if "error" not in r]
    errs = len(load_rows(a.jsonl)) - len(rows)
    params = {}
    if a.params:
        for line in open(a.params):
            t = line.split()
            if len(t) >= 2 and not line.startswith("#"):
                params[t[0]] = float(t[1])
    n = len(rows)
    sol = sum(1 for r in rows if r.get("solved", 0) > 0)
    hit = sum(1 for r in rows if r.get("hit", 0) > 0)
    out = {"tag": a.tag, "n": n, "errors": errs, "solved": sol, "hit": hit}
    for s, nm in ((1, "forehand"), (2, "backhand")):
        rs = [r for r in rows if r.get("side") == s]
        out[nm] = {"n": len(rs), "solved": sum(1 for r in rs if r.get("solved", 0) > 0), "hit": sum(1 for r in rs if r.get("hit", 0) > 0)}
    out["classes"] = summarize_classes(rows)
    out["pitch_yaw"] = pitch_yaw(rows)
    out["pad_velocity"] = pad_velocity(rows)
    if a.logdir and os.path.isdir(a.logdir):
        out["place"] = place_error(rows, a.logdir)
        out["posture"] = posture_table(rows, a.logdir, params)
    print(f"== {a.tag}: {n} serves ({errs} errors): solved {sol} ({100 * sol / max(n, 1):.1f}%), hit {hit} ({100 * hit / max(n, 1):.1f}%); "
          f"forehand {out['forehand']['solved']}/{out['forehand']['n']}, backhand {out['backhand']['solved']}/{out['backhand']['n']}")
    print("   classes:", json.dumps(out["classes"]))
    py, pv, pl = out["pitch_yaw"], out["pad_velocity"], out.get("place", {})
    if py:
        print(f"   pitch sigma {py['pitch_sigma']:.2f} deg (mean {py['pitch_mean']:+.1f}; fh {py.get('fh', {}).get('pitch_sigma', float('nan')):.2f}, bh {py.get('bh', {}).get('pitch_sigma', float('nan')):.2f}), "
              f"yaw sigma {py['yaw_sigma']:.2f} (fh {py.get('fh', {}).get('yaw_sigma', float('nan')):.2f}, bh {py.get('bh', {}).get('yaw_sigma', float('nan')):.2f}) over {py['n']} hits")
    if pv:
        print(f"   pad-velocity sigma {pv['sigma']:.3f} m/s (x,y,z sd {', '.join('%.2f' % x for x in pv['comp_sd'])}); along the pad normal {pv['along_normal_mean']:+.2f} +- {pv['along_normal_sd']:.2f}"
              f" (fh sd {pv.get('fh', {}).get('along_normal_sd', float('nan')):.2f}, bh sd {pv.get('bh', {}).get('along_normal_sd', float('nan')):.2f}); mean pad speed {pv['speed_mean']:.2f}")
    if pl:
        print(f"   place error {pl['sigma_cm']:.2f} cm per axis (median distance {pl['median_cm']:.1f} cm; row before contact: {pl['sigma_cm_row_before']:.2f} / {pl['median_cm_row_before']:.1f}); "
              f"{100 * pl['frac_ge_8p5cm']:.0f}% of hits beyond 8.5 cm; z offset {pl['z_offset_cm_mean_sd'][0]:+.1f} +- {pl['z_offset_cm_mean_sd'][1]:.1f} cm; "
              f"fh {pl.get('fh', {}).get('sigma_cm', float('nan')):.2f}, bh {pl.get('bh', {}).get('sigma_cm', float('nan')):.2f}")
    for nm, pt in out.get("posture", {}).items():
        print(f"   ready posture, {nm} (n {pt['n']}): joint, asked, start, reached mean +- sd, reached/asked, excursion ratio, at-limit")
        for j in pt["joints"]:
            rr = j["ratio_raw"]
            rs = j["ratio_from_start"]
            al = j["frac_at_limit"]
            print(f"      {j['joint']:<14} {j['asked']:+.3f}  {j['start']:+.3f}  {j['reached_mean']:+.3f} +- {j['reached_sd']:.3f}   "
                  f"{'-' if rr is None else format(rr, '.2f')}  {'-' if rs is None else format(rs, '.2f')}  {'-' if al is None else format(100 * al, '.0f') + '%'}")
    if a.json:
        json.dump(out, open(a.json, "w"), indent=1)


if __name__ == "__main__":
    main()
