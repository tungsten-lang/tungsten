# GradientBoostingRegressor / GradientBoostingClassifier — additive CART
# ensembles trained stage by stage.
#
#     reg = GradientBoostingRegressor.new(100, nil, 3, 1)
#     clf = GradientBoostingClassifier.new(100, nil, 3, 1)
#
# Constructor order is:
#
#     n_estimators, learning_rate, max_depth, min_samples_leaf
#
# learning_rate defaults to 0.1, built as 1.to_f / 10.to_f rather than a
# decimal literal. Every stage is a deterministic DecisionTreeRegressor:
#
#   regression       residual = y - current prediction
#   classification   residual = one_hot(y) - current probability
#
# Regression leaves already hold the least-squares line-search optimum: the
# weighted mean residual. Classification follows Friedman's gradient
# boosting exactly: CART discovers terminal regions from the negative
# gradient, then every leaf is replaced by its Newton step. Binary boosting
# grows one tree per stage; multiclass boosting grows one tree per class per
# stage and applies the (K - 1) / K correction. `predict_proba` therefore
# comes from the additive logits themselves, not from vote fractions.
#
# Unlike a random forest, boosting is intentionally SEQUENTIAL: tree m fits
# what trees 0...m-1 still get wrong. There is no random subsampling in this
# first implementation, so fixed data and hyperparameters give byte-identical
# trees, probabilities, and Persist payloads on both engines.
#
# Sample weights enter every relevant quantity: the initial mean/class prior,
# the CART split and residual leaf mean, the classification Newton numerator
# and denominator, and the recorded training loss. Integer weights are
# consequently equivalent to row duplication, koala's estimator-wide
# correctness contract.

