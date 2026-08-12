# Probability calibration — reliability diagrams plus cross-validated
# Platt/sigmoid and isotonic calibration for any probabilistic koala
# classifier.
#
#     curve = Metrics.calibration_curve(scores, y, 10, :uniform)
#     curve.prob_true       # observed positive rate in each non-empty bin
#     curve.prob_pred       # mean predicted probability in the same bins
#     curve.ece             # expected calibration error
#
#     calibrated = CalibratedClassifierCV.new(
#       DecisionTreeClassifier.new,
#       :sigmoid,
#       5
#     )
#     calibrated.fit(x, y)
#     calibrated.predict_proba(x)       # rows in calibrated.classes order
#
# CalibratedClassifierCV is deliberately CROSS-FITTED. Each fold trains a
# fresh clone of the base estimator on the other folds, then learns its
# calibrator only from that fold's held-out predictions. Prediction averages
# the calibrated probabilities from all fold models. No row is used both to
# fit a base model and calibrate that same model, avoiding the optimistic
# probabilities produced by calibrating on training predictions.
#
# Binary classifiers learn one calibrator for classes[1] and use 1-p for
# classes[0]. Multiclass classifiers learn one-vs-rest calibrators and
# normalize their outputs row-wise. Fold-local class orders are always
# remapped to the full fit's first-seen order before calibration.
#
# Two methods ship:
#
#   * `sigmoid` — Platt's Bayesian-smoothed logistic mapping. The two
#     parameters are solved by deterministic Newton steps on cross-entropy.
#   * `isotonic` — weighted pair-adjacent-violators regression followed by
#     clipped linear interpolation between observed score thresholds.
#
# Both accept sample weights. A zero-weight row is dropped before class
# discovery and fold construction; positive weights reach both the base
# estimator's training fold and the calibrator's held-out fold.
#
# NOTE: every float derives through `.to_f`; bare decimals are not portable
# across the interpreter/compiler boundary.

+ CalibrationCurve
  ro :prob_true       # observed positive fraction per non-empty bin
  ro :prob_pred       # mean predicted probability per non-empty bin
  ro :counts          # positive-weight row count per non-empty bin
  ro :weight_sums     # total sample weight per non-empty bin
  ro :n_bins          # requested bin count (empty bins are omitted)
  ro :strategy        # "uniform" or "quantile"
  ro :ece             # weighted expected calibration error
  ro :mce             # maximum calibration error

  -> new(prob_true, prob_pred, counts, weight_sums, n_bins, strategy)
    @prob_true = prob_true
    @prob_pred = prob_pred
    @counts = counts
    @weight_sums = weight_sums
    @n_bins = n_bins
    @strategy = strategy
    total_weight = 0.to_f
    weighted_gap = 0.to_f
    largest_gap = 0.to_f
    i = 0
    while i < prob_true.size
      gap = LinAlg.fabs(prob_true[i].to_f - prob_pred[i].to_f)
      weighted_gap += gap * weight_sums[i]
      total_weight += weight_sums[i]
      largest_gap = gap if gap > largest_gap
      i += 1
    @ece = weighted_gap / total_weight
    @mce = largest_gap

  # Build sklearn-style non-empty reliability bins. Uniform bins have
  # equal width over [0,1]; quantile bins have equal sample-rank width.
  -> .from(scores, actual, n_bins, strategy, pos_label, sample_weight = nil)
    probs = nil
    labels = nil
    probs = Estimator.target_values(scores) if scores != nil
    labels = Estimator.target_values(actual) if actual != nil
    mode = strategy.to_s
    ok = probs != nil && labels != nil
    ok = probs.size == labels.size && probs.size > 0 if ok
    ok = type(n_bins) == "Int" && n_bins > 0 if ok
    ok = mode == "uniform" || mode == "quantile" if ok
    if ok
      probs.each -> (p)
        kind = type(p)
        ok = false if kind != "Int" && kind != "Float"
        if kind == "Int" || kind == "Float"
          v = p.to_f
          ok = false if v < 0.to_f || v > 1.to_f
    wts = nil
    if ok && sample_weight != nil
      wts = Estimator.weight_values(sample_weight, probs.size)
      ok = false if wts == nil
    out = nil
    if ok
      edges = []
      if mode == "quantile"
        ordered = Stats.sorted(probs)
        j = 1
        while j < n_bins
          span = j * (ordered.size - 1)
          lo = span / n_bins
          hi = lo + 1
          hi = ordered.size - 1 if hi >= ordered.size
          fraction = (span % n_bins).to_f / n_bins.to_f
          edge = ordered[lo].to_f + fraction * (ordered[hi].to_f - ordered[lo].to_f)
          edges.push(edge)
          j += 1
      count_bins = []
      weight_bins = []
      score_bins = []
      positive_bins = []
      n_bins.times -> (b)
        count_bins.push(0)
        weight_bins.push(0.to_f)
        score_bins.push(0.to_f)
        positive_bins.push(0.to_f)
      i = 0
      while i < probs.size
        p = probs[i].to_f
        bin = 0
        if mode == "uniform"
          bin = (p * n_bins.to_f).floor
          bin = n_bins - 1 if bin >= n_bins
        else
          j = 0
          while j < edges.size
            bin = j + 1 if p >= edges[j]
            j += 1
        wt = 1.to_f
        wt = wts[i] if wts != nil
        if wt > 0.to_f
          count_bins[bin] += 1
          weight_bins[bin] += wt
          score_bins[bin] += p * wt
          positive_bins[bin] += wt if labels[i] == pos_label
        i += 1
      prob_true = []
      prob_pred = []
      counts = []
      weight_sums = []
      b = 0
      while b < n_bins
        if weight_bins[b] > 0.to_f
          prob_true.push(positive_bins[b] / weight_bins[b])
          prob_pred.push(score_bins[b] / weight_bins[b])
          counts.push(count_bins[b])
          weight_sums.push(weight_bins[b])
        b += 1
      out = CalibrationCurve.new(prob_true, prob_pred, counts, weight_sums, n_bins, mode)
    out

