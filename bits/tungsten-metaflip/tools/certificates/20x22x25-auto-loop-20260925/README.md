# Exact two-round 20×22×25 feedback

The bounded offline loop started from the checked-in 20×22×25/r6076 GF(2)
certificate, projected all one-coordinate children, ran two five-million-move
native walks, and revisited descendants in its second round. Two subsequent
50M/100M continuations lowered its best 19×21×25 child again; a final 100M
continuation tied. The compact manifest retains the best child per improved
shape and every ancestor needed to trace it back to the source. It is under
2 MB, not the 19 MB scratch run.

| Shape | Prior local price | Retained rank | Pinned external comparison |
| --- | ---: | ---: | ---: |
| 19×22×25 | 6128 | 5954 | 5912 |
| 20×21×25 | 5923 | 5875 | 5802 |
| 19×21×25 | 5833 | 5689 | 5675 |
| 19×22×24 | 5829 | 5733 | 5610 |

The four direct local reductions sum to 462 rank units. During the two-round
campaign, repricing the finite 2..32 GF(2) composition table after each
admission saved 695 units across affected shapes; this excludes the later 29
rank units from the two direct continuations. The external numbers come from the pinned catalog digest in
`manifest.json`; they are comparison metadata, possibly over other fields.
**None of these tensors beats its pinned external comparison, and no world
record is claimed.**

From the repository root, run
`python3 -B bits/tungsten-metaflip/tools/certificates/20x22x25-auto-loop-20260925/verify.py`
to decode all nine tensors, check their complete
GF(2) identities in Python and independently in Ruby, compare ranks/hashes,
and replay every retained projection. Native walk step counts and nonces in
the manifest are provenance, not a deterministic transcript of every flip.
