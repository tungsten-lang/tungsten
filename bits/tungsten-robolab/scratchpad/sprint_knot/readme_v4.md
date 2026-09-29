### Round 3: body fidelity and the calibrated v4 body

The pitch-free ceilings above put the average body below untrained men. Round 3
asks why. It sets human targets from sources, uses the ideal-control analysis
as a probe with one model factor changed at a time, and builds a calibrated
body, **v4**. v4 is opt-in, and every change in it rests on a citation.

**Human targets.** Every number below was read in the source (verified),
calculated from verified numbers (derived), or read off a plotted figure
(fig-read). The full list is in `playground/calibrations/v4.json`
(`human_targets`).

| population | top speed | contact / aerial | step | mean / peak vertical force | status |
| --- | --- | --- | --- | --- | --- |
| untrained young men | ~7.8 m/s (7.3-8.3); Lazarczuk et al. 2025: 7.77 +- 0.86; Clark, Meng & Stearne 2020: 8.23 +- 0.41 | 0.130 / 0.109 s (Clark 2020); 0.120 / 0.124 at 8 m/s (Weyand et al. 2000 regressions) | 1.96 m at 4.21 /s (Clark 2020); 2.00 m at 3.96 /s (Weyand 2000) | 2.07 BW at 8 m/s (Weyand 2000) / ~3.2 BW (Clark & Weyand 2014 Fig. 7A, athlete non-sprinters) | verified; derived; peak fig-read and weakly sourced |
| untrained, 95th percentile | ~8.8-9.2 m/s (mean + 1.645 SD, SD 0.4-0.9) | contact ~0.105-0.112 s | ~2.0-2.1 m at 4.4-4.6 /s | ~2.0-2.1 BW mean | derived |
| trained sprinters, 1.75 m / 66.6 kg | 9.90 +- 0.46 m/s (Miyashiro et al. 2019, 79 sprinters) | 0.103 / 0.113 s | 2.15 m at 4.60 /s | 2.30 / 3.93 +- 0.51 BW (Weyand et al. 2009, at 10.8 m/s) | verified |
| elite sprinters | 11.5-12.3 m/s (Bolt 12.26; 2009 finalists 11.80 +- 0.23; ~11.6-11.8 at 1.75 m) | 0.084-0.104 / 0.104-0.136 s | 2.26-2.70 m at 4.4-5.0 /s | 2.3-2.45 / ~3.8-4.5 BW | verified (Krzysztof & Mero 2013; Bissas et al. 2018 World Athletics report); forces fig-read / derived |

**The probe.** The probe is `sprint_limits.py speeds --pitch-free`, chained
upward from 5 m/s. It reports two ceilings:

- **Margin:** the fastest speed at which the swing-time margin
  tc + 2 taer - t_sw stays positive.
- **Stance budget:** the speed at which the best penalised stance budget
  tc + 2 taer falls to a human swing time of 0.35 s (Weyand 2000: 0.373 +- 0.03;
  sprinters 0.33-0.36). This one needs no swing optimisation and is steadier.

Parameter changes come from `ROBOLAB_CALIB_SET` on a v4 body with an empty
calibration, which is v3 exactly (`scratchpad/sprint_knot/probe_batch.sh`,
`budget_ceiling.py`). Each screen row is one chain with one optimisation per
speed, so it carries about +-0.5-0.7 m/s: v4 itself measures 7.46 on one chain
and 8.2 on two. Only the strength and force-length rows stand clear of that
noise.

