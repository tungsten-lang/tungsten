# Exact whole-symbol Hamming and agreement metrics.  For an interleaved word,
# one coordinate disagrees when any lane differs.  This is deliberately
# separate from componentwise scalar distance.

+ CodingTheoryMetrics
  -> .require_compatible(left, right)
    left_name = left == nil ? "Nil" : left.class_name
    right_name = right == nil ? "Nil" : right.class_name
    if left_name != right_name
      raise "coding-theory words must use the same representation"
    if left_name != "FiniteFieldCodeword" && left_name != "InterleavedCodeword"
      raise "coding-theory metrics expect finite-field codewords"
    if left.field != right.field
      raise "coding-theory words belong to different finite fields"
    if left.size != right.size || left.width != right.width
      raise "coding-theory words must have the same shape"
    true

  -> .position_equal?(left, right, position)
    lane = 0
    while lane < left.width
      if !left.field.equal?(
        left.symbol_at(position, lane), right.symbol_at(position, lane))
        return false
      lane += 1
    true

  -> .hamming_distance(left, right)
    CodingTheoryMetrics.require_compatible(left, right)
    distance = 0
    position = 0
    while position < left.size
      if !CodingTheoryMetrics.position_equal?(left, right, position)
        distance += 1
      position += 1
    distance

  -> .agreement_count(left, right)
    distance = CodingTheoryMetrics.hamming_distance(left, right)
    left.size - distance

  -> .relative_distance(left, right)
    CodingTheoryMetrics.require_nonempty(left)
    Rational.new(CodingTheoryMetrics.hamming_distance(left, right), left.size)

  -> .agreement_fraction(left, right)
    CodingTheoryMetrics.require_nonempty(left)
    Rational.new(CodingTheoryMetrics.agreement_count(left, right), left.size)

  -> .agreement_indices(left, right)
    CodingTheoryMetrics.require_compatible(left, right)
    indices = []
    position = 0
    while position < left.size
      if CodingTheoryMetrics.position_equal?(left, right, position)
        indices.push(position)
      position += 1
    indices

  -> .within_errors?(left, right, maximum_errors)
    CodingTheorySupport.require_nonnegative_integer(
      maximum_errors, "maximum Hamming errors")
    CodingTheoryMetrics.require_compatible(left, right)
    errors = 0
    position = 0
    while position < left.size
      if !CodingTheoryMetrics.position_equal?(left, right, position)
        errors += 1
        return false if errors > maximum_errors
      position += 1
    true

  -> .component_hamming_distance(left, right, lane)
    CodingTheoryMetrics.require_compatible(left, right)
    if left.class_name != "InterleavedCodeword"
      raise "component distance requires interleaved codewords"
    CodingTheorySupport.require_nonnegative_integer(lane, "interleaving lane")
    raise "interleaving lane out of range" if lane >= left.width
    distance = 0
    position = 0
    while position < left.size
      if !left.field.equal?(left.at(position, lane), right.at(position, lane))
        distance += 1
      position += 1
    distance

  # Count supplied entries in a Hamming ball. Duplicate entries count more
  # than once. This is finite enumeration, not a list-decoding theorem or an
  # implicit enumeration of a code.
  -> .enumerated_ball_count(candidates, received, maximum_errors)
    CodingTheorySupport.require_array(candidates, "candidate codewords")
    CodingTheorySupport.require_nonnegative_integer(
      maximum_errors, "maximum Hamming errors")
    count = 0
    i = 0
    while i < candidates.size
      if CodingTheoryMetrics.within_errors?(
        candidates[i], received, maximum_errors)
        count += 1
      i += 1
    count

  -> .require_nonempty(word)
    CodingTheoryMetrics.require_compatible(word, word)
    raise "relative coding-theory metrics require a nonempty word" if word.size == 0
    true
