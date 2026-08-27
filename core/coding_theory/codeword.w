# Owned codeword values.  Scalar Reed-Solomon words and position-major
# interleaved words are distinct types so lane order and block-Hamming
# semantics cannot be confused accidentally.

+ FiniteFieldCodeword
  -> new(field, symbols)
    __initialize_codeword(field, symbols, false)

  -> new(field, symbols, raw)
    __initialize_codeword(field, symbols, raw)

  -> .raw(field, symbols)
    FiniteFieldCodeword.new(field, symbols, true)

  -> __initialize_codeword(field, symbols, raw)
    @field = CodingTheorySupport.require_finite_field(field)
    if raw
      @symbols = CodingTheorySupport.normalize_elements(
        @field, symbols, "codeword symbols")
    else
      @symbols = CodingTheorySupport.coerce_elements(
        @field, symbols, "codeword symbols")
    self

  -> field
    @field

  -> size
    @symbols.size

  -> length
    size

  -> width
    1

  -> [](index)
    at(index)

  -> at(index)
    if index < 0 || index >= @symbols.size
      raise "codeword index out of range"
    @symbols[index]

  -> symbol_at(position, lane = 0)
    raise "scalar codeword lane must be zero" if lane != 0
    at(position)

  -> symbols
    CodingTheorySupport.copy_array(@symbols)

  -> to_a
    symbols

  -> hamming_distance(other)
    CodingTheoryMetrics.hamming_distance(self, other)

  -> agreement_count(other)
    CodingTheoryMetrics.agreement_count(self, other)

  -> agreement_fraction(other)
    CodingTheoryMetrics.agreement_fraction(self, other)

  -> ==(other)
    return false if other.class_name != "FiniteFieldCodeword"
    return false if @field != other.field
    return false if size != other.size
    i = 0
    while i < size
      return false if !@field.equal?(@symbols[i], other.at(i))
      i += 1
    true

  -> to_s
    "FiniteFieldCodeword(" + @symbols.to_s + ")"

  -> inspect
    to_s


+ InterleavedCodeword
  -> new(field, rows)
    __initialize_codeword(field, rows, nil, false)

  -> new(field, rows, width)
    __initialize_codeword(field, rows, width, false)

  -> new(field, rows, width, raw)
    __initialize_codeword(field, rows, width, raw)

  -> .raw(field, rows)
    InterleavedCodeword.new(field, rows, nil, true)

  -> .raw(field, rows, width)
    InterleavedCodeword.new(field, rows, width, true)

  -> __initialize_codeword(field, rows, width, raw)
    @field = CodingTheorySupport.require_finite_field(field)
    CodingTheorySupport.require_array(rows, "interleaved codeword rows")
    if width == nil
      raise "cannot infer interleaving from an empty codeword" if rows.size == 0
      CodingTheorySupport.require_array(rows[0], "interleaved codeword row")
      width = rows[0].size
    CodingTheorySupport.require_positive_integer(width, "interleaving")
    @width = width
    @rows = []
    position = 0
    while position < rows.size
      row = rows[position]
      CodingTheorySupport.require_array(row, "interleaved codeword row")
      if row.size != @width
        raise "interleaved codeword rows must have the declared width"
      if raw
        @rows.push(CodingTheorySupport.normalize_elements(
          @field, row, "interleaved codeword row"))
      else
        @rows.push(CodingTheorySupport.coerce_elements(
          @field, row, "interleaved codeword row"))
      position += 1
    self

  -> field
    @field

  -> size
    @rows.size

  -> length
    size

  -> width
    @width

  -> row(position)
    if position < 0 || position >= @rows.size
      raise "interleaved codeword position out of range"
    CodingTheorySupport.copy_array(@rows[position])

  -> [](position)
    row(position)

  -> at(position, lane)
    if position < 0 || position >= @rows.size
      raise "interleaved codeword position out of range"
    if lane < 0 || lane >= @width
      raise "interleaved codeword lane out of range"
    @rows[position][lane]

  -> symbol_at(position, lane)
    at(position, lane)

  -> rows
    CodingTheorySupport.copy_nested_array(@rows)

  -> to_a
    rows

  -> hamming_distance(other)
    CodingTheoryMetrics.hamming_distance(self, other)

  -> component_hamming_distance(other, lane)
    CodingTheoryMetrics.component_hamming_distance(self, other, lane)

  -> agreement_count(other)
    CodingTheoryMetrics.agreement_count(self, other)

  -> agreement_fraction(other)
    CodingTheoryMetrics.agreement_fraction(self, other)

  -> ==(other)
    return false if other.class_name != "InterleavedCodeword"
    return false if @field != other.field || @width != other.width
    return false if size != other.size
    position = 0
    while position < size
      lane = 0
      while lane < @width
        if !@field.equal?(@rows[position][lane], other.at(position, lane))
          return false
        lane += 1
      position += 1
    true

  -> to_s
    text = "InterleavedCodeword(width=" + @width.to_s
    text += ", rows=" + @rows.to_s + ")"
    text

  -> inspect
    to_s
