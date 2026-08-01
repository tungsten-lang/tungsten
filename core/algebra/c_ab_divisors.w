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

  -> model
    @model

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

  -> model
    @model

  -> formal_divisor
    @formal_divisor

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

  -> space
    @space

  -> divisor
    @divisor

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

  -> subspace
    @subspace

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

  -> space
    @space

  -> divisor
    @divisor

  -> evaluation_kernel
    @evaluation_kernel

  -> function_subspace
    @function_subspace

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

  -> space
    @space

  -> divisor
    @divisor

  -> evaluation_kernel
    @evaluation_kernel

  -> function_subspace
    @function_subspace

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


+ CAbKhuriMakdisiRepresentativeCertificate
  -> new(@representative)
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
    return false if @representative.class_name != (
      "CAbKhuriMakdisiRepresentative")
    model = @representative.model
    divisor = @representative.divisor
    base_degree = @representative.base_degree
    return false if !model.certified? || !divisor.certified?
    valid_divisor = divisor.class_name == "CAbEffectivePointDivisor"
    valid_divisor = true if divisor.class_name == "CAbEffectivePlaceDivisor"
    return false if !valid_divisor
    return false if divisor.model != model
    return false if divisor.degree != base_degree
    return false if base_degree < 2*model.genus + 1
    divisor_space = @representative.divisor_space
    return false if !divisor_space.certified?
    return false if divisor_space.space.bound != 2*base_degree
    return false if !divisor_space.independent_conditions_certified?
    return false if divisor_space.dimension != (
      base_degree + 1 - model.genus)
    true

  -> certified?
    verified?

  -> proof_kind
    :khuri_makdisi_representation_with_exact_c_ab_replay

  -> theorem
    "for d0 >= 2g+1, W_D=L(2d0*infinity-D) represents the degree-zero divisor class [D-d0*infinity]"

  -> theorem_reference
    "Khuri-Makdisi linear-algebra representation of Jacobian points"

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    true


+ CAbKhuriMakdisiRepresentative
  -> new(@model, @divisor, base_degree = nil)
    if @model.class_name != "CAbCurveModel"
      raise "Khuri-Makdisi representatives need a C_ab curve model"
    valid_divisor = @divisor.class_name == "CAbEffectivePointDivisor"
    valid_divisor = true if @divisor.class_name == "CAbEffectivePlaceDivisor"
    if !valid_divisor || @divisor.model != @model
      raise "Khuri-Makdisi representative needs a divisor on its curve"
    @base_degree = base_degree == nil ? @divisor.degree : base_degree
    if @divisor.degree != @base_degree
      raise "Khuri-Makdisi point divisor must have the base degree"
    if @base_degree < 2*@model.genus + 1
      raise "Khuri-Makdisi base degree must be at least 2g+1"
    ambient = @model.riemann_roch_space(2*@base_degree)
    if @divisor.class_name == "CAbEffectivePointDivisor"
      @divisor_space = CAbDivisorSpace.new(ambient, @divisor)
    else
      @divisor_space = CAbPlaceDivisorSpace.new(ambient, @divisor)
    @certificate_cache = CAbKhuriMakdisiRepresentativeCertificate.new(self)
    if !@certificate_cache.verified?
      raise "Khuri-Makdisi representative failed certification"

  -> model
    @model

  -> divisor
    @divisor

  -> base_degree
    @base_degree

  -> divisor_space
    @divisor_space

  -> function_subspace
    @divisor_space.function_subspace

  -> dimension
    @divisor_space.dimension

  -> class_description
    ("D_" + @divisor.degree.to_s + "_minus_" +
     @base_degree.to_s + "_Inf")

  -> unreduced_product(other)
    CAbKhuriMakdisiProduct.new(self, other)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    "KM " + class_description

  -> inspect
    to_s


+ CAbKhuriMakdisiProductCertificate
  -> new(@product)
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
    return false if @product.class_name != "CAbKhuriMakdisiProduct"
    left = @product.left
    right = @product.right
    return false if !left.certified? || !right.certified?
    return false if left.model != right.model
    return false if left.base_degree != right.base_degree
    return false if !left.divisor.disjoint?(right.divisor)
    expected = @product.expected_divisor_space
    return false if !expected.certified?
    return false if !@product.function_subspace.same_subspace?(
      expected.function_subspace)
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_unreduced_khuri_makdisi_product_replay

  -> theorem
    "the replayed product W_D*W_E equals L(4d0*infinity-D-E) and represents [D+E-2d0*infinity]"

  -> theorem_reference
    "Khuri-Makdisi subspace multiplication"

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    true


