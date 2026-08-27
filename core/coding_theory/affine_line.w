# The ordered affine-line generator z |-> (1, z) and its induced componentwise
# combination U0 + z*U1.  These are ordered pairs/rows: SymmetricTuple is not
# used because swapping the two components changes the affine combination.

+ AffineLineGenerator
  -> new(field)
    @field = CodingTheorySupport.require_finite_field(field)
    self

  -> field
    @field

  -> coordinates(parameter)
    __coordinates_raw(@field.coerce(parameter))

  -> coordinates_raw(parameter)
    parameter = CodingTheorySupport.require_element(
      @field, parameter, "affine-line parameter")
    __coordinates_raw(parameter)

  -> __coordinates_raw(parameter)
    [@field.one, parameter]

  -> at(parameter)
    coordinates(parameter)

  -> at_raw(parameter)
    coordinates_raw(parameter)

  -> combine(base, direction, parameter)
    __combine_raw(
      @field.coerce(base), @field.coerce(direction), @field.coerce(parameter))

  -> combine_raw(base, direction, parameter)
    base = CodingTheorySupport.require_element(
      @field, base, "affine-line base")
    direction = CodingTheorySupport.require_element(
      @field, direction, "affine-line direction")
    parameter = CodingTheorySupport.require_element(
      @field, parameter, "affine-line parameter")
    __combine_raw(base, direction, parameter)

  -> __combine_raw(base, direction, parameter)
    @field.add(base, @field.multiply(parameter, direction))

  -> combine_words(base_word, direction_word, parameter)
    __combine_words_raw(
      base_word, direction_word, @field.coerce(parameter))

  -> combine_words_raw(base_word, direction_word, parameter)
    parameter = CodingTheorySupport.require_element(
      @field, parameter, "affine-line parameter")
    __combine_words_raw(base_word, direction_word, parameter)

  -> __combine_words_raw(base_word, direction_word, parameter)
    if base_word.class_name != direction_word.class_name
      raise "affine-line words must use the same codeword representation"
    name = base_word.class_name
    if name != "FiniteFieldCodeword" && name != "InterleavedCodeword"
      raise "affine-line combination expects finite-field codewords"
    if base_word.field != @field || direction_word.field != @field
      raise "affine-line words belong to a different finite field"
    if base_word.size != direction_word.size || base_word.width != direction_word.width
      raise "affine-line words must have the same shape"

    if name == "FiniteFieldCodeword"
      symbols = []
      i = 0
      while i < base_word.size
        symbols.push(__combine_raw(
          base_word.at(i), direction_word.at(i), parameter))
        i += 1
      return FiniteFieldCodeword.raw(@field, symbols)

    rows = []
    i = 0
    while i < base_word.size
      row = []
      lane = 0
      while lane < base_word.width
        row.push(__combine_raw(
          base_word.at(i, lane), direction_word.at(i, lane), parameter))
        lane += 1
      rows.push(row)
      i += 1
    InterleavedCodeword.raw(@field, rows, base_word.width)
