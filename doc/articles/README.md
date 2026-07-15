# Articles

Write-ups from building a matrix-multiplication rank search natively in Tungsten.

The work started from a question — could a self-verifying, all-paths search idea
(originally for the Traveling Salesman Problem) be turned on the problem of
*discovering* faster matrix-multiplication algorithms? — and ended as a fast,
leak-free, SOTA-matching flip-graph search written entirely in Tungsten, plus a
set of hard-won compiler-performance lessons.

## Contents

- **[matmul-flip-graph-search.md](matmul-flip-graph-search.md)** — the search
  itself: the flip-graph method over GF(2), the native-Tungsten implementation,
  and the results (3×3 → 23, 4×4 → 47, 5×5 → 95). What was matched, what wasn't,
  and how those results compare with the current GF(2) record targets.

- **[tungsten-performance-engineering.md](tungsten-performance-engineering.md)** —
  the engineering: a root-caused compiler codegen bug, a 375 MB/s memory leak, and
  a profiler-guided **18× speedup** — with the general rule that came out of it
  (*type hot-loop variables `## i64`; profile, don't guess*).

- **[metaflip-certified-bounds-and-block-composition.md](metaflip-certified-bounds-and-block-composition.md)** —
  the next research phase: an independent replay of the new 3×3 lower bound 20,
  an independently replayed quotient-rank proof that `<3,2,4>` has exact GF(2)
  rank 20, 186 independently reconstructed
  block-composed GF(2) algorithms (176 strict apparent records, one co-record,
  and nine exact upper bounds without a pinned GF(2) comparator), the candidate 7×7
  rank-247 record, and exact tunnels into term-disjoint restart basins.

## Project summary

A flip-graph matrix-multiplication search (flips + reductions + plus-transitions,
all over GF(2)) was implemented as native compiled Tungsten, including the *full*
Arai et al. adaptive policy (structured plus-transition + edge-constraint
hierarchy). Getting it fast and correct required fixing a compiler codegen bug,
killing a per-move bignum leak that OOM'd the machine in ~20 s, and an 18×
profiler-guided speedup (the default arbitrary-precision `Int` was routing every
hot-loop compare/add through bignum helpers). The finished search runs leak-free at
~10–28 million moves/second per core and matches standing records: **3×3 rank 23**
and **4×4 rank 47** (the latter now reached in ~1 minute from naive via the edge
hierarchy, a verified decomposition disjoint from AlphaTensor's). It does **not**
break any record: **5×5 walls at 95** (not 94) under every policy tried, and **6×6
stalls at the recursive seed 161** because the Kronecker seed is a near-isolated
flip-graph vertex. Current larger GF(2) targets are lower still: 5×5 rank 93, 6×6
rank 153, and 7×7 rank 247. That first search phase broke no record; its durable wins were the
compiler fixes, the 18× speedup, the edge-constraint convergence on small sizes,
and an honest map of exactly where the method's reach ends.

The follow-up work changes that last conclusion in two carefully separated
ways. Wang's certificate now proves the stronger 3×3 lower bound 20, while
support-aware block composition gives 176 strict apparent GF(2) upper-bound records
across larger rectangular formats and a weighted outer construction gives a
candidate 7×7 rank-247 record. For `<3,2,4>`, two constrained mode lemmas and
six independently replayed quotient-rank pseudo-Boolean proofs now exclude
rank 19, closing the global GF(2) rank at exactly 20. A hardened two-basin 4×4 campaign
still did not find rank 46 after 988.5 billion reported moves; that remains a
search negative, not a lower-bound proof. The third article above gives the
exact certificates, audit boundaries, and reproduction details.
