# Deterministic standalone Tungsten source export for fitted classification
# and regression forests.
#
#     artifact = RandomForestExport.export(
#       model, [:variables, :clauses], :select_solver
#     )
#
# The generated source has no Koala dependency. A classifier exports both
# `select_solver(features, checksum)` and
# `select_solver_predict_proba(features, checksum)`; a regressor exports the
# prediction function alone. Each tree is lowered to nested comparisons, so
# deployment needs no model loader, hashes, or recursive traversal.
#
# Classifier export preserves Koala's soft vote: every generated tree adds its
# leaf distribution directly into one shared totals array, the ensemble
# normalizes those totals after visiting trees in fitted order, and the
# prediction function uses the same first-class argmax tie break. Integer,
# finite Float, String, and Symbol class labels are supported; finite
# regression values are supported. Other labels are refused rather than
# embedded as executable source.
#
# As with DecisionTreeExport, callers must pin the returned schema checksum
# beside the independently maintained feature builder. It guards ordered
# feature names, not model integrity.
#
# `export_compact` / `source_compact` provide the same prediction contracts
# using concatenated immutable node arrays and one shared traversal function.
# They are the preferred deployment form for a nontrivial forest: source is
# smaller and instruction locality is better. `export` remains the direct,
# fully unrolled nested-source form for inspection and tiny ensembles.

