# Transformer — base trait and implementations for data transformation steps
# Transformers implement fit/transform/fit_transform for pipeline composition.

in Tungsten:Koala

# Trait that all transformers must implement.
trait Transformable
  -> fit(df, target: nil)
  -> transform(df)
  -> fit_transform(df, target: nil)
    self.fit(df, target: target)
    self.transform(df)

# Base transformer with common behavior.
+ Transformer
  use Transformable

  ro :fitted

  -> new
    @fitted = false

  -> fit(df, target: nil)
    @fitted = true
    self

  -> transform(df)
    <! TransformerError, "Not fitted" unless @fitted
    df

  -> fit_transform(df, target: nil)
    self.fit(df, target: target)
    self.transform(df)

  -> params {}
  -> set_params(**kw) kw.each(-> (k, v) self.instance_set(k, v)); self


# ColumnSelector — select or drop columns as a pipeline step.
#
#     ColumnSelector.new(keep: [:age, :salary])
#     ColumnSelector.new(drop: [:id, :timestamp])
+ ColumnSelector < Transformer
  -> new(keep: nil, drop: nil)
    super()
    @keep = keep&.map(&:to_sym)
    @drop = drop&.map(&:to_sym)

  -> transform(df)
    super(df)
    case
    => @keep -> df.select(*@keep)
    => @drop -> df.drop(*@drop)
    => _     -> df


# FunctionTransformer — wrap any function as a pipeline step.
#
#     FunctionTransformer.new(-> (df) df.assign(log_price: df[:price].map(&Math.log)))
+ FunctionTransformer < Transformer
  -> new(@func)
    super()

  -> transform(df)
    super(df)
    @func.call(df)


# PolynomialFeatures — generate polynomial and interaction features.
#
#     PolynomialFeatures.new(degree: 2, columns: [:x1, :x2])
+ PolynomialFeatures < Transformer
  -> new(degree: 2, columns: nil, interaction_only: false)
    super()
    @degree = degree
    @columns = columns&.map(&:to_sym)
    @interaction_only = interaction_only

  -> fit(df, target: nil)
    @columns ||= df.columns
    @fitted = true
    self

  -> transform(df)
    super(df)
    result = df
    cols = @columns

    if @degree >= 2
      cols.each -> (c)
        unless @interaction_only
          result = result.assign(**{ "[c]_sq".to_sym => df[c] ** 2 })

      # Interaction terms
      cols.combination(2).each -> (c1, c2)
        result = result.assign(**{ "[c1]_x_[c2]".to_sym => df[c1] * df[c2] })

    if @degree >= 3 && !@interaction_only
      cols.each -> (c)
        result = result.assign(**{ "[c]_cube".to_sym => df[c] ** 3 })

    result


+ TransformerError < Error
