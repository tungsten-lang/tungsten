# Exact one-point C_ab function spaces.
#
# A smooth C_ab curve has affine coordinates x,y with
#
#   ord_infinity(x) = -a,  ord_infinity(y) = -b,  gcd(a,b) = 1,
#
# and a relation whose leading terms are y^a and x^b.  Every affine function
# has a unique normal form
#
#   sum c_ij x^i y^j,  0 <= j < a.
#
# The resulting monomial spaces L(n infinity) are the small exact linear
# spaces used by Khuri--Makdisi and ideal-class Jacobian arithmetic.  This
# file implements that representation and multiplication; divisor-class
# reduction is a separate layer.

+ CAbFunctionSubspaceCertificate
  -> new(@function_subspace)
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
    return false if @function_subspace.class_name != "CAbFunctionSubspace"
    space = @function_subspace.space
    return false if !space.certified?
    field = space.model.field
    return false if field.class_name != "FiniteField"
    return false if !field.prime_field?
    vectors = @function_subspace.coordinate_subspace
    return false if !vectors.certified?
    return false if vectors.prime != field.characteristic
    return false if vectors.ambient_dimension != space.dimension
    basis = vectors.basis
    index = 0
    while index < basis.size
      function = space.function(basis[index])
      return false if space.coordinates(function).to_s != basis[index].to_s
      index += 1
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_c_ab_function_subspace_coordinate_replay

  -> theorem
    "a function subspace is represented by its canonical coordinate row space in a certified C_ab Riemann-Roch basis"

  -> theorem_reference
    "finite-dimensional linear algebra in L(n infinity)"

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    true


