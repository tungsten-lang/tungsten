# Top-two projection directed child (GF(2))

The certified top-two projection parent, oriented as 8×16×13 at rank 1044,
was walked for 100 million directed moves (nonce 2026092473). The exact
result has rank **1040**. Two 100-million-move continuations retained that
rank and reduced density to 26654. A fourth continuation did not change the
retained tensor. After permuting the axes to 16×13×8, another 100-million-move
walk (nonce 2026092479) reached rank **1039**. A two-pass basis change and
another 100-million-move walk reached ranks **1038** and **1037**. Six
orientation walks from rank 1037 and two further basis walks held rank. The
manifest records the retained tensors, walk nonces, and hashes.

The retained MFW1 tensor is compressed here; the checker reconstructs the
rank-1044 parent from its earlier certificate and checks each retained
tensor independently. The final rank-1037 tensor yields four descendants:
16×26×32/r7259 via Strassen's 2×2×2 tensor, 13×16×32/r3879 and
13×16×31/r3808 via certified blocks, and 8×13×17/r1141 by appending a
naive layer. Only the primitive certificates are stored; larger tensors are
generated and checked during replay. Earlier descendants remain checked as
provenance.

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