+ GradientBoosting
  -> .number?(value)
    kind = type(value)
    kind == "Integer" || kind == "Float"

  -> .numeric_targets?(values)
    ok = values != nil && values.size > 0
    if ok
      values.each -> (value)
        ok = false if !GradientBoosting.number?(value)
    ok

  -> .params_ok?(n_estimators, learning_rate, max_depth, min_samples_leaf)
    ok = type(n_estimators) == "Integer" && n_estimators > 0
    ok = GradientBoosting.number?(learning_rate) && learning_rate.to_f > 0.to_f if ok
    if ok && max_depth != nil
      ok = type(max_depth) == "Integer" && max_depth >= 0
    ok = type(min_samples_leaf) == "Integer" && min_samples_leaf >= 1 if ok
    ok

  # Fit one deterministic regression tree and return its plain root hash.
  -> .fit_tree(rows, targets, weights, max_depth, min_samples_leaf)
    model = DecisionTreeRegressor.new(max_depth, 2, min_samples_leaf, :mse)
    fitted = model.fit(rows, targets, weights)
    out = nil
    out = model.tree if fitted != nil
    out

  -> .tree_predictions(tree, rows)
    out = []
    rows.each -> (row)
      out.push(DecisionTree.descend(tree, row)[:prediction].to_f)
    out

  -> .query_rows(x, n_features)
    rows = nil
    rows = Estimator.feature_rows(x) if x != nil
    ok = rows != nil
    ok = LogisticRegression.numeric_rows?(rows) if ok
    if ok
      rows.each -> (row)
        ok = false if row.size != n_features
    out = nil
    out = rows if ok
    out

  -> .constant_array(n, value)
    out = []
    n.times -> (i)
      out.push(value.to_f)
    out

  -> .copy_array(values)
    out = []
    values.each -> (value)
      out.push(value)
    out

  # Stable softmax over an already-computed logit row.
  -> .softmax_logits(logits)
    largest = logits[0]
    i = 1
    while i < logits.size
      largest = logits[i] if logits[i] > largest
      i += 1
    exps = []
    total = 0.to_f
    logits.each -> (logit)
      value = Math.exp(logit.to_f - largest.to_f)
      exps.push(value)
      total += value
    out = []
    exps.each -> (value)
      out.push(value / total)
    out

  -> .binary_probabilities(raw)
    out = []
    raw.each -> (score)
      p = LogisticRegression.sigmoid(score)
      out.push([1.to_f - p, p])
    out

  -> .multiclass_probabilities(raw)
    out = []
    raw.each -> (logits)
      out.push(GradientBoosting.softmax_logits(logits))
    out

  # Give every terminal region a deterministic left-to-right integer id.
  # The id remains in the plain tree hash; DecisionTree readers ignore it,
  # while it lets one row-major pass accumulate Newton statistics without
  # relying on Hash identity/equality (which differs across the engines).
  -> .assign_leaf_ids(node, next_id)
    out = next_id
    if node[:leaf]
      node[:boost_id] = next_id
      out = next_id + 1
    else
      after_left = GradientBoosting.assign_leaf_ids(node[:left], next_id)
      out = GradientBoosting.assign_leaf_ids(node[:right], after_left)
    out

  # Replace the residual means in a classification tree with Newton leaf
  # steps: factor * sum(w * (y-p)) / sum(w * p * (1-p)).
  -> .newton_leaves(tree, rows, targets, probabilities, weights, factor)
    count = GradientBoosting.assign_leaf_ids(tree, 0)
    numerators = GradientBoosting.constant_array(count, 0)
    denominators = GradientBoosting.constant_array(count, 0)
    i = 0
    while i < rows.size
      leaf = DecisionTree.descend(tree, rows[i])
      id = leaf[:boost_id]
      weight = 1.to_f
      weight = weights[i] if weights != nil
      p = probabilities[i].to_f
      numerators[id] += weight * (targets[i].to_f - p)
      denominators[id] += weight * p * (1.to_f - p)
      i += 1
    GradientBoosting.set_newton_values(tree, numerators, denominators, factor)
    tree

  -> .set_newton_values(node, numerators, denominators, factor)
    if node[:leaf]
      id = node[:boost_id]
      value = 0.to_f
      denom = denominators[id]
      value = factor.to_f * numerators[id] / denom if denom > 0.to_f
      node[:prediction] = value
    else
      GradientBoosting.set_newton_values(node[:left], numerators, denominators, factor)
      GradientBoosting.set_newton_values(node[:right], numerators, denominators, factor)
    node

  -> .class_counts(labels, classes, weights)
    counts = GradientBoosting.constant_array(classes.size, 0)
    i = 0
    labels.each -> (label)
      c = 0
      while c < classes.size
        if classes[c] == label
          weight = 1.to_f
          weight = weights[i] if weights != nil
          counts[c] += weight
        c += 1
      i += 1
    counts

  -> .argmax(values)
    best = 0
    i = 1
    while i < values.size
      best = i if values[i] > values[best]
      i += 1
    best