+ CAbFunctionSubspace
  -> new(@space, vectors)
    if @space.class_name != "CAbRiemannRochSpace"
      raise "C_ab function subspaces need a Riemann-Roch space"
    field = @space.model.field
    if field.class_name != "FiniteField" || !field.prime_field?
      raise "C_ab function subspaces currently need a prime field"
    if vectors.class_name == "PrimeFieldSubspace"
      if vectors.prime != field.characteristic
        raise "C_ab function subspace has the wrong prime field"
      if vectors.ambient_dimension != @space.dimension
        raise "C_ab function subspace has the wrong ambient dimension"
      @coordinate_subspace = vectors
    else
      @coordinate_subspace = PrimeFieldSubspace.new(
        field.characteristic, @space.dimension, vectors)
    @certificate_cache = CAbFunctionSubspaceCertificate.new(self)
    if !@certificate_cache.verified?
      raise "C_ab function subspace failed certification"

  -> .from_functions(space, functions)
    if functions.class_name != "Array"
      raise "C_ab function subspace functions must be an array"
    vectors = []
    index = 0
    while index < functions.size
      vectors.push(space.coordinates(functions[index]))
      index += 1
    CAbFunctionSubspace.new(space, vectors)

  -> .full(space)
    field = space.model.field
    CAbFunctionSubspace.new(
      space,
      PrimeFieldSubspace.full(
        field.characteristic, space.dimension))

  -> .zero(space)
    field = space.model.field
    CAbFunctionSubspace.new(
      space,
      PrimeFieldSubspace.zero(
        field.characteristic, space.dimension))

  -> space
    @space

  -> model
    @space.model

  -> dimension
    @coordinate_subspace.dimension

  -> codimension
    @coordinate_subspace.codimension

  -> coordinate_subspace
    @coordinate_subspace

  -> basis_vectors
    @coordinate_subspace.basis

  -> functions
    out = []
    vectors = basis_vectors
    index = 0
    while index < vectors.size
      out.push(@space.function(vectors[index]))
      index += 1
    out

  -> contains_function?(function)
    @coordinate_subspace.contains_vector?(
      @space.coordinates(function))

  -> same_ambient!(other)
    if other.class_name != "CAbFunctionSubspace"
      raise "C_ab function-space operation needs another subspace"
    if other.space.model != @space.model || (
         other.space.bound != @space.bound)
      raise "C_ab function subspaces have different ambient spaces"
    true

  -> same_subspace?(other)
    return false if other.class_name != "CAbFunctionSubspace"
    return false if other.space.model != @space.model
    return false if other.space.bound != @space.bound
    @coordinate_subspace.same_subspace?(other.coordinate_subspace)

  -> contains_subspace?(other)
    same_ambient!(other)
    @coordinate_subspace.contains_subspace?(other.coordinate_subspace)

  -> sum(other)
    same_ambient!(other)
    CAbFunctionSubspace.new(
      @space, @coordinate_subspace.sum(other.coordinate_subspace))

  -> intersection(other)
    same_ambient!(other)
    CAbFunctionSubspace.new(
      @space,
      @coordinate_subspace.intersection(other.coordinate_subspace))

  -> multiply(other, target_space = nil)
    if other.class_name != "CAbFunctionSubspace" || (
         other.space.model != @space.model)
      raise "C_ab subspace multiplication needs the same curve model"
    target = target_space
    if target == nil
      target = @space.model.riemann_roch_space(
        @space.bound + other.space.bound)
    if target.class_name != "CAbRiemannRochSpace" || (
         target.model != @space.model)
      raise "C_ab product target uses a different curve model"
    if target.bound < @space.bound + other.space.bound
      raise "C_ab product target pole bound is too small"
    products = []
    left_functions = functions
    right_functions = other.functions
    left_index = 0
    while left_index < left_functions.size
      right_index = 0
      while right_index < right_functions.size
        product = @space.model.multiply(
          left_functions[left_index], right_functions[right_index],
          target.bound)
        products.push(target.coordinates(product))
        right_index += 1
      left_index += 1
    CAbFunctionSubspace.new(target, products)

  -> embedded_in(target_space)
    if target_space.class_name != "CAbRiemannRochSpace" || (
         target_space.model != @space.model)
      raise "C_ab subspace embedding target uses a different curve model"
    if target_space.bound < @space.bound
      raise "C_ab subspace embedding target pole bound is too small"
    CAbFunctionSubspace.from_functions(target_space, functions)

  # Return all g in candidate_space such that g*self is contained in target.
  -> multiplier_preimage_in(target, candidate_space)
    CAbMultiplierPreimage.new(target, self, candidate_space)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    ("function subspace(" + dimension.to_s + "/" +
     @space.dimension.to_s + " in " + @space.to_s + ")")

  -> inspect
    to_s


+ CAbEvaluationKernelCertificate
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
    return false if @kernel.class_name != "CAbEvaluationKernel"
    space = @kernel.space
    return false if !space.certified?
    matrix = []
    points = @kernel.points
    point_index = 0
    while point_index < points.size
      row = []
      basis = space.basis
      basis_index = 0
      while basis_index < basis.size
        row.push(space.model.evaluate(
          basis[basis_index], points[point_index]))
        basis_index += 1
      matrix.push(row)
      point_index += 1
    return false if matrix.to_s != @kernel.evaluation_matrix.to_s
    expected = PrimeFieldSubspace.kernel(
      matrix, space.model.field.characteristic, space.dimension)
    return false if !expected.same_subspace?(
      @kernel.subspace.coordinate_subspace)
    functions = @kernel.subspace.functions
    function_index = 0
    while function_index < functions.size
      point_index = 0
      while point_index < points.size
        return false if !space.model.field.zero?(
          space.model.evaluate(
            functions[function_index], points[point_index]))
        point_index += 1
      function_index += 1
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_c_ab_evaluation_kernel_replay

  -> theorem
    "the kernel of simultaneous evaluation is exactly the subspace of L(n infinity) vanishing at the listed affine points"

  -> theorem_reference
    "kernel of the evaluation map"

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    true


