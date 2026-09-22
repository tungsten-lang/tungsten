# Rectangular wide-walk certificates (GF(2))

`9x5x20-r623.mfw` is a complete 623-term tensor decomposition of
matrix multiplication over GF(2), in MFW1 factor order `U(9x5) V(5x20)
W(9x20)`. Its canonical SHA-256 is
`04deeee17b7cd975f233aa9d952d988409266d2b91d60f44252df940925f0df5`.
This is a one-term improvement on the rank-624 structured-parent candidate;
it is not an optimality or global novelty claim.

`12x10x20-r1448.mfw` is a complete 1448-term decomposition in factor order
`U(12x10) V(10x20) W(12x20)`, with canonical SHA-256
`ce1223857ec1c7bf2215b248a5cbeb42c4171df2c648ee7d752fd9f822741df8`.
It improves the structured-parent rank 1464 by 16 terms. Among the verified
rank-1448 continuations, this retained representation has the lowest density
(74455); density was an archive tie-break, not a walk acceptance gate.

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
The finite walker checks the seed and output tensor exactly. The saved
certificates are independently expanded by
`python3 spec/wide_rectangular_certificate_test.py` and can also be checked by
`ruby tools/verify_tensor.rb --shape SHAPE CERT.mfw` (paths relative to this
MetaFlip package and certificate directory as appropriate).

The pinned-catalog closure comparison is replayable with
`python3 tools/check_wide_rectangular_closure.py CATALOG.json`. It reports 11
rank-price improvements totaling 56 terms among shapes with coordinates 2
through 32; those are composition prices, not 11 separately materialized
certificates. No square shape improves in this finite closure.
Another 100 million moves from the retained rank-623 seed, and three further
100-million-move continuations from distinct rank-623 seeds, found no rank-622
result. This finite search is not a lower-bound proof.
Five 100-million-move continuations from rank-1448 seeds found no lower rank.
