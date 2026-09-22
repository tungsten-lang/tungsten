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
For context, the [Université de Lille full table](https://fmm.univ-lille.fr/algo_32.html)
consulted on 2026-09-22 lists 10x12x19:1434, 10x12x25:1856,
16x25x27:6048, and 16x25x28:6344. The retained 12x10x19 rank 1421,
12x10x25 rank 1836, and 16x28x25 rank 6223 beat their corresponding table
entries; 16x27x25 rank 6080 does not. Some
individual shape pages show older, weaker bounds, so those pages should not
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
`python3 tools/check_wide_rectangular_closure.py CATALOG.json`. It reports 17
rank-price improvements totaling 272 terms among shapes with coordinates 2
through 32; those are composition prices, not 17 separately materialized
certificates. No square shape improves in this finite closure.
Another 100 million moves from the retained rank-623 seed, and three further
100-million-move continuations from distinct rank-623 seeds, found no rank-622
result. This finite search is not a lower-bound proof.
Five 100-million-move continuations from rank-1448 seeds found no lower rank.
One further 100-million-move continuation from rank 6223 found no lower rank.
