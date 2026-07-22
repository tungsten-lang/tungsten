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

  # A centroid is a MEAN and inertia is a SUM, so both have exact
  # weighted forms — see fit.
  -> supports_sample_weight?
    true

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
  # ragged rows, k < 1, fewer rows than clusters, or an unusable
  # sample_weight).
  #
  # SAMPLE WEIGHTS touch the two places k-means adds things up: a centroid
  # becomes the WEIGHTED mean of its assigned rows, and inertia the
  # weighted sum of squared distances. The ASSIGN step is untouched — a
  # row's nearest centroid does not depend on how much that row counts —
  # so Lloyd's convergence argument survives unchanged.
  #
  # Zero-weight rows are NOT dropped here (unlike the supervised
  # estimators): `labels` is documented as one entry per input row, and
  # silently shortening it would be a worse surprise than carrying a row
  # that contributes nothing. Instead they are excluded where their
  # presence would actually change the answer — they never SEED a
  # centroid (init_centroids skips them, so a weighted fit initializes
  # exactly as the row-duplicated one does) and they add nothing to a
  # centroid mean or to inertia. They are still assigned a label, which is
  # simply "the cluster this row would belong to".
  -> fit(x, sample_weight = nil)
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
    wts = nil
    wts = Estimator.weight_values(sample_weight, rows.size) if ok && sample_weight != nil
    ok = false if sample_weight != nil && wts == nil
    if ok && wts != nil
      # k clusters need k rows that are actually IN the sample.
      positive = 0
      wts.each -> (v)
        positive += 1 if v > 0.to_f
      ok = false if positive < @k
    out = nil
    if ok
      kk = @k
      sd = @seed
      width = rows[0].size
      mi = @max_iter
      centers = KMeans.init_centroids(rows, kk, sd, wts)
      labels = KMeans.assign_step(rows, centers)
      iters = 0
      converged = false
      mi.times -> (t)
        if !converged
          nc = KMeans.update_step(rows, labels, centers, kk, width, wts)
          nl = KMeans.assign_step(rows, nc)
          centers = nc
          iters = iters + 1
          converged = true if KMeans.labels_equal(labels, nl)
          labels = nl
      total = KMeans.inertia_of(rows, labels, centers, wts)
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
  # x under the fitted centroids (greater is better, 0 is perfect), each
  # row's contribution scaled by its weight when sample_weight is given.
  # nil before fit, on a width mismatch, or for an unusable weight vector.
  -> score(x, sample_weight = nil)
    labs = self.predict(x)
    out = nil
    if labs != nil
      rows = Estimator.feature_rows(x)
      ok = true
      wts = nil
      wts = Estimator.weight_values(sample_weight, rows.size) if sample_weight != nil
      ok = false if sample_weight != nil && wts == nil
      out = 0.to_f - KMeans.inertia_of(rows, labs, @centroids, wts) if ok
    out

  # --- static helpers (no @ivars, so they are safe inside blocks) ---

  # The within-cluster sum of squared distances of `rows` to their
  # assigned centroids, each term scaled by that row's weight (1 when
  # `wts` is nil). Shared by fit's `inertia` and score.
  -> .inertia_of(rows, labels, centers, wts)
    total = 0.to_f
    idx = 0
    rows.each -> (r)
      wt = 1.to_f
      wt = wts[idx] if wts != nil
      total += KMeans.sq_dist(r, centers[labels[idx]]) * wt
      idx += 1
    total

  # Initial centroids: the first k DISTINCT rows of the (optionally
  # seed-shuffled) index order, skipping any row whose weight is zero —
  # such a row is not in the sample, so it must not seed a cluster, and
  # skipping it is what makes a weighted init identical to the
  # row-duplicated one. A degenerate input with fewer than k distinct rows
  # falls back to filling from the order with repeats.
  -> .init_centroids(rows, k, seed, wts)
    order = Splitter.indices(rows.size, seed)
    centers = []
    order.each -> (ix)
      pt = rows[ix]
      live = true
      live = wts[ix] > 0.to_f if wts != nil
      if centers.size < k && live
        dup = false
        centers.each -> (c)
          dup = true if KMeans.rows_equal(c, pt)
        centers.push(KMeans.to_floats(pt)) if !dup
    order.each -> (ix)
      spare = true
      spare = wts[ix] > 0.to_f if wts != nil
      centers.push(KMeans.to_floats(rows[ix])) if centers.size < k && spare
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

  # Recompute each centroid as the WEIGHTED mean of its assigned rows (a
  # weight of 1 multiplies exactly, so this is the plain mean when `wts`
  # is nil); a cluster holding no weight at all keeps its previous
  # centroid.
  -> .update_step(rows, labels, centers, k, width, wts)
    out = []
    k.times -> (c)
      cnt = 0.to_f
      acc = []
      width.times -> (w)
        acc.push(0.to_f)
      idx = 0
      rows.each -> (r)
        if labels[idx] == c
          wt = 1.to_f
          wt = wts[idx] if wts != nil
          cnt += wt
          w2 = 0
          r.each -> (v)
            acc[w2] = acc[w2] + v.to_f * wt
            w2 += 1
        idx += 1
      if cnt > 0.to_f
        row = []
        width.times -> (w)
          row.push(acc[w] / cnt)
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
