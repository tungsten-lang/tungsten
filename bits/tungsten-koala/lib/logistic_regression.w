# LogisticRegression — binary logistic regression by batch gradient
# descent on the cross-entropy loss (pure Tungsten, CPU-only; koala's
# parametric probabilistic classifier — the companion to KNNClassifier's
# lazy classification and LinearRegression's regression: fit / predict /
# predict_proba / score with per-instance fitted state, sklearn-style)
#
#     model = LogisticRegression.new            # lr = 0.1, 1000 epochs
#     model = LogisticRegression.new(1, 500)    # learning rate 1, 500 epochs
#     model.fit(x, y)            # self when fitted, nil when unfittable
#     model.coefficients         # per-feature weights (array of floats)
#     model.intercept            # bias term (float)
#     model.classes              # the two labels, first-seen order [c0, c1]
#     model.predict_proba(x)     # array of P(class = classes[1]) in (0, 1)
#     model.predict(x)           # array of predicted labels (classes[0/1])
#     model.score(x, y)          # accuracy of predict(x) against y
#
# fit learns weights w and bias b minimizing the mean cross-entropy of
# sigmoid(w·x + b) against 0/1 targets, by full-batch gradient descent:
# for each epoch the gradient of the loss is mean((p - t) * x) in the
# weights and mean(p - t) in the bias (p = sigmoid, t = target), and the
# parameters step by -learning_rate * gradient. Weights start at zero, so
# with sigmoid(0) = 0.5 the first epoch is exact: on x = [[0], [1]],
# y = [0, 1] with learning_rate 1 and one epoch the gradient in w is
# (0.5·0 + (0.5 - 1)·1) / 2 = -0.25, giving w = [0.25], b = 0 — no
# transcendental in the first step, so it is hand-verifiable.
#
# Labels are binary and OPAQUE: fit collects the distinct labels in
# first-seen order (Array#sort is not portable across engines — the
# Encoder / ConfusionMatrix convention) and requires EXACTLY two; the
# first-seen label maps to target 0, the second to target 1. predict
# returns those original labels (P >= 0.5 -> classes[1], else classes[0],
# scikit-learn's threshold), and predict_proba returns P(classes[1]), so
# a LogisticRegression feeds directly into Metrics.accuracy / precision /
# recall / f1 exactly like KNNClassifier. A y with one distinct label, or
# three or more, makes fit return nil and fitted? stay false.
#
# Accepted shapes are the estimators' shared ones, coerced through the
# neutral Estimator.feature_rows / .target_values: x is a DataFrame
# (numeric columns only), a Matrix, an array of row arrays, or a flat
# single-feature array; y is a Series, a Vector, or a plain array of
# labels. nil cells are NOT handled — run an Imputer first. An empty x,
# a ragged x, or a y whose size mismatches makes fit return nil; predict
# / predict_proba / score return nil before a successful fit and when a
# query row's width differs from the fitted feature count.
#
# The sigmoid argument is clamped to [-30, 30] so exp never overflows;
# the result stays strictly in (0, 1) and the classifier is deterministic
# on both engines (Math.exp / Math.log agree bit-for-bit — verified).
#
# NOTE: every float derives from the data via .to_f. A bare decimal
# literal is a Decimal and does not coerce with Float, so the default
# learning rate is built as 1.to_f / 10.to_f and a caller wanting a
# fractional rate must derive it the same way
# (`LogisticRegression.new(1.to_f / 10.to_f)`).
+ LogisticRegression
  is Estimable
  is SupervisedEstimator

  ro :coefficients   # per-feature weights after a successful fit; nil before
  ro :intercept      # bias term after a successful fit; nil before
  ro :classes        # the two labels, first-seen order; nil before fit
  ro :learning_rate  # gradient-descent step size
  ro :epochs         # number of full-batch gradient-descent passes

  -> new(learning_rate = nil, epochs = 1000)
    lr = learning_rate
    lr = 1.to_f / 10.to_f if lr == nil
    @learning_rate = lr
    @epochs = epochs
    @fitted = false
    @coefficients = nil
    @intercept = nil
    @classes = nil

  -> fitted?
    @fitted

  # --- Estimable contract (see lib/estimator_base.w) ---

  -> estimator_name
    "LogisticRegression"

  # Learns from features AND labels: fit(x, y) / score(x, y).
  -> supervised?
    true

  # The gradient is a SUM over rows, so a weight is just that row's
  # multiplier in it — see fit.
  -> supports_sample_weight?
    true

  # The hyperparameters a search varies — never the learned weights.
  -> params
    { learning_rate: @learning_rate, epochs: @epochs }

  # A NEW, UNFITTED LogisticRegression with `overrides` applied; self is left
  # untouched. Unmentioned keys carry over, so with_params(params) round-trips.
  -> with_params(overrides)
    LogisticRegression.new(Estimator.opt(overrides, :learning_rate, @learning_rate), Estimator.opt(overrides, :epochs, @epochs))

  # Sigmoid 1 / (1 + e^-z), with z clamped to [-30, 30] so e^-z cannot
  # overflow; the output is strictly inside (0, 1).
  -> .sigmoid(z)
    lim = 30.to_f
    zc = z.to_f
    zc = 0.to_f - lim if zc < 0.to_f - lim
    zc = lim if zc > lim
    1.to_f / (1.to_f + Math.exp(0.to_f - zc))

  # Bias plus the weight·row dot product (float).
  -> .dot_plus(weights, row, bias)
    total = bias.to_f
    n = weights.size
    n.times -> (j)
      total += weights[j].to_f * row[j].to_f
    total

  # P(class = classes[1]) for every row under weights / bias.
  -> .predict_probs(weights, bias, rows)
    probs = []
    rows.each -> (r)
      z = LogisticRegression.dot_plus(weights, r, bias)
      probs.push(LogisticRegression.sigmoid(z))
    probs

  # Sum of a float array (Stats.sum accumulates as an integer), weighted
  # per element when `wts` is given: the bias gradient.
  #
  # The weight multiplies the FINISHED per-row term (`(e) * w`, not
  # `(w * e)`), so an integer weight of 2 gives bit-for-bit the same
  # double as adding that row's term twice — which is what makes the
  # duplication equivalence exact rather than merely close.
  -> .sum_f(values, wts = nil)
    total = 0.to_f
    i = 0
    values.each -> (v)
      if wts == nil
        total += v
      else
        total += v * wts[i]
      i += 1
    total

  # Per-feature gradient sum: gw[j] = sum_i w_i * errors[i] * rows[i][j]
  # (w_i = 1 unweighted).
  -> .gradient_w(errors, rows, nf, wts)
    gw = []
    nf.times -> (j)
      total = 0.to_f
      i = 0
      errors.each -> (e)
        if wts == nil
          total += e * rows[i][j].to_f
        else
          total += (e * rows[i][j].to_f) * wts[i]
        i += 1
      gw.push(total)
    gw

  # Learn weights and intercept from x/y by gradient descent. Returns
  # self, or nil — fitted? stays false — when the shapes are unusable
  # (empty x, ragged rows, y size mismatch, an unusable sample_weight) or
  # y is not exactly binary.
  #
  # SAMPLE WEIGHTS enter the one place they can: the loss is a SUM over
  # rows, so weighting it re-weights each row's contribution to the
  # gradient and nothing else —
  #
  #     gw[j] = sum_i w_i (p_i - t_i) x_ij      gb = sum_i w_i (p_i - t_i)
  #
  # divided by sum(w) rather than n. Everything else — the epoch count,
  # the learning rate, the zero start, the clamp — is untouched, so a
  # weighted run takes exactly the same trajectory a run on the
  # row-duplicated dataset would, epoch for epoch. A zero-weight row is
  # dropped up front (it would contribute nothing but would still shift
  # the first-seen class order, which decides which label is target 1).
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
    wts = nil
    wts = Estimator.weight_values(sample_weight, rows.size) if ok && sample_weight != nil
    ok = false if sample_weight != nil && wts == nil
    if ok && wts != nil
      trimmed = Estimator.drop_zero_weights(rows, labels, wts)
      rows = trimmed[:rows]
      labels = trimmed[:targets]
      wts = trimmed[:weights]
    classes = []
    if ok
      labels.each -> (l)
        classes.push(l) if !classes.include?(l)
      ok = false if classes.size != 2
    out = nil
    if ok
      class1 = classes[1]
      targets = []
      labels.each -> (l)
        t = 0.to_f
        t = 1.to_f if l == class1
        targets.push(t)
      nf = rows[0].size
      n = rows.size
      nd = Estimator.weight_total(wts, n).to_f
      lr = @learning_rate
      steps = @epochs
      weights = []
      nf.times -> (j)
        weights.push(0.to_f)
      bias = 0.to_f
      steps.times -> (e)
        probs = LogisticRegression.predict_probs(weights, bias, rows)
        errors = []
        i = 0
        probs.each -> (p)
          errors.push(p - targets[i])
          i += 1
        gw = LogisticRegression.gradient_w(errors, rows, nf, wts)
        gb = LogisticRegression.sum_f(errors, wts)
        new_w = []
        nf.times -> (j)
          new_w.push(weights[j] - lr * (gw[j] / nd))
        weights = new_w
        bias = bias - lr * (gb / nd)
      @coefficients = weights
      @intercept = bias
      @classes = classes
      @fitted = true
      out = self
    out

  # P(class = classes[1]) for every row of x as a plain array of floats;
  # nil before fit, and nil when x's rows do not match the fitted feature
  # count.
  -> predict_proba(x)
    rows = nil
    rows = Estimator.feature_rows(x) if @fitted
    out = nil
    if rows != nil
      weights = @coefficients
      bias = @intercept
      nf = weights.size
      ok = true
      rows.each -> (r)
        ok = false if r.size != nf
      if ok
        out = LogisticRegression.predict_probs(weights, bias, rows)
    out

  # Predicted labels for x: classes[1] when P >= 0.5, else classes[0].
  # nil before fit or on a width mismatch (predict_proba returns nil).
  -> predict(x)
    probs = self.predict_proba(x)
    out = nil
    if probs != nil
      classes = @classes
      c0 = classes[0]
      c1 = classes[1]
      half = 1.to_f / 2.to_f
      preds = []
      probs.each -> (p)
        if p < half
          preds.push(c0)
        else
          preds.push(c1)
      out = preds
    out

  # Accuracy (Metrics.accuracy) of self's predictions on x against y,
  # weighted when sample_weight is given; nil before fit, when the shapes
  # do not line up, or when the weights are unusable.
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
    "LogisticRegression"

  # `classes` rides along with the weights: the label a probability maps
  # to is learned state, not a knob, and a model that lost it would
  # predict 0/1 instead of what it was trained on.
  -> to_state
    { learning_rate: @learning_rate, epochs: @epochs, coefficients: @coefficients, intercept: @intercept, classes: @classes }

  -> .load_state(st)
    out = nil
    ok = st != nil
    ok = st[:learning_rate] != nil && st[:epochs] != nil if ok
    ok = st[:coefficients] != nil && st[:intercept] != nil && st[:classes] != nil if ok
    if ok
      model = LogisticRegression.new(st[:learning_rate], st[:epochs])
      out = model.restore_state(st)
    out

  -> restore_state(st)
    @coefficients = st[:coefficients]
    @intercept = st[:intercept]
    @classes = st[:classes]
    @fitted = true
    self
