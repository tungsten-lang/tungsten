# GF(2) 7×12×16 rank-872 directed descendant

This certificate extends the exact rank-962 `7×13×16` witness in the
adjacent `7x13x16-directed-20260924` archive. A mode-6 two-pass basis
rewrite followed by deleting coordinate 6 of the 13-axis and exact shared-
factor compression gives `7×16×12` at rank 880. A 100-million-move directed
walk with nonce `2026092501` reaches rank 873. A mode-12 basis rewrite keeps
rank 873; a second 100-million-move walk with nonce `2026092504` reaches
rank 872. Each retained full tensor passes Python and independent Ruby checks.

Run `python3 tools/check_7x12x16_directed_20260925.py` from
`bits/tungsten-metaflip` to check the complete source-to-result chain. Add
`--replay-walk BINARY` to replay both this archive's walks and both parent
walks byte-for-byte, using a compiled `tools/wide_rect_walk.w` binary. Add
`--catalog PATH` with the pinned catalog revision named in `manifest.json`
to replay the finite 2..32 composition closure.

The pinned GF(2) closure previously priced `7×12×16` at 876; this exact
representation lowers it to 872. Together with the parent rank-962 witness,
the finite closure improves 37 shapes by 184 rank units. Relative to the
parent witness alone, this descendant improves 20 more shapes by 103 units.
Those are bounded composition calculations, not tensor-rank lower bounds.
The public tracker listed 878 for `7×12×16` when checked on 2026-09-25:
https://github.com/dronperminov/FastMatrixMultiplication . The field is
GF(2); no claim is made about lifting this witness to Z or Q, worldwide
novelty, or optimality.
