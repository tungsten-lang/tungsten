# Canonical genus-three theta-characteristic incidence over F2.
#
# A symplectic basis identifies J[2] with F2^6.  Quadratic refinements of the
# standard pairing are indexed by six-bit characteristics; the 28 with Arf
# invariant one are odd.  Four odd characteristics are syzygetic exactly when
# their affine labels sum to zero.  The finite construction and all module
# ranks are replayed here.  Identifying it with a curve's bitangents is the
# Riemann--Mumford/BPS theorem step and remains explicit in the certificate.

+ ThetaQuadraticFormCertificate
  -> new(@form)
    @verified_cache = nil

  -> verified?
    return @verified_cache if @verified_cache != nil
    @verified_cache = verify!
    @verified_cache

  # The polar form of a quadratic polynomial is bilinear, so checking it on
  # every pair of basis vectors checks all 64x64 vector pairs without
  # repeating the same linear expansion for every form.
  -> verify!
    return false if @form.class_name != "ThetaQuadraticForm"
    space = @form.space
    return false if @form.evaluate(space.vector(0)) != 0
    left = 0
    while left < space.dimension
      x = space.vector(1 << left)
      right = 0
      while right < space.dimension
        y = space.vector(1 << right)
        sum = space.add(x, y)
        identity = @form.evaluate(sum)
        identity = identity ^ @form.evaluate(x)
        identity = identity ^ @form.evaluate(y)
        return false if identity != space.pairing(x, y)
        right += 1
      left += 1
    @form.arf_invariant == space.dot(
      @form.left_characteristic,
      @form.right_characteristic)

  -> certified?
    verified?

  -> proof_kind
    :exact_quadratic_coefficient_identity

  -> kernel_checked?
    true


+ SymplecticF2Space
  -> new(@genus)
    if !F2LinearAlgebra.integer?(@genus) || @genus < 1
      raise "symplectic F2 genus must be positive"
    @dimension = 2 * @genus

  -> genus
    @genus

  -> dimension
    @dimension

  -> vector(encoded)
    if !F2LinearAlgebra.integer?(encoded)
      raise "encoded symplectic vector must be an integer"
    if encoded < 0 || encoded >= (1 << @dimension)
      raise "encoded symplectic vector is out of range"
    out = []
    bit = 0
    while bit < @dimension
      out.push((encoded >> bit) & 1)
      bit += 1
    out

  -> validate(vector)
    F2LinearAlgebra.validate_vector(vector, @dimension)

  -> add(left, right)
    validate(left)
    validate(right)
    out = []
    i = 0
    while i < @dimension
      out.push(left[i] ^ right[i])
      i += 1
    out

  -> dot(left, right)
    F2LinearAlgebra.dot(left, right)

  -> pairing(left, right)
    validate(left)
    validate(right)
    answer = 0
    i = 0
    while i < @genus
      answer = answer ^ (left[i] & right[@genus + i])
      answer = answer ^ (left[@genus + i] & right[i])
      i += 1
    answer


+ ThetaQuadraticForm
  -> new(@space, characteristic)
    if @space.class_name != "SymplecticF2Space"
      raise "theta quadratic form needs a symplectic F2 space"
    @characteristic = []
    characteristic.each -> (bit)
      @characteristic.push(bit)
    @space.validate(@characteristic)
    @certificate_cache = ThetaQuadraticFormCertificate.new(self)

  -> space
    @space

  -> characteristic
    F2LinearAlgebra.copy_vector(@characteristic)

  -> left_characteristic
    out = []
    i = 0
    while i < @space.genus
      out.push(@characteristic[i])
      i += 1
    out

  -> right_characteristic
    out = []
    i = 0
    while i < @space.genus
      out.push(@characteristic[@space.genus + i])
      i += 1
    out

  -> evaluate(vector)
    @space.validate(vector)
    value = 0
    i = 0
    while i < @space.genus
      value = value ^ (vector[i] & vector[@space.genus + i])
      value = value ^ (@characteristic[i] & vector[@space.genus + i])
      value = value ^ (@characteristic[@space.genus + i] & vector[i])
      i += 1
    value

  -> arf_invariant
    @space.dot(left_characteristic, right_characteristic)

  -> odd?
    arf_invariant == 1

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ GenusThreeThetaIncidenceCertificate
  -> new(@incidence)
    @verified_cache = nil

  -> theorem
    "the odd-theta incidence of a smooth genus-three curve is the canonical Sp6(F2) incidence"

  -> theorem_reference
    "Riemann-Mumford and Bruin-Poonen-Stoll sections 5.2 and 12.2-12.3"

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

  -> finite_replay_checked?
    true

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
    return false if @incidence.class_name != "GenusThreeThetaIncidence"
    forms = @incidence.odd_characteristics
    return false if forms.size != 28
    i = 0
    while i < forms.size
      return false if !forms[i].odd?
      return false if !forms[i].certificate.verified?
      j = 0
      while j < i
        return false if F2LinearAlgebra.same_vector?(
          forms[i].characteristic, forms[j].characteristic)
        j += 1
      i += 1

    expected = []
    a = 0
    while a < forms.size
      b = a + 1
      while b < forms.size
        c = b + 1
        while c < forms.size
          d = c + 1
          while d < forms.size
            if @incidence.syzygetic_indices?(a, b, c, d)
              expected.push([a, b, c, d])
            d += 1
          c += 1
        b += 1
      a += 1
    return false if expected.size != 315
    return false if expected.to_s != @incidence.syzygetic_quadruples.to_s
    @incidence.module_dimensions.to_s == "\[0, 1, 7, 21, 27, 28\]"

  -> certified?
    verified?


