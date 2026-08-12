# SVC — deterministic soft-margin kernel support-vector classification.
#
#     model = SVC.new(1, :rbf, :scale)
#     model.fit(x, y)
#     model.support_vectors
#     model.decision_function(x_test)
#
# Binary fitting solves the C-SVM dual with deterministic Sequential Minimal
# Optimization (SMO):
#
#   maximize  sum_i alpha_i
#             - 1/2 sum_i,j alpha_i alpha_j y_i y_j K(x_i, x_j)
#
#   subject to 0 <= alpha_i <= C_i,  sum_i alpha_i y_i = 0
#
# where C_i = C * sample_weight_i. The pair update is the standard Platt
# update with exact box bounds; the second alpha is chosen by the largest
# |E_i - E_j|, ties to the lowest row index. There is no entropy source and
# no random fallback, so the same data produces the same support vectors and
# payload on the interpreter and compiled.
#
# Multiclass follows scikit-learn's SVC strategy: one binary model for every
# class pair. Prediction votes one-vs-one; decision_function returns the
# sklearn-style OVR-shaped vote plus bounded confidence tie-break, one column
# per first-seen class. CalibratedClassifierCV can wrap those raw margins to
# supply cross-fitted sigmoid/isotonic probabilities.
#
# Kernels:
#   :linear  dot(x, z)
#   :rbf     exp(-gamma * ||x-z||^2)
#   :poly    (gamma * dot(x,z) + coef0)^degree
#
# gamma is a positive number, :auto (1 / n_features), or :scale (the
# default: 1 / (n_features * population_variance(X)), falling back to 1
# when variance is zero). These are sklearn's definitions.

