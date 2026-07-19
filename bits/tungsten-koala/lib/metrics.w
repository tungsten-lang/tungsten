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
