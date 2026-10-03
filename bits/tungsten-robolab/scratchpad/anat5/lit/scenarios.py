#!/usr/bin/env python3
"""Second-stage analysis on top of moment_arms_*.json (run after moment_arms.py):
  (1) shares with Arnold et al. 2010 (Ann Biomed Eng 38:269) Table 1 peak forces (cadaver PCSA x 61 N/cm2,
      PCSA from Ward et al. 2009) applied to the Rajagopal-2016 (Arnold-derived) geometry;
  (2) the RF knee-extension arm / hip-flexion arm ratio in the 'fold-back' postures;
  (3) evaluation of candidate (rf, hip_flex_pos, knee_neg) splits for the v5 calibration;
  (4) PCSA / volume architecture shares from Ward 2009 Table (read from PMC2650051) and the
      Rajagopal-2016 model volumes V = F * l_opt / 60 N/cm2 (their Eq. 3).
Writes scenarios.json.  Run from tungsten-robolab:  .venv/bin/python scratchpad/anat5/lit/scenarios.py"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
HIP = [-20, 0, 20, 40, 60]
KNEE = [0, 30, 60, 90, 120]

# Arnold et al. 2010, Table 1 'Muscle modeling parameters' (read in PMC2903973 XML): peak force (N)
ARNOLD_F = {
    "iliacus_r": 621.9, "psoas_r": 479.7, "recfem_r": 848.8, "sart_r": 113.5, "tfl_r": 155.0,
    "addbrev_r": 303.7, "addlong_r": 399.5, "addmagDist_r": 324.2, "addmagIsch_r": 324.2, "addmagMid_r": 324.2,
    "addmagProx_r": 324.2, "grac_r": 137.3, "glmed1_r": 881.1, "glmed2_r": 616.5, "glmed3_r": 702.0,
    "glmin1_r": 180.0, "glmin2_r": 190.0, "glmin3_r": 215.0, "glmax1_r": 546.1, "glmax2_r": 780.5, "glmax3_r": 526.1,
    "piri_r": 296.0, "vasint_r": 1024.2, "vaslat_r": 2255.4, "vasmed_r": 1443.7,
}

# Ward et al. 2009 (Clin Orthop Relat Res 467:1074), architecture table read in PMC2650051 (HTML): PCSA cm2 (mean)
WARD_PCSA = {"psoas": 7.7, "iliacus": 9.9, "rectus_femoris": 13.5, "sartorius": 1.9, "vastus_lateralis": 35.1,
             "vastus_intermedius": 16.7, "vastus_medialis": 20.6, "gracilis": 2.2, "adductor_longus": 6.5,
             "adductor_brevis": 5.0, "adductor_magnus": 20.5, "gluteus_medius": 33.8}
WARD_GROUPS = {"hip_flexors_total_PCSA(psoas,iliacus,RF,sartorius)": (35.9, 9.0), "knee_extensors_total_PCSA": (88.4, 30.5)}

HIPGROUPS = {"iliopsoas": ("iliacus_r", "psoas_r"), "rf": ("recfem_r",), "sartorius": ("sart_r",), "tfl": ("tfl_r",)}


def load(k):
    return json.load(open(os.path.join(HERE, "moment_arms_%s.json" % k)))


def hip_shares(ma, Fmap=None, knee=90):
    rows = {}
    for hi, hd in enumerate(HIP):
        caps = {}
        for nm, r in ma["muscles"].items():
            if r.get("hip_arm_m") is None:
                continue
            F = Fmap.get(nm) if Fmap is not None else r["F"]
            if F is None:
                continue
            a = r["hip_arm_m"][str(knee)][hi]
            if a > 0:
                caps[nm] = F * a
        tot = sum(caps.values())
        ilio = sum(caps.get(n, 0) for n in ("iliacus_r", "psoas_r"))
        rf = sum(v for n, v in caps.items() if n.startswith(("recfem", "rect_fem")))
        p5 = ilio + rf + sum(caps.get(n, 0) for n in ("sart_r", "tfl_r"))
        rows[str(hd)] = dict(total_Nm=tot, rf_share=rf / tot, iliopsoas_share=ilio / tot, rest_share=1 - rf / tot,
                             rf_share_of_iliopsoas_rf_sar_tfl=rf / p5, iliopsoas_share_of_iliopsoas_rf_sar_tfl=ilio / p5)
    return rows


def knee_shares(ma, Fmap=None, hip=0):
    rows = {}
    for ki, kd in enumerate(KNEE):
        rf = vas = 0.0
        for nm, r in ma["muscles"].items():
            if r.get("knee_ext_arm_m") is None:
                continue
            F = Fmap.get(nm) if Fmap is not None else r["F"]
            if F is None:
                continue
            a = r["knee_ext_arm_m"][str(hip)][ki]
            if a <= 0:
                continue
            if nm.startswith(("recfem", "rect_fem")):
                rf += F * a
            elif nm.startswith("vas"):
                vas += F * a
        rows[str(kd)] = dict(rf_Nm=rf, vasti_Nm=vas, rf_share=rf / (rf + vas))
    return rows


def main():
    out = {}
    raj = load("rajagopal2016")
    g = load("gait2392")
    lai = load("rajagopal_lai_uhlrich2023")
    out["arnold2010_F_on_rajagopal_geometry"] = dict(
        hip_knee90=hip_shares(raj, ARNOLD_F, 90), hip_knee0=hip_shares(raj, ARNOLD_F, 0),
        knee_hip0=knee_shares(raj, ARNOLD_F, 0))
    # F-only shares (no moment arms)
    out["F_only"] = dict(
        gait2392_RF_over_RF_plus_vasti=1169 / (1169 + 1294 + 1365 + 1871),
        rajagopal2016_RF_over_RF_plus_vasti=2192 / (2192 + 1697 + 5149 + 2748),
        arnold2010_RF_over_RF_plus_vasti=848.8 / (848.8 + 1024.2 + 2255.4 + 1443.7),
        gait2392_RF_over_RF_plus_iliopsoas=1169 / (1169 + 1073 + 1113),
        rajagopal2016_RF_over_RF_plus_iliopsoas=2192 / (2192 + 1021 + 1427),
        arnold2010_RF_over_RF_plus_iliopsoas=848.8 / (848.8 + 621.9 + 479.7))
    # architecture (PCSA) shares, Ward 2009
    P = WARD_PCSA
    vas = P["vastus_lateralis"] + P["vastus_intermedius"] + P["vastus_medialis"]
    hf4 = P["psoas"] + P["iliacus"] + P["rectus_femoris"] + P["sartorius"]
    out["ward2009_PCSA"] = dict(
        RF_over_RF_plus_vasti=P["rectus_femoris"] / (P["rectus_femoris"] + vas),
        RF_over_vasti=P["rectus_femoris"] / vas,
        RF_over_hipflexor4_sum=P["rectus_femoris"] / hf4, iliopsoas_over_hipflexor4_sum=(P["psoas"] + P["iliacus"]) / hf4,
        sartorius_over_hipflexor4_sum=P["sartorius"] / hf4,
        RF_over_group_total_35p9=P["rectus_femoris"] / 35.9, RF_over_knee_ext_group_total_88p4=P["rectus_femoris"] / 88.4,
        hipflexor4_sum=hf4, vasti_sum=vas)
    # Rajagopal 2016 model volumes: V = F * lopt / sigma, sigma = 60 N/cm2 (lopt cm from Table II of the paper / .osim)
    vol = {}
    for nm in ("iliacus_r", "psoas_r", "recfem_r", "sart_r", "tfl_r", "vasint_r", "vaslat_r", "vasmed_r"):
        r = raj["muscles"][nm]
        vol[nm] = r["F"] * (r["lopt"] * 100.0) / 60.0
    volvas = vol["vasint_r"] + vol["vaslat_r"] + vol["vasmed_r"]
    out["rajagopal2016_volume_cm3_derived"] = dict(
        vol, vasti_sum=volvas, RF_over_RF_plus_vasti=vol["recfem_r"] / (vol["recfem_r"] + volvas),
        RF_over_RF_plus_iliopsoas=vol["recfem_r"] / (vol["recfem_r"] + vol["iliacus_r"] + vol["psoas_r"]))
    # RF knee/hip moment arm ratio in the fold-back postures
    ratio = {}
    for key, ma, nm in (("gait2392", g, "rect_fem_r"), ("rajagopal2016", raj, "recfem_r"), ("rajagopal_lai_uhlrich2023", lai, "recfem_r")):
        r = ma["muscles"][nm]
        ratio[key] = {}
        for hd in (0, 20, 40, 60):
            for kd in (30, 60, 90, 120):
                hi = HIP.index(hd)
                ha = r["hip_arm_m"][str(kd)][hi]
                ka = r["knee_ext_arm_m"][str(hd)][KNEE.index(kd)]
                ratio[key]["hip%d_knee%d" % (hd, kd)] = dict(hip_arm_cm=100 * ha, knee_arm_cm=100 * ka, ratio_knee_over_hip=ka / ha)
    out["rf_knee_over_hip_arm_ratio"] = ratio
    # candidate splits for the v5 body: totals hip 250, knee 350 fixed, rf couples 1.0 (hip) : 0.8 (knee)
    cands = {}
    for rf in (150, 100, 90, 88, 85, 80, 76, 70, 66, 60, 50):
        cands[str(rf)] = dict(rf=rf, hip_flex_pos=250 - rf, knee_neg=350 - 0.8 * rf, rf_share_hip=rf / 250.0,
                              rf_share_knee=0.8 * rf / 350.0, rf_hip_torque_Nm=rf, rf_knee_torque_Nm=0.8 * rf)
    out["candidate_splits"] = cands
    with open(os.path.join(HERE, "scenarios.json"), "w") as f:
        json.dump(out, f, indent=1, default=float)
    # console summary
    a = out["arnold2010_F_on_rajagopal_geometry"]
    print("Arnold2010 F on Rajagopal geometry, hip flexion, knee 90: RF share of all-positive capacity by hip angle")
    print("  hip   ", HIP)
    print("  RF    ", ["%.1f" % (100 * a["hip_knee90"][str(h)]["rf_share"]) for h in HIP])
    print("  iliops", ["%.1f" % (100 * a["hip_knee90"][str(h)]["iliopsoas_share"]) for h in HIP])
    print("  total ", ["%.0f" % a["hip_knee90"][str(h)]["total_Nm"] for h in HIP])
    print("  RF/(ilio+RF+sar+tfl)", ["%.1f" % (100 * a["hip_knee90"][str(h)]["rf_share_of_iliopsoas_rf_sar_tfl"]) for h in HIP])
    print("Arnold2010 F on Rajagopal geometry, knee ext RF/(RF+vasti) at hip 0 by knee", KNEE, ["%.1f" % (100 * a["knee_hip0"][str(k)]["rf_share"]) for k in KNEE])
    print("F-only:", {k: round(v, 3) for k, v in out["F_only"].items()})
    print("Ward2009 PCSA:", {k: round(v, 3) for k, v in out["ward2009_PCSA"].items()})
    print("Raj2016 volumes cm3:", {k: round(v, 1) if isinstance(v, float) and v > 2 else round(v, 3) for k, v in out["rajagopal2016_volume_cm3_derived"].items()})
    for k, v in ratio.items():
        print("RF knee/hip arm ratio", k, {kk: round(vv["ratio_knee_over_hip"], 2) for kk, vv in v.items() if kk in ("hip0_knee30", "hip20_knee90", "hip40_knee90", "hip40_knee120", "hip60_knee90", "hip60_knee120")})


if __name__ == "__main__":
    main()
