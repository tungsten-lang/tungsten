# KFold / CrossValidation — k-fold cross-validation (pure Tungsten,
# CPU-only; the model-evaluation companion to Splitter's single
# hold-out split — it ties koala's estimators (LinearRegression,
# KNNClassifier) to its Metrics by re-fitting on each of k folds and
# recording the held-out score, sklearn-style).
#
#     KFold.new(5).split(10)          # 5 contiguous [train, test] index pairs
#     KFold.new(5, 42).split(10)      # ... over a seeded shuffle first
#     CrossValidation.cross_val_score(LinearRegression.new, x, y, 5)
#       # => array of 5 per-fold R² (or accuracy for a classifier)
#     CrossValidation.cross_val_mean(KNNClassifier.new(3), x, y, 4)
#       # => the mean fold score (the single number usually reported)
#     CrossValidation.cross_val_mean(KMeans.new(2), x, nil, 2)
#       # => unsupervised: y is nil, folds score -inertia on held-out rows
#
# KFold partitions 0...n into k folds. Fold sizes match scikit-learn
# exactly: with n samples and k folds, the FIRST (n mod k) folds hold
# ceil(n/k) samples and the rest hold floor(n/k), so every sample lands
# in exactly one test fold. `split(n)` returns an array of k pairs
# [train_indices, test_indices]; fold f's test set is that fold's slice
# and its train set is every other index (order preserved).
#
# Determinism: with seed = nil the indices are 0..n-1 in order (folds are
# contiguous blocks — scikit-learn's shuffle=False), and an integer seed
# shuffles first through Splitter.indices — koala's built-in MINSTD
# Lehmer generator — so the same seed gives the same folds on BOTH
# engines. k must satisfy 2 <= k <= n; split returns nil otherwise (the
# bit's shape-error convention).
#
# CrossValidation.cross_val_score coerces x / y through the estimators'
# shared Estimator.feature_rows / .target_values (every accepted
# input shape, one definition: a DataFrame, Matrix, array of row arrays,
# or flat single-feature array for x; a Series, Vector, or array for y),
# builds the folds against the sample count, and for each fold re-fits
# the SAME model on the training rows and records its score on the
# held-out rows. Re-fitting is safe: each estimator's fit fully
# recomputes its state (hyperparameters — alpha, k — are preserved), so
# fold scores are independent; the model is left fitted on the LAST fold.
# A fold whose fit fails (nil — e.g. collinear features at alpha = 0)
# records a nil score AND IS NOT SCORED: scoring an estimator whose
# re-fit just failed would silently report the PREVIOUS fold's state.
# cross_val_mean averages through Stats.mean, which drops those nils
# (all-nil folds give nil). nil overall when x / y cannot be coerced,
# their lengths disagree, or KFold rejects k.
#
# SUPERVISED AND UNSUPERVISED. Both fit and score go through
# Estimator.fit_model / .score_model rather than calling model.fit(rows, y)
# directly, so the model's own `supervised?` picks the arity: fit(rows, y)
# for LinearRegression / KNNClassifier / LogisticRegression / GaussianNB,
# fit(rows) for KMeans. That is exactly what the estimator contract's
# arity-safe dispatch exists for, and it is what lets GridSearch search an
# unsupervised estimator without special-casing it. y is optional: pass
# nil (or omit it) for an unsupervised model, whose fold score is
# -inertia on the held-out rows.
#
# NOTE: locals are hoisted from ivars before any `-> (x)` block, methods
# containing closures avoid early `return`, and no float literals appear
# here (every float derives from the data) — the same conventions as the
# rest of koala's estimator code.
+ KFold
  ro :k      # number of folds (2 <= k <= n)
  ro :seed   # shuffle seed; nil keeps input order (contiguous folds)

  -> new(k = 5, seed = nil)
    @k = k
    @seed = seed

  # k [train_indices, test_indices] pairs partitioning 0...n; nil when
  # k is out of range (k < 2 or k > n) or n <= 0.
  -> split(n)
    k = @k
    seed = @seed
    out = nil
    if n > 0 && k >= 2 && k <= n
      order = Splitter.indices(n, seed)
      base = n / k
      rem = n % k
      pairs = []
      start = 0
      k.times -> (f)
        size = base
        size = base + 1 if f < rem
        stop = start + size
        test_idx = []
        train_idx = []
        pos = 0
        order.each -> (ix)
          if pos >= start && pos < stop
            test_idx.push(ix)
          else
            train_idx.push(ix)
          pos += 1
        pair = [train_idx, test_idx]
        pairs.push(pair)
        start = stop
      out = pairs
    out

+ CrossValidation
  # Per-fold scores (an array of k floats) from re-fitting `model` on
  # each fold's training rows and scoring the held-out rows. nil when the
  # inputs cannot be coerced, their lengths disagree, or KFold rejects k.
  # A fold whose fit fails contributes a nil score.
  #
  # Works for SUPERVISED and UNSUPERVISED estimators alike: `model` is
  # fitted and scored through Estimator.fit_model / .score_model, which
  # read model.supervised? and pass the right arity. y is therefore
  # OPTIONAL — omit it (or pass nil) for an unsupervised model like
  # KMeans, whose folds score -inertia on the held-out rows. A supervised
  # model still requires a y whose length matches x.
  -> .cross_val_score(model, x, y = nil, k = 5, seed = nil)
    rows = Estimator.feature_rows(x)
    supervised = model.supervised?
    yvals = nil
    yvals = Estimator.target_values(y) if supervised && y != nil
    out = nil
    ok = rows != nil
    ok = yvals != nil && rows.size == yvals.size if ok && supervised
    ok = rows.size > 0 if ok
    if ok
      folds = KFold.new(k, seed).split(rows.size)
      if folds != nil
        scores = []
        folds.each -> (fold)
          tr_idx = fold[0]
          te_idx = fold[1]
          tr_rows = []
          tr_y = []
          tr_idx.each -> (ix)
            tr_rows.push(rows[ix])
            tr_y.push(yvals[ix]) if yvals != nil
          te_rows = []
          te_y = []
          te_idx.each -> (ix)
            te_rows.push(rows[ix])
            te_y.push(yvals[ix]) if yvals != nil
          f = Estimator.fit_model(model, tr_rows, tr_y)
          s = nil
          s = Estimator.score_model(model, te_rows, te_y) if f != nil
          scores.push(s)
        out = scores
    out

  # The mean of cross_val_score (the single headline number). nil when
  # cross_val_score is nil; nil-scoring folds are dropped by Stats.mean,
  # and an all-nil set of folds means nil overall. This is the number
  # GridSearch ranks candidates by.
  -> .cross_val_mean(model, x, y = nil, k = 5, seed = nil)
    scores = self.cross_val_score(model, x, y, k, seed)
    out = nil
    out = Stats.mean(scores) if scores != nil
    out
