# Top-two projection directed child (GF(2))

The certified top-two projection parent, oriented as 8×16×13 at rank 1044,
was walked for 100 million directed moves (nonce 2026092473). The exact
result has rank **1040**. Two 100-million-move continuations retained that
rank and reduced density to 26654. A fourth continuation did not change the
retained tensor. The manifest records every replay nonce and SHA-256.

The retained MFW1 tensor is compressed here; the checker reconstructs the
rank-1044 parent from its earlier certificate, checks the retained tensor
independently, then builds and checks two descendants: 16×26×32 at rank
7280 via Strassen's 2×2×2 tensor, and 13×16×32 at rank 3882 via a certified
13×16×24 block. Only the primitive certificate is stored; the larger tensors
are generated during replay.

Run from the repository root:

```sh
python3 bits/tungsten-metaflip/tools/check_top_two_directed_20260924.py
```

To reproduce the walks byte for byte, compile
`bits/tungsten-metaflip/tools/wide_rect_walk.w` with
`bin/tungsten compile ... --release --native` and pass its binary as
`--replay-walk PATH`.

These ranks are exact GF(2) upper bounds. The manifest's Lille comparisons
are from a dated digest, not a proof of current worldwide novelty or
optimality.
