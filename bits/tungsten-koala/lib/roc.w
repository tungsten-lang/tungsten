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
# (a bare decimal literal is a Decimal and does not coerce with Float),
# and outer locals accumulate inside `.each` / `.times` blocks the way
# Stats / LogisticRegression do.
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

# PrecisionRecallCurve — the precision-recall curve and its area
# (average precision), RocCurve's companion for IMBALANCED data
# (scikit-learn's precision_recall_curve / average_precision_score).
#
#     c = Metrics.precision_recall_curve(scores, actual)   # or nil
#     c.precision            # precision at each point
#     c.recall               # recall at each point, 1 down to 0
#     c.thresholds           # the score cut per point, ASCENDING
#     c.average_precision    # the area — a step sum, not a trapezoid
#
#     Metrics.average_precision(scores, actual)   # the scalar directly
#
# Both curves are built from the same tp / fp counts at every distinct
# score, but they normalize the false positives differently, and that is
# the whole point. ROC plots TPR against FPR = FP / all negatives, so a
# large negative class DILUTES the false positives; the PR curve plots
# precision = TP / (TP + FP) against recall, normalizing by what the
# model actually flagged, which does not shrink as negatives are added.
# On a 1%-positive problem a model can hold a ROC-AUC near 0.9 while its
# precision is a few percent — the PR curve shows that, the ROC curve
# hides it.
#
# LAYOUT follows scikit-learn exactly, which is NOT RocCurve's layout:
# points run in ASCENDING threshold order (so recall descends from 1 to
# 0), and a closing (recall 0, precision 1) point is appended for which
# there is no threshold — .precision and .recall are therefore ONE
# LONGER than .thresholds. RocCurve, by contrast, runs in descending
# threshold order with a leading reject-all point and all three arrays
# the same length.
#
# The area is scikit-learn's average_precision_score, the STEP sum
# sum_n (R_n - R_n-1) * P_n rather than a trapezoidal integral — the
# trapezoid would interpolate linearly between operating points, which
# is optimistic on a PR curve because the segment between two thresholds
# is not achievable. Its baseline is the POSITIVE RATE (a random ranker
# scores about n_pos / n), not roc_auc's 0.5.
#
# nil only when scores and actual are misaligned or empty — unlike
# RocCurve, a single present class still yields a curve, matching
# scikit-learn: with no positives every precision is 0 and recall is
# pinned at 1, with no negatives precision is 1 throughout.
+ PrecisionRecallCurve
  ro :precision            # precision per point (thresholds ascending)
  ro :recall               # recall per point, descending from 1 to 0
  ro :thresholds           # score cut per point, ascending; one shorter
  ro :average_precision    # area under the curve (float)

  # Plain field setter — PrecisionRecallCurve.from builds and validates.
  -> new(precision, recall, thresholds, average_precision)
    @precision = precision
    @recall = recall
    @thresholds = thresholds
    @average_precision = average_precision

  # Build from scores / actual / pos_label, or nil when the inputs are
  # unusable (misaligned or empty).
  -> .from(scores, actual, pos_label)
    ok = scores != nil && actual != nil
    ok = scores.size == actual.size && scores.size > 0 if ok
    out = nil
    if ok
      npos = 0
      actual.each -> (a)
        npos += 1 if a == pos_label
      npf = npos.to_f
      # Walk the distinct scores from the strictest cut down, counting
      # the tp / fp admitted at each — the same sweep RocCurve.from makes.
      desc = RocCurve.distinct_desc(scores)
      prec_desc = []
      rec_desc = []
      desc.each -> (t)
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
        p = 0.to_f
        p = tp.to_f / (tp + fp).to_f if (tp + fp) > 0
        # With no positives at all, recall is pinned at 1 rather than
        # 0/0 — scikit-learn's convention.
        r = 1.to_f
        r = tp.to_f / npf if npos > 0
        prec_desc.push(p)
        rec_desc.push(r)
      # Reverse into ascending-threshold order (Array#reverse is not a
      # portable assumption here — index the array directly), then close
      # the curve at (recall 0, precision 1), which has no threshold.
      precision = []
      recall = []
      thresholds = []
      n = desc.size
      n.times -> (j)
        k = n - 1 - j
        precision.push(prec_desc[k])
        recall.push(rec_desc[k])
        thresholds.push(desc[k])
      precision.push(1.to_f)
      recall.push(0.to_f)
      # AP = sum (R_n - R_n+1) * P_n over the curve as laid out above,
      # scikit-learn's -sum(diff(recall) * precision[:-1]).
      ap = 0.to_f
      m = recall.size
      m.times -> (j)
        ap += (recall[j] - recall[j + 1]) * precision[j] if j < m - 1
      out = PrecisionRecallCurve.new(precision, recall, thresholds, ap)
    out
