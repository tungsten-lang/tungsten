"""Replay vs closed loop for the launch stage: where does the ball rise through z 0.62 at the left hand?

    OMP_NUM_THREADS=1 .venv/bin/python scratchpad/btl2/check_m1.py --npz scratchpad/btl2/runs/gs_pass0_g10.npz

Replays the stage's program (gain-scheduled, from the record made with A4 = rec_s_m1) and compares the ball's rising crossing of z 0.62
after the first bounce with the closed-loop recording made with the stage in the loop (rec_s0v2, params pgP0.txt, btl2-b11).
"""
import argparse
import pickle
import sys

import numpy as np

sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")
sys.path.insert(0, "scratchpad/btl2")
import oracle_gs as G  # noqa: E402
import oracle_lib as O  # noqa: E402
import oracle_multi as M  # noqa: E402
import oracle_search as S  # noqa: E402


def crossing(pos, vel, i0, h=0.62):
    """First rising crossing of z h after tick i0 (linear interpolation): (x, y, i)."""
    for i in range(i0 + 1, len(pos)):
        if pos[i - 1, 2] < h <= pos[i, 2] and vel[i, 2] > 0:
            f = (h - pos[i - 1, 2]) / (pos[i, 2] - pos[i - 1, 2])
            p = pos[i - 1] + f * (pos[i] - pos[i - 1])
            return p[0], p[1], i
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--npz", required=True)
    ap.add_argument("--seeds", default="801..880")
    ap.add_argument("--release", action="store_true")
    a = ap.parse_args()
    lo, hi = a.seeds.split("..")
    seeds = list(range(int(lo), int(hi) + 1))
    c1 = pickle.load(open("scratchpad/btl2/runs/rec_s_m1.pkl", "rb"))
    c2 = pickle.load(open("scratchpad/btl2/runs/rec_s0v2.pkl", "rb"))
    z = np.load(a.npz)
    nom, sc = z["nom"], z["sc"]
    n = 160
    nprog = int(round(0.40 / 0.005))
    rows = []
    for sd in seeds:
        k1 = (sd, "params/dribble_btl_a4.txt", "bin/challengers/btl2-b8", 1.35, 1.75, 2.5)
        k2 = (sd, "scratchpad/btl2/params/pgP0.txt", "bin/challengers/btl2-b11", 1.70, 2.40, 3.0)
        if k1 not in c1 or k2 not in c2:
            continue
        r1, r2 = c1[k1], c2[k2]
        rp = O.Replay(r1)
        ks = M.trigger_tick(r1, rp, 1, lead=32 * 0.005 + 0.005)
        if ks is None or ks not in r1["snaps"]:
            continue
        pc = rp.pred_cross(ks)
        if pc is None:
            continue
        u = np.clip((np.array(pc[:2]) - nom) / sc, -2.5, 2.5)
        idx, kt = list(z["idx"]), z["kt"]
        cfg = {"idx": idx, "kt": kt, "nprog": nprog, "gmax": 1.0}
        base = r1["acts"][ks:ks + n + 1]
        ov = G.program_gs(z["x"], cfg, base, n, u)
        out = rp.run(ov, ticks=n, start=ks)
        # first bounce: floor contact after the program starts
        fl = np.nonzero(out["cf"][:, 2] > 0.2)[0]
        if len(fl) == 0:
            continue
        cr = crossing(out["pos"], out["vel"], fl[0])
        # closed loop: the ball path of the pgP0 record, from the first floor bounce after t 1.35 (ball z minimum)
        bp = r2["ball"]
        bv = r2["ballv"]
        # the record starts at t 0: the first rising crossing of z 0.62 on the left hand's side (x < 0.1) after t = 1.4 s
        t0 = int(1.40 / 0.005)
        cr2 = None
        i = t0
        while i < len(bp) - 1:
            c = crossing(bp, bv, i)
            if c is None:
                break
            if c[0] < 0.1:
                cr2 = c
                break
            i = c[2]
        if cr is None or cr2 is None:
            continue
        rows.append((sd, u[0], u[1], cr[0], cr[1], cr2[0], cr2[1]))
        if a.release:
            def free_release(pos_, vel_, ib):
                # the last tick before the bounce whose acceleration is not free flight: the palm's last push
                for i in range(ib - 1, 1, -1):
                    if pos_[i, 2] < 0.25:
                        continue
                    acc = (vel_[i] - vel_[i - 1]) / 0.005
                    if np.linalg.norm(acc - np.array([0.0, 0.0, -9.81])) > 3.0:
                        return i
                return None
            i1 = free_release(out["pos"], out["vel"], fl[0])
            b2 = None
            for i in range(cr2[2], 0, -1):
                if bv[i - 1, 2] < 0 <= bv[i, 2] and bp[i, 2] < 0.2:
                    b2 = i
                    break
            i2 = free_release(bp, bv, b2)
            v1, p1 = out["vel"][i1], out["pos"][i1]
            v2, p2 = bv[i2], bp[i2]
            print(f"   {sd} u ({u[0]:+.1f},{u[1]:+.1f}) replay rel v ({v1[0]:+.2f},{v1[1]:+.2f},{v1[2]:+.2f}) p ({p1[0]:+.2f},{p1[1]:+.2f},{p1[2]:.2f}) tick {i1} | "
                  f"closed rel v ({v2[0]:+.2f},{v2[1]:+.2f},{v2[2]:+.2f}) p ({p2[0]:+.2f},{p2[1]:+.2f},{p2[2]:.2f}) | bounce closed ({bp[b2][0]:+.2f},{bp[b2][1]:+.2f}) replay ({out['pos'][fl[0]][0]:+.2f},{out['pos'][fl[0]][1]:+.2f})")
    R = np.array(rows)
    print("seed  u(x,y)        replay(x,y)      closed(x,y)     diff")
    for r in R:
        print(f"{int(r[0])} ({r[1]:+.1f},{r[2]:+.1f}) ({r[3]:+.3f},{r[4]:+.3f}) ({r[5]:+.3f},{r[6]:+.3f}) ({r[5] - r[3]:+.3f},{r[6] - r[4]:+.3f})")
    d = R[:, 5:7] - R[:, 3:5]
    print("n", len(R), "replay mean", np.round(R[:, 3:5].mean(0), 3), "std", np.round(R[:, 3:5].std(0), 3),
          "| closed mean", np.round(R[:, 5:7].mean(0), 3), "std", np.round(R[:, 5:7].std(0), 3),
          "| diff mean", np.round(d.mean(0), 3), "std", np.round(d.std(0), 3))


if __name__ == "__main__":
    main()
