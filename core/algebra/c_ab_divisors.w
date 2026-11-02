# Effective point divisors and the first Khuri--Makdisi representation layer
# for one-point C_ab curves over prime fields.
#
# A squarefree effective divisor D = Q_1 + ... + Q_d supported on affine
# rational points cuts out
#
#   W_D(n) = L(n infinity - D)
#          = { f in L(n infinity) : f(Q_i) = 0 for every i }.
#
# With d0 >= 2g+1, a degree-zero class [D - d0*infinity] is represented by
# W_D(2d0).  The finite-field kernels and products are replayed exactly; the
# general Riemann--Roch dimension statement is named explicitly as a trusted
# theorem boundary.

+ CAbEffectivePointDivisorCertificate
  -> new(@divisor)
    @verified_cache = nil

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
    return false if @divisor.class_name != "CAbEffectivePointDivisor"
    model = @divisor.model
    return false if !model.certified?
    points = @divisor.points
    index = 0
    while index < points.size
      model.evaluate(model.ring.zero, points[index])
      previous = 0
      while previous < index
        return false if points[previous] == points[index]
        previous += 1
      index += 1
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_squarefree_affine_point_divisor_replay

  -> theorem
    "the listed distinct affine rational points define a squarefree effective divisor of their cardinality"

  -> theorem_reference
    "effective divisors supported on rational points"

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true


+ CAbEffectivePointDivisor
  -> new(@model, points)
    if @model.class_name != "CAbCurveModel"
      raise "C_ab point divisors need a C_ab curve model"
    if points.class_name != "Array"
      raise "C_ab point divisor support must be an array"
    @points = []
    index = 0
    while index < points.size
      support_point = points[index]
      @model.evaluate(@model.ring.zero, support_point)
      previous = 0
      while previous < @points.size
        if @points[previous] == support_point
          raise "C_ab point divisor support must be squarefree"
        previous += 1
      @points.push(support_point)
      index += 1
    @certificate_cache = CAbEffectivePointDivisorCertificate.new(self)
    if !@certificate_cache.verified?
      raise "C_ab effective point divisor failed certification"

  ro :model

  -> points
    out = []
    index = 0
    while index < @points.size
      out.push(@points[index])
      index += 1
    out

  -> degree
    @points.size

  -> squarefree?
    true

  -> contains_point?(candidate)
    index = 0
    while index < @points.size
      return true if @points[index] == candidate
      index += 1
    false

  -> disjoint?(other)
    return false if other.class_name != "CAbEffectivePointDivisor"
    return false if other.model != @model
    other_points = other.points
    index = 0
    while index < other_points.size
      return false if contains_point?(other_points[index])
      index += 1
    true

  -> sum(other)
    if other.class_name != "CAbEffectivePointDivisor" || (
         other.model != @model)
      raise "C_ab point-divisor sum needs the same curve model"
    if !disjoint?(other)
      raise "squarefree C_ab point-divisor sum needs disjoint support"
    CAbEffectivePointDivisor.new(@model, points + other.points)

  -> function_space(bound)
    CAbDivisorSpace.new(
      @model.riemann_roch_space(bound), self)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    "effective affine point divisor(degree " + degree.to_s + ")"

  -> inspect
    to_s


+ CAbPlaceEvaluationArithmetic
  -> .value(model, function, place)
    if !Place.place?(place) || place.curve != model.curve
      raise "C_ab place evaluation needs a place on its curve"
    if place.class_name == "Place"
      return model.evaluate(function, place.point)
    if place.class_name != "ClosedPlace" || !place.certified?
      raise "C_ab closed-place evaluation needs a certified closed place"
    extension = place.residue_field
    target_ring = PolynomialRing.new(model.ring.names, extension)
    lifted = model.reduce(function).change_ring(target_ring)
    point = place.residue_point
    infinity_value = point.coordinates[model.infinity_index]
    if extension.zero?(infinity_value)
      raise "C_ab place evaluation does not support infinity"
    scale = extension.inverse(infinity_value)
    x_value = extension.multiply(
      point.coordinates[model.x_index], scale)
    y_value = extension.multiply(
      point.coordinates[model.y_index], scale)
    lifted.evaluate_raw([x_value, y_value])

  -> .rows(space, divisor)
    if space.class_name != "CAbRiemannRochSpace" || (
         divisor.class_name != "CAbEffectivePlaceDivisor")
      raise "C_ab place evaluation rows need a space and place divisor"
    if space.model != divisor.model
      raise "C_ab place evaluation changes curve model"
    rows = []
    basis = space.basis
    places = divisor.places
    place_index = 0
    while place_index < places.size
      place = places[place_index]
      values = []
      basis_index = 0
      while basis_index < basis.size
        values.push(CAbPlaceEvaluationArithmetic.value(
          space.model, basis[basis_index], place))
        basis_index += 1
      if place.class_name == "Place"
        rows.push(values)
      else
        coefficient_index = 0
        while coefficient_index < place.degree
          row = []
          basis_index = 0
          while basis_index < values.size
            row.push(values[basis_index].coefficients[coefficient_index])
            basis_index += 1
          rows.push(row)
          coefficient_index += 1
      place_index += 1
    rows