+ Calibration
  # First-seen distinct labels.
  -> .classes(labels)
    out = []
    labels.each -> (label)
      out.push(label) if !out.include?(label)
    out

  -> .label_index(labels, wanted)
    out = 0 - 1
    i = 0
    labels.each -> (label)
      out = i if label == wanted
      i += 1
    out

  -> .numeric_vector?(values)
    ok = values != nil
    ok = values.size > 0 if ok
    if ok
      values.each -> (value)
        kind = type(value)
        ok = false if kind != "Int" && kind != "Float"
    ok

  # A fitted classifier's class order, including a classifier behind a
  # Pipeline (Pipeline forwards classes).
  -> .model_classes(model)
    out = nil
    out = model.classes if model != nil && model.respond_to?("classes")
    out

  # Reorder a fitted model's decision/probability response into `classes`.
  # The result is always n-by-k. For a binary flat response, the sole value
  # belongs to model.classes[1]; reversing class order negates a decision
  # score or complements a probability.
  -> .raw_scores(model, x, classes)
    local_classes = Calibration.model_classes(model)
    out = nil
    ok = local_classes != nil && local_classes.size == classes.size
    if ok
      classes.each -> (label)
        ok = false if !local_classes.include?(label)
    response = nil
    decision = false
    if ok && model.respond_to?("decision_function")
      response = model.decision_function(x)
      decision = true if response != nil
    if ok && response == nil && model.respond_to?("predict_proba")
      response = model.predict_proba(x)
      decision = false
    ok = false if response == nil
    if ok
      flat = response.size == 0
      flat = type(response[0]) != "Array" if response.size > 0
      if flat
        ok = false if classes.size != 2
        if ok
          local_positive = local_classes[1]
          same_positive = local_positive == classes[1]
          matrix = []
          response.each -> (value)
            kind = type(value)
            ok = false if kind != "Int" && kind != "Float"
            if kind == "Int" || kind == "Float"
              positive = value.to_f
              if !same_positive
                if decision
                  positive = 0.to_f - positive
                else
                  positive = 1.to_f - positive
              matrix.push([0.to_f - positive, positive])
          out = matrix if ok
      else
        positions = []
        classes.each -> (label)
          positions.push(Calibration.label_index(local_classes, label))
        matrix = []
        response.each -> (row)
          ok = false if type(row) != "Array"
          ok = false if type(row) == "Array" && row.size != local_classes.size
          reordered = []
          if type(row) == "Array" && row.size == local_classes.size
            positions.each -> (pos)
              value = row[pos]
              kind = type(value)
              ok = false if kind != "Int" && kind != "Float"
              reordered.push(value.to_f) if kind == "Int" || kind == "Float"
          matrix.push(reordered)
        out = matrix if ok
    out

  # Platt calibration. State stores sklearn's sign convention:
  # p = sigmoid(-(slope * score + intercept)).
  -> .fit_sigmoid(scores, targets, weights)
    prior0 = 0.to_f
    prior1 = 0.to_f
    i = 0
    while i < scores.size
      wt = 1.to_f
      wt = weights[i] if weights != nil
      if targets[i] > 0.to_f
        prior1 += wt
      else
        prior0 += wt
      i += 1
    out = nil
    if prior0 > 0.to_f && prior1 > 0.to_f
      max_abs = 0.to_f
      scores.each -> (score)
        v = LinAlg.fabs(score.to_f)
        max_abs = v if v > max_abs
      scale = 1.to_f
      scale = max_abs if max_abs >= 30.to_f
      slope = 0.to_f
      intercept = Math.log((prior0 + 1.to_f) / (prior1 + 1.to_f))
      keep_going = true
      iteration = 0
      hundred_thousand = 100000.to_f
      tolerance = 1.to_f / (hundred_thousand * hundred_thousand)
      thousand = 1000.to_f
      curvature_floor = 1.to_f / (thousand * thousand * thousand * thousand * thousand)
      while iteration < 100 && keep_going
        grad_slope = 0.to_f
        grad_intercept = 0.to_f
        h_ss = 0.to_f
        h_si = 0.to_f
        h_ii = 0.to_f
        i = 0
        while i < scores.size
          f = scores[i].to_f / scale
          wt = 1.to_f
          wt = weights[i] if weights != nil
          target = 1.to_f / (prior0 + 2.to_f)
          target = (prior1 + 1.to_f) / (prior1 + 2.to_f) if targets[i] > 0.to_f
          p = LogisticRegression.sigmoid(0.to_f - (slope * f + intercept))
          diff = target - p
          grad_slope += diff * f * wt
          grad_intercept += diff * wt
          curvature = p * (1.to_f - p) * wt
          h_ss += curvature * f * f
          h_si += curvature * f
          h_ii += curvature
          i += 1
        determinant = h_ss * h_ii - h_si * h_si
        if determinant <= curvature_floor
          keep_going = false
        else
          delta_slope = (h_ii * grad_slope - h_si * grad_intercept) / determinant
          delta_intercept = (h_ss * grad_intercept - h_si * grad_slope) / determinant
          slope -= delta_slope
          intercept -= delta_intercept
          movement = LinAlg.fabs(delta_slope) + LinAlg.fabs(delta_intercept)
          keep_going = false if movement <= tolerance
        iteration += 1
      out = { kind: "sigmoid", slope: slope / scale, intercept: intercept }
    out

  # Stable indices by ascending score (no Array#sort portability gamble).
  -> .ascending_indices(scores)
    order = []
    i = 0
    while i < scores.size
      inserted = false
      next_order = []
      order.each -> (old)
        if !inserted && scores[i].to_f < scores[old].to_f
          next_order.push(i)
          inserted = true
        next_order.push(old)
      next_order.push(i) if !inserted
      order = next_order
      i += 1
    order

  # Weighted pair-adjacent-violators. Equal input scores are grouped before
  # pooling, and each resulting monotone block is expanded back over those
  # distinct thresholds for clipped linear interpolation at prediction.
  -> .fit_isotonic(scores, targets, weights)
    order = Calibration.ascending_indices(scores)
    xs = []
    sums = []
    positives = []
    order.each -> (idx)
      x = scores[idx].to_f
      wt = 1.to_f
      wt = weights[idx] if weights != nil
      target = targets[idx].to_f
      if xs.size > 0 && xs[xs.size - 1] == x
        last = xs.size - 1
        sums[last] += wt
        positives[last] += target * wt
      else
        xs.push(x)
        sums.push(wt)
        positives.push(target * wt)
    blocks = []
    i = 0
    while i < xs.size
      block = {
        first: i,
        last: i,
        weight: sums[i],
        positive: positives[i],
        value: positives[i] / sums[i]
      }
      blocks.push(block)
      merging = true
      while blocks.size > 1 && merging
        right = blocks[blocks.size - 1]
        left = blocks[blocks.size - 2]
        if left[:value] > right[:value]
          blocks.pop
          blocks.pop
          weight = left[:weight] + right[:weight]
          positive = left[:positive] + right[:positive]
          blocks.push({
            first: left[:first],
            last: right[:last],
            weight: weight,
            positive: positive,
            value: positive / weight
          })
        else
          merging = false
      i += 1
    fitted = []
    xs.size.times -> (j)
      fitted.push(0.to_f)
    blocks.each -> (block)
      j = block[:first]
      while j <= block[:last]
        fitted[j] = block[:value]
        j += 1
    { kind: "isotonic", x_thresholds: xs, y_thresholds: fitted }

  -> .fit_calibrator(method, scores, targets, weights)
    out = nil
    if Calibration.numeric_vector?(scores) && Calibration.numeric_vector?(targets)
      out = Calibration.fit_sigmoid(scores, targets, weights) if method == "sigmoid"
      out = Calibration.fit_isotonic(scores, targets, weights) if method == "isotonic"
    out

  -> .isotonic_predict(state, score)
    xs = state[:x_thresholds]
    ys = state[:y_thresholds]
    x = score.to_f
    out = ys[0]
    if x >= xs[xs.size - 1]
      out = ys[ys.size - 1]
    else
      if x > xs[0]
        i = 1
        found = false
        while i < xs.size && !found
          if x <= xs[i]
            width = xs[i] - xs[i - 1]
            if width <= 0.to_f
              out = ys[i]
            else
              fraction = (x - xs[i - 1]) / width
              out = ys[i - 1] + fraction * (ys[i] - ys[i - 1])
            found = true
          i += 1
    out

  -> .apply_calibrator(state, score)
    out = nil
    if state != nil
      if state[:kind] == "sigmoid"
        out = LogisticRegression.sigmoid(0.to_f - (state[:slope] * score.to_f + state[:intercept]))
      if state[:kind] == "isotonic"
        out = Calibration.isotonic_predict(state, score)
    out

  # Strict enough for persistence to reject a payload whose calibrator
  # shape was corrupted instead of deferring the failure to prediction.
  -> .valid_calibrator_state?(state, method)
    ok = state != nil && type(state) == "Hash"
    kind = nil
    kind = state[:kind] if ok
    ok = kind == method if ok
    if ok && kind == "sigmoid"
      slope_kind = type(state[:slope])
      intercept_kind = type(state[:intercept])
      ok = false if slope_kind != "Int" && slope_kind != "Float"
      ok = false if intercept_kind != "Int" && intercept_kind != "Float"
    if ok && kind == "isotonic"
      xs = state[:x_thresholds]
      ys = state[:y_thresholds]
      ok = type(xs) == "Array" && type(ys) == "Array"
      ok = xs.size > 0 && xs.size == ys.size if ok
      if ok
        i = 0
        while i < xs.size
          x_kind = type(xs[i])
          y_kind = type(ys[i])
          ok = false if x_kind != "Int" && x_kind != "Float"
          ok = false if y_kind != "Int" && y_kind != "Float"
          if y_kind == "Int" || y_kind == "Float"
            ok = false if ys[i].to_f < 0.to_f || ys[i].to_f > 1.to_f
          previous_x_kind = nil
          previous_y_kind = nil
          if i > 0
            previous_x_kind = type(xs[i - 1])
            previous_y_kind = type(ys[i - 1])
          numeric_pair = i > 0
          numeric_pair = false if x_kind != "Int" && x_kind != "Float"
          numeric_pair = false if y_kind != "Int" && y_kind != "Float"
          numeric_pair = false if previous_x_kind != "Int" && previous_x_kind != "Float"
          numeric_pair = false if previous_y_kind != "Int" && previous_y_kind != "Float"
          if numeric_pair
            ok = false if xs[i].to_f < xs[i - 1].to_f
            ok = false if ys[i].to_f < ys[i - 1].to_f
          i += 1
    ok

  # Apply one fold's class calibrators and normalize multiclass OVR output.
  -> .calibrated_rows(raw, calibrators, class_count)
    out = []
    raw.each -> (row)
      if class_count == 2
        positive = Calibration.apply_calibrator(calibrators[1], row[1])
        out.push([1.to_f - positive, positive])
      else
        values = []
        total = 0.to_f
        c = 0
        while c < class_count
          value = Calibration.apply_calibrator(calibrators[c], row[c])
          values.push(value)
          total += value
          c += 1
        if total <= 0.to_f
          values = []
          class_count.times -> (j)
            values.push(1.to_f / class_count.to_f)
        else
          normalized = []
          values.each -> (value)
            normalized.push(value / total)
          values = normalized
        out.push(values)
    out