+ CAbKhuriMakdisiProduct
  -> new(@left, @right)
    if @left.class_name != "CAbKhuriMakdisiRepresentative" || (
         @right.class_name != "CAbKhuriMakdisiRepresentative")
      raise "Khuri-Makdisi product needs two representatives"
    if @left.model != @right.model || (
         @left.base_degree != @right.base_degree)
      raise "Khuri-Makdisi representatives use different base data"
    if !@left.divisor.disjoint?(@right.divisor)
      raise "squarefree Khuri-Makdisi product needs disjoint support"
    @combined_divisor = @left.divisor.sum(@right.divisor)
    target = @left.model.riemann_roch_space(4*@left.base_degree)
    @function_subspace = @left.function_subspace.multiply(
      @right.function_subspace, target)
    if @combined_divisor.class_name == "CAbEffectivePointDivisor"
      @expected_divisor_space = CAbDivisorSpace.new(
        target, @combined_divisor)
    else
      @expected_divisor_space = CAbPlaceDivisorSpace.new(
        target, @combined_divisor)
    @certificate_cache = CAbKhuriMakdisiProductCertificate.new(self)
    if !@certificate_cache.verified?
      raise "Khuri-Makdisi product did not fill the expected divisor space"

  -> left
    @left

  -> right
    @right

  -> combined_divisor
    @combined_divisor

  -> function_subspace
    @function_subspace

  -> expected_divisor_space
    @expected_divisor_space

  -> dimension
    @function_subspace.dimension

  -> class_description
    ("D_plus_E_minus_" + (2*@left.base_degree).to_s + "_Inf")

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    "unreduced KM product " + class_description

  -> inspect
    to_s


+ CAbKhuriMakdisiZeroCertificate
  -> new(@zero)
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
    return false if @zero.class_name != "CAbKhuriMakdisiZero"
    model = @zero.model
    base_degree = @zero.base_degree
    return false if !model.certified?
    return false if base_degree < 2*model.genus + 1
    expected = model.riemann_roch_space(base_degree).embedded_subspace(
      model.riemann_roch_space(2*base_degree))
    return false if !expected.same_subspace?(@zero.function_subspace)
    return false if @zero.dimension != base_degree + 1 - model.genus
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_khuri_makdisi_zero_representation

  -> theorem
    "L(d0*infinity), embedded in L(2d0*infinity), represents the zero class [d0*infinity-d0*infinity]"

  -> theorem_reference
    "Khuri-Makdisi identity representation"

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    true


+ CAbKhuriMakdisiZero
  -> new(@model, @base_degree)
    if @model.class_name != "CAbCurveModel"
      raise "Khuri-Makdisi zero needs a C_ab curve model"
    if @base_degree < 2*@model.genus + 1
      raise "Khuri-Makdisi base degree must be at least 2g+1"
    source = @model.riemann_roch_space(@base_degree)
    target = @model.riemann_roch_space(2*@base_degree)
    @function_subspace = source.embedded_subspace(target)
    @certificate_cache = CAbKhuriMakdisiZeroCertificate.new(self)
    if !@certificate_cache.verified?
      raise "Khuri-Makdisi zero representation failed certification"

  -> model
    @model

  -> base_degree
    @base_degree

  -> function_subspace
    @function_subspace

  -> dimension
    @function_subspace.dimension

  -> class_description
    "zero"

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    "KM zero"

  -> inspect
    to_s


+ CAbKhuriMakdisiAffineZeroCertificate
  -> new(@zero)
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
    return false if @zero.class_name != "CAbKhuriMakdisiAffineZero"
    model = @zero.model
    base_degree = @zero.base_degree
    return false if !model.certified?
    return false if base_degree < 2*model.genus + 1
    function = @zero.principal_function
    return false if model.pole_bound(function) != base_degree
    divisor = @zero.divisor
    return false if !divisor.certified?
    return false if divisor.degree != base_degree
    points = divisor.points
    index = 0
    while index < points.size
      return false if !model.field.zero?(
        model.evaluate(function, points[index]))
      index += 1
    representative = @zero.representative
    return false if !representative.certified?
    return false if !representative.function_subspace.same_subspace?(
      @zero.function_subspace)
    true

  -> certified?
    verified?

  -> proof_kind
    :principal_affine_zero_with_exact_c_ab_replay

  -> theorem
    "a function of exact pole order d0 with d0 distinct affine zeros has divisor E-d0*infinity, so E represents the zero Jacobian class"

  -> theorem_reference
    "degree zero of a principal divisor and the moving lemma"

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    true


