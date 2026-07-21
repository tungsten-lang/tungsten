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