+ CAbEvaluationKernel
  -> new(@space, points)
    if @space.class_name != "CAbRiemannRochSpace"
      raise "C_ab evaluation kernels need a Riemann-Roch space"
    field = @space.model.field
    if field.class_name != "FiniteField" || !field.prime_field?
      raise "C_ab evaluation kernels currently need a prime field"
    if points.class_name != "Array"
      raise "C_ab evaluation points must be an array"
    @points = []
    index = 0
    while index < points.size
      evaluation_point = points[index]
      # Evaluating zero performs all curve, source-space, and affine checks.
      @space.model.evaluate(@space.model.ring.zero, evaluation_point)
      previous = 0
      while previous < @points.size
        if @points[previous] == evaluation_point
          raise "C_ab evaluation points must be distinct"
        previous += 1
      @points.push(evaluation_point)
      index += 1

    @evaluation_matrix = []
    basis = @space.basis
    index = 0
    while index < @points.size
      row = []
      basis_index = 0
      while basis_index < basis.size
        row.push(@space.model.evaluate(basis[basis_index], @points[index]))
        basis_index += 1
      @evaluation_matrix.push(row)
      index += 1
    coordinate_kernel = PrimeFieldSubspace.kernel(
      @evaluation_matrix, field.characteristic, @space.dimension)
    @subspace = CAbFunctionSubspace.new(@space, coordinate_kernel)
    @certificate_cache = CAbEvaluationKernelCertificate.new(self)
    if !@certificate_cache.verified?
      raise "C_ab evaluation kernel failed certification"

  -> space
    @space

  -> points
    out = []
    index = 0
    while index < @points.size
      out.push(@points[index])
      index += 1
    out

  -> evaluation_matrix
    out = []
    index = 0
    while index < @evaluation_matrix.size
      row = []
      column = 0
      while column < @evaluation_matrix[index].size
        row.push(@evaluation_matrix[index][column])
        column += 1
      out.push(row)
      index += 1
    out

  -> subspace
    @subspace

  -> dimension
    @subspace.dimension

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ CAbMultiplierPreimageCertificate
  -> new(@preimage)
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
    return false if @preimage.class_name != "CAbMultiplierPreimage"
    target = @preimage.target_subspace
    multipliers = @preimage.multiplier_subspace
    candidate = @preimage.candidate_space
    result = @preimage.subspace
    return false if !target.certified? || !multipliers.certified?
    return false if !candidate.certified? || !result.certified?
    return false if target.model != multipliers.model
    return false if target.model != candidate.model
    return false if result.space != candidate
    expected = PrimeFieldSubspace.kernel(
      @preimage.constraint_matrix,
      candidate.model.field.characteristic,
      candidate.dimension)
    return false if !expected.same_subspace?(
      result.coordinate_subspace)
    result_functions = result.functions
    multiplier_functions = multipliers.functions
    result_index = 0
    while result_index < result_functions.size
      multiplier_index = 0
      while multiplier_index < multiplier_functions.size
        product = target.model.multiply(
          result_functions[result_index],
          multiplier_functions[multiplier_index],
          target.space.bound)
        return false if !target.contains_function?(product)
        multiplier_index += 1
      result_index += 1
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_c_ab_multiplier_preimage_kernel

  -> theorem
    "the returned space is exactly {g in L(b infinity) : gU is contained in W}"

  -> theorem_reference
    "linear preimage of a multiplication map"

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    true


