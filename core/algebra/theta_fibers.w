# Certified theta-incidence labeling on one finite reduction of a plane
# quartic.
#
# Bruin--Poonen--Stoll Lemma 12.2 characterizes a syzygetic quadruple of
# bitangents by a conic through their four contact divisors.  For a chart-0
# bitangent
#
#   B = u*S + v*Z
#
# with normalized contact quadratic U^2 + q1*U*V + q2*V^2, containment of
# the contact divisor imposes two linear conditions on the six coefficients
# of a plane conic.  This file replays those conditions over an explicit
# finite splitting field.
#
# A finite-fiber labeling is stronger than matching Frobenius cycle lengths:
# it identifies every reduced bitangent with a canonical odd characteristic
# and checks all 315 syzygetic blocks.  It is still not a common global
# labeling of characteristic-zero roots across several primes.

+ ExactFieldRowReduction
  -> .rank(field, matrix, width = nil)
    if width == nil
      column_count = matrix.size == 0 ? 0 : matrix[0].size
    else
      column_count = width
    work = []
    row_index = 0
    while row_index < matrix.size
      source = matrix[row_index]
      if source.class_name != "Array" || source.size != column_count
        raise "exact row reduction received a ragged matrix"
      row = []
      column = 0
      while column < column_count
        row.push(field.normalize_element(source[column]))
        column += 1
      work.push(row)
      row_index += 1

    pivot_row = 0
    column = 0
    while column < column_count && pivot_row < work.size
      selected = pivot_row
      while selected < work.size && field.zero?(work[selected][column])
        selected += 1
      if selected < work.size
        if selected != pivot_row
          temporary = work[pivot_row]
          work[pivot_row] = work[selected]
          work[selected] = temporary
        inverse = field.inverse(work[pivot_row][column])
        j = column
        while j < column_count
          work[pivot_row][j] = field.multiply(
            work[pivot_row][j], inverse)
          j += 1
        row = 0
        while row < work.size
          if row != pivot_row
            scale = work[row][column]
            if !field.zero?(scale)
              j = column
              while j < column_count
                product = field.multiply(
                  scale, work[pivot_row][j])
                work[row][j] = field.subtract(
                  work[row][j], product)
                j += 1
          row += 1
        pivot_row += 1
      column += 1
    pivot_row


+ PlaneQuarticFiniteThetaFiberCertificate
  -> new(@fiber)
    @verified_cache = nil

  -> theorem
    "four bitangents are syzygetic exactly when a conic contains their contact divisors"

  -> theorem_reference
    "Bruin-Poonen-Stoll Lemma 12.2, Proposition 5.7, and Corollary 12.5"

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

  -> finite_replay_checked?
    true

  -> arithmetic_fiber_labeling_checked?
    true

  -> global_arithmetic_labeling_checked?
    false

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
    expected_class = "PlaneQuarticFiniteThetaFiber"
    return false if @fiber.class_name != expected_class
    scheme = @fiber.scheme_certificate
    return false if scheme.class_name != "PlaneQuarticBitangentSchemeCertificate"
    return false if !scheme.verified? || scheme.etale_degree != 27
    return false if !@fiber.good_reduction?

    field = @fiber.splitting_field
    return false if field.class_name != "FiniteField"
    return false if field.characteristic != @fiber.prime
    return false if field.degree != @fiber.extension_degree
    return false if !field.modulus_certificate.verified?

    roots = @fiber.roots
    labels = @fiber.theta_labels
    return false if roots.size != 27 || labels.size != 28
    return false if !@fiber.labels_form_permutation?
    return false if !@fiber.roots_are_distinct?

    contacts = @fiber.recompute_contacts
    return false if contacts.size != 28
    return false if !@fiber.component_root_counts_match?(contacts)
    return false if !@fiber.contact_identities_hold?(contacts)

    incidence = @fiber.incidence
    return false if !incidence.certificate.verified?
    return false if incidence.syzygetic_quadruples.size != 315
    inverse = @fiber.source_index_by_theta_label
    canonical = incidence.syzygetic_quadruples
    block_index = 0
    while block_index < canonical.size
      block = canonical[block_index]
      rows = []
      i = 0
      while i < block.size
        contact_rows = @fiber.conic_rows(
          contacts[inverse[block[i]]])
        rows.push(contact_rows[0])
        rows.push(contact_rows[1])
        i += 1
      # A rank-five system has the unique projective conic asserted by the
      # BPS construction.  The 315-block theorem then proves exhaustion.
      conic_rank = ExactFieldRowReduction.rank(
        field, rows, 6)
      return false if conic_rank != 5
      block_index += 1

    source_frobenius = @fiber.source_frobenius_permutation
    return false if source_frobenius.size != 28
    theta_frobenius = @fiber.theta_permutation
    return false if !theta_frobenius.certificate.verified?
    source = 0
    while source < 28
      label = labels[source]
      image_label = labels[source_frobenius[source]]
      return false if theta_frobenius.apply(label) != image_label
      source += 1
    true

  -> certified?
    verified?


