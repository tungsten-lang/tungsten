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
# NOTE: locals are hoisted from ivars before any `-> (x)` block — the
# interpreter cannot resolve @ivars from a block body.
+ Pipeline
  ro :steps

  -> new(steps)
    @steps = steps
    @fitted = false

  -> fitted?
    @fitted

  -> size
    @steps.size

  # The i-th step (fit order).
  -> [](i)
    @steps[i]

  # Fit every step, feeding each the previous step's transform output.
  -> fit(df)
    steps = @steps
    current = df
    steps.each -> (step)
      step.fit(current)
      current = step.transform(current)
    @fitted = true
    self

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
