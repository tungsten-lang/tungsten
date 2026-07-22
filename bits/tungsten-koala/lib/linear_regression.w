# LinearRegression — least squares via Householder QR, with optional
# ridge regularization on the normal equations (pure Tungsten,
# CPU-only; koala's first estimator: fit / predict / score with
# per-instance fitted state, sklearn-style)
#
#     model = LinearRegression.new
#     model = LinearRegression.new(12)   # ridge, alpha = 12
#     model.fit(x, y)          # self when fitted, nil when unfittable
#     model.coefficients       # per-feature slopes (array of floats)
#     model.intercept          # bias term (float)
#     model.predict(x)         # plain array of float predictions
#     model.score(x, y)        # R² of predict(x) against y (Metrics.r2)
#
# TWO SOLVERS, chosen by alpha:
#
#   alpha = 0 (the default) — PLAIN OLS through LinAlg.lstsq:
#     Householder QR on the design matrix X itself, with back
#     substitution through R. The normal equations are never formed,
#     so cond(X) is not squared and an ill-conditioned design keeps
#     roughly twice as many correct digits (see the numerics note in
#     lib/linalg.w, and the head-to-head against the old route in
#     spec/linalg_spec.w: 6.9e-11 error versus 5.3e-4 on a clustered
#     Vandermonde).
#
#   alpha > 0 — RIDGE through the penalized normal equations,
#     (X^T X + alpha*I') beta = X^T y, where I' is the identity with a
#     ZERO in the intercept slot: the standard penalty shrinks every
#     feature coefficient toward zero but never the bias. This path is
#     UNCHANGED — the ridge penalty is defined on X^T X, and the
#     penalty itself bounds the conditioning that made OLS's normal
#     equations unsafe. With alpha > 0 the penalized matrix is positive
#     definite, so inputs whose plain X^T X is singular (collinear
#     features) fit fine.
#
# Rank deficiency is rejected identically by both routes: QR's scaled
# rank test (LinAlg.rank_tol) and elimination's zero-pivot test both
# return nil for genuinely collinear features, so fit's contract below
# is the same as it always was.
#
# alpha honesty (verified by probe on both engines): pass an INTEGER
# (`LinearRegression.new(12)`), or a data-derived float built with
# .to_f arithmetic (`LinearRegression.new(1.to_f / 2.to_f)`). Never
# write a float LITERAL for it — a float literal anywhere in a program
# (even `a / 10.0` in an unrelated top-level line) corrupts later
# method-call arguments on BOTH engines today ("undefined method for
# Object (numeric 0xfffd...)"), so fractional alpha must come from
# integer .to_f division.
#
# Accepted shapes, normalized in one place (feature_rows /
# target_values): x is a DataFrame (numeric columns only, in column
# order — string/symbol columns are skipped, see DataFrame#to_matrix),
# a Matrix (rows are samples), an array of row arrays, or a flat
# numeric array (one single-feature row per value). y is a Series, a
# Vector, or a plain array. nil cells are NOT handled — run an
# Imputer first.
#
# fit builds the design matrix X with a leading all-ones intercept
# column and hands it to whichever solver alpha selects (above). An
# unusable system — collinear features, or fewer samples than features,
# with alpha = 0 — makes the solver return nil, so fit returns nil and
# fitted? stays false: the bit's shape-error convention. predict/score
# return nil before a successful fit, and predict returns nil when a
# row's width differs from the fitted feature count.
#
# NOTE: locals are hoisted from ivars before any `-> (x)` block — the
# interpreter cannot resolve @ivars from a block body — and methods
# containing closures avoid early `return` (see stats.w). No float
# literals appear here: every float derives from the data via .to_f.
+ LinearRegression
  is Estimable
  is SupervisedEstimator

  ro :coefficients   # per-feature slopes after a successful fit; nil before
  ro :intercept      # bias term after a successful fit; nil before
  ro :alpha          # ridge strength; 0 = plain OLS

  -> new(alpha = 0)
    @fitted = false
    @coefficients = nil
    @intercept = nil
    @alpha = alpha

  -> fitted?
    @fitted

  # --- Estimable contract (see lib/estimator_base.w) ---

  -> estimator_name
    "LinearRegression"

  # Learns from features AND a target: fit(x, y) / score(x, y).
  -> supervised?
    true

  # The hyperparameters a search varies — never the learned coefficients.
  -> params
    { alpha: @alpha }

  # A NEW, UNFITTED LinearRegression with `overrides` applied; self is left
  # untouched. Unmentioned keys carry over, so with_params(params) round-trips.
  -> with_params(overrides)
    LinearRegression.new(Estimator.opt(overrides, :alpha, @alpha))

  # Learn coefficients and intercept from x/y. Returns self, or nil —
  # fitted? stays false — when the shapes are unusable (empty x,
  # ragged rows, y size mismatch) or X^T X is singular.
  -> fit(x, y)
    rows = Estimator.feature_rows(x)
    yvals = Estimator.target_values(y)
    ok = rows != nil && yvals != nil
    ok = rows.size > 0 && rows.size == yvals.size if ok
    ok = rows[0].size > 0 if ok
    if ok
      width = rows[0].size
      rows.each -> (r)
        ok = false if r.size != width
    out = nil
    if ok
      # design matrix: leading all-ones intercept column, then features
      design = []
      rows.each -> (r)
        row = [1]
        r.each -> (v)
          row.push(v)
        design.push(row)
      xm = Matrix.new(design)
      alpha = @alpha
      beta = nil
      if alpha == 0
        # PLAIN OLS: least squares straight off the design matrix by
        # Householder QR. X^T X is never formed, so the condition
        # number is not squared — on an ill-conditioned design this is
        # the difference between four correct digits and eleven (see
        # the numerics note in lib/linalg.w and the head-to-head spec
        # in spec/linalg_spec.w). Rank-deficient designs still come
        # back nil: LinAlg's scaled rank test replaces the old
        # exactly-zero pivot, and both reject genuinely collinear
        # features with six decades of margin.
        beta = LinAlg.lstsq(xm, yvals)
      else
        # RIDGE: the penalized normal equations, unchanged. Adding
        # alpha to the feature diagonal is defined ON X^T X, and the
        # penalty makes the system positive definite — so the squared
        # condition number the OLS path fled is bounded here by alpha
        # itself, and every hand-computed ridge value in the specs is
        # produced by exactly this arithmetic.
        xt = xm.transpose
        xtx = xt.matmul(xm)
        # add alpha to every diagonal entry EXCEPT the intercept's
        # (row 0 of the design is the all-ones column — the bias is
        # never penalized).
        ents = xtx.to_a
        n = ents.size
        n.times -> (k)
          ents[k][k] = ents[k][k] + alpha if k > 0
        beta = LinAlg.solve(xtx, xt.matvec(Vector.new(yvals)))
      if beta != nil
        b = beta.to_a
        coefs = []
        i = 0
        b.each -> (v)
          coefs.push(v) if i > 0
          i += 1
        @intercept = b[0]
        @coefficients = coefs
        @fitted = true
        out = self
    out

  # Predictions for x as a plain array of floats (Metrics-ready).
  # nil before fit, and nil when x's rows do not match the fitted
  # feature count.
  -> predict(x)
    rows = nil
    rows = Estimator.feature_rows(x) if @fitted
    out = nil
    if rows != nil
      coefs = @coefficients
      base = @intercept
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

  # R² (Metrics.r2) of self's predictions on x against y; nil before
  # fit or when the shapes do not line up.
  -> score(x, y)
    preds = self.predict(x)
    yvals = Estimator.target_values(y)
    out = nil
    if preds != nil && yvals != nil
      out = Metrics.r2(preds, yvals) if preds.size == yvals.size && preds.size > 0
    out

  # --- Input coercion: DELEGATING ALIASES ---
  #
  # The one definition of every accepted input shape moved to the neutral
  # Estimator base (lib/estimator_base.w) — a classifier has no business
  # depending on the linear model for it. These two survive unchanged in
  # behavior so existing callers keep working; new code should call
  # Estimator.feature_rows / Estimator.target_values directly.

  -> .feature_rows(x)
    Estimator.feature_rows(x)

  -> .target_values(y)
    Estimator.target_values(y)
