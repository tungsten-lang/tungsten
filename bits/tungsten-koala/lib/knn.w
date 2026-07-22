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
# Accepted shapes are the estimators' shared ones, coerced through the
# neutral Estimator.feature_rows / Estimator.target_values (one definition
# of every accepted input shape): x is a DataFrame (numeric columns only),
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
  is Estimable
  is SupervisedEstimator

  ro :k   # neighbour count

  -> new(k = 5)
    @k = k
    @fitted = false
    @train_rows = nil
    @train_labels = nil

  -> fitted?
    @fitted

  # --- Estimable contract (see lib/estimator_base.w) ---

  -> estimator_name
    "KNNClassifier"

  # Learns from features AND labels: fit(x, y) / score(x, y).
  -> supervised?
    true

  # NO — and it says so out loud. scikit-learn's KNeighborsClassifier has
  # no sample_weight either, and the reason is structural rather than an
  # omission: fit stores the training set unchanged, so there is nowhere
  # for a weight to be absorbed, and the only thing weights COULD touch is
  # the neighbour vote — which is a different algorithm (sklearn spells it
  # `weights=`, a hyperparameter over DISTANCE, not a per-row importance).
  # Silently ignoring a weight vector would hand back a model the caller
  # believes is weighted, so fit returns nil instead. `score` still takes
  # weights: a weighted accuracy is well defined however the labels arose.
  -> supports_sample_weight?
    false

  # The hyperparameters a search varies — never the stored training rows.
  -> params
    { k: @k }

  # A NEW, UNFITTED KNNClassifier with `overrides` applied; self is left
  # untouched. Unmentioned keys carry over, so with_params(params) round-trips.
  -> with_params(overrides)
    KNNClassifier.new(Estimator.opt(overrides, :k, @k))

  # Store the training rows and labels. Returns self, or nil — fitted?
  # stays false — when the shapes are unusable (empty x, ragged rows,
  # y size mismatch) or when a sample_weight is supplied at all.
  #
  # The weight argument exists ONLY so the refusal is explicit: k-NN
  # cannot honour per-row weights (see supports_sample_weight?), and a
  # nil fit is how this bit says "I will not answer that" — never a
  # silently unweighted model wearing a weighted caller's expectations.
  -> fit(x, y, sample_weight = nil)
    rows = Estimator.feature_rows(x)
    labels = Estimator.target_values(y)
    ok = rows != nil && labels != nil
    ok = rows.size > 0 && rows.size == labels.size if ok
    ok = rows[0].size > 0 if ok
    if ok
      width = rows[0].size
      rows.each -> (r)
        ok = false if r.size != width
    ok = false if sample_weight != nil
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
    rows = Estimator.feature_rows(x) if @fitted
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
  # nil before fit, when the shapes do not line up, or when sample_weight
  # is unusable. Weights ARE honoured here (a weighted accuracy needs
  # nothing from the model) even though fit refuses them.
  -> score(x, y, sample_weight = nil)
    preds = self.predict(x)
    yvals = Estimator.target_values(y)
    out = nil
    if preds != nil && yvals != nil
      ok = preds.size == yvals.size && preds.size > 0
      wts = nil
      wts = Estimator.weight_values(sample_weight, preds.size) if ok && sample_weight != nil
      ok = false if sample_weight != nil && wts == nil
      out = Metrics.accuracy(preds, yvals, wts) if ok
    out

  # --- Persistence (see lib/persist.w) ---

  -> persist_name
    "KNNClassifier"

  # A lazy learner's fitted state IS its training set, so that is what a
  # saved k-NN carries — there is nothing smaller that predicts the same.
  -> to_state
    { k: @k, train_rows: @train_rows, train_labels: @train_labels }

  -> .load_state(st)
    out = nil
    if st != nil && st[:k] != nil && st[:train_rows] != nil && st[:train_labels] != nil
      model = KNNClassifier.new(st[:k])
      out = model.restore_state(st)
    out

  -> restore_state(st)
    @train_rows = st[:train_rows]
    @train_labels = st[:train_labels]
    @fitted = true
    self
