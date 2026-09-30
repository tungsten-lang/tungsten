# Round 11 (agent Z): per-start tables

Written by `scratchpad/hazard/make_results.py`; entries: **brake** = `params/myo_soccer_single_leg_310_shc.txt` (`bin/challengers/soccer6-p`), **H2b** = `params/hazard/myo_soccer_310_shc_h2b.txt` (`bin/challengers/soccer7-bh1`: the brake + `bhold 1`, `bh_dknee -0.2`).

## OFFICIAL `soccer_single_leg_310_40` (unmodified `myo_soccer`, unguarded, 310 s, seeds 89100-89139): H2b

**40 / 40** hold 300 s (`bal1_300-soccer7-bh1-20260929-224305.json`); per seed `bal1_raw` (longest one-leg stretch, s) and `stand_time`:

| seeds | bal1_raw / stand_time |
| --- | --- |
| 89100 89101 89102 89103 89104 | 308.01 / 310.01; 308.57 / 310.01; 308.57 / 310.01; 308.24 / 310.01; 308.28 / 310.01 |
| 89105 89106 89107 89108 89109 | 308.54 / 310.01; 308.42 / 310.01; 308.38 / 310.01; 307.88 / 310.01; 308.50 / 310.01 |
| 89110 89111 89112 89113 89114 | 308.40 / 310.01; 308.33 / 310.01; 308.08 / 310.01; 308.08 / 310.01; 308.34 / 310.01 |
| 89115 89116 89117 89118 89119 | 308.18 / 310.01; 308.51 / 310.01; 308.25 / 310.01; 308.66 / 310.01; 308.58 / 310.01 |
| 89120 89121 89122 89123 89124 | 308.31 / 310.01; 308.52 / 310.01; 308.48 / 310.01; 308.52 / 310.01; 307.97 / 310.01 |
| 89125 89126 89127 89128 89129 | 308.22 / 310.01; 308.57 / 310.01; 308.47 / 310.01; 308.42 / 310.01; 308.44 / 310.01 |
| 89130 89131 89132 89133 89134 | 308.12 / 310.01; 308.07 / 310.01; 308.54 / 310.01; 308.53 / 310.01; 308.56 / 310.01 |
| 89135 89136 89137 89138 89139 | 308.06 / 310.01; 308.25 / 310.01; 308.51 / 310.01; 308.50 / 310.01; 308.46 / 310.01 |

## Practice screen: 20 s, starts 97100-97159, guarded task in count-only mode

| arm | starts | stand 20 s | falls (seed @ s) | recfem_r within 1e-4 / 1e-3 / 1e-2 of its tangent (substeps) | margin (late median) |
| --- | --- | --- | --- | --- | --- |
| B0 | 60 | 59 | 97136 @ 3.6 | 0.87 / 11.10 / 65.29 % | -0.006 |
| K17 | 60 | 59 | 97136 @ 3.6 | 0.00 / 0.00 / 0.00 % | -0.213 |
| H1 | 30 | 30 | - | 0.00 / 0.00 / 0.00 % | -0.213 |
| K16 | 60 | 59 | 97136 @ 3.8 | 0.00 / 0.00 / 0.00 % | -0.384 |
| K19 | 41 | 39 | 97131 @ 4.3; 97136 @ 3.5 | 0.00 / 0.00 / 0.07 % | +0.188 |
| H2b | 60 | 59 | 97136 @ 3.6 | 0.00 / 0.00 / 0.00 % | -0.384 |

## Fresh 20 s check, seeds 97400-97519 (H2b): hold20 = 1 in **120 / 120** starts; NaN events 0

## Fresh 20 s check, seeds 97400-97519 (B0): hold20 = 1 in **120 / 120** starts; NaN events 0

## Fresh 310 s scan (H2b, seeds 97700-97819, count-only guarded task = the official behaviour): 37 / 37 hold 300 s so far; NaN events 0

