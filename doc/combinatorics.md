# Finite combinatorics

`use combinatorics` loads exact finite graph and coding-theory foundations.
The module is intended for replayable finite objects and certificates. It does
not import asymptotic bounds merely because their finite definitions are
available.

## Simple graphs

`FiniteSimpleGraph` owns an undirected loop-free adjacency matrix and exposes
exact `edge_count`, `connected?`, `bipartite?`, `acyclic?`, `triangle`, and
`degeneracy` queries.

```tungsten
use combinatorics

cycle = FiniteSimpleGraph.new([
  [0, 1, 0, 1],
  [1, 0, 1, 0],
  [0, 1, 0, 1],
  [1, 0, 1, 0]])

<< cycle.bipartite?                    # true
<< cycle.degeneracy                    # 2
<< cycle.degeneracy_certificate.verified? # true
```

The degeneracy certificate proves both directions. Its elimination ordering
gives the upper bound, while a recorded induced vertex set with minimum degree
at least the claim gives the lower bound. This is stronger than returning the
result of a greedy pass without a witness.

`CompleteGraphEdgeColoring` checks a finite symmetric color matrix and finds a
monochromatic triangle. `TriangleRamseyAudit` can exhaust every coloring only
under an explicit `coloring_limit`; a completed bounded exhaustion is an exact
finite Ramsey certificate, not an asymptotic Ramsey theorem.

Missing graph layers include canonical sparse storage, graph/hypergraph
homomorphisms, extremal-number objects, graph limits, flag algebras, and
probabilistic-family certificates.

## Binary and spherical codes

`BinaryBlockCode` validates a finite set of distinct binary words and computes
exact pairwise distances, the minimum distance, Hamming-ball volume, and the
normalized distance distribution

```text
A_i = |C|^-1 |{(x,y) in C^2 : d(x,y)=i}|.
```

`Krawtchouk.binary(k, i, n)` evaluates the binary Krawtchouk polynomial with
integer arithmetic. `delsarte_transform(k)` computes

```text
sum_i A_i K_k(i),
```

and `delsarte_feasible?` replays nonnegativity for every degree. This checks
the association-scheme inequalities for a supplied finite code; it does not
solve the Delsarte LP, prove the MRRW bound, or take an asymptotic rate limit.

`ConstantNormCode` handles distinct integer-coordinate vectors, checks their
common squared norm, and returns the exact maximum normalized inner product as
a `Rational`. General exact algebraic coordinates, semidefinite hierarchies,
and rigorous angular optimization remain future layers.

## Trust boundary

These classes use `exact` or `certified` in the terminology of
[`mathematics.md`](mathematics.md). They provide no Lean proof object. A future
Lean bridge should identify a named theorem and a pinned kernel-checked
artifact separately from these finite replay certificates.