+ CAbKhuriMakdisiAffineZero
  # Deterministic producer for a moving-lemma identity representative.  The
  # exact certificate below remains the authority: this search merely scans
  # normalized coefficient vectors until it finds a function whose full
  # degree-d0 zero divisor is rational, squarefree, and affine.
  -> .search(model, base_degree, max_candidates = nil)
    if model.class_name != "CAbCurveModel" || (
         model.field.class_name != "FiniteField") || (
         !model.field.prime_field?)
      raise "affine Khuri-Makdisi zero search needs a prime-field C_ab model"
    if base_degree < 2*model.genus + 1
      raise "affine Khuri-Makdisi zero search needs d0 at least 2g+1"
    space = model.riemann_roch_space(base_degree)
    basis = space.basis
    pivot = nil
    index = 0
    while index < basis.size && pivot == nil
      pivot = index if model.pole_bound(basis[index]) == base_degree
      index += 1
    if pivot == nil
      raise "L(d0*infinity) has no function of exact pole order d0"

    prime = model.field.characteristic
    free_count = space.dimension - 1
    total = prime ** free_count
    limit = total
    if max_candidates != nil && max_candidates < limit
      limit = max_candidates
    if limit < 0
      raise "affine Khuri-Makdisi zero search limit must be nonnegative"

    points = model.affine_rational_points
    candidate_index = 0
    while candidate_index < limit
      vector = []
      coordinate = 0
      while coordinate < space.dimension
        vector.push(0)
        coordinate += 1
      vector[pivot] = 1
      digits = candidate_index
      coordinate = 0
      while coordinate < space.dimension
        if coordinate != pivot
          vector[coordinate] = digits % prime
          digits = digits / prime
        coordinate += 1
      function = space.function(vector)
      zero_count = 0
      point_index = 0
      while point_index < points.size && zero_count <= base_degree
        if model.field.zero?(model.evaluate(function, points[point_index]))
          zero_count += 1
        point_index += 1
      if zero_count == base_degree
        return CAbKhuriMakdisiAffineZero.new(
          model, base_degree, function)
      candidate_index += 1
    raise (
      "no affine Khuri-Makdisi zero found in " + limit.to_s +
      " normalized candidates")

  -> new(@model, @base_degree, principal_function)
    if @model.class_name != "CAbCurveModel"
      raise "affine Khuri-Makdisi zero needs a C_ab curve model"
    if @base_degree < 2*@model.genus + 1
      raise "Khuri-Makdisi base degree must be at least 2g+1"
    @principal_function = @model.reduce(principal_function)
    if @model.pole_bound(@principal_function) != @base_degree
      raise "affine Khuri-Makdisi zero needs exact pole order d0"
    zeros = []
    points = @model.affine_rational_points
    index = 0
    while index < points.size
      zeros.push(points[index]) if @model.field.zero?(
        @model.evaluate(@principal_function, points[index]))
      index += 1
    if zeros.size != @base_degree
      raise "principal function does not have d0 distinct rational affine zeros"
    @divisor = CAbEffectivePointDivisor.new(@model, zeros)
    @representative = CAbKhuriMakdisiRepresentative.new(
      @model, @divisor, @base_degree)
    @function_subspace = @representative.function_subspace
    @certificate_cache = CAbKhuriMakdisiAffineZeroCertificate.new(self)
    if !@certificate_cache.verified?
      raise "affine Khuri-Makdisi zero failed certification"

  -> model
    @model

  -> base_degree
    @base_degree

  -> principal_function
    @principal_function

  -> divisor
    @divisor

  -> representative
    @representative

  -> function_subspace
    @function_subspace

  -> dimension
    @function_subspace.dimension

  -> class_description
    "zero_affine"

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    "KM affine zero"

  -> inspect
    to_s


+ CAbKhuriMakdisiAddFlipCertificate
  -> new(@addflip)
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
    return false if @addflip.class_name != "CAbKhuriMakdisiAddFlip"
    left = @addflip.left
    right = @addflip.right
    return false if !left.certified? || !right.certified?
    return false if left.model != right.model
    return false if left.base_degree != right.base_degree
    model = left.model
    base_degree = left.base_degree
    expected_dimension = base_degree + 1 - model.genus
    return false if !@addflip.product_subspace.certified?
    return false if !@addflip.section_subspace.certified?
    return false if @addflip.section_subspace.dimension != expected_dimension
    section_functions = @addflip.section_subspace.functions
    return false if section_functions.size == 0
    return false if model.reduce(@addflip.chosen_section).zero?
    return false if model.pole_bound(@addflip.chosen_section) != 3*base_degree
    return false if !@addflip.section_subspace.contains_function?(
      @addflip.chosen_section)
    chosen = nil
    section_index = 0
    while section_index < section_functions.size && chosen == nil
      if model.pole_bound(section_functions[section_index]) == 3*base_degree
        chosen = section_functions[section_index]
      section_index += 1
    return false if chosen == nil || !chosen.eql?(@addflip.chosen_section)
    return false if !@addflip.section_multiple_subspace.certified?
    division = @addflip.division
    return false if !division.certified?
    return false if !division.subspace.same_subspace?(
      @addflip.function_subspace)
    return false if @addflip.dimension != expected_dimension
    true

  -> certified?
    verified?

  -> proof_kind
    :khuri_makdisi_addflip_with_exact_linear_replay

  -> theorem
    "AddFlip intersects W_D W_E with L(3d0*infinity), chooses f, and divides fL(2d0*infinity) by that section space to represent -(x+y)"

  -> theorem_reference
    "Khuri-Makdisi AddFlip algorithm"

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    true