+ CAbEffectivePlaceDivisorCertificate
  -> new(@divisor)
    @verified_cache = nil

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
    return false if @divisor.class_name != "CAbEffectivePlaceDivisor"
    model = @divisor.model
    return false if !model.certified?
    formal = @divisor.formal_divisor
    return false if formal.curve != model.curve
    terms = formal.terms
    degree = 0
    index = 0
    while index < terms.size
      return false if terms[index][0] != 1
      place = terms[index][1]
      return false if place.curve != model.curve
      if place.class_name == "Place"
        return false if model.field.zero?(
          place.point.coordinates[model.infinity_index])
      else
        return false if place.class_name != "ClosedPlace"
        return false if !place.certified?
        extension = place.residue_field
        return false if extension.zero?(
          place.residue_point.coordinates[model.infinity_index])
      degree += place.degree
      index += 1
    return false if degree != @divisor.degree
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_squarefree_affine_place_divisor

  -> theorem
    "the listed degree-one and closed affine places define a squarefree effective divisor of their total residue degree"

  -> theorem_reference
    "effective divisors on a curve"

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true


+ CAbEffectivePlaceDivisor
  -> new(@model, source)
    if @model.class_name != "CAbCurveModel"
      raise "C_ab place divisors need a C_ab curve model"
    if source.class_name == "Divisor"
      @formal_divisor = source
    elsif source.class_name == "Array"
      terms = []
      index = 0
      while index < source.size
        terms.push([1, source[index]])
        index += 1
      @formal_divisor = Divisor.new(@model.curve, terms)
    else
      raise "C_ab place divisor needs a Divisor or place array"
    if @formal_divisor.curve != @model.curve
      raise "C_ab place divisor uses a different curve"
    terms = @formal_divisor.terms
    index = 0
    while index < terms.size
      if terms[index][0] != 1
        raise "C_ab place divisor currently needs squarefree support"
      index += 1
    @certificate_cache = CAbEffectivePlaceDivisorCertificate.new(self)
    if !@certificate_cache.verified?
      raise "C_ab effective place divisor failed certification"

  ro :model, :formal_divisor

  -> places
    out = []
    terms = @formal_divisor.terms
    index = 0
    while index < terms.size
      out.push(terms[index][1])
      index += 1
    out

  -> degree
    @formal_divisor.degree

  -> contains_place?(candidate)
    values = places
    index = 0
    while index < values.size
      return true if values[index].eql?(candidate)
      index += 1
    false

  -> disjoint?(other)
    return false if other.class_name != "CAbEffectivePlaceDivisor"
    return false if other.model != @model
    values = other.places
    index = 0
    while index < values.size
      return false if contains_place?(values[index])
      index += 1
    true

  -> sum(other)
    if other.class_name != "CAbEffectivePlaceDivisor" || (
         other.model != @model)
      raise "C_ab place-divisor sum needs the same curve model"
    if !disjoint?(other)
      raise "squarefree C_ab place-divisor sum needs disjoint support"
    CAbEffectivePlaceDivisor.new(@model, places + other.places)

  -> function_space(bound)
    CAbPlaceDivisorSpace.new(
      @model.riemann_roch_space(bound), self)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    "effective affine place divisor(degree " + degree.to_s + ")"

  -> inspect
    to_s


+ CAbPlaceEvaluationKernelCertificate
  -> new(@kernel)
    @verified_cache = nil

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
    return false if @kernel.class_name != "CAbPlaceEvaluationKernel"
    space = @kernel.space
    divisor = @kernel.divisor
    return false if !space.certified? || !divisor.certified?
    rows = CAbPlaceEvaluationArithmetic.rows(space, divisor)
    return false if rows.to_s != @kernel.evaluation_matrix.to_s
    return false if rows.size != divisor.degree
    expected = PrimeFieldSubspace.kernel(
      rows, space.model.field.characteristic, space.dimension)
    expected.same_subspace?(@kernel.subspace.coordinate_subspace)

  -> certified?
    verified?

  -> proof_kind
    :exact_c_ab_closed_place_evaluation_kernel

  -> theorem
    "vanishing at a residue-degree d closed place is the kernel of its d coefficient evaluation rows"

  -> theorem_reference
    "evaluation in the residue field of a closed point"

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    true


