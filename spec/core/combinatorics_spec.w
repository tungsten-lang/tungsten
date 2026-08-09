# Exact finite graph and coding-theory foundations.
# Run in both engines:
#   bin/tungsten run spec/core/combinatorics_spec.w
#   bin/tungsten compile spec/core/combinatorics_spec.w \
#     --out /tmp/combinatorics-spec --no-lto

use combinatorics

-> combinatorics_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> same_values?(left, right)
  return false if left.size != right.size
  i = 0
  while i < left.size
    return false if left[i] != right[i]
    i += 1
  true

combinatorics_check("binomial", Combinatorics.binomial(8, 3) == 56)
combinatorics_check("krawtchouk.endpoint",
                    Krawtchouk.binary(2, 0, 4) == 6)
combinatorics_check("krawtchouk.middle",
                    Krawtchouk.binary(2, 2, 4) == -2)

c4 = FiniteSimpleGraph.new([
  [0, 1, 0, 1],
  [1, 0, 1, 0],
  [0, 1, 0, 1],
  [1, 0, 1, 0]])
combinatorics_check("graph.order", c4.order == 4)
combinatorics_check("graph.edges", c4.edge_count == 4)
combinatorics_check("graph.connected", c4.connected?)
combinatorics_check("graph.bipartite", c4.bipartite?)
combinatorics_check("graph.cyclic", !c4.acyclic?)
combinatorics_check("graph.triangle_free", c4.triangle_free?)
certificate = c4.degeneracy_certificate
combinatorics_check("graph.degeneracy", certificate.claimed_degeneracy == 2)
combinatorics_check("graph.degeneracy_certificate", certificate.verified?)

k3 = FiniteSimpleGraph.new([
  [0, 1, 1],
  [1, 0, 1],
  [1, 1, 0]])
combinatorics_check("graph.triangle", same_values?(k3.triangle, [0, 1, 2]))
combinatorics_check("graph.nonbipartite", !k3.bipartite?)

one_color = TriangleRamseyAudit.every_coloring_forces_triangle?(3, 1)
combinatorics_check("ramsey.forced", one_color[0])
combinatorics_check("ramsey.exhausted", one_color[1] == 1)

# Red cycle and blue complement: a triangle-free two-coloring of K5.
k5 = []
5.times ->
  row = []
  5.times -> row.push(-1)
  k5.push(row)
i = 0
while i < 5
  j = i + 1
  while j < 5
    cycle_edge = j == i + 1 || (i == 0 && j == 4)
    color = cycle_edge ? 0 : 1
    k5[i][j] = color
    k5[j][i] = color
    j += 1
  i += 1
coloring = CompleteGraphEdgeColoring.new(k5, 2)
combinatorics_check("ramsey.k5_witness", coloring.triangle_free?)

repetition = BinaryBlockCode.new([[0, 0, 0], [1, 1, 1]])
combinatorics_check("code.length", repetition.length == 3)
combinatorics_check("code.minimum_distance", repetition.minimum_distance == 3)
combinatorics_check("code.distance_certificate",
                    repetition.minimum_distance_certificate.verified?)
distribution = repetition.distance_distribution
combinatorics_check("code.distance_distribution",
                    same_values?(distribution,
                                 [Rational.new(1), Rational.new(0),
                                  Rational.new(0), Rational.new(1)]))
combinatorics_check("code.delsarte", repetition.delsarte_feasible?)
combinatorics_check("code.delsarte.degree2",
                    repetition.delsarte_transform(2) == Rational.new(6))
combinatorics_check("code.hamming_bound", repetition.hamming_bound_holds?)

cross = ConstantNormCode.new([[1, 0], [0, 1], [-1, 0], [0, -1]])
combinatorics_check("spherical.constant_norm", cross.constant_norm?)
combinatorics_check("spherical.maximum_inner_product",
                    cross.maximum_inner_product_ratio == Rational.new(0))
combinatorics_check("spherical.bound",
                    cross.certifies_maximum_inner_product?(Rational.new(0)))

<< "combinatorics_spec: all checks passed"