+ CalibratedClassifierCV
  is Estimable
  is SupervisedEstimator

  ro :estimator          # unfitted prototype (a fitted fold after load)
  ro :method             # "sigmoid" or "isotonic"
  ro :cv                 # fold count or an object answering folds(n, y)
  ro :classes            # first-seen full-data label order
  ro :calibrated_models  # [{ model:, calibrators: }, ...], one per fold

  -> new(estimator, method = "sigmoid", cv = 5)
    @estimator = estimator
    @method = method.to_s
    @cv = cv
    @classes = nil
    @calibrated_models = nil
    @effective_cv = nil
    @fitted = false

  -> fitted?
    @fitted

  -> estimator_name
    "CalibratedClassifierCV"

  -> supervised?
    true

  -> supports_sample_weight?
    out = false
    if @estimator != nil && @estimator.respond_to?("supports_sample_weight?")
      out = @estimator.supports_sample_weight?
    out

  # The base estimator stays generically tunable under an `estimator.`
  # prefix, so GridSearch can vary tree depth and calibration method in one
  # surface without knowing this wrapper exists.
  -> params
    out = { method: @method, cv: @cv }
    if @estimator != nil && @estimator.respond_to?("params")
      base = @estimator.params
      base.keys.each -> (key)
        out["estimator." + key.to_s] = base[key]
    out

  -> with_params(overrides)
    method = Estimator.opt(overrides, :method, @method)
    cv = Estimator.opt(overrides, :cv, @cv)
    base = Estimator.unfitted_copy(@estimator)
    if base != nil
      original = @estimator.params
      local = {}
      original.keys.each -> (key)
        full = "estimator." + key.to_s
        local[key] = overrides[full] if overrides != nil && overrides.key?(full)
      base = @estimator.with_params(local)
    CalibratedClassifierCV.new(base, method, cv)

  -> .splitter_for(cv)
    out = nil
    if cv != nil
      if cv.respond_to?("folds")
        out = cv
      else
        out = StratifiedKFold.new(cv) if type(cv) == "Int"
    out

  # Cross-fit one base model + one calibrator set per validation fold.
  -> fit(x, y, sample_weight = nil)
    @fitted = false
    @classes = nil
    @calibrated_models = nil
    @effective_cv = nil
    features = x
    n = Estimator.feature_count(features)
    labels = nil
    labels = Estimator.target_values(y) if y != nil
    ok = n != nil && labels != nil
    ok = n > 0 && n == labels.size if ok
    ok = @method == "sigmoid" || @method == "isotonic" if ok
    ok = @estimator != nil && @estimator.respond_to?("supervised?") if ok
    ok = @estimator.supervised? if ok
    ok = @estimator.respond_to?("predict_proba") || @estimator.respond_to?("decision_function") if ok
    wts = nil
    if ok && sample_weight != nil
      wts = Estimator.weight_values(sample_weight, n)
      ok = false if wts == nil
      ok = false if ok && !self.supports_sample_weight?
    if ok && wts != nil
      keep = Estimator.positive_weight_indices(wts, n)
      features = Estimator.subset_features(features, keep)
      labels = Estimator.subset(labels, keep)
      wts = Estimator.subset(wts, keep)
      n = keep.size
    classes = []
    if ok
      classes = Calibration.classes(labels)
      ok = false if classes.size < 2
    splitter = nil
    folds = nil
    if ok
      splitter = CalibratedClassifierCV.splitter_for(@cv)
      folds = splitter.folds(n, labels) if splitter != nil
      ok = false if folds == nil || folds.size == 0
    trained = []
    if ok
      folds.each -> (fold)
        if ok
          train_idx = fold[0]
          test_idx = fold[1]
          train_rows = Estimator.subset_features(features, train_idx)
          train_y = Estimator.subset(labels, train_idx)
          train_w = Estimator.subset(wts, train_idx)
          test_rows = Estimator.subset_features(features, test_idx)
          test_y = Estimator.subset(labels, test_idx)
          test_w = Estimator.subset(wts, test_idx)
          model = Estimator.unfitted_copy(@estimator)
          fit_result = nil
          fit_result = Estimator.fit_model(model, train_rows, train_y, train_w) if model != nil
          ok = false if fit_result == nil
          raw = nil
          raw = Calibration.raw_scores(model, test_rows, classes) if ok
          ok = false if raw == nil || raw.size != test_y.size
          calibrators = []
          if ok
            classes.size.times -> (c)
              calibrators.push(nil)
            if classes.size == 2
              scores = []
              targets = []
              i = 0
              while i < raw.size
                scores.push(raw[i][1])
                target = 0.to_f
                target = 1.to_f if test_y[i] == classes[1]
                targets.push(target)
                i += 1
              calibrators[1] = Calibration.fit_calibrator(@method, scores, targets, test_w)
              ok = false if calibrators[1] == nil
            else
              c = 0
              while c < classes.size
                scores = []
                targets = []
                i = 0
                while i < raw.size
                  scores.push(raw[i][c])
                  target = 0.to_f
                  target = 1.to_f if test_y[i] == classes[c]
                  targets.push(target)
                  i += 1
                calibrators[c] = Calibration.fit_calibrator(@method, scores, targets, test_w)
                ok = false if calibrators[c] == nil
                c += 1
          trained.push({ model: model, calibrators: calibrators }) if ok
    out = nil
    if ok && trained.size == folds.size
      @classes = classes
      @calibrated_models = trained
      @effective_cv = folds.size
      @fitted = true
      out = self
    out

  # Always a full n-by-k matrix, averaged over calibrated fold models.
  -> predict_proba_matrix(x)
    out = nil
    if @fitted
      total = nil
      ok = true
      @calibrated_models.each -> (pair)
        raw = Calibration.raw_scores(pair[:model], x, @classes)
        ok = false if raw == nil
        if ok
          fold_probs = Calibration.calibrated_rows(raw, pair[:calibrators], @classes.size)
          if total == nil
            total = []
            fold_probs.each -> (row)
              zeros = []
              row.size.times -> (c)
                zeros.push(0.to_f)
              total.push(zeros)
          ok = false if fold_probs.size != total.size
          if ok
            i = 0
            while i < fold_probs.size
              c = 0
              while c < @classes.size
                total[i][c] += fold_probs[i][c]
                c += 1
              i += 1
      if ok
        denom = @calibrated_models.size.to_f
        total.each -> (row)
          c = 0
          while c < row.size
            row[c] = row[c] / denom
            c += 1
        out = total
    out

  # Full matrix by default; a supplied label selects one flat class column.
  -> predict_proba(x, label = nil)
    matrix = self.predict_proba_matrix(x)
    out = nil
    if matrix != nil
      if label == nil
        out = matrix
      else
        index = Calibration.label_index(@classes, label)
        if index >= 0
          column = []
          matrix.each -> (row)
            column.push(row[index])
          out = column
    out

  -> predict(x)
    probs = self.predict_proba_matrix(x)
    out = nil
    if probs != nil
      preds = []
      probs.each -> (row)
        best = 0
        c = 1
        while c < row.size
          best = c if row[c] > row[best]
          c += 1
        preds.push(@classes[best])
      out = preds
    out

  -> score(x, y, sample_weight = nil)
    preds = self.predict(x)
    labels = nil
    labels = Estimator.target_values(y) if y != nil
    out = nil
    if preds != nil && labels != nil && preds.size == labels.size && preds.size > 0
      out = Metrics.accuracy(preds, labels, sample_weight)
    out

  -> log_loss(x, y, sample_weight = nil)
    labels = nil
    labels = Estimator.target_values(y) if y != nil
    Metrics.multiclass_log_loss(self.predict_proba_matrix(x), labels, @classes, sample_weight)

  # --- Persistence ---

  -> persist_name
    "CalibratedClassifierCV"

  # The fitted fold models are the serving model. The original prototype is
  # intentionally omitted; load uses a fitted fold model as the source for
  # future unfitted clones through with_params.
  -> to_state
    stored_cv = @effective_cv
    stored_cv = @cv if type(@cv) == "Int"
    {
      method: @method,
      cv: stored_cv,
      classes: @classes,
      calibrated_models: @calibrated_models
    }

  -> .load_state(st)
    out = nil
    ok = st != nil && type(st) == "Hash"
    ok = st[:method] != nil && st[:cv] != nil if ok
    ok = st[:classes] != nil && st[:calibrated_models] != nil if ok
    if ok
      method = st[:method].to_s
      classes = st[:classes]
      models = st[:calibrated_models]
      ok = method == "sigmoid" || method == "isotonic"
      ok = type(st[:cv]) == "Int" && st[:cv] >= 2 if ok
      ok = type(classes) == "Array" && classes.size >= 2 if ok
      ok = type(models) == "Array" && models.size > 0 if ok
      if ok
        unique = Calibration.classes(classes)
        ok = false if unique.size != classes.size
      if ok
        models.each -> (pair)
          pair_ok = type(pair) == "Hash"
          model = nil
          calibrators = nil
          if pair_ok
            model = pair[:model]
            calibrators = pair[:calibrators]
            pair_ok = false if model == nil
            pair_ok = false if !model.respond_to?("predict")
            pair_ok = false if !model.respond_to?("fitted?")
            pair_ok = false if model.respond_to?("fitted?") && !model.fitted?
            model_classes = Calibration.model_classes(model)
            pair_ok = false if model_classes == nil
            pair_ok = false if model_classes != nil && model_classes.size != classes.size
            if model_classes != nil
              classes.each -> (label)
                pair_ok = false if !model_classes.include?(label)
            pair_ok = false if type(calibrators) != "Array"
            pair_ok = false if type(calibrators) == "Array" && calibrators.size != classes.size
          if pair_ok
            if classes.size == 2
              pair_ok = false if calibrators[0] != nil
              pair_ok = false if !Calibration.valid_calibrator_state?(calibrators[1], method)
            else
              calibrators.each -> (state)
                pair_ok = false if !Calibration.valid_calibrator_state?(state, method)
          ok = false if !pair_ok
      if ok
        model = CalibratedClassifierCV.new(models[0][:model], method, st[:cv])
        out = model.restore_state(st)
    out

  -> restore_state(st)
    @classes = st[:classes]
    @calibrated_models = st[:calibrated_models]
    @effective_cv = @calibrated_models.size
    @estimator = @calibrated_models[0][:model]
    @fitted = true
    self
