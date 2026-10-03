"""Write playground/calibrations/v5.json: v4's every value unchanged + a `peaks` block that re-proportions ONLY the split of each joint's
total peak torque between the rectus femoris and the monoarticular hip flexors / knee extensors (data only, no code change).

    .venv/bin/python scratchpad/anat5/make_v5.py [--rf 80] [--out playground/calibrations/v5.json]

The numbers come from scratchpad/anat5/lit (moment arms computed from the OpenSim model files, PCSA tables read in the papers): see the
`sources` and `split_check` blocks of the output.
"""
import argparse, json, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ap = argparse.ArgumentParser()
ap.add_argument("--rf", type=float, default=80.0)
ap.add_argument("--out", default=os.path.join(ROOT, "playground", "calibrations", "v5.json"))
a = ap.parse_args()

v4 = json.load(open(os.path.join(ROOT, "playground", "calibrations", "v4.json")))
HIP_TOTAL, KNEE_TOTAL = 250.0, 350.0          # v4: hip_flex_pos 100 + 1.0 x rf 150 ; knee_neg 230 + 0.8 x rf 150
rf = a.rf
hip = HIP_TOTAL - 1.0 * rf
knee = KNEE_TOTAL - 0.8 * rf
peaks = {"hip_flex_pos": round(hip, 6), "rf": rf, "knee_neg": round(knee, 6)}
share_hip, share_knee = rf / HIP_TOTAL, 0.8 * rf / KNEE_TOTAL

params = json.loads(json.dumps(v4["params"]))     # every v4 value, byte for byte (tendon_scale, omega_muscle)
params["peaks"] = {
    "value": peaks,
    "v4": {"hip_flex_pos": 100, "rf": 150, "knee_neg": 230},
    "unit": "unscaled peak isometric force / torque scale of one muscle direction (N m at coefficient 1); the population profile then multiplies it (p95: x1.32). hip_flex_pos = the lumped monoarticular hip flexors (iliopsoas, sartorius, tensor fasciae latae, pectineus, anterior adductors), knee_neg = the lumped vasti, rf = the biarticular rectus femoris (torque 1.0 x F at the hip, 0.8 x F at the knee). Both legs.",
    "totals_kept": {
        "hip flexion": "hip_flex_pos + 1.0 x rf = 250 N m (v4: 100 + 150)",
        "knee extension": "knee_neg + 0.8 x rf = 350 N m (v4: 230 + 120)",
        "unchanged": "hip extension (hip_flex_neg 120 + ham), knee flexion (knee_pos 40 + ham, gas), ankle, toe, every speed (omega), tendon and activation value: not touched"
    },
    "shares": {
        "v4": {"rf share of hip flexion": "60 % (150/250)", "rf share of knee extension": "34 % (120/350)"},
        "v5": {"rf share of hip flexion": f"{share_hip * 100:.0f} % ({rf:g}/250)", "rf share of knee extension": f"{share_knee * 100:.1f} % ({0.8 * rf:g}/350)"}
    },
    "evidence": [
        "the sources' rectus femoris share of HIP FLEXION capacity (isometric F_max x sagittal moment arm, every muscle with a positive hip-flexion arm in the denominator; knee 90 deg): gait2392 (Delp 1990 lineage, model file gait2392_thelen2003muscle.osim) 19 / 26 / 29 / 31 / 30 % at hip -20 / 0 / 20 / 40 / 60 deg with iliopsoas 43 / 46 / 47 / 46 / 48 %; Rajagopal et al. 2016 (IEEE TBME 63:2068, Table II forces) 19 / 29 / 36 / 39 / 41 % with iliopsoas 32 / 29 / 28 / 30 / 34 %; Arnold et al. 2010 cadaver forces (Ann Biomed Eng 38:269, Table 1, PMC2903973) on the Rajagopal geometry 16 / 25 / 32 / 36 / 37 % with iliopsoas 33 / 31 / 31 / 33 / 37 %. A sprinter's swing runs the hip from about -20 to +60 deg flexion, so 26-41 % (about 32 % as the middle of the flexed-hip values) is the source share; 60 % is not (it is roughly the cadaver RF share among iliopsoas + RF ONLY, Kumazaki et al. 2022, 57-62 %, while v4's lumped hip flexor also holds sartorius, tensor fasciae latae, pectineus and the adductors)",
        "the sources' rectus femoris share of KNEE EXTENSION capacity, RF / (RF + vasti), hip 0 deg, knee 0-120 deg: gait2392 19-22 %, Rajagopal 2016 19-21 %, Rajagopal-Lai-Uhlrich 2023 20-22 %, Arnold 2010 forces on the Rajagopal geometry 16-17 %; by force only 15.2 % (Arnold 2010: 848.8 N against 4723 N of vasti), 18.6 % (Rajagopal), 20.5 % (gait2392); by PCSA 15.7 % (Ward et al. 2009, Clin Orthop Relat Res 467:1074, PMC2650051: rectus femoris 13.5 cm2, vasti 35.1 + 16.7 + 20.6 cm2). In the models the vasti and the rectus femoris act through the same patellar tendon with similar knee-extension moment arms (rectus femoris 4.6-5.0 cm, vasti 4.0-4.9 cm at 0-30 deg knee flexion, gait2392 / Rajagopal), so the share of capacity is close to the share of force. 34 % is above every source",
        "the compromise taken: rf 80 N, i.e. 32 % of hip flexion (sources 26-41 %) and 18.3 % of knee extension (sources 15-22 %); the two shares are tied by the fixed 1.0 : 0.8 coefficients, so one rf value cannot match a low knee share (cadaver PCSA 15 %) and Rajagopal's high hip share (38-41 %) together; 80 is inside both ranges. Alternatives priced in the split_check block: rf 66 (knee 15.1 %, hip 26.4 %), rf 88 (knee 20.1 %, hip 35.2 %)",
        "the monoarticular groups take up the difference so the joint totals stay at v4's (hip_flex_pos 100 -> 170, knee_neg 230 -> 286): the v4 file's argument that the v3 capacities are already 1.4-2.9x young men's voluntary maxima (Anderson et al. 2007; Maden-Wilkinson et al. 2020) and are not raised applies unchanged, so this changes no joint's total strength"
    ],
    "verified": "derived (shares computed from model-file forces and moment arms computed from the .osim geometry with the wrap logic of OpenSim; PCSA and cadaver forces read in the papers; only sagittal moment arms, rigid-tendon capacities; no published hip-flexion moment-arm table could be re-read to validate the hip arms, the knee arm 4-5 cm agrees with Arnold 2010)"
}

