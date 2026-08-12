# PolynomialFeatures — generate polynomial and interaction features.
#
#     poly = PolynomialFeatures.new(2)
#     poly.fit_transform([[2, 3]])
#     # columns x0, x1, x0^2, x0*x1, x1^2
#
# Output ordering matches scikit-learn: total degree increases first and,
# within a degree, feature-index combinations are lexicographic. With
# interaction_only, a feature index may occur at most once in a monomial.
# include_bias prepends a constant column named "1".
#
# Input is any shape Estimator.frame accepts. Unlike DataFrame#to_matrix,
# this transformer does not silently discard non-numeric columns: every
# fitted feature must be numeric and non-nil because every one participates
# in the generated products. Run an Encoder / Imputer first when needed.
#
# fit learns only the input schema and the ordered monomials. Transform
# requires the same feature names in the same order. The transformer is
# Tunable, Pipeline-compatible, and exactly persistable.
+ PolynomialFeatures
  is Tunable

  ro :degree
  ro :include_bias
  ro :interaction_only

  -> new(degree = 2, include_bias = false, interaction_only = false)
    @degree = degree
    @include_bias = include_bias
    @interaction_only = interaction_only
    @fitted = false
    @feature_names = []
    @combinations = []
    @output_names = []

  -> fitted?
    @fitted

  -> supervised_transformer?
    false

  -> supports_sample_weight?
    false

  -> params
    { degree: @degree, include_bias: @include_bias, interaction_only: @interaction_only }

  -> with_params(overrides)
    PolynomialFeatures.new(
      Estimator.opt(overrides, :degree, @degree),
      Estimator.opt(overrides, :include_bias, @include_bias),
      Estimator.opt(overrides, :interaction_only, @interaction_only)
    )

  # Learn the input schema and monomial order. self on success, nil for
  # empty, ragged, non-numeric, nil-bearing, or invalid-degree input.
  -> fit(x)
    @fitted = false
    frame = Estimator.frame(x)
    ok = frame != nil
    ok = frame.respond_to?("valid?") if ok
    ok = frame.valid? if ok
    ok = type(@degree) == "Int" if ok
    ok = @degree >= 1 if ok
    ok = frame.row_count > 0 && frame.col_count > 0 if ok
    names = []
    if ok
      names = frame.column_names
      names.each -> (name)
        values = frame.column_values(name)
        ok = false if !Stats.numeric?(values)
        if values != nil
          values.each -> (v)
            ok = false if !PolynomialFeatures.numeric_cell?(v)
    out = nil
    if ok
      combos = PolynomialFeatures.make_combinations(names.size, @degree, @include_bias, @interaction_only)
      if combos.size > 0
        @feature_names = names
        @combinations = combos
        @output_names = PolynomialFeatures.names_for(names, combos)
        @fitted = true
        out = self
    out

  # Generate the learned columns for x, preserving row order.
  -> transform(x)
    out = nil
    if @fitted
      frame = Estimator.frame(x)
      ok = PolynomialFeatures.compatible_frame?(frame, @feature_names)
      if ok
        pairs = []
        ci = 0
        while ci < @combinations.size
          combo = @combinations[ci]
          vals = []
          ri = 0
          while ri < frame.row_count
            product = 1.to_f
            fi = 0
            while fi < combo.size
              col = frame.column_values(@feature_names[combo[fi]])
              product *= col[ri].to_f
              fi += 1
            vals.push(product)
            ri += 1
          pairs.push([@output_names[ci], vals])
          ci += 1
        out = DataFrame.new(pairs)
    out

  -> fit_transform(x)
    fitted = self.fit(x)
    out = nil
    out = self.transform(x) if fitted != nil
    out

  # The generated feature labels, in transform column order.
  -> feature_names_out
    out = nil
    out = @output_names if @fitted
    out

  -> learned_params
    out = nil
    out = { feature_names: @feature_names, combinations: @combinations, output_names: @output_names } if @fitted
    out

  # Degree-ordered combinations of feature indices. `previous` contains
  # exactly the combinations of degree d-1, so extending each prefix with
  # indices at or after its last index yields combinations-with-replacement
  # in lexicographic order. interaction_only advances past the last index.
  -> .make_combinations(width, degree, include_bias, interaction_only)
    out = []
    out.push([]) if include_bias
    previous = [[]]
    d = 1
    while d <= degree
      current = []
      pi = 0
      while pi < previous.size
        prefix = previous[pi]
        start = 0
        if prefix.size > 0
          start = prefix[prefix.size - 1]
          start += 1 if interaction_only
        j = start
        while j < width
          combo = []
          k = 0
          while k < prefix.size
            combo.push(prefix[k])
            k += 1
          combo.push(j)
          current.push(combo)
          j += 1
        pi += 1
      current.each -> (combo)
        out.push(combo)
      previous = current
      d += 1
    out

  -> .names_for(feature_names, combinations)
    out = []
    combinations.each -> (combo)
      label = "1"
      if combo.size > 0
        parts = []
        i = 0
        while i < feature_names.size
          count = 0
          j = 0
          while j < combo.size
            count += 1 if combo[j] == i
            j += 1
          if count == 1
            parts.push(feature_names[i].to_s)
          if count > 1
            parts.push(feature_names[i].to_s + "^" + count.to_s)
          i += 1
        label = parts.join("*")
      out.push(label)
    out

  -> .numeric_cell?(value)
    kind = type(value)
    kind == "Int" || kind == "Float"

  -> .compatible_frame?(frame, feature_names)
    ok = frame != nil
    ok = frame.respond_to?("valid?") if ok
    ok = frame.valid? if ok
    ok = frame.row_count > 0 if ok
    ok = frame.col_count == feature_names.size if ok
    if ok
      names = frame.column_names
      i = 0
      while i < feature_names.size
        ok = false if names[i] != feature_names[i]
        values = frame.column_values(names[i])
        ok = false if !Stats.numeric?(values)
        if values != nil
          j = 0
          while j < values.size
            ok = false if !PolynomialFeatures.numeric_cell?(values[j])
            j += 1
        i += 1
    ok

  -> persist_name
    "PolynomialFeatures"

  -> to_state
    { degree: @degree, include_bias: @include_bias, interaction_only: @interaction_only, feature_names: @feature_names, combinations: @combinations, output_names: @output_names }

  -> .load_state(state)
    out = nil
    ok = state != nil
    ok = state[:feature_names] != nil && state[:combinations] != nil && state[:output_names] != nil if ok
    if ok
      model = PolynomialFeatures.new(state[:degree], state[:include_bias], state[:interaction_only])
      out = model.restore_state(state)
    out

  -> restore_state(state)
    @feature_names = state[:feature_names]
    @combinations = state[:combinations]
    @output_names = state[:output_names]
    @fitted = true
    self
