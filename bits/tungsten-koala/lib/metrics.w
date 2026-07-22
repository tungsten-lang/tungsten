# Metrics — model evaluation metrics (plain arrays in, scalars out)
#
#     Metrics.accuracy(predictions, actual)
#     Metrics.rmse(predictions, actual)
#     Metrics.r2(predictions, actual)
#
# ARGUMENT ORDER. Metrics that judge HARD LABELS take predictions first —
# accuracy / precision / recall / f1 / fbeta / balanced_accuracy /
# matthews_corrcoef / cohen_kappa / confusion_matrix /
# classification_report, and the whole regression family. Metrics that
# judge a probabilistic classifier's SCORES take scores first —
# roc_curve / roc_auc / precision_recall_curve / average_precision /
# log_loss / brier_score. Both families end with an optional pos_label
# (default 1) naming the positive class. This is koala's order throughout;
# scikit-learn's is (y_true, y_pred), so the two arrays swap when porting
# a reference call.
+ Metrics
  # Are two arrays a usable metric input — both present, the same length,
  # and non-empty? The guard behind koala's return-nil convention: a
  # metric never raises on a misaligned or empty pair, it answers nil.
  -> .aligned?(a, b)
    ok = a != nil && b != nil
    ok = a.size == b.size && a.size > 0 if ok
    ok

  # --- Classification ---

  # Accuracy: fraction of correct predictions.
  #
  # With `sample_weight` it is the WEIGHTED fraction —
  # sum(w_i * [pred_i == actual_i]) / sum(w) — scikit-learn's
  # accuracy_score(..., sample_weight=w). This is what makes
  # `model.score(x, y, w)` mean anything: an integer weight vector scores
  # exactly as the row-duplicated dataset would, and all-1s reproduces the
  # unweighted number. nil (never a raise) for an unusable weight vector,
  # by Estimator.weight_values' rules.
  -> .accuracy(predictions, actual, sample_weight = nil)
    out = nil
    if sample_weight == nil
      correct = 0
      i = 0
      predictions.each -> (p)
        correct += 1 if p == actual[i]
        i += 1
      out = correct.to_f / predictions.size.to_f
    else
      wts = Estimator.weight_values(sample_weight, predictions.size)
      if wts != nil
        hit = 0.to_f
        total = 0.to_f
        i = 0
        predictions.each -> (p)
          hit += wts[i] if p == actual[i]
          total += wts[i]
          i += 1
        out = hit / total
    out

  # Precision for a binary classifier: of the rows predicted positive,
  # the fraction that are truly positive — TP / (TP + FP). pos_label
  # names the positive class (default 1). 0.0 when nothing is predicted
  # positive, matching scikit-learn's zero-division convention.
  # With `sample_weight` every cell of the confusion count becomes a sum
  # of weights instead of a count of rows — scikit-learn's
  # precision_score(..., sample_weight=w). Imbalance is the whole reason
  # weights exist, and precision / recall are the metrics imbalance is
  # judged by, so they take them too.
  -> .precision(predictions, actual, pos_label = 1, sample_weight = nil)
    out = nil
    if sample_weight == nil
      tp = 0
      fp = 0
      i = 0
      predictions.each -> (p)
        if p == pos_label
          tp += 1 if actual[i] == pos_label
          fp += 1 if actual[i] != pos_label
        i += 1
      out = 0.to_f
      out = tp.to_f / (tp + fp).to_f if (tp + fp) > 0
    else
      wts = Estimator.weight_values(sample_weight, predictions.size)
      if wts != nil
        tpw = 0.to_f
        fpw = 0.to_f
        i = 0
        predictions.each -> (p)
          if p == pos_label
            tpw += wts[i] if actual[i] == pos_label
            fpw += wts[i] if actual[i] != pos_label
          i += 1
        out = 0.to_f
        out = tpw / (tpw + fpw) if (tpw + fpw) > 0.to_f
    out

  # Recall (sensitivity) for a binary classifier: of the truly positive
  # rows, the fraction the model caught — TP / (TP + FN). 0.0 when there
  # are no actual positives.
  -> .recall(predictions, actual, pos_label = 1, sample_weight = nil)
    out = nil
    if sample_weight == nil
      tp = 0
      fneg = 0
      i = 0
      actual.each -> (a)
        if a == pos_label
          tp += 1 if predictions[i] == pos_label
          fneg += 1 if predictions[i] != pos_label
        i += 1
      out = 0.to_f
      out = tp.to_f / (tp + fneg).to_f if (tp + fneg) > 0
    else
      wts = Estimator.weight_values(sample_weight, predictions.size)
      if wts != nil
        tpw = 0.to_f
        fnw = 0.to_f
        i = 0
        actual.each -> (a)
          if a == pos_label
            tpw += wts[i] if predictions[i] == pos_label
            fnw += wts[i] if predictions[i] != pos_label
          i += 1
        out = 0.to_f
        out = tpw / (tpw + fnw) if (tpw + fnw) > 0.to_f
    out

  # F1 score: the harmonic mean of precision and recall,
  # 2 * P * R / (P + R). 0.0 when both are 0.
  -> .f1(predictions, actual, pos_label = 1, sample_weight = nil)
    p = self.precision(predictions, actual, pos_label, sample_weight)
    r = self.recall(predictions, actual, pos_label, sample_weight)
    out = nil
    if p != nil && r != nil
      out = 0.to_f
      out = 2.to_f * p * r / (p + r) if (p + r) > 0
    out

  # F-beta score — scikit-learn's fbeta_score, the WEIGHTED harmonic mean
  # of precision and recall that f1 is the beta = 1 case of:
  #
  #     F_beta = (1 + beta^2) * P * R / (beta^2 * P + R)
  #
  # beta is how many times as much a unit of recall is worth as a unit of
  # precision. beta = 2 (recall-leaning) is the standard choice when a
  # MISSED positive costs more than a false alarm — fraud, disease
  # screening, defect detection; beta = 1/2 (precision-leaning) when the
  # false alarm is the expensive one — spam quarantine, auto-blocking.
  # beta = 0 collapses to precision exactly, and F_beta rises toward
  # recall as beta grows, so one knob sweeps the whole precision/recall
  # trade-off that f1 fixes at the midpoint. 0.0 when beta^2*P + R is 0,
  # scikit-learn's zero-division convention.
  #
  # Predictions first, like precision / recall / f1. Pass beta as an
  # INTEGER or a derived Float (2, or 1.to_f / 2.to_f) — a bare decimal
  # literal is a Decimal and does not coerce with Float.
  -> .fbeta(predictions, actual, beta = 1, pos_label = 1, sample_weight = nil)
    p = self.precision(predictions, actual, pos_label, sample_weight)
    r = self.recall(predictions, actual, pos_label, sample_weight)
    out = nil
    if p != nil && r != nil
      b2 = beta.to_f * beta.to_f
      denom = b2 * p + r
      out = 0.to_f
      out = (1.to_f + b2) * p * r / denom if denom > 0
    out

  # --- Regression ---

  # Mean squared error. With `sample_weight`, sum(w*d^2) / sum(w) —
  # scikit-learn's mean_squared_error(..., sample_weight=w). nil for an
  # unusable weight vector.
  -> .mse(predictions, actual, sample_weight = nil)
    out = nil
    if sample_weight == nil
      total = 0.to_f
      i = 0
      predictions.each -> (p)
        d = p.to_f - actual[i].to_f
        total += d * d
        i += 1
      out = total / predictions.size.to_f
    else
      wts = Estimator.weight_values(sample_weight, predictions.size)
      if wts != nil
        total = 0.to_f
        sw = 0.to_f
        i = 0
        predictions.each -> (p)
          d = p.to_f - actual[i].to_f
          total += d * d * wts[i]
          sw += wts[i]
          i += 1
        out = total / sw
    out

  # Root mean squared error (weighted when sample_weight is given).
  -> .rmse(predictions, actual, sample_weight = nil)
    m = self.mse(predictions, actual, sample_weight)
    out = nil
    out = Math.sqrt(m) if m != nil
    out

  # Mean absolute error. With `sample_weight`, sum(w*|d|) / sum(w).
  -> .mae(predictions, actual, sample_weight = nil)
    out = nil
    if sample_weight == nil
      total = 0.to_f
      i = 0
      predictions.each -> (p)
        d = p.to_f - actual[i].to_f
        d = 0.to_f - d if d < 0
        total += d
        i += 1
      out = total / predictions.size.to_f
    else
      wts = Estimator.weight_values(sample_weight, predictions.size)
      if wts != nil
        total = 0.to_f
        sw = 0.to_f
        i = 0
        predictions.each -> (p)
          d = p.to_f - actual[i].to_f
          d = 0.to_f - d if d < 0
          total += d * wts[i]
          sw += wts[i]
          i += 1
        out = total / sw
    out

  # Median absolute error — the median of the absolute residuals,
  # scikit-learn's median_absolute_error. The mean/median/max of the
  # absolute-residual distribution are mae / median_absolute_error /
  # max_error respectively; the median is the robust one, unmoved by a
  # single large residual, so it reports typical error where mae is
  # dragged up by outliers.
  -> .median_absolute_error(predictions, actual)
    resid = []
    i = 0
    predictions.each -> (p)
      d = p.to_f - actual[i].to_f
      d = 0.to_f - d if d < 0
      resid.push(d)
      i += 1
    Stats.median(resid)

  # Max error — the largest absolute residual, scikit-learn's max_error:
  # the worst single-point miss, a hard upper bound on prediction error.
  # Always >= 0; 0 exactly when every prediction is exact.
  -> .max_error(predictions, actual)
    worst = 0.to_f
    i = 0
    predictions.each -> (p)
      d = p.to_f - actual[i].to_f
      d = 0.to_f - d if d < 0
      worst = d if d > worst
      i += 1
    worst

  # Mean absolute percentage error (MAPE) — scikit-learn's
  # mean_absolute_percentage_error: the mean of |actual - pred| / |actual|,
  # a scale-free RELATIVE error (a fraction, not a percent; multiply by 100
  # for a percentage). Each actual is guarded by a small eps = 1e-15 so a
  # zero target does not divide by zero — the term explodes instead,
  # matching scikit-learn (which guards with machine epsilon), so MAPE is
  # only meaningful when the targets stay away from zero. Where mse / mae
  # weight absolute error, MAPE weights error relative to the target's
  # magnitude, so a miss of 1 on a target of 2 counts far more than the
  # same miss on a target of 100.
  -> .mape(predictions, actual)
    kilo = 1000.to_f
    eps = 1.to_f / (kilo * kilo * kilo * kilo * kilo)
    total = 0.to_f
    i = 0
    predictions.each -> (p)
      denom = actual[i].to_f
      denom = 0.to_f - denom if denom < 0
      denom = eps if denom < eps
      d = p.to_f - actual[i].to_f
      d = 0.to_f - d if d < 0
      total += d / denom
      i += 1
    total / predictions.size.to_f

  # Explained variance score — scikit-learn's explained_variance_score:
  #
  #     1 - Var(actual - pred) / Var(actual)
  #
  # r2's mean-corrected sibling. Where r2 divides the raw residual sum of
  # squares by the total, explained variance divides the residual VARIANCE
  # (which subtracts the mean residual first) by the target variance, so it
  # ignores a constant bias in the predictions: the two are equal exactly
  # when the mean residual is zero, and explained variance exceeds r2 when a
  # systematic offset inflates r2's residual term. 1 is perfect. When the
  # target is constant (Var(actual) = 0) the score is 1 if the residual
  # variance is also 0, else 0 — scikit-learn's convention.
  -> .explained_variance(predictions, actual)
    resid = []
    i = 0
    predictions.each -> (p)
      resid.push(actual[i].to_f - p.to_f)
      i += 1
    numer = Stats.var(resid)
    denom = Stats.var(actual)
    out = 1.to_f
    if denom == 0
      out = 0.to_f if numer != 0
    else
      out = 1.to_f - numer / denom
    out

  # --- Multiclass / report (see classification.w) ---

  # Confusion matrix as a ConfusionMatrix: .matrix[i][j] counts rows with
  # actual == labels[i] and predicted == labels[j]; .labels lists classes
  # in first-seen order (actual, then predictions). .count(actual, pred)
  # and .to_df read it back. Generalizes accuracy/precision/recall/f1 to
  # any number of classes.
  -> .confusion_matrix(predictions, actual)
    ConfusionMatrix.new(predictions, actual)

  # --- Imbalanced-data scores (confusion-matrix derived; see classification.w) ---
  #
  # Accuracy lies on skewed data: a classifier that always answers the
  # majority class scores 0.8 on a 4:1 split while learning nothing. The
  # three metrics below all report that failure honestly — balanced
  # accuracy 0.5, MCC 0, kappa 0 — each from a different angle: balanced
  # accuracy re-weights the classes to equal size, MCC correlates the two
  # label vectors, kappa discounts the agreement chance alone would give.
  # All take PREDICTIONS first (the accuracy / precision / f1 order) and
  # work for any number of classes. nil for a misaligned or empty pair.

  # Balanced accuracy — the unweighted mean of the per-class recalls
  # (macro recall), scikit-learn's balanced_accuracy_score. Every class
  # contributes equally no matter how rare it is, so the majority-class
  # classifier lands on 1/n_classes (0.5 for binary — the chance level)
  # instead of accuracy's flattering majority fraction. 1 is perfect.
  # Classes that appear only among the PREDICTIONS have no recall to
  # average and are skipped, matching scikit-learn (which averages over
  # the classes present in the true labels).
  -> .balanced_accuracy(predictions, actual)
    out = nil
    if self.aligned?(predictions, actual)
      cm = ConfusionMatrix.new(predictions, actual)
      out = cm.balanced_accuracy
    out

  # Matthews correlation coefficient (MCC) — scikit-learn's
  # matthews_corrcoef: the Pearson correlation between the predicted and
  # the true labels, in [-1, 1]. 1 is perfect, 0 is chance, -1 is
  # perfectly inverted. MCC is the metric of choice for IMBALANCED binary
  # problems because it is the only common score that stays low unless
  # ALL FOUR confusion cells are good — TP, TN, FP and FN all enter the
  # formula symmetrically, so, unlike f1 (which ignores TN entirely), it
  # cannot be inflated by a huge majority class or by predicting one
  # class always. 0.0 when a whole row or column of the matrix is empty
  # (a constant classifier, or a single class present), where the
  # correlation is undefined — scikit-learn's convention.
  -> .matthews_corrcoef(predictions, actual)
    out = nil
    if self.aligned?(predictions, actual)
      cm = ConfusionMatrix.new(predictions, actual)
      out = cm.matthews_corrcoef
    out

  # Cohen's kappa — scikit-learn's cohen_kappa_score: agreement between
  # the predictions and the truth CORRECTED for the agreement two
  # independent labelers would reach by chance,
  #
  #     kappa = (p_observed - p_expected) / (1 - p_expected)
  #
  # where p_observed is the accuracy and p_expected is the accuracy the
  # same two label DISTRIBUTIONS would produce if they were independent.
  # 1 is perfect, 0 is chance-level (accuracy exactly as good as guessing
  # with the right class frequencies), negative is worse than chance.
  # Where balanced accuracy re-weights the classes and MCC correlates
  # them, kappa answers "how much of this accuracy did the model actually
  # earn?". 0.0 when p_expected is 1 (only one class present on both
  # sides), where scikit-learn yields nan — koala never emits nan, and 0
  # reads as "no chance-corrected agreement is measurable here", the same
  # convention matthews_corrcoef uses for its degenerate case.
  -> .cohen_kappa(predictions, actual)
    out = nil
    if self.aligned?(predictions, actual)
      cm = ConfusionMatrix.new(predictions, actual)
      out = cm.cohen_kappa
    out

  # --- ROC analysis (probabilistic classifier scores; see roc.w) ---

  # ROC curve as a RocCurve: .fpr / .tpr arrays (one point per distinct
  # score plus a leading reject-all point at the origin), .thresholds
  # (descending score cuts) and .auc. scores are the model's P(positive)
  # — e.g. LogisticRegression#predict_proba — and actual the true labels;
  # pos_label names the positive class (default 1, matching precision /
  # recall / f1). nil when the arrays are misaligned or empty, or when one
  # class is absent (TPR / FPR undefined). Full curve, no intermediate
  # points dropped, so integrating it gives the exact AUC.
  -> .roc_curve(scores, actual, pos_label = 1)
    RocCurve.from(scores, actual, pos_label)

  # ROC AUC: the area under the ROC curve, a probabilistic classifier's
  # threshold-free ranking quality — the probability it scores a random
  # positive above a random negative (ties count half). 1 is perfect, 0.5
  # random, 0 perfectly inverted. nil under the same conditions as
  # roc_curve.
  -> .roc_auc(scores, actual, pos_label = 1)
    curve = RocCurve.from(scores, actual, pos_label)
    out = nil
    out = curve.auc if curve != nil
    out

  # Trapezoidal area under a curve given its x and y point arrays
  # (scikit-learn's metrics.auc), integrated in point order:
  # roc_auc = auc(curve.fpr, curve.tpr).
  -> .auc(x, y)
    RocCurve.trapezoid(x, y)

  # Log loss — binary cross-entropy, the mean negative log-likelihood a
  # probabilistic classifier assigns the true labels. This is the EXACT
  # objective LogisticRegression minimizes, and scikit-learn's log_loss:
  #
  #     L = -mean( y*ln(p) + (1 - y)*ln(1 - p) )
  #
  # where scores[i] = p is the model's P(row i is positive) — e.g.
  # LogisticRegression#predict_proba — y is 1 when actual[i] == pos_label
  # else 0, and pos_label names the positive class (default 1, matching
  # precision / recall / f1 / roc_auc). Lower is better: 0 is a perfectly
  # confident classifier, ln 2 ≈ 0.693147 a coin flip, and it grows without
  # bound as confidence in a wrong label rises. It complements roc_auc —
  # AUC judges only the RANKING of the scores, log loss judges their
  # CALIBRATION (how close each probability is to the outcome), so a model
  # can rank perfectly (AUC 1) yet carry a large log loss from
  # under-confident probabilities. Probabilities are clipped to
  # [eps, 1 - eps] (eps = 1e-15, scikit-learn's default) so a fully
  # confident wrong prediction stays finite. Unlike roc_auc, a single class
  # is fine — log loss is defined with no negatives (or no positives) — so
  # nil arises only when scores and actual are misaligned or empty.
  -> .log_loss(scores, actual, pos_label = 1)
    ok = self.aligned?(scores, actual)
    out = nil
    if ok
      kilo = 1000.to_f
      eps = 1.to_f / (kilo * kilo * kilo * kilo * kilo)
      hi = 1.to_f - eps
      total = 0.to_f
      i = 0
      scores.each -> (s)
        p = s.to_f
        p = eps if p < eps
        p = hi if p > hi
        y = 0.to_f
        y = 1.to_f if actual[i] == pos_label
        total += y * Math.log(p) + (1.to_f - y) * Math.log(1.to_f - p)
        i += 1
      out = 0.to_f - total / scores.size.to_f
    out

  # Precision-recall curve as a PrecisionRecallCurve: .precision /
  # .recall arrays (one point per distinct score, plus a closing
  # (recall 0, precision 1) point), .thresholds (ASCENDING score cuts,
  # one shorter than the curve arrays) and .average_precision —
  # scikit-learn's precision_recall_curve, point for point.
  #
  # The PR curve is ROC's companion and the RIGHT curve for imbalanced
  # data. ROC normalizes false positives by the number of NEGATIVES, so a
  # large negative class hides them: a model can flag ten false positives
  # for every true one and still post an impressive ROC-AUC. Precision
  # normalizes by what the model actually FLAGGED, so those same ten cost
  # it directly. When positives are rare — fraud, disease, defects — read
  # this curve, not the ROC one.
  #
  # scores are the model's P(positive) (e.g. LogisticRegression's
  # predict_proba), actual the true labels, pos_label the positive class
  # (default 1) — the roc_curve / log_loss argument order. nil when the
  # arrays are misaligned or empty. Unlike roc_curve, a single present
  # class is FINE: with no positives every precision is 0 and recall is
  # pinned at 1 (scikit-learn's convention), with no negatives precision
  # is 1 throughout.
  -> .precision_recall_curve(scores, actual, pos_label = 1)
    PrecisionRecallCurve.from(scores, actual, pos_label)

  # Average precision (PR-AUC) — the area under the precision-recall
  # curve, scikit-learn's average_precision_score. It is a step sum, NOT
  # a trapezoid:
  #
  #     AP = sum over thresholds of (R_n - R_n-1) * P_n
  #
  # i.e. the precision at each cut weighted by the recall it gained,
  # which is exactly the mean precision over the positives and never
  # interpolates optimistically between operating points the way a
  # trapezoidal PR area does. 1 is perfect; the BASELINE is the positive
  # rate itself (a random ranker scores ~ n_pos/n), not the 0.5 that
  # roc_auc's baseline sits at — so an AP of 0.5 is excellent on a 1%
  # positive class and terrible on a balanced one. Always read it against
  # that rate. nil under the same conditions as precision_recall_curve.
  -> .average_precision(scores, actual, pos_label = 1)
    curve = PrecisionRecallCurve.from(scores, actual, pos_label)
    out = nil
    out = curve.average_precision if curve != nil
    out

  # Brier score — scikit-learn's brier_score_loss: the mean squared error
  # of the predicted probabilities,
  #
  #     B = mean( (p - y)^2 )
  #
  # where scores[i] = p is the model's P(row i is positive) and y is 1
  # when actual[i] == pos_label else 0. Lower is better: 0 is perfect,
  # 0.25 a constant 0.5 coin flip, 1 the worst possible (confident and
  # wrong every time).
  #
  # Like log_loss it measures CALIBRATION rather than ranking — but it is
  # the BOUNDED, gentle sibling. Log loss is unbounded and punishes a
  # confident miss without limit (one p = 0 on a true positive would send
  # it to infinity but for clipping), so a single outlier can dominate
  # it; the Brier score's worst case per row is 1, so it stays readable
  # and comparable across data sets. Reach for log loss when you are
  # optimizing (it is what logistic regression minimizes), the Brier
  # score when you are REPORTING how well the probabilities are
  # calibrated. Scores first, the log_loss / roc_auc order. nil when the
  # arrays are misaligned or empty; a single present class is fine.
  -> .brier_score(scores, actual, pos_label = 1)
    out = nil
    if self.aligned?(scores, actual)
      total = 0.to_f
      i = 0
      scores.each -> (s)
        y = 0.to_f
        y = 1.to_f if actual[i] == pos_label
        d = s.to_f - y
        total += d * d
        i += 1
      out = total / scores.size.to_f
    out

  # A ClassificationReport: per-class precision / recall / f1 / support
  # (each metric one-vs-rest, the binary metrics above per class), plus
  # overall accuracy and macro / support-weighted averages — scikit-learn's
  # classification_report, in koala's (predictions, actual) argument order.
  -> .classification_report(predictions, actual)
    ClassificationReport.new(predictions, actual)

  # R² (coefficient of determination).
  #
  # With `sample_weight` every squared term is weighted AND the baseline
  # is the WEIGHTED mean of `actual` — scikit-learn's
  # r2_score(..., sample_weight=w):
  #
  #     1 - sum(w*(a - p)^2) / sum(w*(a - weighted_mean(a))^2)
  #
  # Weighting the residuals but not the baseline would be the classic
  # wrong answer (it compares against a model the weighted data never
  # proposes), so both move together. 1 when the weighted target variance
  # is 0; nil for an unusable weight vector.
  -> .r2(predictions, actual, sample_weight = nil)
    out = nil
    if sample_weight == nil
      m = Stats.mean(actual)
      ss_res = 0.to_f
      ss_tot = 0.to_f
      i = 0
      actual.each -> (a)
        dr = a.to_f - predictions[i].to_f
        dt = a.to_f - m
        ss_res += dr * dr
        ss_tot += dt * dt
        i += 1
      out = 1.to_f
      out = 1.to_f - ss_res / ss_tot if ss_tot != 0
    else
      wts = Estimator.weight_values(sample_weight, predictions.size)
      if wts != nil
        wm = Estimator.weighted_mean(actual, wts)
        ss_res = 0.to_f
        ss_tot = 0.to_f
        i = 0
        actual.each -> (a)
          dr = a.to_f - predictions[i].to_f
          dt = a.to_f - wm
          ss_res += dr * dr * wts[i]
          ss_tot += dt * dt * wts[i]
          i += 1
        out = 1.to_f
        out = 1.to_f - ss_res / ss_tot if ss_tot != 0
    out

  # --- Clustering (unsupervised; no true labels exist) ---

  # Silhouette score — scikit-learn's silhouette_score: the mean over
  # every row of
  #
  #     s(i) = (b(i) - a(i)) / max(a(i), b(i))
  #
  # where a(i) is the mean Euclidean distance from row i to the OTHER
  # rows of its own cluster (how tight its cluster is) and b(i) is the
  # smallest mean distance from row i to any other cluster (how far the
  # nearest rival is). s(i) is in [-1, 1]: near 1 the row sits deep in a
  # well-separated cluster, near 0 it straddles a boundary, negative it
  # is closer to a different cluster than to its own — it was assigned to
  # the wrong one. Rows alone in their cluster score 0 (scikit-learn's
  # convention: with no neighbors there is no a(i) to compare against).
  #
  # This is koala's first UNSUPERVISED metric, and the answer to the one
  # question KMeans could not previously be asked. KMeans reports
  # `inertia` — the within-cluster sum of squares — but inertia falls
  # monotonically as k rises, so it can rank two fits at the SAME k and
  # nothing more; it can never say whether the clustering is any good, or
  # choose k. The silhouette normalizes cohesion against SEPARATION, so
  # it is comparable across different k and is the standard way to pick
  # one: fit KMeans for k = 2, 3, 4, ... and keep the k with the highest
  # silhouette.
  #
  #     m = KMeans.new(3).fit(x)
  #     Metrics.silhouette_score(x, m.labels)
  #
  # x is the row data — an array of feature-value arrays, or a flat array
  # of numbers for a single feature — and labels the cluster assignment
  # per row (any values: integers, strings, symbols). Data first, then
  # labels, matching scikit-learn. nil when x and labels are misaligned
  # or empty, or when the number of distinct clusters is not in
  # 2 .. n_rows - 1 — one cluster has nothing to separate from and
  # n clusters leaves every row a singleton, so the score is undefined
  # (scikit-learn raises there; koala returns nil).
  -> .silhouette_score(x, labels)
    ok = self.aligned?(x, labels)
    groups = []
    if ok
      labels.each -> (l)
        groups.push(l) if !groups.include?(l)
      ok = groups.size > 1 && groups.size < x.size
    out = nil
    if ok
      n = x.size
      k = groups.size
      rows = []
      x.each -> (r)
        row = r
        row = [r] if type(r) != "Array"
        rows.push(row)
      owns = []
      labels.each -> (l)
        owns.push(ConfusionMatrix.index_of(groups, l))
      total = 0.to_f
      n.times -> (i)
        # sums[g] / counts[g] is the mean distance from row i to cluster g.
        sums = []
        counts = []
        k.times -> (g)
          sums.push(0.to_f)
          counts.push(0)
        n.times -> (j)
          if i != j
            gj = owns[j]
            sums[gj] = sums[gj] + Metrics.euclidean(rows[i], rows[j])
            counts[gj] = counts[gj] + 1
        own = owns[i]
        a = 0.to_f
        a = sums[own] / counts[own].to_f if counts[own] > 0
        b = 0.to_f
        found = false
        k.times -> (g)
          if g != own && counts[g] > 0
            m = sums[g] / counts[g].to_f
            if !found
              b = m
              found = true
            else
              b = m if m < b
        # A singleton cluster (counts[own] == 0) scores 0, not 1.
        s = 0.to_f
        if found && counts[own] > 0
          hi = a
          hi = b if b > a
          s = (b - a) / hi if hi > 0
        total += s
      out = total / n.to_f
    out

  # Euclidean distance between two equal-length feature rows.
  -> .euclidean(p, q)
    total = 0.to_f
    i = 0
    p.each -> (v)
      d = v.to_f - q[i].to_f
      total += d * d
      i += 1
    Math.sqrt(total)