+ CAbMultiplierPreimage
  -> new(@target_subspace, @multiplier_subspace, @candidate_space)
    if @target_subspace.class_name != "CAbFunctionSubspace" || (
         @multiplier_subspace.class_name != "CAbFunctionSubspace")
      raise "C_ab multiplier preimage needs function subspaces"
    if @candidate_space.class_name != "CAbRiemannRochSpace"
      raise "C_ab multiplier preimage needs a candidate Riemann-Roch space"
    model = @target_subspace.model
    if @multiplier_subspace.model != model || @candidate_space.model != model
      raise "C_ab multiplier preimage spaces use different curve models"
    if @target_subspace.space.bound < (
         @multiplier_subspace.space.bound + @candidate_space.bound)
      raise "C_ab multiplier-preimage target pole bound is too small"

    prime = model.field.characteristic
    annihilator = @target_subspace.coordinate_subspace.orthogonal_complement
    annihilator_vectors = annihilator.basis
    multiplier_functions = @multiplier_subspace.functions
    candidate_basis = @candidate_space.basis
    @constraint_matrix = []
    multiplier_index = 0
    while multiplier_index < multiplier_functions.size
      # Multiplication is the expensive part.  Build each candidate product
      # once, then apply every quotient-space linear form to those columns.
      # The previous loop order recomputed the same product once per
      # annihilator row, which is especially costly in the interpreter.
      product_columns = []
      candidate_index = 0
      while candidate_index < candidate_basis.size
        product = model.multiply(
          multiplier_functions[multiplier_index],
          candidate_basis[candidate_index],
          @target_subspace.space.bound)
        product_columns.push(
          @target_subspace.space.coordinates(product))
        candidate_index += 1
      annihilator_index = 0
      while annihilator_index < annihilator_vectors.size
        row = []
        candidate_index = 0
        while candidate_index < candidate_basis.size
          product_vector = product_columns[candidate_index]
          dot = 0
          coordinate = 0
          while coordinate < product_vector.size
            dot += annihilator_vectors[annihilator_index][coordinate] * (
              product_vector[coordinate])
            coordinate += 1
          row.push(PrimeLinearAlgebra.normalize(dot, prime))
          candidate_index += 1
        @constraint_matrix.push(row)
        annihilator_index += 1
      multiplier_index += 1
    coordinate_result = PrimeFieldSubspace.kernel(
      @constraint_matrix, prime, @candidate_space.dimension)
    @subspace = CAbFunctionSubspace.new(
      @candidate_space, coordinate_result)
    @certificate_cache = CAbMultiplierPreimageCertificate.new(self)
    if !@certificate_cache.verified?
      raise "C_ab multiplier preimage failed certification"

  -> target_subspace
    @target_subspace

  -> multiplier_subspace
    @multiplier_subspace

  -> candidate_space
    @candidate_space

  -> constraint_matrix
    out = []
    row = 0
    while row < @constraint_matrix.size
      values = []
      column = 0
      while column < @constraint_matrix[row].size
        values.push(@constraint_matrix[row][column])
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

+ CAbRiemannRochSpaceCertificate
  -> new(@space)
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
    return false if @space.class_name != "CAbRiemannRochSpace"
    model = @space.model
    return false if !model.certificate.verified?
    return false if @space.bound < 0
    expected = model.basis_exponents(@space.bound)
    return false if expected.to_s != @space.exponents.to_s
    basis = @space.basis
    return false if basis.size != expected.size
    index = 0
    while index < basis.size
      wanted = model.ring.monomial(
        model.field.one, expected[index])
      return false if !basis[index].eql?(wanted)
      return false if model.pole_bound(basis[index]) > @space.bound
      index += 1
    if @space.bound >= 2*model.genus - 1
      return false if @space.dimension != (
        @space.bound + 1 - model.genus)
    true

  -> certified?
    verified?

  -> proof_kind
    :trusted_c_ab_riemann_roch_basis_with_exact_replay

  -> theorem
    "for a one-point C_ab curve, the monomials x^i y^j with 0 <= j < a and ai+bj <= n form a basis of L(n infinity)"

  -> theorem_reference
    "C_ab curve one-point function-space theorem and Riemann-Roch"

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true


