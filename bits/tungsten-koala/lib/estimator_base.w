# Estimator — the shared contract every koala estimator answers, plus the
# ONE definition of every accepted input shape.
#
# This is the neutral home the estimators lean on. Before it, coercion lived
# on a concrete sibling (LinearRegression.feature_rows), so KNNClassifier,
# LogisticRegression, GaussianNB, KMeans and CrossValidation all structurally
# depended on the linear model — backwards. They now all call
# Estimator.feature_rows / Estimator.target_values;
# LinearRegression.feature_rows / .target_values survive as delegating
# aliases so nothing outside the bit breaks.
#
# --- The contract ---
#
# Every estimator conforms to `Estimable` plus exactly one of
# `SupervisedEstimator` / `UnsupervisedEstimator`:
#
#     + LinearRegression
#       is Estimable
#       is SupervisedEstimator
#
#   Estimable                — fitted? / predict(x) / supervised? /
#                              params / with_params(overrides) /
#                              estimator_name
#   SupervisedEstimator      — fit(x, y) / score(x, y)
#   UnsupervisedEstimator    — fit(x)    / score(x)
#
# The split exists because fit's ARITY genuinely differs: KMeans is
# unsupervised (fit(x) / score(x)); the other four are supervised
# (fit(x, y) / score(x, y)). `supervised?` makes that difference
# machine-readable, so generic tooling — cross-validation, and the grid
# search this contract exists to enable — can dispatch safely instead of
# guessing. Estimator.fit_model / .score_model do exactly that dispatch.
#
# MECHANISM HONESTY (verified by probe on BOTH engines before adopting):
#   * `trait T` + `is T` parses, compiles and runs on both engines, and a
#     class may carry SEVERAL `is` lines. It is a DECLARATION, not an
#     enforcement — a class naming a trait it does not satisfy still
#     compiles — so spec/estimator_spec.w asserts the conformance directly
#     (every estimator answers every contract method, via respond_to?).
#   * `with OtherTrait` trait COMPOSITION does NOT run on the interpreter
#     ("Undefined variable or method 'with'"), so the three traits above are
#     FLAT and a class names each one it satisfies.
#   * `type(obj)` on a user instance returns the class name compiled but
#     "Hash" interpreted — do not use it to identify an estimator. That is
#     why the contract carries `estimator_name`.
#   * Hash `to_s` key ORDER differs between engines, so `params` is compared
#     per key (params[:alpha]), never as a whole-hash string.
#
# --- Hyperparameters ---
#
#     model.params                      # => { alpha: 12 }  (hyperparameters only)
#     model.with_params({ alpha: 3 })   # => a NEW, UNFITTED LinearRegression
#
# `params` reports only what the constructor takes — the knobs a search
# varies — never learned state (coefficients, centroids). `with_params`
# CLONES: it returns a fresh unfitted instance with the overrides applied
# and leaves the receiver untouched, so a search can fan out from one
# prototype without aliasing. Unmentioned keys carry over, so
# `m.with_params(m.params)` round-trips. An override whose value is nil
# still applies (KMeans's seed can be cleared), because the lookup tests
# key presence, not the value.
#
# --- Tunable: the hyperparameter half, on its own ---
#
# That `params` / `with_params` pair is exactly what Pipeline's tunable
# surface and GridSearch reach for, and it is meaningful for objects that
# are NOT estimators: Scaler, Imputer and Encoder carry real
# hyperparameters (kind / strategy / columns / fill_value) but have no
# predict and no fit ARITY to declare, so `Estimable` would be a lie for
# them. `Tunable` is that pair alone, and the three transformers declare
# it — which is what puts "scale.kind" and "impute.strategy" into a
# pipeline's search space with no change to lib/pipeline.w.
#
# Estimable RESTATES the two methods rather than composing Tunable: trait
# composition (`with`) does not run on the interpreter, so the traits here
# are flat by construction (see MECHANISM HONESTY above). Every Estimable
# is therefore a Tunable in behaviour, and Pipeline.tunable? — which tests
# the two METHODS, never a trait — accepts both without knowing either
# name.
#
# LEARNED STATE IS NOT `params`. A transformer that also wants to expose
# what it learned at fit time answers `learned_params` (Scaler's
# [name, mean, std] triples, Imputer's [name, fill] pairs). The two names
# are kept apart deliberately: `params` is what you SET, `learned_params`
# is what fit DISCOVERED, and collapsing them would let fitted state leak
# into a search space that cannot rebuild it.
+ Estimator
  # --- Input coercion (every accepted shape, one place) ---

  # x as plain feature rows: a Matrix or DataFrame goes through its
  # to_matrix (numeric columns only for a frame — nil when it has
  # none), an array of arrays is taken as-is, and a flat array becomes
  # one single-feature row per value.
  -> .feature_rows(x)
    out = nil
    if type(x) == "Array"
      if x.size == 0
        out = []
      else
        if type(x[0]) == "Array"
          out = x
        else
          rows = []
          x.each -> (v)
            rows.push([v])
          out = rows
    else
      m = x.to_matrix
      out = m.to_a if m != nil
    out

  # x as a DataFrame — the TRANSFORMER-side twin of feature_rows, and
  # the reason koala's transformers work inside generic tooling at all.
  #
  # Scaler / Imputer / Encoder are written against a frame (they address
  # columns BY NAME), but CrossValidation — and therefore GridSearch —
  # coerces x to plain row arrays before the model ever sees it, so a
  # Pipeline with a Scaler step used to die on `column_names` for an
  # Array the moment it was cross-validated. frame closes that: anything
  # feature_rows accepts (a Matrix, an array of row arrays, a flat
  # single-feature array) becomes a frame whose columns are named
  # x0, x1, … positionally, and a DataFrame passes straight through
  # untouched — detected by BEHAVIOUR (respond_to? "column_names", the
  # string form, the only one that answers on both engines) because
  # type(obj) on an instance returns "Hash" interpreted and cannot tell
  # a frame from a matrix. nil in, nil out.
  -> .frame(x)
    out = nil
    if x != nil
      if x.respond_to?("column_names")
        out = x
      else
        rows = Estimator.feature_rows(x)
        if rows != nil
          width = 0
          width = rows[0].size if rows.size > 0
          pairs = []
          width.times -> (c)
            vals = []
            rows.each -> (r)
              vals.push(r[c])
            pairs.push(["x" + c.to_s, vals])
          out = DataFrame.new(pairs)
    out

  # y as a plain array of target values: Series / Vector -> to_a, a
  # plain array is taken as-is.
  -> .target_values(y)
    out = nil
    if type(y) == "Array"
      out = y
    else
      out = y.to_a
    out

  # --- Hyperparameter plumbing ---

  # overrides[key] when the hash carries that key, else fallback. A nil
  # overrides hash, or a key it does not carry, keeps the fallback; a key
  # present with a nil VALUE overrides to nil (that is how KMeans's seed
  # gets cleared). Every estimator's with_params is built from this.
  -> .opt(overrides, key, fallback)
    out = fallback
    out = overrides[key] if overrides != nil && overrides.key?(key)
    out

  # --- Arity-safe dispatch (what `supervised?` is FOR) ---

  # Fit `model` without knowing whether it is supervised: supervised
  # estimators get fit(rows, yvals), unsupervised ones get fit(rows).
  # Returns whatever fit returns (the model, or nil when unfittable).
  -> .fit_model(model, rows, yvals)
    out = nil
    if model.supervised?
      out = model.fit(rows, yvals)
    else
      out = model.fit(rows)
    out

  # Score `model` without knowing whether it is supervised; the mirror of
  # fit_model. nil before a successful fit, as ever.
  -> .score_model(model, rows, yvals)
    out = nil
    if model.supervised?
      out = model.score(rows, yvals)
    else
      out = model.score(rows)
    out

# The hyperparameter half, on its own: what a search needs and nothing
# more. Every Estimable answers it too (the two methods are restated
# below — the traits here are flat); koala's transformers answer ONLY
# this, which is exactly what makes them tunable inside a Pipeline
# without pretending to be estimators.
trait Tunable
  -> params
  -> with_params(overrides)

# The core every estimator answers, supervised or not.
trait Estimable
  -> fitted?
  -> predict(x)
  -> supervised?
  -> params
  -> with_params(overrides)
  -> estimator_name

# Learns from features AND labels: fit(x, y) / score(x, y).
trait SupervisedEstimator
  -> fit(x, y)
  -> score(x, y)

# Learns from features alone: fit(x) / score(x).
trait UnsupervisedEstimator
  -> fit(x)
  -> score(x)
