# Certified archimedean places of number fields.
#
# Real places carry an exact Sturm-isolated embedding and therefore compute
# signs without floating point.  Complex places occur in conjugate pairs; for
# 2-descent their local square-class quotient is trivial, so no arbitrary
# numerical choice of one embedding from a pair is needed.

+ Polynomial
  # Isolate every root of an already squarefree rational polynomial directly,
  # without first factoring it over Q.  This is the natural path for finite
  # etale quotient presentations: squarefreeness is already certified, while
  # a complete irreducible factorization is unrelated and can be much more
  # expensive than Sturm isolation.
  -> squarefree_real_root_isolation(split_limit = 250_000)
    validate_sturm_domain
    if !squarefree?
      raise "direct real-root isolation needs a squarefree polynomial"
    total = real_root_count
    return RealRootIsolation.new(self, []) if total == 0
    sequence = sturm_sequence
    bound = cauchy_root_bound
    stack = [[0 - bound, bound, total]]
    roots = []
    splits = 0
    while stack.size > 0
      entry = stack.pop
      left = entry[0]
      right = entry[1]
      count = entry[2]
      if count == 1
        root_index = sturm_root_index_before_with_sequence(
          sequence, left)
        roots.push(AlgebraicRealRoot.new(
          self.monic, left, right, root_index))
      else
        splits += 1
        if splits > split_limit
          raise "direct real-root isolation split limit exceeded"
        middle = (left + right) / Rational.new(2)
        if at(middle).zero?
          roots.push(middle)
          left_count = sturm_root_count_with_sequence(
            sequence, left, middle)
          right_count = sturm_root_count_with_sequence(
            sequence, middle, right)
        else
          left_count = sturm_root_count_with_sequence(
            sequence, left, middle)
          right_count = count - left_count
        stack.push([middle, right, right_count]) if right_count > 0
        stack.push([left, middle, left_count]) if left_count > 0
    sorted = Polynomial.sort_real_root_values(roots)
    result = RealRootIsolation.new(self, sorted)
    if !result.certified?
      raise "direct real-root isolation completeness certificate failed"
    result

  -> squarefree_real_roots(split_limit = 250_000)
    squarefree_real_root_isolation(split_limit).roots


+ NumberFieldArchimedeanPlace
  -> new(@field, @kind, @index, embedding = nil)
    @embedding = embedding
    if !verified?
      raise "invalid archimedean place"

  -> field
    @field

  -> kind
    @kind

  -> index
    @index

  -> embedding
    if !real?
      raise "a complex conjugate place has no selected real embedding"
    @embedding

  -> real?
    @kind == :real

  -> complex?
    @kind == :complex_pair

  -> verified?
    return false if @field.class_name != "NumberField"
    integer_index = @index.class_name == "Integer"
    integer_index = true if @index.class_name == "Int"
    integer_index = true if @index.class_name == "BigInt"
    return false if !integer_index
    return false if @index < 0
    if real?
      return false if @embedding == nil
      return false if @embedding.class_name != "NumberFieldRealEmbedding"
      return false if @embedding.field != @field
      return @embedding.certificate.verified? if @embedding.respond_to?(
        "certificate")
      return @embedding.verified?
    @kind == :complex_pair && @embedding == nil

  -> certified?
    verified?

  -> image(value)
    if !real?
      raise "exact images are exposed only at real archimedean places"
    @embedding.image(value)

  -> sign(value)
    @embedding.sign(value)

  # The R^*/R^{*2} coordinate: negative is 1 and positive is 0.
  # C^*/C^{*2} is trivial, so a complex pair always contributes zero.
  -> square_class_bit(value)
    return 0 if complex?
    value_sign = sign(value)
    raise "zero has no archimedean square class" if value_sign == 0
    value_sign < 0 ? 1 : 0

  -> to_s
    if real?
      return "RealPlace(" + @field.to_s + ", " + @index.to_s + ")"
    "ComplexPlacePair(" + @field.to_s + ", " + @index.to_s + ")"

  -> inspect
    to_s


