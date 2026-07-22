# Lasso / ElasticNet — L1 and L1+L2 regularized linear regression by
# CYCLIC COORDINATE DESCENT with soft-thresholding (pure Tungsten,
# CPU-only; the sparse half of koala's regularized-linear family, and
# the one that ridge cannot do: it drives coefficients to EXACTLY zero
# rather than merely shrinking them).
#
#     model = Lasso.new(alpha)                        # L1 only
#     model = ElasticNet.new(alpha, l1_ratio)         # L1 + L2 mixed
#     model.fit(x, y)          # self when fitted, nil when unfittable
#     model.fit(x, y, [2, 1, 1])                      # weighted
#     model.coefficients       # per-feature slopes (array of floats)
#     model.intercept          # bias term (float), never penalized
#     model.n_iter             # coordinate-descent sweeps actually run
#     model.predict(x)         # plain array of float predictions
#     model.score(x, y)        # R² of predict(x) against y (Metrics.r2)
#
# --- Where this sits beside LinearRegression ---
#
# lib/linear_regression.w already carries OLS (alpha = 0, Householder QR)
# and RIDGE (alpha > 0, the penalized normal equations). Both are
# closed-form: ridge's L2 penalty is differentiable everywhere, so the
# optimum falls out of a linear solve. L1 is NOT differentiable at zero,
# there is no linear system to solve, and that kink is exactly the point —
# it is what makes the optimum LAND on zero for a whole set of
# coefficients instead of merely near it. A ridge fit with an irrelevant
# feature returns a small nonzero slope for it forever; a lasso fit
# returns 0, and the feature is gone. That is feature SELECTION, a
# genuinely different capability, and it is why this file exists rather
# than another branch inside linear_regression.w.
#
# Nothing here modifies or reaches into LinearRegression: the intercept
# convention is COPIED from it (below), and the shared input coercion
# comes from the neutral Estimator base, exactly as every other estimator
# in the bit gets it.
#
# --- The objective (scikit-learn's, exactly) ---
#
# ElasticNet minimizes, over coefficients w and an intercept b:
#
#     1/(2*W) * sum_i v_i * (y_i - x_i·w - b)^2
#   + alpha * l1_ratio * sum_j |w_j|
#   + alpha * (1 - l1_ratio) / 2 * sum_j w_j^2
#
# where v_i is row i's sample weight (1 when unweighted) and W = sum_i v_i
# (so W = n_samples unweighted). Lasso is this with l1_ratio = 1, and the
# implementation is LITERALLY SHARED: `Lasso.new(a)` and
# `ElasticNet.new(a, 1)` run the identical solver and produce identical
# coefficients (asserted in spec/regularized_linear_spec.w). Lasso exists
# as its own class for its NAME, its params surface (no l1_ratio knob to
# sweep) and its persist tag — the same relationship scikit-learn has,
# where `Lasso` is an `ElasticNet` subclass pinned at l1_ratio = 1.0.
#
# PARAMETERIZATION, stated plainly. This is scikit-learn's objective term
# for term, including the 1/(2*n_samples) on the data fit — which means
# koala's `alpha` here means exactly what sklearn's `alpha` means, and
# every reference value in the spec is a scikit-learn 1.9 number, not a
# hand-derived one. It does NOT mean the same thing as
# `LinearRegression.new(alpha)`'s ridge alpha, because koala's ridge (like
# sklearn's `Ridge`) does NOT scale its data term:
#
#     Ridge:       sum_i v_i (y_i - x_i·w - b)^2  +  alpha_ridge * ||w||^2
#     ElasticNet:  1/(2W) sum_i v_i (...)^2 + ... + alpha (1-l1r)/2 ||w||^2
#
# Multiplying the ElasticNet objective through by 2W and setting
# l1_ratio = 0 gives sum_i v_i (...)^2 + W*alpha*||w||^2, so
#
#     ElasticNet.new(a, 0)  ==  LinearRegression.new(W * a)
#
# with W the sample count (or the total sample weight). That is the SAME
# n_samples factor that relates sklearn's own ElasticNet and Ridge, and
# the spec asserts both halves: koala ElasticNet(a, 0) == koala
# Ridge(n*a), and both == sklearn's numbers.
#
# --- The algorithm ---
#
# Cyclic coordinate descent. With every other coefficient held fixed, the
# objective as a function of w_j is a one-dimensional quadratic plus
# lambda*|w_j|, whose exact minimizer is the SOFT-THRESHOLD
#
#     w_j <- S(x_j·r + w_j * ||x_j||^2 , W*alpha*l1_ratio)
#            / ( ||x_j||^2 + W*alpha*(1 - l1_ratio) )
#
#     S(z, t) = z - t if z > t ; z + t if z < -t ; EXACTLY 0 otherwise
#
# where r is the current residual, and both x_j·r and ||x_j||^2 are the
# WEIGHTED forms (each term multiplied by v_i). Sweeping j = 0 .. p-1 in
# order and updating the residual in place is scikit-learn's
# `enet_coordinate_descent` with `selection="cyclic"` (its default), and
# with n_samples generalized to W. There is no line search, no step size,
# no random coordinate order and no seed: every step is a closed-form
# exact minimization, so a fit is DETERMINATE and byte-identical on both
# engines.
#
# The zero in S's middle branch is a literal, exact `0.to_f` — not a small
# number that prints as zero. That is the whole mechanism behind sparsity,
# and the spec asserts `== 0.to_f`, not a tolerance.
#
# THE INTERCEPT IS NEVER PENALIZED, matching linear_regression.w's ridge
# convention (which puts a ZERO in the intercept slot of the penalty
# diagonal). Here that is achieved by CENTERING rather than by a zero in a
# matrix: x and y are shifted by their (weighted) means, coordinate
# descent runs on the centered problem with no intercept column at all,
# and the bias is recovered afterwards as
#
#     b = ybar - sum_j w_j * xbar_j
#
# The two are the same thing. For a squared loss with an UNPENALIZED
# intercept, the optimum always satisfies b = ybar - xbar·w; substituting
# that back gives exactly the centered problem, so centering is not an
# approximation but the closed-form elimination of b. It is what
# scikit-learn and glmnet both do, and it keeps the penalty from ever
# seeing the bias — a penalized intercept would make the fit depend on
# where the origin of y happens to sit.
#
# --- Convergence criterion and iteration cap ---
#
# A sweep ends; let d = max_j |w_j_new - w_j_old| over that sweep and
# m = max_j |w_j| after it. The fit STOPS when
#
#     d <= tol * m
#
# a RELATIVE coefficient-change test. Justification:
#
#   * Each coordinate update is the EXACT minimizer along that coordinate,
#     so the objective decreases monotonically and is bounded below; the
#     iterates converge and d -> 0. d is therefore a sound termination
#     signal, not a heuristic.
#   * It is scale-free in y: doubling y doubles every coefficient and
#     doubles d, so the same tol means the same thing on any units. An
#     ABSOLUTE test (d <= tol) would silently tighten or loosen with the
#     data's scale.
#   * It is the test that actually terminates scikit-learn's loop —
#     `d_w_max / w_max < d_w_tol` in `enet_coordinate_descent` — so the
#     same `tol` buys the same accuracy here as there.
#   * The all-zero solution is handled by the same expression rather than
#     a special case: when m = 0 every coefficient is 0, so d = 0 too and
#     `0 <= tol * 0` holds. (A sweep that COLLAPSES a nonzero coefficient
#     to zero has d > 0 and m = 0 and does not stop, correctly: it costs
#     one confirming sweep, which is the cheap and safe direction.)
#
# What is deliberately NOT implemented is scikit-learn's DUALITY GAP
# check, which it runs after the change test as an optimality certificate.
# The gap needs a dual-feasible rescaling of the residual and a second,
# differently-scaled tolerance (sklearn multiplies tol by y·y for it), and
# it can only make the loop run LONGER, never shorter — it is a stronger
# stopping rule layered on the same iteration. Omitting it costs accuracy
# only in the last digits, and the spec pins that cost by measuring
# against scikit-learn's own values: at the specs' tolerances the two
# agree, and the reference table in spec/regularized_linear_spec.w is
# sklearn 1.9 output.
#
# The ITERATION CAP is `max_iter` sweeps, defaulting to 1000 —
# scikit-learn's default, and roughly fifteen times what these problems
# need (sklearn reports n_iter_ = 0..64 on every dataset in the spec). It
# exists because coordinate descent on a rank-deficient or unpenalized
# problem need not have a unique fixed point; the cap turns "no unique
# answer" into "a finite answer", never a hang. `n_iter` reports the
# sweeps actually run, so hitting the cap is visible (sklearn's n_iter_).
#
# TOL defaults to 1e-4, also scikit-learn's. Both are derived by integer
# division (`1.to_f / 10000.to_f`), never written as float literals.
#
# --- Sample weights: SUPPORTED, and exactly equal to duplication ---
#
# `fit(x, y, sample_weight)` weights each row's squared error by v_i, and
# the 1/(2W) normalization uses W = sum_i v_i rather than the row count.
# That combination is what makes an INTEGER weight vector EXACTLY the same
# model as duplicating each row that many times — the bit's stated
# definition of correctness (lib/estimator_base.w). The unweighted
# objective on the duplicated data has W' = sum v_i rows and the same
# per-row terms, so the two objectives are identical function for
# function, penalty included. scikit-learn reaches the same place by
# rescaling sample_weight to sum to n_samples before scaling X and y by
# sqrt(w); the spec checks weighted-fit == duplicated-fit on both koala
# and sklearn.
#
# Zero-weight rows are dropped first (Estimator.drop_zero_weights), so
# "weight 0" means "not in the sample" here as everywhere else in koala.
# The weighted column means used for centering are weighted too, so the
# intercept moves with the weights.
#
# --- What is rejected, and what is NOT ---
#
# fit returns nil — never raises, and fitted? stays false — for: an empty
# x, ragged rows, a y whose size mismatches, an unusable weight vector, a
# NEGATIVE alpha, an l1_ratio outside [0, 1], max_iter < 1, or a negative
# tol. predict / score return nil before a successful fit and when a
# query row's width differs from the fitted feature count.
#
# NOT rejected, unlike LinearRegression: COLLINEAR features and FEWER
# SAMPLES THAN FEATURES. OLS has to refuse those (the system is singular);
# with alpha > 0 the penalized objective is strictly convex in the
# directions that matter and has a well-defined minimum, and p > n is the
# case lasso was invented for. At alpha = 0 on a rank-deficient design the
# minimizer is not unique and coordinate descent returns one of them
# (deterministically, but not the minimum-norm one) — use
# LinearRegression, which detects the rank deficiency and says nil.
#
# NOTE: the descent loops are `while` loops over explicit indices rather
# than blocks — the inner loops are the hot path. No float literal appears
# in this file (a bare decimal literal is a Decimal and does not coerce
# with Float): every float derives from the data or from
# integer division via .to_f.

