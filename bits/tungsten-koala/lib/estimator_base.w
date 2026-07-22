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
#                              supports_sample_weight? /
#                              params / with_params(overrides) /
#                              estimator_name
#   SupervisedEstimator      — fit(x, y, sample_weight) /
#                              score(x, y, sample_weight)
#   UnsupervisedEstimator    — fit(x, sample_weight) /
#                              score(x, sample_weight)
#
# The split exists because fit's ARITY genuinely differs: KMeans is
# unsupervised (fit(x) / score(x)); the other four are supervised
# (fit(x, y) / score(x, y)). `supervised?` makes that difference
# machine-readable, so generic tooling — cross-validation, and the grid
# search this contract exists to enable — can dispatch safely instead of
# guessing. Estimator.fit_model / .score_model do exactly that dispatch.
#
# --- Sample weights ---
#
# `sample_weight` is an OPTIONAL TRAILING argument on fit and score, the
# same shape scikit-learn gives it (`fit(X, y, sample_weight=None)`):
#
#     model.fit(x, y)                  # unweighted — unchanged, forever
#     model.fit(x, y, [2, 1, 1])       # row 0 counts twice
#     model.score(x, y, [2, 1, 1])     # ... and scores that way too
#
# WHY A TRAILING ARGUMENT rather than a `fit_weighted` sibling or state
# carried on the estimator:
#
#   * Every existing `fit(x, y)` call keeps working BYTE-IDENTICALLY —
#     the default is nil, and nil takes the unweighted code path, not a
#     synthesized all-ones vector. Nothing that was exact becomes
#     approximate.
#   * It stays GENERICALLY DISPATCHABLE. Estimator.fit_model /
#     .score_model already own the supervised/unsupervised arity split,
#     so weights ride along as one more optional argument in the ONE
#     place that knows the arity — CrossValidation, GridSearch and
#     Pipeline thread them through with no new dispatch concept.
#   * A `fit_weighted` sibling would double the surface AND force
#     fit_model to grow a second dispatcher; weights held as state would
#     be a lie about `params` (weights are DATA, not a hyperparameter —
#     they are per-row and must be subset per CV fold, exactly like y).
#
# THE DEFINITION OF CORRECTNESS is that an INTEGER weight vector is
# indistinguishable from duplicating each row that many times:
#
#     model.fit([r0, r1, r2], [y0, y1, y2], [2, 1, 1])
#     model.fit([r0, r0, r1, r2], [y0, y0, y1, y2])   # the same model
#
# so a weight of 0 DROPS a row (Estimator.drop_zero_weights makes that
# structural rather than something each estimator re-derives) and a
# vector of all 1s is a no-op. Weights are validated in ONE place —
# Estimator.weight_values — and an unusable vector (wrong length, empty,
# negative, or summing to zero) makes fit return nil and leaves fitted?
# false: the bit's shape-error convention, never a raise.
#
# NOT EVERY ESTIMATOR CAN HONOUR THEM. koala follows scikit-learn:
# LinearRegression, LogisticRegression, GaussianNB, both trees and KMeans
# support sample_weight; KNNClassifier does NOT (neither does sklearn's
# KNeighborsClassifier — there is nowhere in a lazy learner's fit for a
# weight to go, and weighting the neighbour VOTE would be a different
# algorithm, sklearn's `weights=` hyperparameter). `supports_sample_weight?`
# makes that machine-readable exactly like `supervised?`, and a
# KNNClassifier handed weights returns nil from fit rather than silently
# ignoring them. Its `score` still accepts them — a weighted accuracy is
# well defined whatever produced the labels, and that is sklearn's split
# too (ClassifierMixin.score takes sample_weight for every classifier).
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

  # --- Sample weights: the ONE definition of a usable weight vector ---

  # `weights` validated for a sample of `n` rows: a plain array of n
  # non-negative floats, or nil — never a raise — when it cannot be used.
  # Unusable means a length that does not match n, an empty vector, a nil
  # or negative entry, or a total of zero (every row dropped, leaving
  # nothing to learn from). A ZERO entry alone is fine: it drops that one
  # row, which is what "duplicate this row zero times" means.
  #
  # Series / Vector / plain array all work — weights travel exactly like a
  # target does, through target_values.
  -> .weight_values(weights, n)
    out = nil
    vals = nil
    vals = Estimator.target_values(weights) if weights != nil
    if vals != nil && vals.size == n && n > 0
      ok = true
      floats = []
      total = 0.to_f
      vals.each -> (v)
        f = 0.to_f
        if v == nil
          ok = false
        else
          f = v.to_f
        ok = false if f < 0.to_f
        total += f
        floats.push(f)
      ok = false if total <= 0.to_f
      out = floats if ok
    out

  # The denominator a weighted mean, prior or impurity divides by: the sum
  # of `weights`, or `n` itself when weights is nil.
  #
  # Returning the INTEGER n unweighted is deliberate, not sloppiness — it
  # keeps every unweighted computation on exactly the arithmetic it used
  # before weights existed, so no existing hand-computed spec value can
  # drift by a last bit.
  -> .weight_total(weights, n)
    out = n
    if weights != nil
      total = 0.to_f
      weights.each -> (v)
        total += v
      out = total
    out

  # The mean of `values` weighted by `weights` — the plain mean when
  # weights is nil, since a weight of 1 multiplies exactly in IEEE754 and
  # the denominator falls back to the count.
  #
  # ONE loop, not two, on purpose: a local counter captured by two SIBLING
  # closures in the same block miscompiles today (the second capture
  # leaves the first closure's copy unset, and the compiled program dies
  # with "expected numeric type" on the index), so every weighted helper
  # in this bit keeps its per-row index inside a single block or gives the
  # second block a different name.
  -> .weighted_mean(values, weights)
    acc = 0.to_f
    i = 0
    values.each -> (v)
      wt = 1.to_f
      wt = weights[i] if weights != nil
      acc += v.to_f * wt
      i += 1
    acc / Estimator.weight_total(weights, values.size).to_f

  # rows / targets / weights with every ZERO-WEIGHT row removed, as a
  # { rows:, targets:, weights: } triple.
  #
  # A zero weight means "this row is not in the sample". Dropping it HERE,
  # once, is what makes an integer weight vector exactly equivalent to
  # duplicating each row that many times (zero copies included) for every
  # estimator at once — otherwise each one would have to re-derive it, and
  # each would get it subtly wrong somewhere (a class whose every row has
  # weight 0 would still claim a prior; a dropped row would still seed a
  # centroid). Row ORDER is preserved, so first-seen class order matches
  # the duplicated dataset's too.
  #
  # Unweighted input (weights nil) and all-positive input pass straight
  # through untouched and uncopied. `targets` may be nil (an unsupervised
  # fit), in which case it stays nil.
  -> .drop_zero_weights(rows, targets, weights)
    out = { rows: rows, targets: targets, weights: weights }
    if weights != nil
      any = false
      weights.each -> (v)
        any = true if v <= 0.to_f
      if any
        kept_rows = []
        kept_targets = []
        kept_weights = []
        i = 0
        weights.each -> (v)
          if v > 0.to_f
            kept_rows.push(rows[i])
            kept_targets.push(targets[i]) if targets != nil
            kept_weights.push(v)
          i += 1
        ts = nil
        ts = kept_targets if targets != nil
        out = { rows: kept_rows, targets: ts, weights: kept_weights }
    out

  # `values` at `idx`, in idx order — how a CV fold subsets a weight
  # vector without disturbing its alignment with the fold's rows. nil in,
  # nil out.
  -> .subset(values, idx)
    out = nil
    if values != nil
      picked = []
      idx.each -> (ix)
        picked.push(values[ix])
      out = picked
    out

  # --- Arity-safe dispatch (what `supervised?` is FOR) ---

  # Fit `model` without knowing whether it is supervised: supervised
  # estimators get fit(rows, yvals, weights), unsupervised ones get
  # fit(rows, weights). Returns whatever fit returns (the model, or nil
  # when unfittable).
  #
  # `weights` defaults to nil, so every existing three-argument call is
  # byte-identical to what it was. An estimator that cannot honour weights
  # (KNNClassifier) answers nil from fit when they are non-nil, so a
  # weighted fold scores nil rather than a wrong number.
  -> .fit_model(model, rows, yvals, weights = nil)
    out = nil
    if model.supervised?
      out = model.fit(rows, yvals, weights)
    else
      out = model.fit(rows, weights)
    out

  # Score `model` without knowing whether it is supervised; the mirror of
  # fit_model. nil before a successful fit, as ever.
  -> .score_model(model, rows, yvals, weights = nil)
    out = nil
    if model.supervised?
      out = model.score(rows, yvals, weights)
    else
      out = model.score(rows, weights)
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
#
# `supports_sample_weight?` is the weights twin of `supervised?`: a
# machine-readable answer to "can I hand this thing a weight vector?",
# so generic tooling asks instead of guessing (KNNClassifier says false,
# every other koala estimator says true).
trait Estimable
  -> fitted?
  -> predict(x)
  -> supervised?
  -> supports_sample_weight?
  -> params
  -> with_params(overrides)
  -> estimator_name

# Learns from features AND labels: fit(x, y) / score(x, y), with an
# optional trailing per-row weight vector on both.
trait SupervisedEstimator
  -> fit(x, y, sample_weight)
  -> score(x, y, sample_weight)

# Learns from features alone: fit(x) / score(x), with an optional
# trailing per-row weight vector on both.
trait UnsupervisedEstimator
  -> fit(x, sample_weight)
  -> score(x, sample_weight)