+ NumberFieldArchimedeanDataCertificate
  -> new(@data)

  -> data
    @data

  -> proof_kind
    :exact_sturm_replay

  -> kernel_checked?
    true

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return false if @data.class_name != "NumberFieldArchimedeanData"
    field = @data.field
    return false if field.class_name != "NumberField"
    return false if !field.signature_certified?
    signature = field.signature
    real_places = @data.real_places
    complex_places = @data.complex_places
    return false if real_places.size != signature[0]
    return false if complex_places.size != signature[1]
    return false if real_places.size + 2 * complex_places.size != field.degree

    seen_roots = []
    i = 0
    while i < real_places.size
      place = real_places[i]
      return false if !place.verified?
      return false if !place.real? || place.index != i
      root = place.embedding.root
      seen_roots.each -> (other)
        return false if root == other
      seen_roots.push(root)
      i += 1

    i = 0
    while i < complex_places.size
      place = complex_places[i]
      return false if !place.verified?
      return false if !place.complex? || place.index != i
      i += 1
    true

  -> certified?
    verified?

  -> to_s
    text = "NumberFieldArchimedeanDataCertificate("
    text + @data.signature.to_s + ")"

  -> inspect
    to_s


+ NumberFieldArchimedeanData
  -> new(@field, search_limit = 250_000)
    if @field.class_name != "NumberField"
      raise "archimedean data needs a NumberField"
    @real_places = []
    embeddings = @field.real_embeddings(search_limit)
    i = 0
    while i < embeddings.size
      @real_places.push(NumberFieldArchimedeanPlace.new(
        @field, :real, i, embeddings[i]))
      i += 1
    @complex_places = []
    i = 0
    while i < @field.complex_embedding_pair_count
      @complex_places.push(NumberFieldArchimedeanPlace.new(
        @field, :complex_pair, i))
      i += 1
    @certificate_cache = NumberFieldArchimedeanDataCertificate.new(self)
    if !@certificate_cache.verified?
      raise "archimedean place data failed certification"

  -> field
    @field

  -> signature
    [@real_places.size, @complex_places.size]

  -> real_places
    out = []
    @real_places.each -> (place)
      out.push(place)
    out

  -> complex_places
    out = []
    @complex_places.each -> (place)
      out.push(place)
    out

  -> places
    real_places + complex_places

  -> real_signs(value)
    out = []
    @real_places.each -> (place)
      out.push(place.sign(value))
    out

  -> square_class_signature(value)
    out = []
    @real_places.each -> (place)
      out.push(place.square_class_bit(value))
    out

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    text = "ArchimedeanPlaces(" + @field.to_s + ", "
    text + signature.to_s + ")"

  -> inspect
    to_s


+ NumberField
  -> archimedean_data(search_limit = 250_000)
    NumberFieldArchimedeanData.new(self, search_limit)

  -> archimedean_places(search_limit = 250_000)
    archimedean_data(search_limit).places


