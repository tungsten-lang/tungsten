# KNNClassifier — k-nearest-neighbors classification (pure Tungsten,
# CPU-only; koala's first CLASSIFIER, the companion to LinearRegression's
# regression: fit / predict / score with per-instance fitted state,
# sklearn-style, and the natural producer of labels for Metrics.accuracy
# / precision / recall / f1)
#
#     model = KNNClassifier.new       # k = 5 (sklearn's default)
#     model = KNNClassifier.new(3)    # k = 3
#     model.fit(x, y)          # self when fitted, nil when unfittable
#     model.predict(x)         # plain array of predicted labels
#     model.score(x, y)        # accuracy of predict(x) against y
#
# A lazy learner: fit just stores the training rows and their labels;
# all the work is in predict. For each query row predict finds the k
# training rows with the smallest (squared) Euclidean distance and
# returns the majority label among them (Stats.mode over the neighbours
# in nearest-first order, so a vote tie breaks to the closer neighbour,
# then to the earlier training row). Labels are opaque — integers,
# strings, or symbols all vote — so a KNNClassifier feeds directly into
# Metrics.accuracy and the binary precision / recall / f1 metrics.
#
# Distance is SQUARED Euclidean: sqrt is monotonic, so squaring gives
# the identical neighbour ordering while keeping integer inputs exact
# (no float rounding to perturb a tie). Distance ties break to the
# lower training index (a strict `<` keeps the first-seen minimum),
# matching scikit-learn's stable neighbour order.
#
# Accepted shapes are exactly LinearRegression's, coerced through the
# same LinearRegression.feature_rows / .target_values (one definition of
# every accepted input shape): x is a DataFrame (numeric columns only),
# a Matrix, an array of row arrays, or a flat single-feature array; y is
# a Series, a Vector, or a plain array of labels. nil cells are NOT
# handled — run an Imputer first. An empty x, a ragged x, or a y whose
# size mismatches makes fit return nil and fitted? stay false; predict /
# score return nil before a successful fit and when a query row's width
# differs from the fitted feature count.
#
# NOTE: locals are hoisted from ivars before any `-> (x)` block — the
# interpreter cannot resolve @ivars from a block body — and methods
# containing closures avoid early `return` (see stats.w). No float
# literals appear here: every float derives from the data via .to_f.
+ KNNClassifier
  ro :k   # neighbour count

  -> new(k = 5)
    @k = k
    @fitted = false
    @train_rows = nil
    @train_labels = nil

  -> fitted?
    @fitted

  # Store the training rows and labels. Returns self, or nil — fitted?
  # stays false — when the shapes are unusable (empty x, ragged rows,
  # y size mismatch).
  -> fit(x, y)
    rows = LinearRegression.feature_rows(x)
    labels = LinearRegression.target_values(y)
    ok = rows != nil && labels != nil
    ok = rows.size > 0 && rows.size == labels.size if ok
    ok = rows[0].size > 0 if ok
    if ok
      width = rows[0].size
      rows.each -> (r)
        ok = false if r.size != width
    out = nil
    if ok
      @train_rows = rows
      @train_labels = labels
      @fitted = true
      out = self
    out

  # Squared Euclidean distance between two equal-width rows (float).
  -> .sq_dist(a, b)
    total = 0.to_f
    n = a.size
    n.times -> (i)
      d = a[i].to_f - b[i].to_f
      total += d * d
    total

  # Predicted label for a single feature row: the majority vote over the
  # k nearest training rows (nearest-first, so Stats.mode breaks ties to
  # the closer neighbour).
  -> predict_one(row)
    trows = @train_rows
    tlabels = @train_labels
    limit = @k
    limit = trows.size if trows.size < @k
    dists = []
    trows.each -> (tr)
      dists.push(KNNClassifier.sq_dist(row, tr))
    chosen = []
    limit.times -> (c)
      best = -1
      bestv = 0.to_f
      i = 0
      dists.each -> (d)
        if !chosen.include?(i)
          if best == -1 || d < bestv
            best = i
            bestv = d
        i += 1
      chosen.push(best)
    votes = []
    chosen.each -> (idx)
      votes.push(tlabels[idx])
    Stats.mode(votes)

  # Predicted labels for x as a plain array. nil before fit, and nil
  # when x's rows do not match the fitted feature count.
  -> predict(x)
    rows = nil
    rows = LinearRegression.feature_rows(x) if @fitted
    out = nil
    if rows != nil
      nf = @train_rows[0].size
      ok = true
      rows.each -> (r)
        ok = false if r.size != nf
      if ok
        preds = []
        rows.each -> (r)
          preds.push(self.predict_one(r))
        out = preds
    out

  # Accuracy (Metrics.accuracy) of self's predictions on x against y;
  # nil before fit or when the shapes do not line up.
  -> score(x, y)
    preds = self.predict(x)
    yvals = LinearRegression.target_values(y)
    out = nil
    if preds != nil && yvals != nil
      out = Metrics.accuracy(preds, yvals) if preds.size == yvals.size && preds.size > 0
    out