# The solver both estimators share: coordinate descent, centering, the
# soft threshold, and the linear predict/score pair. Class methods only —
# it holds no state, exactly like the neutral Estimator base.
+ ElasticNetSolver
  # S(z, t): z pulled toward zero by t, and EXACTLY 0.to_f once |z| <= t.
  # The dead zone is what puts a hard zero in a coefficient vector; it is
  # returned as the literal zero, not as a difference that rounds to it.
  -> .soft_threshold(z, t)
    zero = 0.to_f
    out = zero
    out = z - t if z > t
    out = z + t if z < zero - t
    out

  # Are the four hyperparameters usable? A negative alpha is not a
  # penalty, an l1_ratio outside [0, 1] is not a mixture, fewer than one
  # sweep cannot fit and a negative tol cannot be met. Each is a nil from
  # fit, never a raise — the bit's shape-error convention extended to the
  # knobs.
  -> .usable_params?(alpha, l1_ratio, max_iter, tol)
    out = false
    if alpha != nil && l1_ratio != nil && max_iter != nil && tol != nil
      zero = 0.to_f
      one = 1.to_f
      out = true
      out = false if alpha.to_f < zero
      out = false if l1_ratio.to_f < zero
      out = false if l1_ratio.to_f > one
      out = false if max_iter < 1
      out = false if tol.to_f < zero
    out

  # The weighted mean of column j of rows, over total weight wtotal.
  -> .column_mean(rows, j, wts, wtotal)
    acc = 0.to_f
    one = 1.to_f
    n = rows.size
    i = 0
    while i < n
      wv = one
      wv = wts[i] if wts != nil
      acc += wv * rows[i][j].to_f
      i += 1
    acc / wtotal

  # Everything fit learns, as { coefficients:, intercept:, n_iter: }, or
  # nil when the inputs or the knobs are unusable. Both estimators call
  # exactly this — Lasso passes l1_ratio = 1 — so there is ONE coordinate
  # descent in the bit and no chance of the two drifting apart.
  -> .fit_state(x, y, sample_weight, alpha, l1_ratio, max_iter, tol)
    rows = Estimator.feature_rows(x)
    yvals = Estimator.target_values(y)
    ok = rows != nil && yvals != nil
    ok = rows.size > 0 && rows.size == yvals.size if ok
    ok = rows[0].size > 0 if ok
    if ok
      width = rows[0].size
      rows.each -> (r)
        ok = false if r.size != width
    ok = false if ok && !ElasticNetSolver.usable_params?(alpha, l1_ratio, max_iter, tol)
    wts = nil
    wts = Estimator.weight_values(sample_weight, rows.size) if ok && sample_weight != nil
    ok = false if sample_weight != nil && wts == nil
    if ok && wts != nil
      trimmed = Estimator.drop_zero_weights(rows, yvals, wts)
      rows = trimmed[:rows]
      yvals = trimmed[:targets]
      wts = trimmed[:weights]
    out = nil
    if ok
      zero = 0.to_f
      one = 1.to_f
      n = rows.size
      nf = rows[0].size
      wtotal = Estimator.weight_total(wts, n).to_f

      # --- centering: the closed-form elimination of the intercept ---
      xbar = []
      j = 0
      while j < nf
        xbar.push(ElasticNetSolver.column_mean(rows, j, wts, wtotal))
        j += 1
      ysum = zero
      i = 0
      while i < n
        wv = one
        wv = wts[i] if wts != nil
        ysum += wv * yvals[i].to_f
        i += 1
      ybar = ysum / wtotal

      # centered features, COLUMN-major: coordinate descent walks one
      # column at a time, so this is the layout every inner loop wants.
      cols = []
      j = 0
      while j < nf
        mu = xbar[j]
        col = []
        i = 0
        while i < n
          col.push(rows[i][j].to_f - mu)
          i += 1
        cols.push(col)
        j += 1

      # weighted squared column norms ||x_j||^2, the denominators
      colsq = []
      j = 0
      while j < nf
        colj = cols[j]
        acc = zero
        i = 0
        while i < n
          wv = one
          wv = wts[i] if wts != nil
          acc += wv * colj[i] * colj[i]
          i += 1
        colsq.push(acc)
        j += 1

      # residual r = y_centered - X_centered · beta, with beta = 0
      res = []
      i = 0
      while i < n
        res.push(yvals[i].to_f - ybar)
        i += 1

      beta = []
      j = 0
      while j < nf
        beta.push(zero)
        j += 1

      # penalty strengths, already multiplied through by W so the update
      # below is scikit-learn's arithmetic term for term
      af = alpha.to_f
      lf = l1_ratio.to_f
      thr = wtotal * af * lf
      l2t = wtotal * af * (one - lf)
      tf = tol.to_f

      # --- the sweeps ---
      iter = 0
      done = false
      while iter < max_iter && !done
        iter += 1
        dmax = zero
        wmax = zero
        j = 0
        while j < nf
          colj = cols[j]
          old = beta[j]
          acc = zero
          i = 0
          while i < n
            wv = one
            wv = wts[i] if wts != nil
            acc += wv * colj[i] * res[i]
            i += 1
          tmp = acc + colsq[j] * old
          denom = colsq[j] + l2t
          nw = zero
          nw = ElasticNetSolver.soft_threshold(tmp, thr) / denom if denom > zero
          if nw != old
            step = nw - old
            i = 0
            while i < n
              res[i] = res[i] - colj[i] * step
              i += 1
            beta[j] = nw
          moved = LinAlg.fabs(nw - old)
          dmax = moved if moved > dmax
          mag = LinAlg.fabs(nw)
          wmax = mag if mag > wmax
          j += 1
        done = true if dmax <= tf * wmax

      # --- the intercept, read back off the centering ---
      base = ybar
      j = 0
      while j < nf
        base = base - beta[j] * xbar[j]
        j += 1
      out = { coefficients: beta, intercept: base, n_iter: iter }
    out

  # Predictions for x from a coefficient vector and a bias — the linear
  # model's forward pass, shared so Lasso and ElasticNet cannot disagree
  # about it. nil for a nil model and on a width mismatch.
  -> .linear_predict(x, coefs, base)
    rows = nil
    rows = Estimator.feature_rows(x) if coefs != nil && base != nil
    out = nil
    if rows != nil
      nf = coefs.size
      ok = true
      rows.each -> (r)
        ok = false if r.size != nf
      if ok
        preds = []
        rows.each -> (r)
          total = base.to_f
          nf.times -> (j)
            total += coefs[j].to_f * r[j].to_f
          preds.push(total)
        out = preds
    out

  # R² of preds against y, weighted when sample_weight is given; nil when
  # preds is nil or the shapes do not line up.
  -> .linear_score(preds, y, sample_weight)
    yvals = nil
    yvals = Estimator.target_values(y) if y != nil
    out = nil
    if preds != nil && yvals != nil
      ok = preds.size == yvals.size && preds.size > 0
      wts = nil
      wts = Estimator.weight_values(sample_weight, preds.size) if ok && sample_weight != nil
      ok = false if sample_weight != nil && wts == nil
      out = Metrics.r2(preds, yvals, wts) if ok
    out

