# Nanguard trials: per-start results

Written by `scratchpad/blowup/make_tables.py` from the arena rows in `scratchpad/blowup/evals/`. Entries: **lift** = round-5 lift (`bin/challengers/soccer5-lift`, `params/myo_soccer_single_leg_310_lift.txt`), **ramp** = round-6 set ramp (`soccer6-i`, `..._ramp.txt`), **brake** = ramp + shift capture-point brake (`soccer6-p`, `..._shc.txt`).

## soccer_single_leg_310_40_ng: 40 starts (seeds 89100-89139), 310 s, bal1_300 (1 = the longest one-leg stretch reaches 300 s)

| entry | official (unguarded) | guarded | NaN events (guarded re-runs) |
| --- | --- | --- | --- |
| lift | 34 / 40 | 35 / 40 | 2 |
| ramp | 38 / 40 | 39 / 40 | 2 |
| brake | 35 / 40 | 40 / 40 | 6 |

Starts where any entry differs between the official and the guarded run, or fails (seed: official -> guarded; `fall` = seconds standing before the fall; `nan` = events, first at t, tendon):

| seed | lift | ramp | brake |
| --- | --- | --- | --- |
| 89103 | pass -> pass | pass -> pass | FAIL (fall 255.75) -> pass; nan 1 @ 255.55 recfem_r_tendon |
| 89106 | FAIL (fall 222.41) -> pass; nan 2 @ 222.068 recfem_r_tendon | pass -> pass | pass -> pass |
| 89110 | FAIL (fall 6.68) -> FAIL (fall 6.68) | pass -> pass | pass -> pass |
| 89115 | FAIL (fall 6.85) -> FAIL (fall 6.85) | pass -> pass | pass -> pass |
| 89117 | FAIL (fall 2.56) -> FAIL (fall 2.56) | pass -> pass | pass -> pass |
| 89122 | pass -> pass | FAIL (fall 16.15) -> pass; nan 2 @ 15.811 recfem_r_tendon | FAIL (fall 16.15) -> pass; nan 2 @ 15.811 recfem_r_tendon |
| 89130 | FAIL (fall 1.46) -> FAIL (fall 1.46) | pass -> pass | FAIL (fall 141.24) -> pass; nan 1 @ 141.04 recfem_r_tendon |
| 89133 | FAIL (fall 3.19) -> FAIL (fall 3.19) | FAIL (fall 2.87) -> FAIL (fall 2.87) | pass -> pass |
| 89134 | pass -> pass | pass -> pass | FAIL (fall 134.57) -> pass; nan 1 @ 134.214 recfem_r_tendon |
| 89135 | pass -> pass | pass -> pass | FAIL (fall 130.55) -> pass; nan 1 @ 130.209 recfem_r_tendon |

## soccer_hold20_120_ng: 120 fresh starts (seeds 96000-96119), 20 s, hold20 (1 = standing since the start and on one leg for the last 15 s)

| entry | hold20 | falls | NaN events (nudged) | mean bal1_raw of the passes |
| --- | --- | --- | --- | --- |
| lift | 102 / 120 | 18 | 1 | 17.89 |
| ramp | 113 / 120 | 7 | 0 | 18.36 |
| brake | 118 / 120 | 2 | 1 | 18.36 |

- ramp vs lift: mean paired diff +0.0917, p = 0.0063; fixed 14, broke 3 (broke [96011, 96059, 96103])
- brake vs lift: mean paired diff +0.1333, p = 0.0000; fixed 16, broke 0
- brake vs ramp: mean paired diff +0.0417, p = 0.0668; fixed 6, broke 1 (broke [96023])

Per start (`ok` = hold20; a fall shows the seconds standing before it; `nan` = guard events):