+ GradientBoostingRegressor
  is Estimable
  is SupervisedEstimator

  ro :n_estimators
  ro :learning_rate
  ro :max_depth
  ro :min_samples_leaf
  ro :initial_prediction
  ro :trees
  ro :train_scores
  ro :n_features

  -> new(n_estimators = nil, learning_rate = nil, max_depth = nil, min_samples_leaf = nil)
    ne = n_estimators
    ne = 100 if ne == nil
    lr = learning_rate
    lr = 1.to_f / 10.to_f if lr == nil
    md = max_depth
    md = 3 if md == nil
    ml = min_samples_leaf
    ml = 1 if ml == nil
    @n_estimators = ne
    @learning_rate = lr
    @max_depth = md
    @min_samples_leaf = ml
    @fitted = false
    @initial_prediction = nil
    @trees = nil
    @train_scores = nil
    @n_features = nil

  -> fitted?
    @fitted

  -> estimator_name
    "GradientBoostingRegressor"

  -> supervised?
    true

  -> supports_sample_weight?
    true

  -> params
    { n_estimators: @n_estimators, learning_rate: @learning_rate, max_depth: @max_depth, min_samples_leaf: @min_samples_leaf }

  -> with_params(overrides)
    GradientBoostingRegressor.new(
      Estimator.opt(overrides, :n_estimators, @n_estimators),
      Estimator.opt(overrides, :learning_rate, @learning_rate),
      Estimator.opt(overrides, :max_depth, @max_depth),
      Estimator.opt(overrides, :min_samples_leaf, @min_samples_leaf)
    )

  -> fit(x, y, sample_weight = nil)
    @fitted = false
    @initial_prediction = nil
    @trees = nil
    @train_scores = nil
    @n_features = nil
    rows = nil
    rows = Estimator.feature_rows(x) if x != nil
    targets = nil
    targets = Estimator.target_values(y) if y != nil
    ok = rows != nil && targets != nil
    ok = rows.size > 0 && rows.size == targets.size if ok
    ok = LogisticRegression.numeric_rows?(rows) if ok
    ok = GradientBoosting.numeric_targets?(targets) if ok
    ok = GradientBoosting.params_ok?(@n_estimators, @learning_rate, @max_depth, @min_samples_leaf) if ok
    weights = nil
    weights = Estimator.weight_values(sample_weight, rows.size) if ok && sample_weight != nil
    ok = false if sample_weight != nil && weights == nil
    if ok && weights != nil
      trimmed = Estimator.drop_zero_weights(rows, targets, weights)
      rows = trimmed[:rows]
      targets = trimmed[:targets]
      weights = trimmed[:weights]
    values = []
    if ok
      targets.each -> (target)
        values.push(target.to_f)
    out = nil
    if ok
      initial = Estimator.weighted_mean(values, weights)
      current = GradientBoosting.constant_array(rows.size, initial)
      trees = []
      scores = []
      stage = 0
      while stage < @n_estimators && ok
        residuals = []
        i = 0
        while i < rows.size
          residuals.push(values[i] - current[i])
          i += 1
        tree = GradientBoosting.fit_tree(rows, residuals, weights, @max_depth, @min_samples_leaf)
        ok = false if tree == nil
        if ok
          updates = GradientBoosting.tree_predictions(tree, rows)
          i = 0
          while i < current.size
            current[i] += @learning_rate.to_f * updates[i]
            i += 1
          trees.push(tree)
          scores.push(Metrics.mse(current, values, weights))
        stage += 1
      if ok
        @initial_prediction = initial
        @trees = trees
        @train_scores = scores
        @n_features = rows[0].size
        @fitted = true
        out = self
    out

  -> query_rows(x)
    out = nil
    out = GradientBoosting.query_rows(x, @n_features) if @fitted
    out

  -> predict(x)
    rows = self.query_rows(x)
    out = nil
    if rows != nil
      preds = GradientBoosting.constant_array(rows.size, @initial_prediction)
      @trees.each -> (tree)
        updates = GradientBoosting.tree_predictions(tree, rows)
        i = 0
        while i < preds.size
          preds[i] += @learning_rate.to_f * updates[i]
          i += 1
      out = preds
    out

  # One prediction vector after each successive tree, in training order.
  # The final element equals predict(x); no refit is performed.
  -> staged_predict(x)
    rows = self.query_rows(x)
    out = nil
    if rows != nil
      current = GradientBoosting.constant_array(rows.size, @initial_prediction)
      stages = []
      @trees.each -> (tree)
        updates = GradientBoosting.tree_predictions(tree, rows)
        i = 0
        while i < current.size
          current[i] += @learning_rate.to_f * updates[i]
          i += 1
        stages.push(GradientBoosting.copy_array(current))
      out = stages
    out

  -> score(x, y, sample_weight = nil)
    preds = self.predict(x)
    yvals = nil
    yvals = Estimator.target_values(y) if y != nil
    out = nil
    if preds != nil && yvals != nil
      ok = preds.size == yvals.size && preds.size > 0
      weights = nil
      weights = Estimator.weight_values(sample_weight, preds.size) if ok && sample_weight != nil
      ok = false if sample_weight != nil && weights == nil
      out = Metrics.r2(preds, yvals, weights) if ok
    out

  -> persist_name
    "GradientBoostingRegressor"

  -> to_state
    { n_estimators: @n_estimators, learning_rate: @learning_rate, max_depth: @max_depth, min_samples_leaf: @min_samples_leaf, initial_prediction: @initial_prediction, trees: @trees, train_scores: @train_scores, n_features: @n_features }

  -> .load_state(state)
    out = nil
    ok = state != nil
    ok = state[:n_estimators] != nil && state[:learning_rate] != nil if ok
    ok = state[:max_depth] != nil && state[:min_samples_leaf] != nil if ok
    ok = state[:initial_prediction] != nil && state[:trees] != nil if ok
    ok = state[:train_scores] != nil && state[:n_features] != nil if ok
    ok = state[:classes] == nil if ok
    if ok
      model = GradientBoostingRegressor.new(
        state[:n_estimators], state[:learning_rate],
        state[:max_depth], state[:min_samples_leaf]
      )
      out = model.restore_state(state)
    out

  -> restore_state(state)
    @initial_prediction = state[:initial_prediction]
    @trees = state[:trees]
    @train_scores = state[:train_scores]
    @n_features = state[:n_features]
    @fitted = true
    self

