# The discrete skeleton of "The (3,4,oo) modular family of 2-tori, completed
# at its three special points, is a complex structure on S^6"
# (https://alpo.ge/s6.pdf): the rank-four lattice representation of the
# triangle group, its Smith normal forms, the van Kampen presentation of
# pi_1(X), the Mayer-Vietoris linear algebra for the toric central fibre W,
# and the Seifert-fibration reading of |pi_1(X)| = |12 l0 - 4 l1 - 3 l2|.
#
#   bin/tungsten run spec/core/s6_lattice_spec.w
#
# Everything here is integer linear algebra, so it is a check on the paper's
# bookkeeping (Lemma 2.2, 2.4, 2.7, Theorem 7.17, Lemma A.3, A.4, Appendix
# A.1) — not on its analytic content.

use algebra

-> s6_check(name, cond)
  raise "FAIL " + name if !cond
  << "PASS " + name

-> same?(a, b)
  return a == b if a.class_name != "Array"
  SmithNormalForm.same_vector?(a, b)

-> same_matrix?(a, b)
  SmithNormalForm.same_matrix?(a, b)

-> power(m, k)
  out = SmithNormalForm.identity(m.size)
  i = 0
  while i < k
    out = SmithNormalForm.multiply(out, m)
    i += 1
  out

-> minus_identity(m)
  SmithNormalForm.subtract_identity(m)

-> negate(v)
  out = []
  v.each ->(x)
    out.push(0 - x)
  out

# ---------------------------------------------------------------------------
# Setup (page 2, Appendix A.1): V = Z^4 with basis (gamma, u, w, delta),
# columns are images.

identity4 = SmithNormalForm.identity(4)
t1 = [[1, 0, -6, 2], [0, -1, 1, 1], [0, -1, 0, 1], [0, 0, 0, 1]]
t2 = [[1, 6, 0, -3], [0, 0, -1, 1], [0, 1, 0, 0], [0, 0, 0, 1]]

# --- Lemma 2.2 ---
s6_check("lemma2.2.det_t1", ExactIntegerLinearAlgebra.determinant(t1) == 1)
s6_check("lemma2.2.det_t2", ExactIntegerLinearAlgebra.determinant(t2) == 1)
s6_check("lemma2.2.t1_order_3", same_matrix?(power(t1, 3), identity4) && !same_matrix?(t1, identity4))
s6_check("lemma2.2.t2_order_4", same_matrix?(power(t2, 4), identity4) && !same_matrix?(power(t2, 2), identity4))

