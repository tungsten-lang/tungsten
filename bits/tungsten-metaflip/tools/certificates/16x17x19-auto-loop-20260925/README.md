# Exact 16×17×19 GF(2) feedback-loop witness

The bounded automatic loop started from the checked-in 16×17×21/r3321
certificate. A basis/projection produced 16×17×20/r3170, and a 50-million-move
directed walk reached **r3138**. Projecting that result produced
16×17×19/r3066; another 50-million-move walk reached **r3045**. The retained
five-state lineage is in `manifest.json`. Run `python3 verify.py` to check
every hash, source identity, exact projection edge, and complete GF(2) tensor
independently in Python and Ruby.

The prior local GF(2) prices were 3140 and 3072, respectively. On
2026-09-25, the [Lille catalogue](https://fmm.univ-lille.fr/) listed 3209 for
16×17×20 and 3066 for 16×17×19. These decompositions are numerically 71
and 21 below those entries. The catalogue is not an exhaustive novelty check;
neither optimality nor a global world record is claimed. All eight scheduled
walks finished; the other tested basis neighborhoods did not lower a rank.
