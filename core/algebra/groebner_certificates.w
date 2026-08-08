# Proof-producing Buchberger computations.
#
# The producer tracks every basis polynomial as an explicit combination of
# the source generators. The certificate separately replays:
#   * B subset <F> from those representations,
#   * F subset <B> from exact zero-remainder identities, and
#   * Buchberger's S-pair criterion from exact zero-remainder identities.
#
# Polynomial identities are kernel-checked exact arithmetic. The implication
# from the S-pair identities to "B is a Groebner basis" remains an explicitly
# labelled classical theorem import.

use core/algebra/groebner

+ PolynomialReductionCertificate
  -> new(@dividend, @divisors, @quotients, @remainder)
    @verified_cache = nil

  -> dividend
    @dividend

  -> divisors
    @divisors

  -> quotients
    @quotients

  -> remainder
    @remainder

  -> verified?
    return @verified_cache if @verified_cache != nil
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    @verified_cache = answer
    answer

  -> verify!
    return false if @dividend.class_name != "Polynomial"
    return false if @divisors.size != @quotients.size
    reconstructed = @remainder
    index = 0
    while index < @divisors.size
      return false if @divisors[index].ring != @dividend.ring
      return false if @quotients[index].ring != @dividend.ring
      reconstructed += @quotients[index]*@divisors[index]
      index += 1
    reconstructed == @dividend

  -> certified?
    verified?

  -> proof_kind
    :exact_polynomial_identity

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    verified?

  -> zero_remainder?
    @remainder.zero?

  -> statement
    "the displayed quotient identity reconstructs the dividend exactly"


+ PolynomialIdealMembershipCertificate
  -> new(@polynomial, @generators, @multipliers)
    @verified_cache = nil

  -> polynomial
    @polynomial

  -> generators
    @generators

  -> multipliers
    @multipliers

  -> verified?
    return @verified_cache if @verified_cache != nil
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    @verified_cache = answer
    answer

  -> verify!
    return false if @polynomial.class_name != "Polynomial"
    return false if @generators.size != @multipliers.size
    reconstructed = @polynomial.ring.zero
    index = 0
    while index < @generators.size
      return false if @generators[index].ring != @polynomial.ring
      return false if @multipliers[index].ring != @polynomial.ring
      reconstructed += @multipliers[index]*@generators[index]
      index += 1
    reconstructed == @polynomial

  -> certified?
    verified?

  -> proof_kind
    :exact_ideal_membership_identity

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    verified?

  -> statement
    "the polynomial is the displayed combination of the ideal generators"


+ GroebnerProofArithmetic
  -> .zero_representation(ring, size)
    out = []
    size.times -> out.push(ring.zero)
    out

  -> .unit_representation(ring, size, index)
    out = GroebnerProofArithmetic.zero_representation(
      ring, size)
    out[index] = ring.one
    out

  -> .copy_representation(source)
    out = []
    source.each -> out.push(item)
    out

  -> .scale_representation(representation, multiplier)
    out = []
    representation.each ->
      out.push(item*multiplier)
    out

  -> .subtract_scaled(representation, other, multiplier)
    out = []
    index = 0
    while index < representation.size
      out.push(
        representation[index] -
        multiplier*other[index])
      index += 1
    out

  -> .same_polynomial_array?(left, right)
    return false if left.size != right.size
    index = 0
    while index < left.size
      return false if left[index] != right[index]
      index += 1
    true

  -> .reconstruct(generators, representation)
    if generators.size != representation.size
      raise "Groebner representation has the wrong size"
    ring = generators[0].ring
    result = ring.zero
    index = 0
    while index < generators.size
      result += representation[index]*generators[index]
      index += 1
    result

  # Return [remainder, remainder representation, reduction certificate].
  -> .reduce_labeled(polynomial, representation,
                      basis, basis_representations)
    if basis.size == 0
      certificate = PolynomialReductionCertificate.new(
        polynomial, [], [], polynomial)
      return [
        polynomial,
        GroebnerProofArithmetic.copy_representation(
          representation),
        certificate]
    division = polynomial.divide(basis)
    quotients = division[0]
    remainder = division[1]
    remainder_representation = (
      GroebnerProofArithmetic.copy_representation(
        representation))
    index = 0
    while index < basis.size
      if !quotients[index].zero?
        remainder_representation = (
          GroebnerProofArithmetic.subtract_scaled(
            remainder_representation,
            basis_representations[index],
            quotients[index]))
      index += 1
    certificate = PolynomialReductionCertificate.new(
      polynomial, basis, quotients, remainder)
    [
      remainder,
      remainder_representation,
      certificate]


