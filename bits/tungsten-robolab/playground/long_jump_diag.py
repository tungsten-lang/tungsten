"""long_jump_diag: what does a landing look like, tick by tick?

Runs a landing program (a long_jump_limits `landing` result, il_* knots) from
saved hand-over states and records the whole body's story after the hand-over:
the COM, its velocity, the angular momentum about the COM, the torso's pitch
and rate, the feet and the first sand contact (which body part, where, how
fast the COM is moving), so a roll-over can be compared with a clean landing.

    .venv/bin/python playground/long_jump_diag.py p95pn2h land.txt --capture p95pn_s0 --idx 16,18,19,17,0 [--table 0.04]

`--idx` picks hand-overs by index or by name; the jitter is the landing
search's own (clock lead 0/4/8 ms and the sand seen 0/1 tick late, by the
index in the whole hand-over list). Output: a table per hand-over and
out/long_jump_run/diag_<handover>_<idx>.npz (the series).
"""

import argparse
import json
import math
import os
import sys

os.environ.setdefault("MUJOCO_GL", "cgl")
import mujoco  # noqa: E402
import numpy as np  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import long_jump_limits as L  # noqa: E402

OUT_RUN = os.path.join(L.ROOT, "out", "long_jump_run")


def pitch_of(body, name):
    up = body.d.xmat[body.m.body(name).id].reshape(3, 3)[:, 2]
    return math.atan2(up[0], up[2])


def sand_parts(body):
    """(body-part name, x, z, |v_z| of the geom's body) for every sand contact."""
    m, d = body.m, body.d
    pit = m.geom("pit").id
    out = []
    for i in range(d.ncon):
        c = d.contact[i]
        for a, g in ((c.geom1, c.geom2), (c.geom2, c.geom1)):
            if a in body.body_geoms and g == pit:
                out.append((mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_BODY, int(m.geom_bodyid[a])), float(c.pos[0]),
                            float(c.pos[2])))
    return out


def run(body, ho, prog, seconds, hz=250):
    m, d = body.m, body.d
    mujoco.mj_setState(m, d, ho["state"], L.SPEC)
    mujoco.mj_forward(m, d)
    prog.start(body)
    t0 = d.time
    ids = body.act_ids
    k = 0
    rows = []
    first_sand = None
    parts_all = {}
    landed = False
    near = None
    head = m.geom("head").id
    while d.time - t0 < seconds:
        t = d.time - t0
        d.ctrl[ids] = np.clip(prog(body, t, k), 0.0, 1.0)
        for _ in range(body.substeps):
            mujoco.mj_step(m, d)
        k += 1
        mujoco.mj_subtreeVel(m, d)
        pel = body.pelvis
        com = d.subtree_com[pel]
        v = d.subtree_linvel[pel]
        Lm = float(d.subtree_angmom[pel][1])
        sp = sand_parts(body)
        if sp and first_sand is None:
            first_sand = (d.time - t0, [p[0] for p in sp], float(com[0]), float(com[2]), float(v[0]), float(v[2]))
        for p in sp:
            parts_all.setdefault(p[0], (d.time - t0, p[1]))
        for i in range(d.ncon):
            c = d.contact[i]
            for a, g in ((c.geom1, c.geom2), (c.geom2, c.geom1)):
                if a in body.body_geoms and g in body.ground:
                    if g == body.runway:
                        rows.append((d.time - t0, -1.0))
                        return {"valid": False, "why": "runway", "t": d.time - t0, "rows": rows, "first_sand": first_sand,
                                "parts": parts_all}
                    landed = True
                    x = float(c.pos[0])
                    near = x if near is None else min(near, x)
        rows.append((d.time - t0, float(com[0]), float(com[2]), float(v[0]), float(v[2]), Lm, body.torso_pitch(),
                     pitch_of(body, "pelvis"), torso_rate(body),
                     float(d.xpos[m.body("l_foot").id][0]), float(d.xpos[m.body("l_foot").id][2]),
                     float(d.xpos[m.body("r_foot").id][0]), float(d.xpos[m.body("r_foot").id][2]),
                     float(d.xpos[body.torso][0]), float(d.xpos[body.torso][2]),
                     float(d.geom_xpos[head][0]), float(d.geom_xpos[head][2]),
                     1.0 if prog.landed else 0.0, prog.shift))
    return {"valid": near is not None, "why": None, "t": d.time - t0, "rows": rows, "first_sand": first_sand,
            "parts": parts_all, "mark": (near - ho["board_x"]) if near is not None else None}


def torso_rate(body):
    return L.torso_rate(body)


COLS = ["t", "com_x", "com_z", "vx", "vz", "Ly", "torso", "pelvis", "torso_rate", "lfoot_x", "lfoot_z", "rfoot_x",
        "rfoot_z", "torso_x", "torso_z", "head_x", "head_z", "landed", "shift"]


_S = {}


def _scan_init(handover, capture, program):
    from search import read_params
    hos = [h for nm in handover.split(",") for h in L.load_handover(nm)]
    c0 = L.load_capture(capture)
    body = L.Body(c0["task"], c0["board_x"], json.loads(c0["env"]))
    kp, kd = L.reflex_gains(body.muscles, json.loads(c0["params"]))
    p = read_params(program)
    nk = int(round(p["il_n"]))
    tab = L.read_il(program, body.muscles, c0["plant"], nk)
    _S.update(hos=hos, body=body, kp=kp, kd=kd, p=p, tab=tab,
              zl=float(json.loads(c0["params"]).get("j_land_z", L.LAND_Z)))


