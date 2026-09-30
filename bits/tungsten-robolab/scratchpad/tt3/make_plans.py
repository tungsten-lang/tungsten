"""Plans of the kinematic-paddle oracle O4 (agent T3): per serve, a pure function of the pass-1 record (out/tt3/logs_o0/<seed>.npz + o0_<set>.jsonl).

    .venv-myo/bin/python scratchpad/tt3/make_plans.py VARIANT [--sets A,B] [--out scratchpad/tt3/results/plan_VARIANT.json]

Every plan = {t_hit, P (pad centre at t_hit), n_out (unit normal from the pad toward the incoming ball), v (pad velocity), t_on, t_off}. The ball path is pass 1's own (it is untouched by the
paddle until contact): p_hit, v_ball = the ball's state at the last control tick before pass 1's contact (closest approach for a miss); P = p_hit - 0.04 n_out, so that the ball's centre reaches the
pad face (half thickness 0.02 + ball radius 0.02) exactly at the pad's centre line: the in-plane offset at contact is zero by construction (no place error).
Variants:
  a    the champion's own plan taken at face value: n = its last aim-law normal (the aim row at or before pass 1's contact), still pad (v = 0)
  a2   the champion's plan with its realised MEAN execution kept and the scatter removed: n = aim normal turned by the side-mean of (pad normal at contact - aim normal) in pitch and yaw,
       v = the side-mean of the pad's world velocity at contact (means over set A's hits of pass 1)
  b    best aim for a still pad: (pitch, yaw) maximising the landing margin under the impact model (tt_impact.margin; E, MU fitted per --fit if given), v = 0
  bm   best aim with a retreat velocity: (pitch, yaw, d along +x, d in [-0.25, 1.5]) maximising the margin, the pad moving at d * alpha
"""
import argparse, json, os, sys
import numpy as np
HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(HERE, "playground"))
import tt_impact as ti

SETS = {"A": (98000, 98100), "B": (830000, 830100)}


def orient(n):
    n = np.asarray(n, float)
    n = n / np.linalg.norm(n)
    return n if n[0] >= 0 else -n


def record(seed, row):
    z = np.load(f"out/tt3/logs_o0/{seed}.npz")
    L, aim, k = z["L"], z["aim"], int(z["contact"])
    hit = k >= 0
    if not hit:
        k = int(np.argmin(np.linalg.norm(L[:, 1:4] - L[:, 7:10], axis=1)))
    kk = max(k - 1, 0)
    d = dict(hit=hit, k=k, kk=kk, t_hit=float(L[kk, 0]), p=L[kk, 1:4].copy(), vb=L[kk, 4:7].copy(),
             pad_n=orient(L[kk, 13:16]), pad_c=L[kk, 7:10].copy())
    if hit:
        vw = np.array(row["paddle_vel"]) if row.get("paddle_vel") else (L[kk, 7:10] - L[max(kk - 1, 0), 7:10]) / (L[kk, 0] - L[max(kk - 1, 0), 0])
        d["vp"] = vw
    if aim.ndim == 2 and len(aim):
        sel = aim[aim[:, 0] <= L[k, 0] + 1e-9]
        d["aim_n"] = orient(sel[-1][1:4]) if len(sel) else None
    else:
        d["aim_n"] = None
    return d


def angles(n):
    p, y = ti.angles_from_normal(np.asarray(n)[None, :])
    return float(np.degrees(p[0])), float(np.degrees(y[0]))


