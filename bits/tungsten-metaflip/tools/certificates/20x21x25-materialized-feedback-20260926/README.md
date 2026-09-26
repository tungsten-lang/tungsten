# Exact two-round GF(2) feedback campaign

A completed four-walk cold campaign from the checked-in 20×21×25/r5829
witness admitted these local price improvements:

| Canonical shape | Prior local price | Exact retained rank | Gain |
| --- | ---: | ---: | ---: |
| 20×21×24 | 5616 | 5563 | 53 |
| 20×20×25 | 5566 | 5507 | 59 |
| 19×20×25 | 5403 | 5364 | 39 |

The first round projected two different child shapes and walked them. The
second round projected the r5507 child to 20×19×25/r5397 and walked it to
r5364; a mode-6 basis rewrite of 20×21×24/r5567 reached r5564 and its walk
reached r5563. Each walk used 100,000,000 moves, with consecutive nonces
253300..253303. Density did not select or reject walk transitions.

Run `python3 verify.py` to reconstruct all nine complete tensors independently
in Python and Ruby and replay the basis/projection edges. Walk metadata
records finite observed runs, not an exhaustive search or optimality proof.
The manifest pins the input catalogue hash and the complete source witness.
Its external comparison columns are the pinned campaign metadata, not a
fresh catalogue audit. No world-record or novelty claim is made.

This campaign exercised the enhanced cold scheduler, but retained no new
`closure-composition` state. Its rank gains came from projections, walks,
and basis cleanup; they do not establish a matched yield advantage for the
new materializer. A separate matched 16×17×18 control and focused recipe
tests cover actual block/Kronecker materialization and feedback admission.