+ CAbKhuriMakdisiAddFlip
  -> new(@left, @right)
    if !valid_input?(@left) || !valid_input?(@right)
      raise "Khuri-Makdisi AddFlip needs certified representatives"
    if @left.model != @right.model || (
         @left.base_degree != @right.base_degree)
      raise "Khuri-Makdisi AddFlip inputs use different base data"
    model = @left.model
    base_degree = @left.base_degree

    ambient2 = model.riemann_roch_space(2*base_degree)
    ambient3 = model.riemann_roch_space(3*base_degree)
    ambient4 = model.riemann_roch_space(4*base_degree)
    ambient5 = model.riemann_roch_space(5*base_degree)

    @product_subspace = @left.function_subspace.multiply(
      @right.function_subspace, ambient4)
    embedded_l3 = ambient3.embedded_subspace(ambient4)
    sections_in_l4 = @product_subspace.intersection(embedded_l3)
    @section_subspace = CAbFunctionSubspace.from_functions(
      ambient3, sections_in_l4.functions)
    if @section_subspace.dimension == 0
      raise "Khuri-Makdisi AddFlip found no section in L(3d0*infinity)"
    section_functions = @section_subspace.functions
    @chosen_section = nil
    section_index = 0
    while section_index < section_functions.size && @chosen_section == nil
      if model.pole_bound(section_functions[section_index]) == 3*base_degree
        @chosen_section = section_functions[section_index]
      section_index += 1
    if @chosen_section == nil
      raise "Khuri-Makdisi AddFlip found no section with exact 3d0 pole order"
    section_line = CAbFunctionSubspace.from_functions(
      ambient3, [@chosen_section])
    @section_multiple_subspace = section_line.multiply(
      ambient2.full_subspace, ambient5)
    @division = @section_subspace.multiplier_preimage_in(
      @section_multiple_subspace, ambient2)
    @function_subspace = @division.subspace
    @certificate_cache = CAbKhuriMakdisiAddFlipCertificate.new(self)
    if !@certificate_cache.verified?
      raise (
        "Khuri-Makdisi AddFlip failed certification: sections=" +
        @section_subspace.dimension.to_s + ", output=" +
        @function_subspace.dimension.to_s)

  -> valid_input?(candidate)
    CAbKhuriMakdisiArithmetic.affine_element?(candidate)

  -> left
    @left

  -> right
    @right

  -> model
    @left.model

  -> base_degree
    @left.base_degree

  -> product_subspace
    @product_subspace

  -> section_subspace
    @section_subspace

  -> chosen_section
    @chosen_section

  -> section_multiple_subspace
    @section_multiple_subspace

  -> division
    @division

  -> function_subspace
    @function_subspace

  -> dimension
    @function_subspace.dimension

  -> class_description
    "negative_sum"

  -> sum_representative(affine_zero)
    if affine_zero.class_name != "CAbKhuriMakdisiAffineZero" || (
         !affine_zero.certified?)
      raise "second AddFlip needs a certified affine zero representative"
    CAbKhuriMakdisiAddFlip.new(self, affine_zero)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    "KM AddFlip result"

  -> inspect
    to_s


+ CAbKhuriMakdisiDifferenceCertificate
  -> new(@difference)
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
    return false if @difference.class_name != "CAbKhuriMakdisiDifference"
    left = @difference.left
    right = @difference.right
    zero = @difference.affine_zero
    return false if !left.certified? || !right.certified? || !zero.certified?
    return false if left.model != right.model || left.model != zero.model
    return false if left.base_degree != right.base_degree || (
      left.base_degree != zero.base_degree)
    negative_right = @difference.negative_right
    negative_difference = @difference.negative_difference
    result = @difference.result
    return false if !negative_right.certified?
    return false if negative_right.left != right || negative_right.right != zero
    return false if !negative_difference.certified?
    return false if negative_difference.left != left || (
      negative_difference.right != negative_right)
    return false if !result.certified?
    return false if result.left != negative_difference || result.right != zero
    return false if !result.function_subspace.same_subspace?(
      @difference.function_subspace)
    return false if @difference.dimension != (
      left.base_degree + 1 - left.model.genus)
    true

  -> certified?
    verified?

  -> proof_kind
    :khuri_makdisi_difference_by_three_addflips

  -> theorem
    "AddFlip(right,0), AddFlip(left,-right), and AddFlip(-(left-right),0) represent left-right"

  -> theorem_reference
    "Khuri-Makdisi AddFlip group law"

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    true


+ CAbKhuriMakdisiDifference
  -> new(@left, @right, @affine_zero)
    if !CAbKhuriMakdisiArithmetic.affine_element?(@left) || (
         !CAbKhuriMakdisiArithmetic.affine_element?(@right))
      raise "Khuri-Makdisi difference needs two affine representatives"
    if @affine_zero.class_name != "CAbKhuriMakdisiAffineZero" || (
         !@affine_zero.certified?)
      raise "Khuri-Makdisi difference needs a certified affine zero"
    if @left.model != @right.model || @left.model != @affine_zero.model || (
         @left.base_degree != @right.base_degree) || (
         @left.base_degree != @affine_zero.base_degree)
      raise "Khuri-Makdisi difference inputs use different base data"
    @negative_right = CAbKhuriMakdisiAddFlip.new(
      @right, @affine_zero)
    @negative_difference = CAbKhuriMakdisiAddFlip.new(
      @left, @negative_right)
    @result = CAbKhuriMakdisiAddFlip.new(
      @negative_difference, @affine_zero)
    @certificate_cache = CAbKhuriMakdisiDifferenceCertificate.new(self)
    if !@certificate_cache.verified?
      raise "Khuri-Makdisi difference failed certification"

  -> left
    @left

  -> right
    @right

  -> affine_zero
    @affine_zero

  -> negative_right
    @negative_right

  -> negative_difference
    @negative_difference

  -> result
    @result

  -> model
    @left.model

  -> base_degree
    @left.base_degree

  -> function_subspace
    @result.function_subspace

  -> dimension
    @result.dimension

  -> class_description
    "left_minus_right"

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    "KM difference"

  -> inspect
    to_s


