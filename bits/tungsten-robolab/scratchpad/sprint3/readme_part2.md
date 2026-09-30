
**Result: no fall-free runner, and not 10 m/s.** The best chain (`params/run_gearx_v4_sprinter_g5a.txt`, promoted in `sprint_top_speed_v4_sprinter`) reaches **8.407 m/s (survivors' mean
peak_speed_1s, 68 % of the 12.36 ceiling)** and survives **8 of the 12 arena starts**; on 80 unseen standing starts it falls 19 times. 10 m/s is 1.6 m/s away and 81 % of the ceiling.
Round 2's P95 champion, replayed on this body, falls on all 12 starts.

**Porting the runner** (each row is a run in `scratchpad/sprint3/LOG.md`; standing starts 30 s, flying starts 24 s from the champion's own steady-running snapshots on THIS body,
`sprj` = 17 training snapshots at 7.5-8.2 m/s, `sprk` = 36 unseen ones at 7.4-8.3):

| stage | flying, 17 training | flying, 36 unseen | standing, 12 arena starts | unseen standing (40 + 40) |
| --- | --- | --- | --- | --- |
| P95 five-gear champion replayed (`x5a`) | | | **0/12** (falls 12.0-16.3 s on ten, 3.5 and 3.8 s on 226 and 230); peaks before the falls 7.6-8.65 | |
| P95 four-gear champion replayed | | | **0/12** (13.0-16.5 s; 226, 230 at 3.5, 3.8 s); peaks before the falls 7.6-8.54 | |
| gear 5 = gear 4's values (control) | 0/17 survive (0.4-5.2 s, after 8.3-8.5 m/s) | | | |
| `x5a`'s extended gear 5 | 0/17 (0.7-6.3 s) | | | |
| V1: gear 5 = gear 4's values, **lean 0.10** (from 0.23) | 8/17 survive, steady 8.35-8.48 | 12/36 survive, peak 8.562 | 6/12, peaks 8.484-8.589 (mean 8.535) | |
| **g5a**: V1 + one generation of gear-5 ES (entered) | 15/17, steady 8.24-8.50, peak 8.428 | | **8/12, mean peak 8.407** | 30/40 (8.385) + 31/40 (8.423) |
| g5a5: the same ES, generation 5 | | 19/36 survive, peak 8.509 | 7/12, mean peak 8.532 | |

- *What breaks on the stronger body is the trunk.* The P95 chain accelerates FASTER here (6.2 m/s at 7.8 s, 8.26 at 12.4 s), then the trunk pitches forward stance after stance (touchdown pitch
  0.13 -> 0.21 -> 0.42 -> 0.54 -> 0.77 rad, peak force 4.2 -> 6.3 BW) and it falls at 15.8 s: the round-2 trunk runaway, reached at ~8.3 m/s. The crouched control rocks the trunk +0.10-0.20
  rad per stance (P95: +0.016). Working reading: the stance hip extensors deliver ~1.5x P95's torque at the same command (strength x1.17, and in the fast retraction the force-velocity factor
  x1.2-1.3 from the x1.21 speed) and the stance-hip trunk servo does not hold it.
- *One lever moves it: the forward-lean set point.* One-at-a-time probes on the control (8-12 flying seeds, 12-14 s): every drive (hamstring, knee, hip, gastrocnemius, ankle) x0.6-0.8, the
  servo gain `torso_kp` 0.4 / 1.5 and `leg_kp` 8 leave 8/8 falling at 3-4.6 s; **`lean` 0.23 -> 0.10: 4/12 fall, steady 8.40** (0.05: 2/12, steady 8.21; 0.0: 6/12; 0.3: 8/8). A lower speed plan
  (`v_top` 8.2 / 8.5) does not prevent the falls (6/6 fall at 11-18 s). Lowering the lean in gears 2-4 as well (V2) is worse (7/12 fall). The extended gear does not survive on this body with any
  lean tried (0.1, 0.0, -0.08: 12/12 fall in 2.4-3.2 s): the crouched family is the base here, the reverse of P95.
- *The gear-5 search* (`hsearch.py --agg mean`, (1+16)-ES on the 78 `g5_*` tunables, 10 training flying starts x 16 s, objective 3, fall penalty 300, `scratchpad/sprint3/es3.sh`, 4 workers)
  was stopped by the machine load and two harness stalls after 8 generations (436 rollouts, against 3900 + 2300 for round 2's gear 5). Its first generation already found a survivor of all 10 seeds
  (15/17 on the training snapshots); the fifth generation's incumbent flies faster (8.53) and falls as often. Its late falls (10 of the 17 on unseen flying starts come at 17-24 s) are
  beyond its 16 s horizon, as in round 2. A start-phase search (`st.sh`, the 12 gear-1 start tunables, standing starts) reached generation 3 and was not usable.
- *What is left are gears 1-4, which nobody re-searched.* Seed 221 falls at 13.048 s in EVERY variant (steady 7.29 m/s, gear 5 never entered): a gear 1-4 event. The start plan tuned on P95 is a
  hazard of ~12 % here (5 of 40 unseen 8 s starts fall at 3.3-4.0 s; `accel` 2.0 makes it 3/40; k0, drv0_* and psi0 change it by chance). Switching to gear 5 earlier rescues 221 and 229 and
  drops two others.
