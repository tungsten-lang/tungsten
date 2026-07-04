# Scaler — feature scaling transformers
# Normalize or standardize numeric columns for ML pipelines.
#
#     scaler = Scaler.new(kind: :standard)
#     scaler.fit_transform(df)

in Tungsten:Koala

+ Scaler < Transformer
  ro :kind       # :standard, :min_max, :robust, :max_abs
  ro :columns    # nil = all numeric columns

  -> new(kind: :standard, columns: nil)
    super()
    @kind    = kind
    @columns = columns&.map(&:to_sym)
    @params  = {}

  -> fit(df, target: nil)
    cols = @columns || df.columns
    cols.each -> (col)
      values = df[col].to_a.reject(&:nil?)
      case @kind
      => :standard ->
        @params[col] = { mean: Stats.mean(values), std: Stats.std(values) }
      => :min_max ->
        @params[col] = { min: values.min, max: values.max }
      => :robust ->
        @params[col] = { median: Stats.median(values), iqr: Stats.percentile(values, 75) - Stats.percentile(values, 25) }
      => :max_abs ->
        @params[col] = { max_abs: values.map(&:abs).max }
    @fitted = true
    self

  -> transform(df)
    <! TransformerError, "Not fitted" unless @fitted
    result = df
    @params.each -> (col, p)
      result = result.transform(col) -> (v)
        return nil if v == nil
        case @kind
        => :standard -> (v - p[:mean]) / (p[:std] == 0 ? 1.0 : p[:std])
        => :min_max  ->
          range = p[:max] - p[:min]
          range == 0 ? 0.0 : (v - p[:min]) / range
        => :robust   ->
          iqr = p[:iqr] == 0 ? 1.0 : p[:iqr]
          (v - p[:median]) / iqr
        => :max_abs  -> v / (p[:max_abs] == 0 ? 1.0 : p[:max_abs])
    result

  # Reverse the scaling transformation.
  -> inverse_transform(df)
    <! TransformerError, "Not fitted" unless @fitted
    result = df
    @params.each -> (col, p)
      result = result.transform(col) -> (v)
        return nil if v == nil
        case @kind
        => :standard -> v * p[:std] + p[:mean]
        => :min_max  -> v * (p[:max] - p[:min]) + p[:min]
        => :robust   -> v * p[:iqr] + p[:median]
        => :max_abs  -> v * p[:max_abs]
    result

  -> params { kind: @kind, **@params }
