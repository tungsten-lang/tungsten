# KNeighborsRegressor — k-nearest-neighbors regression (pure Tungsten,
# CPU-only). Lazy learner: fit stores rows; predict averages the k nearest
# training targets (or inverse-distance weighted average when
# weights: :distance).
#
#     model = KNeighborsRegressor.new          # k = 5, :uniform
#     model = KNeighborsRegressor.new(3, :distance)
#     model.fit(x, y)
#     model.predict(x_test)
#     model.score(x_test, y_test)              # R²
#
# Neighbour ordering uses squared Euclidean distance (same as
# KNNClassifier), while :distance weights use inverse EUCLIDEAN distance,
# matching sklearn. Ties break to lower training index. sample_weight is
# refused on fit; score still accepts weights for Metrics.r2.
#
# NOTE: floats derive via .to_f — a bare decimal literal is a Decimal and
# does not coerce with Float.

+ KNeighborsRegressor
  is Estimable
  is SupervisedEstimator

  ro :k
  ro :weight_kind   # :uniform or :distance

  -> new(k = 5, weight_kind = :uniform)
    @k = k
    @weight_kind = weight_kind
    @fitted = false
    @train_rows = nil
    @train_targets = nil

  -> fitted?
    @fitted

  -> estimator_name
    "KNeighborsRegressor"

  -> supervised?
    true

  -> supports_sample_weight?
    false

  -> params
    { k: @k, weight_kind: @weight_kind }

  -> with_params(overrides)
    KNeighborsRegressor.new(Estimator.opt(overrides, :k, @k), Estimator.opt(overrides, :weight_kind, @weight_kind))

  -> fit(x, y, sample_weight = nil)
    @fitted = false
    @train_rows = nil
    @train_targets = nil
    rows = Estimator.feature_rows(x)
    targets = Estimator.target_values(y)
    ok = rows != nil && targets != nil
    ok = rows.size > 0 && rows.size == targets.size if ok
    ok = KNNClassifier.numeric_rows?(rows) if ok
    ok = Stats.numeric?(targets) if ok
    if ok
      targets.each -> (target)
        ok = false if target == nil
    ok = type(@k) == "Int" if ok
    ok = @k > 0 if ok
    ok = false if sample_weight != nil
    kind = @weight_kind
    ok = false if kind != :uniform && kind != :distance
    out = nil
    if ok
      @train_rows = rows
      @train_targets = targets
      @fitted = true
      out = self
    out

  -> .sq_dist(a, b)
    total = 0.to_f
    n = a.size
    n.times -> (i)
      d = a[i].to_f - b[i].to_f
      total += d * d
    total

  # Mean (or inverse-distance-weighted mean) of the k nearest targets.
  -> predict_one(row)
    trows = @train_rows
    tvals = @train_targets
    kind = @weight_kind
    limit = @k
    limit = trows.size if trows.size < @k
    dists = []
    trows.each -> (tr)
      dists.push(KNeighborsRegressor.sq_dist(row, tr))
    used = []
    trows.each -> (tr)
      used.push(false)
    chosen_d = []
    chosen_y = []
    limit.times -> (c)
      best = -1
      bestv = 0.to_f
      i = 0
      dists.each -> (d)
        if !used[i]
          if best == -1
            best = i
            bestv = d
          else
            if d < bestv
              best = i
              bestv = d
        i += 1
      used[best] = true
      chosen_d.push(bestv)
      chosen_y.push(tvals[best].to_f)
    out = 0.to_f
    if kind == :distance
      # Exact matches exclude non-zero neighbours. Multiple exact matches
      # receive equal weight (sklearn), rather than arbitrarily taking one.
      zero_count = 0
      zero_total = 0.to_f
      i = 0
      chosen_d.each -> (d)
        if d == 0.to_f
          zero_count += 1
          zero_total += chosen_y[i]
        i += 1
      if zero_count > 0
        out = zero_total / zero_count.to_f
      else
        wsum = 0.to_f
        num = 0.to_f
        i = 0
        chosen_d.each -> (d)
          w = 1.to_f / Math.sqrt(d)
          num += w * chosen_y[i]
          wsum += w
          i += 1
        out = num / wsum if wsum > 0.to_f
    else
      sum = 0.to_f
      chosen_y.each -> (y)
        sum += y
      out = sum / chosen_y.size.to_f
    out

  -> predict(x)
    out = nil
    if @fitted
      rows = Estimator.feature_rows(x)
      if rows != nil && KNNClassifier.numeric_rows?(rows, true)
        width = @train_rows[0].size
        ok = true
        rows.each -> (r)
          ok = false if r.size != width
        if ok
          preds = []
          rows.each -> (r)
            preds.push(self.predict_one(r))
          out = preds
    out

  -> score(x, y, sample_weight = nil)
    out = nil
    if @fitted
      preds = self.predict(x)
      actual = Estimator.target_values(y)
      out = Metrics.r2(preds, actual, sample_weight) if preds != nil && actual != nil
    out

  -> persist_name
    "KNeighborsRegressor"

  -> to_state
    { k: @k, weight_kind: @weight_kind, train_rows: @train_rows, train_targets: @train_targets }

  -> .load_state(st)
    out = nil
    ok = st != nil && type(st) == "Hash"
    ok = st[:k] != nil && st[:weight_kind] != nil if ok
    ok = st[:train_rows] != nil && st[:train_targets] != nil if ok
    ok = type(st[:k]) == "Int" && st[:k] > 0 if ok
    ok = st[:weight_kind] == :uniform || st[:weight_kind] == :distance if ok
    ok = KNNClassifier.numeric_rows?(st[:train_rows]) if ok
    ok = type(st[:train_targets]) == "Array" && Stats.numeric?(st[:train_targets]) if ok
    ok = st[:train_rows].size == st[:train_targets].size if ok
    if ok
      st[:train_targets].each -> (target)
        ok = false if target == nil
    if ok
      model = KNeighborsRegressor.new(st[:k], st[:weight_kind])
      out = model.restore_state(st)
    out

  -> restore_state(st)
    @train_rows = st[:train_rows]
    @train_targets = st[:train_targets]
    @fitted = true
    self
