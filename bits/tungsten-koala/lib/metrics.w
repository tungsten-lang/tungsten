# Metrics — model evaluation metrics (plain arrays in, scalars out)
#
#     Metrics.accuracy(predictions, actual)
#     Metrics.rmse(predictions, actual)
#     Metrics.r2(predictions, actual)
+ Metrics
  # --- Classification ---

  # Accuracy: fraction of correct predictions.
  -> .accuracy(predictions, actual)
    correct = 0
    i = 0
    predictions.each -> (p)
      correct += 1 if p == actual[i]
      i += 1
    correct.to_f / predictions.size.to_f

  # Precision for a binary classifier: of the rows predicted positive,
  # the fraction that are truly positive — TP / (TP + FP). pos_label
  # names the positive class (default 1). 0.0 when nothing is predicted
  # positive, matching scikit-learn's zero-division convention.
  -> .precision(predictions, actual, pos_label = 1)
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
    out

  # Recall (sensitivity) for a binary classifier: of the truly positive
  # rows, the fraction the model caught — TP / (TP + FN). 0.0 when there
  # are no actual positives.
  -> .recall(predictions, actual, pos_label = 1)
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
    out

  # F1 score: the harmonic mean of precision and recall,
  # 2 * P * R / (P + R). 0.0 when both are 0.
  -> .f1(predictions, actual, pos_label = 1)
    p = self.precision(predictions, actual, pos_label)
    r = self.recall(predictions, actual, pos_label)
    out = 0.to_f
    out = 2.to_f * p * r / (p + r) if (p + r) > 0
    out

  # --- Regression ---

  # Mean squared error.
  -> .mse(predictions, actual)
    total = 0.to_f
    i = 0
    predictions.each -> (p)
      d = p.to_f - actual[i].to_f
      total += d * d
      i += 1
    total / predictions.size.to_f

  # Root mean squared error.
  -> .rmse(predictions, actual)
    Math.sqrt(self.mse(predictions, actual))

  # Mean absolute error.
  -> .mae(predictions, actual)
    total = 0.to_f
    i = 0
    predictions.each -> (p)
      d = p.to_f - actual[i].to_f
      d = 0.to_f - d if d < 0
      total += d
      i += 1
    total / predictions.size.to_f

  # --- Multiclass / report (see classification.w) ---

  # Confusion matrix as a ConfusionMatrix: .matrix[i][j] counts rows with
  # actual == labels[i] and predicted == labels[j]; .labels lists classes
  # in first-seen order (actual, then predictions). .count(actual, pred)
  # and .to_df read it back. Generalizes accuracy/precision/recall/f1 to
  # any number of classes.
  -> .confusion_matrix(predictions, actual)
    ConfusionMatrix.new(predictions, actual)

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
    ok = scores != nil && actual != nil
    ok = scores.size == actual.size && scores.size > 0 if ok
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

  # A ClassificationReport: per-class precision / recall / f1 / support
  # (each metric one-vs-rest, the binary metrics above per class), plus
  # overall accuracy and macro / support-weighted averages — scikit-learn's
  # classification_report, in koala's (predictions, actual) argument order.
  -> .classification_report(predictions, actual)
    ClassificationReport.new(predictions, actual)

  # R² (coefficient of determination).
  -> .r2(predictions, actual)
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
    return 1.to_f if ss_tot == 0
    1.to_f - ss_res / ss_tot