+ CAbPlaceEvaluationKernel
  -> new(@space, @divisor)
    if @space.class_name != "CAbRiemannRochSpace" || (
         @divisor.class_name != "CAbEffectivePlaceDivisor")
      raise "C_ab place kernel needs a space and place divisor"
    if @space.model != @divisor.model
      raise "C_ab place kernel changes curve model"
    @evaluation_matrix = CAbPlaceEvaluationArithmetic.rows(
      @space, @divisor)
    coordinate_kernel = PrimeFieldSubspace.kernel(
      @evaluation_matrix, @space.model.field.characteristic,
      @space.dimension)
    @subspace = CAbFunctionSubspace.new(@space, coordinate_kernel)
    @certificate_cache = CAbPlaceEvaluationKernelCertificate.new(self)
    if !@certificate_cache.verified?
      raise "C_ab place evaluation kernel failed certification"

  ro :space, :divisor

  -> evaluation_matrix
    out = []
    row = 0
    while row < @evaluation_matrix.size
      values = []
      column = 0
      while column < @evaluation_matrix[row].size
        values.push(@evaluation_matrix[row][column])
        column += 1
      out.push(values)
      row += 1
    out

  ro :subspace

  -> dimension
    @subspace.dimension

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ CAbPlaceDivisorSpaceCertificate
  -> new(@divisor_space)
    @verified_cache = nil

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
    return false if @divisor_space.class_name != "CAbPlaceDivisorSpace"
    space = @divisor_space.space
    divisor = @divisor_space.divisor
    return false if !space.certified? || !divisor.certified?
    return false if space.model != divisor.model
    kernel = @divisor_space.evaluation_kernel
    return false if !kernel.certified?
    return false if !kernel.subspace.same_subspace?(
      @divisor_space.function_subspace)
    if @divisor_space.independent_conditions_theorem_applies?
      return false if @divisor_space.codimension != divisor.degree
      return false if @divisor_space.dimension != (
        space.bound - divisor.degree + 1 - space.model.genus)
    true

  -> certified?
    verified?

  -> proof_kind
    :riemann_roch_closed_place_kernel_replay

  -> theorem
    "in nonspecial degree, closed-place evaluation imposes deg(D) independent conditions on L(n*infinity)"

  -> theorem_reference
    "Riemann-Roch in nonspecial degree"

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    true


+ CAbPlaceDivisorSpace
  -> new(@space, @divisor)
    if @space.class_name != "CAbRiemannRochSpace" || (
         @divisor.class_name != "CAbEffectivePlaceDivisor")
      raise "C_ab place divisor spaces need a space and place divisor"
    if @space.model != @divisor.model
      raise "C_ab place divisor space changes curve model"
    @evaluation_kernel = CAbPlaceEvaluationKernel.new(@space, @divisor)
    @function_subspace = @evaluation_kernel.subspace
    @certificate_cache = CAbPlaceDivisorSpaceCertificate.new(self)
    if !@certificate_cache.verified?
      raise "C_ab place divisor space failed certification"

  ro :space, :divisor, :evaluation_kernel, :function_subspace

  -> dimension
    @function_subspace.dimension

  -> codimension
    @function_subspace.codimension

  -> independent_conditions_theorem_applies?
    @space.bound - @divisor.degree >= 2*@space.model.genus - 1

  -> independent_conditions_certified?
    independent_conditions_theorem_applies? && (
      codimension == @divisor.degree)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ CAbDivisorSpaceCertificate
  -> new(@divisor_space)
    @verified_cache = nil

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
    return false if @divisor_space.class_name != "CAbDivisorSpace"
    space = @divisor_space.space
    divisor = @divisor_space.divisor
    return false if !space.certified? || !divisor.certified?
    return false if space.model != divisor.model
    kernel = @divisor_space.evaluation_kernel
    return false if !kernel.certified?
    return false if !kernel.subspace.same_subspace?(
      @divisor_space.function_subspace)
    if @divisor_space.independent_conditions_theorem_applies?
      return false if @divisor_space.codimension != divisor.degree
      return false if @divisor_space.dimension != (
        space.bound - divisor.degree + 1 - space.model.genus)
    true

  -> certified?
    verified?

  -> proof_kind
    :riemann_roch_dimension_with_exact_kernel_replay

  -> theorem
    "if deg(n*infinity-D) >= 2g-1, then W_D(n)=L(n*infinity-D) has dimension n-deg(D)+1-g"

  -> theorem_reference
    "Riemann-Roch in nonspecial degree"

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    true


+ CAbDivisorSpace
  -> new(@space, @divisor)
    if @space.class_name != "CAbRiemannRochSpace"
      raise "C_ab divisor spaces need a Riemann-Roch space"
    if @divisor.class_name != "CAbEffectivePointDivisor"
      raise "C_ab divisor spaces need an effective point divisor"
    if @space.model != @divisor.model
      raise "C_ab divisor space uses a different curve model"
    @evaluation_kernel = @space.evaluation_kernel(@divisor.points)
    @function_subspace = @evaluation_kernel.subspace
    @certificate_cache = CAbDivisorSpaceCertificate.new(self)
    if !@certificate_cache.verified?
      raise "C_ab divisor space failed certification"

  ro :space, :divisor, :evaluation_kernel, :function_subspace

  -> dimension
    @function_subspace.dimension

  -> codimension
    @function_subspace.codimension

  -> independent_conditions_theorem_applies?
    @space.bound - @divisor.degree >= 2*@space.model.genus - 1

  -> independent_conditions_certified?
    independent_conditions_theorem_applies? && (
      codimension == @divisor.degree)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    ("L(" + @space.bound.to_s + "*infinity - D_" +
     @divisor.degree.to_s + ")")

  -> inspect
    to_s


