**What did not move the number** (champion binary and params unless noted; first 120 serves of the fixed pools or `710000:710120`; solved of 120 against the champion's on the same serves):

| variant | solved | what it showed |
| --- | --- | --- |
| pelvis speed governor `pv 2` (the slide reaches its goal at contact retreating at `0.47 (v - 4.83)` m/s) | 31 vs 34 | forehand pelvis velocity at contact right on average (0.41 +- 0.47 for a planned 0.40) with a larger spread; the parent's dispatch dropped the backhand's plan |
| `pv 2` on both sides (dispatch fixed, the slide coasts the last 20 ms) | 21 vs 34 | the pelvis now follows its plan (0.08 +- 0.23 forehand, 0.02 +- 0.15 backhand) but the arm adds +0.2 / +0.5 m/s: pad velocity 0.60 / 0.95 for a planned 0.44, returns too slow (exit 4.6 against 5.6 m/s, 41 net hits against 16), hit rate 0.73 against 0.80 |
| `pv 3` (predictive, arm velocity carried to contact) | 22 vs 34 | hit rate 0.56 (pad below the ball 17): the plane's accuracy is what a governor costs |
| late pelvis kick `kk` (default law), backhand pool | 28 vs 31 | exit speed normalised (6.05 +- 1.09 -> 5.08 +- 0.68 m/s), "long" 14 -> 1, but "net" 11 -> 31: exit elevation 23 +- 23 deg |
| `t_lock 0.10` (servo frozen earlier) | 29 vs 34 | forehand pad velocity noise barely lower (0.41 against 0.48 m/s), accuracy lost |
| no stroke (`d_push 0, drv_push 0`) | 34 vs 34 | identical serve for serve: the stroke fires at contact and does nothing |
| `t_servo 0.20` | 37 vs 34 | forehand returns better controlled, 11 pad-below-the-ball misses |
| forehand posture consolidated (the mean servo correction folded into the ready posture) | 29 | forehand pitch error to the aim +2.5 +- 4.1 (was -3.4 +- 8.9) but the ball is met above the pad |
| `hx_pad 1` / `hx_pad 0.5, z_bias -0.03` | 34 / 38 | height matching from the pad's measured height: no change / +3 (n.s.) |
| `x_hi 2.3 / 2.6` | 31 / 31 | the pad plane never goes past 2.3 |
| height / normal anticipation `g_ffz`, `g_ffn` | 26 / 29 | the pad ends 5 cm lower (contact height 1.148 against 1.197 m): consistent with `z_bias -0.0735` being a fudge for a servo that converges about half way |
| servo and aim from the ball's state at the goal plane `sg` | 27 | the moving-target hypothesis is not supported: the servo simply under-tracks (effective gain 0.25-0.4) |
| yaw-only forehand servo `qa 3` | 21 vs 54 (forehand pool) | the pitch servo helps; the pitch spread is not made by the servo |
| `qa 3` with the wrist raised (-0.65 / -0.45 / -0.25) | 24 / 2 / 0 of 120 | pitch sd 8.6 / 6.9 / 4.2 degrees but the pad ends 11 cm low (hit 0.75 / 0.51 / 0.19) |
| least-squares forehand postures from a finite-difference pose Jacobian (7 joints -> pitch, yaw, height) | 29% / 33% vs 45% (forehand pool) | the pose is reached (pitch -1.8, height +1.4 cm), the pitch sd stays 9 degrees: it is set by the wrist, not the servo |
| absolute far landing target, or the box 0.1-0.25 m deeper (forehand pool) | 54 vs 54, 49 vs 54 | the aim law's box is not what fails |
| side boundary `y_switch` 0.0 / 0.2 (300 serves) | 86 / 81 vs 84 | flat |
| backhand posture steps that remove its closed-face bias (pitch error +11.7 -> +4..+6 degrees as predicted) | 9 / 9 vs 16 of 60 | hit 0.87 -> 0.72-0.77: the swing's arrival and the pad's place move with the posture |
| servo start timed on the predicted contact (`ts_lead` 0.20 / 0.235 / 0.27 forehand, `bh_ts_lead` 0.20 / 0.23 / 0.26 backhand; 200 serves) | 64 / 74 / 74 vs 79; 55 / 62 / 65 vs 69 | the absolute `t_servo` is at least as good |
| contact-timed backhand swing `bh_lead` 0.42 / 0.47 / 0.52 on run 21's backhand (200 serves) | 1 / 8 / 16 vs 69 | the whole backhand set is tuned for the absolute timing |
| round-9 live tracking (`lt`) at its round-9 parameters | 5 / 12 vs 54 / 31 (fh / bh) | see below |

Computed muscle control (`tt_cmc.py`): MuJoCo's own muscle force model (gain and bias per fibre length and velocity) reproduces the model's actuator forces exactly; the arm's seven
joints have folded inertias 0.003-1.6 kg m^2 and torque capacities +-45-83 N m at the shoulder, +-7-13 N m at the forearm and wrist; a computed-torque law with a bounded
least-squares allocation over the 32 arm muscles saturates on a 0.5 rad move in 0.3 s (about 100 N m against ~50 at the shoulder) and leaves 0.4-0.6 rad errors on the wrist. Porting it
to the controller is days of work for a reflex-limited arm; the prototype is the record.
