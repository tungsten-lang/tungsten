# A direct four-color Ramsey construction

A clean algebraic construction gives a coloring of the edges of the complete
32-vertex graph with four colors and no monochromatic triangle. Restricting it
to 30 vertices also works. This is an input-derived construction, with no stored
competition witness. It is not yet integrated into Wassat or replayed on an
original competition file.

Work in GF(16), represented by four-bit polynomials modulo `t^4 + t + 1`.
Addition is XOR. The nonzero elements split into these multiplicative cosets of
an order-five subgroup:

- `{1, 8, 10, 12, 15}`
- `{2, 3, 7, 11, 13}`
- `{4, 5, 6, 9, 14}`

Each set is sum-free: the XOR of any two distinct members is outside that set.
All 30 pair checks pass. Color the edge between distinct field elements `a,b`
by the set containing `a XOR b`. A monochromatic triangle would give three
members `x,y,z` of one set with `x XOR y = z`, contradicting sum-freeness.
This gives a three-color triangle-free complete graph on 16 vertices.

Replace each vertex by two vertices. Give their internal edge a fourth color;
color edges between two pairs by the original field coloring. A triangle in
three different pairs inherits a nonmonochromatic field triangle. A triangle
in two pairs has both the fourth color and an original color. A triangle
cannot lie within one two-vertex pair.

For vertex IDs `i,j` in `0..31`, the construction is therefore:

```text
if i // 2 == j // 2:
  color = 3
else:
  color = coset_index[(i // 2) XOR (j // 2)]
```

Independent verification checked all 4,060 triangles on 30 vertices and all
4,960 on 32 vertices. It also constructed and checked every clause of two
representative encodings:

| Vertices | Variables | Clauses | Complete model |
|---:|---:|---:|---|
| 30 | 37,410 | 162,400 | Valid |
| 32 | 45,632 | 198,400 | Valid |

Those encodings use two bits per edge, guarded XOR witnesses for pairwise
color differences, and a three-way difference clause for every triangle.
Their dimensions match the family described in LymphoSAT's four-color Ramsey
worker. Matching dimensions does not establish equivalence to an original file.

To use this in Wassat, recover the actual edge/triangle incidence and bit
interpretation, map the construction into that graph, lift auxiliaries, and
check every original clause. For renamed complete graphs, large vertex-star
cliques in the edge-incidence graph can recover the underlying vertices.
Additional constraints or different gadget semantics can invalidate a candidate;
full original-CNF model validation remains necessary.

Reproduction: `build/lymphosat-specialist-audit-20261117/probes/83-field-construction.py`.
Evidence: `build/lymphosat-specialist-audit-20261117/83-field-product-construction.json`.
Full representative formulas and models: `build/lymphosat-specialist-audit-20261117/83-construction/`.