| seed | bal1_raw | stand_time | NaN events | recfem_r substeps < 1e-3 | other segments' worst dwell (fraction of steps < 1e-3) |
| --- | --- | --- | --- | --- | --- |
| 97700 | 308.50 | 310.01 | 0 | 0 | 0.0154 (LTpL_L1_l_tendon@back_cylinder_s) |
| 97701 | 308.36 | 310.01 | 0 | 0 | 0.0004 (semimem_l_tendon@SM_at_condyles_l_wrap) |
| 97702 | 308.46 | 310.01 | 0 | 0 | 0.0004 (semimem_l_tendon@SM_at_condyles_l_wrap) |
| 97703 | 308.29 | 310.01 | 0 | 0 | 0.0001 (semimem_r_tendon@SM_at_condyles_r_wrap) |
| 97704 | 308.60 | 310.01 | 0 | 0 | 0.0002 (semimem_l_tendon@SM_at_condyles_l_wrap) |
| 97705 | 308.58 | 310.01 | 0 | 0 | 0.0001 (semimem_r_tendon@SM_at_condyles_r_wrap) |
| 97706 | 308.45 | 310.01 | 0 | 0 | 0.0004 (semimem_l_tendon@SM_at_condyles_l_wrap) |
| 97707 | 308.48 | 310.01 | 0 | 0 | 0.0141 (LTpL_L1_l_tendon@back_cylinder_s) |
| 97708 | 308.27 | 310.01 | 0 | 0 | 0.0566 (IL_L1_l_tendon@back_cylinder_s) |
| 97709 | 308.23 | 310.01 | 0 | 0 | 0.0001 (semiten_l_tendon@ST_at_condyles_l_wrap) |
| 97710 | 308.02 | 310.01 | 0 | 0 | 0.0001 (semimem_r_tendon@SM_at_condyles_r_wrap) |
| 97711 | 308.51 | 310.01 | 0 | 0 | 0.0000 (semimem_r_tendon@SM_at_condyles_r_wrap) |
| 97712 | 308.46 | 310.01 | 0 | 0 | 0.0309 (IL_L1_l_tendon@back_cylinder_s) |
| 97713 | 308.47 | 310.01 | 0 | 0 | 0.0002 (semimem_l_tendon@SM_at_condyles_l_wrap) |
| 97714 | 308.49 | 310.01 | 0 | 0 | 0.0001 (semimem_r_tendon@SM_at_condyles_r_wrap) |
| 97715 | 307.99 | 310.01 | 0 | 0 | 0.0001 (semimem_r_tendon@SM_at_condyles_r_wrap) |
| 97716 | 308.48 | 310.01 | 0 | 0 | 0.0002 (semimem_l_tendon@SM_at_condyles_l_wrap) |
| 97717 | 308.62 | 310.01 | 0 | 0 | 0.0001 (semimem_l_tendon@SM_at_condyles_l_wrap) |
| 97718 | 308.56 | 310.01 | 0 | 0 | 0.0008 (semimem_l_tendon@SM_at_condyles_l_wrap) |
| 97719 | 308.51 | 310.01 | 0 | 0 | 0.0004 (semimem_l_tendon@SM_at_condyles_l_wrap) |
| 97720 | 308.42 | 310.01 | 0 | 0 | 0.0005 (semimem_l_tendon@SM_at_condyles_l_wrap) |
| 97721 | 308.58 | 310.01 | 0 | 0 | 0.0137 (LTpL_L1_r_tendon@back_cylinder_s) |
| 97722 | 308.17 | 310.01 | 0 | 0 | 0.0000 (vasmed_r_tendon@KnExt_at_fem_r_wrap) |
| 97723 | 308.48 | 310.01 | 0 | 0 | 0.0003 (semimem_l_tendon@SM_at_condyles_l_wrap) |
| 97724 | 307.77 | 310.01 | 0 | 0 | 0.0002 (semimem_l_tendon@SM_at_condyles_l_wrap) |
| 97725 | 308.55 | 310.01 | 0 | 0 | 0.0001 (semimem_r_tendon@SM_at_condyles_r_wrap) |
| 97726 | 308.55 | 310.01 | 0 | 0 | 0.0001 (semimem_r_tendon@SM_at_condyles_r_wrap) |
| 97727 | 308.35 | 310.01 | 0 | 0 | 0.0003 (semimem_l_tendon@SM_at_condyles_l_wrap) |
| 97728 | 308.29 | 310.01 | 0 | 0 | 0.0168 (LTpL_L1_r_tendon@back_cylinder_s) |
| 97729 | 308.45 | 310.01 | 0 | 0 | 0.0153 (IL_L1_l_tendon@back_cylinder_s) |
| 97730 | 308.41 | 310.01 | 0 | 0 | 0.0004 (semimem_l_tendon@SM_at_condyles_l_wrap) |
| 97731 | 308.33 | 310.01 | 0 | 0 | 0.0465 (IL_L1_l_tendon@back_cylinder_s) |
| 97732 | 308.26 | 310.01 | 0 | 0 | 0.0001 (semimem_r_tendon@SM_at_condyles_r_wrap) |
| 97733 | 308.58 | 310.01 | 0 | 0 | 0.0002 (semimem_l_tendon@SM_at_condyles_l_wrap) |
| 97734 | 308.35 | 310.01 | 0 | 0 | 0.0000 (grac_r_tendon@GR_at_condyles_r_wrap) |
| 97735 | 307.80 | 310.01 | 0 | 0 | 0.0002 (semimem_r_tendon@SM_at_condyles_r_wrap) |
| 97736 | 308.47 | 310.01 | 0 | 0 | 0.0174 (IL_L1_l_tendon@back_cylinder_s) |

