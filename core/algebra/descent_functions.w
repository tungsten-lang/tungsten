# Exact divisor and function families for plane-quartic two-descent.
#
# If l is a bitangent, then l.C = 2 beta_l.  A rational distinguished
# bitangent l0 turns the 28-member fake BPS setup into the 27-member true
# setup
#
#   beta'_l = beta_l - beta_l0,
#   f_l     = l / l0,
#   div(f_l) = 2 beta'_l.
#
# The bitangent chart supplies each line over a finite etale component.  This
# file reconstructs a normalized contact quadratic q and verifies the exact
# binary-quartic identity l.C = a q^2 in that component.  Point evaluation
# then returns an executable element of the degree-27 etale algebra.


+ EtaleAlgebra
  # Evaluate a polynomial over the base field at elements of this quotient
  # algebra.  Polynomial#evaluate_raw intentionally stays inside its
  # coefficient Field, whereas descent needs values in a finite etale
  # algebra, which can have zero divisors.
  -> evaluate_base_polynomial(polynomial, values)
    if polynomial.class_name != "Polynomial"
      raise "etale polynomial evaluation needs a Polynomial"
    if polynomial.ring.field != @base_field
      raise "etale polynomial evaluation changes the base field"
    wrong_arity = values.class_name != "Array"
    if !wrong_arity
      wrong_arity = true if values.size != polynomial.ring.arity
    if wrong_arity
      raise "wrong etale polynomial evaluation arity"
    normalized = []
    values.each -> (value)
      normalized.push(normalize_element(value))
    result = zero
    polynomial.each_term -> (coefficient, exponents)
      term = coerce(coefficient)
      i = 0
      while i < exponents.size
        if exponents[i] > 0
          term = term * power(
            normalized[i], exponents[i])
        i += 1
      result = result + term
    result


+ PlaneQuarticBitangentContactComponentCertificate
  -> new(@contact)
    @verified_cache = nil

  -> contact
    @contact

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return true if @verified_cache == true
    if @contact.class_name != "PlaneQuarticBitangentContactComponent"
      raise "bitangent-contact certificate has the wrong subject"
    source = @contact.source_component
    chart = @contact.chart
    algebra = @contact.algebra
    if !source.verified? || source.chart != chart
      raise "bitangent contact has an invalid projection component"
    if !algebra.certificate.verified?
      raise "bitangent contact has an uncertified etale algebra"
    expected_modulus = source.factor.monic
    if !algebra.defining_polynomial.eql?(expected_modulus)
      raise "bitangent contact uses the wrong etale component"

    u = algebra.from_polynomial(source.u_image)
    v = algebra.generator
    restrictions = []
    chart.line_binary_coefficients.each -> (polynomial)
      restrictions.push(
        algebra.evaluate_base_polynomial(
          polynomial, [u, v]))
    if !same_elements?(
         restrictions,
         @contact.restriction_coefficients)
      raise "bitangent contact restriction does not replay"

    expected_line = []
    3.times -> expected_line.push(algebra.zero)
    free = chart.free_indices
    expected_line[chart.pivot] = algebra.one
    expected_line[free[0]] = u.negate
    expected_line[free[1]] = v.negate
    if !same_elements?(
         expected_line, @contact.line_coefficients)
      raise "bitangent contact line does not match its chart"

    q = @contact.contact_quadratic
    if q.size != 3
      raise "bitangent contact quadratic has the wrong degree"
    scale = @contact.scale
    if !algebra.unit?(scale)
      raise "bitangent contact scale is not a unit"
    two = algebra.coerce(2)
    square = [
      q[0] * q[0],
      q[0] * q[1] * two,
      q[1] * q[1] + q[0] * q[2] * two,
      q[1] * q[2] * two,
      q[2] * q[2]
    ]
    i = 0
    while i < square.size
      square[i] = square[i] * scale
      i += 1
    if !same_elements?(square, restrictions)
      raise "bitangent contact is not an exact doubled divisor"
    @verified_cache = true
    true

  -> same_elements?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if !left[i].eql?(right[i])
      i += 1
    true

  -> certified?
    verified?

  -> to_s
    text = "PlaneQuarticBitangentContactComponentCertificate("
    text + @contact.degree.to_s + ")"

  -> inspect
    to_s