+ CAbRiemannRochSpace
  -> new(@model, @bound)
    if @model.class_name != "CAbCurveModel"
      raise "C_ab Riemann-Roch spaces need a C_ab curve model"
    if @bound.class_name != "Integer" && @bound.class_name != "Int" && (
         @bound.class_name != "BigInt")
      raise "C_ab pole bound must be an integer"
    raise "C_ab pole bound must be nonnegative" if @bound < 0
    @exponents = @model.basis_exponents(@bound)
    @basis = []
    @exponents.each -> (powers)
      @basis.push(@model.ring.monomial(
        @model.field.one, powers))
    @certificate_cache = CAbRiemannRochSpaceCertificate.new(self)
    if !@certificate_cache.verified?
      raise "C_ab Riemann-Roch space failed certification"

  -> model
    @model

  -> bound
    @bound

  -> exponents
    out = []
    @exponents.each -> (powers)
      out.push([powers[0], powers[1]])
    out

  -> basis
    out = []
    @basis.each -> out.push(item)
    out

  -> dimension
    @basis.size

  -> contains?(function)
    @model.pole_bound(function) <= @bound

  -> coordinates(function)
    @model.coordinates(function, @bound)

  -> function(vector)
    @model.from_coordinates(vector, @bound)

  -> multiply(left, right, target_bound = nil)
    limit = target_bound == nil ? 2*@bound : target_bound
    @model.multiply(left, right, limit)

  -> full_subspace
    CAbFunctionSubspace.full(self)

  -> function_subspace(functions)
    CAbFunctionSubspace.from_functions(self, functions)

  -> coordinate_subspace(vectors)
    CAbFunctionSubspace.new(self, vectors)

  -> evaluation_kernel(points)
    CAbEvaluationKernel.new(self, points)

  -> vanishing_subspace(points)
    evaluation_kernel(points).subspace

  -> embedded_subspace(target_space)
    if target_space.class_name != "CAbRiemannRochSpace" || (
         target_space.model != @model)
      raise "C_ab embedding target uses a different curve model"
    if target_space.bound < @bound
      raise "C_ab embedding target pole bound is too small"
    CAbFunctionSubspace.from_functions(target_space, basis)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    "L(" + @bound.to_s + "*infinity; C_ab)"

  -> inspect
    to_s


+ CAbCurveModelCertificate
  -> new(@model)
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
    return false if @model.class_name != "CAbCurveModel"
    curve = @model.curve
    return false if curve.class_name != "Curve"
    return false if !curve.nonsingular?
    return false if @model.x_index == @model.y_index
    return false if @model.x_index == @model.infinity_index
    return false if @model.y_index == @model.infinity_index
    return false if @model.x_pole_order < 1
    return false if @model.y_pole_order < 1
    return false if @model.x_pole_order.gcd(
      @model.y_pole_order) != 1
    return false if @model.genus != curve.genus
    return false if @model.genus != (
      (@model.x_pole_order - 1) *
      (@model.y_pole_order - 1) / 2)
    return false if !@model.unique_infinity_shape?
    equation = @model.affine_equation
    return false if equation.ring != @model.ring
    return false if @model.field.zero?(
      equation.coeff([0, @model.x_pole_order]))
    return false if @model.field.zero?(
      equation.coeff([@model.y_pole_order, 0]))
    return false if !@model.weight_shape_valid?
    return false if !@model.reduce(equation).zero?
    true

  -> certified?
    verified?

  -> proof_kind
    :trusted_c_ab_one_point_model_with_exact_replay

  -> theorem
    "the certified C_ab weighted shape gives a unique place at infinity with pole semigroup generated by a and b"

  -> theorem_reference
    "C_ab curve one-point model theorem"

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true