+ RandomForestExport
  -> .schema_version
    1

  -> .schema_checksum(feature_names)
    payload = "koala-random-forest-source|" + RandomForestExport.schema_version.to_s + "|" + feature_names.size.to_s + "|"
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

  -> .compact_schema_checksum(feature_names)
    payload = "koala-random-forest-compact-source|" + RandomForestExport.schema_version.to_s + "|" + feature_names.size.to_s + "|"
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

  -> .normalize_function_name(function_name)
    given = function_name
    given = "koala_forest_predict" if given == nil
    DecisionTreeExport.normalize_function_name(given)

  # The same learned missing routing as DecisionTreeExport.render_node, but a
  # classification leaf adds its normalized class distribution into the
  # caller's one shared totals array. That avoids one allocation per tree and
  # one class loop per tree at inference.
  -> .render_probability_node(node, feature_count, class_count, indent, lines)
    ok = node != nil && type(node) == "Hash"
    if ok && node[:leaf] == true
      counts = node[:counts]
      weight = node[:weight]
      ok = false if counts == nil || weight == nil || weight.to_f <= 0.to_f
      ok = false if counts != nil && counts.size != class_count
      c = 0
      while ok && c < class_count
        probability = counts[c].to_f / weight.to_f
        literal = DecisionTreeExport.float_literal(probability)
        ok = false if literal == nil
        lines.push(indent + "totals\[" + c.to_s + "\] += " + literal) if ok
        c += 1
    elsif ok && node[:leaf] == false
      feature = node[:feature]
      threshold = node[:threshold]
      missing_left = node[:missing_left]
      threshold_literal = nil
      threshold_literal = DecisionTreeExport.float_literal(threshold) if threshold != nil
      ok = false if feature == nil || !feature.is_a?(Integer)
      ok = false if feature != nil && (feature < 0 || feature >= feature_count)
      ok = false if threshold_literal == nil
      ok = false if node[:left] == nil || node[:right] == nil
      if ok && missing_left == nil
        left_weight = node[:left][:weight]
        right_weight = node[:right][:weight]
        ok = false if left_weight == nil || right_weight == nil
        missing_left = left_weight > right_weight if ok
      elsif ok && missing_left != true && missing_left != false
        ok = false
      if ok
        cell = "features\[" + feature.to_s + "\]"
        condition = nil
        if missing_left
          condition = cell + " == nil || (type(" + cell + ") == \"Float\" && " + cell + " != " + cell + ") || " + cell + ".to_f <= " + threshold_literal
        else
          condition = cell + " != nil && (type(" + cell + ") != \"Float\" || " + cell + " == " + cell + ") && " + cell + ".to_f <= " + threshold_literal
        lines.push(indent + "if " + condition)
        ok = RandomForestExport.render_probability_node(
          node[:left], feature_count, class_count, indent + "  ", lines
        )
      if ok
        lines.push(indent + "else")
        ok = RandomForestExport.render_probability_node(
          node[:right], feature_count, class_count, indent + "  ", lines
        )
    else
      ok = false
    ok

  -> .append_header(lines, name, version, checksum, names, tree_count, kind)
    lines.push("# Generated by Koala RandomForestExport; do not edit.")
    lines.push("# schema-version: " + version.to_s)
    lines.push("# schema-checksum: " + checksum.to_s)
    lines.push("# forest-kind: " + kind)
    lines.push("# tree-count: " + tree_count.to_s)
    fields = []
    i = 0
    while i < names.size
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
    lines.push("  " + names.size.to_s)
    lines.push("")
    lines.push("-> " + name + "_tree_count")
    lines.push("  " + tree_count.to_s)
    lines.push("")

  -> .append_validation(lines, name, checksum, feature_count, indent)
    feature_word = "features"
    feature_word = "feature" if feature_count == 1
    lines.push(indent + "raise \"" + name + ": feature schema checksum mismatch\" if feature_schema_checksum != " + checksum.to_s)
    lines.push(indent + "raise \"" + name + ": expected " + feature_count.to_s + " " + feature_word + "\" if features.size != " + feature_count.to_s)
    lines.push(indent + "i = 0")
    lines.push(indent + "while i < features.size")
    lines.push(indent + "  cell = features\[i\]")
    lines.push(indent + "  kind = type(cell)")
    lines.push(indent + "  valid = cell == nil || kind == \"Int\" || (kind == \"Float\" && (cell != cell || cell - cell == 0.to_f))")
    lines.push(indent + "  return nil if !valid")
    lines.push(indent + "  i += 1")

  -> .export(model, feature_names, function_name = nil)
    ok = model != nil
    classifier = false
    regressor = false
    if ok
      classifier = model.is_a?(RandomForestClassifier)
      regressor = model.is_a?(RandomForestRegressor)
      ok = classifier || regressor
    ok = model.fitted? if ok
    ok = model.trees != nil && model.trees.size > 0 if ok
    ok = model.n_features != nil if ok
    names = nil
    names = DecisionTreeExport.normalize_feature_names(feature_names, model.n_features) if ok
    ok = names != nil if ok
    name = nil
    name = RandomForestExport.normalize_function_name(function_name) if ok
    ok = name != nil if ok

    class_literals = []
    if ok && classifier
      classes = model.classes
      ok = classes != nil && classes.size > 0
      c = 0
      while ok && c < classes.size
        literal = DecisionTreeExport.prediction_literal(classes[c])
        ok = false if literal == nil
        class_literals.push(literal) if ok
        c += 1

    out = nil
    if ok
      version = RandomForestExport.schema_version
      checksum = RandomForestExport.schema_checksum(names)
      tree_count = model.trees.size
      kind = "regressor"
      kind = "classifier" if classifier
      lines = []
      RandomForestExport.append_header(
        lines, name, version, checksum, names, tree_count, kind
      )

      rendered = true
      t = 0
      while rendered && t < tree_count
        helper = name + "_tree_" + t.to_s
        helper_args = "(features)"
        helper_args = "(features, totals)" if classifier
        lines.push("-> " + helper + helper_args)
        if classifier
          rendered = RandomForestExport.render_probability_node(
            model.trees[t], names.size, class_literals.size, "  ", lines
          )
        else
          rendered = DecisionTreeExport.render_node(
            model.trees[t], names.size, "  ", lines
          )
        lines.push("") if rendered
        t += 1

      if rendered && classifier
        probability_name = name + "_predict_proba"
        lines.push("-> " + probability_name + "(features, feature_schema_checksum)")
        RandomForestExport.append_validation(
          lines, probability_name, checksum, names.size, "  "
        )
        lines.push("  totals = []")
        lines.push("  " + class_literals.size.to_s + ".times -> (c)")
        lines.push("    totals.push(0.to_f)")
        t = 0
        while t < tree_count
          lines.push("  " + name + "_tree_" + t.to_s + "(features, totals)")
          t += 1
        lines.push("  divisor = " + DecisionTreeExport.float_literal(tree_count.to_f))
        lines.push("  c = 0")
        lines.push("  while c < totals.size")
        lines.push("    totals\[c\] = totals\[c\] / divisor")
        lines.push("    c += 1")
        lines.push("  totals")
        lines.push("")
        lines.push("-> " + name + "(features, feature_schema_checksum)")
        lines.push("  probabilities = " + probability_name + "(features, feature_schema_checksum)")
        lines.push("  return nil if probabilities == nil")
        lines.push("  best = 0")
        lines.push("  c = 1")
        lines.push("  while c < probabilities.size")
        lines.push("    best = c if probabilities\[c\] > probabilities\[best\]")
        lines.push("    c += 1")
        c = 0
        while c + 1 < class_literals.size
          lines.push("  return " + class_literals[c] + " if best == " + c.to_s)
          c += 1
        lines.push("  " + class_literals[class_literals.size - 1])
      elsif rendered
        lines.push("-> " + name + "(features, feature_schema_checksum)")
        RandomForestExport.append_validation(
          lines, name, checksum, names.size, "  "
        )
        lines.push("  total = 0.to_f")
        t = 0
        while t < tree_count
          lines.push("  total += " + name + "_tree_" + t.to_s + "(features)")
          t += 1
        lines.push("  total / " + DecisionTreeExport.float_literal(tree_count.to_f))

      if rendered
        source = lines.join("\n") + "\n"
        out = {
          format: "koala-random-forest-source",
          schema_version: version,
          schema_checksum: checksum,
          feature_names: names,
          function_name: name,
          forest_kind: kind,
          tree_count: tree_count,
          source: source
        }
    out

  -> .source(model, feature_names, function_name = nil)
    artifact = RandomForestExport.export(model, feature_names, function_name)
    out = nil
    out = artifact[:source] if artifact != nil
    out

  -> .integer_array_literal(values)
    texts = []
    values.each -> (value)
      texts.push(value.to_s)
    "\[" + texts.join(", ") + "\]"

  -> .boolean_array_literal(values)
    texts = []
    values.each -> (value)
      text = "false"
      text = "true" if value
      texts.push(text)
    "\[" + texts.join(", ") + "\]"

  -> .float_array_literal(values)
    texts = []
    ok = true
    values.each -> (value)
      literal = DecisionTreeExport.float_literal(value.to_f)
      ok = false if literal == nil
      texts.push(literal) if ok
    out = nil
    out = "\[" + texts.join(", ") + "\]" if ok
    out

  # Compact deployment form. Instead of repeating a full branch expression
  # for every node, all trees share one flat traversal function over immutable
  # source constants. Split nodes are nonnegative indices into the split
  # arrays; leaves are encoded as `-(leaf_index + 1)`, so no placeholder
  # thresholds/children are stored for leaves and no zero probability/value is
  # stored for splits. Roots and children use that same tagged index. A
  # classifier has one dense leaf-probability column per class; a regressor has
  # one dense leaf-value array.
  -> .export_compact(model, feature_names, function_name = nil)
    ok = model != nil
    classifier = false
    regressor = false
    if ok
      classifier = model.is_a?(RandomForestClassifier)
      regressor = model.is_a?(RandomForestRegressor)
      ok = classifier || regressor
    ok = model.fitted? if ok
    ok = model.trees != nil && model.trees.size > 0 if ok
    ok = model.n_features != nil if ok
    names = nil
    if ok
      names = DecisionTreeExport.normalize_feature_names(
        feature_names, model.n_features
      )
    ok = names != nil if ok
    name = nil
    name = RandomForestExport.normalize_function_name(function_name) if ok
    ok = name != nil if ok

    class_literals = []
    class_count = 0
    if ok && classifier
      classes = model.classes
      ok = classes != nil && classes.size > 0
      class_count = classes.size if ok
      c = 0
      while ok && c < class_count
        literal = DecisionTreeExport.prediction_literal(classes[c])
        ok = false if literal == nil
        class_literals.push(literal) if ok
        c += 1

    roots = []
    features = []
    thresholds = []
    missing_directions = []
    left_indices = []
    right_indices = []
    values = []
    leaf_count = 0
    probability_columns = []
    if classifier
      class_count.times -> (c)
        probability_columns.push([])

    t = 0
    while ok && t < model.trees.size
      tree = model.trees[t]
      # Run the strict recursive renderer as validation before consuming the
      # faster projection helper, so a malformed public tree returns nil just
      # as the unrolled exporter does.
      scratch = []
      if classifier
        ok = RandomForestExport.render_probability_node(
          tree, names.size, class_count, "", scratch
        )
      else
        ok = DecisionTreeExport.render_node(tree, names.size, "", scratch)
      if ok
        program = DecisionTree.prediction_program(tree, classifier)
        local_features = program[0]
        local_thresholds = program[1]
        local_missing = program[2]
        local_left = program[3]
        local_right = program[4]
        local_values = program[5]
        local_probabilities = program[6]
        node_map = []
        next_split = features.size
        i = 0
        while i < local_features.size
          feature = local_features[i]
          if feature >= 0
            node_map.push(next_split)
            next_split += 1
          else
            node_map.push(0 - leaf_count - 1)
            if classifier
              c = 0
              while c < class_count
                probability_columns[c].push(local_probabilities[i][c])
                c += 1
            else
              values.push(local_values[i].to_f)
            leaf_count += 1
          i += 1
        roots.push(node_map[0])
        i = 0
        while i < local_features.size
          feature = local_features[i]
          if feature >= 0
            features.push(feature)
            thresholds.push(local_thresholds[i])
            missing_directions.push(local_missing[i])
            left_indices.push(node_map[local_left[i]])
            right_indices.push(node_map[local_right[i]])
          i += 1
      t += 1

    out = nil
    if ok
      version = RandomForestExport.schema_version
      checksum = RandomForestExport.compact_schema_checksum(names)
      tree_count = model.trees.size
      kind = "regressor"
      kind = "classifier" if classifier
      prefix = name.upcase
      lines = []
      RandomForestExport.append_header(
        lines, name, version, checksum, names, tree_count, kind
      )
      lines.push("# compact-layout constants")
      lines.push(prefix + "_ROOTS = " + RandomForestExport.integer_array_literal(roots))
      lines.push(prefix + "_FEATURES = " + RandomForestExport.integer_array_literal(features))
      lines.push(prefix + "_THRESHOLDS = " + RandomForestExport.float_array_literal(thresholds))
      lines.push(prefix + "_MISSING_LEFT = " + RandomForestExport.boolean_array_literal(missing_directions))
      lines.push(prefix + "_LEFT = " + RandomForestExport.integer_array_literal(left_indices))
      lines.push(prefix + "_RIGHT = " + RandomForestExport.integer_array_literal(right_indices))
      if classifier
        c = 0
        while c < class_count
          lines.push(
            prefix + "_PROBABILITY_" + c.to_s + " = " +
            RandomForestExport.float_array_literal(probability_columns[c])
          )
          c += 1
      else
        lines.push(prefix + "_VALUES = " + RandomForestExport.float_array_literal(values))
      lines.push("")

      if classifier
        lines.push("-> " + name + "_accumulate(features, totals, root)")
      else
        lines.push("-> " + name + "_tree_value(features, root)")
      lines.push("  index = root")
      lines.push("  while index >= 0")
      lines.push("    value = features\[" + prefix + "_FEATURES\[index\]\]")
      lines.push("    if value == nil || (type(value) == \"Float\" && value != value)")
      lines.push("      go_left = " + prefix + "_MISSING_LEFT\[index\]")
      lines.push("    else")
      lines.push("      go_left = value.to_f <= " + prefix + "_THRESHOLDS\[index\]")
      lines.push("    if go_left")
      lines.push("      index = " + prefix + "_LEFT\[index\]")
      lines.push("    else")
      lines.push("      index = " + prefix + "_RIGHT\[index\]")
      lines.push("  leaf = 0 - index - 1")
      if classifier
        c = 0
        while c < class_count
          lines.push(
            "  totals\[" + c.to_s + "\] += " + prefix +
            "_PROBABILITY_" + c.to_s + "\[leaf\]"
          )
          c += 1
      else
        lines.push("  " + prefix + "_VALUES\[leaf\]")
      lines.push("")

      if classifier
        probability_name = name + "_predict_proba"
        lines.push("-> " + probability_name + "(features, feature_schema_checksum)")
        RandomForestExport.append_validation(
          lines, probability_name, checksum, names.size, "  "
        )
        lines.push("  totals = []")
        lines.push("  " + class_count.to_s + ".times -> (c)")
        lines.push("    totals.push(0.to_f)")
        lines.push("  t = 0")
        lines.push("  while t < " + prefix + "_ROOTS.size")
        lines.push(
          "    " + name + "_accumulate(features, totals, " +
          prefix + "_ROOTS\[t\])"
        )
        lines.push("    t += 1")
        lines.push("  divisor = " + DecisionTreeExport.float_literal(tree_count.to_f))
        lines.push("  c = 0")
        lines.push("  while c < totals.size")
        lines.push("    totals\[c\] = totals\[c\] / divisor")
        lines.push("    c += 1")
        lines.push("  totals")
        lines.push("")
        lines.push("-> " + name + "(features, feature_schema_checksum)")
        lines.push("  probabilities = " + probability_name + "(features, feature_schema_checksum)")
        lines.push("  return nil if probabilities == nil")
        lines.push("  best = 0")
        lines.push("  c = 1")
        lines.push("  while c < probabilities.size")
        lines.push("    best = c if probabilities\[c\] > probabilities\[best\]")
        lines.push("    c += 1")
        c = 0
        while c + 1 < class_count
          lines.push("  return " + class_literals[c] + " if best == " + c.to_s)
          c += 1
        lines.push("  " + class_literals[class_count - 1])
      else
        lines.push("-> " + name + "(features, feature_schema_checksum)")
        RandomForestExport.append_validation(
          lines, name, checksum, names.size, "  "
        )
        lines.push("  total = 0.to_f")
        lines.push("  t = 0")
        lines.push("  while t < " + prefix + "_ROOTS.size")
        lines.push(
          "    total += " + name + "_tree_value(features, " +
          prefix + "_ROOTS\[t\])"
        )
        lines.push("    t += 1")
        lines.push("  total / " + DecisionTreeExport.float_literal(tree_count.to_f))

      source = lines.join("\n") + "\n"
      out = {
        format: "koala-random-forest-compact-source",
        schema_version: version,
        schema_checksum: checksum,
        feature_names: names,
        function_name: name,
        forest_kind: kind,
        tree_count: tree_count,
        node_count: features.size + leaf_count,
        split_count: features.size,
        leaf_count: leaf_count,
        source: source
      }
    out

  -> .source_compact(model, feature_names, function_name = nil)
    artifact = RandomForestExport.export_compact(
      model, feature_names, function_name
    )
    out = nil
    out = artifact[:source] if artifact != nil
    out
