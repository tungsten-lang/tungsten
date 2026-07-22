# KMeans — k-means clustering by Lloyd's algorithm (pure Tungsten,
# CPU-only; koala's first UNSUPERVISED learner — it partitions rows into
# k groups with no labels at all, the companion to the supervised
# LinearRegression / KNNClassifier / LogisticRegression estimators, and
# koala's first clustering model)
#
#     model = KMeans.new(3)      # 3 clusters; k defaults to 8 (sklearn)
#     model.fit(x)               # self when fitted, nil when unfittable
#     model.labels               # cluster index (0..k-1) per training row
#     model.centroids            # array of k centroid rows (floats)
#     model.inertia              # sum of squared point->centroid distances
#     model.n_iter               # Lloyd iterations run to convergence
#     model.predict(x)           # assign new rows to the nearest centroid
#     model.fit_predict(x)       # fit, then return the training labels
#     model.score(x)             # -inertia on x (sklearn's convention)
#
# Lloyd's algorithm: seed k centroids, then repeat two steps until the
# assignment stops changing (or max_iter, default 300 — sklearn's cap):
#   1. ASSIGN each row to its nearest centroid (squared Euclidean).
#   2. UPDATE each centroid to the mean of the rows assigned to it.
# An empty cluster keeps its previous centroid. Inertia (within-cluster
# sum of squares) never increases across steps and the partition space
# is finite, so with a deterministic assignment rule the loop always
# converges.
#
# DETERMINISM — the whole point of a clustering learner you can spec.
# The only source of randomness in k-means is the initial centroids, so
# koala pins it down two ways, both reproducible on BOTH engines:
#   * no seed (the default): the initial centroids are the first k
#     DISTINCT training rows, in order — no RNG at all.
#   * an integer seed: the rows are permuted first through Splitter's
#     MINSTD Lehmer generator (the same seeded shuffle KFold / Splitter
#     use), then the first k distinct rows of that permutation seed the
#     centroids — so the same seed gives the same clustering every time.
# Distance ties in ASSIGN break to the lowest-index centroid (strict
# `<`, exactly like KNNClassifier), so the assignment is a pure function
# of the inputs. Every float derives from the data via .to_f (no float
# literal ever reaches a call argument — those corrupt args on both
# engines), and Math is not even needed: squared distance keeps integer
# inputs exact until the centroid means divide.
#
# REFERENCE (hand-computed, matches scikit-learn's KMeans with the same
# fixed init, n_init=1): on the two 2x2 boxes
#   [[0,0],[2,0],[0,2],[2,2],[10,10],[12,10],[10,12],[12,12]]
# with k=2 and the default init (first two distinct rows [0,0],[2,0]),
# Lloyd converges in n_iter=2 to centroids [[1,1],[11,11]], labels
# [0,0,0,0,1,1,1,1], and inertia exactly 16 (each of the eight points
# sits sqrt(2) from its centroid, squared distance 2, times eight).
#
# Accepted input shapes are the estimators' shared ones, coerced through
# the neutral Estimator.feature_rows: x is a DataFrame (numeric
# columns only), a Matrix, an array of row arrays, or a flat
# single-feature array. nil cells are NOT handled — run an Imputer
# first. fit returns nil (and fitted? stays false) for an empty x, a
# ragged x, k < 1, or fewer rows than clusters (k > n); predict / score
# return nil before a successful fit and when a query row's width
# differs from the fitted feature count.
#
# NOTE: locals are hoisted from ivars before any `-> (x)` block — the
# interpreter cannot resolve @ivars from a block body — and methods
# containing closures avoid early `return` (see stats.w). Array `+`
# concatenation is avoided (it is unsupported); arrays are built with
# push.
+ KMeans
  is Estimable
  is UnsupervisedEstimator

  ro :k          # cluster count
  ro :seed       # init seed (nil = deterministic first-k-distinct init)
  ro :max_iter   # Lloyd iteration cap (sklearn's 300)
  ro :centroids  # k centroid rows (arrays of floats) after fit; nil before
  ro :labels     # cluster index per training row after fit; nil before
  ro :inertia    # within-cluster sum of squared distances; nil before fit
  ro :n_iter     # Lloyd iterations run to convergence; 0 before fit

  -> new(k = 8, seed = nil, max_iter = 300)
    @k = k
    @seed = seed
    @max_iter = max_iter
    @fitted = false
    @centroids = nil
    @labels = nil
    @inertia = nil
    @n_iter = 0

  -> fitted?
    @fitted

  # --- Estimable contract (see lib/estimator_base.w) ---

  -> estimator_name
    "KMeans"

  # koala's only UNSUPERVISED estimator: fit(x) / score(x), no labels.
  # Generic tooling must read this before calling fit — see
  # Estimator.fit_model / .score_model.
  -> supervised?
    false

  # The hyperparameters a search varies — never the learned centroids.
  -> params
    { k: @k, seed: @seed, max_iter: @max_iter }

  # A NEW, UNFITTED KMeans with `overrides` applied; self is left untouched.
  # Unmentioned keys carry over, so with_params(params) round-trips. An
  # explicit `{ seed: nil }` DOES clear the seed (key presence, not value,
  # decides), restoring the deterministic first-k-distinct init.
  -> with_params(overrides)
    KMeans.new(Estimator.opt(overrides, :k, @k), Estimator.opt(overrides, :seed, @seed), Estimator.opt(overrides, :max_iter, @max_iter))

  # Learn k centroids and the per-row cluster assignment from x. Returns
  # self, or nil — fitted? stays false — for unusable shapes (empty x,
  # ragged rows, k < 1, or fewer rows than clusters).
  -> fit(x)
    rows = Estimator.feature_rows(x)
    ok = rows != nil
    ok = rows.size > 0 if ok
    ok = @k >= 1 if ok
    ok = rows.size >= @k if ok
    ok = rows[0].size > 0 if ok
    if ok
      width0 = rows[0].size
      rows.each -> (r)
        ok = false if r.size != width0
    out = nil
    if ok
      kk = @k
      sd = @seed
      width = rows[0].size
      mi = @max_iter
      centers = KMeans.init_centroids(rows, kk, sd)
      labels = KMeans.assign_step(rows, centers)
      iters = 0
      converged = false
      mi.times -> (t)
        if !converged
          nc = KMeans.update_step(rows, labels, centers, kk, width)
          nl = KMeans.assign_step(rows, nc)
          centers = nc
          iters = iters + 1
          converged = true if KMeans.labels_equal(labels, nl)
          labels = nl
      total = 0.to_f
      idx = 0
      rows.each -> (r)
        lab = labels[idx]
        total += KMeans.sq_dist(r, centers[lab])
        idx += 1
      @centroids = centers
      @labels = labels
      @inertia = total
      @n_iter = iters
      @fitted = true
      out = self
    out

  # Cluster index (0..k-1) for each row of x. nil before fit, and nil
  # when a row's width differs from the fitted feature count.
  -> predict(x)
    rows = nil
    rows = Estimator.feature_rows(x) if @fitted
    out = nil
    if rows != nil
      cs = @centroids
      nf = cs[0].size
      ok = true
      rows.each -> (r)
        ok = false if r.size != nf
      if ok
        preds = []
        rows.each -> (r)
          preds.push(KMeans.assign_one(r, cs))
        out = preds
    out

  # Fit, then return the training-row cluster labels (nil if unfittable).
  -> fit_predict(x)
    r = self.fit(x)
    out = nil
    out = @labels if r != nil
    out

  # sklearn's KMeans.score: the NEGATED within-cluster sum of squares of
  # x under the fitted centroids (greater is better, 0 is perfect). nil
  # before fit or on a width mismatch.
  -> score(x)
    labs = self.predict(x)
    out = nil
    if labs != nil
      rows = Estimator.feature_rows(x)
      cs = @centroids
      total = 0.to_f
      idx = 0
      rows.each -> (r)
        lab = labs[idx]
        total += KMeans.sq_dist(r, cs[lab])
        idx += 1
      out = 0.to_f - total
    out

  # --- static helpers (no @ivars, so they are safe inside blocks) ---

  # Initial centroids: the first k DISTINCT rows of the (optionally
  # seed-shuffled) index order. A degenerate input with fewer than k
  # distinct rows falls back to filling from the order with repeats.
  -> .init_centroids(rows, k, seed)
    order = Splitter.indices(rows.size, seed)
    centers = []
    order.each -> (ix)
      pt = rows[ix]
      if centers.size < k
        dup = false
        centers.each -> (c)
          dup = true if KMeans.rows_equal(c, pt)
        centers.push(KMeans.to_floats(pt)) if !dup
    order.each -> (ix)
      centers.push(KMeans.to_floats(rows[ix])) if centers.size < k
    centers

  # Assign every row to its nearest centroid.
  -> .assign_step(rows, centers)
    labels = []
    rows.each -> (r)
      labels.push(KMeans.assign_one(r, centers))
    labels

  # Nearest-centroid index for one row; ties break to the lower index.
  -> .assign_one(row, centers)
    best = 0
    bestd = KMeans.sq_dist(row, centers[0])
    ci = 0
    centers.each -> (c)
      d = KMeans.sq_dist(row, c)
      if d < bestd
        bestd = d
        best = ci
      ci += 1
    best

  # Recompute each centroid as the mean of its assigned rows; an empty
  # cluster keeps its previous centroid.
  -> .update_step(rows, labels, centers, k, width)
    out = []
    k.times -> (c)
      cnt = 0
      acc = []
      width.times -> (w)
        acc.push(0.to_f)
      idx = 0
      rows.each -> (r)
        if labels[idx] == c
          cnt += 1
          w2 = 0
          r.each -> (v)
            acc[w2] = acc[w2] + v.to_f
            w2 += 1
        idx += 1
      if cnt > 0
        row = []
        cf = cnt.to_f
        width.times -> (w)
          row.push(acc[w] / cf)
        out.push(row)
      else
        out.push(centers[c])
    out

  # Squared Euclidean distance between two equal-width rows (float).
  -> .sq_dist(a, b)
    total = 0.to_f
    n = a.size
    n.times -> (i)
      d = a[i].to_f - b[i].to_f
      total += d * d
    total

  # Element-wise numeric equality (compared as floats).
  -> .rows_equal(a, b)
    same = true
    n = a.size
    same = false if b.size != n
    if same
      n.times -> (i)
        same = false if a[i].to_f != b[i].to_f
    same

  # Element-wise equality of two integer label arrays.
  -> .labels_equal(a, b)
    same = true
    n = a.size
    same = false if b.size != n
    if same
      n.times -> (i)
        same = false if a[i] != b[i]
    same

  # A row copied to floats.
  -> .to_floats(row)
    out = []
    row.each -> (v)
      out.push(v.to_f)
    out