| factor (average body) | stance-budget ceiling, m/s (v3: 6.89) | what the literature says | in v4 |
| --- | --- | --- | --- |
| plantarflexor strength x1.5 | **9.10 (+2.2)** | the model's isometric capacities are already 1.4-2.9x young men's voluntary maxima (Anderson et al. 2007; Maden-Wilkinson et al. 2020; Krantz et al. 2020), as is usual in models | kept |
| vasti strength x1.5 | **8.91 (+2.0)** | as above | kept |
| force-length width 0.85-1.15 L0 (v3: 0.75-1.05, 0.5 of isometric at the short end) | **7.72 (+0.8)** | already generous: human muscles keep 0.1-0.35 at the short end (Anderson 2007; Maganaris 2001, 2003) | kept |
| foot friction 2.0 (v3: 1.2) | 7.50 (+0.6) | no source says 1.2 is too low; noise-level | kept |
| hip joint speeds 18.5 extension / 29 flexion rad/s (v3: 15 / 15) | 7.33 (+0.4) | derived: the standard models' 10 L0/s fibre speed (Thelen 2003; gait2392; Rajagopal 2016; Arnold & Delp 2011) x Ward et al. 2009's fibre lengths / hip moment arms. At 15 the muscles have ~0 force at sprinters' measured 14.8 rad/s hip extension and 13.8 rad/s thigh lift (Miyashiro 2019) | **applied (derived)** |
| hip extensor strength x1.5 | 7.32 (+0.4) | already above voluntary maxima | kept |
| Achilles stiffness x2 | 7.33 (+0.4) | 200 N/mm matches 188 +- 43 in hopping (Lichtwark & Wilson 2005); 306-319 (Rosager et al. 2002) | kept |
| quadriceps series stiffness x4 (250 -> 1000 N/mm) | 7.11 (+0.2; -0.1 in the first screen) | the OpenSim models' whole vasti series is ~976 N/mm (gait2392) / ~927 N/mm (Rajagopal 2016); the free patellar tendon is 1076-4334 N/mm (O'Brien et al. 2010; Hansen et al. 2006; and others) | **applied (verified)** |
| eccentric force plateau fvmax 1.6 (v3: 1.2) | 7.10 (+0.2; +0.9 in the first screen, +1.0 on the margin probe) | models use 1.4 (Millard et al. 2013; Rajagopal 2016) to 1.8 (De Groote et al. 2016; Thelen). This is modelling convention, and there is no in-vivo whole-muscle measurement | **not applied (uncertain)** |
| foot contact solref 0.01 s (v3: MuJoCo's 0.02) | 5.68 (-1.2; -0.2 in the first screen, -0.6 on the margin probe) | heel-pad and track stiffness suggest 0.005-0.01 s (Aerts et al. 1995; Kerdok et al. 2002), but this is checked only against peak forces, not measured | **not applied (uncertain)** |
| activation / deactivation x0.5 (v3: 10 / 40 ms) | 6.26 (-0.6) | 10 / 40 ms is the OpenSim default (Millard 2013); sprint simulations use 10 / 30 ms (Chumanov et al. 2011) | kept |
| hip flexor strength x1.5; leg mass x0.85 | the chains broke at 5.0-5.5 m/s (unreliable) | Dempster / Winter / de Leva masses match | kept |

**What caps the ceiling** is the vertical impulse that a short stance can
deliver. The knee and ankle extensors' force moves the ceiling most, then the
force-length width. The literature says the model is already generous in both,
so neither is raised to buy speed. Two v3 values are below the evidence: the
hip speeds (a 15 rad/s cap on a joint that sprinters move at 14.8 rad/s) and
the quadriceps series stiffness (a quarter of the models' value). **v4
changes exactly those two**, and nothing else.

**v4 build.** v4 is `HumanoidV4Builder` in `playground/body.py`, with its
calibration in `playground/calibrations/v4.json`:

- **What the JSON records:** each parameter's v3 and v4 values, its sources and
  its verification status. It also lists the parameters kept at v3 and why,
  the uncertain changes not applied with their measured effect, and the
  superseded first draft.
- **How to select it:** `ROBOLAB_CALIB` names a calibration file, and
  `ROBOLAB_CALIB_SET` overrides values for probes. `sprint_limits.py` builds v4
  under `ROBOLAB_BODY=v4`, and the tasks are `run_v4` and `sprint_touch_v4`.
- **Byte-identity:** the v2 and v3 XML are unchanged for the default, p95,
  elite and elite2 bodies, and an empty calibration reproduces v3's XML exactly.
- **v4a (superseded):** the first draft took the high-speed models' 15 L0/s
  (hip 30 rad/s both ways) and a recoil-assisted ankle speed (27). It was
  replaced before any sprinter was tuned on it; its ceilings were 8.35 / 10.95 /
  9.39 m/s.

**Validation** (ideal control, pitch free, the better of two chains per body):

| body | ceiling v3 | ceiling v4 | human | v4 at speed: contact / aerial / step / rate / mean F / peak F | human at that speed |
| --- | --- | --- | --- | --- | --- |
| average | 6.89 | **8.2** (7.9-8.6 for t_sw 0.37-0.33; margin chains 8.5, 6.5) | 7.8 (7.3-8.3) | at 8.0: 0.124 s / 0.146 s / 2.16 m / 3.71 /s / 2.18 / 4.81 BW | 0.120-0.130 / 0.109-0.124 / 1.96-2.00 / 3.96-4.21 / 2.07 / ~3.2 |
| P95 | 9.69 | **10.45** (margins 10.0, 10.5) | untrained P95 8.8-9.2; trained sprinters 9.90 +- 0.46 | at 10.0: 0.100 / 0.161 / 2.61 / 3.83 / 2.61 / 5.06 | sprinters at 9.9: 0.103 / 0.113 / 2.15 / 4.60 |
| elite2 | 8.5 | **9.28** (margins 8.0, 8.5) | elite 11.5-12.3 | at 9.0: 0.112 / 0.169 / 2.53 / 3.56 / 2.51 / 4.79 | - |

- **Average body:** its ceiling and its contact time land in the untrained
  range. Its ideal-control gait flies ~25 % longer than humans do. It steps
  ~10 % longer at a ~10 % lower rate, with ~6 % more mean and ~40 % more peak
  vertical force. The optimiser uses the 5 BW cap that the analysis allows,
  and the peak human forces are the least certain targets.
- **P95:** above the untrained 95th percentile and near trained sprinters.
  The profile is a composite, with every part at its own 95th percentile at
  once.
- **elite2:** far below elite sprinters, and below P95. The literature keeps
  elite knee and ankle extensor strength per kg near the untrained mean, and
  those extensors are what the ceiling is most sensitive to. Whatever else
  makes elites fast is not in the model. Stance technique and tendon
  properties beyond the Achilles are candidates.

SPRINTERS_PLACEHOLDER