# ElasticNet — the L1/L2 mixture, and the general case both classes are
# built on. See the header for the objective, the update and the
# convergence rule.
#
#     ElasticNet.new(alpha, l1_ratio, max_iter, tol)
#     ElasticNet.new                      # alpha 1, l1_ratio 0.5, 1000, 1e-4
#
# Defaults are scikit-learn's ElasticNet defaults. alpha defaults to 1
# rather than to LinearRegression's 0 because a regularizer with no
# regularization is not what anyone reaches for this class to get — pass
# 0 deliberately (it is well defined, and reproduces OLS) rather than by
# accident.
#
# ALPHA HONESTY, the same as linear_regression.w's: pass an INTEGER, or a
# Float built with .to_f arithmetic (`1.to_f / 10.to_f`). Keep it in
# Float — a bare decimal literal is a Decimal and does not coerce with the
# solver's Float arithmetic.
+ ElasticNet
  is Estimable
  is SupervisedEstimator

  ro :coefficients   # per-feature slopes after a successful fit; nil before
  ro :intercept      # bias term after a successful fit; nil before
  ro :alpha          # overall penalty strength; 0 reproduces OLS
  ro :l1_ratio       # L1 share of the penalty; 1 is pure lasso, 0 is ridge
  ro :max_iter       # coordinate-descent sweep cap
  ro :tol            # relative coefficient-change tolerance
  ro :n_iter         # sweeps actually run by the last fit; nil before

  -> new(alpha = 1, l1_ratio = nil, max_iter = 1000, tol = nil)
    mix = l1_ratio
    mix = 1.to_f / 2.to_f if mix == nil
    eps = tol
    eps = 1.to_f / 10000.to_f if eps == nil
    @alpha = alpha
    @l1_ratio = mix
    @max_iter = max_iter
    @tol = eps
    @fitted = false
    @coefficients = nil
    @intercept = nil
    @n_iter = nil

  -> fitted?
    @fitted

  # --- Estimable contract (see lib/estimator_base.w) ---

  -> estimator_name
    "ElasticNet"

  -> supervised?
    true

  # Weighted coordinate descent is exact here — see the header.
  -> supports_sample_weight?
    true

  # The hyperparameters a search varies — never the learned coefficients.
  # All four are sweepable; alpha and l1_ratio are the two that matter.
  -> params
    { alpha: @alpha, l1_ratio: @l1_ratio, max_iter: @max_iter, tol: @tol }

  # A NEW, UNFITTED ElasticNet with `overrides` applied; self is left
  # untouched. Unmentioned keys carry over, so with_params(params)
  # round-trips. An l1_ratio or tol overridden to nil falls back to the
  # constructor default, which is what "clear this knob" should mean.
  -> with_params(overrides)
    a = Estimator.opt(overrides, :alpha, @alpha)
    mix = Estimator.opt(overrides, :l1_ratio, @l1_ratio)
    mi = Estimator.opt(overrides, :max_iter, @max_iter)
    eps = Estimator.opt(overrides, :tol, @tol)
    ElasticNet.new(a, mix, mi, eps)

  # Learn coefficients and intercept from x/y by coordinate descent.
  # Returns self, or nil — fitted? stays false — when the shapes or the
  # hyperparameters are unusable (see the header's rejection list).
  -> fit(x, y, sample_weight = nil)
    res = ElasticNetSolver.fit_state(x, y, sample_weight, @alpha, @l1_ratio, @max_iter, @tol)
    out = nil
    if res != nil
      @coefficients = res[:coefficients]
      @intercept = res[:intercept]
      @n_iter = res[:n_iter]
      @fitted = true
      out = self
    out

  # Predictions for x as a plain array of floats (Metrics-ready). nil
  # before fit, and nil when x's rows do not match the fitted feature
  # count.
  -> predict(x)
    out = nil
    out = ElasticNetSolver.linear_predict(x, @coefficients, @intercept) if @fitted
    out

  # R² (Metrics.r2) of self's predictions on x against y, weighted when
  # sample_weight is given; nil before fit or when the shapes do not line
  # up.
  -> score(x, y, sample_weight = nil)
    ElasticNetSolver.linear_score(self.predict(x), y, sample_weight)

  # --- Persistence (see lib/persist.w) ---

  -> persist_name
    "ElasticNet"

  # The hyperparameters AND what fit learned — a saved model is exactly
  # that pair. n_iter rides along because it is a fact about the fit that
  # cannot be recomputed without the training data.
  -> to_state
    { alpha: @alpha, l1_ratio: @l1_ratio, max_iter: @max_iter, tol: @tol, coefficients: @coefficients, intercept: @intercept, n_iter: @n_iter }

  # A FITTED ElasticNet rebuilt from `st`, or nil when st is not one of
  # ours — the guard that stops a payload written by a different
  # estimator, or a truncated one, from loading as a model that answers
  # predictions.
  -> .load_state(st)
    out = nil
    ok = st != nil
    ok = st[:alpha] != nil && st[:l1_ratio] != nil if ok
    ok = st[:max_iter] != nil && st[:tol] != nil if ok
    ok = st[:coefficients] != nil && st[:intercept] != nil if ok
    if ok
      model = ElasticNet.new(st[:alpha], st[:l1_ratio], st[:max_iter], st[:tol])
      out = model.restore_state(st)
    out

  # Reinstate the learned coefficients on self; returns self.
  -> restore_state(st)
    @coefficients = st[:coefficients]
    @intercept = st[:intercept]
    @n_iter = st[:n_iter]
    @fitted = true
    self

