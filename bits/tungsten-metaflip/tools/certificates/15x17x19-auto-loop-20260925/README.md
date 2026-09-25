# Exact 15×17×19 GF(2) feedback-loop witness

The bounded loop started from the checked-in 16×17×19/r3045 witness.
A basis/projection produced 15×17×19/r2987; a 50-million-move directed walk
reached **r2964**, improving the prior local GF(2) price of 2973.
`manifest.json` retains the three exact states. Run `python3 verify.py` to
check the source and projection lineage and reconstruct every full tensor in
Python and Ruby. The eight-walk campaign found no other strict rank drop.

The [Lille catalogue](https://fmm.univ-lille.fr/) listed rank 2934 for this
shape on 2026-09-25, so this is a local-price improvement rather than a
catalogue-beating claim. No optimality or global novelty is claimed.