def _scan_one(job):
    i, tg, lz = job
    hos, body, p = _S["hos"], _S["body"], _S["p"]
    tab = dict(_S["tab"])
    tab["tg"] = tg
    tab["zl"] = _S["zl"]
    if lz is not None:
        tab["lz"] = lz
    ho = hos[i]
    lead, delay = 0.004 * (i % 3), (i // 3) % 2
    prog = L.LandingProgram(tab, p["il_h"], p["il_ld"], p.get("j_il_g", 0.3), 1.0, _S["kp"], _S["kd"], lead, delay)
    r = L.run_landing(body, ho, prog, ho.get("t_left", 1.5))
    return L.landing_score(r, ho), r.get("mark"), r.get("max_pitch")


def scan(a):
    """The landing program on every hand-over for a list of ballistic-clock
    references (tg; 0 = the clock from the hand-over)."""
    import multiprocessing as mp
    tgs = [float(x) for x in a.tgs.split(",")]
    hos = [h for nm in a.handover.split(",") for h in L.load_handover(nm)]
    with mp.Pool(a.workers, initializer=_scan_init, initargs=(a.handover, a.capture, a.program)) as pool:
        for tg in tgs:
            res = pool.map(_scan_one, [(i, tg, a.lz) for i in range(len(hos))], chunksize=1)
            sc = np.array([r[0] for r in res])
            roll = [i for i, r in enumerate(res) if r[0] < -2.0]
            print(f"tg {tg:.3f}: mean {sc.mean():.3f} min {sc.min():.2f} roll-overs {len(roll)} {roll} "
                  f"marks {np.round(sc, 2).tolist()}", flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("handover")
    ap.add_argument("program", help="a params file with the il_* landing program")
    ap.add_argument("--capture", required=True)
    ap.add_argument("--idx", default="0", help="comma list of hand-over indices or names")
    ap.add_argument("--table", type=float, default=0.08, help="table row spacing (s)")
    ap.add_argument("--nojitter", action="store_true")
    ap.add_argument("--tag", default="")
    ap.add_argument("--tgs", help="scan: comma list of ballistic-clock references (s); with --idx scan")
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--lz", type=float, default=None)
    ap.add_argument("--tg", type=float, default=0.0, help="the ballistic-time clock reference for the table run")
    a = ap.parse_args()
    if a.tgs:
        return scan(a)
    hos = [h for nm in a.handover.split(",") for h in L.load_handover(nm)]
    c0 = L.load_capture(a.capture)
    body = L.Body(c0["task"], c0["board_x"], json.loads(c0["env"]))
    mus = body.muscles
    kp, kd = L.reflex_gains(mus, json.loads(c0["params"]))
    from search import read_params
    p = read_params(a.program)
    nk = int(round(p["il_n"]))
    tab = L.read_il(a.program, mus, c0["plant"], nk)
    if a.tg:
        tab["tg"] = a.tg
        tab["zl"] = float(json.loads(c0["params"]).get("j_land_z", L.LAND_Z))
    if a.lz is not None:
        tab["lz"] = a.lz
    h, ld, g = p["il_h"], p["il_ld"], p.get("j_il_g", 0.3)
    print(f"landing program {a.program}: h {h} nk {nk} ld {ld} g {g:.3f} lz {tab.get('lz')}")
    names = [x["name"] for x in hos]
    for sel in a.idx.split(","):
        i = int(sel) if sel.lstrip("-").isdigit() else names.index(sel)
        ho = hos[i]
        lead, delay = (0.0, 0) if a.nojitter else (0.004 * (i % 3), (i // 3) % 2)
        prog = L.LandingProgram(tab, h, ld, g, 1.0, kp, kd, lead, delay)
        r = run(body, ho, prog, ho.get("t_left", 1.5))
        rows = np.array([row for row in r["rows"] if len(row) > 3])
        print(f"\n=== hand-over {i} {ho['name']}: vx {ho['vx']:.2f} vz {ho['vz']:.2f} L {ho['L']:.2f} torso {ho['torso_pitch']:.2f} "
              f"D_board {ho['D_board']:.2f} foul {ho['foul']} jitter lead {lead} delay {delay}")
        print("first sand:", None if r["first_sand"] is None else
              "t %.3f parts %s com (%.2f, %.2f) v (%.2f, %.2f)" % (r["first_sand"][0], r["first_sand"][1],
                                                                   r["first_sand"][2] - ho["board_x"], r["first_sand"][3],
                                                                   r["first_sand"][4], r["first_sand"][5]))
        print("parts touching the sand (t, x from line):", {k: (round(v[0], 3), round(v[1] - ho["board_x"], 2)) for k, v in r["parts"].items()})
        print("mark", r.get("mark"), "valid", r["valid"], r["why"])
        if len(rows):
            step = max(1, int(round(a.table / (rows[1, 0] - rows[0, 0]))))
            print("   t   com_x  com_z   vx    vz     Ly   torso  pelv  trate | lfoot x/z    rfoot x/z    | head x/z | landed shift")
            for j in range(0, len(rows), step):
                q = rows[j]
                print("%5.2f %6.2f %5.2f %5.2f %5.2f %6.1f %5.2f %5.2f %5.1f | %5.2f %4.2f  %5.2f %4.2f | %5.2f %4.2f | %d %6.3f" % (
                    q[0], q[1] - ho["board_x"], q[2], q[3], q[4], q[5], q[6], q[7], q[8], q[9] - ho["board_x"], q[10],
                    q[11] - ho["board_x"], q[12], q[15] - ho["board_x"], q[16], q[17], q[18]))
                if q[0] > 1.6:
                    break
        np.savez(os.path.join(OUT_RUN, f"diag_{a.handover}_{i}{a.tag}.npz"), rows=rows, cols=json.dumps(COLS))


if __name__ == "__main__":
    main()
