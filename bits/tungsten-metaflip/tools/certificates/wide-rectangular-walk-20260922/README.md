# Rectangular wide-walk certificates (GF(2))

`9x5x20-r623.mfw` is a complete 623-term tensor decomposition of
matrix multiplication over GF(2), in MFW1 factor order `U(9x5) V(5x20)
W(9x20)`. Its canonical SHA-256 is
`04deeee17b7cd975f233aa9d952d988409266d2b91d60f44252df940925f0df5`.
This is a one-term improvement on the rank-624 structured-parent candidate;
it is not an optimality or global novelty claim.

The first pass used every one of the 81 compact portfolio rows as an exact
seed, with 10 million directed moves and nonce 19071 per row. Exactly three
rows dropped rank in that finite pass: 9x5x20, 12x10x20, and 16x28x25.
The other 78 did not drop in this budget; that is not evidence of optimality.

`12x10x20-r1448.mfw` is a complete 1448-term decomposition in factor order
`U(12x10) V(10x20) W(12x20)`, with canonical SHA-256
`ce1223857ec1c7bf2215b248a5cbeb42c4171df2c648ee7d752fd9f822741df8`.
It improves the structured-parent rank 1464 by 16 terms. Among the verified
rank-1448 continuations, this retained representation has the lowest density
(74455); density was an archive tie-break, not a walk acceptance gate.

`16x28x25-r6223.mfw.gz.b64` retains a complete 6223-term tensor with SHA-256
`049d2676a8f0e9c560026c5ad511faadc14debd415cc5d6d6c97e3407f3e3923`
after base64 and gzip decoding. Its factor order is `U(16x28) V(28x25)
W(16x25)`. It improves the rank-6225 structured-parent candidate by two
terms. The 1.77 MB MFW1 text is stored as about 186 KB of encoded compressed
text so the repository need not carry the full-width archive verbatim.

`12x10x25-r1836.mfw.gz.b64` retains a complete 1836-term tensor, canonical
SHA-256 `9f6e46e1cbbf99417ab2f1ae3c36a92260809ef313e6540eabcaa065baab7c58`,
in factor order `U(12x10) V(10x25) W(12x25)`. It comes from exact replay of the
`10x12x25` structured-parent row followed by an axis-0 reverse shared-factor
refactor. The refactor preserves rank and lowers density from 92102 to 91648;
density was an archive tie-break, not a search acceptance gate. Matched 50
million-move walks from both the original and refactored seeds, plus two
20-million-move walks from other refactors, found no lower rank in those
finite budgets.

Two exact coordinate projections of these retained tensors, followed by
GF(2) duplicate cancellation and shared-factor compression, improve further
rectangles. Deleting coordinate 19 (zero-based) of the output axis of the
12x10x20 certificate gives a rank-1421 tensor. Two exact same-rank refactors
(axis 0 forward, then axis 1 forward) give the retained
`12x10x19-r1421.mfw.gz.b64`, SHA-256
`a184dc5aeb7a90d5e88af72a4ec4eb73f58888ea9ce0caa5159b533ed0724de5`,
density 69756. The pinned catalog plus compact-parent portfolio priced that
shape at 1451. Deleting coordinate 27 of the middle axis of the 16x28x25
certificate gives an exact rank-6129 seed. A directed 10-million-move walk
with nonce 19071, then four 50-million-move continuations with nonces
19072 through 19075, reached rank 6080. Two exact same-rank refactors
(axis 0 reverse, then axis 2 forward) give the retained
`16x27x25-r6080.mfw.gz.b64`, SHA-256
`7d6bdd7c300602617ad8f9c52b3638210391699394e69c55d7b86dc12bfd2ce3`,
density 231672; the previous finite composition price was 6195. Both tensors
were separately expanded by the Ruby verifier and the independent Python
certificate test. These are exact GF(2) decompositions, not global record or
optimality claims.

Replaying the `16x25x32` structured-parent row produces an exact rank-7055
tensor in factor order `U(16x32) V(32x25) W(16x25)`. Coordinate projection,
exact shared-factor refactors, and bounded directed walks produce
`16x31x25-r6916.mfw.gz.b64`, canonical SHA-256
`a31cfc6638245c110fcba943c4ed948889915210be74ced9d2c8f12b057e4e41`,
density 267253. Continuing through a projected 16x30x25 intermediate produces
`16x29x25-r6534.mfw.gz.b64`, canonical SHA-256
`bb01d2f6b1516808bc22a9edfd3ca2a0b36da9ea9c440a46846a07a22c0cad78`,
density 254205. The intermediate reached rank 6745, but is not retained as a
rank candidate: the pinned GF(2) catalog already has rank 6690 for 16x25x30.
Both retained tensors were independently expanded by the Ruby verifier and
the focused Python certificate test.