# One squarefree etale component of the remaining bitangent family.
#
# In the chart X_p = u X_i + v X_j, write the line restriction as
#
#   a U^4 + b U^3 V + c U^2 V^2 + d U V^3 + e V^4.
#
# Since a is a unit for the focused shell-width chart, its normalized contact
# quadratic is
#
#   q = U^2 + b/(2a) UV + (4ac-b^2)/(8a^2) V^2.
#
# The certificate checks all five coefficients of restriction = a q^2.
+ PlaneQuarticBitangentContactComponent
  -> new(@chart, @source_component, @algebra)
    if @chart.class_name != "PlaneQuarticBitangentChart"
      raise "bitangent contact needs a bitangent chart"
    expected_source = "BitangentEtaleComponentCertificate"
    if @source_component.class_name != expected_source
      raise "bitangent contact needs a projection component"
    if !@source_component.verified?
      raise "bitangent contact projection component is unverified"
    if @source_component.chart != @chart
      raise "bitangent contact component changes its chart"
    if @algebra.class_name != "EtaleAlgebra"
      raise "bitangent contact needs an etale component algebra"
    expected_modulus = @source_component.factor.monic
    if !@algebra.defining_polynomial.eql?(expected_modulus)
      raise "bitangent contact has the wrong quotient algebra"

    @u = @algebra.from_polynomial(
      @source_component.u_image)
    @v = @algebra.generator
    @line_coefficients = []
    3.times -> @line_coefficients.push(@algebra.zero)
    free = @chart.free_indices
    @line_coefficients[@chart.pivot] = @algebra.one
    @line_coefficients[free[0]] = @u.negate
    @line_coefficients[free[1]] = @v.negate

    @restriction_coefficients = []
    @chart.line_binary_coefficients.each -> (polynomial)
      @restriction_coefficients.push(
        @algebra.evaluate_base_polynomial(
          polynomial, [@u, @v]))
    a = @restriction_coefficients[0]
    b = @restriction_coefficients[1]
    c = @restriction_coefficients[2]
    if !@algebra.unit?(a)
      raise "focused bitangent contact chart has nonunit leading coefficient"
    two_a = a * @algebra.coerce(2)
    q1 = b / two_a
    numerator = a * c * @algebra.coerce(4) - b * b
    denominator = a * a * @algebra.coerce(8)
    q2 = numerator / denominator
    @contact_quadratic = [
      @algebra.one, q1, q2
    ]
    @scale = a
    @certificate_cache = PlaneQuarticBitangentContactComponentCertificate.new(self)
    if !@certificate_cache.verified?
      raise "bitangent contact component failed certification"

  -> chart
    @chart

  -> curve
    @chart.curve

  -> source_component
    @source_component

  -> algebra
    @algebra

  -> degree
    @algebra.dimension

  -> parameters
    [@u, @v]

  -> line_coefficients
    out = []
    @line_coefficients.each -> out.push(item)
    out

  -> restriction_coefficients
    out = []
    @restriction_coefficients.each -> out.push(item)
    out

  -> contact_quadratic
    out = []
    @contact_quadratic.each -> out.push(item)
    out

  -> scale
    @scale

  -> relative_degree
    2

  -> doubled?
    certificate.verified?

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    text = "BitangentContactComponent(degree "
    text + degree.to_s + ")"

  -> inspect
    to_s


