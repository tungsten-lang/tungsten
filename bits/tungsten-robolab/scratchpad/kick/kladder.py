"""The noise ladder: a controller on the P1 start with joint noise x scale (of the P2 draw's +-0.02 rad) and root
offsets, per-run diagnostics, optional checkpoint dumps.

  kladder.py --controller C --params P --noise 0,0.05,0.1 --seeds 5000:5008 [--dx 0,-0.1] [--dy 0,0.1]
             [--workers 2] [--dump DIR] [--set k=v,...] [--seconds 5] [--tag NAME]

A run's row: goal, kick_ok (the ball leaves fast and would cross the line inside the posts, keeper ignored),
ball speed, touch time, the toe-to-ball vector at the swing start and at the snap, pelvis yaw at the swing start.
"""
import argparse
import gzip
import json
import multiprocessing as mp
import os
import pickle
import sys
import time

import numpy as np

sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick")
import kcommon as K


def first(tr, lab):
    for j, r in enumerate(tr):
        if r["lab"] == lab:
            return j
    return None


def summarize(sim, m):
    tr = sim.task.tr
    out = {"goal": m.get("goal"), "ball_speed": m.get("ball_speed"), "t_touch": m.get("t_touch"),
           "touch_body": m.get("touch_body"), "cross_y": m.get("cross_y", m.get("pred_y")),
           "cross_z": m.get("cross_z"), "launch": m.get("launch_deg"), "elev": m.get("launch_elev_deg"),
           "fallen": m.get("fallen"), "t_fall": m.get("t_fall"), "strike_zone": m.get("strike_zone"),
           "strike_point": m.get("strike_point_all"), "keeper": m.get("keeper_policy"), "keeper_y": m.get("keeper_y"),
           "r_toe_ball_min": m.get("r_toe_ball_min"), "steps": m.get("steps"), "time": m.get("time")}
    cy = out["cross_y"]
    out["kick_ok"] = bool(out["ball_speed"] is not None and out["ball_speed"] > 8.5 and cy is not None
                          and abs(cy) < 3.0 and (out["cross_z"] is None or out["cross_z"] < 2.0)
                          and (not out["fallen"] or (m.get("t_cross") is not None)))
    ev = {}
    for e in m.get("events", []):
        ev.setdefault(e[1].split(":")[-1], e[0])
    out["events"] = ev
    js = first(tr, "swing")
    jn = first(tr, "snap")
    for name, j in (("sw", js), ("sn", jn)):
        if j is not None:
            r = tr[j]
            d = r["bof_r"] - r["ball"]
            out[name + "_t"] = r["t"]
            out[name + "_toe"] = [round(float(v), 3) for v in d]
            out[name + "_pelvis"] = [round(float(v), 3) for v in (r["pelvis"] - r["ball"])]
            out[name + "_yaw"] = round(r["yaw"], 3)
            out[name + "_com"] = [round(float(v), 3) for v in (r["com"] - r["ball"])]
    jt = K.touch_index(sim)
    if jt is not None:
        r = tr[jt]
        d = r["bof_r"] - r["ball"]
        out["ct_toe"] = [round(float(v), 3) for v in d]
        out["ct_vtoe"] = [round(float(v), 2) for v in r["vtoe_r"]]
    return out


def job(a):
    (params, ctl, seed, noise, dx, dy, secs, dump, tag, groups) = a
    K.ensure()
    t0 = time.time()
    sim = K.make_sim(params, ctl, seed, dict(noise=noise, dx=dx, dy=dy, groups=groups))
    m = sim.run(secs)
    row = summarize(sim, m)
    row.update({"seed": seed, "noise": noise, "dx": dx, "dy": dy, "groups": groups, "wall": round(time.time() - t0, 1)})
    if dump:
        os.makedirs(dump, exist_ok=True)
        tr = sim.task.tr
        jt = K.touch_index(sim)
        jend = (jt + 12) if jt is not None else len(sim.S_hist)
        pack = {"seed": seed, "reset_kw": dict(noise=noise, dx=dx, dy=dy), "params": params, "controller": ctl,
                "S": sim.S_hist[:jend], "A": sim.A_hist[:jend], "state": sim.state_hist[:jend],
                "geometry": sim.geometry_pack(), "row": row, "trace": tr[:jend]}
        name = f"{tag}_n{noise:g}_dx{dx:+g}_dy{dy:+g}_s{seed}.pkl.gz"
        with gzip.open(os.path.join(dump, name), "wb", compresslevel=3) as f:
            pickle.dump(pack, f)
        row["file"] = name
    return row


