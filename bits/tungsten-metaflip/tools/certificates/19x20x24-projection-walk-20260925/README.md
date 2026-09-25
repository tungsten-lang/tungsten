# Two exact GF(2) projection/walk descendants

The checked 19x21x25/r5682 parent projects by deleting coordinate 12 of its
third axis. Exact shared-factor compression gives 19x21x24/r5446. Three bounded
native walks (10M, 20M, 100M moves) give the retained r5422 representation.
Deleting coordinate 10 of its second axis and compressing gives
19x20x24/r5153; a 1M + 10M + 100M continuation gives the retained r5102
tensor.

`verify.py` independently checks both retained full tensors in Python and Ruby,
recomputes both projections, and checks every rank and SHA-256 in the manifest.
Pass `--walker PATH` to replay the four deterministic walks as well. The two
compressed tensors are retained because the cold auto-loop discovers direct
certificate minima from checked-in `.mfw.gz.b64` files.

The screened local seed/certificate closure, including archived exact prices,
previously priced these shapes at 5686 and 5308. These local improvements are
**not world-record claims**: the [live Lille
index](https://fmm.univ-lille.fr/) listed 19x20x24/r4995 on 2026-09-25. The
individual Lille shape page still listed r5132 and was stale, so it must not be
used for a record comparison.