+ CAbKhuriMakdisiPlaceDifferenceCertificate
  -> new(@difference)
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
    return false if @difference.class_name != (
      "CAbKhuriMakdisiPlaceDifference")
    model = @difference.model
    positive = @difference.positive_divisor
    negative = @difference.negative_divisor
    padding = @difference.padding_divisor
    zero = @difference.affine_zero
    return false if !model.certified? || !positive.certified? || (
      !negative.certified?) || !padding.certified? || !zero.certified?
    return false if positive.model != model || negative.model != model || (
      padding.model != model) || zero.model != model
    return false if positive.degree != negative.degree
    return false if positive.degree + padding.degree != zero.base_degree
    return false if !positive.disjoint?(padding) || (
      !negative.disjoint?(padding))
    return false if !@difference.left_divisor.certified? || (
      !@difference.right_divisor.certified?)
    return false if @difference.left_divisor.degree != zero.base_degree || (
      @difference.right_divisor.degree != zero.base_degree)
    return false if !@difference.left_representative.certified? || (
      !@difference.right_representative.certified?)
    result = @difference.difference
    return false if !result.certified?
    return false if !result.function_subspace.same_subspace?(
      @difference.function_subspace)
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_padded_closed_place_khuri_makdisi_difference

  -> theorem
    "common padding cancels, so the computed Khuri-Makdisi difference represents the positive place divisor minus the negative place divisor"

  -> theorem_reference
    "Khuri-Makdisi divisor-class representation"

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    true


+ CAbKhuriMakdisiPlaceDifference
  -> new(@model, @positive_divisor, @negative_divisor,
         @padding_divisor, @affine_zero)
    divisors = [@positive_divisor, @negative_divisor, @padding_divisor]
    divisors.each -> (divisor)
      if divisor.class_name != "CAbEffectivePlaceDivisor" || (
           divisor.model != @model)
        raise "padded Khuri-Makdisi difference needs place divisors on one model"
    if @positive_divisor.degree != @negative_divisor.degree
      raise "positive and negative place divisors need equal degree"
    if @affine_zero.class_name != "CAbKhuriMakdisiAffineZero" || (
         @affine_zero.model != @model) || !@affine_zero.certified?
      raise "padded Khuri-Makdisi difference needs an affine zero"
    if @positive_divisor.degree + @padding_divisor.degree != (
         @affine_zero.base_degree)
      raise "padding does not fill the Khuri-Makdisi base degree"
    if !@positive_divisor.disjoint?(@padding_divisor) || (
         !@negative_divisor.disjoint?(@padding_divisor))
      raise "Khuri-Makdisi padding must avoid both signed supports"
    @left_divisor = @positive_divisor.sum(@padding_divisor)
    @right_divisor = @negative_divisor.sum(@padding_divisor)
    @left_representative = CAbKhuriMakdisiRepresentative.new(
      @model, @left_divisor, @affine_zero.base_degree)
    @right_representative = CAbKhuriMakdisiRepresentative.new(
      @model, @right_divisor, @affine_zero.base_degree)
    @difference = CAbKhuriMakdisiDifference.new(
      @left_representative, @right_representative, @affine_zero)
    @certificate_cache = CAbKhuriMakdisiPlaceDifferenceCertificate.new(self)
    if !@certificate_cache.verified?
      raise "padded Khuri-Makdisi place difference failed certification"

  -> model
    @model

  -> positive_divisor
    @positive_divisor

  -> negative_divisor
    @negative_divisor

  -> padding_divisor
    @padding_divisor

  -> affine_zero
    @affine_zero

  -> left_divisor
    @left_divisor

  -> right_divisor
    @right_divisor

  -> left_representative
    @left_representative

  -> right_representative
    @right_representative

  -> difference
    @difference

  -> function_subspace
    @difference.function_subspace

  -> dimension
    @difference.dimension

  -> base_degree
    @affine_zero.base_degree

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    "padded KM place difference"

  -> inspect
    to_s


+ CAbKhuriMakdisiArithmetic
  -> .affine_element?(candidate)
    return false if candidate == nil
    name = candidate.class_name
    valid = name == "CAbKhuriMakdisiRepresentative"
    valid = true if name == "CAbKhuriMakdisiAddFlip"
    valid = true if name == "CAbKhuriMakdisiAffineZero"
    valid = true if name == "CAbKhuriMakdisiDifference"
    valid = true if name == "CAbKhuriMakdisiPlaceDifference"
    valid = true if name == "CAbKhuriMakdisiSum"
    valid = true if name == "CAbKhuriMakdisiScalarMultiple"
    return false if !valid
    candidate.certified?

  -> .compatible?(left, right)
    return false if !CAbKhuriMakdisiArithmetic.affine_element?(left) || (
      !CAbKhuriMakdisiArithmetic.affine_element?(right))
    left.model == right.model && left.base_degree == right.base_degree


+ CAbKhuriMakdisiSumCertificate
  -> new(@sum)
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
    return false if @sum.class_name != "CAbKhuriMakdisiSum"
    left = @sum.left
    right = @sum.right
    zero = @sum.affine_zero
    return false if !CAbKhuriMakdisiArithmetic.compatible?(left, right)
    return false if zero.class_name != "CAbKhuriMakdisiAffineZero" || (
      !zero.certified?)
    return false if left.model != zero.model || (
      left.base_degree != zero.base_degree)
    negative = @sum.negative_sum
    result = @sum.result
    return false if !negative.certified? || !result.certified?
    return false if negative.left != left || negative.right != right
    return false if result.left != negative || result.right != zero
    return false if !result.function_subspace.same_subspace?(
      @sum.function_subspace)
    true

  -> certified?
    verified?

  -> proof_kind
    :khuri_makdisi_sum_by_two_addflips

  -> theorem
    "AddFlip(left,right) followed by AddFlip(-(left+right),0) represents left+right"

  -> theorem_reference
    "Khuri-Makdisi AddFlip group law"

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    true


