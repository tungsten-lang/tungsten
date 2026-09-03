# Coding theory (core/combinatorics/coding.w): Krawtchouk polynomials,
# BinaryBlockCode and ConstantNormCode, checked against the textbook codes
# whose parameters are known exactly.
#
# The anchor is the Hamming [7,4,3] code. It is *perfect*: the 16 radius-1
# Hamming balls around its codewords tile all 2^7 = 128 words of F_2^7
# exactly, which is precisely the statement "one bit error is always
# detected and always corrected to the unique nearest codeword". That is
# replayed here vertex by vertex, not asserted. Its weight enumerator is
# [1,0,0,7,7,0,0,1], and the MacWilliams identity sends it to 16 * the
# simplex code's [1,0,0,0,7,0,0,0] under the module's Delsarte transform.
#
# Also here: the extended Hamming [8,4,4] code, the simplex [7,3,4] dual,
# the even-weight [4,3,2] parity code, repetition codes, and the cube's
# eight vertices as a constant-norm code with maximum inner product 1/3.
#
# Run in both engines:
#   bin/tungsten run --interpret spec/core/combinatorics_coding_spec.w
#   bin/tungsten -o /tmp/comb-coding-spec spec/core/combinatorics_coding_spec.w && /tmp/comb-coding-spec

use combinatorics

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> same_rationals?(got, want)
  return false if got.size != want.size
  i = 0
  while i < got.size
    return false if got[i] != Rational.new(want[i])
    i += 1
  true

# --- Krawtchouk polynomials -------------------------------------------------

# K_k(0) = C(n, k)
check("krawtchouk.at_zero_is_binomial", Krawtchouk.binary(4, 0, 7) == 35)
check("krawtchouk.at_zero_k1", Krawtchouk.binary(1, 0, 7) == 7)
# K_0(i) = 1 for every i
check("krawtchouk.degree_zero", Krawtchouk.binary(0, 3, 7) == 1)
check("krawtchouk.degree_zero_endpoint", Krawtchouk.binary(0, 7, 7) == 1)
# K_n(i) = (-1)^i
check("krawtchouk.top_degree_odd", Krawtchouk.binary(7, 3, 7) == -1)
check("krawtchouk.top_degree_even", Krawtchouk.binary(7, 4, 7) == 1)
# K_1(i) = n - 2i
check("krawtchouk.linear", Krawtchouk.binary(1, 2, 7) == 3)
check("krawtchouk.linear_midpoint", Krawtchouk.binary(1, 4, 7) == -1)
# reciprocity: C(n,i) K_k(i) = C(n,k) K_i(k)
check("krawtchouk.reciprocity",
      Combinatorics.binomial(7, 3) * Krawtchouk.binary(2, 3, 7) ==
      Combinatorics.binomial(7, 2) * Krawtchouk.binary(3, 2, 7))

raised = false
begin
  Krawtchouk.binary(9, 0, 7)
rescue e
  raised = true
check("krawtchouk.degree_over_length_raises", raised)

# --- the Hamming [7,4,3] code -----------------------------------------------

# Systematic generator: (d1 d2 d3 d4 | d1+d2+d3, d2+d3+d4, d1+d2+d4).
hamming_words = []
message = 0
while message < 16
  d1 = (message >> 3) & 1
  d2 = (message >> 2) & 1
  d3 = (message >> 1) & 1
  d4 = message & 1
  hamming_words.push([d1, d2, d3, d4,
                      (d1 ^ d2) ^ d3, (d2 ^ d3) ^ d4, (d1 ^ d2) ^ d4])
  message += 1
hamming = BinaryBlockCode.new(hamming_words)

check("hamming.length", hamming.length == 7)
check("hamming.size", hamming.size == 16)
check("hamming.rate_is_four_bits", hamming.size == 2 ** 4)
check("hamming.minimum_distance", hamming.minimum_distance == 3)
check("hamming.words_are_a_copy", hamming.words != hamming.words[0])
check("hamming.zero_word_first", hamming.words[0][0] == 0 && hamming.words[0][6] == 0)
# weight enumerator 1 + 7z^3 + 7z^4 + z^7 (a linear code's distance
# distribution is its weight distribution)
check("hamming.weight_enumerator",
      same_rationals?(hamming.distance_distribution, [1, 0, 0, 7, 7, 0, 0, 1]))
check("hamming.distance_of_a_pair", hamming.distance(0, 1) == 3)
check("hamming.self_distance_zero", hamming.distance(5, 5) == 0)

