# Compact GF(2) impact-parent witnesses

Six MFW1 decompositions found in bounded local campaigns are
retained here as gzip/base64 text, rather than leaving their only copies in
temporary search directories. Each has a complete tensor identity, not merely
a rank or a composition-price estimate. Run `python3 verify.py` to check the
hash, rank, full GF(2) tensor in Python, and full tensor again with the Ruby
verifier. This is an upper-bound certificate set, not a novelty or optimality
claim.

`search_wide_auto_loop.py` already discovers compact certificates recursively
and admits these bounds to its initial price closure after a full tensor check.
The six witnesses jointly lower the pinned 2..32 local rank-only closure at
103 shapes by a total of 7,444 rank units. That figure prices recursively
composed algorithms; it is not a claim that all 103 tensor witnesses are
materialized here. The live multiword fleet still does not automatically
compose and restart from these wide descendants.
