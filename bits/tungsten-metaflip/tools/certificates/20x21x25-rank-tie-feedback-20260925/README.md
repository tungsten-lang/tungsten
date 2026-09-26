# Exact 20×21×25 GF(2) rank-5829 witness

This lineage preserves a useful **rank tie**, not only strict parent improvements:

1. Checked-in 20×22×25/r6073, SHA-256 `a18d7b8c…`.
2. A 100M-move continuation, nonce 251701, ties at r6073 with a different
   full term set, SHA-256 `c1ff324e…`.
3. Mode-12 basis/projection, deleting middle coordinate 16, gives
   20×21×25/r5874, SHA-256 `6fa36309…`.
4. A 50M-move walk, nonce 251900, reaches **r5829**, SHA-256 `cc17e69d…`.

Run `python3 verify.py` to reconstruct all four complete tensors in Python
and Ruby and replay the basis/coordinate projection. Walk metadata describes
finite observed runs, not exhaustive search or optimality.

Matched follow-up: screening the same basis/projection family from the
original r6073 parent gives a best 20×21×25 child at r5876 (mode 16,
middle coordinate 10). With the same 50M-move follow-up budget and nonce
251900 it reaches r5830, SHA-256
`415e436050ce4e57220893bc5693614becb562baf0c6cc5d526579427be5812c`.
Both branches were independently full-tensor checked; only the winning
lineage is retained here. Producing the alternative parent itself cost the
additional 100M moves above, so this is not a matched total-campaign yield
claim.

The preceding local GF(2) price was 5875. The live
[Lille catalogue](https://fmm.univ-lille.fr/) comparison checked on
2026-09-25 is 5789: this is a local gain of 46, still 40 above that entry.
No world-record or global novelty claim is made.