+ CAbKhuriMakdisiSum
  -> new(@left, @right, @affine_zero)
    if !CAbKhuriMakdisiArithmetic.compatible?(@left, @right)
      raise "Khuri-Makdisi sum needs compatible affine representatives"
    if @affine_zero.class_name != "CAbKhuriMakdisiAffineZero" || (
         !@affine_zero.certified?) || @affine_zero.model != @left.model || (
         @affine_zero.base_degree != @left.base_degree)
      raise "Khuri-Makdisi sum needs a compatible affine zero"
    @negative_sum = CAbKhuriMakdisiAddFlip.new(@left, @right)
    @result = CAbKhuriMakdisiAddFlip.new(
      @negative_sum, @affine_zero)
    @certificate_cache = CAbKhuriMakdisiSumCertificate.new(self)
    if !@certificate_cache.verified?
      raise "Khuri-Makdisi sum failed certification"

  -> left
    @left

  -> right
    @right

  -> affine_zero
    @affine_zero

  -> negative_sum
    @negative_sum

  -> result
    @result

  -> model
    @left.model

  -> base_degree
    @left.base_degree

  -> function_subspace
    @result.function_subspace

  -> dimension
    @result.dimension

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    "KM sum"

  -> inspect
    to_s


+ CAbKhuriMakdisiZeroTestCertificate
  -> new(@test)
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
    return false if @test.class_name != "CAbKhuriMakdisiZeroTest"
    element = @test.element
    return false if !CAbKhuriMakdisiArithmetic.affine_element?(element)
    model = element.model
    base_degree = element.base_degree
    ambient = model.riemann_roch_space(2*base_degree)
    return false if element.function_subspace.space.model != model || (
      element.function_subspace.space.bound != ambient.bound)
    base = model.riemann_roch_space(base_degree).embedded_subspace(ambient)
    expected = element.function_subspace.intersection(base)
    return false if !expected.same_subspace?(@test.witness_subspace)
    return false if expected.dimension > 1
    return false if @test.zero? != (expected.dimension == 1)
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_affine_khuri_makdisi_zero_test

  -> theorem
    "for affine D of degree d0, [D-d0*infinity]=0 exactly when L(d0*infinity-D) is nonzero"

  -> theorem_reference
    "degree-zero divisors and Khuri-Makdisi equality testing"

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    true


+ CAbKhuriMakdisiZeroTest
  -> new(@element)
    if !CAbKhuriMakdisiArithmetic.affine_element?(@element)
      raise "Khuri-Makdisi zero test needs an affine representative"
    model = @element.model
    base_degree = @element.base_degree
    ambient = model.riemann_roch_space(2*base_degree)
    if @element.function_subspace.space.model != model || (
         @element.function_subspace.space.bound != ambient.bound)
      raise "Khuri-Makdisi zero test has the wrong ambient space"
    base = model.riemann_roch_space(base_degree).embedded_subspace(ambient)
    @witness_subspace = @element.function_subspace.intersection(base)
    if @witness_subspace.dimension > 1
      raise "Khuri-Makdisi zero test encountered support at the base point"
    @zero = @witness_subspace.dimension == 1
    @certificate_cache = CAbKhuriMakdisiZeroTestCertificate.new(self)
    if !@certificate_cache.verified?
      raise "Khuri-Makdisi zero test failed certification"

  -> element
    @element

  -> witness_subspace
    @witness_subspace

  -> witness
    return nil if !@zero
    @witness_subspace.functions[0]

  -> zero?
    @zero

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ CAbKhuriMakdisiEqualityCertificate
  -> new(@equality)
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
    return false if @equality.class_name != "CAbKhuriMakdisiEquality"
    left = @equality.left
    right = @equality.right
    return false if !CAbKhuriMakdisiArithmetic.compatible?(left, right)
    difference = @equality.difference
    zero_test = @equality.zero_test
    return false if !difference.certified? || !zero_test.certified?
    return false if difference.left != left || difference.right != right
    return false if zero_test.element != difference
    @equality.equal? == zero_test.zero?

  -> certified?
    verified?

  -> proof_kind
    :exact_khuri_makdisi_equality_by_zero_difference

  -> theorem
    "two Jacobian representatives are equal exactly when their difference is zero"

  -> theorem_reference
    "Jacobian group law"

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    true


