"""Compose a round-10 candidate parameter file from the champion's, a backhand RSM run and a forehand RSM run (or the champion's forehand).

    .venv-myo/bin/python playground/tt_r10_compose.py --bh out/tt_r10/rsm_bh3:21 [--fh out/tt_r10/rsm_fh3:7] --write params/x.txt [--set k=v,...]

The backhand run's values go to the backhand's own names (`kk2_amp/k/v0`, `ns_k2`, `k_vpm2`, `bh_box_dx` = its box shift from the champion's box);
the forehand run's kick, aim and servo values go to the shared names the forehand uses. `bk 1` (the bounce-tick guard) is on for both.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import tt_fast  # noqa: E402
from tt_rsm_run_params import run_params  # noqa: E402

CHAMP = os.path.join(HERE, "..", "params", "myo_tt_p2_r5_bhprac.txt")
BH_OWN = ("bh_t_servo", "bh_k_z", "bh_k_n", "bh_p_z", "bh_p_n", "bh_dnz", "bh_gain", "bh_dur", "kk_m2", "lc16", "bh_wflex", "bh_dev", "bh_elbow",
          "bh_elv", "bh_sh_elv", "bh_sh_rot", "bh_pro_sup", "bh_trunk_ar", "bh_grip", "bh_y_trim", "lc24")
FH_OWN = ("kk_amp", "kk_k", "kk_v0", "kk_m1", "t_servo", "lc0", "lc8", "k_z", "k_n", "p_z", "p_n", "nz_bias", "box_x0", "box_x1", "t_lock", "hx_pad",
          "ns_k", "k_vpm", "z_bias", "y_trim", "arm_kp", "stiff", "t_swing", "d_push")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bh", required=True, help="DIR:RUN of a backhand tt_rsm design")
    ap.add_argument("--fh", help="DIR:RUN of a forehand tt_rsm design, or params:FILE (a forehand step file); default: the champion's forehand")
    ap.add_argument("--set", default="")
    ap.add_argument("--write", required=True)
    a = ap.parse_args()
    champ = tt_fast.read_params(CHAMP)
    P = dict(champ)
    bdir, brun = a.bh.split(":")
    B = run_params(bdir, int(brun))
    for k in BH_OWN:
        if k in B:
            P[k] = B[k]
    P["kk2_amp"], P["kk2_k"], P["kk2_v0"] = B["kk_amp"], B["kk_k"], B["kk_v0"]
    P["ns_k2"], P["k_vpm2"] = B["ns_k"], B["k_vpm"]
    P["bh_box_dx"] = round(B["box_x0"] - champ.get("box_x0", -1.2), 6)
    if a.fh:
        if a.fh.startswith("params:"):
            F = tt_fast.read_params(a.fh[len("params:"):])
        else:
            fdir, frun = a.fh.split(":")
            F = run_params(fdir, int(frun))
        for k in FH_OWN:
            if k in F:
                P[k] = F[k]
    else:
        P["kk_amp"] = 0.0
        P["kk_m1"] = 0.27
    # the backhand's box is the forehand's shifted by one number (bh_box_dx; mean of the two ends' shifts)
    fx0, fx1 = P.get("box_x0", champ.get("box_x0", -1.2)), P.get("box_x1", champ.get("box_x1", -0.7))
    P["bh_box_dx"] = round(0.5 * ((B["box_x0"] - fx0) + (B["box_x1"] - fx1)), 6)
    for k, v in (("bk", 1.0), ("kk", 1.0), ("lc", 1.0), ("lt_arms", 0.0)):
        P[k] = v
    for kv in filter(None, a.set.split(",")):
        k, v = kv.split("=")
        P[k] = float(v)
    with open(a.write, "w") as f:
        f.write(f"# round 10 candidate: backhand {a.bh}" + (f", forehand {a.fh}" if a.fh else ", forehand = round-5 champion + bk") + "\n")
        for k in sorted(P):
            f.write(f"{k} {float(P[k])!r}\n")
    print("wrote", a.write, "; backhand-own:", {k: P[k] for k in ("kk2_amp", "kk2_k", "kk2_v0", "ns_k2", "k_vpm2", "bh_box_dx", "kk_m2", "bh_gain", "bh_p_n")})


if __name__ == "__main__":
    main()