# Archimedean places of a finite etale Q-algebra presented as a product of
# squarefree monogenic quotients.  A component may itself be reducible: its
# exact real roots are the real algebra maps to R, so no unjustified
# irreducibility or number-field coercion is introduced.
+ EtaleProductArchimedeanPlace
  -> new(@order, @component_index, @kind,
         @index, root = nil)
    @root = root
    if !verified?
      raise "invalid etale-product archimedean place"

  -> order
    @order

  -> component_index
    @component_index

  -> index
    @index

  -> kind
    @kind

  -> real?
    @kind == :real

  -> complex?
    @kind == :complex_pair

  -> root
    raise "a complex place pair has no selected real root" if !real?
    if @root.class_name == "AlgebraicRealRoot"
      return @root.refined(0)
    @root

  -> component_polynomial
    @order.component_algebra_orders[
      @component_index].algebra.defining_polynomial

  -> verified?
    return false if @order.class_name != "EtaleProductOrder"
    component_class = @component_index.class_name
    integer_component = component_class == "Integer"
    integer_component = true if component_class == "Int"
    integer_component = true if component_class == "BigInt"
    index_class = @index.class_name
    integer_index = index_class == "Integer"
    integer_index = true if index_class == "Int"
    integer_index = true if index_class == "BigInt"
    return false if !integer_component || !integer_index
    return false if @component_index < 0
    return false if @component_index >= @order.component_count
    return false if @index < 0
    if complex?
      return @root == nil
    return false if !real?
    root_class = @root.class_name
    rational_root = root_class == "Rational"
    rational_root = true if root_class == "Integer"
    rational_root = true if root_class == "Int"
    rational_root = true if root_class == "BigInt"
    if rational_root
      return component_polynomial.at(@root).zero?
    return false if root_class != "AlgebraicRealRoot"
    return false if !@root.certificate.verified?
    component_polynomial.rem(
      @root.defining_polynomial).zero?

  -> certified?
    verified?

  -> component_value(value)
    @order.coerce(value).components[@component_index]

  -> image(value)
    if !real?
      raise "exact images are exposed only at real archimedean places"
    coefficients = component_value(value).coefficients
    selected_root = root
    result = coefficients[coefficients.size - 1]
    i = coefficients.size - 2
    while i >= 0
      if selected_root.class_name == "AlgebraicRealRoot"
        result = AlgebraicRealArithmetic.compute(
          result, selected_root, "*").value
        result = AlgebraicRealArithmetic.compute(
          result, coefficients[i], "+").value
      else
        result = result * Rational.coerce(selected_root)
        result += coefficients[i]
      i -= 1
    result

  -> sign(value)
    polynomial = component_value(value).polynomial
    selected_root = root
    if selected_root.class_name != "AlgebraicRealRoot"
      result = polynomial.at(selected_root)
      return 0 if result.zero?
      return result.negative? ? -1 : 1

    defining = selected_root.defining_polynomial
    common = defining.gcd(polynomial)
    if common.degree > 0
      count = common.sturm_root_count(
        selected_root.lower_bound,
        selected_root.upper_bound)
      return 0 if count == 1

    sequence = defining.sturm_sequence
    lower = selected_root.lower_bound
    upper = selected_root.upper_bound
    refinements = 0
    while refinements < 10_000
      interval = polynomial_interval(
        polynomial, lower, upper)
      return -1 if interval[1] < 0
      return 1 if interval[0] > 0
      middle = (lower + upper) / Rational.new(2)
      if defining.at(middle).zero?
        exact = polynomial.at(middle)
        return 0 if exact.zero?
        return exact.negative? ? -1 : 1
      left_count = defining.sturm_root_count_with_sequence(
        sequence, lower, middle)
      if left_count == 1
        upper = middle
      else
        lower = middle
      refinements += 1
    raise "could not determine exact sign at etale real place"

  -> polynomial_interval(polynomial, lower, upper)
    result_lower = Rational.new(0)
    result_upper = Rational.new(0)
    i = polynomial.degree
    while i >= 0
      products = [
        result_lower * lower,
        result_lower * upper,
        result_upper * lower,
        result_upper * upper
      ]
      product_lower = products[0]
      product_upper = products[0]
      products.each -> (product)
        product_lower = product if product < product_lower
        product_upper = product if product > product_upper
      coefficient = polynomial.coeff(i)
      result_lower = product_lower + coefficient
      result_upper = product_upper + coefficient
      i -= 1
    [result_lower, result_upper]

  -> square_class_bit(value)
    return 0 if complex?
    value_sign = sign(value)
    raise "zero has no archimedean square class" if value_sign == 0
    value_sign < 0 ? 1 : 0

  -> to_s
    text = real? ? "EtaleRealPlace(" : "EtaleComplexPlacePair("
    text + @component_index.to_s + ", " + @index.to_s + ")"

  -> inspect
    to_s