+ CAbKhuriMakdisiEquality
  -> new(@left, @right, @affine_zero)
    if !CAbKhuriMakdisiArithmetic.compatible?(@left, @right)
      raise "Khuri-Makdisi equality needs compatible affine representatives"
    @difference = CAbKhuriMakdisiDifference.new(
      @left, @right, @affine_zero)
    @zero_test = CAbKhuriMakdisiZeroTest.new(@difference)
    @equal = @zero_test.zero?
    @certificate_cache = CAbKhuriMakdisiEqualityCertificate.new(self)
    if !@certificate_cache.verified?
      raise "Khuri-Makdisi equality failed certification"

  -> left
    @left

  -> right
    @right

  -> difference
    @difference

  -> zero_test
    @zero_test

  -> equal?
    @equal

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ CAbKhuriMakdisiScalarMultipleCertificate
  -> new(@multiple)
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

  -> .known_multiple(elements, multiples, candidate, wanted)
    index = 0
    while index < elements.size
      return true if elements[index] == candidate && multiples[index] == wanted
      index += 1
    false

  -> verify!
    return false if @multiple.class_name != "CAbKhuriMakdisiScalarMultiple"
    element = @multiple.element
    zero = @multiple.affine_zero
    return false if !CAbKhuriMakdisiArithmetic.affine_element?(element)
    return false if zero.class_name != "CAbKhuriMakdisiAffineZero" || (
      !zero.certified?)
    return false if element.model != zero.model || (
      element.base_degree != zero.base_degree)
    known_elements = [zero, element]
    known_multiples = [0, 1]
    trace = @multiple.trace
    index = 0
    while index < trace.size
      record = trace[index]
      operation = record[0]
      left = record[1]
      right = record[2]
      left_multiple = record[3]
      right_multiple = record[4]
      output_multiple = record[5]
      return false if !CAbKhuriMakdisiScalarMultipleCertificate.known_multiple(
        known_elements, known_multiples, left, left_multiple)
      return false if !CAbKhuriMakdisiScalarMultipleCertificate.known_multiple(
        known_elements, known_multiples, right, right_multiple)
      return false if !operation.certified?
      if operation.class_name == "CAbKhuriMakdisiSum"
        return false if operation.left != left || operation.right != right
        return false if output_multiple != left_multiple + right_multiple
      elsif operation.class_name == "CAbKhuriMakdisiDifference"
        return false if operation.left != left || operation.right != right
        return false if output_multiple != left_multiple - right_multiple
      else
        return false
      known_elements.push(operation)
      known_multiples.push(output_multiple)
      index += 1
    return false if !CAbKhuriMakdisiScalarMultipleCertificate.known_multiple(
      known_elements, known_multiples, @multiple.result, @multiple.scalar)
    true

  -> certified?
    verified?

  -> proof_kind
    :certified_binary_khuri_makdisi_scalar_chain

  -> theorem
    "the replayed binary addition chain represents the stated integer multiple"

  -> theorem_reference
    "binary scalar multiplication in an abelian group"

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    true


+ CAbKhuriMakdisiScalarMultiple
  -> new(@element, @scalar, @affine_zero)
    if !CAbKhuriMakdisiArithmetic.affine_element?(@element)
      raise "Khuri-Makdisi scalar multiplication needs an affine representative"
    scalar_class = @scalar.class_name
    if scalar_class != "Integer" && scalar_class != "Int" && (
         scalar_class != "BigInt")
      raise "Khuri-Makdisi scalar must be an integer"
    if @affine_zero.class_name != "CAbKhuriMakdisiAffineZero" || (
         !@affine_zero.certified?) || @affine_zero.model != @element.model || (
         @affine_zero.base_degree != @element.base_degree)
      raise "Khuri-Makdisi scalar multiplication needs a compatible affine zero"
    @trace = []
    magnitude = @scalar < 0 ? 0 - @scalar : @scalar
    result = @affine_zero
    result_multiple = 0
    addend = @element
    addend_multiple = 1
    while magnitude > 0
      if magnitude.odd?
        operation = CAbKhuriMakdisiSum.new(
          result, addend, @affine_zero)
        @trace.push([
          operation, result, addend, result_multiple,
          addend_multiple, result_multiple + addend_multiple])
        result = operation
        result_multiple += addend_multiple
      magnitude = magnitude / 2
      if magnitude > 0
        operation = CAbKhuriMakdisiSum.new(
          addend, addend, @affine_zero)
        @trace.push([
          operation, addend, addend, addend_multiple,
          addend_multiple, 2*addend_multiple])
        addend = operation
        addend_multiple *= 2
    if @scalar < 0
      operation = CAbKhuriMakdisiDifference.new(
        @affine_zero, result, @affine_zero)
      @trace.push([
        operation, @affine_zero, result, 0,
        result_multiple, 0 - result_multiple])
      result = operation
      result_multiple = 0 - result_multiple
    @result = result
    if result_multiple != @scalar
      raise "Khuri-Makdisi scalar chain ended at the wrong multiple"
    @certificate_cache = CAbKhuriMakdisiScalarMultipleCertificate.new(self)
    if !@certificate_cache.verified?
      raise "Khuri-Makdisi scalar multiplication failed certification"

  -> element
    @element

  -> scalar
    @scalar

  -> affine_zero
    @affine_zero

  -> trace
    out = []
    index = 0
    while index < @trace.size
      record = @trace[index]
      out.push([
        record[0], record[1], record[2],
        record[3], record[4], record[5]])
      index += 1
    out

  -> result
    @result

  -> model
    @element.model

  -> base_degree
    @element.base_degree

  -> function_subspace
    @result.function_subspace

  -> dimension
    @result.dimension

  -> zero_test
    CAbKhuriMakdisiZeroTest.new(self)

  -> zero?
    zero_test.zero?

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    @scalar.to_s + " * KM element"

  -> inspect
    to_s