| seed | lift | ramp | brake |
| --- | --- | --- | --- |
| 96000 | ok (17.7) | ok (18.6) | ok (18.6) |
| 96001 | ok (18.5) | ok (18.7) | ok (18.7) |
| 96002 | ok (17.5) | ok (18.5) | ok (18.5) |
| 96003 | ok (18.0) | ok (18.6) | ok (18.6) |
| 96004 | ok (18.0) | ok (18.4) | ok (18.5) |
| 96005 | ok (17.8) | ok (18.5) | ok (18.5) |
| 96006 | ok (18.2) | ok (18.5) | ok (18.5) |
| 96007 | ok (17.9) | ok (18.6) | ok (18.6) |
| 96008 | ok (18.4) | ok (18.6) | ok (18.6) |
| 96009 | ok (17.7) | ok (18.0) | ok (18.0) |
| 96010 | ok (17.9) | ok (18.0) | ok (18.1) |
| 96011 | ok (18.4) | FAIL (fall at 5.0 s standing) | ok (18.2) |
| 96012 | ok (18.1) | ok (18.4) | ok (18.5) |
| 96013 | ok (18.2) | ok (18.6) | ok (18.6) |
| 96014 | ok (17.4) | ok (18.1) | ok (18.1) |
| 96015 | ok (17.5) | ok (18.5) | ok (18.5) |
| 96016 | ok (17.9) | ok (18.6) | ok (18.6) |
| 96017 | ok (18.3) | ok (18.2) | ok (18.3) |
| 96018 | ok (17.0) | ok (18.2) | ok (18.2) |
| 96019 | ok (18.5) | ok (18.3) | ok (18.4) |
| 96020 | ok (17.7) | ok (18.4) | ok (18.4) |
| 96021 | ok (17.6) | ok (18.4) | ok (18.4) |
| 96022 | ok (17.8) | ok (18.3) | ok (18.3) |
| 96023 | FAIL (fall at 2.88 s standing) | ok (18.1) | FAIL (fall at 11.13 s standing) |
| 96024 | ok (17.8) | ok (18.4) | ok (18.4) |
| 96025 | ok (17.3) | ok (18.2) | ok (18.1) |
| 96026 | ok (17.7) | ok (18.6) | ok (18.5) |
| 96027 | ok (18.0) | ok (18.6) | ok (18.6) |
| 96028 | ok (18.0) | ok (18.1) | ok (18.1) |
| 96029 | ok (18.2) nan 1 @ 2.12 IL_L1_r_tendon | ok (18.4) | ok (18.4) |
| 96030 | ok (17.8) | ok (18.4) | ok (18.5) |
| 96031 | ok (17.7) | ok (18.0) | ok (18.0) |
| 96032 | ok (18.2) | ok (18.4) | ok (18.4) |
| 96033 | FAIL (fall at 3.48 s standing) | ok (18.5) | ok (18.6) |
| 96034 | ok (17.9) | ok (17.9) | ok (18.0) |
| 96035 | ok (18.2) | ok (18.4) | ok (18.4) |
| 96036 | ok (17.9) | ok (18.3) | ok (18.3) |
| 96037 | ok (17.5) | ok (18.3) | ok (18.4) |
| 96038 | ok (17.9) | ok (18.4) | ok (18.4) |
| 96039 | FAIL (fall at 2.96 s standing) | ok (18.6) | ok (18.6) |
| 96040 | ok (17.8) | ok (18.4) | ok (18.5) |
| 96041 | ok (17.8) | ok (18.0) | ok (18.0) |
| 96042 | ok (17.7) | ok (18.4) | ok (18.4) |
| 96043 | FAIL (fall at 3.17 s standing) | ok (18.5) | ok (18.5) |
| 96044 | ok (18.0) | ok (18.0) | ok (17.9) |
| 96045 | FAIL (fall at 2.12 s standing) | ok (18.4) | ok (18.4) |
| 96046 | ok (17.9) | ok (18.1) | ok (18.1) |
| 96047 | ok (17.6) | ok (18.1) | ok (18.1) |
| 96048 | ok (18.2) | ok (18.6) | ok (18.6) |
| 96049 | ok (17.9) | ok (18.2) | ok (18.2) |
| 96050 | ok (18.3) | ok (18.5) | ok (18.5) |
| 96051 | ok (18.1) | ok (18.6) | ok (18.6) |
| 96052 | FAIL (fall at 1.33 s standing) | ok (18.6) | ok (18.5) |
| 96053 | ok (18.0) | ok (18.5) | ok (18.5) |
| 96054 | ok (17.5) | ok (18.4) | ok (18.4) |
| 96055 | FAIL (fall at 2.53 s standing) | FAIL (fall at 7.74 s standing) | ok (18.2) |
| 96056 | ok (18.2) | ok (18.4) | ok (18.4) |
| 96057 | ok (18.2) | ok (18.6) | ok (18.6) |
| 96058 | ok (17.9) | ok (18.5) | ok (18.4) |
| 96059 | ok (18.2) | FAIL (fall at 4.96 s standing) | ok (17.9) |
| 96060 | ok (18.1) | ok (18.6) | ok (18.6) |
| 96061 | ok (17.8) | ok (18.3) | ok (18.4) |
| 96062 | ok (17.7) | ok (17.9) | ok (17.9) |
| 96063 | ok (17.8) | ok (18.5) | ok (18.5) |
| 96064 | FAIL (fall at 3.19 s standing) | ok (18.5) | ok (18.5) |
| 96065 | ok (16.8) | ok (18.1) | ok (18.1) |
| 96066 | ok (17.5) | ok (18.3) | ok (18.3) |
| 96067 | FAIL (fall at 4.03 s standing) | ok (18.5) | ok (18.6) |
| 96068 | ok (18.3) | ok (18.6) | ok (18.6) |
| 96069 | ok (17.8) | ok (18.3) | ok (18.3) |
| 96070 | FAIL (fall at 3.56 s standing) | ok (17.9) | ok (17.9) |
| 96071 | ok (17.2) | ok (18.5) | ok (18.5) |
| 96072 | ok (17.8) | ok (18.3) | ok (18.2) |
| 96073 | ok (17.9) | ok (18.4) | ok (18.4) |
| 96074 | ok (17.6) | ok (18.5) | ok (18.5) |
| 96075 | ok (17.9) | ok (18.1) | ok (18.1) |
| 96076 | ok (17.5) | ok (18.1) | ok (18.2) |
| 96077 | ok (18.1) | ok (18.4) | ok (18.4) |
| 96078 | ok (18.1) | ok (18.6) | ok (18.6) |
| 96079 | ok (18.0) | ok (18.5) | ok (18.5) |
| 96080 | ok (17.9) | ok (18.5) | ok (18.5) |
| 96081 | FAIL (fall at 1.52 s standing) | ok (18.4) | ok (18.4) nan 1 @ 14.336 recfem_r_tendon |
| 96082 | ok (18.2) | ok (18.4) | ok (18.4) |
| 96083 | ok (17.5) | ok (18.5) | ok (18.5) |
| 96084 | ok (18.5) | ok (18.6) | ok (18.6) |
| 96085 | ok (18.2) | ok (18.2) | ok (18.2) |
| 96086 | FAIL (fall at 4.94 s standing) | ok (18.4) | ok (18.4) |
| 96087 | ok (18.1) | ok (18.1) | ok (18.1) |
| 96088 | ok (17.3) | ok (17.8) | ok (17.8) |
| 96089 | ok (18.3) | ok (18.4) | ok (18.4) |
| 96090 | ok (18.4) | ok (18.5) | ok (18.5) |
| 96091 | ok (17.8) | ok (18.6) | ok (18.6) |
| 96092 | ok (18.3) | ok (18.5) | ok (18.6) |
| 96093 | ok (17.3) | ok (18.1) | ok (18.1) |
| 96094 | ok (18.1) | ok (18.6) | ok (18.6) |
| 96095 | FAIL (fall at 2.14 s standing) | FAIL (fall at 4.17 s standing) | ok (17.0) |
| 96096 | FAIL (fall at 2.03 s standing) | ok (18.1) | ok (18.1) |
| 96097 | ok (18.2) | ok (18.0) | ok (18.0) |
| 96098 | FAIL (fall at 3.02 s standing) | FAIL (fall at 3.58 s standing) | ok (18.2) |
| 96099 | ok (17.9) | ok (18.4) | ok (18.4) |
| 96100 | FAIL (fall at 3.9 s standing) | ok (18.3) | ok (18.3) |
| 96101 | ok (17.6) | ok (18.1) | ok (18.1) |
| 96102 | ok (17.5) | ok (18.6) | ok (18.6) |
| 96103 | ok (18.0) | FAIL (fall at 8.46 s standing) | ok (18.5) |
| 96104 | ok (18.1) | ok (18.5) | ok (18.5) |
| 96105 | FAIL (fall at 3.84 s standing) | ok (18.3) | ok (18.3) |
| 96106 | ok (17.8) | ok (18.4) | ok (18.4) |
| 96107 | ok (17.8) | ok (18.2) | ok (18.2) |
| 96108 | ok (17.8) | ok (18.5) | ok (18.5) |
| 96109 | ok (18.1) | ok (18.4) | ok (18.4) |
| 96110 | ok (18.3) | ok (17.9) | ok (18.0) |
| 96111 | ok (17.9) | ok (18.3) | ok (18.3) |
| 96112 | ok (17.6) | ok (18.5) | ok (18.5) |
| 96113 | ok (17.1) | ok (18.5) | ok (18.5) |
| 96114 | ok (18.1) | ok (18.4) | ok (18.4) |
| 96115 | ok (18.0) | ok (18.3) | ok (18.3) |
| 96116 | FAIL (fall at 1.66 s standing) | FAIL (fall at 2.4 s standing) | FAIL (fall at 2.28 s standing) |
| 96117 | ok (17.9) | ok (18.5) | ok (18.5) |
| 96118 | ok (17.8) | ok (18.4) | ok (18.4) |
| 96119 | ok (18.2) | ok (18.4) | ok (18.5) |