+ SupportVectorMachine
  -> .number?(value)
    kind = type(value)
    kind == "Int" || kind == "Float"

  -> .copy_array(values)
    out = []
    values.each -> (value)
      out.push(value)
    out

  -> .abs(value)
    out = value.to_f
    out = 0.to_f - out if out < 0.to_f
    out

  -> .dot(left, right)
    total = 0.to_f
    i = 0
    while i < left.size
      total += left[i].to_f * right[i].to_f
      i += 1
    total

  -> .distance2(left, right)
    total = 0.to_f
    i = 0
    while i < left.size
      delta = left[i].to_f - right[i].to_f
      total += delta * delta
      i += 1
    total

  -> .power(base, degree)
    out = 1.to_f
    degree.times -> (i)
      out *= base.to_f
    out

  -> .kernel_value(left, right, config)
    kind = config[:kernel]
    out = 0.to_f
    if kind == "linear"
      out = SupportVectorMachine.dot(left, right)
    if kind == "rbf"
      out = Math.exp(0.to_f - config[:gamma].to_f * SupportVectorMachine.distance2(left, right))
    if kind == "poly"
      base = config[:gamma].to_f * SupportVectorMachine.dot(left, right) + config[:coef0].to_f
      out = SupportVectorMachine.power(base, config[:degree])
    out

  -> .kernel_matrix(rows, config)
    n = rows.size
    matrix = []
    n.times -> (i)
      row = []
      n.times -> (j)
        row.push(0.to_f)
      matrix.push(row)
    i = 0
    while i < n
      j = i
      while j < n
        value = SupportVectorMachine.kernel_value(rows[i], rows[j], config)
        matrix[i][j] = value
        matrix[j][i] = value
        j += 1
      i += 1
    matrix

  -> .resolved_gamma(setting, rows)
    out = nil
    width = rows[0].size
    if SupportVectorMachine.number?(setting)
      out = setting.to_f if setting.to_f > 0.to_f
    else
      name = ""
      name = setting.to_s if setting != nil
      if name == "auto"
        out = 1.to_f / width.to_f
      if name == "scale"
        total = 0.to_f
        count = 0
        rows.each -> (row)
          row.each -> (value)
            total += value.to_f
            count += 1
        mean = total / count.to_f
        squared = 0.to_f
        rows.each -> (row)
          row.each -> (value)
            delta = value.to_f - mean
            squared += delta * delta
        variance = squared / count.to_f
        if variance > 0.to_f
          out = 1.to_f / (width.to_f * variance)
        else
          out = 1.to_f
    out

  -> .training_decision(alphas, targets, kernels, intercept, index)
    total = intercept.to_f
    j = 0
    while j < alphas.size
      total += alphas[j] * targets[j] * kernels[j][index]
      j += 1
    total

  -> .clip(value, low, high)
    out = value
    out = low if out < low
    out = high if out > high
    out

  # Best second-coordinate value along one equality-constrained pair.
  # Negative eta is the usual concave kernel direction and has a stationary
  # maximum. Zero/positive eta can occur for duplicate rows or an indefinite
  # user-selected polynomial kernel; then the dual maximum lies at a box
  # endpoint, so compare the exact objective gain at low and high.
  -> .pair_next_alpha(old_j, target_j, error_i, error_j, eta, low, high, tiny)
    out = old_j
    if eta < 0.to_f
      out = old_j - target_j * (error_i - error_j) / eta
      out = SupportVectorMachine.clip(out, low, high)
    else
      slope = target_j * (error_i - error_j)
      low_delta = low - old_j
      high_delta = high - old_j
      low_gain = low_delta * slope + eta * low_delta * low_delta / 2.to_f
      high_gain = high_delta * slope + eta * high_delta * high_delta / 2.to_f
      if low_gain > high_gain + tiny
        out = low
      if high_gain > low_gain + tiny
        out = high
    out

  # Deterministic simplified SMO for one binary problem. targets are -1/+1.
  -> .solve_binary(rows, targets, weights, original_indices, config)
    n = rows.size
    kernels = SupportVectorMachine.kernel_matrix(rows, config)
    alphas = SupportVectorMachine.zeros(n)
    bounds = []
    n.times -> (i)
      weight = 1.to_f
      weight = weights[i] if weights != nil
      bounds.push(config[:c].to_f * weight)
    intercept = 0.to_f
    passes = 0
    iteration = 0
    tiny = 1.to_f / 1000000000000.to_f
    while passes < 10 && iteration < config[:max_iter]
      changed = 0
      i = 0
      while i < n
        decision_i = SupportVectorMachine.training_decision(alphas, targets, kernels, intercept, i)
        error_i = decision_i - targets[i]
        violates = false
        violates = true if targets[i] * error_i < 0.to_f - config[:tol] && alphas[i] < bounds[i] - tiny
        violates = true if targets[i] * error_i > config[:tol] && alphas[i] > tiny
        if violates
          j = 0 - 1
          best_gap = 0.to_f - 1.to_f
          candidate = 0
          while candidate < n
            if candidate != i
              decision_j = SupportVectorMachine.training_decision(alphas, targets, kernels, intercept, candidate)
              error_j = decision_j - targets[candidate]
              candidate_low = 0.to_f
              candidate_high = 0.to_f
              if targets[i] != targets[candidate]
                candidate_low = alphas[candidate] - alphas[i]
                candidate_low = 0.to_f if candidate_low < 0.to_f
                candidate_high = bounds[i] + alphas[candidate] - alphas[i]
                candidate_high = bounds[candidate] if candidate_high > bounds[candidate]
              else
                candidate_total = alphas[i] + alphas[candidate]
                candidate_low = candidate_total - bounds[i]
                candidate_low = 0.to_f if candidate_low < 0.to_f
                candidate_high = candidate_total
                candidate_high = bounds[candidate] if candidate_high > bounds[candidate]
              candidate_eta = 2.to_f * kernels[i][candidate] - kernels[i][i] - kernels[candidate][candidate]
              if candidate_high - candidate_low > tiny
                candidate_next = SupportVectorMachine.pair_next_alpha(
                  alphas[candidate], targets[candidate], error_i, error_j,
                  candidate_eta, candidate_low, candidate_high, tiny
                )
                gap = SupportVectorMachine.abs(error_i - error_j)
                if SupportVectorMachine.abs(candidate_next - alphas[candidate]) > tiny && gap > best_gap
                  best_gap = gap
                  j = candidate
            candidate += 1
          if j >= 0
            error_j = SupportVectorMachine.training_decision(alphas, targets, kernels, intercept, j) - targets[j]
            old_i = alphas[i]
            old_j = alphas[j]
            low = 0.to_f
            high = 0.to_f
            if targets[i] != targets[j]
              low = old_j - old_i
              low = 0.to_f if low < 0.to_f
              high = bounds[i] + old_j - old_i
              high = bounds[j] if high > bounds[j]
            else
              total_alpha = old_i + old_j
              low = total_alpha - bounds[i]
              low = 0.to_f if low < 0.to_f
              high = total_alpha
              high = bounds[j] if high > bounds[j]
            if high - low > tiny
              eta = 2.to_f * kernels[i][j] - kernels[i][i] - kernels[j][j]
              next_j = SupportVectorMachine.pair_next_alpha(
                old_j, targets[j], error_i, error_j, eta, low, high, tiny
              )
              if SupportVectorMachine.abs(next_j - old_j) > tiny
                next_i = old_i + targets[i] * targets[j] * (old_j - next_j)
                next_i = SupportVectorMachine.clip(next_i, 0.to_f, bounds[i])
                b1 = intercept - error_i
                b1 -= targets[i] * (next_i - old_i) * kernels[i][i]
                b1 -= targets[j] * (next_j - old_j) * kernels[i][j]
                b2 = intercept - error_j
                b2 -= targets[i] * (next_i - old_i) * kernels[i][j]
                b2 -= targets[j] * (next_j - old_j) * kernels[j][j]
                alphas[i] = next_i
                alphas[j] = next_j
                if next_i > tiny && next_i < bounds[i] - tiny
                  intercept = b1
                else
                  if next_j > tiny && next_j < bounds[j] - tiny
                    intercept = b2
                  else
                    intercept = (b1 + b2) / 2.to_f
                changed += 1
        i += 1
      if changed == 0
        passes += 1
      else
        passes = 0
      iteration += 1

    # Average y_i - sum_j alpha_j*y_j*K_ji over free support vectors for a
    # less path-dependent intercept. Keep the SMO intercept when all support
    # vectors sit on their bounds.
    free_total = 0.to_f
    free_count = 0
    i = 0
    while i < n
      if alphas[i] > tiny && alphas[i] < bounds[i] - tiny
        sum = 0.to_f
        j = 0
        while j < n
          sum += alphas[j] * targets[j] * kernels[j][i]
          j += 1
        free_total += targets[i] - sum
        free_count += 1
      i += 1
    intercept = free_total / free_count.to_f if free_count > 0

    support_vectors = []
    support_indices = []
    coefficients = []
    support_alphas = []
    i = 0
    while i < n
      if alphas[i] > tiny
        copied = []
        rows[i].each -> (value)
          copied.push(value)
        support_vectors.push(copied)
        support_indices.push(original_indices[i])
        coefficients.push(alphas[i] * targets[i])
        support_alphas.push(alphas[i])
      i += 1
    out = nil
    if support_vectors.size > 0
      out = {
        support_vectors: support_vectors,
        support_indices: support_indices,
        coefficients: coefficients,
        alphas: support_alphas,
        intercept: intercept,
        n_iter: iteration
      }
    out

  -> .zeros(n)
    out = []
    n.times -> (i)
      out.push(0.to_f)
    out

  -> .integer_weights?(weights)
    ok = weights != nil
    if ok
      weights.each -> (weight)
        ok = false if weight != weight.to_i.to_f
    ok

  # Expanding integer weights makes the estimator-wide "weights equal row
  # duplication" contract byte-exact, including the SMO update order.
  -> .expand_integer_weights(rows, labels, weights)
    expanded_rows = []
    expanded_labels = []
    i = 0
    while i < rows.size
      copies = weights[i].to_i
      copies.times -> (copy)
        row = []
        rows[i].each -> (value)
          row.push(value)
        expanded_rows.push(row)
        expanded_labels.push(labels[i])
      i += 1
    { rows: expanded_rows, labels: expanded_labels }

  -> .decision_one(estimator, row, config)
    total = estimator[:intercept].to_f
    i = 0
    while i < estimator[:support_vectors].size
      kernel = SupportVectorMachine.kernel_value(estimator[:support_vectors][i], row, config)
      total += estimator[:coefficients][i] * kernel
      i += 1
    total

  -> .sorted_unique_indices(values)
    sorted = DecisionTree.sorted_ints(values)
    out = []
    sorted.each -> (value)
      out.push(value) if out.size == 0 || out[out.size - 1] != value
    out

  -> .argmax(values)
    best = 0
    i = 1
    while i < values.size
      best = i if values[i] > values[best]
      i += 1
    best

  -> .query_rows(x, n_features)
    rows = nil
    rows = Estimator.feature_rows(x) if x != nil
    ok = rows != nil && rows.size > 0
    ok = LogisticRegression.numeric_rows?(rows) if ok
    if ok
      rows.each -> (row)
        ok = false if row.size != n_features
    out = nil
    out = rows if ok
    out

