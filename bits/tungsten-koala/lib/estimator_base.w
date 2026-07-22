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