# Lasso — pure L1. Exactly ElasticNet at l1_ratio = 1, running the exact
# same solver; the class exists for its name, for a params surface with no
# l1_ratio to sweep, and for its own persist tag.
#
#     Lasso.new(alpha, max_iter, tol)
#     Lasso.new              # alpha 1, 1000 sweeps, tol 1e-4 (sklearn's)
#
# The sparsity claim lives here: with alpha large enough, an uninformative
# feature's coefficient is EXACTLY 0.to_f, not a small number. Ridge at
# the equivalent strength leaves it small and nonzero forever. Both are
# asserted side by side in spec/regularized_linear_spec.w.
+ Lasso
  is Estimable
  is SupervisedEstimator

  ro :coefficients   # per-feature slopes after a successful fit; nil before
  ro :intercept      # bias term after a successful fit; nil before
  ro :alpha          # L1 penalty strength; 0 reproduces OLS
  ro :max_iter       # coordinate-descent sweep cap
  ro :tol            # relative coefficient-change tolerance
  ro :n_iter         # sweeps actually run by the last fit; nil before

  -> new(alpha = 1, max_iter = 1000, tol = nil)
    eps = tol
    eps = 1.to_f / 10000.to_f if eps == nil
    @alpha = alpha
    @max_iter = max_iter
    @tol = eps
    @fitted = false
    @coefficients = nil
    @intercept = nil
    @n_iter = nil

  -> fitted?
    @fitted

  # The mixture Lasso is pinned at — 1, all L1. Reported, not settable:
  # an L1 model whose L1 share could be turned down is an ElasticNet.
  -> l1_ratio
    1

  # --- Estimable contract (see lib/estimator_base.w) ---

  -> estimator_name
    "Lasso"

  -> supervised?
    true

  -> supports_sample_weight?
    true

  -> params
    { alpha: @alpha, max_iter: @max_iter, tol: @tol }

  -> with_params(overrides)
    a = Estimator.opt(overrides, :alpha, @alpha)
    mi = Estimator.opt(overrides, :max_iter, @max_iter)
    eps = Estimator.opt(overrides, :tol, @tol)
    Lasso.new(a, mi, eps)

  -> fit(x, y, sample_weight = nil)
    res = ElasticNetSolver.fit_state(x, y, sample_weight, @alpha, 1, @max_iter, @tol)
    out = nil
    if res != nil
      @coefficients = res[:coefficients]
      @intercept = res[:intercept]
      @n_iter = res[:n_iter]
      @fitted = true
      out = self
    out

  -> predict(x)
    out = nil
    out = ElasticNetSolver.linear_predict(x, @coefficients, @intercept) if @fitted
    out

  -> score(x, y, sample_weight = nil)
    ElasticNetSolver.linear_score(self.predict(x), y, sample_weight)

  # --- Persistence (see lib/persist.w) ---

  -> persist_name
    "Lasso"

  -> to_state
    { alpha: @alpha, max_iter: @max_iter, tol: @tol, coefficients: @coefficients, intercept: @intercept, n_iter: @n_iter }

  # A FITTED Lasso rebuilt from `st`, or nil when st is not one of ours.
  #
  # The l1_ratio test is what makes the guard SYMMETRIC. Lasso's state is
  # a strict SUBSET of ElasticNet's keys, so without it an ElasticNet
  # payload relabelled "Lasso" would load — as a model whose coefficients
  # came from a mixed penalty but which reports l1_ratio 1. Refusing a
  # state that carries a key Lasso never writes is exactly the check that
  # tells two same-shaped states apart (ElasticNet.load_state refuses a
  # Lasso body for the mirror-image reason: no l1_ratio at all).
  -> .load_state(st)
    out = nil
    ok = st != nil
    ok = st[:alpha] != nil && st[:max_iter] != nil && st[:tol] != nil if ok
    ok = st[:coefficients] != nil && st[:intercept] != nil if ok
    ok = st[:l1_ratio] == nil if ok
    if ok
      model = Lasso.new(st[:alpha], st[:max_iter], st[:tol])
      out = model.restore_state(st)
    out

  -> restore_state(st)
    @coefficients = st[:coefficients]
    @intercept = st[:intercept]
    @n_iter = st[:n_iter]
    @fitted = true
    self
