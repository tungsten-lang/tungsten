# Feature-selection transformers — Tunable fit/transform steps for Pipelines.
#
#     VarianceThreshold.new           # drop zero-variance columns (default 0)
#     VarianceThreshold.new(1.to_f / 10.to_f)
#     SelectKBest.new(2)              # keep k highest |Pearson r| with y
#     SelectKBest.new(2, :f_classif)  # ANOVA-style: between/within class var
#
# Both answer Tunable (params / with_params) and fit/transform like Scaler.
# sample_weight is accepted on fit when computing means/variances for
# VarianceThreshold and for correlation scores.

+ VarianceThreshold
  is Tunable

  ro :threshold

  -> new(threshold = 0)
    @threshold = threshold
    @fitted = false
    @keep_names = []

  -> fitted?
    @fitted

  -> params
    { threshold: @threshold }

  -> with_params(overrides)
    VarianceThreshold.new(Estimator.opt(overrides, :threshold, @threshold))

  -> fit(df, sample_weight = nil)
    frame = Estimator.frame(df)
    n = frame.row_count
    wts = nil
    ok = true
    if sample_weight != nil
      wts = Estimator.weight_values(sample_weight, n)
      ok = false if wts == nil
    out = nil
    if ok
      thr = @threshold.to_f
      keep = []
      frame.column_names.each -> (name)
        values = frame.column_values(name)
        if Stats.numeric?(values)
          s = Estimator.weighted_sample_std(values, wts)
          # sample variance = s^2. sklearn VarianceThreshold removes
          # columns with variance <= threshold.
          v = 0.to_f
          v = s * s if s != nil
          keep.push(name) if v > thr
      @keep_names = keep
      @fitted = true
      out = self
    out

  -> transform(df)
    out = nil
    if @fitted
      frame = Estimator.frame(df)
      keep = @keep_names
      pairs = []
      keep.each -> (name)
        vals = frame.column_values(name)
        pairs.push([name, vals]) if vals != nil
      out = DataFrame.new(pairs)
    out

  -> fit_transform(df, sample_weight = nil)
    self.fit(df, sample_weight)
    self.transform(df)

  -> persist_name
    "VarianceThreshold"

  -> to_state
    { threshold: @threshold, keep_names: @keep_names }

  -> .load_state(st)
    out = nil
    if st != nil && st[:keep_names] != nil
      model = VarianceThreshold.new(st[:threshold])
      out = model.restore_state(st)
    out

  -> restore_state(st)
    @keep_names = st[:keep_names]
    @fitted = true
    self

+ SelectKBest
  is Tunable

  ro :k
  ro :score_func   # :f_regression | :f_classif

  -> new(k = 10, score_func = :f_regression)
    @k = k
    @score_func = score_func
    @fitted = false
    @keep_names = []
    @scores = []

  -> fitted?
    @fitted

  -> params
    { k: @k, score_func: @score_func }

  -> with_params(overrides)
    SelectKBest.new(Estimator.opt(overrides, :k, @k), Estimator.opt(overrides, :score_func, @score_func))

  # Supervised: needs y. fit(df, y) or fit(rows, y) via Estimator.frame.
  # Signature matches transformers that take optional trailing weight:
  # fit(x, y = nil, sample_weight = nil) when used as pipeline step before
  # an estimator — Pipeline currently only passes weights, not y, to
  # intermediate steps. Call fit(x, y) directly for now; Pipeline support
  # for supervised transformers is a follow-up.
  -> fit(df, y = nil, sample_weight = nil)
    frame = Estimator.frame(df)
    targets = Estimator.target_values(y)
    out = nil
    ok = frame != nil && targets != nil && targets.size == frame.row_count
    ok = @k > 0 if ok
    kind = @score_func
    ok = false if kind != :f_regression && kind != :f_classif
    if ok
      names = []
      scores = []
      frame.column_names.each -> (name)
        values = frame.column_values(name)
        if Stats.numeric?(values)
          sc = nil
          sc = SelectKBest.score_regression(values, targets) if kind == :f_regression
          sc = SelectKBest.score_classif(values, targets) if kind == :f_classif
          if sc != nil
            names.push(name)
            scores.push(sc)
      # pick top k by score (strictly better; ties → lower index)
      keep = []
      used = []
      names.each -> (n)
        used.push(false)
      limit = @k
      limit = names.size if names.size < @k
      limit.times -> (c)
        best = -1
        bestv = 0.to_f
        i = 0
        scores.each -> (sc)
          if !used[i]
            if best == -1
              best = i
              bestv = sc
            else
              if sc > bestv
                best = i
                bestv = sc
          i += 1
        used[best] = true
        keep.push(names[best])
      @keep_names = keep
      @scores = scores
      @fitted = true
      out = self
    out

  # |Pearson r| between column and target (nils dropped pairwise).
  -> .score_regression(values, targets)
    xs = []
    ys = []
    i = 0
    values.each -> (v)
      t = targets[i]
      if v != nil && t != nil
        xs.push(v.to_f)
        ys.push(t.to_f)
      i += 1
    out = nil
    if xs.size > 1
      mx = Estimator.weighted_mean(xs, nil)
      my = Estimator.weighted_mean(ys, nil)
      num = 0.to_f
      dx = 0.to_f
      dy = 0.to_f
      i = 0
      xs.each -> (x)
        a = x - mx
        b = ys[i] - my
        num += a * b
        dx += a * a
        dy += b * b
        i += 1
      den = Math.sqrt(dx * dy)
      r = 0.to_f
      r = num / den if den > 0.to_f
      if r < 0.to_f
        r = 0.to_f - r
      out = r
    out

  # Between-class / within-class variance ratio (simple f-classif proxy).
  -> .score_classif(values, targets)
    # group means
    labels = []
    groups = []
    i = 0
    values.each -> (v)
      t = targets[i]
      if v != nil && t != nil
        key = t.to_s
        idx = -1
        j = 0
        labels.each -> (lb)
          idx = j if lb == key
          j += 1
        if idx == -1
          labels.push(key)
          groups.push([])
          idx = labels.size - 1
        groups[idx].push(v.to_f)
      i += 1
    out = nil
    if labels.size > 1
      all = []
      groups.each -> (g)
        g.each -> (x)
          all.push(x)
      if all.size > labels.size
        grand = Estimator.weighted_mean(all, nil)
        bss = 0.to_f
        wss = 0.to_f
        groups.each -> (g)
          m = Estimator.weighted_mean(g, nil)
          n = g.size.to_f
          d = m - grand
          bss += n * d * d
          g.each -> (x)
            e = x - m
            wss += e * e
        out = 0.to_f
        out = bss / wss if wss > 0.to_f
    out

  -> transform(df)
    out = nil
    if @fitted
      frame = Estimator.frame(df)
      pairs = []
      @keep_names.each -> (name)
        vals = frame.column_values(name)
        pairs.push([name, vals]) if vals != nil
      out = DataFrame.new(pairs)
    out

  -> fit_transform(df, y = nil, sample_weight = nil)
    self.fit(df, y, sample_weight)
    self.transform(df)

  -> persist_name
    "SelectKBest"

  -> to_state
    { k: @k, score_func: @score_func, keep_names: @keep_names, scores: @scores }

  -> .load_state(st)
    out = nil
    if st != nil && st[:keep_names] != nil
      model = SelectKBest.new(st[:k], st[:score_func])
      out = model.restore_state(st)
    out

  -> restore_state(st)
    @keep_names = st[:keep_names]
    @scores = st[:scores]
    @fitted = true
    self
