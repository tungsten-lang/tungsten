#!/usr/bin/env python3
"""Does the grip matter AT IMPACT? The decelerating ideal servo (the pad's measured pose is corrected, so a grip that changes the paddle's pose in the hand no longer adds an orientation error)
with the champion's grip and firmer grips (the earlier sweep's variants) on the 70 validation serves 98030-98099. Measures per variant: serves reaching contact, lost before contact, pad error at
contact, pad speed at contact, solved. Run from bits/tungsten-robolab. A file with a __main__ guard."""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grasp_search as gs  # noqa: E402

VARIANTS = [("champion grip", {}), ("grip_drive 0.8", {"grip_drive": 0.8}), ("grip_drive 1.5", {"grip_drive": 1.5}),
            ("gfull", {"grip_drive": 0.8, "g_fpl": 0.6, "g_idx": 0.6, "g_mid": 0.6, "g_ring": 0.4, "g_idx_int": 0.6}),
            ("gmax", {"grip_drive": 2.0, "g_fpl": 0.6, "g_op": 0.6, "g_idx": 0.6, "g_mid": 0.6, "g_ring": 0.6, "g_idx_int": 0.6, "g_text": -0.5, "g_fext": -0.5}),
            ("loose grip (drive 0, flexors 0)", {"grip_drive": 0.0, "g_fpl": 0.0, "g_op": 0.0, "g_idx": 0.0, "g_mid": 0.0, "g_ring": 0.0, "g_idx_int": 0.0})]


def main():
    base = gs.champion_x()
    out = []
    for label, over in VARIANTS:
        x = base.copy()
        for k, v in over.items():
            x[gs.PARAMS.index(k)] = v
        d = gs.run_serves(x, "var_" + label.split()[0] + "_" + str(len(out)), gs.VALID, workers=6)
        m = gs.metrics(d, gs.VALID)
        sp = []
        for s in range(gs.VALID[0], gs.VALID[1]):
            f = os.path.join(d, "logs", f"{s}.npz")
            if os.path.exists(f):
                z = np.load(f, allow_pickle=True)
                L, k = z["L"], int(z["contact"])
                if k >= 3:
                    sp.append(float(np.linalg.norm((L[k - 1, 7:10] - L[k - 2, 7:10]) / (L[k - 1, 0] - L[k - 2, 0]))))
        m["pad_speed_med"] = round(float(np.median(sp)), 2) if sp else None
        m["solved_of_contacts"] = round(m["solved"] / max(m["contact"], 1), 3)
        print(f"{label:34s} {m}", flush=True)
        out.append({"label": label, **m})
    json.dump(out, open("scratchpad/tt4/gs_grip_variants.json", "w"), indent=1)


if __name__ == "__main__":
    main()
