# Rectangular wide-walk certificate (GF(2))

`9x5x20-r623.mfw` is a complete 623-term tensor decomposition of
matrix multiplication over GF(2), in MFW1 factor order `U(9x5) V(5x20)
W(9x20)`. Its canonical SHA-256 is
`04deeee17b7cd975f233aa9d952d988409266d2b91d60f44252df940925f0df5`.
This is a one-term improvement on the rank-624 structured-parent candidate;
it is not an optimality or global novelty claim.

Reproduction: replay the `5x9x20` row of
`../structured-parent-portfolio-20260922/manifest.json` with
`tools/replay_structured_parent_portfolio.rb --output DIR --only 5x9x20`.
Compile `tools/wide_rect_walk.w` with `bin/tungsten compile ... --release
--native --no-lto`, then run the resulting binary as
`wide-rect-walk 9x5x20 DIR/5x9x20/9x5x20.mfw OUT.mfw 10000000 19071`.
The finite walker checks the seed and output tensor exactly. The saved
certificate is independently expanded by
`python3 spec/wide_rectangular_certificate_test.py` and can also be checked by
`ruby tools/verify_tensor.rb --shape 9x5x20 9x5x20-r623.mfw` (paths relative to
this MetaFlip package and certificate directory as appropriate).

The pinned-catalog closure comparison is replayable with
`python3 tools/check_wide_rectangular_closure.py CATALOG.json`. It reports eight
one-unit rank-price improvements among shapes with coordinates 2 through 32;
those are composition prices, not eight separately materialized certificates.
Another 100 million moves from the retained rank-623 seed, and three further
100-million-move continuations from distinct rank-623 seeds, found no rank-622
result. This finite search is not a lower-bound proof.
