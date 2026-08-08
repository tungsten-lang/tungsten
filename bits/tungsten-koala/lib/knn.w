# KNNClassifier — k-nearest-neighbors classification (pure Tungsten,
# CPU-only; koala's first CLASSIFIER, the companion to LinearRegression's
# regression: fit / predict / score with per-instance fitted state,
# sklearn-style, and the natural producer of labels for Metrics.accuracy
# / precision / recall / f1)
#
#     model = KNNClassifier.new                    # k = 5, :uniform
#     model = KNNClassifier.new(3, :distance)      # inverse-distance vote
#     model.fit(x, y)          # self when fitted, nil when unfittable
#     model.predict(x)         # plain array of predicted labels
#     model.predict_proba(x)   # probability rows in model.classes order
#     model.score(x, y)        # accuracy of predict(x) against y
#
# A lazy learner: fit just stores the training rows and their labels;
# all the work is in predict. For each query row predict finds the k
# training rows with the smallest (squared) Euclidean distance and
# returns the majority label among them. `:distance` weights each vote by
# inverse Euclidean distance; when any neighbour is an exact match, only
# exact matches vote (sklearn's zero-distance rule). A vote tie breaks to
# the closer neighbour, then to the earlier training row. Labels are opaque
# — integers, strings, or symbols all vote — and `classes` preserves their
# first-seen order.
#
# Neighbour ordering uses SQUARED Euclidean distance: sqrt is monotonic,
# so squaring keeps integer inputs exact (no float rounding to perturb a
# tie). `:distance` takes sqrt only when calculating vote weight. Distance
# ties break to the lower training index (a strict `<` keeps the
# first-seen minimum), matching scikit-learn's stable neighbour order.
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
# NOTE: every float here derives from the data via .to_f — a bare decimal
# literal is a Decimal and does not coerce with Float.
+ KNNClassifier
  is Estimable
  is SupervisedEstimator

  ro :k   # neighbour count
  ro :weight_kind   # :uniform or :distance
  ro :classes       # first-seen label order

  -> new(k = 5, weight_kind = :uniform)
    @k = k
    @weight_kind = weight_kind
    @fitted = false
    @train_rows = nil
    @train_labels = nil
    @classes = nil

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
    { k: @k, weight_kind: @weight_kind }

  # A NEW, UNFITTED KNNClassifier with `overrides` applied; self is left
  # untouched. Unmentioned keys carry over, so with_params(params) round-trips.
  -> with_params(overrides)
    KNNClassifier.new(
      Estimator.opt(overrides, :k, @k),
      Estimator.opt(overrides, :weight_kind, @weight_kind)
    )

  # Store the training rows and labels. Returns self, or nil — fitted?
  # stays false — when the shapes are unusable (empty x, ragged rows,
  # y size mismatch) or when a sample_weight is supplied at all.
  #
  # The weight argument exists ONLY so the refusal is explicit: k-NN
  # cannot honour per-row weights (see supports_sample_weight?), and a
  # nil fit is how this bit says "I will not answer that" — never a
  # silently unweighted model wearing a weighted caller's expectations.
  -> fit(x, y, sample_weight = nil)
    @fitted = false
    @train_rows = nil
    @train_labels = nil
    @classes = nil
    rows = Estimator.feature_rows(x)
    labels = Estimator.target_values(y)
    ok = rows != nil && labels != nil
    ok = rows.size > 0 && rows.size == labels.size if ok
    ok = KNNClassifier.numeric_rows?(rows) if ok
    ok = type(@k) == "Integer" if ok
    ok = @k > 0 if ok
    ok = @weight_kind == :uniform || @weight_kind == :distance if ok
    classes = []
    if ok
      labels.each -> (label)
        ok = false if label == nil
        classes.push(label) if label != nil && !classes.include?(label)
    ok = false if sample_weight != nil
    out = nil
    if ok
      @train_rows = rows
      @train_labels = labels
      @classes = classes
      @fitted = true
      out = self
    out

  # A rectangular, entirely numeric feature block.
  -> .numeric_rows?(rows, allow_empty = false)
    ok = rows != nil
    ok = rows.size > 0 if ok && !allow_empty
    width = 0
    if ok && rows.size > 0
      ok = type(rows[0]) == "Array"
      width = rows[0].size if ok
      ok = width > 0 if ok
    if ok
      rows.each -> (row)
        ok = false if type(row) != "Array"
        if type(row) == "Array"
          ok = false if row.size != width
          row.each -> (value)
            kind = type(value)
            ok = false if kind != "Integer" && kind != "Float"
    ok

  # Squared Euclidean distance between two equal-width rows (float).
  -> .sq_dist(a, b)
    total = 0.to_f
    n = a.size
    n.times -> (i)
      d = a[i].to_f - b[i].to_f
      total += d * d
    total

  -> .class_index(classes, label)
    out = -1
    i = 0
    classes.each -> (candidate)
      out = i if candidate == label
      i += 1
    out

  # The selected training indices and their squared distances, nearest-first.
  # A Boolean membership mask keeps the selection sweep O(training rows * k)
  # after distances are computed; strict improvement preserves index-order ties.
  -> neighbors(row)
    trows = @train_rows
    limit = @k
    limit = trows.size if trows.size < @k
    dists = []
    trows.each -> (tr)
      dists.push(KNNClassifier.sq_dist(row, tr))
    used = []
    trows.each -> (tr)
      used.push(false)
    chosen = []
    picked_d = []
    limit.times -> (c)
      best = -1
      bestv = 0.to_f
      i = 0
      dists.each -> (d)
        if !used[i]
          if best == -1 || d < bestv
            best = i
            bestv = d
        i += 1
      used[best] = true
      chosen.push(best)
      picked_d.push(bestv)
    { indices: chosen, distances: picked_d }

  # One query's weighted vote and normalized class probabilities.
  -> vote(row)
    near = self.neighbors(row)
    chosen = near[:indices]
    dists = near[:distances]
    zero_only = false
    if @weight_kind == :distance
      dists.each -> (d)
        zero_only = true if d == 0.to_f
    scores = []
    @classes.each -> (label)
      scores.push(0.to_f)
    tie_order = []
    i = 0
    chosen.each -> (idx)
      d = dists[i]
      active = true
      active = false if zero_only && d != 0.to_f
      if active
        class_i = KNNClassifier.class_index(@classes, @train_labels[idx])
        tie_order.push(class_i) if !tie_order.include?(class_i)
        weight = 1.to_f
        if @weight_kind == :distance && !zero_only
          weight = 1.to_f / Math.sqrt(d)
        scores[class_i] += weight
      i += 1
    total = 0.to_f
    scores.each -> (score)
      total += score
    probabilities = []
    scores.each -> (score)
      probabilities.push(score / total)
    best = tie_order[0]
    tie_order.each -> (class_i)
      best = class_i if scores[class_i] > scores[best]
    { label: @classes[best], probabilities: probabilities }

  # Predicted label for a single feature row.
  -> predict_one(row)
    self.vote(row)[:label]

  # Predicted labels for x as a plain array. nil before fit, and nil
  # when x's rows do not match the fitted feature count.
  -> predict(x)
    rows = nil
    rows = Estimator.feature_rows(x) if @fitted
    out = nil
    if rows != nil && KNNClassifier.numeric_rows?(rows, true)
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

  # Probability rows in first-seen `classes` order. Supplying a label
  # requests its flat probability column, matching koala's other
  # probabilistic classifiers.
  -> predict_proba(x, label = nil)
    rows = nil
    rows = Estimator.feature_rows(x) if @fitted
    out = nil
    if rows != nil && KNNClassifier.numeric_rows?(rows, true)
      nf = @train_rows[0].size
      ok = true
      rows.each -> (row)
        ok = false if row.size != nf
      class_i = -1
      class_i = KNNClassifier.class_index(@classes, label) if label != nil
      ok = false if label != nil && class_i == -1
      if ok
        probabilities = []
        rows.each -> (row)
          p = self.vote(row)[:probabilities]
          if label == nil
            probabilities.push(p)
          else
            probabilities.push(p[class_i])
        out = probabilities
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
    {
      k: @k,
      weight_kind: @weight_kind,
      train_rows: @train_rows,
      train_labels: @train_labels,
      classes: @classes
    }

  -> .load_state(st)
    out = nil
    ok = st != nil && type(st) == "Hash"
    ok = st[:k] != nil if ok
    ok = st[:train_rows] != nil && st[:train_labels] != nil if ok
    ok = type(st[:k]) == "Integer" && st[:k] > 0 if ok
    kind = st[:weight_kind]
    kind = :uniform if kind == nil
    ok = kind == :uniform || kind == :distance if ok
    ok = KNNClassifier.numeric_rows?(st[:train_rows]) if ok
    ok = type(st[:train_labels]) == "Array" if ok
    ok = st[:train_rows].size == st[:train_labels].size if ok
    expected = []
    if ok
      st[:train_labels].each -> (label)
        ok = false if label == nil
        expected.push(label) if label != nil && !expected.include?(label)
    classes = st[:classes]
    classes = expected if classes == nil
    ok = type(classes) == "Array" if ok
    if ok
      ok = expected.size == classes.size
      if ok
        i = 0
        while i < expected.size
          ok = false if expected[i] != classes[i]
          i += 1
    if ok
      model = KNNClassifier.new(st[:k], kind)
      state = {
        k: st[:k],
        weight_kind: kind,
        train_rows: st[:train_rows],
        train_labels: st[:train_labels],
        classes: classes
      }
      out = model.restore_state(state)
    out

  -> restore_state(st)
    @train_rows = st[:train_rows]
    @train_labels = st[:train_labels]
    @classes = st[:classes]
    @fitted = true
    self