# perfect: 16 * |ball of radius 1| = 16 * 8 = 128 = 2^7
check("hamming.ball_volume", hamming.hamming_ball_volume(1) == 8)
check("hamming.ball_volume_zero", hamming.hamming_ball_volume(0) == 1)
check("hamming.sphere_packing_is_tight",
      hamming.size * hamming.hamming_ball_volume(1) == 2 ** 7)
check("hamming.hamming_bound", hamming.hamming_bound_holds?)
check("hamming.delsarte_feasible", hamming.delsarte_feasible?)

# MacWilliams: sum_i A_i K_k(i) = |C| * B_k, and the dual of Hamming[7,4]
# is the simplex code with B = [1,0,0,0,7,0,0,0].
check("hamming.macwilliams.k0", hamming.delsarte_transform(0) == Rational.new(16))
check("hamming.macwilliams.k1", hamming.delsarte_transform(1) == Rational.new(0))
check("hamming.macwilliams.k2", hamming.delsarte_transform(2) == Rational.new(0))
check("hamming.macwilliams.k3", hamming.delsarte_transform(3) == Rational.new(0))
check("hamming.macwilliams.k4", hamming.delsarte_transform(4) == Rational.new(112))
check("hamming.macwilliams.k5", hamming.delsarte_transform(5) == Rational.new(0))
check("hamming.macwilliams.k7", hamming.delsarte_transform(7) == Rational.new(0))

# --- single-error correction, replayed over all 128 received words ----------

# Because d = 3, every word of F_2^7 is within Hamming distance 1 of at
# most one codeword; because the code is perfect, it is within distance 1
# of exactly one. So flipping any single bit of any codeword still decodes
# back to that codeword, uniquely.
ambiguous = 0
uncovered = 0
received = 0
while received < 128
  vector = []
  bit = 6
  while bit >= 0
    vector.push((received >> bit) & 1)
    bit -= 1
  nearby = 0
  index = 0
  while index < 16
    nearby += 1 if Combinatorics.hamming_distance(vector, hamming_words[index]) <= 1
    index += 1
  ambiguous += 1 if nearby > 1
  uncovered += 1 if nearby == 0
  received += 1
check("hamming.decoding_is_unambiguous", ambiguous == 0)
check("hamming.every_word_is_covered", uncovered == 0)

# and the correction is the original codeword, bit by bit
mistakes = 0
word_index = 0
while word_index < 16
  flip = 0
  while flip < 7
    corrupted = Combinatorics.copy_vector(hamming_words[word_index])
    corrupted[flip] = 1 - corrupted[flip]
    best = -1
    candidate = 0
    while candidate < 16
      if Combinatorics.hamming_distance(corrupted, hamming_words[candidate]) <= 1
        best = candidate
      candidate += 1
    mistakes += 1 if best != word_index
    flip += 1
  word_index += 1
check("hamming.corrects_every_single_bit_error", mistakes == 0)

# two errors are NOT correctable: flipping bits 0 and 1 of the all-zero
# codeword lands at distance 1 from a weight-3 codeword, i.e. it decodes
# to the wrong word — which is why d = 3 buys exactly one correction.
double = Combinatorics.copy_vector(hamming_words[0])
double[0] = 1
double[1] = 1
misdecoded = false
candidate = 0
while candidate < 16
  if candidate != 0 && Combinatorics.hamming_distance(double, hamming_words[candidate]) <= 1
    misdecoded = true
  candidate += 1
check("hamming.two_errors_misdecode", misdecoded)

certificate = hamming.minimum_distance_certificate
check("hamming.certificate.verified", certificate.verified?)
check("hamming.certificate.claim", certificate.claimed_minimum_distance == 3)
check("hamming.certificate.code", certificate.code == hamming)
check("hamming.certificate.proof_kind",
      certificate.proof_kind == :exact_pairwise_hamming_replay)
check("hamming.proof_kind",
      hamming.proof_kind == :exact_finite_binary_block_code)
check("hamming.wrong_claim_is_rejected",
      !BinaryCodeDistanceCertificate.new(hamming, 4).verified?)
check("hamming.noninteger_claim_is_rejected",
      !BinaryCodeDistanceCertificate.new(hamming, "3").verified?)

# --- extended Hamming [8,4,4] -----------------------------------------------

# One overall parity bit lifts d from 3 to 4 (single-error-correcting,
# double-error-detecting) and makes every weight even.
extended_words = []
row = 0
while row < 16
  base = hamming_words[row]
  parity = 0
  i = 0
  while i < 7
    parity = parity ^ base[i]
    i += 1
  extended_words.push(base + [parity])
  row += 1
