# Imputer — missing value imputation
# Fill missing (nil) values using statistical strategies.
#
#     imp = Imputer.new(strategy: :median)
#     imp = Imputer.new(strategy: :constant, fill_value: 0)
#     imp = Imputer.new(strategy: :knn, k: 5)

in Tungsten:Koala

+ Imputer < Transformer
  ro :strategy   # :mean, :median, :most_frequent, :constant, :knn, :forward, :backward
  ro :columns

  -> new(strategy: :mean, columns: nil, fill_value: nil, k: 5)
    super()
    @strategy   = strategy
    @columns    = columns&.map(&:to_sym)
    @fill_value = fill_value
    @k          = k
    @fill_map   = {}

  -> fit(df, target: nil)
    cols = @columns || df.columns

    cols.each -> (col)
      values = df[col].to_a

      case @strategy
      => :mean ->
        clean = values.reject(&:nil?)
        @fill_map[col] = clean.empty? ? 0.0 : Stats.mean(clean)
      => :median ->
        clean = values.reject(&:nil?)
        @fill_map[col] = clean.empty? ? 0.0 : Stats.median(clean)
      => :most_frequent ->
        clean = values.reject(&:nil?)
        @fill_map[col] = clean.empty? ? nil : Stats.mode(clean).first
      => :constant ->
        @fill_map[col] = @fill_value
      => :knn ->
        @fill_map[col] = :knn  # handled at transform time
        @train_data = df       # store training data for KNN lookup
      => :forward, :backward ->
        @fill_map[col] = @strategy  # directional fill, no pre-computation

    @fitted = true
    self

  -> transform(df)
    <! TransformerError, "Not fitted" unless @fitted
    result = df

    @fill_map.each -> (col, fill)
      case fill
      => :knn ->
        result = self.knn_impute(result, col)
      => :forward ->
        result = self.forward_fill(result, col)
      => :backward ->
        result = self.backward_fill(result, col)
      => _ ->
        result = result.transform(col, -> (v) v || fill)

    result

  -> params { strategy: @strategy, fill_map: @fill_map }

  [private]

  -> knn_impute(df, col)
    values = df[col].to_a
    other_cols = df.columns.reject(-> (c) c == col)

    filled = values.each_with_index.map -> (v, i)
      next v unless v == nil

      # Find k nearest neighbors using other columns
      distances = df.row_count.times
        .reject(-> (j) j == i || df[col].to_a[j] == nil)
        .map -> (j)
          dist = other_cols.map -> (c)
            a = df[c].to_a[i]
            b = df[c].to_a[j]
            (a && b) ? (a - b) ** 2 : 0
          .sum
          [Math.sqrt(dist), j]
        .sort_by(&:first)
        .take(@k)

      neighbor_vals = distances.map(-> (_, j) df[col].to_a[j])
      neighbor_vals.sum.to_f / neighbor_vals.size

    df.assign(**{ col => filled })

  -> forward_fill(df, col)
    values = df[col].to_a
    last = nil
    filled = values.map -> (v)
      if v != nil
        last = v
        v
      else
        last
    df.assign(**{ col => filled })

  -> backward_fill(df, col)
    values = df[col].to_a.reverse
    last = nil
    filled = values.map -> (v)
      if v != nil
        last = v
        v
      else
        last
    df.assign(**{ col => filled.reverse })
