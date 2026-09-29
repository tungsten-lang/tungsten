"""Turn an oracle program (npz from oracle_search.py / oracle_multi.py) into skill params (pg_* tables).

    .venv/bin/python scratchpad/btl2/oracle_to_params.py base.txt out.txt --add prog.npz:side:ordinal [--add ...] [--pg-first 1] [--lead 0.165] [--gain 0]

`side` is l or r (the arm the table drives; the oracle's muscle order is mapped to the skill's canonical order:
shoulder flex/abd/rot, elbow, wrist flex/dev, finger mcp/pip, each pos then neg), `ordinal` the programmed pass (0 = the
first programmed pass, pass number pg_first). Several --add build several stages; pg_n is the highest ordinal + 1.
"""
import argparse
import sys
import numpy as np
sys.path.insert(0, "scratchpad/btl2")
from common import load, write_params

JOINTS = ["shoulder_flex", "shoulder_abd", "shoulder_rot", "elbow", "wrist_flex", "wrist_dev", "finger_mcp", "finger_pip"]


def canonical_rows(names, idx, side):
    rows = []
    lookup = {names[i]: r for r, i in enumerate(idx)}
    for j in JOINTS:
        for pn in ("pos", "neg"):
            rows.append(lookup[f"{side}_{j}_{pn}"])
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("base")
    ap.add_argument("out")
    ap.add_argument("--add", action="append", required=True)
    ap.add_argument("--pg-first", type=int, default=1)
    ap.add_argument("--lead", type=float, default=0.165)
    ap.add_argument("--gain", type=float, default=0.0)
    ap.add_argument("--note", default="")
    ap.add_argument("--pg-n", type=int, default=0, help="programmed passes (default: the number of stages)")
    ap.add_argument("--pg-per", type=int, default=0, help="after the last stage, cycle through the last N stages")
    a = ap.parse_args()
    import oracle_lib as O
    p = load(a.base)
    # the muscle names, from any build of the model
    from bridge import Sim
    from dribble_btl import DribbleBtlTask
    t = DribbleBtlTask(); t.body_kind = "v3"
    names = [mu.name for mu in Sim(t, params={}, controller="/x").muscles]
    nmax = 0
    gs_any = False
    pg_zj = None
    gmax = 1000.0
    dk = None
    nk = None
    for spec in a.add:
        f, side, ordinal = spec.split(":")
        ordinal = int(ordinal)
        z = np.load(f)
        idx, kt, x = list(z["idx"]), z["kt"], z["x"]
        is_gs = "gs" in z.files
        nm_, K_ = len(idx), len(kt)
        nblocks = len(x) // (nm_ * K_)
        blocks = x.reshape(nblocks, nm_, K_)
        nz = max(nblocks - 3, 0) if is_gs else 0
        zj = [int(v) for v in z["zj"]] if (is_gs and "zj" in z.files) else []
        assert len(zj) == nz, f"{f}: {nz} posture blocks but joints {zj}"
        # a gain-scheduled table forms T0 + u Tx + u Ty at the knots before bounding it, so T0 is written as searched
        X = blocks[0] if is_gs else np.clip(blocks[0], 0, 1)
        rows = canonical_rows(names, idx, side)
        dk_here = int(kt[1] - kt[0])
        nk_here = len(kt)
        if dk is None:
            dk, nk = dk_here, nk_here
        assert (dk, nk) == (dk_here, nk_here), "all stages need the same knot layout"
        for m, r in enumerate(rows):
            for k in range(nk):
                p[f"pg{ordinal}_{m}_{k}"] = float(X[r, k])
                if is_gs:
                    p[f"pgx{ordinal}_{m}_{k}"] = float(blocks[1][r, k])
                    p[f"pgy{ordinal}_{m}_{k}"] = float(blocks[2][r, k])
                    for i in range(nz):
                        p[f"pgz{ordinal}_{i}_{m}_{k}"] = float(blocks[3 + i][r, k])
        if is_gs:
            gs_any = True
            gmax = float(z["gmax"]) if "gmax" in z.files else 1000.0
            p[f"pgc{ordinal}x"] = float(z["nom"][0])
            p[f"pgc{ordinal}y"] = float(z["nom"][1])
            p[f"pgs{ordinal}x"] = float(z["sc"][0])
            p[f"pgs{ordinal}y"] = float(z["sc"][1])
            for i in range(nz):
                p[f"pgzn{ordinal}_{i}"] = float(z["nom"][2 + i])
                p[f"pgzs{ordinal}_{i}"] = float(z["sc"][2 + i])
            if nz:
                if pg_zj is None:
                    pg_zj = zj
                assert pg_zj == zj, f"all posture stages need the same joints ({pg_zj} vs {zj})"
        nmax = max(nmax, ordinal + 1)
    p["pg_on"] = 1.0
    p["pg_gs"] = 1.0 if gs_any else 0.0
    if gs_any:
        p["pg_gmax"] = gmax
    if pg_zj:
        p["pg_nz"] = float(len(pg_zj))
        for i, j in enumerate(pg_zj):
            p[f"pgzj{i}"] = float(j)
    p["pg_stages"] = float(nmax)
    p["pg_per"] = float(a.pg_per)
    p["pg_n"] = float(a.pg_n or nmax)
    p["pg_first"] = float(a.pg_first)
    p["pg_nk"] = float(nk)
    p["pg_dk"] = dk * 0.005
    p["pg_lead"] = a.lead
    p["pg_gain"] = a.gain
    write_params(a.out, p, a.note or f"A4 + muscle programs {a.add}")
    print("wrote", a.out, "stages", nmax, "knots", nk, "dk", dk * 0.005)


if __name__ == "__main__":
    main()