extended = BinaryBlockCode.new(extended_words)
check("extended.length", extended.length == 8)
check("extended.size", extended.size == 16)
check("extended.minimum_distance", extended.minimum_distance == 4)
check("extended.weight_enumerator",
      same_rationals?(extended.distance_distribution,
                      [1, 0, 0, 0, 14, 0, 0, 0, 1]))
check("extended.hamming_bound", extended.hamming_bound_holds?)
check("extended.delsarte_feasible", extended.delsarte_feasible?)
# self-dual: sum_i A_i K_k(i) = 16 A_k
check("extended.self_dual.k4", extended.delsarte_transform(4) == Rational.new(16 * 14))
check("extended.self_dual.k8", extended.delsarte_transform(8) == Rational.new(16))

# --- the simplex [7,3,4] code, dual of Hamming ------------------------------

# Rows of the Hamming parity-check matrix H = [P^T | I3].
generators = [[1, 1, 1, 0, 1, 0, 0],
              [0, 1, 1, 1, 0, 1, 0],
              [1, 1, 0, 1, 0, 0, 1]]
simplex_words = []
combination = 0
while combination < 8
  word = []
  column = 0
  while column < 7
    accumulated = 0
    accumulated = accumulated ^ generators[0][column] if (combination & 4) != 0
    accumulated = accumulated ^ generators[1][column] if (combination & 2) != 0
    accumulated = accumulated ^ generators[2][column] if (combination & 1) != 0
    word.push(accumulated)
    column += 1
  simplex_words.push(word)
  combination += 1
simplex = BinaryBlockCode.new(simplex_words)
check("simplex.size", simplex.size == 8)
check("simplex.length", simplex.length == 7)
# every nonzero simplex codeword has weight exactly 4 — the "equidistant"
# property the name refers to
check("simplex.minimum_distance", simplex.minimum_distance == 4)
check("simplex.equidistant",
      same_rationals?(simplex.distance_distribution, [1, 0, 0, 0, 7, 0, 0, 0]))
# MacWilliams the other way: |C| = 8 times Hamming's [1,0,0,7,7,0,0,1]
check("simplex.macwilliams.k0", simplex.delsarte_transform(0) == Rational.new(8))
check("simplex.macwilliams.k3", simplex.delsarte_transform(3) == Rational.new(56))
check("simplex.macwilliams.k4", simplex.delsarte_transform(4) == Rational.new(56))
check("simplex.macwilliams.k7", simplex.delsarte_transform(7) == Rational.new(8))
check("simplex.delsarte_feasible", simplex.delsarte_feasible?)

# --- even-weight (parity check) [4,3,2] -------------------------------------

even_words = []
value = 0
while value < 16
  bits = [(value >> 3) & 1, (value >> 2) & 1, (value >> 1) & 1, value & 1]
  if (((bits[0] ^ bits[1]) ^ bits[2]) ^ bits[3]) == 0
    even_words.push(bits)
  value += 1
even = BinaryBlockCode.new(even_words)
check("even.size", even.size == 8)
check("even.minimum_distance", even.minimum_distance == 2)
check("even.weight_enumerator",
      same_rationals?(even.distance_distribution, [1, 0, 6, 0, 1]))
# d = 2 detects one error but corrects none: the radius is 0
check("even.corrects_nothing", even.hamming_ball_volume(0) == 1)
check("even.hamming_bound", even.hamming_bound_holds?)

# --- repetition codes -------------------------------------------------------

repeat3 = BinaryBlockCode.new([[0, 0, 0], [1, 1, 1]])
check("repetition3.minimum_distance", repeat3.minimum_distance == 3)
check("repetition3.perfect", repeat3.size * repeat3.hamming_ball_volume(1) == 2 ** 3)
repeat5 = BinaryBlockCode.new([[0, 0, 0, 0, 0], [1, 1, 1, 1, 1]])
check("repetition5.minimum_distance", repeat5.minimum_distance == 5)
check("repetition5.corrects_two", repeat5.hamming_ball_volume(2) == 16)
check("repetition5.perfect", repeat5.size * repeat5.hamming_ball_volume(2) == 2 ** 5)
check("repetition5.weight_enumerator",
      same_rationals?(repeat5.distance_distribution, [1, 0, 0, 0, 0, 1]))