+ GroebnerBasisCertificate
  -> new(@source_generators, @basis,
         @basis_representations,
         @source_reductions,
         @s_pair_reductions)
    @verified_cache = nil

  -> source_generators
    @source_generators

  -> basis
    @basis

  -> basis_representations
    @basis_representations

  -> source_reductions
    @source_reductions

  -> s_pair_reductions
    @s_pair_reductions

  -> theorem
    "Buchberger's S-pair criterion characterizes Groebner bases"

  -> theorem_reference
    "classical Buchberger criterion"

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    verified?

  -> verified?
    return @verified_cache if @verified_cache != nil
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    @verified_cache = answer
    answer

  -> verify!
    return false if @source_generators.size == 0
    ring = GroebnerBasis.validate_generators(
      @source_generators)
    return false if @basis.size != @basis_representations.size
    return false if (
      @source_reductions.size !=
      @source_generators.size)

    index = 0
    while index < @basis.size
      return false if @basis[index].ring != ring
      representation = @basis_representations[index]
      return false if (
        representation.size !=
        @source_generators.size)
      reconstructed = GroebnerProofArithmetic.reconstruct(
        @source_generators, representation)
      return false if reconstructed != @basis[index]
      index += 1

    index = 0
    while index < @source_generators.size
      reduction = @source_reductions[index]
      return false if !reduction.verified?
      return false if !reduction.zero_remainder?
      return false if (
        reduction.dividend != @source_generators[index])
      return false if !GroebnerProofArithmetic.same_polynomial_array?(
        reduction.divisors, @basis)
      index += 1

    expected_pair_count = 0
    i = 0
    while i < @basis.size
      expected_pair_count += i
      i += 1
    return false if (
      @s_pair_reductions.size !=
      expected_pair_count)

    reduction_index = 0
    i = 0
    while i < @basis.size
      j = 0
      while j < i
        reduction = @s_pair_reductions[reduction_index]
        expected_s = GroebnerBasis.s_polynomial(
          @basis[j], @basis[i])
        return false if reduction.dividend != expected_s
        return false if !GroebnerProofArithmetic.same_polynomial_array?(
          reduction.divisors, @basis)
        return false if !reduction.verified?
        return false if !reduction.zero_remainder?
        reduction_index += 1
        j += 1
      i += 1
    true

  -> certified?
    verified?

  -> statement
    ("the displayed basis generates the source ideal and satisfies " +
     "every exact S-pair reduction identity")


