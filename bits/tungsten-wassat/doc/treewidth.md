# Clause-checked treewidth lower bounds

The fast-mode worker decodes an elimination-order treewidth encoding from the
input clauses. It stores no graph, contraction sequence, model, or benchmark
answer. Its constant-size admission check runs on the coordinator; all clause
verification and graph search run alongside the existing solving arms.

The accepted structure follows Jdrasil's improved formulation: transitive
ordering variables, mandatory graph edges, fill-edge implications, edge
orientation, and sequential counters bounding each vertex's outgoing arcs.
See the upstream [formulation](https://github.com/maxbannach/Jdrasil/blob/eafaa4cc76df9d938ac85b88e5c4218a4fbb6c1a/subprojects/core/src/main/java/jdrasil/sat/formulations/ImprovedEncoder.java)
and [counter encoder](https://github.com/maxbannach/Jdrasil/blob/eafaa4cc76df9d938ac85b88e5c4218a4fbb6c1a/subprojects/core/src/main/java/jdrasil/sat/encodings/DecreasingCardinalityEncoder.java).
Block order is checked; literal order inside a clause may vary, as the early
flat propagation probe permutes watched literals. Exact matching rejects
missing literals and repeated literals. Counter inputs must be a permutation
of exactly one vertex's arcs, and auxiliary ranges must be fresh and disjoint.
Symmetry-breaking unit clauses may be ignored: additional constraints cannot
invalidate a refutation of the checked subset.

Why a refutation is sound:

1. A satisfying assignment defines a total elimination order. Mandatory edges
   and fill clauses ensure that each eliminated vertex's remaining neighbors
   are represented by outgoing arcs. The counters bound their number by `k`.
   Thus the decoded graph would have an elimination order of width at most `k`.
2. Contracting a graph edge cannot increase treewidth. Replacing its endpoints
   by one vertex in every bag of a tree decomposition preserves connectedness
   and cannot enlarge a bag. Isolated vertices can also be deleted safely.
3. The worker contracts minimum-degree vertices into a neighbor with fewest
   common neighbors, with deterministic tie breaking, until at most 24 vertices
   remain. It then enumerates all possible first vertices of degree at most
   `k`, fills their neighborhoods, and recurses. A remaining-vertex mask uniquely
   determines the filled graph, so completed failed states can be memoized.
   Only exhaustive failure is a refutation. A successful order for the minor
   says nothing decisive about the original graph and falls back to CDCL.

The implementation bounds graphs to 256 vertices, inputs to 2 million variables,
40 million clauses and 160 million literals, counter strides to 32 and width
bounds to 12. Search stops at one million nodes or five seconds. Fixed arrays
hold the graph, counter mapping, recursion stack and memo bitset; no node
allocates memory. Cancellation is checked every 4,096 verified clauses, every
contraction, and every 1,024 search nodes. Cap, deadline, cancellation and any
recognition failure return no result.

The worker races the scout without a grace period. Interrupted or unpublished
proofs may retry in an unused later worker slot. If memory permits only one
CDCL arm, that arm continues from the scout while the worker runs. Proof modes
and finite-conflict runs retain the ordinary CDCL path. `WASSAT_TREEWIDTH=0`
disables the worker; `WASSAT_TREEWIDTH_SCOUT=0` leaves only its later entry.

On SC2026 `ex095_8`, decoding yields 181 vertices, 466 edges and bound 8. A
157-edge contraction leaves a 24-vertex minor. Independent reconstruction,
a separately generated SAT encoding, CaDiCaL, and DRAT verification confirm
that this minor has no width-8 elimination order. This is a structural
certificate in fast mode, not a DRAT proof of the original large CNF.

Focused tests cover valid SAT/UNSAT encodings, clause permutations, malformed
templates, counter inputs, partial bounds, cancellation and retry semantics.
The retained experiment also compares 72 generated encodings and mutations
against CaDiCaL, checks every reference UNSAT proof, and replays every SAT CLI
model against its original clauses.