+ CAbKhuriMakdisiOrderCertificate
  -> new(@order_computation)
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
    return false if @order_computation.class_name != "CAbKhuriMakdisiOrder"
    element = @order_computation.element
    zero = @order_computation.affine_zero
    return false if !CAbKhuriMakdisiArithmetic.affine_element?(element)
    return false if zero.class_name != "CAbKhuriMakdisiAffineZero" || (
      !zero.certified?)
    return false if element.model != zero.model || (
      element.base_degree != zero.base_degree)
    group_order = element.model.curve.zeta.numerator.at(1)
    return false if group_order != @order_computation.group_order
    order = @order_computation.order
    return false if order < 1 || group_order % order != 0
    annihilator = @order_computation.annihilator
    return false if !annihilator.certified? || annihilator.scalar != order
    return false if annihilator.element != element || !annihilator.zero?
    witnesses = @order_computation.minimality_witnesses
    factors = order.factor
    return false if witnesses.size != factors.size
    index = 0
    while index < factors.size
      factor = factors[index]
      witness = witnesses[index]
      return false if witness[0] != factor.prime
      multiple = witness[1]
      return false if !multiple.certified?
      return false if multiple.element != element
      return false if multiple.scalar != order / factor.prime
      return false if multiple.zero?
      index += 1
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_finite_jacobian_element_order

  -> theorem
    "the zeta numerator gives the finite Jacobian order; nP=0 and (n/l)P nonzero for every prime l dividing n certify ord(P)=n"

  -> theorem_reference
    "Weil zeta function, Lagrange theorem, and prime-divisor order criterion"

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    true


+ CAbKhuriMakdisiOrder
  -> new(@element, @affine_zero)
    if !CAbKhuriMakdisiArithmetic.affine_element?(@element)
      raise "Khuri-Makdisi order needs an affine representative"
    if @affine_zero.class_name != "CAbKhuriMakdisiAffineZero" || (
         !@affine_zero.certified?) || @affine_zero.model != @element.model || (
         @affine_zero.base_degree != @element.base_degree)
      raise "Khuri-Makdisi order needs a compatible affine zero"
    @group_order = @element.model.curve.zeta.numerator.at(1)
    current = @group_order
    factors = @group_order.factor
    factor_index = 0
    while factor_index < factors.size
      prime = factors[factor_index].prime
      while current % prime == 0
        candidate = CAbKhuriMakdisiScalarMultiple.new(
          @element, current / prime, @affine_zero)
        if candidate.zero?
          current = current / prime
        else
          break
      factor_index += 1
    @order = current
    @annihilator = CAbKhuriMakdisiScalarMultiple.new(
      @element, @order, @affine_zero)
    if !@annihilator.zero?
      raise "candidate Khuri-Makdisi order does not annihilate the element"
    @minimality_witnesses = []
    order_factors = @order.factor
    factor_index = 0
    while factor_index < order_factors.size
      prime = order_factors[factor_index].prime
      witness = CAbKhuriMakdisiScalarMultiple.new(
        @element, @order / prime, @affine_zero)
      if witness.zero?
        raise "candidate Khuri-Makdisi order is not minimal"
      @minimality_witnesses.push([prime, witness])
      factor_index += 1
    @certificate_cache = CAbKhuriMakdisiOrderCertificate.new(self)
    if !@certificate_cache.verified?
      raise "Khuri-Makdisi order failed certification"

  -> element
    @element

  -> affine_zero
    @affine_zero

  -> group_order
    @group_order

  -> order
    @order

  -> annihilator
    @annihilator

  -> minimality_witnesses
    out = []
    index = 0
    while index < @minimality_witnesses.size
      out.push([
        @minimality_witnesses[index][0],
        @minimality_witnesses[index][1]])
      index += 1
    out

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    "KM element order " + @order.to_s

  -> inspect
    to_s


+ CAbKhuriMakdisiNondivisibilityCertificate
  -> new(@result)
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
    return false if @result.class_name != (
      "CAbKhuriMakdisiNondivisibility")
    order = @result.order_computation
    return false if order.class_name != "CAbKhuriMakdisiOrder" || (
      !order.certified?)
    expected = []
    factors = order.group_order.factor
    index = 0
    while index < factors.size
      factor = factors[index]
      exponent = CAbKhuriMakdisiNondivisibility.valuation(
        order.order, factor.prime)
      if exponent == factor.exponent
        expected.push(factor.prime)
      index += 1
    return false if expected.to_s != @result.primes.to_s
    true

  -> certified?
    verified?

  -> proof_kind
    :finite_group_prime_nondivisibility_from_exact_order

  -> theorem
    "if v_l(ord(x)) equals v_l(|G|), then x is not in lG"

  -> theorem_reference
    "primary decomposition of a finite abelian group"

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true


+ CAbKhuriMakdisiNondivisibility
  -> .valuation(number, prime)
    value = number
    exponent = 0
    while value % prime == 0
      value = value / prime
      exponent += 1
    exponent

  -> new(@order_computation)
    if @order_computation.class_name != "CAbKhuriMakdisiOrder" || (
         !@order_computation.certified?)
      raise "finite nondivisibility needs a certified KM order"
    @primes = []
    factors = @order_computation.group_order.factor
    index = 0
    while index < factors.size
      factor = factors[index]
      exponent = CAbKhuriMakdisiNondivisibility.valuation(
        @order_computation.order, factor.prime)
      if exponent == factor.exponent
        @primes.push(factor.prime)
      index += 1
    @certificate_cache = CAbKhuriMakdisiNondivisibilityCertificate.new(self)
    if !@certificate_cache.verified?
      raise "finite KM nondivisibility failed certification"

  -> order_computation
    @order_computation

  -> primes
    out = []
    @primes.each -> out.push(item)
    out

  -> odd_primes
    out = []
    @primes.each -> (prime)
      out.push(prime) if prime != 2
    out

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    "not divisible by " + @primes.to_s

  -> inspect
    to_s