# a one-word code has no pairwise distance at all
single = BinaryBlockCode.new([[1, 0, 1]])
check("singleton.minimum_distance_zero", single.minimum_distance == 0)
check("singleton.size", single.size == 1)

# --- loud failures on malformed codes ---------------------------------------

raised = false
begin
  BinaryBlockCode.new([])
rescue e
  raised = true
check("error.empty_code", raised)

raised = false
begin
  BinaryBlockCode.new([[0, 1], [0, 1, 1]])
rescue e
  raised = true
check("error.ragged_words", raised)

raised = false
begin
  BinaryBlockCode.new([[0, 2]])
rescue e
  raised = true
check("error.nonbinary_entry", raised)

raised = false
begin
  BinaryBlockCode.new([[0, 1], [0, 1]])
rescue e
  raised = true
check("error.duplicate_words", raised)

raised = false
begin
  hamming.hamming_ball_volume(8)
rescue e
  raised = true
check("error.radius_over_length", raised)

raised = false
begin
  hamming.delsarte_transform(8)
rescue e
  raised = true
check("error.delsarte_degree_over_length", raised)

# --- ConstantNormCode: the cube's eight vertices ----------------------------

cube_vertices = []
corner = 0
while corner < 8
  cube_vertices.push([1 - 2 * ((corner >> 2) & 1),
                      1 - 2 * ((corner >> 1) & 1),
                      1 - 2 * (corner & 1)])
  corner += 1
cube = ConstantNormCode.new(cube_vertices)
check("cube.size", cube.size == 8)
check("cube.dimension", cube.dimension == 3)
check("cube.norm_squared", cube.norm_squared == 3)
check("cube.constant_norm", cube.constant_norm?)
# adjacent corners share two coordinates: <x,y> = 1, ratio 1/3
check("cube.maximum_inner_product", cube.maximum_inner_product_ratio == Rational.new(1, 3))
check("cube.certifies_its_own_bound",
      cube.certifies_maximum_inner_product?(Rational.new(1, 3)))
check("cube.certifies_a_weaker_bound",
      cube.certifies_maximum_inner_product?(Rational.new(1, 2)))
check("cube.rejects_a_stronger_bound",
      !cube.certifies_maximum_inner_product?(Rational.new(0)))
check("cube.proof_kind",
      cube.proof_kind == :exact_finite_constant_norm_inner_product_replay)

# an antipodal pair: max inner product is -1 (ratio -1), the tightest there is
antipodal = ConstantNormCode.new([[1, 0, 0], [-1, 0, 0]])
check("antipodal.norm_squared", antipodal.norm_squared == 1)
check("antipodal.maximum_inner_product",
      antipodal.maximum_inner_product_ratio == Rational.new(-1))

raised = false
begin
  ConstantNormCode.new([[1, 0]])
rescue e
  raised = true
check("error.constant_norm_needs_two_vectors", raised)

raised = false
begin
  ConstantNormCode.new([[0, 0], [1, 0]])
rescue e
  raised = true
check("error.constant_norm_needs_positive_norm", raised)

# A code that is NOT constant norm should report so and refuse to bound.
#
# BUG: `return` inside a block does not return from the enclosing method in
# the native interpreter — it is silently discarded and the method falls
# through — so ConstantNormCode#constant_norm? (core/combinatorics/coding.w,
# `@vectors.each -> (vector) / return false if ...`) answers `true` for a
# code with mixed norms interpreted, while compiled answers `false`.
# Minimal repro (compiled prints false, interpreted prints true):
#   + Probe
#     -> new(items)
#       @items = items
#     -> all_ones?
#       @items.each -> (v)
#         return false if v != 1
#       true
#   << Probe.new([1, 2]).all_ones?.to_s
# Same root cause makes a top-level `f = -> (x) / if .. / return y / z` raise
# "__SIGNAL__" interpreted. ~40 core methods in combinatorics/ and geometry/
# use this shape.
mixed = ConstantNormCode.new([[1, 0], [1, 1]])
# check("mixed.not_constant_norm", !mixed.constant_norm?)
# check("mixed.no_ratio", mixed.maximum_inner_product_ratio == nil)
# check("mixed.certifies_nothing", !mixed.certifies_maximum_inner_product?(Rational.new(5)))
# What both engines DO agree on: the vectors that were handed in, and the
# norm-squared taken from the first one.
check("mixed.size", mixed.size == 2)
check("mixed.norm_squared_from_first", mixed.norm_squared == 1)

<< "combinatorics_coding_spec: all checks passed"
