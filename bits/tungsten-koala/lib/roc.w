# RocCurve — ROC (receiver operating characteristic) analysis for a
# binary probabilistic classifier (pure Tungsten, CPU-only). Koala's
# threshold-free evaluation companion to the confusion-matrix metrics:
# where accuracy / precision / recall / f1 judge hard 0/1 predictions at
# a fixed 0.5 cut, ROC-AUC judges the underlying SCORES a model ranks
# rows by — exactly the P(positive) that LogisticRegression#predict_proba
# now produces — across every threshold at once.
#
#     curve = Metrics.roc_curve(scores, actual)   # a RocCurve, or nil
#     curve.fpr          # false-positive rate at each curve point
#     curve.tpr          # true-positive rate  at each curve point
#     curve.thresholds   # the score cut for each point (descending)
#     curve.auc          # area under the curve — 1 perfect, 0.5 random
#
#     Metrics.roc_auc(scores, actual)   # the .auc scalar directly, or nil
#     Metrics.auc(x, y)                 # trapezoidal area under any curve
#
# scores[i] is the model's P(row i is positive) and actual[i] the true
# label; pos_label names the positive class (default 1, matching
# Metrics.precision / recall / f1). For a LogisticRegression whose
# classes are [c0, c1], pass scores = model.predict_proba(x) and
# pos_label = c1 (the label predict_proba scores), so ROC-AUC measures
# how well the fitted probabilities rank c1 rows above c0 rows.
#
# The curve is the FULL step curve — one point per distinct score value
# plus a leading "reject-all" point at (0, 0) (scikit-learn's
# drop_intermediate=False): thresholds are the distinct scores in
# descending order, tpr / fpr accumulate the positives / negatives at or
# above each cut, and the leading threshold is max(score) + 1 (the cut
# above which nothing is positive — the pre-1.3 scikit-learn convention;
# koala emits no float infinity). The AUC is the trapezoidal integral of
# tpr over fpr, which equals the Mann-Whitney U statistic exactly,
# including the 0.5 credit a tied score gives — so a block of tied scores
# contributes a diagonal segment and AUC stays correct under ties.
#
# nil (from Metrics.roc_curve / roc_auc) when scores and actual are
# misaligned or empty, or when one class is absent — a single class makes
# TPR or FPR undefined (no positives or no negatives to normalize by),
# scikit-learn's error case, rendered as koala's return-nil convention.
#
# NOTE: the koala conventions — every float derives from data via .to_f
# (a float literal corrupts call arguments on both engines), methods
# holding a closure take no early `return`, and outer locals accumulate
# inside `.each` / `.times` blocks the way Stats / LogisticRegression do.
+ RocCurve
  ro :fpr          # false-positive rate per curve point (0..1, ascending)
  ro :tpr          # true-positive rate per curve point (0..1, ascending)
  ro :thresholds   # score cut per point, descending (leading = reject-all)
  ro :auc          # area under the curve (float)

  # Plain field setter — RocCurve.from builds the arrays and validates;
  # this only stores an already-consistent curve.
  -> new(fpr, tpr, thresholds, auc)
    @fpr = fpr
    @tpr = tpr
    @thresholds = thresholds
    @auc = auc

  # The distinct values of scores as floats, sorted DESCENDING (stable
  # insertion sort — Array#sort is not portable across engines, the Stats
  # convention). These are the ROC thresholds, high score first.
  -> .distinct_desc(scores)
    distinct = []
    scores.each -> (s)
      v = s.to_f
      distinct.push(v) if !distinct.include?(v)
    out = []
    distinct.each -> (v)
      inserted = false
      next_out = []
      out.each -> (u)
        if !inserted && v > u
          next_out.push(v)
          inserted = true
        next_out.push(u)
      next_out.push(v) if !inserted
      out = next_out
    out

  # Largest score as a float.
  -> .max_f(scores)
    m = scores[0].to_f
    scores.each -> (s)
      m = s.to_f if s.to_f > m
    m

  # Trapezoidal area under the curve through (x[i], y[i]) in point order:
  # sum of 0.5 * (x[i] - x[i-1]) * (y[i] + y[i-1]). scikit-learn's
  # metrics.auc. roc_auc = auc(fpr, tpr).
  -> .trapezoid(x, y)
    area = 0.to_f
    n = x.size
    n.times -> (i)
      if i > 0
        dx = x[i].to_f - x[i - 1].to_f
        avg = (y[i].to_f + y[i - 1].to_f) / 2.to_f
        area += dx * avg
    area

  # Build a RocCurve from scores / actual / pos_label, or nil when the
  # inputs are unusable (misaligned, empty, or one class absent).
  -> .from(scores, actual, pos_label)
    ok = scores != nil && actual != nil
    ok = scores.size == actual.size && scores.size > 0 if ok
    npos = 0
    nneg = 0
    if ok
      actual.each -> (a)
        if a == pos_label
          npos += 1
        else
          nneg += 1
      ok = npos > 0 && nneg > 0
    out = nil
    if ok
      thresholds = RocCurve.distinct_desc(scores)
      tps = [0]
      fps = [0]
      thresholds.each -> (t)
        tp = 0
        fp = 0
        i = 0
        scores.each -> (s)
          if s.to_f >= t
            if actual[i] == pos_label
              tp += 1
            else
              fp += 1
          i += 1
        tps.push(tp)
        fps.push(fp)
      npf = npos.to_f
      nnf = nneg.to_f
      fpr = []
      fps.each -> (f)
        fpr.push(f.to_f / nnf)
      tpr = []
      tps.each -> (tp)
        tpr.push(tp.to_f / npf)
      lead = RocCurve.max_f(scores) + 1.to_f
      full_thresholds = [lead]
      thresholds.each -> (t)
        full_thresholds.push(t)
      auc = RocCurve.trapezoid(fpr, tpr)
      out = RocCurve.new(fpr, tpr, full_thresholds, auc)
    out
