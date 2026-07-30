# Deterministic standalone Tungsten source export for fitted classification
# trees.
#
#     model = DecisionTreeClassifier.new(3).fit(x, arm_ids)
#     artifact = DecisionTreeExport.export(
#       model,
#       [:variables, :clauses, :literal_count],
#       :wassat_select_arm
#     )
#     artifact[:source] # write this text into Wassat's source tree
#
# The emitted file has no Koala dependency. It contains:
#
#   * three metadata functions (`<name>_schema_version`,
#     `<name>_schema_checksum`, and `<name>_feature_count`);
#   * one prediction function `<name>(features, feature_schema_checksum)`;
#   * nested `if features[i].to_f <= ~threshold` comparisons, left first,
#     ending directly in numeric class literals.
#
# The prediction function REQUIRES the schema checksum as its second argument
# and rejects a mismatched checksum or feature count. The integration should
# pin `artifact[:schema_checksum]` independently beside the code that builds
# `features`; taking the value from the generated helper at every call would
# defeat the drift guard:
#
#     WASSAT_ROUTER_SCHEMA = 1846011820 # pinned from the artifact above
#     arm = wassat_select_arm(features, WASSAT_ROUTER_SCHEMA)
#
# `feature_names` is required, ordered, and exact-width. Names may be Strings
# or Symbols but must be distinct ASCII identifiers; the normalized names and
# their indices are also written into the source header. The checksum covers a
# domain tag, schema version, count, index, byte size, and name for every
# feature, so reordering or renaming a feature changes it deterministically on
# both engines.
#
# Classification labels must be Integer or finite Float values. Thresholds and
# Float labels use Tungsten's `~` f64 literal with Float#to_s's round-trip
# representation; the exporter verifies the text parses back to the identical
# f64 before emitting it. Non-numeric labels are refused instead of being
# quoted into a Wassat router accidentally.

