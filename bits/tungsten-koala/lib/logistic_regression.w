# LogisticRegression — binary sigmoid or multiclass softmax regression by
# batch gradient descent on cross-entropy (pure Tungsten, CPU-only; koala's
# parametric probabilistic classifier — the companion to KNNClassifier's
# lazy classification and LinearRegression's regression: fit / predict /
# predict_proba / score with per-instance fitted state, sklearn-style)
#
#     model = LogisticRegression.new            # lr = 0.1, 1000 epochs
#     model = LogisticRegression.new(1, 500)    # learning rate 1, 500 epochs
#     model.fit(x, y)            # self when fitted, nil when unfittable
#     model.coefficients         # binary: [feature]; multiclass: [class][feature]
#     model.intercept            # binary: float; multiclass: [class]
#     model.classes              # labels in first-seen order
#     model.predict_proba(x)     # binary: P(class[1]); multiclass: row vectors
#     model.predict_proba(x, c)  # flat P(class = c), binary or multiclass
#     model.predict(x)           # labels by threshold / softmax argmax
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
# Labels are OPAQUE and collected in first-seen order (Array#sort is not
# portable across engines — the Encoder / ConfusionMatrix convention).
# Two classes keep the original sigmoid optimizer and flat probability API
# bit-for-bit. Three or more use one weight vector per class and a stable
# softmax; predict_proba returns one probability row per sample, or a flat
# class column when a label is supplied. A one-class target is not a
# classification problem and fit returns nil.
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

  ro :coefficients   # binary [feature]; multiclass [class][feature]
  ro :intercept      # binary Float; multiclass [class]
  ro :classes        # labels in first-seen order; nil before fit
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

  # A rectangular, entirely numeric feature block. Fit and prediction use
  # the same guard so nil/string cells fail at the API boundary rather than
  # reaching `.to_f` midway through an optimization.
  -> .numeric_rows?(rows, allow_empty = false)
    ok = rows != nil
    ok = rows.size > 0 if ok && !allow_empty
    width = 0
    if ok && rows.size > 0
      ok = false if type(rows[0]) != "Array"
      width = rows[0].size if ok
      ok = false if width == 0
    if ok
      rows.each -> (row)
        ok = false if type(row) != "Array"
        if type(row) == "Array"
          ok = false if row.size != width
          row.each -> (value)
            kind = type(value)
            ok = false if kind != "Int" && kind != "Float"
    ok

  # Numerically stable softmax for one row: subtracting the largest logit
  # makes every exponent <= 1 and leaves the probabilities unchanged.
  -> .softmax_row(weights, biases, row)
    logits = []
    c = 0
    while c < weights.size
      logits.push(LogisticRegression.dot_plus(weights[c], row, biases[c]))
      c += 1
    largest = logits[0]
    c = 1
    while c < logits.size
      largest = logits[c] if logits[c] > largest
      c += 1
    exps = []
    total = 0.to_f
    c = 0
    while c < logits.size
      shifted = logits[c] - largest
      value = Math.exp(shifted)
      exps.push(value)
      total += value
      c += 1
    probs = []
    c = 0
    while c < exps.size
      probs.push(exps[c] / total)
      c += 1
    probs

  -> .softmax_rows(weights, biases, rows)
    out = []
    rows.each -> (row)
      out.push(LogisticRegression.softmax_row(weights, biases, row))
    out

  # Learn weights and intercept from x/y by gradient descent. Returns
  # self, or nil — fitted? stays false — when the shapes are unusable
  # (empty x, ragged rows, y size mismatch, an unusable sample_weight) or
  # y has fewer than two distinct classes.
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
  # first-seen probability-column and tie-break order).
  -> fit(x, y, sample_weight = nil)
    @fitted = false
    @coefficients = nil
    @intercept = nil
    @classes = nil
    rows = Estimator.feature_rows(x)
    labels = Estimator.target_values(y)
    ok = rows != nil && labels != nil
    ok = rows.size > 0 && rows.size == labels.size if ok
    ok = LogisticRegression.numeric_rows?(rows) if ok
    if ok
      rate_kind = type(@learning_rate)
      ok = false if rate_kind != "Int" && rate_kind != "Float"
      ok = false if @learning_rate.to_f <= 0.to_f
      ok = false if type(@epochs) != "Int" || @epochs < 1
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
      ok = false if classes.size < 2
    out = nil
    if ok
      nf = rows[0].size
      n = rows.size
      nd = Estimator.weight_total(wts, n).to_f
      lr = @learning_rate
      steps = @epochs
      if classes.size == 2
        # Compatibility path: retain the original binary arithmetic and
        # flat probability API exactly.
        class1 = classes[1]
        targets = []
        labels.each -> (l)
          t = 0.to_f
          t = 1.to_f if l == class1
          targets.push(t)
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
      else
        # Multinomial cross-entropy. Every class gets its own linear logit;
        # softmax couples them, and all class gradients are computed from
        # the same pre-update probability matrix each epoch.
        weights = []
        biases = []
        classes.each -> (label)
          row_weights = []
          nf.times -> (j)
            row_weights.push(0.to_f)
          weights.push(row_weights)
          biases.push(0.to_f)
        epoch = 0
        while epoch < steps
          # Accumulate every class gradient in one row-major pass. This is
          # the same batch gradient as materializing an n-by-k probability
          # matrix and rescanning it once per feature, without those large
          # transient arrays — important on the interpreter and on wide
          # multiclass tables.
          gradient_weights = []
          gradient_biases = []
          c = 0
          while c < classes.size
            gradient_row = []
            j = 0
            while j < nf
              gradient_row.push(0.to_f)
              j += 1
            gradient_weights.push(gradient_row)
            gradient_biases.push(0.to_f)
            c += 1
          i = 0
          while i < rows.size
            probability_row = LogisticRegression.softmax_row(weights, biases, rows[i])
            wt = 1.to_f
            wt = wts[i] if wts != nil
            c = 0
            while c < classes.size
              target = 0.to_f
              target = 1.to_f if labels[i] == classes[c]
              error = probability_row[c] - target
              gradient_biases[c] += error * wt
              j = 0
              while j < nf
                gradient_weights[c][j] += (error * rows[i][j].to_f) * wt
                j += 1
              c += 1
            i += 1
          next_weights = []
          next_biases = []
          c = 0
          while c < classes.size
            updated = []
            j = 0
            while j < nf
              updated.push(weights[c][j] - lr * (gradient_weights[c][j] / nd))
              j += 1
            next_weights.push(updated)
            next_biases.push(biases[c] - lr * (gradient_biases[c] / nd))
            c += 1
          weights = next_weights
          biases = next_biases
          epoch += 1
        @coefficients = weights
        @intercept = biases
      @classes = classes
      @fitted = true
      out = self
    out

  # One probability vector per row in classes order, for both binary and
  # multiclass fits.
  -> predict_proba_matrix(x)
    rows = nil
    rows = Estimator.feature_rows(x) if @fitted
    out = nil
    if rows != nil && LogisticRegression.numeric_rows?(rows, true)
      nf = @coefficients.size
      nf = @coefficients[0].size if @classes.size > 2
      ok = rows.size == 0
      ok = rows[0].size == nf if rows.size > 0
      if ok
        if @classes.size == 2
          positive = LogisticRegression.predict_probs(@coefficients, @intercept, rows)
          matrix = []
          positive.each -> (p)
            matrix.push([1.to_f - p, p])
          out = matrix
        else
          out = LogisticRegression.softmax_rows(@coefficients, @intercept, rows)
    out

  # Backwards compatibility: on a binary fit and with no label, return the
  # original flat P(classes[1]) array. Multiclass returns the full matrix.
  # Supplying a label returns that class's flat column in either mode.
  -> predict_proba(x, label = nil)
    matrix = self.predict_proba_matrix(x)
    out = nil
    if matrix != nil
      picked = 0 - 1
      if label != nil
        i = 0
        @classes.each -> (candidate)
          picked = i if candidate == label
          i += 1
      else
        picked = 1 if @classes.size == 2
      if picked >= 0
        column = []
        matrix.each -> (row)
          column.push(row[picked])
        out = column
      else
        out = matrix if label == nil
    out

  # Raw linear scores before sigmoid/softmax. Binary returns one score per
  # row; multiclass returns one score row per sample in classes order.
  -> decision_function(x)
    rows = nil
    rows = Estimator.feature_rows(x) if @fitted
    out = nil
    if rows != nil && LogisticRegression.numeric_rows?(rows, true)
      nf = @coefficients.size
      nf = @coefficients[0].size if @classes.size > 2
      ok = rows.size == 0
      ok = rows[0].size == nf if rows.size > 0
      if ok
        scores = []
        rows.each -> (row)
          if @classes.size == 2
            scores.push(LogisticRegression.dot_plus(@coefficients, row, @intercept))
          else
            class_scores = []
            c = 0
            while c < @classes.size
              class_scores.push(LogisticRegression.dot_plus(@coefficients[c], row, @intercept[c]))
              c += 1
            scores.push(class_scores)
        out = scores
    out

  # Predicted labels: binary threshold at P(class[1]) >= 0.5; multiclass
  # softmax argmax with first-seen class order breaking exact ties.
  -> predict(x)
    probs = self.predict_proba_matrix(x)
    out = nil
    if probs != nil
      preds = []
      if @classes.size == 2
        half = 1.to_f / 2.to_f
        probs.each -> (row)
          if row[1] < half
            preds.push(@classes[0])
          else
            preds.push(@classes[1])
      else
        probs.each -> (row)
          best = 0
          c = 1
          while c < row.size
            best = c if row[c] > row[best]
            c += 1
          preds.push(@classes[best])
      out = preds
    out

  # Cross-entropy on labelled data, using the same probability convention
  # fit optimizes. Lower is better; nil on an unusable target/weight shape.
  -> log_loss(x, y, sample_weight = nil)
    yvals = nil
    yvals = Estimator.target_values(y) if y != nil
    out = nil
    if @classes != nil && @classes.size == 2
      out = Metrics.log_loss(self.predict_proba(x), yvals, @classes[1], sample_weight)
    else
      out = Metrics.multiclass_log_loss(self.predict_proba_matrix(x), yvals, @classes, sample_weight)
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