doc = {
    "name": "v5",
    "about": "Opt-in calibration of the v4 body (select with ROBOLAB_BODY=v4 ROBOLAB_CALIB=v5): v4 with ONE change, the split of the hip-flexion and knee-extension capacity between the biarticular rectus femoris and the monoarticular muscles, set from the musculoskeletal-model and cadaver literature instead of v4's round numbers (rf 150 N = 60 % of hip flexion and 34 % of knee extension). Every v4 value is unchanged (params.tendon_scale and params.omega_muscle are copied from v4.json), each joint's TOTAL peak torque is kept (hip flexion 250 N m, knee extension 350 N m), the v1-v4 bodies and playground/calibrations/v4.json are untouched (no code change: peaks is an existing calibration key). Why it exists: the rectus femoris pulls the swing knee straight whenever the hip flexes hard (about -100 N m at the knee in the first 60 ms of swing in the P95 champion), and the searched runners fold the trailing heel to only ~98 deg knee flexion (heel 0.35 m high) where sprinters fold to ~140 deg (scratchpad/heel/LOG.md; A/B and verdict in scratchpad/anat5/LOG.md). This is a DIFFERENT BODY: a result on v5 is not comparable with the v4 rows of the arena.",
    "params": params,
    "kept": {
        "everything else": "every other parameter of v4.json (tendon_scale quadriceps x4, omega_muscle hip_flex_neg 18.5 / hip_flex_pos 29 rad/s) and every default of the v4 builder (peaks of all other muscles: hip_flex_neg 120, knee_pos 40, ankle 150 / 80, ham 200, gas 180; segments, foot contact, activation, force-length, force-velocity)",
        "rf coefficients": "the rectus femoris keeps V2_BIARTICULAR's 1.0 (hip) : 0.8 (knee) coefficients (a code constant, not a calibration key)",
        "quadriceps tendon": "the group's total series stiffness (250 N/mm x4 at 4.5 cm, v4) is unchanged; the v3 builder shares it among the group's muscles in proportion to their peak torques, so the vasti's tendon gets stiffer and the rectus femoris' softer with the new peaks (p95 XML: knee_neg 1996 -> 2482, rf 1627 -> 868 N m/rad equivalent; the fibre armature and damping follow the same shares): a consequence of the builder's sharing rule, not a separate choice"
    },
    "split_check": {
        "how": "scratchpad/anat5/lit/{moment_arms.py, osim_paths.py, scenarios.py, moment_arms_*.json, shares.json, scenarios.json, tables.txt, sources.json}: muscle-tendon path lengths from the .osim path points, conditional / moving points, joint transforms and cylinder wraps, moment arm = -dL/dtheta by central differences (sagittal, pelvis fixed), capacity = F_max x arm; shares over every muscle with a positive hip-flexion arm (knee 90 deg for the hip table).",
        "rectus femoris share of hip flexion, %": {
            "hip angle, deg": [-20, 0, 20, 40, 60],
            "gait2392": [19, 26, 29, 31, 30],
            "rajagopal2016": [19, 29, 36, 39, 41],
            "arnold2010_forces_on_rajagopal_geometry": [16, 25, 32, 36, 37],
            "v4 body": 60,
            "v5 body": round(share_hip * 100, 1)
        },
        "iliopsoas share of hip flexion, %": {
            "gait2392": [43, 46, 47, 46, 48],
            "rajagopal2016": [32, 29, 28, 30, 34],
            "arnold2010_forces_on_rajagopal_geometry": [33, 31, 31, 33, 37],
            "v5 body (hip_flex_pos lumps iliopsoas + sartorius + TFL + pectineus + anterior adductors)": round((hip / HIP_TOTAL) * 100, 1)
        },
        "rectus femoris share of knee extension, RF / (RF + vasti), %": {
            "capacity, hip 0, knee 0-120 deg": {"gait2392": "19-22", "rajagopal2016": "19-21", "rajagopal_lai_uhlrich2023": "20-22", "arnold2010_forces_on_rajagopal_geometry": "16-17"},
            "force only": {"arnold2010": 15.2, "rajagopal2016": 18.6, "gait2392": 20.5},
            "pcsa_ward2009": 15.7,
            "v4 body": 34.3,
            "v5 body": round(share_knee * 100, 1)
        },
        "options priced (rf N -> hip_flex_pos, knee_neg, hip share %, knee share %)": {
            "rf 66": [66, 184, 297.2, 26.4, 15.1],
            "rf 80 (taken)": [80, 170, 286, 32.0, 18.3],
            "rf 88": [88, 162, 279.6, 35.2, 20.1],
            "the brief's draft rf 60": [60, 190, 302, 24.0, 13.7]
        },
        "draft_rejected": "the first proposal (rf 60, hip_flex_pos 190, knee_neg 302: 24 % of hip flexion, 13.7 % of knee extension) is below every source share on both joints (hip 26-41 %, knee 15-22 %); it was run only as a what-if through ROBOLAB_CALIB_SET (scratchpad/anat5/LOG.md) and is not a calibration"
    },
    "sources": {
        "read in the source (numbers taken from the text or table)": [
            "Arnold EM, Ward SR, Lieber RL, Delp SL. A model of the lower limb for analysis of human movement. Ann Biomed Eng 2010;38:269-279 (PMC2903973): Table 1 PCSA and peak force: rectus femoris 13.9 cm2 / 848.8 N, iliacus 10.2 cm2 / 621.9 N, psoas 7.9 cm2 / 479.7 N, sartorius 113.5 N, TFL 155 N, pectineus 177 N, vasti 1024.2 + 2255.4 + 1443.7 N; text: the model quadriceps knee-extension moment arm peaks at 4.7 cm at 25 deg, the literature 4-5 cm",
            "Rajagopal A, Dembia CL, DeMers MS, Delp DD, Hicks JL, Delp SL. Full-body musculoskeletal model for muscle-driven simulation of human gait. IEEE Trans Biomed Eng 2016;63:2068-2079 (PMC5507211): Table II and the model file Rajagopal2016.osim: rectus femoris 2192 N, iliacus 1021, psoas 1427, sartorius 249, TFL 411, vasti 1697 + 5149 + 2748 N (60 N/cm2 x Handsfield et al. 2014 volume fractions)",
            "Ward SR, Eng CM, Smallwood LH, Lieber RL. Are current measurements of lower extremity muscle architecture accurate? Clin Orthop Relat Res 2009;467:1074-1082 (PMC2650051): PCSA psoas 7.7, iliacus 9.9, rectus femoris 13.5, sartorius 1.9, vastus lateralis / intermedius / medialis 35.1 / 16.7 / 20.6 cm2; hip flexors (psoas, iliacus, RF, sartorius) 35.9 +- 9.0 cm2, knee extensors 88.4 +- 30.5 cm2",
            "Kumazaki T, et al. Action and contribution of the iliopsoas and rectus femoris as hip flexor agonists examined with anatomical analysis. Juntendo Iji Zasshi 2022;68:352-362 (PMC11250012): 22 cadaver limbs, PCSA psoas 5.45, iliacus 6.91, RF 10.88 cm2; RF share of (psoas + iliacus + RF) torque indicator 57.3 % at 0 deg, 60-62 % at 20-40 deg; only three muscles counted",
            "Jiroumaru T, et al. SpringerPlus 2014;3:624 (PMC4221557): isometric hip-flexion torque of 10 young men 159.7 N m at 0 deg (knee 90), 70 % at 30 deg, 50 % at 60 deg; the iliopsoas contribution is relatively larger in the flexed hip (qualitative)"
        ],
        "read (model file) and computed (moment arms)": [
            "gait2392_thelen2003muscle.osim (OpenSim; Delp SL, Loan JP, Hoy MG, Zajac FE, Topp EL, Rosen JM. An interactive graphics-based model of the lower extremity to study orthopaedic surgical procedures. IEEE Trans Biomed Eng 1990;37:757-767 lineage; Thelen, Seth, Anderson, Delp): iliacus 1073 N, psoas 1113, rectus femoris 1169, sartorius 156, TFL 233, pectineus 266, vasti 1294 + 1365 + 1871 N",
            "Rajagopal2016.osim, RajagopalLaiUhlrich2023.osim (github.com/opensim-org/opensim-models)"
        ],
        "not accessible (nothing quoted from them)": "Delp 1990 and Arnold et al. 2000 (Comput Aided Surg 5:108) full texts, Nemeth & Ohlsen 1985, Visser et al. 1990, Spoor & van Leeuwen 1992, Herzog & Read 1993 (scanned), Handsfield et al. 2014 (paywalled): no hip-flexion moment-arm table could be re-read to validate the computed arms",
        "file_layer": "scratchpad/anat5/lit/sources.json lists each source with its status"
    },
    "not_applied": {
        "posture-dependent rf knee coupling": "the moment-arm ratio RF knee / RF hip is 0.36-0.54 in all three models at hip 40-60 deg and knee 90-120 deg (the fold-back posture) and 1.2-1.4 at hip 0, knee 30 deg (stance); V2_BIARTICULAR's fixed 0.8 therefore overstates the rectus femoris's knee-extension pull in the swing by ~1.5-2x. A fixed MuJoCo tendon cannot vary with posture; a lower constant coefficient would understate the stance; a code change, not a calibration key, so not part of v5",
        "sartorius / gracilis (hip flexion + knee flexion)": "no biarticular hip-flexor-knee-flexor exists in the v2-v4 anatomy (sartorius 113-249 N, gracilis 162-281 N in the models: small); an optional v5.1 (needs a body.py change), not part of v5"
    }
}
os.makedirs(os.path.dirname(a.out), exist_ok=True)
tmp = a.out + ".tmp"
with open(tmp, "w") as f:
    json.dump(doc, f, indent=1)
    f.write("\n")
os.replace(tmp, a.out)
print("wrote", a.out, "peaks", peaks, f"hip share {share_hip * 100:.1f} %, knee share {share_knee * 100:.1f} %")