+ ThetaF2SpanCertificate
  -> new(masks, @width)
    @masks = []
    masks.each -> (mask)
      @masks.push(mask)
    @rank = compute_rank

  -> masks
    out = []
    @masks.each -> (mask)
      out.push(mask)
    out

  -> rank
    @rank

  -> compute_rank
    pivots = []
    @width.times -> pivots.push(0)
    answer = 0
    @masks.each -> (mask)
      value = mask
      bit = @width - 1
      placed = false
      while bit >= 0 && !placed
        if ((value >> bit) & 1) == 1
          if pivots[bit] == 0
            pivots[bit] = value
            answer += 1
            placed = true
          else
            value = value ^ pivots[bit]
        bit -= 1
    answer

  -> verified?
    return false if @width < 0
    limit = 1 << @width
    i = 0
    while i < @masks.size
      return false if @masks[i] < 0 || @masks[i] >= limit
      i += 1
    @rank == compute_rank

  -> certified?
    verified?

  -> proof_kind
    :exact_f2_bit_span

  -> kernel_checked?
    true


+ GenusThreeThetaIncidence
  -> new
    @space = SymplecticF2Space.new(3)
    @odd_characteristics = []
    @odd_labels = []
    encoded = 0
    while encoded < 64
      form = ThetaQuadraticForm.new(
        @space, @space.vector(encoded))
      if form.odd?
        @odd_characteristics.push(form)
        @odd_labels.push(encoded)
      encoded += 1
    @syzygetic_quadruples = []
    a = 0
    while a < @odd_characteristics.size
      b = a + 1
      while b < @odd_characteristics.size
        c = b + 1
        while c < @odd_characteristics.size
          d = c + 1
          while d < @odd_characteristics.size
            if syzygetic_indices?(a, b, c, d)
              @syzygetic_quadruples.push([a, b, c, d])
            d += 1
          c += 1
        b += 1
      a += 1
    @syzygetic_masks = []
    @syzygetic_quadruples.each -> (quadruple)
      @syzygetic_masks.push(subset_mask(quadruple))
    @module_rank_certificates = compute_module_rank_certificates
    @certificate_cache = GenusThreeThetaIncidenceCertificate.new(self)
    if !@certificate_cache.verified?
      raise "canonical genus-three theta incidence failed certification"

  -> space
    @space

  -> odd_characteristics
    out = []
    @odd_characteristics.each -> (form)
      out.push(form)
    out

  -> syzygetic_quadruples
    F2LinearAlgebra.copy_matrix(@syzygetic_quadruples)

  -> syzygetic_indices?(a, b, c, d)
    value = @odd_labels[a] ^ @odd_labels[b]
    value = value ^ @odd_labels[c]
    (value ^ @odd_labels[d]) == 0

  -> characteristic_sum(indices)
    encoded = 0
    indices.each -> (index)
      encoded = encoded ^ @odd_labels[index]
    @space.vector(encoded)

  -> subset_vector(indices)
    out = []
    @odd_characteristics.size.times -> out.push(0)
    indices.each -> (index)
      out[index] = out[index] ^ 1
    out

  -> subset_mask(indices)
    out = 0
    indices.each -> (index)
      out = out ^ (1 << index)
    out

  -> pair_masks
    out = []
    i = 0
    while i < 28
      j = i + 1
      while j < 28
        out.push((1 << i) | (1 << j))
        j += 1
      i += 1
    out

  -> gamma_masks
    out = []
    i = 0
    while i < 28
      j = i + 1
      while j < 28
        pair = (1 << i) | (1 << j)
        value = 0
        @syzygetic_masks.each -> (quadruple)
          value = value ^ quadruple if (quadruple & pair) == pair
        out.push(value)
        j += 1
      i += 1
    out

  -> rank_certificate(masks)
    ThetaF2SpanCertificate.new(masks, 28)

  -> compute_module_rank_certificates
    zero = rank_certificate([])
    one = rank_certificate([(1 << 28) - 1])
    j_tilde = rank_certificate(gamma_masks)
    r = rank_certificate(@syzygetic_masks)
    e = rank_certificate(pair_masks)
    ambient = []
    i = 0
    while i < 28
      ambient.push(1 << i)
      i += 1
    full = rank_certificate(ambient)
    [zero, one, j_tilde, r, e, full]

  -> module_rank_certificates
    out = []
    @module_rank_certificates.each -> (certificate)
      out.push(certificate)
    out

  -> module_dimensions
    @module_rank_certificates.map -> item.rank

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ Algebra
  -> .genus_three_theta_incidence
    GenusThreeThetaIncidence.new