Replaying the `8x20x30` structured-parent row yields rank 2803. Deleting
coordinate 14 of its middle axis, cancelling equal GF(2) terms, and applying
exact shared-factor compression yields `8x19x30` at rank 2743. Two exact
refactors lower it to 2729. Bounded walks of 50 million moves (nonce 19073)
and 100 million moves (nonce 19077) lower it to 2724 and 2723, respectively.
The retained same-rank refactor is `8x19x30-r2723.mfw.gz.b64`, SHA-256
`519e99587c73888bbc011a5a11c7342fcae631e79d591b077e52d3749772fc7a`,
density 84555. The prior pinned GF(2) catalog-plus-portfolio composition price
was 2766. This certificate is checked by both full-tensor verifiers; the
finite walk is not an optimality proof.

Replaying the `15x20x28` structured-parent row yields a rank-4700 tensor in
factor order `20x28x15`. Deleting coordinate 13 of the first axis and applying
exact GF(2) cancellation/compression yields `19x28x15` at rank 4600; exact
refactoring lowers it to 4598. A 50-million-move walk (nonce 19101) reaches
4576; the 100-million-move continuation (nonce 19107) does not lower rank.
The retained same-rank refactor `19x28x15-r4576.mfw.gz.b64` has SHA-256
`20554ab7fe74e6a977ad7612274843926e79b18bbd2f3f168bf103b0cbc2ca86`
and density 150216. Deleting coordinate 7 of the last axis of the same
rank-4700 parent yields `20x28x14` at rank 4503 after exact compression;
refactoring lowers it to 4491. A 50-million-move walk (nonce 19103) reaches
4485 and a 100-million-move continuation (nonce 19109) reaches 4484. The
retained same-rank refactor `20x28x14-r4484.mfw.gz.b64` has SHA-256
`10b966b8ceeb69bdf506007eb026df28df0aed4d6c118a5593e991a915ce8091`
and density 144255. Prior pinned GF(2) catalog-plus-portfolio prices were
4682 and 4530 for the two projected shapes.

Projecting output-axis coordinate 7 (zero-based) of the verified
`20x28x14` tensor and applying exact GF(2) shared-factor compression gives
`20x28x13` at rank 4188. Two bounded basis sweeps reduce it to 4180; directed
walks of 50 million, then 100 million, then 100 million moves (nonces 19115,
19117, 19119) reduce it to 4172, 4168, and 4167. The retained
`20x28x13-r4167.mfw.gz.b64` has SHA-256
`dbbcfd9d67a9c7a51927f6b0e7cdf72f2df419fb136e2a9cde04743d6749e986`.
The pinned GF(2) catalog-plus-portfolio price was 4271. The other two
one-coordinate projections of the same parent that were tested here are
exact, but the pinned catalog already derives lower ranks for their shapes.

A follow-up scan tested all 749 one-coordinate projections of the 13 retained
rectangular certificates, using exact cancellation and shared-factor
compression. Four projected shapes improved the pinned GF(2) composition
prices. From `20x28x13`, first-axis coordinate 3 gives `19x28x13` at rank
4093; two bounded basis sweeps reach 4071 and a 50-million-move walk (nonce
19125) reaches the retained rank 4068, SHA-256
`15e461d7172163885bc5a51485d6de238e42ca783f02adc786bb9c85947c53e5`.
From the same parent, middle-axis coordinate 15 gives `20x27x13` at rank
4105; two basis sweeps reach 4097 and a 50-million-move walk (nonce 19131)
reaches the retained rank 4092, SHA-256
`23a9d6e38925bfaecdccf3f3dc9f400dfd68b2f66f3fb4ab8e5aa1b032e4cc3d`.
From `8x19x30`, last-axis coordinate 16 gives `8x19x29` at rank 2663; two
basis sweeps reach 2654, then 50-million and 100-million-move walks (nonces
19129 and 19137) reach the retained rank 2642, SHA-256
`cf97d17f4b857e83df6e97541938e545f4a3ad03ce981d828a189df90099c633`.
From `19x28x15`, middle-axis coordinate 21 gives `19x27x15` at rank 4507;
two basis sweeps reach 4495 and a 50-million-move walk (nonce 19141) reaches
the retained rank 4488, SHA-256
`6547c40d267aed101dae2f3a2d91e5d3ded8198e586a5a4ea1f46af701b41feb`.
The latter improves the pinned GF(2) composition price but not the currently
served Lille table entry of 4485. The other three beat that table's entries
for 13x19x28 (4096), 13x20x27 (4160), and 8x19x29 (2696). All four
certificates are checked by the Ruby and independent Python full-tensor
verifiers; finite walks are not optimality proofs.

