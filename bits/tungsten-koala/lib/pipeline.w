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
# --- Named steps ---
#
# A step may be given as a [name, step] PAIR, which is what makes the
# chain addressable by meaning rather than by position:
#
#     pipe = Pipeline.new([
#       [:scale, Scaler.new(:standard)],
#       [:model, LinearRegression.new]
#     ])
#     pipe.step(:scale)      # => the Scaler       (pipe[0] still works)
#     pipe.names             # => ["scale", "model"]
#     pipe.has_step?(:model) # => true
#
# The bare-array form keeps working unchanged and gets names derived
# for it: a step that answers `estimator_name` is named after it,
# downcased (sklearn's make_pipeline convention — LinearRegression
# becomes "linearregression"); anything else — the plain transformers,
# which carry no name of their own on either engine — is named for its
# POSITION, "step_0", "step_1", so the auto name mirrors pipe[i].
# Repeats are de-duplicated by suffix, so two LinearRegressions become
# "linearregression" and "linearregression_2" and every name in a
# pipeline is unique. Names are normalized to STRINGS (:scale and
# "scale" address the same step) — one vocabulary, because the params
# keys below are strings too.
#
# --- The Estimable contract (see lib/estimator_base.w) ---
#
# A Pipeline answers `fitted?` / `predict` / `supervised?` / `params` /
# `with_params` / `estimator_name`, so generic tooling — cross-validation,
# grid search — drives a whole chain through exactly the interface it uses
# for a bare estimator, without knowing pipelines exist:
#
#     pipe.params
#     # => { "model.alpha" => 0 }
#     tuned = pipe.with_params({ "model.alpha" => 10 })   # fresh + UNFITTED
#
# SEPARATOR — a step's parameters are addressed "<step>.<param>", the
# two joined by a DOT. The dot reads as what it is (attribute access on
# a named step), it cannot occur inside a param name, and it NESTS for
# free: a pipeline inside a pipeline flattens to "inner.model.alpha"
# because each level only prefixes its own step name. (scikit-learn
# spells this "__" because a Python keyword argument cannot contain a
# dot; a Tungsten hash key is an ordinary string, so the readable
# separator is available and is the one used here.)
#
# THE TUNABLE SURFACE is exactly the steps that answer BOTH `params` and
# `with_params` — the Estimable half of the contract. That rule is not a
# convenience: `params` and `with_params` have to round-trip
# (`p.with_params(p.params)` reproduces p), so reporting a key that
# with_params could not apply would break the contract for every caller.
# It also excludes any step that cannot take part — a step answering
# neither half is carried by reference and contributes no keys. koala's
# bundled transformers DO take part (Scaler / Imputer / Encoder are
# `is Tunable`), so a Scaler + LinearRegression chain's surface is
# { "scale.kind" => ..., "scale.columns" => ..., "model.alpha" => ... }
# and a grid search tunes the scaling alongside the model. Nothing here
# was special-cased to make that happen: the rule was always stated in
# terms of the two METHODS, never a class, so the transformers joined
# the surface with no change to this file. What fit LEARNED answers to
# `learned_params`, which is deliberately not `params`.
#
# with_params returns a FRESH, UNFITTED Pipeline and leaves the receiver
# untouched, so a search fans out from one prototype without aliasing.
# Every tunable step is rebuilt through its OWN with_params (a fresh
# unfitted step, even where no key targeted it); a step outside the
# contract cannot be cloned generically and is carried over by
# reference. That is safe for the serial fit-then-use a search does —
# the new pipeline is unfitted and Pipeline#fit re-fits every step from
# scratch — but two clones must not be fitted and used interleaved.
#
# `supervised?` delegates to the TAIL step (false for a
# transformer-only chain, and for a tail that answers no supervised?),
# which is what tells generic tooling the fit ARITY to use. A Pipeline
# declares only `is Estimable` and not one of the two arity traits
# precisely because that arity is its tail's to decide at runtime, not
# a property of the class — Estimator.fit_model / .score_model read
# supervised? and dispatch. Today the tail estimator must be a
# SUPERVISED one: fitting without y transforms through every step,
# which an unsupervised tail has no transform for.
#
# NOTE: locals are hoisted from ivars before any `-> (x)` block — the
# interpreter cannot resolve @ivars from a block body — and methods
# containing closures avoid early `return`. Array `+` concatenation is
# avoided (it is unsupported); arrays are built with push. respond_to?
# is passed a STRING ("with_params"), the only form that answers on
# both engines.
+ Pipeline
  is Estimable

  ro :steps   # the steps themselves, in fit order
  ro :names   # their names, positionally parallel to steps

  # steps is an array whose entries are each either a bare step or a
  # [name, step] pair; the two forms mix freely in one chain.
  -> new(steps)
    entries = steps
    plain = []
    named = []
    i = 0
    entries.each -> (entry)
      plain.push(Pipeline.entry_step(entry))
      named.push(Pipeline.unique_name(named, Pipeline.entry_base(entry, i), 1))
      i += 1
    @steps = plain
    @names = named
    @fitted = false
    @has_estimator = false

  -> fitted?
    @fitted

  -> size
    @steps.size

  # The i-th step (fit order).
  -> [](i)
    @steps[i]

  # The step called `name` — symbol or string, both address the same
  # step — or nil when the pipeline carries no such step.
  -> step(name)
    step_names = @names
    all = @steps
    key = name.to_s
    out = nil
    i = 0
    step_names.each -> (n)
      out = all[i] if n == key
      i += 1
    out

  -> has_step?(name)
    self.step(name) != nil

  # Fit every step, feeding each the previous step's transform output.
  # With y given, the LAST step is fitted as an estimator —
  # step.fit(current, y, sample_weight) — and fit returns nil (fitted?
  # stays false) when that estimator fit itself returns nil.
  #
  # SAMPLE WEIGHTS reach the ESTIMATOR TAIL only. The transformers are
  # fitted unweighted, which is a real limitation and stated rather than
  # hidden: a weighted Scaler would centre on the weighted mean and a
  # weighted Imputer would fill with the weighted mean, and neither
  # Scaler nor Imputer takes weights today (scikit-learn's StandardScaler
  # does; koala's does not yet). So on a weighted pipeline the scaling
  # statistics are those of the unweighted training rows, while the model
  # on top is genuinely weighted.
  -> fit(df, y = nil, sample_weight = nil)
    steps = @steps
    last = steps.size - 1
    current = df
    ok = true
    i = 0
    steps.each -> (step)
      if y != nil && i == last
        ok = false if step.fit(current, y, sample_weight) == nil
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
  # y defaults to nil so an unsupervised caller — Estimator.score_model
  # on a chain whose supervised? is false — reaches the same nil rather
  # than an arity error. sample_weight rides through to the tail.
  -> score(x, y = nil, sample_weight = nil)
    out = nil
    if @fitted && @has_estimator
      steps = @steps
      out = steps[steps.size - 1].score(self.transform_features(x), y, sample_weight)
    out

  # --- Estimable contract (see lib/estimator_base.w) ---

  -> estimator_name
    "Pipeline"

  # The fit arity is the TAIL's to decide — false for a chain that ends
  # in a transformer, or in a tail that answers no supervised?.
  -> supervised?
    steps = @steps
    out = false
    if steps.size > 0
      tail = steps[steps.size - 1]
      out = tail.supervised? if tail.respond_to?("supervised?")
    out

  # Weights are the TAIL's to honour, so this delegates exactly like
  # supervised? does — a Pipeline ending in a KNNClassifier says false,
  # and so does a transformer-only chain (there is nothing to weight).
  -> supports_sample_weight?
    steps = @steps
    out = false
    if steps.size > 0
      tail = steps[steps.size - 1]
      out = tail.supports_sample_weight? if tail.respond_to?("supports_sample_weight?")
    out

  # Every tunable step's hyperparameters, flattened and addressed
  # "<step>.<param>" — the whole chain's search space as one hash a
  # caller can read without knowing it holds a pipeline.
  -> params
    steps = @steps
    step_names = @names
    out = {}
    i = 0
    steps.each -> (step)
      if Pipeline.tunable?(step)
        prefix = step_names[i] + "."
        sp = step.params
        sp.keys.each -> (k)
          out[prefix + k.to_s] = sp[k]
      i += 1
    out

  # A NEW, UNFITTED Pipeline with `overrides` applied to the steps they
  # address; self is left untouched. Unmentioned keys carry over (each
  # step's own with_params does the carrying), so
  # with_params(params) round-trips, and a key naming no step or no
  # parameter of it is ignored rather than fatal.
  -> with_params(overrides)
    steps = @steps
    step_names = @names
    rebuilt = []
    i = 0
    steps.each -> (step)
      rebuilt.push([step_names[i], Pipeline.respec(step, step_names[i], overrides)])
      i += 1
    Pipeline.new(rebuilt)

  # --- Step plumbing (statics: callable from inside a block) ---

  # A [name, step] pair? Only a two-element Array counts — a step
  # object is never an Array on either engine.
  -> .pair?(entry)
    type(entry) == "Array" && entry.size == 2

  # The step an entry carries, pair or bare.
  -> .entry_step(entry)
    out = entry
    out = entry[1] if Pipeline.pair?(entry)
    out

  # The name an entry asks for, before de-duplication.
  -> .entry_base(entry, i)
    out = nil
    if Pipeline.pair?(entry)
      out = entry[0].to_s
    else
      out = Pipeline.auto_name(entry, i)
    out

  # The name a BARE step is given: its own estimator_name downcased
  # when it has one, else its position.
  -> .auto_name(step, i)
    out = "step_" + i.to_s
    out = step.estimator_name.downcase if step.respond_to?("estimator_name")
    out

  # `base`, or base_2 / base_3 / … — the first candidate `taken` does
  # not already hold. n is the suffix to try, counting from 1 (bare).
  -> .unique_name(taken, base, n)
    cand = base
    cand = base + "_" + n.to_s if n > 1
    out = cand
    out = Pipeline.unique_name(taken, base, n + 1) if taken.include?(cand)
    out

  # Does this step take part in the hyperparameter contract? BOTH
  # halves are required — see the header on why reporting a param the
  # step cannot rebuild would break the round-trip.
  -> .tunable?(step)
    step.respond_to?("params") && step.respond_to?("with_params")

  # One step, rebuilt from the overrides addressed to it. The lookup
  # walks the STEP's own parameter names — so nothing needs to parse a
  # dotted key back apart, and a nested pipeline recurses naturally on
  # its own (already dotted) keys.
  -> .respec(step, name, overrides)
    out = step
    if Pipeline.tunable?(step)
      prefix = name + "."
      sp = step.params
      local = {}
      sp.keys.each -> (k)
        full = prefix + k.to_s
        local[k] = overrides[full] if overrides != nil && overrides.key?(full)
      out = step.with_params(local)
    out