+ EtaleProductArchimedeanDataCertificate
  -> new(@data)

  -> proof_kind
    :exact_sturm_replay

  -> kernel_checked?
    true

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return false if @data.class_name != "EtaleProductArchimedeanData"
    order = @data.order
    return false if order.class_name != "EtaleProductOrder"
    return false if !order.certificate.verified?
    component_signatures = @data.component_signatures
    return false if component_signatures.size != order.component_count
    components = order.component_algebra_orders
    real_counts = []
    complex_counts = []
    total = 0
    i = 0
    while i < component_signatures.size
      polynomial = components[i].algebra.defining_polynomial
      expected_real = polynomial.real_root_count
      expected_complex = (polynomial.degree - expected_real) / 2
      return false if component_signatures[i][0] != expected_real
      return false if component_signatures[i][1] != expected_complex
      total += expected_real + 2 * expected_complex
      real_counts.push(0)
      complex_counts.push(0)
      i += 1
    return false if total != order.rank

    real_places = @data.real_places
    i = 0
    while i < real_places.size
      place = real_places[i]
      return false if !place.verified? || !place.real?
      return false if place.order != order
      component = place.component_index
      return false if place.index != real_counts[component]
      j = 0
      while j < i
        earlier = real_places[j]
        if earlier.component_index == component
          return false if earlier.root == place.root
        j += 1
      real_counts[component] += 1
      i += 1

    complex_places = @data.complex_places
    i = 0
    while i < complex_places.size
      place = complex_places[i]
      return false if !place.verified? || !place.complex?
      return false if place.order != order
      component = place.component_index
      return false if place.index != complex_counts[component]
      complex_counts[component] += 1
      i += 1

    i = 0
    while i < component_signatures.size
      return false if real_counts[i] != component_signatures[i][0]
      return false if complex_counts[i] != component_signatures[i][1]
      i += 1
    return false if real_places.size != @data.signature[0]
    return false if complex_places.size != @data.signature[1]
    true

  -> certified?
    verified?

  -> to_s
    text = "EtaleProductArchimedeanDataCertificate("
    text + @data.signature.to_s + ")"

  -> inspect
    to_s


+ EtaleProductArchimedeanData
  -> new(@order, search_limit = 250_000)
    if @order.class_name != "EtaleProductOrder"
      raise "etale archimedean data needs an EtaleProductOrder"
    @real_places = []
    @complex_places = []
    @component_signatures = []
    components = @order.component_algebra_orders
    component_index = 0
    while component_index < components.size
      polynomial = components[
        component_index].algebra.defining_polynomial
      roots = polynomial.squarefree_real_roots(search_limit)
      real_count = roots.size
      complex_count = (polynomial.degree - real_count) / 2
      @component_signatures.push([real_count, complex_count])
      i = 0
      while i < roots.size
        @real_places.push(EtaleProductArchimedeanPlace.new(
          @order, component_index, :real, i, roots[i]))
        i += 1
      i = 0
      while i < complex_count
        @complex_places.push(EtaleProductArchimedeanPlace.new(
          @order, component_index, :complex_pair, i))
        i += 1
      component_index += 1
    @certificate_cache = EtaleProductArchimedeanDataCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "etale-product archimedean data failed certification"

  -> order
    @order

  -> component_signatures
    out = []
    @component_signatures.each -> (component_signature)
      out.push([component_signature[0], component_signature[1]])
    out

  -> signature
    real_count = 0
    complex_count = 0
    @component_signatures.each -> (component_signature)
      real_count += component_signature[0]
      complex_count += component_signature[1]
    [real_count, complex_count]

  -> real_places
    out = []
    @real_places.each -> (place)
      out.push(place)
    out

  -> complex_places
    out = []
    @complex_places.each -> (place)
      out.push(place)
    out

  -> places
    real_places + complex_places

  -> real_signs(value)
    out = []
    @real_places.each -> (place)
      out.push(place.sign(value))
    out

  -> square_class_signature(value)
    out = []
    @real_places.each -> (place)
      out.push(place.square_class_bit(value))
    out

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    text = "EtaleProductArchimedeanPlaces("
    text + signature.to_s + ")"

  -> inspect
    to_s


+ EtaleProductOrder
  -> archimedean_data(search_limit = 250_000)
    EtaleProductArchimedeanData.new(self, search_limit)

  -> archimedean_places(search_limit = 250_000)
    archimedean_data(search_limit).places
