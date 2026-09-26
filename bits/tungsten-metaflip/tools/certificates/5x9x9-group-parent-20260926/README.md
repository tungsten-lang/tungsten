# Checked 5×9×9 group-composition parent

This exact GF(2) rank-294 tensor improves the **available body** for this
shape in the bounded composition library from rank 301 to rank 294. It does
not improve the local price or the [Lille comparison](https://fmm.univ-lille.fr/5x9x9.html)
of 293 checked on 2026-09-26. No world-record or optimality claim is made.

The parent is the packaged Perminov 2026 3×3×5/r38 serendipitous scheme,
SHA-256 `8d77e11626b09930411147a75615e2f20db3da5e3fc844f476e3b328c074f2e3`.
Scale (3,3,1) partitions its equal-U classes into five singletons, twelve
pairs, and three triples. The corresponding exact leaf ranks 9, 15, and 23
give `5*9 + 12*15 + 3*23 = 294`, rather than the pair-only 297.
The rank-15 leaf is a verified projection of the packaged Peterson 2026
2×3×5/r26 scheme. Metadata pins every static leaf recipe, not a catalogue
price. See [Perminov's construction](https://arxiv.org/html/2606.02480v1).

Run `python3 verify.py`. It checks the original packaged parent hash, replays
the static leaves, independently reconstructs the group product in Ruby,
and verifies the complete compressed MFW tensor in Python and Ruby.
The small decimal snapshots make the group recipe self-contained.

`CompositionLibrary.from_repository()` discovers the MFW automatically, so
it can replace a weaker projected walk seed without a new strategy switch.
A matched 100M-move control (nonce 254101) tied at rank 294 from this seed;
the pair-only rank-297 seed also reached rank 294. This is useful witness
availability, not evidence of a general search-yield advantage.
