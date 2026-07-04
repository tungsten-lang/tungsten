# Pipeline — composable ML pipelines
# Chain transformers, estimators, and custom steps into reproducible workflows.
#
#     pipe = Pipeline.new([
#       Imputer.new(strategy: :median),
#       Scaler.new(kind: :standard),
#       Encoder.new(:one_hot, columns: [:category]),
#       Estimator.new(:linear_regression)
#     ])
#     pipe.fit(train_df, target: :price)
#     predictions = pipe.predict(test_df)

in Tungsten:Koala

+ Pipeline
  ro :steps      # array of { name:, step: } hashes
  ro :fitted

  -> new(steps)
    @steps = steps.each_with_index.map -> (step, i)
      case step
      => Array -> { name: step[0], step: step[1] }
      => _     -> { name: step.class.name.downcase + "_[i]", step: step }
    @fitted = false

  # Fit the pipeline on training data.
  #
  #     pipe.fit(df, target: :price)
  -> fit(df, target: nil)
    current = df
    target_series = target ? df[target] : nil

    @steps.each_with_index -> (entry, i)
      step = entry[:step]
      is_last = i == @steps.size - 1

      case
      => step.respond_to?(:fit_transform) && !is_last
        current = step.fit_transform(current, target: target_series)
      => step.respond_to?(:fit)
        if is_last && step.respond_to?(:predict)
          step.fit(current, target_series)
        else
          step.fit(current)
          current = step.transform(current) unless is_last

    @fitted = true
    self

  # Transform data through all steps (excluding final estimator).
  -> transform(df)
    <! PipelineError, "Pipeline not fitted" unless @fitted
    current = df
    transformer_steps = if @steps.last[:step].respond_to?(:predict)
      @steps[0...-1]
    else
      @steps

    transformer_steps.each -> (entry)
      current = entry[:step].transform(current)
    current

  # Fit and transform in one step.
  -> fit_transform(df, target: nil)
    self.fit(df, target: target)
    self.transform(df)

  # Predict using the fitted pipeline.
  #
  #     predictions = pipe.predict(test_df)
  -> predict(df)
    <! PipelineError, "Pipeline not fitted" unless @fitted
    <! PipelineError, "Last step must be an estimator" unless @steps.last[:step].respond_to?(:predict)

    transformed = self.transform(df)
    @steps.last[:step].predict(transformed)

  # Score using the final estimator's scoring method.
  -> score(df, target)
    predictions = self.predict(df)
    @steps.last[:step].score(predictions, target)

  # Get a step by name or index.
  -> [](key)
    case key
    => Int    -> @steps[key][:step]
    => String -> @steps.find(-> (s) s[:name] == key)&.fetch(:step)
    => Symbol -> @steps.find(-> (s) s[:name] == key.to_s)&.fetch(:step)

  # Get fitted parameters from all steps.
  -> params
    @steps.map(-> (s) [s[:name], s[:step].respond_to?(:params) ? s[:step].params : {}]).to_h

  # Set parameters on steps.
  -> set_params(**step_params)
    step_params.each -> (step_name, params)
      step = self[step_name]
      step.set_params(**params) if step&.respond_to?(:set_params)
    self

  -> to_s
    step_names = @steps.map(-> (s) s[:name]).join(" → ")
    "Pipeline([step_names], fitted=[fitted])"

+ PipelineError < Error