+ PlaneQuarticFiniteThetaFiber
  -> new(@scheme_certificate, @prime, @extension_modulus, root_encodings, theta_labels, symplectic_matrix)
    if @scheme_certificate.class_name != "PlaneQuarticBitangentSchemeCertificate"
      raise "finite theta fiber needs a bitangent-scheme certificate"
    if !@scheme_certificate.verified?
      raise "finite theta fiber needs a verified bitangent scheme"
    @splitting_field = FiniteField.new(
      @prime, @extension_modulus)
    @extension_degree = @splitting_field.degree
    @root_encodings = []
    root_encodings.each -> @root_encodings.push(item)
    @theta_labels = []
    theta_labels.each -> @theta_labels.push(item)
    @incidence = Algebra.genus_three_theta_incidence
    transformation = SymplecticF2Map.new(
      @incidence.space, symplectic_matrix)
    @theta_permutation = GenusThreeThetaPermutation.new(
      @incidence, transformation)
    @certificate_cache = PlaneQuarticFiniteThetaFiberCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "finite plane-quartic theta labeling failed certification"

  -> scheme_certificate
    @scheme_certificate

  -> prime
    @prime

  -> extension_degree
    @extension_degree

  -> splitting_field
    @splitting_field

  -> incidence
    @incidence

  -> roots
    out = []
    @root_encodings.each ->
      out.push(@splitting_field.normalize_element(item))
    out

  -> theta_labels
    F2LinearAlgebra.copy_vector(@theta_labels)

  -> theta_permutation
    @theta_permutation

  -> distinguished_theta_label
    @theta_labels[27]

  -> finite_fiber_only?
    true

  -> global_arithmetic_labeling_certified?
    false

  -> labels_form_permutation?
    return false if @theta_labels.size != 28
    seen = []
    28.times -> seen.push(false)
    i = 0
    while i < @theta_labels.size
      label = @theta_labels[i]
      return false if !F2LinearAlgebra.integer?(label)
      return false if label < 0 || label >= 28 || seen[label]
      seen[label] = true
      i += 1
    true

  -> roots_are_distinct?
    return false if @root_encodings.size != 27
    seen = []
    i = 0
    while i < @root_encodings.size
      root = @root_encodings[i]
      return false if !F2LinearAlgebra.integer?(root)
      return false if root < 0 || root >= @splitting_field.order
      return false if seen.include?(root)
      seen.push(root)
      i += 1
    true

  -> good_reduction?
    return false if @prime == 2
    @scheme_certificate.setup.curve.reduce(@prime).nonsingular?

  -> evaluate_source_polynomial(polynomial, values)
    if polynomial.ring.arity != values.size
      raise "finite theta evaluation has the wrong arity"
    field = @splitting_field
    out = field.zero
    polynomial.each_term -> (coefficient, exponents)
      term = field.embed_from(
        polynomial.ring.field, coefficient)
      variable = 0
      while variable < values.size
        if exponents[variable] > 0
          term = field.multiply(
            term,
            field.power(values[variable],
                        exponents[variable]))
        variable += 1
      out = field.add(out, term)
    out

  -> contact_for_root(root)
    projection = @scheme_certificate.primary_certificate
    components = projection.components
    matches = []
    i = 0
    while i < components.size
      if @splitting_field.zero?(
           evaluate_source_polynomial(
             components[i].factor, [root]))
        matches.push(i)
      i += 1
    if matches.size != 1
      raise "finite bitangent root does not select one etale component"
    component_index = matches[0]
    component = components[component_index]
    u = evaluate_source_polynomial(
      component.u_image, [root])

    coefficients = []
    chart = @scheme_certificate.primary_chart
    chart.line_binary_coefficients.each -> (polynomial)
      coefficients.push(
        evaluate_source_polynomial(
          polynomial, [u, root]))
    a = coefficients[0]
    if @splitting_field.zero?(a)
      raise "finite bitangent contact has zero leading coefficient"
    two = @splitting_field.coerce(2)
    four = @splitting_field.coerce(4)
    eight = @splitting_field.coerce(8)
    q1 = @splitting_field.divide(
      coefficients[1],
      @splitting_field.multiply(two, a))
    numerator = @splitting_field.subtract(
      @splitting_field.multiply(
        four,
        @splitting_field.multiply(a, coefficients[2])),
      @splitting_field.multiply(
        coefficients[1], coefficients[1]))
    denominator = @splitting_field.multiply(
      eight, @splitting_field.multiply(a, a))
    q2 = @splitting_field.divide(numerator, denominator)
    [component_index, u, root, q1, q2] + coefficients

  -> distinguished_contact
    certificate = @scheme_certificate.setup.distinguished_certificate
    line = certificate.line.coefficients
    point = certificate.point.coordinates
    field = @scheme_certificate.setup.curve.field
    expected_line = [0, 0, 1]
    expected_point = [1, 0, 0]
    i = 0
    while i < 3
      if !field.equal?(line[i], expected_line[i])
        raise "focused finite theta fiber needs distinguished line Z = 0"
      if !field.equal?(point[i], expected_point[i])
        raise "focused finite theta fiber needs hyperflex point [1:0:0]"
      i += 1
    [:distinguished]

  -> recompute_contacts
    contacts = []
    roots.each -> (root)
      contacts.push(contact_for_root(root))
    contacts.push(distinguished_contact)
    contacts

  -> component_root_counts_match?(contacts)
    expected = @scheme_certificate.component_degrees
    counts = []
    expected.size.times -> counts.push(0)
    i = 0
    while i < 27
      component_index = contacts[i][0]
      return false if component_index < 0 || component_index >= counts.size
      counts[component_index] = counts[component_index] + 1
      i += 1
    counts.to_s == expected.to_s

  -> contact_identities_hold?(contacts)
    field = @splitting_field
    two = field.coerce(2)
    i = 0
    while i < 27
      contact = contacts[i]
      q1 = contact[3]
      q2 = contact[4]
      coefficients = contact.copy(5, 5)
      a = coefficients[0]
      expected = []
      expected.push(a)
      expected.push(field.multiply(
        field.multiply(two, a), q1))
      middle = field.add(
        field.multiply(q1, q1),
        field.multiply(two, q2))
      expected.push(field.multiply(a, middle))
      expected.push(field.multiply(
        field.multiply(two, a),
        field.multiply(q1, q2)))
      expected.push(field.multiply(
        a, field.multiply(q2, q2)))
      j = 0
      while j < 5
        return false if !field.equal?(
          coefficients[j], expected[j])
        j += 1
      i += 1
    true

  -> scaled_difference(left, scale, right)
    out = []
    i = 0
    while i < left.size
      out.push(@splitting_field.subtract(
        left[i],
        @splitting_field.multiply(scale, right[i])))
      i += 1
    out

  -> conic_rows(contact)
    if contact.size == 1
      return [
        [1, 0, 0, 0, 0, 0],
        [0, 0, 0, 1, 0, 0]
      ]
    field = @splitting_field
    u = contact[1]
    v = contact[2]
    q1 = contact[3]
    q2 = contact[4]
    u2 = field.multiply(u, u)
    v2 = field.multiply(v, v)
    uv2 = field.multiply(
      field.coerce(2), field.multiply(u, v))
    degree_two = [u2, 1, 0, u, 0, 0]
    degree_one = [uv2, 0, 0, v, u, 1]
    degree_zero = [v2, 0, 1, 0, v, 0]
    [
      scaled_difference(degree_one, q1, degree_two),
      scaled_difference(degree_zero, q2, degree_two)
    ]

  -> source_index_by_theta_label
    inverse = []
    28.times -> inverse.push(-1)
    i = 0
    while i < @theta_labels.size
      inverse[@theta_labels[i]] = i
      i += 1
    inverse

  -> source_frobenius_permutation
    roots = roots()
    permutation = []
    i = 0
    while i < roots.size
      target = @splitting_field.frobenius(roots[i])
      image = roots.index(target)
      if image == nil
        raise "finite bitangent roots are not Frobenius-stable"
      permutation.push(image)
      i += 1
    permutation.push(27)
    permutation

  -> source_frobenius_cycle_lengths
    permutation = source_frobenius_permutation
    seen = []
    28.times -> seen.push(false)
    lengths = []
    seed = 0
    while seed < 28
      if !seen[seed]
        length = 0
        current = seed
        while !seen[current]
          seen[current] = true
          length += 1
          current = permutation[current]
        lengths.push(length)
      seed += 1
    GenusThreeThetaPermutation.sort_integers(lengths)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> .shell_width_at_five(setup)
    roots = [
      414, 492, 802, 1062, 2000, 2672, 4003, 4141, 4546,
      4672, 5148, 5965, 6423, 6699, 6919, 7289, 7348, 8033,
      8254, 8730, 10786, 10856, 10865, 11013, 11554, 14686,
      14860
    ]
    labels = [
      25, 23, 0, 17, 2, 20, 5, 11, 9,
      4, 19, 13, 27, 1, 10, 6, 26, 7,
      24, 16, 18, 14, 12, 21, 22, 3,
      8, 15
    ]
    matrix = [
      [0, 1, 0, 0, 0, 0],
      [0, 0, 1, 0, 0, 0],
      [0, 1, 0, 1, 0, 0],
      [1, 0, 1, 0, 1, 0],
      [0, 1, 1, 0, 0, 1],
      [1, 1, 0, 1, 0, 0]
    ]
    modulus = [2, 0, 1, 4, 1, 0, 1]
    PlaneQuarticFiniteThetaFiber.new(
      setup.bitangent_scheme_certificate,
      5, modulus, roots, labels, matrix)


+ PlaneQuarticTwoDescentSetup
  -> certify_theta_fiber_at_five
    if @bitangent_scheme_certificate == nil
      certify_bitangent_scheme
    fiber = PlaneQuarticFiniteThetaFiber.shell_width_at_five(
      self)
    if @theta_fiber_certificates == nil
      @theta_fiber_certificates = []
    @theta_fiber_certificates.push(fiber)
    fiber

  -> theta_fiber_certificates
    out = []
    if @theta_fiber_certificates != nil
      @theta_fiber_certificates.each -> (fiber)
        out.push(fiber)
    out