+ CertifiedGroebnerBasis
  -> new(@source_generators, pair_limit = 20_000)
    @ring = GroebnerBasis.validate_generators(
      @source_generators)
    @basis = []
    @basis_representations = []
    source_size = @source_generators.size

    generator_index = 0
    while generator_index < source_size
      generator = @source_generators[generator_index]
      if !generator.zero?
        representation = (
          GroebnerProofArithmetic.unit_representation(
            @ring, source_size, generator_index))
        reduced = GroebnerProofArithmetic.reduce_labeled(
          generator, representation,
          @basis, @basis_representations)
        remainder = reduced[0]
        representation = reduced[1]
        if !remainder.zero?
          scale = @ring.field.divide(
            @ring.field.one,
            remainder.leading_coefficient)
          multiplier = @ring.monomial_raw(
            scale, @ring.zero_exponents)
          remainder = remainder.monomial_multiply_raw(
            @ring.zero_exponents, scale)
          representation = (
            GroebnerProofArithmetic.scale_representation(
              representation, multiplier))
          if remainder.constant?
            @basis = [remainder]
            @basis_representations = [representation]
            break
          else
            @basis.push(remainder)
            @basis_representations.push(representation)
      generator_index += 1

    pairs = []
    pending = {}
    i = 0
    while i < @basis.size
      j = 0
      while j < i
        pairs.push([j, i, GroebnerBasis.monomial_lcm(
          @basis[j].leading_term[1],
          @basis[i].leading_term[1])])
        pending[GroebnerBasis.pair_key(j, i)] = true
        j += 1
      i += 1

    processed = 0
    while pairs.size > 0
      if processed >= pair_limit
        raise "certified Groebner pair limit exceeded"
      best = 0
      i = 1
      while i < pairs.size
        if @ring.monomial_compare(
             pairs[i][2], pairs[best][2]) < 0
          best = i
        i += 1
      pair = pairs.delete_at(best)
      pending.delete(
        GroebnerBasis.pair_key(pair[0], pair[1]))
      processed += 1
      left = @basis[pair[0]]
      right = @basis[pair[1]]
      if !GroebnerBasis.relatively_prime?(
           left.leading_term[1], right.leading_term[1])
        if !GroebnerBasis.chain_redundant?(
             @basis, pending, pair)
          s_data = labeled_s_polynomial(
            pair[0], pair[1])
          reduced = GroebnerProofArithmetic.reduce_labeled(
            s_data[0], s_data[1],
            @basis, @basis_representations)
          remainder = reduced[0]
          representation = reduced[1]
          if !remainder.zero?
            scale = @ring.field.divide(
              @ring.field.one,
              remainder.leading_coefficient)
            multiplier = @ring.monomial_raw(
              scale, @ring.zero_exponents)
            remainder = remainder.monomial_multiply_raw(
              @ring.zero_exponents, scale)
            representation = (
              GroebnerProofArithmetic.scale_representation(
                representation, multiplier))
            if remainder.constant?
              @basis = [remainder]
              @basis_representations = [representation]
              pairs = []
              pending = {}
            else
              new_index = @basis.size
              @basis.push(remainder)
              @basis_representations.push(
                representation)
              j = 0
              while j < new_index
                pairs.push([
                  j, new_index,
                  GroebnerBasis.monomial_lcm(
                    @basis[j].leading_term[1],
                    remainder.leading_term[1])])
                pending[GroebnerBasis.pair_key(
                  j, new_index)] = true
                j += 1

    @source_reductions = []
    @source_generators.each -> (generator)
      division = generator.divide(@basis)
      @source_reductions.push(
        PolynomialReductionCertificate.new(
          generator, @basis,
          division[0], division[1]))

    @s_pair_reductions = []
    i = 0
    while i < @basis.size
      j = 0
      while j < i
        s_polynomial = GroebnerBasis.s_polynomial(
          @basis[j], @basis[i])
        division = s_polynomial.divide(@basis)
        @s_pair_reductions.push(
          PolynomialReductionCertificate.new(
            s_polynomial, @basis,
            division[0], division[1]))
        j += 1
      i += 1

    @certificate = GroebnerBasisCertificate.new(
      @source_generators, @basis,
      @basis_representations,
      @source_reductions,
      @s_pair_reductions)
    if !@certificate.verified?
      raise "produced Groebner certificate did not verify"

  -> labeled_s_polynomial(left_index, right_index)
    left = @basis[left_index]
    right = @basis[right_index]
    left_term = left.leading_term
    right_term = right.leading_term
    left_powers = []
    right_powers = []
    index = 0
    while index < @ring.arity
      lcm = (
        left_term[1][index] > right_term[1][index] ?
        left_term[1][index] : right_term[1][index])
      left_powers.push(lcm - left_term[1][index])
      right_powers.push(lcm - right_term[1][index])
      index += 1
    left_multiplier = @ring.monomial_raw(
      @ring.field.divide(
        @ring.field.one, left_term[0]),
      left_powers)
    right_multiplier = @ring.monomial_raw(
      @ring.field.divide(
        @ring.field.one, right_term[0]),
      right_powers)
    polynomial = (
      left_multiplier*left -
      right_multiplier*right)
    representation = []
    index = 0
    while index < @source_generators.size
      representation.push(
        left_multiplier*
          @basis_representations[left_index][index] -
        right_multiplier*
          @basis_representations[right_index][index])
      index += 1
    [polynomial, representation]

  -> ring
    @ring

  -> source_generators
    @source_generators

  -> polynomials
    @basis

  -> basis
    @basis

  -> representations
    @basis_representations

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> size
    @basis.size

  -> [](index)
    @basis[index]

  -> reduce(polynomial)
    @ring.coerce(polynomial).normal_form(@basis)

  -> contains?(polynomial)
    reduce(polynomial).zero?

  -> membership_certificate(polynomial)
    value = @ring.coerce(polynomial)
    division = value.divide(@basis)
    if !division[1].zero?
      raise "polynomial is not in the certified ideal"
    multipliers = GroebnerProofArithmetic.zero_representation(
      @ring, @source_generators.size)
    basis_index = 0
    while basis_index < @basis.size
      quotient = division[0][basis_index]
      source_index = 0
      while source_index < @source_generators.size
        multipliers[source_index] += (
          quotient*
          @basis_representations[
            basis_index][source_index])
        source_index += 1
      basis_index += 1
    certificate = PolynomialIdealMembershipCertificate.new(
      value, @source_generators, multipliers)
    if !certificate.verified?
      raise "ideal-membership certificate did not verify"
    certificate


+ Ideal
  -> certified_groebner_basis(pair_limit = 20_000)
    CertifiedGroebnerBasis.new(
      @generators, pair_limit)