def fmt(v):
    return "-" if v is None else (f"{v:.2f}" if isinstance(v, float) else str(v))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--controller", default=K.P1_CTL)
    ap.add_argument("--params", default=K.P1_PARAMS)
    ap.add_argument("--noise", default="0")
    ap.add_argument("--dx", default="0")
    ap.add_argument("--dy", default="0")
    ap.add_argument("--seeds", default="5000:5004")
    ap.add_argument("--seconds", type=float, default=5.0)
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--set", default="")
    ap.add_argument("--dump", default="")
    ap.add_argument("--tag", default="p1")
    ap.add_argument("--json", default="")
    ap.add_argument("--groups", default="", help="';'-separated groups of ','-separated joint-name substrings that get the noise: e.g. '_r;_l;L1_,L2_,L3_,L4_,Abs,axial,flex_ext,lat_'")
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()
    lo, hi = a.seeds.split(":")
    seeds = list(range(int(lo), int(hi)))
    p = K.read_params(a.params)
    for kv in a.set.split(","):
        if "=" in kv:
            k, v = kv.split("=")
            p[k.strip()] = float(v)
    ctl = os.path.abspath(a.controller)
    glist = [None] if not a.groups else [g.split(",") for g in a.groups.split(";")]
    jobs = [(p, ctl, s, float(nz), float(dx), float(dy), a.seconds, a.dump, a.tag, gr)
            for gr in glist for dx in a.dx.split(",") for dy in a.dy.split(",") for nz in a.noise.split(",") for s in seeds]
    t0 = time.time()
    with mp.Pool(a.workers) as pool:
        rows = pool.map(job, jobs, chunksize=1)
    groups = {}
    for r in rows:
        groups.setdefault((r["noise"], r["dx"], r["dy"], str(r.get("groups"))), []).append(r)
    for key, rs in groups.items():
        g = sum(1 for r in rs if r["goal"])
        ok = sum(1 for r in rs if r["kick_ok"])
        sp = np.mean([r["ball_speed"] or 0 for r in rs])
        print(f"noise {key[0]:.3f} dx {key[1]:+.2f} dy {key[2]:+.2f} {key[3][:60]}: goals {g}/{len(rs)} kick_ok {ok}/{len(rs)} ball {sp:5.2f} m/s "
              f"touched {sum(1 for r in rs if r['t_touch'] is not None)} fallen {sum(1 for r in rs if r['fallen'])}", flush=True)
        if a.verbose:
            for r in rs:
                print(f"   seed {r['seed']} ok {int(r['kick_ok'])} goal {r['goal']:.0f} ball {fmt(r['ball_speed'])} touch {fmt(r['t_touch'])} "
                      f"cross_y {fmt(r['cross_y'])} launch {fmt(r['launch'])} keeper {r['keeper']} | swing t {fmt(r.get('sw_t'))} toe {r.get('sw_toe')} yaw {fmt(r.get('sw_yaw'))} "
                      f"| snap toe {r.get('sn_toe')} | contact toe {r.get('ct_toe')} | fallen {r['fallen']} min toe-ball {fmt(r['r_toe_ball_min'])}")
    print(f"total {time.time() - t0:.0f}s")
    if a.json:
        json.dump(rows, open(a.json, "w"), indent=1)


if __name__ == "__main__":
    main()