## Supplementary scan: the brake at 310 s (guarded) on the fresh hold20 starts, 69 of 120 finished (seeds 96000-96038 and 96060-96089)

`scratchpad/blowup/analyse_120.py`, from the rollout cache; the 120-start trial was withdrawn unseeded (see LOG.md).

```
69 of 120 starts done (the scan was stopped: 96000..96089); hold 300 s: 68 / 69
  FAIL 96023: standing 11.13 s, bal1 5.61, fell True (hold20 at 20 s: FAIL); events 0.0
late failures (hold20 ok, fail before 300 s): 0 []
NaN events 15 in 6 starts, 21092 start-seconds = 0.71 per 1000; tendons ['recfem_r_tendon']; other resets 0
recfem_r sliver states: survived 209 + NaN 15; expected NaN from the table 15.78; exact 1-dot of the events 1.4e-21 3.2e-18 4.3e-18 5.2e-18 7.0e-18 7.0e-18 1.4e-17 2.0e-17 2.1e-17 2.2e-17 2.3e-17 2.8e-17 4.6e-17 6.2e-17 9.6e-17
events by start: 96010 x4 @25.092 recfem_r_tendon; 96022 x1 @191.076 recfem_r_tendon; 96070 x1 @50.163 recfem_r_tendon; 96080 x1 @282.698 recfem_r_tendon; 96081 x7 @14.336 recfem_r_tendon; 96088 x1 @31.398 recfem_r_tendon
```
