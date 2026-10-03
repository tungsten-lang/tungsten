#!/usr/bin/env python3
"""Moment arms and isometric torque capacities of the hip/knee muscles of published OpenSim models.

Run from /Users/erik/tungsten/bits/tungsten-robolab:
    .venv/bin/python scratchpad/anat5/lit/moment_arms.py
Writes (next to this file): moment_arms_<model>.json and shares.json

METHOD (all computed, nothing typed in from memory):
  * osim_paths.py parses the .osim (OpenSim 4.0 format) and evaluates the muscle-tendon path length
    L(q) from the model geometry: path points on bodies, ConditionalPathPoints, MovingPathPoints,
    CustomJoint SpatialTransforms (SimmSpline = natural cubic spline), CoordinateCouplerConstraints
    (patella), and WrapCylinders (port of OpenSim WrapCylinder::wrapLine + GeometryPath::applyWrapObjects).
  * moment arm = -dL/dq (central difference, h = 0.5 deg, one-sided at the range ends), sign so that
    hip FLEXION arm > 0 and knee EXTENSION arm > 0 (knee flexion angle phi >= 0: r_ext = +dL/dphi).
  * pelvis fixed, hip adduction = rotation = 0, other coordinates at their default (0).
  * capacity = F_max * max(arm, 0)   ("isometric torque capacity", f_L = 1)
    capacity_fL = F_max * f_L(fiber length) * max(arm, 0), with a rigid-tendon fiber length
      l_f = sqrt((l_mt - l_ts)^2 + (l_opt sin(alpha0))^2)   (constant-thickness pennation)
      f_L = exp(-(l_f/l_opt - 1)^2 / 0.45)                  (Thelen 2003 Gaussian, used for BOTH models)
    -> the f_L-weighted numbers are an approximation (rigid tendon, Gaussian f_L for the Millard model too).
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from osim_paths import Model, DEG  # noqa: E402

HIP = [-20, 0, 20, 40, 60]
KNEE = [0, 30, 60, 90, 120]
H = 0.5 * DEG

MODELS = [
    dict(key="gait2392", file="gait2392_thelen2003muscle.osim",
         desc="gait2392 (Delp et al. 1990 lineage; OpenSim 4.0 file, Thelen2003Muscle)"),
    dict(key="rajagopal2016", file="Rajagopal2016.osim",
         desc="Rajagopal et al. 2016 IEEE TBME (Millard2012EquilibriumMuscle)"),
    dict(key="rajagopal_lai_uhlrich2023", file="RajagopalLaiUhlrich2023.osim",
         desc="Rajagopal model as modified by Lai/Uhlrich (2023 release, Millard2012EquilibriumMuscle)"),
]

GROUPS_HIP = [
    ("iliopsoas", ("iliacus", "psoas")),
    ("rf", ("rect_fem", "recfem")),
    ("sartorius", ("sar_", "sart_")),
    ("tfl", ("tfl",)),
    ("pectineus", ("pect",)),
    ("adductors_gracilis", ("add_", "add", "grac")),
    ("glut_med_min", ("glut_med", "glut_min", "glmed", "glmin")),
]


def group_of(name, table):
    for g, prefixes in table:
        if any(name.startswith(p) for p in prefixes):
            return g
    return "other"


def is_vastus(name):
    return name.startswith("vas")


def knee_sign(m):
    a = m.body_T(m.coords({"knee_angle_r": 0.5}))["talus_r"][0, 3]
    b = m.body_T(m.coords({"knee_angle_r": -0.5}))["talus_r"][0, 3]
    return 1 if a < b else -1  # flexion moves the ankle posteriorly (-x)


def bodies_of(mus):
    return {p["body"] for p in mus["points"]}


def crosses_hip(mus):
    b = bodies_of(mus)
    return "pelvis" in b and len(b - {"pelvis"}) > 0


def crosses_knee(mus):
    b = bodies_of(mus)
    prox = b & {"pelvis", "femur_r"}
    dist = b & {"tibia_r", "patella_r", "talus_r", "calcn_r", "toes_r"}
    return bool(prox) and bool(dist)


def deriv(fn, x0, lo, hi, h=H):
    """d fn/dx at x0 (rad) using central difference, one-sided at the range ends (lo/hi in rad)."""
    if x0 - h >= lo - 1e-12 and x0 + h <= hi + 1e-12:
        return (fn(x0 + h) - fn(x0 - h)) / (2 * h)
    if x0 - h < lo:
        return (fn(x0 + h) - fn(x0)) / h
    return (fn(x0) - fn(x0 - h)) / h


def compute_model(spec):
    m = Model(os.path.join(HERE, spec["file"]))
    ks = knee_sign(m)
    kr = m.coord_range["knee_angle_r"]
    kflex_lo, kflex_hi = (0.0, 120.0 * DEG)
    out = dict(model=spec["key"], file=spec["file"], desc=spec["desc"], knee_sign=ks, hip_deg=HIP, knee_deg=KNEE,
               h_deg=0.5, notes=[], muscles={})
    if ks == -1:
        out["notes"].append("knee flexion phi = -knee_angle_r in this model")
    unsupported = []
    for nm, mus in m.muscles.items():
        if not nm.endswith("_r"):
            continue
        rec = dict(F=mus["F"], lopt=mus["lopt"], lts=mus["lts"], pen=mus["pen"], type=mus["type"],
                   bodies=sorted(bodies_of(mus)), hip_arm_m=None, knee_ext_arm_m=None, L_mtu_m=None,
                   fl=None, lf_norm=None)
        try:
            # length / f_L grid over (hip, knee)
            L = []
            lf = []
            fl = []
            for hd in HIP:
                Lrow, lfrow, flrow = [], [], []
                for kd in KNEE:
                    q = {"hip_flexion_r": hd * DEG, "knee_angle_r": ks * kd * DEG}
                    Lm = m.length(nm, q)
                    lfib = math.sqrt(max(Lm - mus["lts"], 0.0) ** 2 + (mus["lopt"] * math.sin(mus["pen"])) ** 2)
                    ln = lfib / mus["lopt"]
                    Lrow.append(Lm)
                    lfrow.append(ln)
                    flrow.append(math.exp(-((ln - 1.0) ** 2) / 0.45))
                L.append(Lrow)
                lf.append(lfrow)
                fl.append(flrow)
            rec["L_mtu_m"], rec["lf_norm"], rec["fl"] = L, lf, fl
            if crosses_hip(mus):
                arm = {}
                lo, hi = m.coord_range["hip_flexion_r"]
                for kd in KNEE:
                    row = []
                    for hd in HIP:
                        f = lambda x, kd=kd: m.length(nm, {"hip_flexion_r": x, "knee_angle_r": ks * kd * DEG})
                        row.append(-deriv(f, hd * DEG, lo, hi))
                    arm[str(kd)] = row
                rec["hip_arm_m"] = arm
            if crosses_knee(mus):
                arm = {}
                for hd in HIP:
                    row = []
                    for kd in KNEE:
                        # derivative wrt knee FLEXION angle phi (>= 0)
                        f = lambda x, hd=hd: m.length(nm, {"hip_flexion_r": hd * DEG, "knee_angle_r": ks * x})
                        row.append(deriv(f, kd * DEG, kflex_lo, kflex_hi))
                    arm[str(hd)] = row
                rec["knee_ext_arm_m"] = arm
        except NotImplementedError as e:
            unsupported.append((nm, str(e)))
            rec["unsupported"] = str(e)
        out["muscles"][nm] = rec
    if unsupported:
        out["notes"].append("unsupported wrap type, muscle skipped: %r" % (unsupported,))
    return m, out


def shares_for_model(out):
    """Capacities and group shares from the computed arms."""
    mus = out["muscles"]
    res = dict(model=out["model"], hip_flexion={}, knee_extension={})
    # ---- hip flexion: for each knee angle (matters for biarticulars) and hip angle
    for weighting in ("isometric", "fl_weighted"):
        res["hip_flexion"][weighting] = {}
        for ki, kd in enumerate(KNEE):
            res["hip_flexion"][weighting][str(kd)] = {}
            for hi, hd in enumerate(HIP):
                caps = {}
                for nm, r in mus.items():
                    if r.get("hip_arm_m") is None:
                        continue
                    a = r["hip_arm_m"][str(kd)][hi]
                    if a <= 0:
                        continue
                    w = r["fl"][hi][ki] if weighting == "fl_weighted" else 1.0
                    caps[nm] = r["F"] * w * a
                total = sum(caps.values())
                groups = {}
                for nm, c in caps.items():
                    g = group_of(nm, GROUPS_HIP)
                    groups[g] = groups.get(g, 0.0) + c
                principal = sum(c for g, c in groups.items() if g in ("iliopsoas", "rf", "sartorius", "tfl", "pectineus"))
                res["hip_flexion"][weighting][str(kd)][str(hd)] = dict(
                    total_Nm=total,
                    group_Nm=groups,
                    share_all={g: c / total for g, c in groups.items()},
                    principal6_total_Nm=principal,
                    share_principal6={g: groups.get(g, 0.0) / principal for g in ("iliopsoas", "rf", "sartorius", "tfl", "pectineus")},
                    per_muscle_Nm=caps,
                )
    # ---- knee extension: for each hip angle, knee angle
    for weighting in ("isometric", "fl_weighted"):
        res["knee_extension"][weighting] = {}
        for hi, hd in enumerate(HIP):
            res["knee_extension"][weighting][str(hd)] = {}
            for ki, kd in enumerate(KNEE):
                caps = {}
                for nm, r in mus.items():
                    if r.get("knee_ext_arm_m") is None:
                        continue
                    a = r["knee_ext_arm_m"][str(hd)][ki]
                    if a <= 0:
                        continue
                    w = r["fl"][hi][ki] if weighting == "fl_weighted" else 1.0
                    caps[nm] = r["F"] * w * a
                rf = sum(c for n, c in caps.items() if n.startswith(("rect_fem", "recfem")))
                vas = sum(c for n, c in caps.items() if is_vastus(n))
                tot_all = sum(caps.values())
                res["knee_extension"][weighting][str(hd)][str(kd)] = dict(
                    rf_Nm=rf, vasti_Nm=vas, total_all_Nm=tot_all, other_Nm=tot_all - rf - vas,
                    share_rf_of_rf_plus_vasti=rf / (rf + vas) if rf + vas > 0 else None,
                    share_rf_of_all=rf / tot_all if tot_all > 0 else None,
                    per_muscle_Nm=caps)
    return res


def main():
    allshares = {}
    for spec in MODELS:
        try:
            m, out = compute_model(spec)
        except Exception as e:  # keep going for the bonus model
            print("FAILED", spec["key"], repr(e))
            continue
        with open(os.path.join(HERE, "moment_arms_%s.json" % spec["key"]), "w") as f:
            json.dump(out, f, indent=1, default=float)
        allshares[spec["key"]] = shares_for_model(out)
        print("wrote", spec["key"], len(out["muscles"]), "right-leg muscles", out["notes"])
    with open(os.path.join(HERE, "shares.json"), "w") as f:
        json.dump(allshares, f, indent=1, default=float)


if __name__ == "__main__":
    main()