+ SVC
  is Estimable
  is SupervisedEstimator

  ro :c
  ro :kernel
  ro :gamma
  ro :degree
  ro :coef0
  ro :tol
  ro :max_iter
  ro :classes
  ro :estimators
  ro :support_vectors
  ro :support_indices
  ro :dual_coef
  ro :intercept
  ro :n_iter
  ro :n_features
  ro :gamma_value

  -> new(c = nil, kernel = nil, gamma = nil, degree = nil, coef0 = nil, tol = nil, max_iter = nil)
    c_value = c
    c_value = 1.to_f if c_value == nil
    kernel_value = kernel
    kernel_value = :rbf if kernel_value == nil
    gamma_setting = gamma
    gamma_setting = :scale if gamma_setting == nil
    degree_value = degree
    degree_value = 3 if degree_value == nil
    coef_value = coef0
    coef_value = 0.to_f if coef_value == nil
    tolerance = tol
    tolerance = 1.to_f / 1000.to_f if tolerance == nil
    iterations = max_iter
    iterations = 1000 if iterations == nil
    @c = c_value
    @kernel = kernel_value
    @gamma = gamma_setting
    @degree = degree_value
    @coef0 = coef_value
    @tol = tolerance
    @max_iter = iterations
    @fitted = false
    @classes = nil
    @estimators = nil
    @support_vectors = nil
    @support_indices = nil
    @dual_coef = nil
    @intercept = nil
    @n_iter = nil
    @n_features = nil
    @gamma_value = nil

  -> fitted?
    @fitted

  -> estimator_name
    "SVC"

  -> supervised?
    true

  -> supports_sample_weight?
    true

  -> params
    { c: @c, kernel: @kernel, gamma: @gamma, degree: @degree, coef0: @coef0, tol: @tol, max_iter: @max_iter }

  -> with_params(overrides)
    SVC.new(
      Estimator.opt(overrides, :c, @c),
      Estimator.opt(overrides, :kernel, @kernel),
      Estimator.opt(overrides, :gamma, @gamma),
      Estimator.opt(overrides, :degree, @degree),
      Estimator.opt(overrides, :coef0, @coef0),
      Estimator.opt(overrides, :tol, @tol),
      Estimator.opt(overrides, :max_iter, @max_iter)
    )

  -> valid_params?
    ok = SupportVectorMachine.number?(@c) && @c.to_f > 0.to_f
    name = @kernel.to_s if @kernel != nil
    ok = name == "linear" || name == "rbf" || name == "poly" if ok
    ok = type(@degree) == "Int" && @degree >= 1 if ok
    ok = SupportVectorMachine.number?(@coef0) if ok
    ok = SupportVectorMachine.number?(@tol) && @tol.to_f > 0.to_f if ok
    ok = type(@max_iter) == "Int" && @max_iter >= 1 if ok
    ok

  -> fit(x, y, sample_weight = nil)
    @fitted = false
    @classes = nil
    @estimators = nil
    @support_vectors = nil
    @support_indices = nil
    @dual_coef = nil
    @intercept = nil
    @n_iter = nil
    @n_features = nil
    @gamma_value = nil
    rows = nil
    rows = Estimator.feature_rows(x) if x != nil
    labels = nil
    labels = Estimator.target_values(y) if y != nil
    ok = rows != nil && labels != nil
    ok = rows.size > 1 && rows.size == labels.size if ok
    ok = LogisticRegression.numeric_rows?(rows) if ok
    ok = self.valid_params? if ok
    weights = nil
    weights = Estimator.weight_values(sample_weight, rows.size) if ok && sample_weight != nil
    ok = false if sample_weight != nil && weights == nil
    if ok && weights != nil
      trimmed = Estimator.drop_zero_weights(rows, labels, weights)
      rows = trimmed[:rows]
      labels = trimmed[:targets]
      weights = trimmed[:weights]
      if SupportVectorMachine.integer_weights?(weights)
        expanded = SupportVectorMachine.expand_integer_weights(rows, labels, weights)
        rows = expanded[:rows]
        labels = expanded[:labels]
        weights = nil
    classes = []
    if ok
      labels.each -> (label)
        classes.push(label) if !classes.include?(label)
      ok = false if classes.size < 2
    gamma_value = nil
    gamma_value = SupportVectorMachine.resolved_gamma(@gamma, rows) if ok
    ok = false if gamma_value == nil
    out = nil
    if ok
      config = {
        c: @c.to_f,
        kernel: @kernel.to_s,
        gamma: gamma_value,
        degree: @degree,
        coef0: @coef0.to_f,
        tol: @tol.to_f,
        max_iter: @max_iter
      }
      estimators = []
      a = 0
      while a < classes.size - 1 && ok
        b = a + 1
        while b < classes.size && ok
          pair_rows = []
          pair_targets = []
          pair_weights = []
          pair_indices = []
          i = 0
          while i < rows.size
            if labels[i] == classes[a] || labels[i] == classes[b]
              pair_rows.push(rows[i])
              target = 0.to_f - 1.to_f
              target = 1.to_f if labels[i] == classes[b]
              pair_targets.push(target)
              pair_weights.push(weights[i]) if weights != nil
              pair_indices.push(i)
            i += 1
          selected_weights = nil
          selected_weights = pair_weights if weights != nil
          estimator = SupportVectorMachine.solve_binary(
            pair_rows, pair_targets, selected_weights, pair_indices, config
          )
          ok = false if estimator == nil
          if ok
            estimator[:class_a] = classes[a]
            estimator[:class_b] = classes[b]
            estimator[:class_a_index] = a
            estimator[:class_b_index] = b
            estimators.push(estimator)
          b += 1
        a += 1
      if ok
        all_indices = []
        estimators.each -> (estimator)
          estimator[:support_indices].each -> (index)
            all_indices.push(index)
        support_indices = SupportVectorMachine.sorted_unique_indices(all_indices)
        support_vectors = []
        support_indices.each -> (index)
          copied = []
          rows[index].each -> (value)
            copied.push(value)
          support_vectors.push(copied)
        dual = []
        intercepts = []
        iterations = []
        estimators.each -> (estimator)
          dual.push(SupportVectorMachine.copy_array(estimator[:coefficients]))
          intercepts.push(estimator[:intercept])
          iterations.push(estimator[:n_iter])
        @classes = classes
        @estimators = estimators
        @support_indices = support_indices
        @support_vectors = support_vectors
        @dual_coef = dual
        @intercept = intercepts
        @n_iter = iterations
        @n_features = rows[0].size
        @gamma_value = gamma_value
        @fitted = true
        out = self
    out

  -> query_rows(x)
    out = nil
    out = SupportVectorMachine.query_rows(x, @n_features) if @fitted
    out

  -> config
    { kernel: @kernel.to_s, gamma: @gamma_value, degree: @degree, coef0: @coef0.to_f }

  # Binary: one signed margin per row, positive toward classes[1].
  # Multiclass: one OVR-shaped vote/confidence score per class.
  -> decision_function(x)
    rows = self.query_rows(x)
    out = nil
    if rows != nil
      cfg = self.config
      if @classes.size == 2
        scores = []
        rows.each -> (row)
          scores.push(SupportVectorMachine.decision_one(@estimators[0], row, cfg))
        out = scores
      else
        matrix = []
        rows.each -> (row)
          votes = SupportVectorMachine.zeros(@classes.size)
          confidences = SupportVectorMachine.zeros(@classes.size)
          @estimators.each -> (estimator)
            score = SupportVectorMachine.decision_one(estimator, row, cfg)
            left = estimator[:class_a_index]
            right = estimator[:class_b_index]
            if score > 0.to_f
              votes[right] += 1.to_f
            else
              votes[left] += 1.to_f
            confidences[left] -= score
            confidences[right] += score
          transformed = []
          c = 0
          while c < @classes.size
            bounded = confidences[c] / (3.to_f * (SupportVectorMachine.abs(confidences[c]) + 1.to_f))
            transformed.push(votes[c] + bounded)
            c += 1
          matrix.push(transformed)
        out = matrix
    out

  -> predict(x)
    decision = self.decision_function(x)
    out = nil
    if decision != nil
      preds = []
      if @classes.size == 2
        decision.each -> (score)
          label = @classes[0]
          label = @classes[1] if score > 0.to_f
          preds.push(label)
      else
        decision.each -> (row)
          preds.push(@classes[SupportVectorMachine.argmax(row)])
      out = preds
    out

  -> score(x, y, sample_weight = nil)
    preds = self.predict(x)
    labels = nil
    labels = Estimator.target_values(y) if y != nil
    out = nil
    if preds != nil && labels != nil
      ok = preds.size == labels.size && preds.size > 0
      weights = nil
      weights = Estimator.weight_values(sample_weight, preds.size) if ok && sample_weight != nil
      ok = false if sample_weight != nil && weights == nil
      out = Metrics.accuracy(preds, labels, weights) if ok
    out

  -> persist_name
    "SVC"

  -> to_state
    {
      c: @c, kernel: @kernel, gamma: @gamma, degree: @degree,
      coef0: @coef0, tol: @tol, max_iter: @max_iter,
      classes: @classes, estimators: @estimators,
      support_vectors: @support_vectors, support_indices: @support_indices,
      dual_coef: @dual_coef, intercept: @intercept, n_iter: @n_iter,
      n_features: @n_features, gamma_value: @gamma_value
    }

  -> .load_state(state)
    out = nil
    ok = state != nil
    ok = state[:c] != nil && state[:kernel] != nil && state[:gamma] != nil if ok
    ok = state[:degree] != nil && state[:coef0] != nil && state[:tol] != nil if ok
    ok = state[:max_iter] != nil && state[:classes] != nil if ok
    ok = state[:estimators] != nil && state[:support_vectors] != nil if ok
    ok = state[:support_indices] != nil && state[:dual_coef] != nil if ok
    ok = state[:intercept] != nil && state[:n_iter] != nil if ok
    ok = state[:n_features] != nil && state[:gamma_value] != nil if ok
    if ok
      model = SVC.new(
        state[:c], state[:kernel], state[:gamma], state[:degree],
        state[:coef0], state[:tol], state[:max_iter]
      )
      out = model.restore_state(state)
    out

  -> restore_state(state)
    @classes = state[:classes]
    @estimators = state[:estimators]
    @support_vectors = state[:support_vectors]
    @support_indices = state[:support_indices]
    @dual_coef = state[:dual_coef]
    @intercept = state[:intercept]
    @n_iter = state[:n_iter]
    @n_features = state[:n_features]
    @gamma_value = state[:gamma_value]
    @fitted = true
    self
