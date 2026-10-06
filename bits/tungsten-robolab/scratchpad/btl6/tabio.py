"""Write a params file with ONE stage's table replaced (every other key kept: the servo, the lifts, ...), keys as the skill reads them."""
import sys
sys.path.insert(0, "scratchpad/btl2"); sys.path.insert(0, "scratchpad/btl6")
import numpy as np
from common import load, write_params
NK = 17


def write_table(base, out, stage, B, note, nom=None, sc=None, extra=None):
    p = load(base)
    nz = 3
    for m in range(16):
        for k in range(NK):
            p[f"pg{stage}_{m}_{k}"] = float(B[0, m, k])
            p[f"pgx{stage}_{m}_{k}"] = float(B[1, m, k])
            p[f"pgy{stage}_{m}_{k}"] = float(B[2, m, k])
            for i in range(nz):
                p[f"pgz{stage}_{i}_{m}_{k}"] = float(B[3 + i, m, k])
    if B.shape[0] > 6:        # the energy-hinge block (skill key pg_vn 1): pgv<stage>_<m>_<k>
        for m in range(16):
            for k in range(NK):
                p[f"pgv{stage}_{m}_{k}"] = float(B[6, m, k])
    if B.shape[0] > 7:        # the strong-side apex block (skill key pgw<stage>_<m>_<k>, pgwk<stage>, pgws<stage>)
        for m in range(16):
            for k in range(NK):
                p[f"pgw{stage}_{m}_{k}"] = float(B[7, m, k])
    if nom is not None:
        p[f"pgc{stage}x"], p[f"pgc{stage}y"] = float(nom[0]), float(nom[1])
        for i in range(nz):
            p[f"pgzn{stage}_{i}"] = float(nom[2 + i])
    if sc is not None:
        p[f"pgs{stage}x"], p[f"pgs{stage}y"] = float(sc[0]), float(sc[1])
        for i in range(nz):
            p[f"pgzs{stage}_{i}"] = float(sc[2 + i])
    if extra:
        p.update(extra)
    write_params(out, p, note)