+ GradientBoostingClassifier
  is Estimable
  is SupervisedEstimator

  ro :n_estimators
  ro :learning_rate
  ro :max_depth
  ro :min_samples_leaf
  ro :classes
  ro :initial_raw
  ro :trees
  ro :train_scores
  ro :n_features

  -> new(n_estimators = nil, learning_rate = nil, max_depth = nil, min_samples_leaf = nil)
    ne = n_estimators
    ne = 100 if ne == nil
    lr = learning_rate
    lr = 1.to_f / 10.to_f if lr == nil
    md = max_depth
    md = 3 if md == nil
    ml = min_samples_leaf
    ml = 1 if ml == nil
    @n_estimators = ne
    @learning_rate = lr
    @max_depth = md
    @min_samples_leaf = ml
    @fitted = false
    @classes = nil
    @initial_raw = nil
    @trees = nil
    @train_scores = nil
    @n_features = nil

  -> fitted?
    @fitted

  -> estimator_name
    "GradientBoostingClassifier"

  -> supervised?
    true

  -> supports_sample_weight?
    true

  -> params
    { n_estimators: @n_estimators, learning_rate: @learning_rate, max_depth: @max_depth, min_samples_leaf: @min_samples_leaf }

  -> with_params(overrides)
    GradientBoostingClassifier.new(
      Estimator.opt(overrides, :n_estimators, @n_estimators),
      Estimator.opt(overrides, :learning_rate, @learning_rate),
      Estimator.opt(overrides, :max_depth, @max_depth),
      Estimator.opt(overrides, :min_samples_leaf, @min_samples_leaf)
    )

  -> fit(x, y, sample_weight = nil)
    @fitted = false
    @classes = nil
    @initial_raw = nil
    @trees = nil
    @train_scores = nil
    @n_features = nil
    rows = nil
    rows = Estimator.feature_rows(x) if x != nil
    labels = nil
    labels = Estimator.target_values(y) if y != nil
    ok = rows != nil && labels != nil
    ok = rows.size > 0 && rows.size == labels.size if ok
    ok = LogisticRegression.numeric_rows?(rows) if ok
    ok = GradientBoosting.params_ok?(@n_estimators, @learning_rate, @max_depth, @min_samples_leaf) if ok
    weights = nil
    weights = Estimator.weight_values(sample_weight, rows.size) if ok && sample_weight != nil
    ok = false if sample_weight != nil && weights == nil
    if ok && weights != nil
      trimmed = Estimator.drop_zero_weights(rows, labels, weights)
      rows = trimmed[:rows]
      labels = trimmed[:targets]
      weights = trimmed[:weights]
    classes = []
    if ok
      labels.each -> (label)
        classes.push(label) if !classes.include?(label)
      ok = false if classes.size < 2
    out = nil
    if ok
      counts = GradientBoosting.class_counts(labels, classes, weights)
      total = Estimator.weight_total(weights, labels.size).to_f
      trees = []
      scores = []
      if classes.size == 2
        positive = classes[1]
        targets = []
        labels.each -> (label)
          value = 0.to_f
          value = 1.to_f if label == positive
          targets.push(value)
        initial = Math.log(counts[1] / counts[0])
        raw = GradientBoosting.constant_array(rows.size, initial)
        stage = 0
        while stage < @n_estimators && ok
          matrix = GradientBoosting.binary_probabilities(raw)
          positive_probs = []
          residuals = []
          i = 0
          while i < rows.size
            p = matrix[i][1]
            positive_probs.push(p)
            residuals.push(targets[i] - p)
            i += 1
          tree = GradientBoosting.fit_tree(rows, residuals, weights, @max_depth, @min_samples_leaf)
          ok = false if tree == nil
          if ok
            GradientBoosting.newton_leaves(tree, rows, targets, positive_probs, weights, 1)
            updates = GradientBoosting.tree_predictions(tree, rows)
            i = 0
            while i < raw.size
              raw[i] += @learning_rate.to_f * updates[i]
              i += 1
            trees.push(tree)
            scores.push(Metrics.multiclass_log_loss(
              GradientBoosting.binary_probabilities(raw), labels, classes, weights
            ))
          stage += 1
        @initial_raw = initial if ok
      else
        initial = []
        counts.each -> (count)
          initial.push(Math.log(count / total))
        raw = []
        rows.each -> (row)
          raw.push(GradientBoosting.copy_array(initial))
        factor = (classes.size - 1).to_f / classes.size.to_f
        stage = 0
        while stage < @n_estimators && ok
          probabilities = GradientBoosting.multiclass_probabilities(raw)
          stage_trees = []
          c = 0
          while c < classes.size && ok
            targets = []
            class_probs = []
            residuals = []
            i = 0
            while i < rows.size
              target = 0.to_f
              target = 1.to_f if labels[i] == classes[c]
              p = probabilities[i][c]
              targets.push(target)
              class_probs.push(p)
              residuals.push(target - p)
              i += 1
            tree = GradientBoosting.fit_tree(rows, residuals, weights, @max_depth, @min_samples_leaf)
            ok = false if tree == nil
            if ok
              GradientBoosting.newton_leaves(tree, rows, targets, class_probs, weights, factor)
              updates = GradientBoosting.tree_predictions(tree, rows)
              i = 0
              while i < raw.size
                raw[i][c] += @learning_rate.to_f * updates[i]
                i += 1
              stage_trees.push(tree)
            c += 1
          if ok
            trees.push(stage_trees)
            scores.push(Metrics.multiclass_log_loss(
              GradientBoosting.multiclass_probabilities(raw), labels, classes, weights
            ))
          stage += 1
        @initial_raw = initial if ok
      if ok
        @classes = classes
        @trees = trees
        @train_scores = scores
        @n_features = rows[0].size
        @fitted = true
        out = self
    out

  -> query_rows(x)
    out = nil
    out = GradientBoosting.query_rows(x, @n_features) if @fitted
    out

  # Binary: one raw log-odds value per row. Multiclass: one logit row.
  -> decision_function(x)
    rows = self.query_rows(x)
    out = nil
    if rows != nil
      if @classes.size == 2
        raw = GradientBoosting.constant_array(rows.size, @initial_raw)
        @trees.each -> (tree)
          updates = GradientBoosting.tree_predictions(tree, rows)
          i = 0
          while i < raw.size
            raw[i] += @learning_rate.to_f * updates[i]
            i += 1
        out = raw
      else
        raw = []
        rows.each -> (row)
          raw.push(GradientBoosting.copy_array(@initial_raw))
        @trees.each -> (stage_trees)
          c = 0
          while c < stage_trees.size
            updates = GradientBoosting.tree_predictions(stage_trees[c], rows)
            i = 0
            while i < raw.size
              raw[i][c] += @learning_rate.to_f * updates[i]
              i += 1
            c += 1
        out = raw
    out

  # Raw scores after every boosting stage. Binary elements are flat logit
  # vectors; multiclass elements are row/class logit matrices.
  -> staged_decision_function(x)
    rows = self.query_rows(x)
    out = nil
    if rows != nil
      stages = []
      if @classes.size == 2
        raw = GradientBoosting.constant_array(rows.size, @initial_raw)
        @trees.each -> (tree)
          updates = GradientBoosting.tree_predictions(tree, rows)
          i = 0
          while i < raw.size
            raw[i] += @learning_rate.to_f * updates[i]
            i += 1
          stages.push(GradientBoosting.copy_array(raw))
      else
        raw = []
        rows.each -> (row)
          raw.push(GradientBoosting.copy_array(@initial_raw))
        @trees.each -> (stage_trees)
          c = 0
          while c < stage_trees.size
            updates = GradientBoosting.tree_predictions(stage_trees[c], rows)
            i = 0
            while i < raw.size
              raw[i][c] += @learning_rate.to_f * updates[i]
              i += 1
            c += 1
          copied = []
          raw.each -> (logits)
            copied.push(GradientBoosting.copy_array(logits))
          stages.push(copied)
      out = stages
    out

  # Full probability matrix by default; a label requests one flat column.
  -> predict_proba(x, label = nil)
    raw = self.decision_function(x)
    out = nil
    if raw != nil
      probabilities = nil
      if @classes.size == 2
        probabilities = GradientBoosting.binary_probabilities(raw)
      else
        probabilities = GradientBoosting.multiclass_probabilities(raw)
      if label == nil
        out = probabilities
      else
        index = 0 - 1
        c = 0
        while c < @classes.size
          index = c if @classes[c] == label
          c += 1
        if index >= 0
          column = []
          probabilities.each -> (row)
            column.push(row[index])
          out = column
    out

  # Full probability matrices after every stage. As with sklearn's
  # staged_predict_proba, the final matrix equals predict_proba(x).
  -> staged_predict_proba(x)
    raw_stages = self.staged_decision_function(x)
    out = nil
    if raw_stages != nil
      stages = []
      raw_stages.each -> (raw)
        if @classes.size == 2
          stages.push(GradientBoosting.binary_probabilities(raw))
        else
          stages.push(GradientBoosting.multiclass_probabilities(raw))
      out = stages
    out

  -> predict(x)
    probabilities = self.predict_proba(x)
    out = nil
    if probabilities != nil
      preds = []
      probabilities.each -> (row)
        preds.push(@classes[GradientBoosting.argmax(row)])
      out = preds
    out

  -> staged_predict(x)
    probability_stages = self.staged_predict_proba(x)
    out = nil
    if probability_stages != nil
      stages = []
      probability_stages.each -> (probabilities)
        preds = []
        probabilities.each -> (row)
          preds.push(@classes[GradientBoosting.argmax(row)])
        stages.push(preds)
      out = stages
    out

  -> log_loss(x, y, sample_weight = nil)
    probabilities = self.predict_proba(x)
    labels = nil
    labels = Estimator.target_values(y) if y != nil
    Metrics.multiclass_log_loss(probabilities, labels, @classes, sample_weight)

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
    "GradientBoostingClassifier"

  -> to_state
    { n_estimators: @n_estimators, learning_rate: @learning_rate, max_depth: @max_depth, min_samples_leaf: @min_samples_leaf, classes: @classes, initial_raw: @initial_raw, trees: @trees, train_scores: @train_scores, n_features: @n_features }

  -> .load_state(state)
    out = nil
    ok = state != nil
    ok = state[:n_estimators] != nil && state[:learning_rate] != nil if ok
    ok = state[:max_depth] != nil && state[:min_samples_leaf] != nil if ok
    ok = state[:classes] != nil && state[:initial_raw] != nil if ok
    ok = state[:trees] != nil && state[:train_scores] != nil if ok
    ok = state[:n_features] != nil if ok
    if ok
      model = GradientBoostingClassifier.new(
        state[:n_estimators], state[:learning_rate],
        state[:max_depth], state[:min_samples_leaf]
      )
      out = model.restore_state(state)
    out

  -> restore_state(state)
    @classes = state[:classes]
    @initial_raw = state[:initial_raw]
    @trees = state[:trees]
    @train_scores = state[:train_scores]
    @n_features = state[:n_features]
    @fitted = true
    self