+ DecisionTreeExport
  # Increment when the generated function contract or checksum payload
  # changes. It is deliberately part of both the artifact and the source.
  -> .schema_version
    1

  # A small cross-engine checksum whose intermediate product stays inside the
  # interpreter's 48-bit integer range:
  #
  #     h' = (131*h + byte) mod (2^31 - 1)
  #
  # This is an ABI drift guard, not a cryptographic integrity primitive.
  -> .schema_checksum(feature_names)
    payload = "koala-decision-tree-source|" + DecisionTreeExport.schema_version.to_s + "|" + feature_names.size.to_s + "|"
    i = 0
    while i < feature_names.size
      name = feature_names[i]
      payload += i.to_s + ":" + name.bytes.size.to_s + ":" + name + "|"
      i += 1
    h = 216613
    bytes = payload.bytes
    i = 0
    while i < bytes.size
      h = (h * 131 + bytes[i]) % 2147483647
      i += 1
    h

  -> .ascii_letter?(byte)
    (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)

  -> .ascii_lower?(byte)
    byte >= 97 && byte <= 122

  -> .ascii_digit?(byte)
    byte >= 48 && byte <= 57

  # Feature names are metadata rather than source identifiers, but keeping
  # them identifier-shaped makes the generated one-line schema unambiguous
  # and prevents a name from injecting source through the comment.
  -> .feature_name?(name)
    out = false
    if name != nil && name.is_a?(String) && name.bytes.size > 0
      bytes = name.bytes
      first = bytes[0]
      ok = DecisionTreeExport.ascii_letter?(first) || first == 95
      i = 1
      while i < bytes.size
        byte = bytes[i]
        ok = false if !DecisionTreeExport.ascii_letter?(byte) && !DecisionTreeExport.ascii_digit?(byte) && byte != 95
        i += 1
      out = ok
    out

  -> .keyword?(name)
    ["if", "else", "elsif", "while", "until", "with", "case", "when",
     "module", "return", "break", "next", "continue", "true", "false",
     "nil", "begin", "rescue", "ensure", "raise", "use", "self", "super",
     "yield", "unless", "trait", "always", "redo", "retry", "in", "fn",
     "is", "as", "and", "or", "not", "xor"].include?(name)

  # Top-level Tungsten function names are kept to lowercase ASCII snake-case.
  # This is intentionally narrower than every spelling the parser may accept:
  # the output has to compile equally under the interpreter, native compiler,
  # and Wassat's typed source.
  -> .function_name?(name)
    out = false
    if name != nil && name.is_a?(String) && name.bytes.size > 0
      bytes = name.bytes
      first = bytes[0]
      ok = DecisionTreeExport.ascii_lower?(first) || first == 95
      i = 1
      while i < bytes.size
        byte = bytes[i]
        ok = false if !DecisionTreeExport.ascii_lower?(byte) && !DecisionTreeExport.ascii_digit?(byte) && byte != 95
        i += 1
      ok = false if DecisionTreeExport.keyword?(name)
      out = ok
    out

  -> .normalize_feature_names(feature_names, expected_size)
    out = nil
    if feature_names != nil && feature_names.is_a?(Array) && feature_names.size == expected_size
      names = []
      ok = true
      i = 0
      while i < feature_names.size
        given = feature_names[i]
        text = nil
        text = given.to_s if given != nil && (given.is_a?(String) || given.is_a?(Symbol))
        ok = false if !DecisionTreeExport.feature_name?(text)
        ok = false if text != nil && names.include?(text)
        names.push(text) if ok
        i += 1
      out = names if ok && names.size == expected_size
    out

  -> .normalize_function_name(function_name)
    given = function_name
    given = "koala_tree_predict" if given == nil
    text = nil
    text = given.to_s if given.is_a?(String) || given.is_a?(Symbol)
    out = nil
    out = text if DecisionTreeExport.function_name?(text)
    out

  # Exact source literal for a numeric classification label. Integer arms are
  # the normal Wassat case; finite f64 labels are supported without rounding.
  -> .prediction_literal(value)
    out = nil
    if value != nil && value.is_a?(Integer)
      out = value.to_s
    elsif value != nil && value.is_a?(Float)
      out = DecisionTreeExport.float_literal(value)
    out

  # Float#to_s is specified to produce a round-trip f64 spelling. Verify that
  # contract here anyway so a runtime regression fails the export rather than
  # silently moving a tree boundary.
  -> .float_literal(value)
    out = nil
    finite = value != nil && value.is_a?(Float)
    finite = value == value && value - value == 0.to_f if finite
    if finite
      text = value.to_s
      # The interpreter accepts `~6`, but native lowering would emit the
      # invalid LLVM token `double 6`. Force a decimal point when the
      # round-trip spelling has neither one nor an exponent.
      if !text.include?(".") && !text.include?("e") && !text.include?("E")
        text += ".0"
      out = "~" + text if text.to_f == value
    out

  # Append one expression-shaped subtree. The generated function uses each
  # branch's final expression as its return value, so it needs no Koala
  # classes, hashes, recursion, or allocations at prediction time.
  -> .render_node(node, feature_count, indent, lines)
    # Hash's generic runtime facade does not currently satisfy is_a?(Hash)
    # under the native engine even though class_name/type is "Hash".
    ok = node != nil && type(node) == "Hash"
    if ok && node[:leaf] == true
      literal = DecisionTreeExport.prediction_literal(node[:prediction])
      ok = false if literal == nil
      lines.push(indent + literal) if ok
    elsif ok && node[:leaf] == false
      feature = node[:feature]
      threshold = node[:threshold]
      threshold_literal = nil
      threshold_literal = DecisionTreeExport.float_literal(threshold) if threshold != nil
      ok = false if feature == nil || !feature.is_a?(Integer)
      ok = false if feature != nil && (feature < 0 || feature >= feature_count)
      ok = false if threshold_literal == nil
      ok = false if node[:left] == nil || node[:right] == nil
      if ok
        lines.push(indent + "if features\[" + feature.to_s + "\].to_f <= " + threshold_literal)
        ok = DecisionTreeExport.render_node(node[:left], feature_count, indent + "  ", lines)
      if ok
        lines.push(indent + "else")
        ok = DecisionTreeExport.render_node(node[:right], feature_count, indent + "  ", lines)
    else
      ok = false
    ok

  # Return a self-describing artifact hash, or nil for an unfitted/wrong model,
  # an invalid schema/function name, a malformed tree, a non-finite threshold,
  # or a non-numeric class prediction.
  -> .export(model, feature_names, function_name = nil)
    ok = model != nil && model.is_a?(DecisionTreeClassifier)
    ok = model.fitted? if ok
    ok = model.tree != nil && model.n_features != nil if ok
    names = nil
    names = DecisionTreeExport.normalize_feature_names(feature_names, model.n_features) if ok
    ok = names != nil if ok
    name = nil
    name = DecisionTreeExport.normalize_function_name(function_name) if ok
    ok = name != nil if ok
    out = nil
    if ok
      version = DecisionTreeExport.schema_version
      checksum = DecisionTreeExport.schema_checksum(names)
      count = names.size
      lines = []
      lines.push("# Generated by Koala DecisionTreeExport; do not edit.")
      lines.push("# schema-version: " + version.to_s)
      lines.push("# schema-checksum: " + checksum.to_s)
      fields = []
      i = 0
      while i < count
        fields.push(i.to_s + "=" + names[i])
        i += 1
      lines.push("# feature-order: " + fields.join(", "))
      lines.push("")
      lines.push("-> " + name + "_schema_version")
      lines.push("  " + version.to_s)
      lines.push("")
      lines.push("-> " + name + "_schema_checksum")
      lines.push("  " + checksum.to_s)
      lines.push("")
      lines.push("-> " + name + "_feature_count")
      lines.push("  " + count.to_s)
      lines.push("")
      lines.push("-> " + name + "(features, feature_schema_checksum)")
      lines.push("  raise \"" + name + ": feature schema checksum mismatch\" if feature_schema_checksum != " + checksum.to_s)
      feature_word = "features"
      feature_word = "feature" if count == 1
      lines.push("  raise \"" + name + ": expected " + count.to_s + " " + feature_word + "\" if features.size != " + count.to_s)
      rendered = DecisionTreeExport.render_node(model.tree, count, "  ", lines)
      if rendered
        source = lines.join("\n") + "\n"
        out = {
          format: "koala-decision-tree-source",
          schema_version: version,
          schema_checksum: checksum,
          feature_names: names,
          function_name: name,
          source: source
        }
    out

  # Convenience for callers that only need the text. The artifact form above
  # is preferred at deployment boundaries because it keeps the checksum and
  # ordered names available without reparsing comments.
  -> .source(model, feature_names, function_name = nil)
    artifact = DecisionTreeExport.export(model, feature_names, function_name)
    out = nil
    out = artifact[:source] if artifact != nil
    out