+ PlaneQuarticBPSTrueDivisorComponentCertificate
  -> new(@divisor)

  -> divisor
    @divisor

  -> verified?
    expected_class = "PlaneQuarticBPSTrueDivisorComponent"
    return false if @divisor.class_name != expected_class
    contact = @divisor.contact
    hyperflex = @divisor.distinguished_certificate
    return false if !contact.certificate.verified?
    return false if !hyperflex.verified?
    return false if contact.curve != hyperflex.curve
    return false if contact.relative_degree != 2
    return false if hyperflex.half_intersection.degree != 2
    @divisor.relative_degree == 0

  -> certified?
    verified?

  -> to_s
    "PlaneQuarticBPSTrueDivisorComponentCertificate"

  -> inspect
    to_s


# One component of beta' = beta_l - beta_l0.  The positive contact divisor is
# represented over its etale component by the certified quadratic q; the
# negative divisor is the rational half-intersection of the distinguished
# hyperflex.  Both have degree two, so beta' has relative degree zero.
+ PlaneQuarticBPSTrueDivisorComponent
  -> new(@contact, @distinguished_certificate)
    expected_contact = "PlaneQuarticBitangentContactComponent"
    if @contact.class_name != expected_contact
      raise "BPS true divisor needs a bitangent contact component"
    expected_hyperflex = "RationalHyperflexCertificate"
    if @distinguished_certificate.class_name != expected_hyperflex
      raise "BPS true divisor needs a rational distinguished bitangent"
    @certificate_cache = PlaneQuarticBPSTrueDivisorComponentCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "BPS true divisor component failed certification"

  -> contact
    @contact

  -> positive_contact
    @contact

  -> distinguished_certificate
    @distinguished_certificate

  -> negative_contact
    @distinguished_certificate.half_intersection

  -> algebra
    @contact.algebra

  -> relative_degree
    @contact.relative_degree - negative_contact.degree

  -> multiplier
    2

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    text = "BPSTrueDivisor(beta_l-beta_l0, degree "
    text + relative_degree.to_s + ")"

  -> inspect
    to_s


+ PlaneQuarticBPSFunctionComponentCertificate
  -> new(@function)

  -> function
    @function

  -> theorem
    "divisor of a ratio of nonzero sections of the same line bundle"

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

  -> verified?
    expected_class = "PlaneQuarticBPSFunctionComponent"
    return false if @function.class_name != expected_class
    beta_prime = @function.beta_prime
    return false if !beta_prime.certificate.verified?
    contact = beta_prime.contact
    hyperflex = beta_prime.distinguished_certificate
    algebra = contact.algebra
    expected_denominator = []
    hyperflex.line.coefficients.each -> (coefficient)
      expected_denominator.push(
        algebra.coerce(coefficient))
    return false if !same_elements?(
      expected_denominator,
      @function.denominator_coefficients)
    numerator = @function.numerator_coefficients
    return false if numerator.size != 3
    return false if same_elements?(
      numerator, expected_denominator)
    @function.divisor_multiplier == 2

  -> same_elements?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if !left[i].eql?(right[i])
      i += 1
    true

  -> certified?
    verified?

  -> to_s
    "PlaneQuarticBPSFunctionComponentCertificate"

  -> inspect
    to_s


