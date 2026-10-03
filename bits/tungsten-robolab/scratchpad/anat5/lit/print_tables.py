#!/usr/bin/env python3
"""Pretty-print the tables from shares.json / moment_arms_*.json (run after moment_arms.py).
    .venv/bin/python scratchpad/anat5/lit/print_tables.py > scratchpad/anat5/lit/tables.txt"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
S = json.load(open(os.path.join(HERE, "shares.json")))
HIP = [-20, 0, 20, 40, 60]
KNEE = [0, 30, 60, 90, 120]
GR = ["iliopsoas", "rf", "sartorius", "tfl", "pectineus", "adductors_gracilis", "glut_med_min", "other"]


def pct(x):
    return "%5.1f" % (100 * x)


for key, sh in S.items():
    ma = json.load(open(os.path.join(HERE, "moment_arms_%s.json" % key)))
    print("=" * 100)
    print("MODEL", key, "-", ma["desc"])
    print("Fmax (N):", {k: round(v["F"]) for k, v in ma["muscles"].items()
                        if k.startswith(("iliacus", "psoas", "rect_fem", "recfem", "sar", "tfl", "pect", "vas"))})
    for weighting in ("isometric", "fl_weighted"):
        for kd in (0, 30, 60, 90, 120):
            print("\nHIP FLEXION capacity shares [%%] (%s), knee flexion %d deg; hip angle across; total in N m" % (weighting, kd))
            print("  %-20s" % "group" + "".join("%9d" % h for h in HIP))
            tot = [sh["hip_flexion"][weighting][str(kd)][str(h)]["total_Nm"] for h in HIP]
            print("  %-20s" % "TOTAL Nm" + "".join("%9.1f" % t for t in tot))
            for g in GR:
                row = []
                for h in HIP:
                    d = sh["hip_flexion"][weighting][str(kd)][str(h)]
                    row.append(d["share_all"].get(g, 0.0))
                print("  %-20s" % g + "".join("%9s" % pct(x) for x in row))
            print("  share among principal-6 (iliopsoas, rf, sar, tfl, pect):")
            for g in ("iliopsoas", "rf"):
                row = [sh["hip_flexion"][weighting][str(kd)][str(h)]["share_principal6"][g] for h in HIP]
                print("  %-20s" % g + "".join("%9s" % pct(x) for x in row))
    for weighting in ("isometric", "fl_weighted"):
        for hd in (0, 60):
            print("\nKNEE EXTENSION (%s), hip %d deg; knee angle across" % (weighting, hd))
            print("  %-26s" % "" + "".join("%9d" % k for k in KNEE))
            for lab, f in (("RF Nm", "rf_Nm"), ("vasti Nm", "vasti_Nm"), ("other Nm", "other_Nm")):
                print("  %-26s" % lab + "".join("%9.1f" % sh["knee_extension"][weighting][str(hd)][str(k)][f] for k in KNEE))
            print("  %-26s" % "RF/(RF+vasti) %" + "".join("%9s" % pct(sh["knee_extension"][weighting][str(hd)][str(k)]["share_rf_of_rf_plus_vasti"]) for k in KNEE))
            print("  %-26s" % "RF/(all ext) %" + "".join("%9s" % pct(sh["knee_extension"][weighting][str(hd)][str(k)]["share_rf_of_all"]) for k in KNEE))
    print("\nMOMENT ARMS [cm]  (hip flexion arm at knee 90; knee extension arm at hip 0 / hip 60)")
    for nm, r in ma["muscles"].items():
        if r.get("hip_arm_m") is not None and any(v > 0 for v in r["hip_arm_m"]["90"]):
            print("  hip  %-14s F=%6.0f  arm@hip%s = %s" % (nm, r["F"], HIP, " ".join("%6.2f" % (100 * a) for a in r["hip_arm_m"]["90"])))
    for nm, r in ma["muscles"].items():
        if r.get("knee_ext_arm_m") is not None and any(v > 0 for v in r["knee_ext_arm_m"]["0"]):
            print("  knee %-14s F=%6.0f  ext-arm@knee%s hip0 = %s | hip60 = %s" % (
                nm, r["F"], KNEE, " ".join("%6.2f" % (100 * a) for a in r["knee_ext_arm_m"]["0"]),
                " ".join("%6.2f" % (100 * a) for a in r["knee_ext_arm_m"]["60"])))
    print("\nfL of RF (hip rows, knee cols) and normalized fibre length:")
    for nm in ma["muscles"]:
        if nm.startswith(("rect_fem", "recfem")):
            r = ma["muscles"][nm]
            for i, h in enumerate(HIP):
                print("  hip %3d  lf/lopt=%s  fL=%s" % (h, " ".join("%5.2f" % x for x in r["lf_norm"][i]), " ".join("%5.2f" % x for x in r["fl"][i])))
    for nm in ma["muscles"]:
        if nm.startswith(("vas_lat", "vaslat")):
            r = ma["muscles"][nm]
            print("  %s (hip 0)  lf/lopt=%s  fL=%s" % (nm, " ".join("%5.2f" % x for x in r["lf_norm"][1]), " ".join("%5.2f" % x for x in r["fl"][1])))
