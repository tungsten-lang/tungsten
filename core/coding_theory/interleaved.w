# Position-major interleaving of equal Reed-Solomon component codes.  A caller
# supplies a total dimension budget K and an interleaving count s; each lane
# receives floor(K/s) coefficients.  The discarded floor remainder and any
# dimension loss from domain saturation remain explicit.

+ InterleavedReedSolomonCode
  -> new(domain, dimension_budget, interleaving)
    if domain == nil || domain.class_name != "FiniteFieldEvaluationDomain"
      raise "interleaved Reed-Solomon codes require an evaluation domain"
    @domain = domain
    @field = domain.field
    @dimension_budget = CodingTheorySupport.require_nonnegative_integer(
      dimension_budget, "interleaved dimension budget")
    @interleaving = CodingTheorySupport.require_positive_integer(
      interleaving, "interleaving")
    @lane_degree_bound = @dimension_budget / @interleaving
    @component_code = ReedSolomonCode.new(@domain, @lane_degree_bound)
    self

  -> domain
    @domain

  -> field
    @field

  -> length
    @domain.size

  -> size
    length

  -> dimension_budget
    @dimension_budget

  -> requested_dimension
    @dimension_budget

  -> interleaving
    @interleaving

  -> lane_degree_bound
    @lane_degree_bound

  -> component_dimension
    @component_code.dimension

  -> dimension
    @interleaving * component_dimension

  -> message_size
    @interleaving * @lane_degree_bound

  -> floor_remainder
    @dimension_budget - message_size

  -> saturation_loss
    message_size - dimension

  -> unrepresented_budget
    floor_remainder + saturation_loss

  -> budget_exact?
    unrepresented_budget == 0

  -> encoder_injective?
    @component_code.encoder_injective?

  -> zero_code?
    dimension == 0

  -> minimum_distance
    @component_code.minimum_distance

  # Rate in interleaved alphabet symbols, not base-field scalars.
  -> rate
    Rational.new(component_dimension, length)

  -> normalize_columns(columns)
    __normalize_columns(columns, false)

  -> normalize_columns_raw(columns)
    __normalize_columns(columns, true)

  -> __normalize_columns(columns, raw)
    CodingTheorySupport.require_array(columns, "interleaved message lanes")
    if columns.size != @interleaving
      raise "interleaved message must contain exactly one Array per lane"
    out = []
    lane = 0
    while lane < columns.size
      column = columns[lane]
      CodingTheorySupport.require_array(column, "interleaved message lane")
      if column.size != @lane_degree_bound
        raise "interleaved lane length must equal the lane degree bound"
      if raw
        out.push(CodingTheorySupport.normalize_elements(
          @field, column, "interleaved coefficient"))
      else
        out.push(CodingTheorySupport.coerce_elements(
          @field, column, "interleaved coefficient"))
      lane += 1
    out

  -> encode_columns(columns)
    __encode_columns_normalized(normalize_columns(columns))

  -> encode_columns_raw(columns)
    __encode_columns_normalized(normalize_columns_raw(columns))

  -> encode(columns)
    encode_columns(columns)

  -> encode_raw(columns)
    encode_columns_raw(columns)

  -> __encode_columns_normalized(columns)
    lane_words = []
    lane = 0
    while lane < @interleaving
      lane_words.push(@component_code.encode_raw(columns[lane]))
      lane += 1
    rows = []
    position = 0
    while position < length
      row = []
      lane = 0
      while lane < @interleaving
        row.push(lane_words[lane].at(position))
        lane += 1
      rows.push(row)
      position += 1
    InterleavedCodeword.raw(@field, rows, @interleaving)

  # Flat messages are lane-major.  Their length is the actual message size,
  # not the requested budget, so a floor remainder is never silently dropped.
  -> encode_lane_major(coefficients)
    __encode_columns_normalized(__split_lane_major(coefficients, false))

  -> encode_lane_major_raw(coefficients)
    __encode_columns_normalized(__split_lane_major(coefficients, true))

  -> __split_lane_major(coefficients, raw)
    CodingTheorySupport.require_array(coefficients, "interleaved flat message")
    if coefficients.size != message_size
      raise "interleaved flat message length must equal the actual message size"
    columns = []
    lane = 0
    while lane < @interleaving
      column = []
      degree = 0
      while degree < @lane_degree_bound
        value = coefficients[lane * @lane_degree_bound + degree]
        if raw
          value = CodingTheorySupport.require_element(
            @field, value, "interleaved coefficient")
        else
          value = @field.coerce(value)
        column.push(value)
        degree += 1
      columns.push(column)
      lane += 1
    columns

  -> contains?(word)
    return false if word == nil || word.class_name != "InterleavedCodeword"
    return false if word.field != @field
    return false if word.size != length || word.width != @interleaving
    lane = 0
    while lane < @interleaving
      symbols = []
      position = 0
      while position < length
        symbols.push(word.at(position, lane))
        position += 1
      lane_word = FiniteFieldCodeword.raw(@field, symbols)
      return false if !@component_code.contains?(lane_word)
      lane += 1
    true

  -> include?(word)
    contains?(word)

  -> codeword(rows)
    word = InterleavedCodeword.new(@field, rows, @interleaving)
    __require_codeword(word)

  -> codeword_raw(rows)
    word = InterleavedCodeword.raw(@field, rows, @interleaving)
    __require_codeword(word)

  -> __require_codeword(word)
    if word.size != length
      raise "interleaved codeword length does not match the domain"
    if !contains?(word)
      raise "word is not a member of the interleaved Reed-Solomon code"
    word

  -> to_s
    text = "InterleavedReedSolomonCode(length=" + length.to_s
    text += ", interleaving=" + @interleaving.to_s
    text += ", lane_degree_bound=" + @lane_degree_bound.to_s
    text += ", dimension=" + dimension.to_s + ")"
    text

  -> inspect
    to_s