# The component function l/l0.  Its numerator contact certificate proves
# l.C = 2 beta_l; the rational hyperflex certificate proves
# l0.C = 2 beta_l0.  The standard divisor identity for a ratio of sections
# therefore gives div(l/l0) = 2(beta_l-beta_l0).
+ PlaneQuarticBPSFunctionComponent
  -> new(@beta_prime)
    expected_divisor = "PlaneQuarticBPSTrueDivisorComponent"
    if @beta_prime.class_name != expected_divisor
      raise "BPS function needs a true divisor component"
    if !@beta_prime.certificate.verified?
      raise "BPS function true divisor is unverified"
    @contact = @beta_prime.contact
    @distinguished_certificate = @beta_prime.distinguished_certificate
    @numerator_coefficients = @contact.line_coefficients
    @denominator_coefficients = []
    @distinguished_certificate.line.coefficients.each -> (coefficient)
      @denominator_coefficients.push(
        algebra.coerce(coefficient))
    @certificate_cache = PlaneQuarticBPSFunctionComponentCertificate.new(self)
    if !@certificate_cache.verified?
      raise "BPS line-ratio function failed certification"

  -> contact
    @contact

  -> beta_prime
    @beta_prime

  -> algebra
    @contact.algebra

  -> distinguished_certificate
    @distinguished_certificate

  -> numerator_coefficients
    out = []
    @numerator_coefficients.each -> out.push(item)
    out

  -> denominator_coefficients
    out = []
    @denominator_coefficients.each -> out.push(item)
    out

  -> divisor_multiplier
    2

  -> relative_divisor_degree
    0

  -> linear_value(coefficients, coordinates)
    wrong_coordinates = coordinates.class_name != "Array"
    if !wrong_coordinates
      wrong_coordinates = true if coordinates.size != coefficients.size
    if wrong_coordinates
      raise "line-ratio evaluation has the wrong coordinate count"
    value = algebra.zero
    i = 0
    while i < coefficients.size
      coordinate = algebra.coerce(coordinates[i])
      value = value + coefficients[i] * coordinate
      i += 1
    value

  -> evaluate_coordinates(coordinates)
    numerator = linear_value(
      @numerator_coefficients, coordinates)
    denominator = linear_value(
      @denominator_coefficients, coordinates)
    if !algebra.unit?(denominator)
      raise "BPS function has a pole at these coordinates"
    if !algebra.unit?(numerator)
      raise "BPS function vanishes on a bitangent component"
    numerator / denominator

  -> call(coordinates)
    evaluate_coordinates(coordinates)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    prefix = "BPSFunctionComponent(l/l0, degree "
    prefix + algebra.dimension.to_s + ")"

  -> inspect
    to_s


+ PlaneQuarticBPSFunctionDataCertificate
  -> new(@data)
    @verified_cache = nil

  -> data
    @data

  -> theorem
    "BPS section 6.5: a rational member converts the bitangent fake setup to a true setup"

  -> reference
    "Bruin-Poonen-Stoll, Generalized explicit descent, section 6.5"

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return true if @verified_cache == true
    if @data.class_name != "PlaneQuarticBPSFunctionData"
      raise "BPS function-data certificate has the wrong subject"
    setup = @data.setup
    scheme = setup.bitangent_scheme_certificate
    if scheme == nil || !scheme.verified?
      raise "BPS function data needs the certified bitangent scheme"
    hyperflex = setup.distinguished_certificate
    if !hyperflex.verified?
      raise "BPS function data needs a certified rational bitangent"
    wrong_degree = scheme.geometric_degree != 28
    wrong_degree = true if scheme.etale_degree != 27
    if wrong_degree
      raise "BPS true setup has the wrong bitangent degrees"
    algebra = @data.etale_algebra
    wrong_algebra = !algebra.certificate.verified?
    wrong_algebra = true if algebra.dimension != 27
    if wrong_algebra
      raise "BPS function data has the wrong etale algebra"
    contacts = @data.contact_components
    beta_primes = @data.beta_components
    functions = @data.function_components
    source = scheme.primary_certificate.components
    components = algebra.component_algebras
    wrong_count = contacts.size != source.size
    wrong_count = true if beta_primes.size != source.size
    wrong_count = true if functions.size != source.size
    wrong_count = true if components.size != source.size
    if wrong_count
      raise "BPS function data lost an etale component"
    total = 0
    i = 0
    while i < contacts.size
      contact = contacts[i]
      beta_prime = beta_primes[i]
      function = functions[i]
      if !contact.certificate.verified?
        raise "BPS function data has an invalid contact component"
      if !function.certificate.verified?
        raise "BPS function data has an invalid line-ratio component"
      if !beta_prime.certificate.verified?
        raise "BPS function data has an invalid true divisor component"
      if contact.source_component != source[i]
        raise "BPS contact component changes its projection factor"
      if contact.algebra != components[i]
        raise "BPS contact component changes its etale algebra"
      if beta_prime.contact != contact
        raise "BPS true divisor changes its contact component"
      if function.beta_prime != beta_prime
        raise "BPS function changes its true divisor component"
      if function.contact != contact
        raise "BPS function component changes its contact divisor"
      total += contact.degree
      i += 1
    if total != 27
      raise "BPS function components do not cover Delta prime"
    @verified_cache = true
    true

  -> certified?
    verified?

  -> to_s
    "PlaneQuarticBPSFunctionDataCertificate(degree 27)"

  -> inspect
    to_s


