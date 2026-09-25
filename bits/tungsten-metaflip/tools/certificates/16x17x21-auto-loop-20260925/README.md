# Exact 16×17×21 GF(2) feedback-loop witness

The bounded projection → directed-walk → composition scheduler started from
the checked-in 16×17×22/r3475 parent. It projected a verified
16×17×21/r3352 child, walked it to r3326, changed its basis, and walked to
r3322. A separate 50-million-move continuation reached **r3321**; a further
100-million-move continuation tied and is not retained. A sibling walk also
reduced the 16×17×22 parent from r3475 to r3474. The nine compact objects in
`manifest.json` preserve the improving states and their ancestors.

Run `python3 verify.py` to check every SHA-256, source identity, rank, full
GF(2) tensor in Python and Ruby, and the exact basis/projection steps. Walk
metadata records finite provenance; the verifier checks each resulting tensor
identity rather than replaying every random move.

The prior local GF(2) price for 16×17×21 was 3364. The
[Lille catalogue](https://fmm.univ-lille.fr/16x17x21.html) listed rank 3374
on 2026-09-25, so this complete GF(2) decomposition is numerically 53 lower
than that listed entry. The catalogue is not an exhaustive novelty check;
neither optimality nor a global world record is claimed.
