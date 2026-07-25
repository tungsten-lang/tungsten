# Heterogeneous column preprocessing.
#
# ColumnSelector is the small sequential primitive:
#
#     ColumnSelector.new([:age, :income])          # keep
#     ColumnSelector.new([:id], :drop)              # drop
#
# ColumnTransformer is sklearn's parallel composition pattern: each named
# transformer sees only its assigned columns, their outputs are concatenated
# in declaration order, and unassigned columns are dropped or passed through.
#
#     prep = ColumnTransformer.new([
#       [:numeric, Scaler.new(:standard), [:age, :income]],
#       [:category, Encoder.new(:one_hot), [:city, :plan]]
#     ], :drop)
#
#     model = Pipeline.new([prep, LogisticRegression.new])
#
# Output names default to "<branch>__<feature>" to prevent two branches from
# silently producing the same column. `verbose_feature_names = false` keeps
# raw names but rejects a collision. Unknown one-hot categories follow
# Encoder's established all-zero convention.
#
# Every branch may be a bundled transformer, `:passthrough`, or `:drop`.
# Supervised transformers (SelectKBest) receive y; weighted transformers
# (Scaler/Imputer) receive sample_weight. The ColumnTransformer validates a
# supplied weight vector once, then Pipeline.fit_transformer dispatches each
# branch through the arity it declares.

+ ColumnSelector
  is Tunable

  ro :columns
  ro :mode
  ro :input_names
  ro :output_names

  -> new(columns = nil, mode = :keep)
    @columns = columns
    @mode = mode.to_s
    @input_names = nil
    @output_names = nil
    @fitted = false

  -> fitted?
    @fitted

  -> supervised_transformer?
    false

  -> supports_sample_weight?
    false

  -> fit(df)
    @fitted = false
    @input_names = nil
    @output_names = nil
    frame = Estimator.frame(df)
    ok = frame != nil
    ok = frame.valid? if ok
    ok = ColumnTransformer.unique_names?(frame.column_names) if ok
    ok = @mode == "keep" || @mode == "drop" if ok
    ok = @columns == nil || type(@columns) == "Array" if ok
    wanted = []
    if ok
      wanted = frame.column_names if @columns == nil
      wanted = @columns if @columns != nil
      ok = ColumnTransformer.unique_names?(wanted)
      wanted.each -> (name)
        ok = false if frame.column_values(name) == nil
    names = []
    if ok
      if @mode == "keep"
        wanted.each -> (name)
          names.push(name)
      else
        frame.column_names.each -> (name)
          names.push(name) if !wanted.include?(name)
      ok = false if names.size == 0
    out = nil
    if ok
      @input_names = ColumnTransformer.copy_array(frame.column_names)
      @output_names = ColumnTransformer.copy_array(names)
      @fitted = true
      out = self
    out

  -> transform(df)
    out = nil
    if @fitted
      frame = Estimator.frame(df)
      ok = frame != nil
      ok = frame.valid? if ok
      ok = ColumnTransformer.same_names?(frame.column_names, @input_names) if ok
      out = frame.select_columns(@output_names) if ok
    out

  -> fit_transform(df)
    fitted = self.fit(df)
    out = nil
    out = self.transform(df) if fitted != nil
    out

  -> get_feature_names_out
    out = nil
    out = ColumnTransformer.copy_array(@output_names) if @fitted
    out

  -> params
    { columns: @columns, mode: @mode }

  -> with_params(overrides)
    ColumnSelector.new(
      Estimator.opt(overrides, :columns, @columns),
      Estimator.opt(overrides, :mode, @mode)
    )

  -> persist_name
    "ColumnSelector"

  -> to_state
    {
      columns: @columns,
      mode: @mode,
      input_names: @input_names,
      output_names: @output_names
    }

  -> .load_state(st)
    out = nil
    ok = st != nil && type(st) == "Hash"
    ok = st[:mode] != nil && st[:input_names] != nil && st[:output_names] != nil if ok
    ok = type(st[:input_names]) == "Array" && type(st[:output_names]) == "Array" if ok
    ok = ColumnTransformer.unique_names?(st[:input_names]) if ok
    ok = ColumnTransformer.unique_names?(st[:output_names]) if ok
    ok = st[:output_names].size > 0 if ok
    ok = st[:mode].to_s == "keep" || st[:mode].to_s == "drop" if ok
    if ok
      wanted = st[:columns]
      ok = wanted == nil || type(wanted) == "Array"
      wanted = st[:input_names] if ok && wanted == nil
      ok = ColumnTransformer.unique_names?(wanted) if ok
      if ok
        wanted.each -> (name)
          ok = false if !st[:input_names].include?(name)
      expected = []
      if ok
        if st[:mode].to_s == "keep"
          expected = ColumnTransformer.copy_array(wanted)
        else
          st[:input_names].each -> (name)
            expected.push(name) if !wanted.include?(name)
        ok = ColumnTransformer.same_names?(expected, st[:output_names])
    if ok
      model = ColumnSelector.new(st[:columns], st[:mode])
      out = model.restore_state(st)
    out

  -> restore_state(st)
    @input_names = st[:input_names]
    @output_names = st[:output_names]
    @fitted = true
    self

