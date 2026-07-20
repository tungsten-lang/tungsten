# Pipeline — chain fit/transform steps into one transformer
#
#     pipe = Pipeline.new([
#       Imputer.new(:mean),
#       Scaler.new(:standard)
#     ])
#     out = pipe.fit_transform(train_df)
#     test_out = pipe.transform(test_df)     # replays TRAINING params
#
# fit runs the steps in order, fitting each on the output of the
# previous step's transform; transform replays the fitted chain on a
# new frame. A step is any object with fit(df) and transform(df) —
# Imputer, Scaler, Encoder, or your own — so a Pipeline nests inside
# another Pipeline. transform before fit returns nil, like the other
# transformers.
#
# The LAST step may instead be an estimator (fit(x, y) / predict /
# score — e.g. LinearRegression). Fit such a chain with the target:
#
#     pipe = Pipeline.new([Scaler.new(:standard), LinearRegression.new])
#     pipe.fit(train_df, y)         # estimator tail gets (features, y)
#     pipe.predict(test_df)         # transform all but last, then predict
#     pipe.score(test_df, y_test)   # ... then the estimator's R²
#
# predict/score return nil unless the pipeline was fitted WITH y; when
# the estimator's own fit fails (nil — e.g. collinear features), fit
# returns nil and fitted? stays false. transform stays a
# transformer-only affair — don't call it on an estimator-tailed chain.
#
# NOTE: locals are hoisted from ivars before any `-> (x)` block — the
# interpreter cannot resolve @ivars from a block body.
+ Pipeline
  ro :steps

  -> new(steps)
    @steps = steps
    @fitted = false
    @has_estimator = false

  -> fitted?
    @fitted

  -> size
    @steps.size

  # The i-th step (fit order).
  -> [](i)
    @steps[i]

  # Fit every step, feeding each the previous step's transform output.
  # With y given, the LAST step is fitted as an estimator —
  # step.fit(current, y) — and fit returns nil (fitted? stays false)
  # when that estimator fit itself returns nil.
  -> fit(df, y = nil)
    steps = @steps
    last = steps.size - 1
    current = df
    ok = true
    i = 0
    steps.each -> (step)
      if y != nil && i == last
        ok = false if step.fit(current, y) == nil
      else
        step.fit(current)
        current = step.transform(current)
      i += 1
    out = nil
    if ok
      @fitted = true
      @has_estimator = true if y != nil
      out = self
    out

  # Run df through every fitted step; nil before fit.
  -> transform(df)
    out = nil
    if @fitted
      steps = @steps
      current = df
      steps.each -> (step)
        current = step.transform(current)
      out = current
    out

  -> fit_transform(df)
    self.fit(df)
    self.transform(df)

  # x transformed through every step but the last — the estimator
  # tail's feature input.
  -> transform_features(x)
    steps = @steps
    last = steps.size - 1
    current = x
    i = 0
    steps.each -> (step)
      current = step.transform(current) if i < last
      i += 1
    current

  # Estimator predictions for x: transform through every step but the
  # last, then the last step's predict. nil unless fitted with y.
  -> predict(x)
    out = nil
    if @fitted && @has_estimator
      steps = @steps
      out = steps[steps.size - 1].predict(self.transform_features(x))
    out

  # The estimator tail's score on x against y; nil unless fitted with y.
  -> score(x, y)
    out = nil
    if @fitted && @has_estimator
      steps = @steps
      out = steps[steps.size - 1].score(self.transform_features(x), y)
    out