+ CAbCurveModel
  -> new(@curve, @x_index, @y_index, @infinity_index,
         @x_pole_order, @y_pole_order)
    if @curve.class_name != "Curve"
      raise "C_ab models need a projective plane curve"
    if @curve.space.coordinate_count != 3
      raise "C_ab models currently need a projective plane"
    indices = [@x_index, @y_index, @infinity_index]
    indices.each -> (index)
      if index.class_name != "Integer" && index.class_name != "Int" && (
           index.class_name != "BigInt")
        raise "C_ab coordinate indices must be integers"
      if index < 0 || index >= 3
        raise "C_ab coordinate index out of range"
    if @x_index == @y_index || @x_index == @infinity_index || (
         @y_index == @infinity_index)
      raise "C_ab coordinate indices must be distinct"
    if @x_pole_order < 1 || @y_pole_order < 1
      raise "C_ab pole orders must be positive"
    if @x_pole_order.gcd(@y_pole_order) != 1
      raise "C_ab pole orders must be coprime"

    @field = @curve.field
    names = [
      @curve.space.coordinate_names[@x_index],
      @curve.space.coordinate_names[@y_index]]
    @ring = PolynomialRing.new(names, @field)
    @x = @ring.generator(0)
    @y = @ring.generator(1)
    @affine_equation = build_affine_equation
    @genus = (
      (@x_pole_order - 1) *
      (@y_pole_order - 1) / 2)
    @relation_coefficient = @affine_equation.coeff(
      [0, @x_pole_order])
    if @field.zero?(@relation_coefficient)
      raise "C_ab relation needs a nonzero y^a coefficient"
    leading_y = @ring.monomial_raw(
      @relation_coefficient, [0, @x_pole_order])
    inverse = @field.inverse(@relation_coefficient)
    @relation_rhs = (
      (@affine_equation - leading_y).negate *
      @ring.constant(inverse))
    @certificate_cache = CAbCurveModelCertificate.new(self)
    if !@certificate_cache.verified?
      raise "projective curve does not certify the requested C_ab model"

  -> build_affine_equation
    terms = []
    @curve.equation.terms.each -> (term)
      powers = [
        term[1][@x_index],
        term[1][@y_index]]
      terms.push([term[0], powers])
    Polynomial.new(@ring, terms)

  -> curve
    @curve

  -> field
    @field

  -> ring
    @ring

  -> x
    @x

  -> y
    @y

  -> x_index
    @x_index

  -> y_index
    @y_index

  -> infinity_index
    @infinity_index

  -> x_pole_order
    @x_pole_order

  -> y_pole_order
    @y_pole_order

  -> genus
    @genus

  -> affine_equation
    @affine_equation

  -> relation_rhs
    @relation_rhs

  -> infinity_point
    coordinates = [
      @field.zero, @field.zero, @field.zero]
    coordinates[@y_index] = @field.one
    @curve.space.point_raw(coordinates)

  -> unique_infinity_shape?
    found = false
    terms = @curve.equation.terms
    index = 0
    while index < terms.size
      term = terms[index]
      if term[1][@infinity_index] == 0
        valid = term[1][@x_index] == @curve.degree
        valid = false if term[1][@y_index] != 0
        return false if !valid
        found = true
      index += 1
    found && @curve.contains?(infinity_point)

  -> weight_shape_valid?
    maximum = @x_pole_order*@y_pole_order
    return false if @curve.genus != @genus
    return false if @field.zero?(
      @affine_equation.coeff([0, @x_pole_order]))
    return false if @field.zero?(
      @affine_equation.coeff([@y_pole_order, 0]))
    terms = @affine_equation.terms
    index = 0
    while index < terms.size
      term = terms[index]
      weight = (
        @x_pole_order*term[1][0] +
        @y_pole_order*term[1][1])
      return false if weight > maximum
      return false if term[1][1] > @x_pole_order
      index += 1
    true

  -> basis_exponents(bound)
    raise "C_ab pole bound must be nonnegative" if bound < 0
    out = []
    y_power = 0
    while y_power < @x_pole_order
      x_power = 0
      while (
          @x_pole_order*x_power +
          @y_pole_order*y_power) <= bound
        out.push([x_power, y_power])
        x_power += 1
      y_power += 1
    # Pole weights are distinct for 0 <= y_power < a.  Sort explicitly so
    # coordinates grow in pole order, independently of polynomial term order.
    i = 1
    while i < out.size
      j = i
      while j > 0 && monomial_weight(out[j]) < (
          monomial_weight(out[j - 1]))
        temporary = out[j - 1]
        out[j - 1] = out[j]
        out[j] = temporary
        j -= 1
      i += 1
    out

  -> monomial_weight(powers)
    (@x_pole_order*powers[0] +
     @y_pole_order*powers[1])

  -> reduce(function)
    work = @ring.coerce(function)
    while true
      selected = nil
      work.terms.each -> (term)
        if selected == nil && term[1][1] >= @x_pole_order
          selected = term
      return work if selected == nil
      coefficient = selected[0]
      x_power = selected[1][0]
      y_power = selected[1][1]
      old_term = @ring.monomial_raw(
        coefficient, [x_power, y_power])
      multiplier = @ring.monomial_raw(
        coefficient,
        [x_power, y_power - @x_pole_order])
      work = work - old_term + multiplier*@relation_rhs

  -> pole_bound(function)
    reduced = reduce(function)
    return -1 if reduced.zero?
    bound = 0
    reduced.terms.each -> (term)
      weight = monomial_weight(term[1])
      bound = weight if weight > bound
    bound

  -> coordinates(function, bound)
    reduced = reduce(function)
    actual = pole_bound(reduced)
    if actual > bound
      raise "function exceeds requested C_ab pole bound"
    out = []
    basis_exponents(bound).each -> (powers)
      out.push(reduced.coeff(powers))
    out

  -> from_coordinates(vector, bound)
    exponents = basis_exponents(bound)
    if vector.class_name != "Array" || vector.size != exponents.size
      raise "C_ab coordinate vector has wrong dimension"
    result = @ring.zero
    index = 0
    while index < vector.size
      result = result + @ring.monomial_raw(
        @field.normalize_element(vector[index]),
        exponents[index])
      index += 1
    result

  -> multiply(left, right, bound = nil)
    result = reduce(@ring.coerce(left) * @ring.coerce(right))
    if bound != nil && pole_bound(result) > bound
      raise "C_ab product exceeds requested pole bound"
    result

  -> evaluate(function, point)
    if point.class_name != "ProjectivePoint" || point.space != @curve.space
      raise "C_ab evaluation needs a point on the source curve"
    if !@curve.contains?(point)
      raise "C_ab evaluation point is not on the curve"
    if @field.zero?(point.coordinates[@infinity_index])
      raise "affine C_ab functions are not evaluated at infinity"
    scale = @field.inverse(
      point.coordinates[@infinity_index])
    x_value = @field.multiply(
      point.coordinates[@x_index], scale)
    y_value = @field.multiply(
      point.coordinates[@y_index], scale)
    reduce(function).evaluate_raw([x_value, y_value])

  -> affine_rational_points
    if @field.class_name != "FiniteField"
      raise "C_ab rational-point enumeration needs a finite field"
    points = []
    x_value = 0
    while x_value < @field.order
      y_value = 0
      while y_value < @field.order
        coordinates = [@field.zero, @field.zero, @field.zero]
        coordinates[@x_index] = @field.element_from_index(x_value)
        coordinates[@y_index] = @field.element_from_index(y_value)
        coordinates[@infinity_index] = @field.one
        candidate = @curve.space.point_raw(coordinates)
        points.push(candidate) if @curve.contains?(candidate)
        y_value += 1
      x_value += 1
    points

  -> rational_points
    points = affine_rational_points
    points.push(infinity_point)
    points

  -> riemann_roch_space(bound)
    CAbRiemannRochSpace.new(self, bound)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    ("C_" + @x_pole_order.to_s + "," +
     @y_pole_order.to_s + "(" + @curve.to_s + ")")

  -> inspect
    to_s


+ Curve
  -> c_ab_model(
       x_index, y_index, infinity_index,
       x_pole_order, y_pole_order)
    CAbCurveModel.new(
      self, x_index, y_index, infinity_index,
      x_pole_order, y_pole_order)