Replaying the `20x20x25` structured-parent row yields rank 5566. Deleting
coordinate 18 of its middle axis, cancelling equal GF(2) terms, and applying
exact shared-factor compression yields `20x19x25` at rank 5439. Repeated
exact refactors lower it to 5418. A 50-million-move walk (nonce 19111)
reaches 5405 and a 100-million-move continuation (nonce 19113) reaches
5403. The retained same-rank refactor `20x19x25-r5403.mfw.gz.b64` has
SHA-256 `c11d3a775ed89031462c126f1707f63cd600c611d268878f165a838b9a8eb2a6`
and density 339443. The prior pinned GF(2) catalog-plus-portfolio price
was 5583. The exact tensor is checked by both independent verifiers.

For context, the [Université de Lille full table](https://fmm.univ-lille.fr/algo_32.html)
(served version `2b71762f906bef43f0ce25d31a9b8e5ad28a23db`, consulted on
2026-09-22) lists 10x12x19:1434, 10x12x25:1844,
16x25x27:6048, 16x25x28:6307, 16x25x29:6507, 16x25x31:6914,
8x19x30:2775, 13x20x28:4271, 15x19x28:4663, 14x20x28:4556,
and 19x20x25:5276.
The retained 12x10x19 rank 1421, 12x10x25 rank 1836, 16x28x25 rank 6223,
8x19x30 rank 2723,
13x20x28 rank 4167, 15x19x28 rank 4576, 14x20x28 rank 4484,
13x19x28 rank 4068, 13x20x27 rank 4092, and 8x19x29 rank 2642 beat their
corresponding table entries; 16x27x25 rank 6080, 16x29x25 rank 6534,
16x31x25 rank 6916, 19x20x25 rank 5403, and 15x19x27 rank 4488 do not.
Some individual
shape pages show older, weaker bounds, so those pages should not
be used alone for record comparisons. These exact GF(2) certificates are not
claims of global novelty across every source or field.

Reproduction: replay the `5x9x20` row of
`../structured-parent-portfolio-20260922/manifest.json` with
`tools/replay_structured_parent_portfolio.rb --output DIR --only 5x9x20`.
Compile `tools/wide_rect_walk.w` with `bin/tungsten compile ... --release
--native --no-lto`, then run the resulting binary as
`wide-rect-walk 9x5x20 DIR/5x9x20/9x5x20.mfw OUT.mfw 10000000 19071`.
For the second certificate, replay `--only 10x12x20`. From its generated
`12x10x20.mfw`, run 10 million moves with nonce 19071 (rank 1456), continue
that output for 100 million moves with nonce 19071 (rank 1448), then continue
for 100 million moves with nonce 19077 (the saved density-74455 certificate).
For the third, replay `--only 16x25x28`, run its generated `16x28x25.mfw` for
10 million moves with nonce 19071 (rank 6224), then run that output for 100
million moves with nonce 19073 (rank 6223). Decode the saved certificate with
`base64 -D < CERT.mfw.gz.b64 | gzip -dc > CERT.mfw` before feeding it to the
standalone walker or Ruby verifier. The focused Python test decodes it itself.
The finite walker checks the seed and output tensor exactly. The saved
certificates are independently expanded by
`python3 spec/wide_rectangular_certificate_test.py` and can also be checked by
`ruby tools/verify_tensor.rb --shape SHAPE CERT.mfw` (paths relative to this
MetaFlip package and certificate directory as appropriate).

The pinned-catalog closure comparison is replayable with
`python3 tools/check_wide_rectangular_closure.py CATALOG.json`. It reports 81
rank-price improvements totaling 3824 terms among shapes with coordinates 2
through 32; those are composition prices, not separate materialized
certificates for every improved shape. No square shape improves in this finite closure.
Another 100 million moves from the retained rank-623 seed, and three further
100-million-move continuations from distinct rank-623 seeds, found no rank-622
result. This finite search is not a lower-bound proof.
Five 100-million-move continuations from rank-1448 seeds found no lower rank.
One further 100-million-move continuation from rank 6223 found no lower rank.