# Certified degree-27 true-descent divisor and function data.  This object
# does not claim that the global S-unit, Galois-module, or local-image stages
# have been computed.
+ PlaneQuarticBPSFunctionData
  -> new(@setup)
    if @setup.class_name != "PlaneQuarticTwoDescentSetup"
      raise "BPS function data needs a plane-quartic descent setup"
    scheme = @setup.bitangent_scheme_certificate
    if scheme == nil || !scheme.verified?
      raise "certify the bitangent scheme before its BPS functions"
    @etale_algebra = scheme.etale_algebra
    source_components = scheme.primary_certificate.components
    component_algebras = @etale_algebra.component_algebras
    @contact_components = []
    @beta_components = []
    @function_components = []
    i = 0
    while i < source_components.size
      contact = PlaneQuarticBitangentContactComponent.new(
        scheme.primary_chart,
        source_components[i],
        component_algebras[i])
      @contact_components.push(contact)
      beta_prime = PlaneQuarticBPSTrueDivisorComponent.new(
        contact, @setup.distinguished_certificate)
      @beta_components.push(beta_prime)
      @function_components.push(
        PlaneQuarticBPSFunctionComponent.new(
          beta_prime))
      i += 1
    @certificate_cache = PlaneQuarticBPSFunctionDataCertificate.new(self)
    if !@certificate_cache.verified?
      raise "BPS divisor and function data failed certification"

  -> setup
    @setup

  -> curve
    @setup.curve

  -> exponent
    2

  -> etale_algebra
    @etale_algebra

  -> etale_degree
    @etale_algebra.dimension

  -> contact_components
    out = []
    @contact_components.each -> out.push(item)
    out

  -> beta_family
    beta_components

  -> beta_components
    out = []
    @beta_components.each -> out.push(item)
    out

  -> function_components
    out = []
    @function_components.each -> out.push(item)
    out

  -> function_family
    function_components

  -> component_degrees
    out = []
    @contact_components.each -> out.push(item.degree)
    out

  -> distinguished_half_intersection
    @setup.distinguished_certificate.half_intersection

  -> point_coordinates(value)
    if value.class_name == "ProjectivePoint"
      if value.space != curve.space
        raise "BPS evaluation point belongs to a different space"
      if !curve.contains?(value)
        raise "BPS evaluation point is not on the curve"
      return value.coordinates
    if value.class_name != "Array"
      raise "BPS function evaluation needs a point or coordinate array"
    point = curve.space.point(value)
    if !curve.contains?(point)
      raise "BPS evaluation coordinates are not on the curve"
    point.coordinates

  -> evaluate_components(value)
    coordinates = point_coordinates(value)
    out = []
    @function_components.each -> (function)
      out.push(function.evaluate_coordinates(
        coordinates))
    out

  -> evaluate(value)
    @etale_algebra.from_components(
      evaluate_components(value))

  -> descent_value(value)
    evaluate(value)

  -> call(value)
    evaluate(value)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    "PlaneQuarticBPSFunctionData(degree 27)"

  -> inspect
    to_s


+ PlaneQuarticTwoDescentSetup
  -> certify_divisor_function_data
    if @bitangent_scheme_certificate == nil
      certify_bitangent_scheme
    @bps_function_data = PlaneQuarticBPSFunctionData.new(
      self)
    @bps_function_data

  -> certify_bps_function_data
    certify_divisor_function_data

  -> divisor_function_data
    @bps_function_data

  -> bps_function_data
    @bps_function_data

  -> true_setup?
    return false if @bps_function_data == nil
    @bps_function_data.certificate.verified?

  -> certified?
    true_setup?