t1_inverse = power(t1, 2)
t2_inverse = power(t2, 3)
t0 = SmithNormalForm.multiply(t2_inverse, t1_inverse)
t0_expected = [[1, 0, 0, 1], [0, 1, -1, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
s6_check("lemma2.2.t0", same_matrix?(t0, t0_expected))
s6_check("lemma2.2.t1_t2_t0", same_matrix?(SmithNormalForm.multiply(SmithNormalForm.multiply(t1, t2), t0), identity4))
n = minus_identity(t0)
zero4 = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]
s6_check("lemma2.2.n_squared_zero", same_matrix?(SmithNormalForm.multiply(n, n), zero4))
# N gamma = N u = 0, N w = -u, N delta = gamma
s6_check("lemma2.2.n_action", same?(SmithNormalForm.column(n, 0), [0, 0, 0, 0]) && same?(SmithNormalForm.column(n, 1), [0, 0, 0, 0]) && same?(SmithNormalForm.column(n, 2), [0, -1, 0, 0]) && same?(SmithNormalForm.column(n, 3), [1, 0, 0, 0]))
n_decomposition = SmithNormalForm.decompose(n)
s6_check("lemma2.2.ker_n_eq_im_n", n_decomposition.rank == 2 && n_decomposition.in_kernel?([1, 0, 0, 0]) && n_decomposition.in_kernel?([0, 1, 0, 0]))

# --- Lemma 2.4: A(T) = (T^-1)^t on the dual lattice Lambda ---
a1 = SmithNormalForm.transpose(t1_inverse)
a2 = SmithNormalForm.transpose(t2_inverse)
m0 = SmithNormalForm.transpose(SmithNormalForm.multiply(t1, t2))
s6_check("lemma2.4.a1", same_matrix?(a1, [[1, 0, 0, 0], [6, 0, 1, 0], [-6, -1, -1, 0], [-2, 1, 0, 1]]))
s6_check("lemma2.4.a2", same_matrix?(a2, [[1, 0, 0, 0], [0, 0, -1, 0], [-6, 1, 0, 0], [3, 0, 1, 1]]))
s6_check("lemma2.4.m0", same_matrix?(m0, [[1, 0, 0, 0], [0, 1, 0, 0], [0, 1, 1, 0], [-1, 0, 0, 1]]))
i_minus_nt = SmithNormalForm.copy(identity4)
i = 0
while i < 4
  j = 0
  while j < 4
    i_minus_nt[i][j] = i_minus_nt[i][j] - n[j][i]
    j += 1
  i += 1
s6_check("lemma2.4.m0_is_i_minus_nt", same_matrix?(m0, i_minus_nt))
s6_check("lemma2.4.a1_a2_m0", same_matrix?(SmithNormalForm.multiply(SmithNormalForm.multiply(a1, a2), m0), identity4))
# gamma o A_j = gamma: the first row of each is (1, 0, 0, 0).
s6_check("lemma2.4.gamma_invariant", same?(a1[0], [1, 0, 0, 0]) && same?(a2[0], [1, 0, 0, 0]) && same?(m0[0], [1, 0, 0, 0]))

# --- Lemma 2.7: coinvariants and invariants ---
coinvariants_v = SmithNormalForm.decompose(SmithNormalForm.augment(minus_identity(t1), minus_identity(t2)))
coinvariants_l = SmithNormalForm.decompose(SmithNormalForm.augment(minus_identity(a1), minus_identity(a2)))
s6_check("lemma2.7.snf_v", same?(coinvariants_v.invariant_factors, [1, 1, 1]) && coinvariants_v.certified?)
s6_check("lemma2.7.snf_lambda", same?(coinvariants_l.invariant_factors, [1, 1, 1]) && coinvariants_l.certified?)
s6_check("lemma2.7.coinvariants_z", coinvariants_l.cokernel == FinitelyGeneratedAbelianGroup.free(1))
# The coinvariants Lambda / ker gamma are detected by gamma alone.
functional = coinvariants_l.cokernel_functionals[0]
s6_check("lemma2.7.detected_by_gamma", same?(functional, [1, 0, 0, 0]) || same?(functional, [-1, 0, 0, 0]))
s6_check("lemma2.7.image_is_ker_gamma", coinvariants_l.image_saturated? && coinvariants_l.in_image?([0, 1, 0, 0]) && coinvariants_l.in_image?([0, 0, 1, 0]) && coinvariants_l.in_image?([0, 0, 0, 1]) && !coinvariants_l.in_image?([1, 0, 0, 0]))
gamma_hat_class = coinvariants_l.cokernel_class([1, 0, 0, 0])
s6_check("lemma2.7.gamma_hat_generates", gamma_hat_class.size == 1 && (gamma_hat_class[0] == 1 || gamma_hat_class[0] == -1))
# Invariants in V: V^T1 = <gamma, 2u + w + 3delta>, V^T2 = <gamma, u + w + 2delta>.
fixed_t1 = SmithNormalForm.decompose(minus_identity(t1))
fixed_t2 = SmithNormalForm.decompose(minus_identity(t2))
s6_check("lemma2.7.v_t1_fixed", fixed_t1.kernel_rank == 2 && fixed_t1.in_kernel?([1, 0, 0, 0]) && fixed_t1.in_kernel?([0, 2, 1, 3]))
s6_check("lemma2.7.v_t2_fixed", fixed_t2.kernel_rank == 2 && fixed_t2.in_kernel?([1, 0, 0, 0]) && fixed_t2.in_kernel?([0, 1, 1, 2]))

# --- Appendix A.1: Lambda_tor, B0, epsilon, epsilon' ---
epsilon = [1, 2, -4, 0]
epsilon_prime = [1, 3, -3, 0]
fixed_a1 = SmithNormalForm.decompose(minus_identity(a1))
fixed_a2 = SmithNormalForm.decompose(minus_identity(a2))
s6_check("A.1.epsilon_fixed_by_a1", fixed_a1.kernel_rank == 2 && fixed_a1.in_kernel?(epsilon))
s6_check("A.1.epsilon_prime_fixed_by_a2", fixed_a2.kernel_rank == 2 && fixed_a2.in_kernel?(epsilon_prime))
s6_check("A.1.epsilon_prime_not_fixed_by_a1", !fixed_a1.in_kernel?(epsilon_prime))
cusp = SmithNormalForm.decompose(minus_identity(m0))
s6_check("A.1.snf_m0_minus_i", same?(cusp.invariant_factors, [1, 1]) && cusp.certified?)
# Lambda_tor = <w^, delta^> is the image of M0 - I, a saturated rank-two sublattice.
s6_check("A.1.lambda_tor", cusp.image_saturated? && cusp.in_image?([0, 0, 1, 0]) && cusp.in_image?([0, 0, 0, 1]) && !cusp.in_image?([0, 1, 0, 0]))
# B0: gamma^ -> -delta^, u^ -> w^.
s6_check("A.1.b0", same?(SmithNormalForm.column(minus_identity(m0), 0), [0, 0, 0, -1]) && same?(SmithNormalForm.column(minus_identity(m0), 1), [0, 0, 1, 0]))
# (A_j - I) Lambda is contained in ker gamma, and gamma(v1) = 1, gamma(v2) = -1.
v1 = epsilon
v2 = negate(epsilon_prime)
s6_check("A.1.ell", v1[0] == 1 && v2[0] == -1)

# ---------------------------------------------------------------------------
# Lemma A.4: H_1(S_j) for the log-transform fillings, from the presentation
#   Gamma_j = < Lambda, g | g lambda g^-1 = A_j lambda, g^m_j = t_v_j >.

-> filling_group(a, m, v)
  relators = []
  k = 0
  while k < 4
    word = [[k, 1]]
    i = 0
    while i < 4
      word.push([i, 0 - a[i][k]])
      i += 1
    relators.push(word)
    k += 1
  word = [[4, m]]
  i = 0
  while i < 4
    word.push([i, 0 - v[i]])
    i += 1
  relators.push(word)
  FinitelyPresentedGroup.new(5, relators)

s1 = filling_group(a1, 3, v1)
s2 = filling_group(a2, 4, v2)
s6_check("A.4.h1_s1_free_rank_2", s1.abelianization == FinitelyGeneratedAbelianGroup.free(2))
s6_check("A.4.h1_s2_free_rank_2", s2.abelianization == FinitelyGeneratedAbelianGroup.free(2))
s6_check("A.4.h1_s2_prime_torsion_free_too", filling_group(a2, 4, epsilon_prime).abelianization == FinitelyGeneratedAbelianGroup.free(2))

# ---------------------------------------------------------------------------
# Theorem 7.17: pi_1(X) = < c, x, y | c central, x y = c^l0, x^3 = c^l1,
# y^4 = c^l2 > = Z / |12 l0 - 4 l1 - 3 l2|, as the Seifert fibration over
# S^2(3, 4) with invariants (3, -l1), (4, -l2) and obstruction l0.

-> paper_order(l0, l1, l2)
  p = 12 * l0 - 4 * l1 - 3 * l2
  p < 0 ? 0 - p : p

x_group = SeifertFibration.new(0, [[3, -1], [4, 1]])
s6_check("thm7.17.x_simply_connected_abelianisation", x_group.first_homology.trivial?)
s6_check("thm7.17.x_prime_z7", SeifertFibration.new(0, [[3, -1], [4, -1]]).first_homology == FinitelyGeneratedAbelianGroup.cyclic(7))
# The presentation written out as in the theorem, generators c = 0, x = 1, y = 2.
-> theorem_group(l0, l1, l2)
  FinitelyPresentedGroup.new(3, [
    FinitelyPresentedGroup.commutator(0, 1),
    FinitelyPresentedGroup.commutator(0, 2),
    [[1, 1], [2, 1], [0, 0 - l0]],
    [[1, 3], [0, 0 - l1]],
    [[2, 4], [0, 0 - l2]]])

all_match = true
all_cyclic = true
l0 = -2
while l0 <= 2
  l1 = -2
  while l1 <= 2
    l2 = -2
    while l2 <= 2
      fibration = SeifertFibration.new(l0, [[3, 0 - l1], [4, 0 - l2]])
      expected = paper_order(l0, l1, l2)
      group = theorem_group(l0, l1, l2).abelianization
      all_match = false if fibration.first_homology_order != expected
      all_match = false if fibration.first_homology_order_formula != expected
      all_match = false if group.order != expected
      all_cyclic = false if !group.cyclic?
      l2 += 1
    l1 += 1
  l0 += 1
s6_check("thm7.17.orlik_formula_grid", all_match)
s6_check("thm7.17.abelianisation_cyclic_grid", all_cyclic)
s6_check("thm7.17.gcd_p_12", paper_order(0, 1, -1).gcd(12) == 1 && paper_order(0, 1, 1).gcd(12) == 1)
# The S^3 heuristic: (z, w) -> (l^3 z, l^4 w) is the Seifert fibration with
# obstruction 0 and invariants (3, -1), (4, 1); its total space is S^3.
s6_check("thm7.17.s3_seifert", SeifertFibration.three_sphere(3, 4).homology_sphere? && x_group.homology_sphere?)
s6_check("thm7.17.euler_number", same?(x_group.euler_number, [-1, 12]))

# The van Kampen presentation before simplification (proof of Theorem 7.17):
#   < Lambda, r1, r2 | r_j lambda r_j^-1 = A_j lambda, r_j^m_j = t_v_j,
#     r1 r2 = t_mu, Lambda_tor = 1 >,  l0 = gamma(mu).
-> van_kampen_group(mu, w1, w2)
  relators = []
  matrices = [a1, a2]
  j = 0
  while j < 2
    k = 0
    while k < 4
      word = [[k, 1]]
      i = 0
      while i < 4
        word.push([i, 0 - matrices[j][i][k]])
        i += 1
      relators.push(word)
      k += 1
    j += 1
  word = [[4, 3]]
  i = 0
  while i < 4
    word.push([i, 0 - w1[i]])
    i += 1
  relators.push(word)
  word = [[5, 4]]
  i = 0
  while i < 4
    word.push([i, 0 - w2[i]])
    i += 1
  relators.push(word)
  word = [[4, 1], [5, 1]]
  i = 0
  while i < 4
    word.push([i, 0 - mu[i]])
    i += 1
  relators.push(word)
  relators.push([[2, 1]])
  relators.push([[3, 1]])
  FinitelyPresentedGroup.new(6, relators)

van_kampen_ok = true
l0 = -2
while l0 <= 2
  mu = [l0, 1, -2, 3]
  van_kampen_ok = false if van_kampen_group(mu, v1, v2).abelian_order != paper_order(l0, 1, -1)
  van_kampen_ok = false if van_kampen_group(mu, v1, epsilon_prime).abelian_order != paper_order(l0, 1, 1)
  l0 += 1
s6_check("thm7.17.van_kampen_abelianisation", van_kampen_ok)

# ---------------------------------------------------------------------------
# Section 4 / Appendix A.2: the cusp filling. The A2 triangulation modulo
# the lattice has one vertex, three edges, two triangles; the star fan is the
# hexagonal fan of dP6, so W is one dP6 glued to itself with two triple
# points and e(W) = 2.

a2_triangulation = LatticeTriangulation.a2
s6_check("A.2.cells_mod_lattice", a2_triangulation.vertex_count == 1 && a2_triangulation.edge_count == 3 && a2_triangulation.triangle_count == 2)
s6_check("A.2.torus_euler_zero", a2_triangulation.euler_characteristic == 0 && a2_triangulation.unimodular?)
hexagon = a2_triangulation.star_fan
s6_check("A.2.star_fan_smooth_hexagon", hexagon.smooth? && hexagon.ray_count == 6 && hexagon.euler_number == 6)
s6_check("A.2.six_minus_one_curves", same?(hexagon.self_intersections, [-1, -1, -1, -1, -1, -1]))
s6_check("A.2.del_pezzo_degree_six", hexagon.del_pezzo? && hexagon.degree == 6 && hexagon.picard_rank == 4 && hexagon.noether?)
# e(W) = e(dP6) - e(hexagon of six P^1) + e(three double curves through two
# triple points) = 6 - 6 + 2 = 2, one torus-fixed point per triangle class.
e_hexagon = 2 * hexagon.ray_count - hexagon.ray_count
e_double_curves = 2 * a2_triangulation.double_curve_count - 2 * a2_triangulation.triple_point_count
s6_check("A.2.euler_w", hexagon.euler_number - e_hexagon + e_double_curves == 2 && a2_triangulation.central_fibre_euler_number == 2)
# Sanity on the fan calculus around it.
s6_check("fan.p2", same?(ToricFan2D.projective_plane.self_intersections, [1, 1, 1]) && ToricFan2D.projective_plane.degree == 9)
s6_check("fan.f2_not_fano", !ToricFan2D.hirzebruch(2).fano? && ToricFan2D.hirzebruch(2).noether?)
s6_check("fan.p1xp1", ToricFan2D.hirzebruch(0).degree == 8)

# ---------------------------------------------------------------------------
# Lemma A.3: H_*(W) by Mayer-Vietoris. The degree-two map
#   H_2(dP6) (+) H_2(D-bar) -> H_2(D), Z^4 (+) Z^3 -> Z^6,
# with D = aH - b1 E1 - b2 E2 - b3 E3 and the hexagon C1 = E1,
# C2 = H - E1 - E2, C3 = E2, C4 = H - E2 - E3, C5 = E3, C6 = H - E3 - E1,
# opposite pairs {C_i, C_(i+3)} glued: rank 4, kernel free of rank 3,
# cokernel Z^2. Hence H_*(W) = (Z, Z^2, Z^4, Z^2, Z) and e(W) = 2.

mayer_vietoris = [
  [0, 1, 0, 0, -1, 0, 0],
  [1, -1, -1, 0, 0, -1, 0],
  [0, 0, 1, 0, 0, 0, -1],
  [1, 0, -1, -1, -1, 0, 0],
  [0, 0, 0, 1, 0, -1, 0],
  [1, -1, 0, -1, 0, 0, -1]]
mv = SmithNormalForm.decompose(mayer_vietoris)
s6_check("A.3.rank_4", mv.rank == 4 && mv.certified?)
s6_check("A.3.kernel_rank_3", mv.kernel_rank == 3)
s6_check("A.3.cokernel_z2", mv.cokernel == FinitelyGeneratedAbelianGroup.free(2))
# The intersection-form summand alone is injective (unimodular form).
form_part = SmithNormalForm.decompose([[0, 1, 0, 0], [1, -1, -1, 0], [0, 0, 1, 0], [1, 0, -1, -1], [0, 0, 0, 1], [1, -1, 0, -1]])
s6_check("A.3.form_injective", form_part.rank == 4)
h_w = [1, 0 + 2, 1 + mv.kernel_rank, mv.cokernel_free_rank, 1]
s6_check("A.3.homology_w", same?(h_w, [1, 2, 4, 2, 1]))
e_w = h_w[0] - h_w[1] + h_w[2] - h_w[3] + h_w[4]
s6_check("A.3.euler_w_matches_toric", e_w == a2_triangulation.central_fibre_euler_number)

# ---------------------------------------------------------------------------
# Theorem 7.22: H_*(X; Z) = (Z, Z/p, Z/p, Z/p, Z/p, 0, Z), e(X) = 2. The
# chain-complex machinery on a minimal CW model with that homology — a
# consistency check that e(X) = 2 is forced by the homology, and that p = 1
# makes X a homology 6-sphere.

-> x_model(p)
  IntegerChainComplex.new([1, 1, 2, 2, 2, 1, 1], [[[0]], [[p, 0]], [[0, 0], [p, 0]], [[0, 0], [p, 0]], [[0], [p]], [[0]]])

x7 = x_model(7)
z7 = FinitelyGeneratedAbelianGroup.cyclic(7)
s6_check("thm7.22.x_prime_homology", x7.homology(1) == z7 && x7.homology(2) == z7 && x7.homology(3) == z7 && x7.homology(4) == z7 && x7.homology(5).trivial? && x7.homology(6) == FinitelyGeneratedAbelianGroup.free(1))
s6_check("thm7.22.euler_two", x7.euler_characteristic == 2 && x7.betti_euler_characteristic == 2 && x7.certified?)
s6_check("thm7.22.homology_sphere", x_model(1).homology_sphere?(6) && !x7.homology_sphere?(6))
s6_check("chain.standard_spaces", IntegerChainComplex.torus.homology(1) == FinitelyGeneratedAbelianGroup.free(2) && IntegerChainComplex.klein_bottle.homology(1) == FinitelyGeneratedAbelianGroup.new(1, [2]) && IntegerChainComplex.projective_plane.homology(2).trivial? && IntegerChainComplex.lens_space(5).homology(1) == FinitelyGeneratedAbelianGroup.cyclic(5))
s6_check("chain.poincare_sphere_perfect", SeifertFibration.poincare_sphere.fundamental_group.perfect?)

# ---------------------------------------------------------------------------
# Section 3.1: the classical facts the period map rests on — E4, E6, Delta
# with E4^3 - E6^2 = 1728 Delta, Delta = q + O(q^2).

e4 = ClassicalModularForms.e4(8)
e6 = ClassicalModularForms.e6(8)
delta = ClassicalModularForms.delta(8)
difference = e4.q_expansion ** 3 - e6.q_expansion ** 2
s6_check("3.1.classical_forms_certified", e4.certified? && e6.certified? && delta.certified?)
s6_check("3.1.e4_cubed_minus_e6_squared", difference.coefficient(0) == 0 && difference.coefficient(1) == 1728 && difference.coefficient(2) == 1728 * delta.coefficient(2))
s6_check("3.1.delta_leading_term", delta.coefficient(0) == 0 && delta.coefficient(1) == 1 && delta.coefficient(2) == -24)

<< "s6 lattice complete"
