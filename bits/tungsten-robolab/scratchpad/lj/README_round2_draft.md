### Round 2: the ideal take-off, the landing that rolls over, and what a fresh start does

DRAFT (numbers marked TBD until the last runs finish; move under "Long jump" before "## High-school 110 m hurdles").

**The pipeline** (`playground/long_jump_limits.py`, the runner's own approach state in, jump out):

1. `capture` a real rollout at the start of the plant flight (or, with `--from pen`, at the penultimate touchdown):
   position, velocities, muscle activations and tendon fibre states, exactly.
2. `optimise`: all 32 muscles follow open-loop excitations from that state to the take-off; sep-CMA chooses them to
   maximise the ballistic distance from the board. This is the IDEAL-CONTROL ceiling of that body from that approach:
   4.93 m for the 7.02 m/s p95 runner (vx 6.27, vz 2.89, contact 0.112 s), 4.25 m for the elite2 runner (6.56 m/s).
3. `distil` the ideal into quintic contraction knots plus drive knots on a 30 ms grid, latched on the plant touchdown
   (`j_ik`, `ik_*` params), and `robust`ly re-optimise it over captured perturbed approaches.
4. `handover` the program on many approaches, then `landing`: a landing program (`j_il`, `il_*`: excitation knots on their
   own clock, latched on the first sand contact) learned by sep-CMA on the hand-over states. ORACLE-class: an open-loop
   excitation table, not contraction targets plus reflexes; so is the take-off program at reflex gain 0.03 (p95 pn).

**What a fresh start does to a champion.** The arena's 16 starts per trial are fixed, so a champion is scored on the
same 16 perturbed starts forever. On 96 fresh starts (seeds 7001-7096) the old p95 robust champion scores 3.27 m, not
3.92 (90 legal, 2 fell in the run, 2 somersaulted, 1 fouled, 1 touched the runway after landing), and the elite2 champion
3.18 m on 80 (69 legal; 5 landed short, 6 fouled). TBD: new champion on the same starts.

**Failure taxonomy** (112 starts, p95 penultimate-touchdown program): ...

**Failure taxonomy** (112 starts: 96 fresh seeds 7001-7096 and the arena's 401-416, p95 penultimate-touchdown program
`ik_from 1`, landing program on a fixed clock unless noted; the harness `handover` reproduces every class):

- **Landing rolls over: a timing problem, not a rotation-control problem.** The landing program's knots run on a
  hand-over clock (the sand only re-syncs it). A flight 0.09 m lower or 0.2 m/s slower than the ones it was learned on
  lands 30-50 ms earlier than the program expects; its legs are still hanging when the toes touch the sand with the
  COM 1.0 m up and 0.1-0.2 m behind the toes, and the body vaults over them (Ly 0 -> 75-110 kg m2/s in 0.1 s, torso
  pitch through pi). Fix (`il_tg`, `il_zl`): a **ballistic-time clock**, the program time before the sand is
  tg - (the COM's ballistic time to fall to zl); a flight is ballistic whatever the limbs do, so the legs' tuck and
  reach are locked to the predicted landing. On the 32 hand-overs of the landing search: 3 roll-overs -> 0 for tg
  0.58-0.66. On other starts the program was trained on 32 hand-overs only and overfits the clock (tg 0.70: 48
  somersaults of 112), so the landing needs many hand-overs (mined: 316).
- **A scuffing swing foot** (4 of 96): the plant-side toe clears the runway by 12 mm in a healthy start (site height
  0.032 m, on the ground 0.019 m) and drags for 0.1-0.15 s in a bad one; the plant-touchdown latch (force > 0.05 BW) fires on
  the scuff at 0.10 s, 0.14 s before the ideal touchdown, the program clock jumps ahead and runs the stance in the air.
  Fix (`ik_fmin` 1.5): the latch needs 1.5 body weights; a real plant reads 4 BW on its first tick, scuffs 0.2-0.94.
- **Weak take-offs** (vz 1.6-2.4 m/s instead of 2.7-3.0): the torso pitch at the penultimate touchdown (0.08 +- 0.03 rad,
  tail 0.19) sets the strength, vz = 3.05 - 4.0 x pitch (harness regression on 161 starts), and the swing foot 0.5-0.7 m
  behind the COM (a late stride phase, ~10% of starts) is the same class. Short flights (0.4-0.6 s) land with the legs
  still hanging. A one-sided pitch feedback on the free leg's hamstrings (`ik_kp_F_ham`, `ik_fbclip 1`) lifts vz
  (vz < 2.4: 10 -> 1 of 161) but turns those starts into forward-rotating take-offs (L +2 .. +23 kg m2/s instead of -5.8 +- 2)
  that no landing recovers: every somersault of the 112 fresh starts has L > 1.7 or a take-off pitch >= 0.24 rad.
- **Fouls** (3 of 112): 5-49 mm over the line; the take-off foot's front lands 0.06 +- 0.05 m behind it. A check mark
  0.05 m longer (`long_jump_p95g`: board 37.54 m, `j_board_shift` and `ik_gap0` moved with it so the run-up is unchanged)
  removes them for 0.05 m.
- **The runner's own stumbles** (2 of 96): a fall in the acceleration phase (steps of 0.9, 0.9, 0.7 m at 3.5 s).