def margin_grid(p0, vin, vp_list, E, ALPHA, MU, pitches, yaws):
    """(len(vp_list), P, Y) landing margins of the return for pad normals on a grid and pad velocities"""
    Pn = np.radians(pitches)[:, None]
    Yn = np.radians(yaws)[None, :]
    n = np.stack([np.cos(Pn) * np.cos(Yn), np.cos(Pn) * np.sin(Yn), np.sin(Pn) + 0 * Yn], axis=-1)
    out = np.full((len(vp_list),) + n.shape[:2], -1.0)
    for i, vp in enumerate(vp_list):
        v = ti.impact(vin, ALPHA * np.asarray(vp), n, E, MU)
        x0, y0, z0 = p0
        vx, vy, vz = v[..., 0], v[..., 1], v[..., 2]
        with np.errstate(divide="ignore", invalid="ignore"):
            t1 = -x0 / vx
            zn = z0 + vz * t1 - 0.5 * ti.G * t1 * t1
            disc = vz * vz + 2 * ti.G * (z0 - ti.Z_C)
            t2 = (vz + np.sqrt(np.maximum(disc, 0.0))) / ti.G
            xl = x0 + vx * t2
            yl = y0 + vy * t2
            m = np.minimum.reduce([zn - (ti.NET_TOP + ti.R_BALL), xl - ti.X_FAR, -xl, ti.Y_HI - yl, yl - ti.Y_LO])
        ok = (vx < -0.3) & (t1 > 0) & (disc > 0)
        out[i] = np.where(ok, m, -1.0)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("variant")
    ap.add_argument("--sets", default="A,B")
    ap.add_argument("--out")
    ap.add_argument("--E", type=float, default=0.95)
    ap.add_argument("--MU", type=float, default=0.012)
    ap.add_argument("--ALPHA", type=float, default=0.9)
    ap.add_argument("--t_on", type=float, default=0.15)
    ap.add_argument("--t_off", type=float, default=0.15)
    ap.add_argument("--dmax", type=float, default=1.5)
    ap.add_argument("--m0", type=float, default=0.25, help="bn: minimum landing margin (m) of the plan nearest to the champion's realised normal")
    a = ap.parse_args()
    rows = {}
    recs = {}
    for s in a.sets.split(","):
        for l in open(f"out/tt3/o0_{s}.jsonl"):
            r = json.loads(l)
            rows[r["seed"]] = r
    for sd, r in rows.items():
        recs[sd] = record(sd, r)
    # calibration means from set A's pass-1 hits, per side
    mean_dp = {1: (0.0, 0.0), 2: (0.0, 0.0)}
    mean_v = {1: np.zeros(3), 2: np.zeros(3)}
    for side in (1, 2):
        dps, dys, vs = [], [], []
        for sd in range(*SETS["A"]):
            r, d = rows.get(sd), recs.get(sd)
            if r is None or not d["hit"] or d["aim_n"] is None or r.get("side") != side:
                continue
            pp, py = angles(d["pad_n"]); ap_, ay = angles(d["aim_n"])
            dps.append(pp - ap_); dys.append(py - ay); vs.append(d["vp"])
        if dps:
            mean_dp[side] = (float(np.mean(dps)), float(np.mean(dys))); mean_v[side] = np.mean(vs, axis=0)
    print("side-mean realised offset (pad - aim, pitch/yaw deg):", mean_dp, "side-mean pad velocity:", {k: np.round(v, 3).tolist() for k, v in mean_v.items()})
    plans = {}
    stats = {"n": 0, "no_aim": 0, "feasible": 0, "margin_med": []}
    pitches = np.arange(-40.0, 60.1, 1.0)
    yaws = np.arange(-35.0, 35.1, 1.0)
    DEL = np.arange(-0.25, a.dmax + 1e-9, 0.125)
    for sd, d in recs.items():
        side = rows[sd].get("side")
        n_pos = None
        v = np.zeros(3)
        if a.variant in ("a", "a2"):
            n_pos = d["aim_n"] if d["aim_n"] is not None else d["pad_n"]
            if d["aim_n"] is None:
                stats["no_aim"] += 1
            if a.variant == "a2":
                p, y = angles(n_pos)
                dp, dy = mean_dp.get(side, (0.0, 0.0))
                n_pos = ti.normal_from_angles(np.radians(p + dp), np.radians(y + dy))
                v = mean_v.get(side, np.zeros(3)).copy()
        elif a.variant == "bn":
            # the feasible still-pad plan (margin >= m0) NEAREST to the champion's realised pad normal at contact: the gentlest plan for an arm that must realise it
            M = margin_grid(d["p"], d["vb"], [np.zeros(3)], a.E, a.ALPHA, a.MU, pitches, yaws)[0]
            P0, Y0 = angles(d["pad_n"])
            PP, YY = np.meshgrid(pitches, yaws, indexing="ij")
            ang = np.hypot(PP - P0, (YY - Y0))
            cand = np.where(M >= a.m0, ang, 1e9)
            if cand.min() > 1e8:
                cand = np.where(M > 0, ang, 1e9)
            j, k = np.unravel_index(int(np.argmin(cand)), cand.shape)
            n_pos = ti.normal_from_angles(np.radians(pitches[j]), np.radians(yaws[k]))
            stats["feasible"] += int(M[j, k] > 0)
            stats["margin_med"].append(float(M[j, k]))
            stats.setdefault("dist", []).append(float(ang[j, k]))
        else:
            vps = [np.zeros(3)] if a.variant == "b" else [np.array([dd, 0.0, 0.0]) for dd in DEL]
            M = margin_grid(d["p"], d["vb"], vps, a.E, a.ALPHA, a.MU, pitches, yaws)
            i, j, k = np.unravel_index(int(np.argmax(M)), M.shape)
            n_pos = ti.normal_from_angles(np.radians(pitches[j]), np.radians(yaws[k]))
            v = vps[i].copy()
            stats["feasible"] += int(M[i, j, k] > 0)
            stats["margin_med"].append(float(M[i, j, k]))
        n_out = -orient(n_pos)
        stats["n"] += 1
        plans[str(sd)] = {"t_hit": d["t_hit"], "P": (d["p"] - 0.04 * n_out).tolist(), "n_out": n_out.tolist(), "v": v.tolist(),
                          "t_on": d["t_hit"] - a.t_on, "t_off": d["t_hit"] + a.t_off, "hit1": bool(d["hit"])}
    out = a.out or f"scratchpad/tt3/results/plan_{a.variant}.json"
    json.dump(plans, open(out, "w"))
    print(f"variant {a.variant}: {stats['n']} plans -> {out}; no aim row {stats['no_aim']}; model-feasible {stats['feasible']}; median margin {np.median(stats['margin_med']) if stats['margin_med'] else None}"
          + (f"; angle from the champion's normal median {np.median(stats['dist']):.1f} deg, 90th pct {np.percentile(stats['dist'], 90):.1f}" if stats.get('dist') else ""))


if __name__ == "__main__":
    main()
