# Exporting the parity contradiction

The SC2025 Tseitin instances put an XOR equation at every vertex. Each edge
variable occurs twice. In a connected component with odd total charge, adding
the vertex equations yields an impossible parity. Wassat's structural
certificate command now exports the component selected by its existing
recognizer and proves this contradiction from the original DIMACS clauses.

For a row of width $k$, let $S$ be its number of true bits and $r$ its
required parity. Introduce a fresh Boolean for each threshold $r+2,r+4,\ldots$
up to $k$. The equality $S=r+2\sum z$ has two directions. Wassat proves
each by a local case split on at most four input bits. The input clauses fix the
last bit and the threshold definitions fix the auxiliary variables. It sums
the lower and upper bounds separately across the component and divides each
by two. All variable coefficients are even and the total charge is odd. The
two rounding steps give a contradiction. A support on which every assignment
is forbidden has a direct case-split proof.

| SC2025 input | Generate | Verify | Certificate |
|---|---:|---:|---:|
| 188-vertex cubic graph | 0.008 s | 0.076 s | 104,618 B |
| 12 × 12 grid | 0.014 s | 0.014 s | 139,532 B |
| 100,000-vertex cubic graph | 0.364 s | 2.554 s | 66,443,646 B |
| 250 × 250 grid | 0.414 s | 2.384 s | 88,322,424 B |
| 400 × 400 grid | 1.109 s | 7.341 s | 235,522,590 B |

These are single end-to-end observations with the native release. VeriPB
3.0.2 reported unconditional UNSAT on all five original inputs. On the largest
grid Wassat peaked at 1.30 GB RSS and VeriPB at 2.05 GB. The checker took
longer than proof generation on each of the three large inputs.
[Measurements and proof hashes](../../../build/wassat-parity-pb-20261118/competition.json)

Twenty independent controls varied the row width from one to five, the
component charge, and the presence of a single input clause. Satisfiable
controls returned UNKNOWN. Every generated refutation passed VeriPB.
The exporter currently covers complete local XOR truth tables. Exact
cardinalities implied by other clause encodings still use the trusted lane.
[Controls](../../../build/wassat-parity-pb-20261118/semantic-controls.json)
