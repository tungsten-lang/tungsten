# Exact finite binary and constant-norm code audits.

+ Krawtchouk
  -> .binary(degree, distance, length)
    Combinatorics.require_nonnegative_integer(degree, "degree")
    Combinatorics.require_nonnegative_integer(distance, "distance")
    Combinatorics.require_nonnegative_integer(length, "length")
    if degree > length || distance > length
      raise "binary Krawtchouk indices exceed the block length"
    value = 0
    j = 0
    while j <= degree
      term = (Combinatorics.binomial(distance, j) *
              Combinatorics.binomial(length - distance, degree - j))
      term = 0 - term if j % 2 == 1
      value += term
      j += 1
    value


+ BinaryBlockCode
  -> new(words)
    if words.class_name != "Array" || words.size == 0
      raise "binary block code needs at least one word"
    @length = words[0].size
    raise "binary block code words must be nonempty" if @length == 0
    @words = []
    words.each -> (source)
      if source.class_name != "Array" || source.size != @length
        raise "binary block code words have inconsistent lengths"
      word = []
      source.each -> (bit)
        if !Combinatorics.integer?(bit) || (bit != 0 && bit != 1)
          raise "binary block code entries must be zero or one"
        word.push(bit)
      @words.push(word)
    left = 0
    while left < @words.size
      right = left + 1
      while right < @words.size
        if @words[left].to_s == @words[right].to_s
          raise "binary block code words must be distinct"
        right += 1
      left += 1

  -> length
    @length

  -> size
    @words.size

  -> words
    Combinatorics.copy_matrix(@words)

  -> distance(left_index, right_index)
    Combinatorics.hamming_distance(
      @words[left_index], @words[right_index])

  -> minimum_distance
    return 0 if size < 2
    best = @length + 1
    left = 0
    while left < size
      right = left + 1
      while right < size
        value = distance(left, right)
        best = value if value < best
        right += 1
      left += 1
    best

  # A_i = |C|^-1 * |{(x,y) in C^2 : d(x,y)=i}|.
  -> distance_distribution
    counts = []
    (@length + 1).times -> counts.push(0)
    left = 0
    while left < size
      right = 0
      while right < size
        counts[distance(left, right)] += 1
        right += 1
      left += 1
    out = []
    counts.each -> (count)
      out.push(Rational.new(count, size))
    out

  -> delsarte_transform(degree)
    Combinatorics.require_nonnegative_integer(degree, "degree")
    raise "Delsarte degree exceeds the block length" if degree > @length
    distribution = distance_distribution
    value = Rational.new(0)
    distance = 0
    while distance <= @length
      term = (distribution[distance] *
              Krawtchouk.binary(degree, distance, @length))
      value += term
      distance += 1
    value

  -> delsarte_feasible?
    degree = 0
    while degree <= @length
      return false if delsarte_transform(degree) < Rational.new(0)
      degree += 1
    true

  -> hamming_ball_volume(radius)
    Combinatorics.require_nonnegative_integer(radius, "radius")
    raise "Hamming radius exceeds the block length" if radius > @length
    volume = 0
    weight = 0
    while weight <= radius
      volume += Combinatorics.binomial(@length, weight)
      weight += 1
    volume

  -> hamming_bound_holds?
    distance = minimum_distance
    radius = distance < 1 ? 0 : (distance - 1) / 2
    size * hamming_ball_volume(radius) <= 2 ** @length

  -> minimum_distance_certificate
    BinaryCodeDistanceCertificate.new(self, minimum_distance)

  -> proof_kind
    :exact_finite_binary_block_code


+ BinaryCodeDistanceCertificate
  -> new(@code, @claimed_minimum_distance)

  -> code
    @code

  -> claimed_minimum_distance
    @claimed_minimum_distance

  -> proof_kind
    :exact_pairwise_hamming_replay

  -> verified?
    (Combinatorics.integer?(@claimed_minimum_distance) &&
     @claimed_minimum_distance == @code.minimum_distance)


+ ConstantNormCode
  -> new(vectors)
    if vectors.class_name != "Array" || vectors.size < 2
      raise "constant-norm code needs at least two vectors"
    @dimension = vectors[0].size
    raise "constant-norm vectors must be nonempty" if @dimension == 0
    @vectors = []
    vectors.each -> (source)
      if source.class_name != "Array" || source.size != @dimension
        raise "constant-norm vectors have inconsistent dimensions"
      vector = []
      source.each -> (coordinate)
        if !Combinatorics.integer?(coordinate)
          raise "constant-norm code currently needs integer coordinates"
        vector.push(coordinate)
      @vectors.push(vector)
    left = 0
    while left < @vectors.size
      right = left + 1
      while right < @vectors.size
        if @vectors[left].to_s == @vectors[right].to_s
          raise "constant-norm code vectors must be distinct"
        right += 1
      left += 1
    @norm_squared = Combinatorics.dot(@vectors[0], @vectors[0])
    raise "constant-norm vectors must have positive norm" if @norm_squared <= 0

  -> size
    @vectors.size

  -> dimension
    @dimension

  -> norm_squared
    @norm_squared

  -> constant_norm?
    @vectors.each -> (vector)
      return false if Combinatorics.dot(vector, vector) != @norm_squared
    true

  -> maximum_inner_product_ratio
    return nil if !constant_norm?
    best = nil
    left = 0
    while left < @vectors.size
      right = left + 1
      while right < @vectors.size
        value = Rational.new(
          Combinatorics.dot(@vectors[left], @vectors[right]), @norm_squared)
        best = value if best == nil || value > best
        right += 1
      left += 1
    best

  -> certifies_maximum_inner_product?(bound)
    return false if !constant_norm?
    maximum_inner_product_ratio <= bound

  -> proof_kind
    :exact_finite_constant_norm_inner_product_replay
