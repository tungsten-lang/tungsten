# Versioned, plain-Tungsten interchange records for exact coding-theory data.
#
# This is an in-process Core stability seam, not an external wire format.  The
# records contain only String-keyed Hashes, Arrays, Integers, booleans, and nil;
# they do not depend on JSON, ArkLib, Lean, or a protocol profile.  Every
# finite-field element is represented by exactly `field.degree` power-basis
# coefficients in ascending degree order.  Packed runtime Integers therefore
# never become an accidental external field-element ABI.

+ CodingTheoryInterchange
  -> .format
    "tungsten-coding-theory"

  -> .schema_version
    1

  -> .new_record(kind)
    {
      "format": CodingTheoryInterchange.format,
      "schema_version": CodingTheoryInterchange.schema_version,
      "kind": kind
    }

  -> .require_header(record, kind)
    CodingTheorySupport.require_record_header(record, kind)

  -> .require_key(record, key, label)
    if !record.has_key?(key)
      raise label + " is missing " + key
    record[key]

  -> .require_string(value, label)
    raise label + " must be a String" if value.class_name != "String"
    value

  -> .require_boolean(value, label)
    if value != true && value != false
      raise label + " must be a boolean"
    value

  -> .require_layout(record, expected, label)
    layout = CodingTheoryInterchange.require_key(record, "layout", label)
    CodingTheoryInterchange.require_string(layout, label + " layout")
    if layout != expected
      raise label + " uses an unsupported layout"
    layout

  -> .require_equal(actual, expected, label)
    if actual != expected
      raise label + " is inconsistent with the record contents"
    actual

  -> .copy_modulus(field)
    return nil if field.prime_field?
    # The certificate accessor supplies the validated canonical coefficients
    # as an owned Array; FiniteField#modulus is defensive as well.
    field.modulus_certificate.modulus

  # ---- Finite fields and elements ---------------------------------------

  -> .field_to_record(field)
    field = CodingTheorySupport.require_finite_field(field)
    record = CodingTheoryInterchange.new_record("finite-field")
    record["characteristic"] = field.characteristic
    record["degree"] = field.degree
    record["element_layout"] = "power-basis-low-degree-first"
    record["modulus_layout"] = "low-degree-first-monic"
    record["modulus"] = CodingTheoryInterchange.copy_modulus(field)
    record

  -> .field_from_record(record)
    CodingTheoryInterchange.require_header(record, "finite-field")
    characteristic = CodingTheorySupport.require_positive_integer(
      CodingTheoryInterchange.require_key(
        record, "characteristic", "finite-field record"),
      "finite-field characteristic")
    degree = CodingTheorySupport.require_positive_integer(
      CodingTheoryInterchange.require_key(
        record, "degree", "finite-field record"),
      "finite-field degree")
    element_layout = CodingTheoryInterchange.require_key(
      record, "element_layout", "finite-field record")
    CodingTheoryInterchange.require_string(
      element_layout, "finite-field element layout")
    if element_layout != "power-basis-low-degree-first"
      raise "unsupported finite-field element layout"
    modulus_layout = CodingTheoryInterchange.require_key(
      record, "modulus_layout", "finite-field record")
    CodingTheoryInterchange.require_string(
      modulus_layout, "finite-field modulus layout")
    if modulus_layout != "low-degree-first-monic"
      raise "unsupported finite-field modulus layout"
    modulus = CodingTheoryInterchange.require_key(
      record, "modulus", "finite-field record")

    if degree == 1
      if modulus != nil
        raise "prime-field interchange modulus must be nil"
      return FiniteField.new(characteristic)

    CodingTheorySupport.require_array(
      modulus, "finite-field interchange modulus")
    if modulus.size != degree + 1
      raise "finite-field interchange modulus has the wrong degree"
    normalized = []
    i = 0
    while i < modulus.size
      coefficient = CodingTheorySupport.require_integer(
        modulus[i], "finite-field modulus coefficient")
      if coefficient < 0 || coefficient >= characteristic
        raise "finite-field modulus coefficient is not a canonical residue"
      normalized.push(coefficient)
      i += 1
    if normalized[degree] != 1
      raise "finite-field interchange modulus must be monic"
    field = FiniteField.new(characteristic, normalized)
    CodingTheoryInterchange.require_equal(
      field.degree, degree, "finite-field degree")
    field

  -> .element_to_coefficients(field, value)
    field = CodingTheorySupport.require_finite_field(field)
    CodingTheoryInterchange.element_to_coefficients_raw(
      field, field.coerce(value))

  -> .element_to_coefficients_raw(field, value)
    field = CodingTheorySupport.require_finite_field(field)
    value = CodingTheorySupport.require_element(
      field, value, "finite-field interchange element")
    coefficients = field.element_coefficients(value)
    if coefficients.size != field.degree
      raise "finite-field element did not produce a full power-basis vector"
    coefficients

  -> .element_from_coefficients(field, coefficients)
    field = CodingTheorySupport.require_finite_field(field)
    CodingTheorySupport.require_array(
      coefficients, "finite-field element coefficients")
    if coefficients.size != field.degree
      raise "finite-field element coefficient width must equal the field degree"
    normalized = []
    i = 0
    while i < coefficients.size
      coefficient = CodingTheorySupport.require_integer(
        coefficients[i], "finite-field element coefficient")
      if coefficient < 0 || coefficient >= field.characteristic
        raise "finite-field element coefficient is not a canonical residue"
      normalized.push(coefficient)
      i += 1
    field.encode_coefficients(normalized)

  -> .elements_to_coefficients(field, values, label)
    CodingTheorySupport.require_array(values, label)
    out = []
    i = 0
    while i < values.size
      out.push(CodingTheoryInterchange.element_to_coefficients(
        field, values[i]))
      i += 1
    out

  -> .elements_to_coefficients_raw(field, values, label)
    CodingTheorySupport.require_array(values, label)
    out = []
    i = 0
    while i < values.size
      out.push(CodingTheoryInterchange.element_to_coefficients_raw(
        field, values[i]))
      i += 1
    out

  -> .elements_from_coefficients(field, values, label)
    CodingTheorySupport.require_array(values, label)
    out = []
    i = 0
    while i < values.size
      out.push(CodingTheoryInterchange.element_from_coefficients(
        field, values[i]))
      i += 1
    out

  -> .rows_to_coefficients(field, rows, row_count, width, label)
    CodingTheorySupport.require_array(rows, label)
    if rows.size != row_count
      raise label + " has the wrong row count"
    out = []
    row_index = 0
    while row_index < rows.size
      row = rows[row_index]
      CodingTheorySupport.require_array(row, label + " row")
      if row.size != width
        raise label + " rows have the wrong width"
      out.push(CodingTheoryInterchange.elements_to_coefficients(
        field, row, label + " row"))
      row_index += 1
    out

  -> .rows_to_coefficients_raw(field, rows, row_count, width, label)
    CodingTheorySupport.require_array(rows, label)
    if rows.size != row_count
      raise label + " has the wrong row count"
    out = []
    row_index = 0
    while row_index < rows.size
      row = rows[row_index]
      CodingTheorySupport.require_array(row, label + " row")
      if row.size != width
        raise label + " rows have the wrong width"
      out.push(CodingTheoryInterchange.elements_to_coefficients_raw(
        field, row, label + " row"))
      row_index += 1
    out

  -> .rows_from_coefficients(field, rows, row_count, width, label)
    CodingTheorySupport.require_array(rows, label)
    if rows.size != row_count
      raise label + " has the wrong row count"
    out = []
    row_index = 0
    while row_index < rows.size
      encoded_row = rows[row_index]
      CodingTheorySupport.require_array(encoded_row, label + " row")
      if encoded_row.size != width
        raise label + " rows have the wrong width"
      out.push(CodingTheoryInterchange.elements_from_coefficients(
        field, encoded_row, label + " row"))
      row_index += 1
    out

  # ---- Ordered evaluation domains --------------------------------------

  -> .domain_to_record(domain)
    if domain == nil || domain.class_name != "FiniteFieldEvaluationDomain"
      raise "domain interchange expects a FiniteFieldEvaluationDomain"
    record = CodingTheoryInterchange.new_record("evaluation-domain")
    record["field"] = CodingTheoryInterchange.field_to_record(domain.field)
    record["layout"] = "ordered-points"
    record["size"] = domain.size
    record["points"] = CodingTheoryInterchange.elements_to_coefficients_raw(
      domain.field, domain.points, "evaluation-domain points")
    record

  -> .domain_from_record(record)
    CodingTheoryInterchange.require_header(record, "evaluation-domain")
    CodingTheoryInterchange.require_layout(
      record, "ordered-points", "evaluation-domain record")
    field = CodingTheoryInterchange.field_from_record(
      CodingTheoryInterchange.require_key(
        record, "field", "evaluation-domain record"))
    size = CodingTheorySupport.require_positive_integer(
      CodingTheoryInterchange.require_key(
        record, "size", "evaluation-domain record"),
      "evaluation-domain size")
    encoded_points = CodingTheoryInterchange.require_key(
      record, "points", "evaluation-domain record")
    CodingTheorySupport.require_array(
      encoded_points, "evaluation-domain interchange points")
    CodingTheoryInterchange.require_equal(
      encoded_points.size, size, "evaluation-domain size")
    points = CodingTheoryInterchange.elements_from_coefficients(
      field, encoded_points, "evaluation-domain interchange points")
    FiniteFieldEvaluationDomain.raw(field, points)

  # ---- Reed-Solomon parameter descriptors -------------------------------

  -> .reed_solomon_parameters_to_record(code)
    if code == nil || code.class_name != "ReedSolomonCode"
      raise "Reed-Solomon parameter interchange expects a ReedSolomonCode"
    record = CodingTheoryInterchange.new_record("reed-solomon-parameters")
    record["domain"] = CodingTheoryInterchange.domain_to_record(code.domain)
    record["dimension_rule"] = "degree-below-bound"
    record["length"] = code.length
    record["degree_bound"] = code.degree_bound
    record["dimension"] = code.dimension
    record["encoder_injective"] = code.encoder_injective?
    record

  -> .reed_solomon_parameters_from_record(record)
    CodingTheoryInterchange.require_header(
      record, "reed-solomon-parameters")
    rule = CodingTheoryInterchange.require_key(
      record, "dimension_rule", "Reed-Solomon parameter record")
    CodingTheoryInterchange.require_string(
      rule, "Reed-Solomon dimension rule")
    if rule != "degree-below-bound"
      raise "unsupported Reed-Solomon dimension rule"
    domain = CodingTheoryInterchange.domain_from_record(
      CodingTheoryInterchange.require_key(
        record, "domain", "Reed-Solomon parameter record"))
    degree_bound = CodingTheorySupport.require_nonnegative_integer(
      CodingTheoryInterchange.require_key(
        record, "degree_bound", "Reed-Solomon parameter record"),
      "Reed-Solomon degree bound")
    code = ReedSolomonCode.new(domain, degree_bound)
    length = CodingTheorySupport.require_positive_integer(
      CodingTheoryInterchange.require_key(
        record, "length", "Reed-Solomon parameter record"),
      "Reed-Solomon length")
    dimension = CodingTheorySupport.require_nonnegative_integer(
      CodingTheoryInterchange.require_key(
        record, "dimension", "Reed-Solomon parameter record"),
      "Reed-Solomon dimension")
    injective = CodingTheoryInterchange.require_boolean(
      CodingTheoryInterchange.require_key(
        record, "encoder_injective", "Reed-Solomon parameter record"),
      "Reed-Solomon encoder-injective flag")
    CodingTheoryInterchange.require_equal(
      length, code.length, "Reed-Solomon length")
    CodingTheoryInterchange.require_equal(
      dimension, code.dimension, "Reed-Solomon dimension")
    CodingTheoryInterchange.require_equal(
      injective, code.encoder_injective?,
      "Reed-Solomon encoder-injective flag")
    code

  -> .interleaved_parameters_to_record(code)
    if code == nil || code.class_name != "InterleavedReedSolomonCode"
      raise "interleaved parameter interchange expects an InterleavedReedSolomonCode"
    record = CodingTheoryInterchange.new_record(
      "interleaved-reed-solomon-parameters")
    record["domain"] = CodingTheoryInterchange.domain_to_record(code.domain)
    record["dimension_rule"] = "s-times-min-floor-K-over-s-and-n"
    record["length"] = code.length
    record["dimension_budget"] = code.dimension_budget
    record["interleaving"] = code.interleaving
    record["lane_degree_bound"] = code.lane_degree_bound
    record["component_dimension"] = code.component_dimension
    record["message_size"] = code.message_size
    record["dimension"] = code.dimension
    record["floor_remainder"] = code.floor_remainder
    record["saturation_loss"] = code.saturation_loss
    record["unrepresented_budget"] = code.unrepresented_budget
    record["budget_exact"] = code.budget_exact?
    record["encoder_injective"] = code.encoder_injective?
    record

  -> .interleaved_parameters_from_record(record)
    CodingTheoryInterchange.require_header(
      record, "interleaved-reed-solomon-parameters")
    rule = CodingTheoryInterchange.require_key(
      record, "dimension_rule", "interleaved parameter record")
    CodingTheoryInterchange.require_string(
      rule, "interleaved dimension rule")
    if rule != "s-times-min-floor-K-over-s-and-n"
      raise "unsupported interleaved Reed-Solomon dimension rule"
    domain = CodingTheoryInterchange.domain_from_record(
      CodingTheoryInterchange.require_key(
        record, "domain", "interleaved parameter record"))
    dimension_budget = CodingTheorySupport.require_nonnegative_integer(
      CodingTheoryInterchange.require_key(
        record, "dimension_budget", "interleaved parameter record"),
      "interleaved dimension budget")
    interleaving = CodingTheorySupport.require_positive_integer(
      CodingTheoryInterchange.require_key(
        record, "interleaving", "interleaved parameter record"),
      "interleaving")
    code = InterleavedReedSolomonCode.new(
      domain, dimension_budget, interleaving)
    length = CodingTheorySupport.require_positive_integer(
      CodingTheoryInterchange.require_key(
        record, "length", "interleaved parameter record"),
      "interleaved Reed-Solomon length")
    lane_degree_bound = CodingTheorySupport.require_nonnegative_integer(
      CodingTheoryInterchange.require_key(
        record, "lane_degree_bound", "interleaved parameter record"),
      "interleaved lane degree bound")
    component_dimension = CodingTheorySupport.require_nonnegative_integer(
      CodingTheoryInterchange.require_key(
        record, "component_dimension", "interleaved parameter record"),
      "interleaved component dimension")
    message_size = CodingTheorySupport.require_nonnegative_integer(
      CodingTheoryInterchange.require_key(
        record, "message_size", "interleaved parameter record"),
      "interleaved message size")
    dimension = CodingTheorySupport.require_nonnegative_integer(
      CodingTheoryInterchange.require_key(
        record, "dimension", "interleaved parameter record"),
      "interleaved Reed-Solomon dimension")
    floor_remainder = CodingTheorySupport.require_nonnegative_integer(
      CodingTheoryInterchange.require_key(
        record, "floor_remainder", "interleaved parameter record"),
      "interleaved floor remainder")
    saturation_loss = CodingTheorySupport.require_nonnegative_integer(
      CodingTheoryInterchange.require_key(
        record, "saturation_loss", "interleaved parameter record"),
      "interleaved saturation loss")
    unrepresented_budget = CodingTheorySupport.require_nonnegative_integer(
      CodingTheoryInterchange.require_key(
        record, "unrepresented_budget", "interleaved parameter record"),
      "interleaved unrepresented budget")
    budget_exact = CodingTheoryInterchange.require_boolean(
      CodingTheoryInterchange.require_key(
        record, "budget_exact", "interleaved parameter record"),
      "interleaved budget-exact flag")
    injective = CodingTheoryInterchange.require_boolean(
      CodingTheoryInterchange.require_key(
        record, "encoder_injective", "interleaved parameter record"),
      "interleaved encoder-injective flag")
    CodingTheoryInterchange.require_equal(
      length, code.length, "interleaved Reed-Solomon length")
    CodingTheoryInterchange.require_equal(
      lane_degree_bound, code.lane_degree_bound,
      "interleaved lane degree bound")
    CodingTheoryInterchange.require_equal(
      component_dimension, code.component_dimension,
      "interleaved component dimension")
    CodingTheoryInterchange.require_equal(
      message_size, code.message_size, "interleaved message size")
    CodingTheoryInterchange.require_equal(
      dimension, code.dimension, "interleaved Reed-Solomon dimension")
    CodingTheoryInterchange.require_equal(
      floor_remainder, code.floor_remainder,
      "interleaved floor remainder")
    CodingTheoryInterchange.require_equal(
      saturation_loss, code.saturation_loss,
      "interleaved saturation loss")
    CodingTheoryInterchange.require_equal(
      unrepresented_budget, code.unrepresented_budget,
      "interleaved unrepresented budget")
    CodingTheoryInterchange.require_equal(
      budget_exact, code.budget_exact?, "interleaved budget-exact flag")
    CodingTheoryInterchange.require_equal(
      injective, code.encoder_injective?,
      "interleaved encoder-injective flag")
    code

  # ---- Messages ---------------------------------------------------------

  -> .reed_solomon_message_to_record(code, message)
    if code == nil || code.class_name != "ReedSolomonCode"
      raise "Reed-Solomon message interchange expects a ReedSolomonCode"
    normalized = code.normalize_message(message)
    CodingTheoryInterchange.__reed_solomon_message_raw_to_record(
      code, normalized)

  -> .reed_solomon_message_to_record_raw(code, message)
    if code == nil || code.class_name != "ReedSolomonCode"
      raise "Reed-Solomon message interchange expects a ReedSolomonCode"
    normalized = code.normalize_message_raw(message)
    CodingTheoryInterchange.__reed_solomon_message_raw_to_record(
      code, normalized)

  -> .__reed_solomon_message_raw_to_record(code, message)
    message = code.normalize_message_raw(message)
    record = CodingTheoryInterchange.new_record("reed-solomon-message")
    record["parameters"] = CodingTheoryInterchange.reed_solomon_parameters_to_record(
      code)
    record["layout"] = "low-degree-first"
    record["coefficient_count"] = message.size
    record["coefficients"] = CodingTheoryInterchange.elements_to_coefficients_raw(
      code.field, message, "Reed-Solomon message")
    record

  -> .reed_solomon_message_from_record(record)
    bundle = CodingTheoryInterchange.reed_solomon_message_bundle_from_record(
      record)
    bundle["message"]

  # Return the reconstructed code together with its raw normalized message.
  # This is the safest loader for extension fields because the packed Integer
  # elements never become detached from the field/domain that interprets them.
  -> .reed_solomon_message_bundle_from_record(record)
    CodingTheoryInterchange.require_header(record, "reed-solomon-message")
    CodingTheoryInterchange.require_layout(
      record, "low-degree-first", "Reed-Solomon message record")
    code = CodingTheoryInterchange.reed_solomon_parameters_from_record(
      CodingTheoryInterchange.require_key(
        record, "parameters", "Reed-Solomon message record"))
    coefficient_count = CodingTheorySupport.require_nonnegative_integer(
      CodingTheoryInterchange.require_key(
        record, "coefficient_count", "Reed-Solomon message record"),
      "Reed-Solomon message coefficient count")
    encoded = CodingTheoryInterchange.require_key(
      record, "coefficients", "Reed-Solomon message record")
    CodingTheorySupport.require_array(encoded, "Reed-Solomon message coefficients")
    CodingTheoryInterchange.require_equal(
      coefficient_count, encoded.size,
      "Reed-Solomon message coefficient count")
    CodingTheoryInterchange.require_equal(
      coefficient_count, code.degree_bound,
      "Reed-Solomon message coefficient count")
    message = CodingTheoryInterchange.elements_from_coefficients(
      code.field, encoded, "Reed-Solomon message coefficients")
    {"code": code, "message": message}

  -> .interleaved_message_to_record(code, columns)
    if code == nil || code.class_name != "InterleavedReedSolomonCode"
      raise "interleaved message interchange expects an InterleavedReedSolomonCode"
    normalized = code.normalize_columns(columns)
    CodingTheoryInterchange.__interleaved_message_raw_to_record(
      code, normalized)

  -> .interleaved_message_to_record_raw(code, columns)
    if code == nil || code.class_name != "InterleavedReedSolomonCode"
      raise "interleaved message interchange expects an InterleavedReedSolomonCode"
    normalized = code.normalize_columns_raw(columns)
    CodingTheoryInterchange.__interleaved_message_raw_to_record(
      code, normalized)

  -> .__interleaved_message_raw_to_record(code, columns)
    columns = code.normalize_columns_raw(columns)
    encoded_columns = CodingTheoryInterchange.rows_to_coefficients_raw(
      code.field, columns, code.interleaving, code.lane_degree_bound,
      "interleaved message columns")
    record = CodingTheoryInterchange.new_record(
      "interleaved-reed-solomon-message")
    record["parameters"] = CodingTheoryInterchange.interleaved_parameters_to_record(
      code)
    record["layout"] = "lane-major-low-degree-first"
    record["column_count"] = code.interleaving
    record["column_length"] = code.lane_degree_bound
    record["columns"] = encoded_columns
    record

  -> .interleaved_message_from_record(record)
    bundle = CodingTheoryInterchange.interleaved_message_bundle_from_record(
      record)
    bundle["message"]

  # Return the reconstructed code together with the raw normalized lane-major
  # message.  Keeping both values avoids losing extension-field provenance.
  -> .interleaved_message_bundle_from_record(record)
    CodingTheoryInterchange.require_header(
      record, "interleaved-reed-solomon-message")
    CodingTheoryInterchange.require_layout(
      record, "lane-major-low-degree-first", "interleaved message record")
    code = CodingTheoryInterchange.interleaved_parameters_from_record(
      CodingTheoryInterchange.require_key(
        record, "parameters", "interleaved message record"))
    column_count = CodingTheorySupport.require_positive_integer(
      CodingTheoryInterchange.require_key(
        record, "column_count", "interleaved message record"),
      "interleaved message column count")
    column_length = CodingTheorySupport.require_nonnegative_integer(
      CodingTheoryInterchange.require_key(
        record, "column_length", "interleaved message record"),
      "interleaved message column length")
    CodingTheoryInterchange.require_equal(
      column_count, code.interleaving, "interleaved message column count")
    CodingTheoryInterchange.require_equal(
      column_length, code.lane_degree_bound,
      "interleaved message column length")
    columns = CodingTheoryInterchange.require_key(
      record, "columns", "interleaved message record")
    message = CodingTheoryInterchange.rows_from_coefficients(
      code.field, columns, column_count, column_length,
      "interleaved message columns")
    {"code": code, "message": message}

  # ---- Codewords --------------------------------------------------------

  -> .reed_solomon_codeword_to_record(code, codeword)
    if code == nil || code.class_name != "ReedSolomonCode"
      raise "Reed-Solomon codeword interchange expects a ReedSolomonCode"
    if codeword == nil || codeword.class_name != "FiniteFieldCodeword"
      raise "Reed-Solomon codeword interchange expects a FiniteFieldCodeword"
    if codeword.field != code.field || codeword.size != code.length
      raise "Reed-Solomon codeword is incompatible with the code parameters"
    if !code.contains?(codeword)
      raise "Reed-Solomon codeword record requires a code member"
    record = CodingTheoryInterchange.new_record("reed-solomon-codeword")
    record["parameters"] = CodingTheoryInterchange.reed_solomon_parameters_to_record(
      code)
    record["layout"] = "domain-order"
    record["symbol_count"] = codeword.size
    record["symbols"] = CodingTheoryInterchange.elements_to_coefficients_raw(
      code.field, codeword.symbols, "Reed-Solomon codeword symbols")
    record

  -> .reed_solomon_codeword_from_record(record)
    bundle = CodingTheoryInterchange.reed_solomon_codeword_bundle_from_record(
      record)
    bundle["codeword"]

  # Retain the exact code whose membership was checked while loading.
  -> .reed_solomon_codeword_bundle_from_record(record)
    CodingTheoryInterchange.require_header(record, "reed-solomon-codeword")
    CodingTheoryInterchange.require_layout(
      record, "domain-order", "Reed-Solomon codeword record")
    code = CodingTheoryInterchange.reed_solomon_parameters_from_record(
      CodingTheoryInterchange.require_key(
        record, "parameters", "Reed-Solomon codeword record"))
    symbol_count = CodingTheorySupport.require_positive_integer(
      CodingTheoryInterchange.require_key(
        record, "symbol_count", "Reed-Solomon codeword record"),
      "Reed-Solomon codeword symbol count")
    CodingTheoryInterchange.require_equal(
      symbol_count, code.length, "Reed-Solomon codeword symbol count")
    encoded = CodingTheoryInterchange.require_key(
      record, "symbols", "Reed-Solomon codeword record")
    CodingTheorySupport.require_array(encoded, "Reed-Solomon codeword symbols")
    CodingTheoryInterchange.require_equal(
      encoded.size, symbol_count, "Reed-Solomon codeword symbol count")
    symbols = CodingTheoryInterchange.elements_from_coefficients(
      code.field, encoded, "Reed-Solomon codeword symbols")
    codeword = code.codeword_raw(symbols)
    {"code": code, "codeword": codeword}

  -> .interleaved_codeword_to_record(code, codeword)
    if code == nil || code.class_name != "InterleavedReedSolomonCode"
      raise "interleaved codeword interchange expects an InterleavedReedSolomonCode"
    if codeword == nil || codeword.class_name != "InterleavedCodeword"
      raise "interleaved codeword interchange expects an InterleavedCodeword"
    if codeword.field != code.field || codeword.size != code.length
      raise "interleaved codeword is incompatible with the code parameters"
    if codeword.width != code.interleaving
      raise "interleaved codeword has the wrong interleaving"
    if !code.contains?(codeword)
      raise "interleaved codeword record requires a code member"
    record = CodingTheoryInterchange.new_record(
      "interleaved-reed-solomon-codeword")
    record["parameters"] = CodingTheoryInterchange.interleaved_parameters_to_record(
      code)
    record["layout"] = "position-major-lane-minor"
    record["position_count"] = codeword.size
    record["interleaving"] = codeword.width
    record["rows"] = CodingTheoryInterchange.rows_to_coefficients_raw(
      code.field, codeword.rows, code.length, code.interleaving,
      "interleaved codeword rows")
    record

  -> .interleaved_codeword_from_record(record)
    bundle = CodingTheoryInterchange.interleaved_codeword_bundle_from_record(
      record)
    bundle["codeword"]

  # Retain the exact interleaved code whose membership was checked while
  # loading, including its domain and floor/saturation convention.
  -> .interleaved_codeword_bundle_from_record(record)
    CodingTheoryInterchange.require_header(
      record, "interleaved-reed-solomon-codeword")
    CodingTheoryInterchange.require_layout(
      record, "position-major-lane-minor", "interleaved codeword record")
    code = CodingTheoryInterchange.interleaved_parameters_from_record(
      CodingTheoryInterchange.require_key(
        record, "parameters", "interleaved codeword record"))
    position_count = CodingTheorySupport.require_positive_integer(
      CodingTheoryInterchange.require_key(
        record, "position_count", "interleaved codeword record"),
      "interleaved codeword position count")
    interleaving = CodingTheorySupport.require_positive_integer(
      CodingTheoryInterchange.require_key(
        record, "interleaving", "interleaved codeword record"),
      "interleaved codeword interleaving")
    CodingTheoryInterchange.require_equal(
      position_count, code.length, "interleaved codeword position count")
    CodingTheoryInterchange.require_equal(
      interleaving, code.interleaving, "interleaved codeword interleaving")
    rows = CodingTheoryInterchange.require_key(
      record, "rows", "interleaved codeword record")
    decoded = CodingTheoryInterchange.rows_from_coefficients(
      code.field, rows, position_count, interleaving,
      "interleaved codeword rows")
    codeword = code.codeword_raw(decoded)
    {"code": code, "codeword": codeword}
