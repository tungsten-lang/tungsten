# Shared validation and copy helpers for the protocol-neutral coding-theory
# layer.  The first surface intentionally accepts FiniteField rather than an
# arbitrary Field: FiniteField gives every element a canonical packed-base-p
# Integer representation, which makes ordered domains and interchange records
# deterministic without inventing a second scalar ABI.

+ CodingTheorySupport
  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> .require_integer(value, label)
    if !CodingTheorySupport.integer?(value)
      raise label + " must be an integer"
    value

  -> .require_nonnegative_integer(value, label)
    CodingTheorySupport.require_integer(value, label)
    raise label + " must be nonnegative" if value < 0
    value

  -> .require_positive_integer(value, label)
    CodingTheorySupport.require_integer(value, label)
    raise label + " must be positive" if value < 1
    value

  -> .require_array(value, label)
    raise label + " must be an Array" if value.class_name != "Array"
    value

  -> .require_hash(value, label)
    raise label + " must be a Hash" if value.class_name != "Hash"
    value

  -> .require_finite_field(field)
    if field == nil || field.class_name != "FiniteField"
      raise "coding theory currently requires a FiniteField"
    field

  # Coding-theory domains, messages, and codewords contain field elements,
  # not external Integer scalars.  Extension-field values are therefore raw
  # packed residues in [0, field.order), exactly as returned by FiniteField.
  -> .require_element(field, value, label)
    CodingTheorySupport.require_finite_field(field)
    CodingTheorySupport.require_integer(value, label)
    if value < 0 || value >= field.order
      raise label + " is outside the finite-field element range"
    value

  -> .copy_array(values)
    out = []
    values.each -> (value) out.push(value)
    out

  -> .copy_nested_array(values)
    out = []
    values.each -> (row)
      CodingTheorySupport.require_array(row, "nested value")
      out.push(CodingTheorySupport.copy_array(row))
    out

  -> .normalize_elements(field, values, label)
    CodingTheorySupport.require_array(values, label)
    out = []
    i = 0
    while i < values.size
      out.push(CodingTheorySupport.require_element(
        field, values[i], label + "[" + i.to_s + "]"))
      i += 1
    out

  -> .coerce_elements(field, values, label)
    CodingTheorySupport.require_array(values, label)
    out = []
    i = 0
    while i < values.size
      out.push(field.coerce(values[i]))
      i += 1
    out

  -> .require_record_header(record, kind)
    CodingTheorySupport.require_hash(record, "coding-theory interchange record")
    format = record["format"]
    if format.class_name != "String" || format != "tungsten-coding-theory"
      raise "unsupported coding-theory interchange format"
    version = record["schema_version"]
    if !CodingTheorySupport.integer?(version) || version != 1
      raise "unsupported coding-theory interchange version"
    record_kind = record["kind"]
    if record_kind.class_name != "String" || record_kind != kind
      raise "unexpected coding-theory interchange record type"
    record