+ ColumnTransformer
  is Tunable

  ro :names
  ro :transformers
  ro :columns
  ro :remainder
  ro :verbose_feature_names
  ro :input_names
  ro :output_names

  # Each entry is [name, transformer, columns].
  -> new(entries, remainder = :drop, verbose_feature_names = true)
    @names = []
    @transformers = []
    @columns = []
    @spec_ok = type(entries) == "Array"
    if @spec_ok
      entries.each -> (entry)
        if type(entry) != "Array" || entry.size != 3
          @spec_ok = false
        else
          name = entry[0].to_s
          @spec_ok = false if name.size == 0
          @spec_ok = false if @names.include?(name)
          @names.push(name)
          @transformers.push(entry[1])
          @columns.push(entry[2])
    @remainder = remainder.to_s
    @verbose_feature_names = verbose_feature_names
    @input_names = nil
    @output_names = nil
    @branch_output_names = nil
    @remainder_names = nil
    @fitted = false

  -> fitted?
    @fitted

  -> valid_spec?
    @spec_ok

  # It CAN host a supervised branch, so the outer Pipeline must make y
  # available. Unsupervised branches simply ignore it.
  -> supervised_transformer?
    true

  # It accepts and validates weights, forwarding them only to branches that
  # declare support.
  -> supports_sample_weight?
    true

  -> named_transformer(name)
    key = name.to_s
    out = nil
    i = 0
    @names.each -> (candidate)
      out = @transformers[i] if candidate == key
      i += 1
    out

  -> .copy_array(values)
    out = []
    values.each -> (value)
      out.push(value)
    out

  -> .same_names?(left, right)
    ok = left != nil && right != nil
    ok = left.size == right.size if ok
    if ok
      i = 0
      while i < left.size
        ok = false if left[i] != right[i]
        i += 1
    ok

  -> .unique_names?(names)
    ok = names != nil && type(names) == "Array"
    seen = []
    if ok
      names.each -> (name)
        ok = false if seen.include?(name)
        seen.push(name)
    ok

  -> .valid_step?(step)
    out = false
    if step == :drop || step == :passthrough
      out = true
    else
      if step != nil
        out = step.respond_to?("fit") && step.respond_to?("transform")
        out = false if out && step.respond_to?("estimator_tail?") && step.estimator_tail?
        out = false if out && step.respond_to?("size") && step.size == 0
    out

  -> .prefixed_name(branch, feature, verbose)
    out = feature
    out = branch + "__" + feature.to_s if verbose
    out

  # All unassigned input names, in original order.
  -> .remainder_names(input_names, branch_columns)
    assigned = []
    branch_columns.each -> (cols)
      if type(cols) == "Array"
        cols.each -> (name)
          assigned.push(name) if !assigned.include?(name)
    out = []
    input_names.each -> (name)
      out.push(name) if !assigned.include?(name)
    out

  # Fit every branch and discover its stable output schema.
  -> fit(df, y = nil, sample_weight = nil)
    @fitted = false
    @input_names = nil
    @output_names = nil
    @branch_output_names = nil
    @remainder_names = nil
    frame = Estimator.frame(df)
    ok = @spec_ok && frame != nil
    ok = frame.valid? if ok
    ok = ColumnTransformer.unique_names?(frame.column_names) if ok
    ok = @remainder == "drop" || @remainder == "passthrough" if ok
    ok = type(@verbose_feature_names) == "Boolean" if ok
    wts = nil
    if ok && sample_weight != nil
      wts = Estimator.weight_values(sample_weight, frame.row_count)
      ok = false if wts == nil
    branch_outputs = []
    final_names = []
    if ok
      i = 0
      while i < @names.size
        branch = @names[i]
        step = @transformers[i]
        cols = @columns[i]
        ok = false if type(cols) != "Array" || cols.size == 0
        if type(cols) == "Array"
          cols.each -> (name)
            ok = false if frame.column_values(name) == nil
        ok = false if !ColumnTransformer.valid_step?(step)
        raw_names = []
        if ok && step != :drop
          selected = frame.select_columns(cols)
          transformed = selected
          if step != :passthrough
            fitted = Pipeline.fit_transformer(step, selected, y, wts)
            ok = false if fitted == nil
            transformed = step.transform(selected) if ok
          out_frame = nil
          out_frame = Estimator.frame(transformed) if transformed != nil
          ok = false if out_frame == nil
          ok = false if out_frame != nil && !out_frame.valid?
          ok = false if out_frame != nil && out_frame.row_count != frame.row_count
          if ok
            raw_names = ColumnTransformer.copy_array(out_frame.column_names)
            raw_names.each -> (feature)
              named = ColumnTransformer.prefixed_name(branch, feature, @verbose_feature_names)
              ok = false if final_names.include?(named)
              final_names.push(named)
        branch_outputs.push(raw_names)
        i += 1
      remainder_names = ColumnTransformer.remainder_names(frame.column_names, @columns)
      if ok && @remainder == "passthrough"
        remainder_names.each -> (feature)
          named = ColumnTransformer.prefixed_name("remainder", feature, @verbose_feature_names)
          ok = false if final_names.include?(named)
          final_names.push(named)
      ok = false if final_names.size == 0
    out = nil
    if ok
      @input_names = ColumnTransformer.copy_array(frame.column_names)
      @output_names = final_names
      @branch_output_names = branch_outputs
      @remainder_names = remainder_names
      @fitted = true
      out = self
    out

  # Apply the fitted branches and concatenate their columns.
  -> transform(df)
    out = nil
    if @fitted
      frame = Estimator.frame(df)
      ok = frame != nil
      ok = frame.valid? if ok
      ok = ColumnTransformer.same_names?(frame.column_names, @input_names) if ok
      pairs = []
      if ok
        i = 0
        while i < @names.size
          branch = @names[i]
          step = @transformers[i]
          cols = @columns[i]
          if step != :drop
            selected = frame.select_columns(cols)
            transformed = selected
            transformed = step.transform(selected) if step != :passthrough
            out_frame = nil
            out_frame = Estimator.frame(transformed) if transformed != nil
            ok = false if out_frame == nil
            ok = false if out_frame != nil && !out_frame.valid?
            ok = false if out_frame != nil && out_frame.row_count != frame.row_count
            expected = @branch_output_names[i]
            ok = false if out_frame != nil && !ColumnTransformer.same_names?(out_frame.column_names, expected)
            if ok
              expected.each -> (feature)
                named = ColumnTransformer.prefixed_name(branch, feature, @verbose_feature_names)
                pairs.push([named, out_frame.column_values(feature)])
          i += 1
        if ok && @remainder == "passthrough"
          @remainder_names.each -> (feature)
            named = ColumnTransformer.prefixed_name("remainder", feature, @verbose_feature_names)
            pairs.push([named, frame.column_values(feature)])
        result = DataFrame.new(pairs)
        ok = false if !ColumnTransformer.same_names?(result.column_names, @output_names)
        out = result if ok
    out

  -> fit_transform(df, y = nil, sample_weight = nil)
    fitted = self.fit(df, y, sample_weight)
    out = nil
    out = self.transform(df) if fitted != nil
    out

  -> get_feature_names_out
    out = nil
    out = ColumnTransformer.copy_array(@output_names) if @fitted
    out

  -> params
    out = {
      remainder: @remainder,
      verbose_feature_names: @verbose_feature_names
    }
    i = 0
    while i < @names.size
      step = @transformers[i]
      if step != :drop && step != :passthrough && Pipeline.tunable?(step)
        nested = step.params
        nested.keys.each -> (key)
          out[@names[i] + "." + key.to_s] = nested[key]
      i += 1
    out

  -> with_params(overrides)
    entries = []
    i = 0
    while i < @names.size
      step = @transformers[i]
      rebuilt = step
      if step != :drop && step != :passthrough
        rebuilt = Pipeline.respec(step, @names[i], overrides)
      entries.push([@names[i], rebuilt, @columns[i]])
      i += 1
    ColumnTransformer.new(
      entries,
      Estimator.opt(overrides, :remainder, @remainder),
      Estimator.opt(overrides, :verbose_feature_names, @verbose_feature_names)
    )

  -> persist_name
    "ColumnTransformer"

  -> to_state
    {
      names: @names,
      transformers: @transformers,
      columns: @columns,
      remainder: @remainder,
      verbose_feature_names: @verbose_feature_names,
      input_names: @input_names,
      output_names: @output_names,
      branch_output_names: @branch_output_names,
      remainder_names: @remainder_names
    }

  -> .load_state(st)
    out = nil
    ok = st != nil && type(st) == "Hash"
    ok = st[:names] != nil && st[:transformers] != nil && st[:columns] != nil if ok
    ok = st[:remainder] != nil && st[:verbose_feature_names] != nil if ok
    ok = st[:input_names] != nil && st[:output_names] != nil if ok
    ok = st[:branch_output_names] != nil && st[:remainder_names] != nil if ok
    if ok
      names = st[:names]
      steps = st[:transformers]
      cols = st[:columns]
      branches = st[:branch_output_names]
      ok = type(names) == "Array" && type(steps) == "Array" && type(cols) == "Array"
      ok = type(branches) == "Array" && type(st[:input_names]) == "Array" if ok
      ok = type(st[:output_names]) == "Array" && type(st[:remainder_names]) == "Array" if ok
      ok = names.size == steps.size && names.size == cols.size if ok
      ok = names.size == branches.size if ok
      ok = ColumnTransformer.unique_names?(names) if ok
      ok = ColumnTransformer.unique_names?(st[:input_names]) if ok
      ok = ColumnTransformer.unique_names?(st[:output_names]) if ok
      ok = st[:output_names].size > 0 if ok
      entries = []
      expected_final = []
      i = 0
      while ok && i < names.size
        ok = type(cols[i]) == "Array" && cols[i].size > 0
        ok = ColumnTransformer.unique_names?(cols[i]) if ok
        if ok
          cols[i].each -> (name)
            ok = false if !st[:input_names].include?(name)
        ok = type(branches[i]) == "Array" if ok
        ok = ColumnTransformer.unique_names?(branches[i]) if ok
        ok = ColumnTransformer.valid_step?(steps[i]) if ok
        if ok && steps[i] == :drop
          ok = branches[i].size == 0
        if ok && steps[i] == :passthrough
          ok = ColumnTransformer.same_names?(branches[i], cols[i])
        if ok && steps[i] != :drop
          branches[i].each -> (feature)
            named = ColumnTransformer.prefixed_name(names[i].to_s, feature, st[:verbose_feature_names])
            ok = false if expected_final.include?(named)
            expected_final.push(named)
        if ok && steps[i] != :drop && steps[i] != :passthrough
          ok = steps[i].respond_to?("fitted?") && steps[i].fitted?
        entries.push([names[i], steps[i], cols[i]]) if ok
        i += 1
      if ok
        model = ColumnTransformer.new(entries, st[:remainder], st[:verbose_feature_names])
        ok = model.valid_spec?
        ok = st[:remainder].to_s == "drop" || st[:remainder].to_s == "passthrough" if ok
        ok = type(st[:verbose_feature_names]) == "Boolean" if ok
        expected_remainder = ColumnTransformer.remainder_names(st[:input_names], cols)
        ok = ColumnTransformer.same_names?(expected_remainder, st[:remainder_names]) if ok
        if ok && st[:remainder].to_s == "passthrough"
          expected_remainder.each -> (feature)
            named = ColumnTransformer.prefixed_name("remainder", feature, st[:verbose_feature_names])
            ok = false if expected_final.include?(named)
            expected_final.push(named)
        ok = ColumnTransformer.same_names?(expected_final, st[:output_names]) if ok
        out = model.restore_state(st) if ok
    out

  -> restore_state(st)
    @input_names = st[:input_names]
    @output_names = st[:output_names]
    @branch_output_names = st[:branch_output_names]
    @remainder_names = st[:remainder_names]
    @fitted = true
    self
