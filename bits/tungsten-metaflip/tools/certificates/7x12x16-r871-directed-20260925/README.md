# GF(2) 7×12×16 rank-871 representations

Three distinct two-pass basis states of the exact rank-872 witness in the
adjacent `7x12x16-directed-20260925` archive each produced a rank-871
decomposition in a separate 100-million-move directed walk. Modes 6, 7, and
13 used nonces `2026092531`, `2026092533`, and `2026092534` respectively.
Their full tensor identities are checked independently; the optional native
replay reproduces each result byte-for-byte. The mode-6 witness is the
lowest-density one; mode 7 has a different factor-pair profile and a better
7×15×12 projection seed. Rank ties are retained as full decompositions, not
collapsed into one number.

Run `python3 tools/check_7x12x16_r871_directed_20260925.py` from
`bits/tungsten-metaflip`. Add `--replay-walk BINARY` for all seven native
walks in this and the two parent archives, or `--catalog PATH` for the pinned
finite 2..32 GF(2) composition closure.

The pinned pre-871 price for `7×12×16` was 872. This archive adds 22 improved
shapes and 30 rank units beyond that parent; together with the rank-962 and
rank-872 ancestors, the cumulative closure improves 39 shapes and saves 214
rank units. This is an exact GF(2) upper bound relative to that local corpus,
not an optimality, integer/rational, or worldwide-novelty claim.
